import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pdfedit/asset_store.dart';
import '../pdfedit/doc_session.dart';
import '../pdfedit/edit_model.dart';
import '../pdfedit/fonts.dart';
import '../pdfedit/pdfium_edit.dart';
import '../pdfedit/signature_tools.dart';
import '../pdfedit/startup.dart';
import '../pdfedit/workspace.dart';
import '../theme/app_theme.dart';
import 'pdf_editor/dialogs.dart';
import 'pdf_editor/editable_page.dart';
import 'pdf_editor/editor_controller.dart';
import 'pdf_editor/editor_rail.dart';
import 'pdf_editor/editor_toolbar.dart';
import 'pdf_editor/image_renderers.dart';
import 'pdf_editor/options_bar.dart';
import 'pdf_editor/page_renderer.dart';
import 'pdf_editor/pdf_canvas.dart';

/// The "PDF Editor" tab: open many PDFs (or a folder), edit text/symbols,
/// annotate, sign, rearrange pages, then Apply changes and save.
class PdfEditorPanel extends StatefulWidget {
  const PdfEditorPanel({super.key});

  @override
  State<PdfEditorPanel> createState() => _PdfEditorPanelState();
}

class _PdfEditorPanelState extends State<PdfEditorPanel> {
  final _ws = PdfWorkspace();
  final _ctrl = EditorController();
  final _focus = FocusNode();
  final _sigStore = AssetStore.forKind('signatures');
  final _stampStore = AssetStore.forKind('stamps');

  List<StoredAsset> _signatures = const [];
  List<StampEntry> _stamps = const [];
  List<String> _recent = const [];
  bool _dragHover = false;
  bool _busy = false;
  String _busyText = '';

  PdfDocSession? get _doc => _ws.active;

