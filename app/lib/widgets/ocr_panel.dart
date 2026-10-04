import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../ocr/file_classifier.dart';
import '../ocr/ocr_models.dart';
import '../ocr/ocr_service.dart';
import '../theme/app_theme.dart';

enum _PanelStatus { idle, extracting, ocring, success, error }

/// "Drag, browse, or paste any file - get exact, copyable text back."
/// Left column is the drop/browse/paste zone, right column is the result.
/// Mirrors ScreenerPanel's bordered-card visual language so it reads as
/// part of the same app, not a bolted-on feature.
class OcrPanel extends StatefulWidget {
  final OcrService service;

  const OcrPanel({super.key, required this.service});

  @override
  State<OcrPanel> createState() => _OcrPanelState();
}

class _OcrPanelState extends State<OcrPanel> {
  _PanelStatus _status = _PanelStatus.idle;
  final _resultController = TextEditingController();
  List<String> _warnings = const [];
  String? _errorMessage;
  bool _dragHovering = false;
  bool _justCopied = false;

  // Deliberately not autofocus: true - the outer HomePage Focus already
  // autofocuses (for Ctrl+N/Q/F/,) and two competing autofocus nodes in
  // the same tree (both tabs are built eagerly by TabBarView) caused
  // focus to jump/flicker when switching tabs. Focus is requested
  // on-hover instead, same as how a desktop app scopes Ctrl+V to whatever
  // pane the mouse is over.
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _resultController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleFile(File file) async {
    if (!isSupportedPath(file.path) && !isPdfPath(file.path)) {
      setState(() {
        _status = _PanelStatus.error;
        _errorMessage = 'Unsupported file type. Try an image, PDF, or Excel/CSV file.';
      });
      return;
    }

    setState(() {
      _status = isPdfPath(file.path) ? _PanelStatus.extracting : _PanelStatus.ocring;
      _errorMessage = null;
    });

    try {
      final result = await widget.service.extract(file);
      if (!mounted) return;
      setState(() {
        _status = _PanelStatus.success;
        _resultController.text = result.text;
        _warnings = result.warnings;
      });
    } on OcrException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _PanelStatus.error;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _PanelStatus.error;
        _errorMessage = 'Something went wrong reading this file: $e';
      });
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', // images
        'pdf',
        'xlsx', 'xls', 'csv', // spreadsheets
      ],
    );
    final path = result?.files.single.path;
    if (path != null) await _handleFile(File(path));
  }

  Future<void> _pasteFromClipboard() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      setState(() {
        _status = _PanelStatus.error;
        _errorMessage = 'Clipboard access is not available on this platform.';
      });
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
        if (bytes != null) await _handlePastedImageBytes(bytes);
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
        await _handleFile(File.fromUri(uri));
        return;
      }
    }

    setState(() {
      _status = _PanelStatus.error;
      _errorMessage = 'Nothing usable on the clipboard - copy an image, file, or screenshot first.';
    });
  }

  Future<void> _handlePastedImageBytes(Uint8List bytes) async {
    setState(() {
      _status = _PanelStatus.ocring;
      _errorMessage = null;
    });
    try {
      final tempFile = await File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'stockcalc_ocr_paste_${DateTime.now().microsecondsSinceEpoch}.png',
      ).writeAsBytes(bytes);
      await _handleFile(tempFile);
      await tempFile.delete().catchError((_) => tempFile);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _PanelStatus.error;
        _errorMessage = 'Could not read the pasted image: $e';
      });
    }
  }

  void _copyResult() {
    Clipboard.setData(ClipboardData(text: _resultController.text));
    setState(() => _justCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _justCopied = false);
    });
  }

  void _clear() {
    setState(() {
      _status = _PanelStatus.idle;
      _resultController.clear();
      _warnings = const [];
      _errorMessage = null;
      _justCopied = false;
    });
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
              Expanded(child: _dropZone()),
              const SizedBox(width: kPanelSpacing),
              Expanded(child: _resultBox()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropZone() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragHovering = true),
      onDragExited: (_) => setState(() => _dragHovering = false),
      onDragDone: (details) async {
        setState(() => _dragHovering = false);
        if (details.files.isNotEmpty) {
          await _handleFile(File(details.files.first.path));
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(kCardRadius),
          border: Border.all(
            color: _dragHovering ? AppColors.accentBlue : AppColors.border,
            width: _dragHovering ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(kCardRadius),
          onTap: _browse,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload_file_rounded,
                      size: 40,
                      color: _dragHovering ? AppColors.accentBlue : AppColors.textMuted),
                  const SizedBox(height: 14),
                  Text(
                    'Drag a file here, or browse / paste below',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Images, PDFs, Excel/CSV, and screenshots',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _browse,
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        label: const Text('Browse...'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste_rounded, size: 16),
                        label: const Text('Paste'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'or hover here and press Ctrl+V',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultBox() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: AppColors.border),
      ),
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
                const Text('Extracted Text',
                    style: TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                if (_status != _PanelStatus.idle)
                  TextButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.clear_rounded, size: 15),
                    label: const Text('Clear'),
                  ),
                if (_status == _PanelStatus.success)
                  TextButton.icon(
                    onPressed: _copyResult,
                    icon: Icon(_justCopied ? Icons.check_rounded : Icons.copy_rounded, size: 15),
                    label: Text(_justCopied ? 'Copied' : 'Copy'),
                  ),
              ],
            ),
          ),
          Expanded(child: _resultBody()),
        ],
      ),
    );
  }

  Widget _resultBody() {
    switch (_status) {
      case _PanelStatus.idle:
        return _centered(
          icon: Icons.description_outlined,
          title: 'No file yet',
          subtitle: 'Drop, browse, or paste a file to extract its text.',
          iconColor: AppColors.textMuted,
        );
      case _PanelStatus.extracting:
        return _centered(
          icon: null,
          title: 'Extracting text...',
          subtitle: 'Reading the document directly - this is fast.',
          iconColor: AppColors.accentBlue,
        );
      case _PanelStatus.ocring:
        return _centered(
          icon: null,
          title: 'Running OCR...',
          subtitle: 'This can take a few seconds for images and scans.',
          iconColor: AppColors.accentBlue,
        );
      case _PanelStatus.error:
        return _centered(
          icon: Icons.error_outline_rounded,
          title: 'Could not extract text',
          subtitle: _errorMessage ?? 'Unknown error.',
          iconColor: AppColors.lossRed,
        );
      case _PanelStatus.success:
        if (_resultController.text.isEmpty) {
          return _centered(
            icon: Icons.description_outlined,
            title: 'No text found',
            subtitle: 'This file didn\'t contain any recognizable text.',
            iconColor: AppColors.textMuted,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_warnings.isNotEmpty) _warningsBanner(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                // Editable, not just selectable - lets the user clean up or
                // annotate the OCR'd text before copying it out.
                child: TextField(
                  controller: _resultController,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontFamily: 'Consolas', fontSize: 12.5, height: 1.5),
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _warningsBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppColors.accentBlue.withValues(alpha: 0.1),
      child: Text(
        _warnings.join(' '),
        style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
      ),
    );
  }

  Widget _centered({
    required IconData? icon,
    required String title,
    required String subtitle,
    required Color iconColor,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, size: 36, color: iconColor)
            else
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: iconColor),
              ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
