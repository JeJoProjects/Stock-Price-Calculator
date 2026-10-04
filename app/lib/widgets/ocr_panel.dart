import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../ocr/ocr_batch.dart';
import '../ocr/ocr_service.dart';
import '../theme/app_theme.dart';

const _pickerExtensions = [
  'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', // images
  'pdf',
  'xlsx', 'xls', 'csv', // spreadsheets
];

enum _ResultView { preview, markdown }

/// "Drop / browse / paste many files or a whole folder - get one combined,
/// copyable Markdown document back." Left: input zone + file queue.
/// Right: rendered preview (or the raw Markdown source) with Save/Copy.
class OcrPanel extends StatefulWidget {
  final OcrService service;

  const OcrPanel({super.key, required this.service});

  @override
  State<OcrPanel> createState() => _OcrPanelState();
}

class _OcrPanelState extends State<OcrPanel> {
  late final OcrBatchController _batch;
  final _titleController = TextEditingController(text: 'OCR Extraction');
  final _sourceController = TextEditingController();
  _ResultView _view = _ResultView.preview;
  bool _sourceEdited = false;
  bool _dragHovering = false;
  String? _flash;
  Timer? _flashTimer;

  // Deliberately not autofocus: true - the outer HomePage Focus already
  // autofocuses (for Ctrl+N/Q/F/,) and two competing autofocus nodes in
  // the same tree (both tabs are built eagerly by TabBarView) caused
  // focus to jump/flicker when switching tabs. Focus is requested
  // on-hover instead, same as how a desktop app scopes Ctrl+V to whatever
  // pane the mouse is over.
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _batch = OcrBatchController(widget.service)..addListener(_onBatchChanged);
    _titleController.addListener(_onBatchChanged);
  }

  @override
  void didUpdateWidget(OcrPanel old) {
    super.didUpdateWidget(old);
    _batch.service = widget.service;
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _batch.dispose();
    _titleController.dispose();
    _sourceController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onBatchChanged() {
    if (!_sourceEdited) _sourceController.text = _batch.toMarkdown(_titleController.text);
    if (mounted) setState(() {});
  }

  String get _markdown =>
      _sourceEdited ? _sourceController.text : _batch.toMarkdown(_titleController.text);

  void _showFlash(String message) {
    _flashTimer?.cancel();
    setState(() => _flash = message);
    _flashTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  Future<void> _browseFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _pickerExtensions,
      allowMultiple: true,
    );
    final paths = result?.files.map((f) => f.path).whereType<String>().toList() ?? const [];
    if (paths.isNotEmpty) await _batch.addPaths(paths);
  }

  Future<void> _browseFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select a folder to OCR');
    if (dir != null) await _batch.addPaths([dir]);
  }

  Future<void> _pasteFromClipboard() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      _showFlash('Clipboard access is not available on this platform.');
      return;
    }

    final reader = await clipboard.read();

    // Snipping Tool / "Copy image" case - pasted bitmap, no file on disk.
    for (final format in [Formats.png, Formats.jpeg, Formats.tiff, Formats.gif]) {
      if (reader.canProvide(format)) {
        final completer = Completer<Uint8List?>();
        reader.getFile(format, (file) async {
          completer.complete(await file.readAll());
        }, onError: (_) => completer.complete(null));
        final bytes = await completer.future;
        if (bytes != null) await _batch.addPastedImage(bytes);
        return;
      }
    }

    // Explorer "Copy" of an actual file on disk.
    if (reader.canProvide(Formats.fileUri)) {
      final completer = Completer<Uri?>();
      reader.getValue(Formats.fileUri, (uri) => completer.complete(uri),
          onError: (_) => completer.complete(null));
      final uri = await completer.future;
      if (uri != null) {
        await _batch.addPaths([File.fromUri(uri).path]);
        return;
      }
    }

    _showFlash('Nothing usable on the clipboard - copy an image, file, or screenshot first.');
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _markdown));
    _showFlash('Copied the full Markdown.');
  }

  Future<void> _saveMarkdown() async {
    final base = _titleController.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: 'Save OCR result',
      fileName: '${base.isEmpty ? 'ocr_result' : base}.md',
      type: FileType.custom,
      allowedExtensions: const ['md'],
    );
    if (picked == null) return;
    final path = picked.toLowerCase().endsWith('.md') ? picked : '$picked.md';
    try {
      await File(path).writeAsString(_markdown, encoding: utf8);
      _showFlash('Saved $path');
    } catch (e) {
      _showFlash('Could not save: $e');
    }
  }

  void _clear() {
    _sourceEdited = false;
    _batch.clear();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _focusNode.requestFocus(),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              HardwareKeyboard.instance.isControlPressed &&
              event.logicalKey == LogicalKeyboardKey.keyV) {
            _pasteFromClipboard();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Padding(
          padding: const EdgeInsets.all(kPanelSpacing),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 340, child: _inputColumn()),
              const SizedBox(width: kPanelSpacing),
              Expanded(child: _resultBox()),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration({Color? borderColor, double borderWidth = 1}) => BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: borderColor ?? AppColors.border, width: borderWidth),
      );

  Widget _inputColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dropZone(),
        const SizedBox(height: kPanelSpacing),
        Expanded(child: _queueCard()),
      ],
    );
  }

  Widget _dropZone() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragHovering = true),
      onDragExited: (_) => setState(() => _dragHovering = false),
      onDragDone: (details) async {
        setState(() => _dragHovering = false);
        final paths = details.files.map((f) => f.path).toList();
        if (paths.isNotEmpty) await _batch.addPaths(paths);
      },
      child: Container(
        decoration: _cardDecoration(
          borderColor: _dragHovering ? AppColors.accentBlue : null,
          borderWidth: _dragHovering ? 2 : 1,
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file_rounded,
                size: 34, color: _dragHovering ? AppColors.accentBlue : AppColors.textMuted),
            const SizedBox(height: 10),
            const Text(
              'Drop files or folders here',
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 4),
            const Text(
              'Images, PDFs, Excel/CSV - many at once',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _browseFiles,
                  icon: const Icon(Icons.insert_drive_file_outlined, size: 16),
                  label: const Text('Files...'),
                ),
                OutlinedButton.icon(
                  onPressed: _browseFolder,
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text('Folder...'),
                ),
                OutlinedButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded, size: 16),
                  label: const Text('Paste'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'or hover here and press Ctrl+V',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _queueCard() {
    final items = _batch.items;
    return Container(
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Text(
                  items.isEmpty ? 'Files' : 'Files (${_batch.finishedCount}/${items.length})',
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const Spacer(),
                if (_batch.hasFailures && !_batch.isBusy)
                  TextButton.icon(
                    onPressed: _batch.retryFailed,
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Retry'),
                  ),
                if (items.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.clear_rounded, size: 15),
                    label: const Text('Clear'),
                  ),
              ],
            ),
          ),
          if (_batch.isBusy)
            LinearProgressIndicator(
              value: items.isEmpty ? null : _batch.finishedCount / items.length,
              minHeight: 2,
              color: AppColors.accentBlue,
              backgroundColor: AppColors.bgInput,
            ),
          if (_batch.notice != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: AppColors.accentBlue.withValues(alpha: 0.1),
              child: Text(_batch.notice!,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
            ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('No files yet',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => _queueRow(i, items[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _queueRow(int index, OcrBatchItem item) {
    final Widget leading = switch (item.status) {
      OcrItemStatus.pending =>
        const Icon(Icons.schedule_rounded, size: 16, color: AppColors.textMuted),
      OcrItemStatus.running => const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentBlue)),
      OcrItemStatus.done =>
        const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.profitGreen),
      OcrItemStatus.error =>
        const Icon(Icons.error_rounded, size: 16, color: AppColors.lossRed),
    };
    return Tooltip(
      message: item.error ?? item.path,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 10),
            Text('${index + 1}.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(item.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
            ),
            if (item.status != OcrItemStatus.running)
              InkWell(
                onTap: () => _batch.remove(item),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 14, color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _resultBox() {
    final hasItems = _batch.items.isNotEmpty;
    return Container(
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _titleController,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Document title',
                      prefixIcon: Icon(Icons.title_rounded, size: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SegmentedButton<_ResultView>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: _ResultView.preview, label: Text('Preview')),
                    ButtonSegment(value: _ResultView.markdown, label: Text('Markdown')),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
                const Spacer(),
                if (_flash != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(_flash!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ),
                  ),
                if (_sourceEdited)
                  TextButton(
                    onPressed: () {
                      _sourceEdited = false;
                      _onBatchChanged();
                    },
                    child: const Text('Reset edits'),
                  ),
                TextButton.icon(
                  onPressed: hasItems ? _copyAll : null,
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('Copy all'),
                ),
                TextButton.icon(
                  onPressed: hasItems ? _saveMarkdown : null,
                  icon: const Icon(Icons.download_rounded, size: 15),
                  label: const Text('Save .md'),
                ),
              ],
            ),
          ),
          Expanded(
            child: !hasItems
                ? _emptyState()
                : _view == _ResultView.preview
                    ? _previewList()
                    : _sourceEditor(),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 36, color: AppColors.textMuted),
            SizedBox(height: 14),
            Text('No files yet',
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
            SizedBox(height: 4),
            Text(
              'Drop, browse, or paste files - or pick a whole folder.\n'
              'Everything is combined into one Markdown document here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceEditor() {
    return Padding(
      padding: const EdgeInsets.all(12),
      // Editable, not just selectable - lets the user clean up or annotate
      // the combined Markdown before copying or saving it.
      child: TextField(
        controller: _sourceController,
        onChanged: (_) => setState(() => _sourceEdited = true),
        maxLines: null,
        expands: true,
        style: const TextStyle(
            color: AppColors.textPrimary, fontFamily: 'Consolas', fontSize: 12.5, height: 1.5),
        decoration: const InputDecoration(filled: false, border: InputBorder.none, isDense: true),
      ),
    );
  }

  Widget _previewList() {
    final items = _batch.items;
    final title = _titleController.text.trim();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          children: [
            Text(title.isEmpty ? 'OCR Extraction' : title,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Divider(color: AppColors.border),
            const SizedBox(height: 6),
            const Text('PART 1: FULL OCR TEXT EXTRACTION (every word, every file)',
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Divider(color: AppColors.border),
            for (var i = 0; i < items.length; i++) _previewItem(i, items[i]),
          ],
        ),
      ),
    );
  }

  Widget _previewItem(int index, OcrBatchItem item) {
    final body = switch (item.status) {
      OcrItemStatus.done => item.text.isEmpty ? '[No text found]' : item.text,
      OcrItemStatus.error => '[OCR failed: ${item.error ?? 'unknown error'}]',
      OcrItemStatus.running => 'Running OCR...',
      OcrItemStatus.pending => 'Waiting...',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Document ${index + 1} - ',
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.bgInput,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(item.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.lossRed, fontFamily: 'Consolas', fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final w in item.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Note: $w',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.bgPrimary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 40, 14),
                  child: SelectableText(
                    body,
                    style: TextStyle(
                      color: item.status == OcrItemStatus.error
                          ? AppColors.lossRed
                          : AppColors.textPrimary,
                      fontFamily: 'Consolas',
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ),
                if (item.status == OcrItemStatus.done)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      tooltip: 'Copy this document',
                      iconSize: 15,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_rounded, color: AppColors.textMuted),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: item.text));
                        _showFlash('Copied ${item.label}.');
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border),
        ],
      ),
    );
  }
}