  @override
  void initState() {
    super.initState();
    _ws.addListener(_onWorkspace);
    _ctrl.addListener(_rebuild);
    _loadAssets();
    _loadRecent();
    if (startupPdfPaths.isNotEmpty) {
      final paths = [...startupPdfPaths];
      startupPdfPaths.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPaths(paths));
    }
  }

  @override
  void dispose() {
    _ws.removeListener(_onWorkspace);
    _ctrl.removeListener(_rebuild);
    _ws.dispose();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  PdfDocSession? _listening;

  void _onWorkspace() {
    final d = _doc;
    if (d != _listening) {
      _listening?.removeListener(_rebuild);
      d?.addListener(_rebuild);
      _listening = d;
      _ctrl.selected = {};
      _ctrl.currentPage = 0;
    }
    _rebuild();
  }

  // ---------------------------------------------------------------- assets ---

  Future<void> _loadAssets() async {
    final sigs = await _sigStore.list();
    final custom = await _stampStore.list();
    final presets = <StampEntry>[];
    for (final (label, color) in stampPresets) {
      presets.add(StampEntry(label, await renderStamp(label, color)));
    }
    if (!mounted) return;
    setState(() {
      _signatures = sigs;
      _stamps = [for (final a in custom) StampEntry('Custom', a.bytes, asset: a), ...presets];
    });
  }

  Future<void> _loadRecent() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _recent = (p.getStringList('pdfEditorRecent') ?? const []).where((f) => File(f).existsSync()).toList());
  }

  Future<void> _remember(Iterable<String> paths) async {
    final p = await SharedPreferences.getInstance();
    final list = {...paths.where(isPdfPath), ..._recent}.take(8).toList();
    await p.setStringList('pdfEditorRecent', list);
    if (mounted) setState(() => _recent = list);
  }

  // ------------------------------------------------------------------ files ---

  Future<void> _openPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    setState(() {
      _busy = true;
      _busyText = 'Opening...';
    });
    await _ws.openPaths(paths);
    if (!mounted) return;
    setState(() => _busy = false);
    unawaited(_remember(paths.where((p) => !FileSystemEntity.isDirectorySync(p))));
    final failed = _ws.lastFailures;
    if (failed.isNotEmpty) {
      _toast('Could not open ${failed.length} file${failed.length == 1 ? '' : 's'}: '
          '${failed.first.path.split(RegExp(r'[\\/]')).last} - ${failed.first.message}');
    }
  }

  Future<void> _pickFiles() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'pdfedit'],
      allowMultiple: true,
    );
    final paths = r?.files.map((f) => f.path).whereType<String>().toList() ?? const [];
    await _openPaths(paths);
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Open a folder of PDFs');
    if (dir != null) await _openPaths([dir]);
  }

  Future<void> _newBlank() async {
    await _ws.newBlank();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 4)));
  }

  String _suggestedName(PdfDocSession d) {
    final base = d.title.replaceAll(RegExp(r'\.(pdf|pdfedit)$', caseSensitive: false), '');
    return '${base}_edited.pdf';
  }

  Future<bool> _saveAs(PdfDocSession d) async {
    final dir = d.sourcePath == null ? null : File(d.sourcePath!).parent.path;
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: 'Save PDF',
      fileName: _suggestedName(d),
      initialDirectory: dir,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (picked == null) return false;
    final path = picked.toLowerCase().endsWith('.pdf') ? picked : '$picked.pdf';
    return _writeTo(d, path);
  }

  Future<bool> _writeTo(PdfDocSession d, String path) async {
    setState(() {
      _busy = true;
      _busyText = 'Saving...';
    });
    try {
      await d.saveTo(path);
      _toast('Saved ${path.split(RegExp(r'[\\/]')).last}');
      unawaited(_remember([path]));
      return true;
    } on Object catch (e) {
      _toast('Could not save: $e');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final d = _doc;
    if (d == null) return;
    if (d.savedPath != null) {
      await _writeTo(d, d.savedPath!);
    } else {
      await _saveAs(d);
    }
  }

  Future<void> _saveDraft() async {
    final d = _doc;
    if (d == null) return;
    final base = d.title.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: 'Save draft (resume editing later)',
      fileName: '$base.pdfedit',
      initialDirectory: d.sourcePath == null ? null : File(d.sourcePath!).parent.path,
      type: FileType.custom,
      allowedExtensions: const ['pdfedit'],
    );
    if (picked == null) return;
    final path = picked.toLowerCase().endsWith('.pdfedit') ? picked : '$picked.pdfedit';
    try {
      await d.saveDraft(path);
      _toast('Draft saved - open it from the Documents toolbar to continue.');
    } on Object catch (e) {
      _toast('Could not save the draft: $e');
    }
  }

  /// "Apply changes": bakes everything into a PDF, then offers to save it.
  Future<void> _applyChanges() async {
    final d = _doc;
    if (d == null) return;
    setState(() {
      _busy = true;
      _busyText = 'Applying changes...';
    });
    Uint8List bytes;
    try {
      bytes = await d.exportBytes();
    } on Object catch (e) {
      if (mounted) setState(() => _busy = false);
      _toast('Could not apply the changes: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final choice = await applyChangesDialog(context,
        fileName: _suggestedName(d), sizeBytes: bytes.length, canReplace: d.sourcePath != null);
    if (choice == null || choice == ApplyChoice.keepEditing || !mounted) return;
    if (choice == ApplyChoice.saveAs) {
      await _saveAs(d);
    } else {
      final src = d.sourcePath!;
      final ok = await confirmDialog(context,
          title: 'Replace the original file?',
          message: 'This overwrites\n$src\nA backup of the original is kept next to it as "(original)".',
          okLabel: 'Replace',
          danger: true);
      if (!ok) return;
      final backup = src.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), ' (original).pdf');
      if (!File(backup).existsSync()) await File(src).copy(backup);
      await _writeTo(d, src);
    }
  }

  Future<void> _closeDoc(int i) async {
    final d = _ws.docs[i];
    if (d.dirty) {
      final ok = await confirmDialog(context,
          title: 'Close without saving?',
          message: '${d.title} has unsaved changes. Use Save or Apply changes first to keep them.',
          okLabel: 'Close without saving',
          danger: true);
      if (!ok) return;
    }
    PageImageCache.instance.evictDoc(d);
    _ws.close(i);
  }

  // ------------------------------------------------------------ page actions ---

  Future<void> _structure(StructAction a, {int? goToPage}) async {
    final d = _doc;
    if (d == null) return;
    setState(() {
      _busy = true;
      _busyText = 'Updating pages...';
    });
    try {
      await d.applyStructure(a);
      _ctrl.selected = {};
      if (_ctrl.currentPage >= d.pageCount) _ctrl.currentPage = d.pageCount - 1;
      if (goToPage != null) _ctrl.requestScrollTo(goToPage.clamp(0, d.pageCount - 1));
    } on PdfiumException catch (e) {
      _toast(e.message);
    } on Object catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePage(int page) async {
    final d = _doc;
    if (d == null) return;
    if (d.pageCount == 1) {
      _toast('A PDF needs at least one page.');
      return;
    }
    await _structure(DeletePages([page]));
  }

  Future<void> _insertFromPdf() async {
    final d = _doc;
    if (d == null) return;
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    final path = r?.files.single.path;
    if (path == null) return;
    await _structure(InsertFromFile(_ctrl.currentPage + 1, path), goToPage: _ctrl.currentPage + 1);
  }

  // ----------------------------------------------------------------- images ---

  Future<void> _newImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.single;
    if (f == null) return;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) return;
    final aspect = imageAspect(bytes);
    if (aspect == null) {
      _toast('That image format is not supported.');
      return;
    }
    _ctrl.startPlacing(PlacingImage(bytes, aspect, widthPt: 220));
  }

  Future<void> _newSignature() async {
    final a = await signatureDialog(context, _sigStore);
    if (a == null) return;
    await _loadAssets();
    final aspect = imageAspect(a.bytes) ?? 3;
    _ctrl.startPlacing(PlacingImage(a.bytes, aspect, widthPt: 140));
  }

  void _placeSignature(StoredAsset a) {
    final aspect = imageAspect(a.bytes) ?? 3;
    _ctrl.startPlacing(PlacingImage(a.bytes, aspect, widthPt: 140));
  }

  Future<void> _deleteSignature(StoredAsset a) async {
    await _sigStore.delete(a);
    await _loadAssets();
  }

  Future<void> _newStamp() async {
    final a = await stampDialog(context, _stampStore);
    if (a == null) return;
    await _loadAssets();
    _placeStamp(a.bytes);
  }

  void _placeStamp(Uint8List png) {
    final aspect = imageAspect(png) ?? 3;
    _ctrl.startPlacing(PlacingImage(png, aspect, widthPt: 150));
  }

  Future<void> _deleteStamp(StoredAsset a) async {
    await _stampStore.delete(a);
    await _loadAssets();
  }

  // ---------------------------------------------------------- find & replace ---

  RegExp _pattern(String find, bool matchCase) => RegExp(RegExp.escape(find), caseSensitive: matchCase);

  Future<int> _countMatches(String find, bool matchCase) async {
    final d = _doc;
    if (d == null || find.isEmpty) return 0;
    final re = _pattern(find, matchCase);
    var n = 0;
    for (var i = 0; i < d.pageCount; i++) {
      final info = await d.pageInfo(i);
      final replaced = <int>{for (final o in d.opsOnPage(i)) if (o is TextOp) ...o.removeObjects};
      for (final line in info.lines) {
        if (line.objectIndices.every(replaced.contains)) continue;
        n += re.allMatches(line.text).length;
      }
      for (final o in d.opsOnPage(i)) {
        if (o is TextOp) n += re.allMatches(o.text).length;
      }
    }
    return n;
  }

  Future<void> _findReplace() async {
    final d = _doc;
    if (d == null) return;
    final req = await findReplaceDialog(context, _countMatches);
    if (req == null) return;
    final re = _pattern(req.find, req.matchCase);
    final add = <EditOp>[];
    final update = <EditOp>[];
    for (var i = 0; i < d.pageCount; i++) {
      final info = await d.pageInfo(i);
      final replaced = <int>{for (final o in d.opsOnPage(i)) if (o is TextOp) ...o.removeObjects};
      for (final line in info.lines) {
        if (line.objectIndices.every(replaced.contains) || !re.hasMatch(line.text)) continue;
        final r = line.first;
        add.add(TextOp(
          id: d.newId(),
          page: i,
          x: r.originX,
          baselineY: r.baselineY,
          text: line.text.replaceAll(re, req.replace),
          fontFamily: FontCatalog.guessFamily(r.fontName),
          size: r.fontSize,
          bold: r.bold,
          italic: r.italic,
          argb: r.argb,
          removeObjects: line.objectIndices,
          cover: [line.box],
        ));
      }
      for (final o in d.opsOnPage(i)) {
        if (o is TextOp && re.hasMatch(o.text)) update.add(o.copyWith(text: o.text.replaceAll(re, req.replace)));
      }
    }
    if (add.isEmpty && update.isEmpty) return;
    // one undo step for the whole replacement
    d.addOps(add);
    if (update.isNotEmpty) d.addOpsReplacing(update);
    _toast('Replaced ${add.length + update.length} line${add.length + update.length == 1 ? '' : 's'}.');
  }

  // ---------------------------------------------------------------- keyboard ---

  bool get _typing {
    final w = FocusManager.instance.primaryFocus?.context?.widget;
    return w is EditableText;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final d = _doc;

    if (ctrl) {
      if (k == LogicalKeyboardKey.keyO) {
        _pickFiles();
        return KeyEventResult.handled;
      }
      if (d == null) return KeyEventResult.ignored;
      if (_typing && (k == LogicalKeyboardKey.keyZ || k == LogicalKeyboardKey.keyY || k == LogicalKeyboardKey.keyA || k == LogicalKeyboardKey.keyC || k == LogicalKeyboardKey.keyV || k == LogicalKeyboardKey.keyX)) {
        return KeyEventResult.ignored; // let the text field handle its own undo/clipboard
      }
      if (k == LogicalKeyboardKey.keyZ) {
        shift ? d.redo() : d.undo();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyY) {
        d.redo();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyS) {
        shift ? _saveAs(d) : _save();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyW) {
        _closeDoc(_ws.activeIndex);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyF) {
        _findReplace();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.add || k == LogicalKeyboardKey.numpadAdd) {
        _ctrl.zoomBy(1.15);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract) {
        _ctrl.zoomBy(1 / 1.15);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.digit0) {
        _ctrl.setZoom(_ctrl.zoom, fit: true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (d == null || _typing) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      if (_ctrl.selected.isNotEmpty) {
        d.removeOps(_ctrl.selected);
        _ctrl.select({});
        return KeyEventResult.handled;
      }
    }
    if (k == LogicalKeyboardKey.escape) {
      if (_ctrl.placing != null || _ctrl.selected.isNotEmpty || _ctrl.tool != EditorTool.select) {
        _ctrl.placing = null;
        _ctrl.selected = {};
        _ctrl.setTool(EditorTool.select);
        _ctrl.changed();
        return KeyEventResult.handled;
      }
    }
    final nudge = shift ? 10.0 : 1.0;
    final dir = switch (k) {
      LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight => const Offset(1, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -1),
      LogicalKeyboardKey.arrowDown => const Offset(0, 1),
      _ => null,
    };
    if (dir != null && _ctrl.selected.isNotEmpty) {
      d.addOpsReplacing([
        for (final id in _ctrl.selected)
          if (d.opById(id) != null) d.opById(id)!.moved(dir.dx * nudge, dir.dy * nudge),
      ]);
      return KeyEventResult.handled;
    }
    final tool = switch (k) {
      LogicalKeyboardKey.keyV => EditorTool.select,
      LogicalKeyboardKey.keyT => EditorTool.text,
      LogicalKeyboardKey.keyW => EditorTool.whiteout,
      LogicalKeyboardKey.keyH => EditorTool.highlight,
      LogicalKeyboardKey.keyD => EditorTool.draw,
      LogicalKeyboardKey.keyR => EditorTool.rectangle,
      LogicalKeyboardKey.keyO => EditorTool.ellipse,
      LogicalKeyboardKey.keyL => EditorTool.line,
      _ => null,
    };
    if (tool != null) {
      _ctrl.setTool(tool);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (!_typing) _focus.requestFocus();
      },
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragHover = true),
          onDragExited: (_) => setState(() => _dragHover = false),
          onDragDone: (details) {
            setState(() => _dragHover = false);
            _openPaths(details.files.map((f) => f.path).toList());
          },
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.all(kPanelSpacing),
              child: _doc == null ? _startView() : _editorView(),
            ),
            if (_dragHover)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.accentBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(kCardRadius),
                      border: Border.all(color: AppColors.accentBlue, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Drop PDF files or a folder to open them',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            if (_busy)
              Positioned.fill(
                child: AbsorbPointer(
                  child: Container(
                    color: const Color(0x66000000),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                      decoration: BoxDecoration(color: AppColors.bgSecondary, borderRadius: BorderRadius.circular(10)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                        const SizedBox(width: 14),
                        Text(_busyText),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- start view ---

  Widget _startView() {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(kCardRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.picture_as_pdf_rounded, size: 52, color: AppColors.accentBlue),
              const SizedBox(height: 14),
              const Text('PDF Editor', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'Edit text and numbers in any PDF, annotate, sign, add images and stamps, and rearrange pages.\n'
                'Everything happens on your computer - nothing is uploaded.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, height: 1.5),
              ),
              const SizedBox(height: 26),
              Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
                FilledButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Upload PDF files'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
                ),
                OutlinedButton.icon(
                  onPressed: _pickFolder,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Open a folder'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
                ),
                OutlinedButton.icon(
                  onPressed: _newBlank,
                  icon: const Icon(Icons.add_box_outlined, size: 18),
                  label: const Text('Start with a blank document'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
                ),
              ]),
              const SizedBox(height: 14),
              const Text('or drag and drop PDFs and folders anywhere in this tab',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              if (_recent.isNotEmpty) ...[
                const SizedBox(height: 26),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Recent', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                ),
                const SizedBox(height: 6),
                for (final f in _recent.take(6))
                  InkWell(
                    onTap: () => _openPaths([f]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        const Icon(Icons.history_rounded, size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(f, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
                        ),
                      ]),
                    ),
                  ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- editor view ---

  Widget _editorView() {
    final d = _doc!;
    final callbacks = PageCallbacks(askLinkUrl: () => askLinkDialog(context));
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EditorRail(
        workspace: _ws,
        ctrl: _ctrl,
        onOpenFiles: _pickFiles,
        onOpenFolder: _pickFolder,
        onNewBlank: _newBlank,
        onClose: _closeDoc,
        onDeletePage: _deletePage,
        onRotatePage: (p, deg) => _structure(RotatePages([p], deg)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: EditorToolbar(
                ctrl: _ctrl,
                signatures: _signatures,
                stamps: _stamps,
                hasDoc: true,
                canUndo: d.canUndo,
                canRedo: d.canRedo,
                actions: ToolbarActions(
                  findReplace: _findReplace,
                  newSignature: _newSignature,
                  placeSignature: _placeSignature,
                  deleteSignature: _deleteSignature,
                  newImage: _newImage,
                  newStamp: _newStamp,
                  placeStamp: _placeStamp,
                  deleteStamp: _deleteStamp,
                  formFieldSoon: (what) => _toast('$what: interactive form fields are coming in an upcoming release. '
                      'For now use the Text tool and the ✕ ✓ ■ symbols to fill forms.'),
                  undo: d.undo,
                  redo: d.redo,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _saveButtons(d),
          ]),
          const SizedBox(height: 8),
          OptionsBar(
            ctrl: _ctrl,
            session: d,
            onDelete: () {
              d.removeOps(_ctrl.selected);
              _ctrl.select({});
            },
          ),
          const SizedBox(height: 8),
          _pageBar(d),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(kCardRadius),
                child: PdfCanvas(session: d, ctrl: _ctrl, callbacks: callbacks),
              ),
              if (d.dirty)
                Positioned(
                  bottom: 18,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Material(
                      color: const Color(0xFFFFE8C6),
                      borderRadius: BorderRadius.circular(12),
                      elevation: 6,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: FilledButton.icon(
                          onPressed: _applyChanges,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.profitGreen,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          ),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Apply changes', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          _statusBar(d),
        ]),
      ),
    ]);
  }

  Widget _saveButtons(PdfDocSession d) {
    final menu = MenuController();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      FilledButton.icon(
        onPressed: _save,
        icon: const Icon(Icons.save_outlined, size: 16),
        label: const Text('Save'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(8))),
        ),
      ),
      MenuAnchor(
        controller: menu,
        style: const MenuStyle(backgroundColor: WidgetStatePropertyAll(AppColors.bgSecondary)),
        menuChildren: [
          MenuItemButton(
            leadingIcon: const Icon(Icons.save_as_outlined, size: 17),
            onPressed: () => _saveAs(d),
            child: const Text('Save as...   Ctrl+Shift+S'),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.bookmark_add_outlined, size: 17),
            onPressed: _saveDraft,
            child: const Text('Save draft (continue later)...'),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.check_rounded, size: 17),
            onPressed: _applyChanges,
            child: const Text('Apply changes and download...'),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.folder_open_rounded, size: 17),
            onPressed: _pickFiles,
            child: const Text('Open PDFs or drafts...   Ctrl+O'),
          ),
        ],
        builder: (context, c, _) => Tooltip(
          message: 'More save options',
          child: InkWell(
            onTap: () => c.isOpen ? c.close() : c.open(),
            child: Container(
              height: 34,
              width: 28,
              decoration: const BoxDecoration(
                color: AppColors.accentBlue,
                borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
                border: Border(left: BorderSide(color: Colors.white24)),
              ),
              child: const Icon(Icons.arrow_drop_down_rounded, size: 20, color: Colors.white),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _pageBar(PdfDocSession d) {
    final zoomPct = (_ctrl.zoom * 100).round();
    Widget btn(IconData i, String tip, VoidCallback? onTap) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: 34,
              height: 32,
              alignment: Alignment.center,
              child: Icon(i, size: 17, color: onTap == null ? AppColors.textMuted.withValues(alpha: 0.4) : AppColors.textPrimary),
            ),
          ),
        );
    final insertMenu = MenuController();
    return Row(children: [
      Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.bgSecondary, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
        child: Text('Page ${_ctrl.currentPage + 1} / ${d.pageCount}', style: const TextStyle(fontSize: 12.5)),
      ),
      const SizedBox(width: 8),
      Container(
        decoration: BoxDecoration(color: AppColors.bgSecondary, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          btn(Icons.delete_outline_rounded, 'Delete this page', () => _deletePage(_ctrl.currentPage)),
          btn(Icons.zoom_in_rounded, 'Zoom in (Ctrl +)', () => _ctrl.zoomBy(1.15)),
          btn(Icons.zoom_out_rounded, 'Zoom out (Ctrl -)', () => _ctrl.zoomBy(1 / 1.15)),
          btn(Icons.rotate_left_rounded, 'Rotate page left', () => _structure(RotatePages([_ctrl.currentPage], -90))),
          btn(Icons.rotate_right_rounded, 'Rotate page right', () => _structure(RotatePages([_ctrl.currentPage], 90))),
        ]),
      ),
      const SizedBox(width: 8),
      MenuAnchor(
        controller: insertMenu,
        style: const MenuStyle(backgroundColor: WidgetStatePropertyAll(AppColors.bgSecondary)),
        menuChildren: [
          MenuItemButton(
            leadingIcon: const Icon(Icons.note_add_outlined, size: 17),
            onPressed: () => _structure(InsertBlank(_ctrl.currentPage + 1), goToPage: _ctrl.currentPage + 1),
            child: const Text('Blank page'),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
            onPressed: _insertFromPdf,
            child: const Text('Pages from another PDF...'),
          ),
        ],
        builder: (context, c, _) => OutlinedButton.icon(
          onPressed: () => c.isOpen ? c.close() : c.open(),
          icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
          label: const Text('Insert page here'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 12)),
        ),
      ),
      const Spacer(),
      Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: AppColors.bgSecondary, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: 'z',
            isDense: true,
            dropdownColor: AppColors.bgSecondary,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
            items: [
              DropdownMenuItem(value: 'z', child: Text(_ctrl.fitWidth ? 'Fit width ($zoomPct%)' : '$zoomPct%')),
              const DropdownMenuItem(value: 'fit', child: Text('Fit width')),
              for (final p in const [50, 75, 100, 125, 150, 200, 300]) DropdownMenuItem(value: '$p', child: Text('$p%')),
            ],
            onChanged: (v) {
              if (v == null || v == 'z') return;
              if (v == 'fit') {
                _ctrl.setZoom(_ctrl.zoom, fit: true);
              } else {
                _ctrl.setZoom(int.parse(v) / 100);
              }
            },
          ),
        ),
      ),
    ]);
  }

  Widget _statusBar(PdfDocSession d) {
    return Row(children: [
      Expanded(
        child: Text(_ctrl.placing != null ? EditorTool.placeImage.hint : _ctrl.tool.hint,
            overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
      ),
      const SizedBox(width: 12),
      Text(d.title, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
      const SizedBox(width: 10),
      if (d.dirty)
        const Text('Unsaved changes', style: TextStyle(color: Color(0xFFFFB300), fontSize: 11.5))
      else
        Text(d.savedPath != null ? 'Saved' : 'No changes', style: const TextStyle(color: AppColors.profitGreen, fontSize: 11.5)),
    ]);
  }
}
