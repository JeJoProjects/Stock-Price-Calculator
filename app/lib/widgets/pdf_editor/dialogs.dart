import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../pdfedit/asset_store.dart';
import '../../pdfedit/signature_tools.dart';
import '../../theme/app_theme.dart';
import 'image_renderers.dart';

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, String okLabel = 'OK', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.bgSecondary,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(message, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.lossRed) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Asks for a link target. Adds https:// when the user types a bare domain.
Future<String?> askLinkDialog(BuildContext context) async {
  final c = TextEditingController(text: 'https://');
  final r = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.bgSecondary,
      title: const Text('Add link', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Web address', hintText: 'https://example.com'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Add link')),
      ],
    ),
  );
  c.dispose();
  if (r == null) return null;
  final t = r.trim();
  if (t.isEmpty || t == 'https://') return null;
  return RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(t) ? t : 'https://$t';
}

class FindReplaceRequest {
  final String find, replace;
  final bool matchCase;
  const FindReplaceRequest(this.find, this.replace, this.matchCase);
}

/// Find & Replace across all pages. [count] reports live match counts.
Future<FindReplaceRequest?> findReplaceDialog(BuildContext context, Future<int> Function(String, bool) count) {
  return showDialog<FindReplaceRequest>(context: context, builder: (_) => _FindReplace(count: count));
}

class _FindReplace extends StatefulWidget {
  const _FindReplace({required this.count});
  final Future<int> Function(String, bool) count;
  @override
  State<_FindReplace> createState() => _FindReplaceState();
}

class _FindReplaceState extends State<_FindReplace> {
  final _find = TextEditingController();
  final _repl = TextEditingController();
  bool _case = false;
  int? _matches;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _find.dispose();
    _repl.dispose();
    super.dispose();
  }

  void _recount() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final q = _find.text;
      final n = q.isEmpty ? null : await widget.count(q, _case);
      if (mounted) setState(() => _matches = n);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgSecondary,
      title: const Text('Find & Replace', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _find,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Find'),
            onChanged: (_) => _recount(),
          ),
          const SizedBox(height: 10),
          TextField(controller: _repl, decoration: const InputDecoration(labelText: 'Replace with')),
          const SizedBox(height: 6),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _case,
            onChanged: (v) {
              setState(() => _case = v ?? false);
              _recount();
            },
            title: const Text('Match case', style: TextStyle(fontSize: 13)),
          ),
          Text(
            _matches == null ? 'Type to search every page.' : (_matches == 0 ? 'No matches.' : '$_matches match${_matches == 1 ? '' : 'es'} found.'),
            style: TextStyle(color: _matches == 0 ? AppColors.lossRed : AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            'Replacing rewrites the whole text line that contains a match, using the closest installed font.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: (_matches ?? 0) > 0 ? () => Navigator.pop(context, FindReplaceRequest(_find.text, _repl.text, _case)) : null,
          child: const Text('Replace all'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- signature ---

Future<StoredAsset?> signatureDialog(BuildContext context, AssetStore store) =>
    showDialog<StoredAsset>(context: context, builder: (_) => _SignatureDialog(store: store));

const _inkColors = [0xFF111111, 0xFF1A237E, 0xFF0D47A1, 0xFFB71C1C];

class _SignatureDialog extends StatefulWidget {
  const _SignatureDialog({required this.store});
  final AssetStore store;
  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  final _name = TextEditingController();
  String _font = signatureFonts.first.$1;
  int _ink = _inkColors[1];
  final List<List<Offset>> _strokes = [];
  double _penWidth = 3;
  Uint8List? _upload;
  String? _uploadName;
  bool _transparent = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _tabs.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _canSave => switch (_tabs.index) {
        0 => _name.text.trim().isNotEmpty,
        1 => _strokes.any((s) => s.isNotEmpty),
        _ => _upload != null,
      };

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final png = switch (_tabs.index) {
        0 => await renderTypedSignature(_name.text.trim(), _font, _ink),
        1 => await renderStrokes(_strokes, _ink, _penWidth),
        _ => _transparent ? removeBackground(_upload!) : _upload!,
      };
      final asset = await widget.store.add(png);
      if (mounted) Navigator.pop(context, asset);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not create the signature: $e';
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.single;
    if (f == null) return;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) return;
    setState(() {
      _upload = bytes;
      _uploadName = f.name;
    });
  }

  Widget _inkRow() => Row(children: [
        const Text('Colour', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(width: 10),
        for (final c in _inkColors)
          GestureDetector(
            onTap: () => setState(() => _ink = c),
            child: Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(color: _ink == c ? AppColors.accentBlue : AppColors.border, width: _ink == c ? 2.5 : 1),
              ),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgSecondary,
      child: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              const Text('New signature', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, size: 18)),
            ]),
          ),
          TabBar(
            controller: _tabs,
            onTap: (_) => setState(() {}),
            tabs: const [Tab(text: 'Type'), Tab(text: 'Draw'), Tab(text: 'Upload image')],
          ),
          SizedBox(
            height: 330,
            child: TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [_typeTab(), _drawTab(), _uploadTab()],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(_error!, style: const TextStyle(color: AppColors.lossRed, fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _canSave && !_busy ? _save : null, child: const Text('Save signature')),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _typeTab() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Type your name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          _inkRow(),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 3.4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final f in signatureFonts)
                  InkWell(
                    onTap: () => setState(() => _font = f.$1),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _font == f.$1 ? AppColors.accentBlue : AppColors.border, width: _font == f.$1 ? 2.5 : 1),
                      ),
                      child: Text(_name.text.trim().isEmpty ? 'Your name' : _name.text.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: f.$1, fontSize: 28, color: Color(_ink))),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      );

  Widget _drawTab() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                color: Colors.white,
                child: Listener(
                  onPointerDown: (e) => setState(() => _strokes.add([e.localPosition])),
                  onPointerMove: (e) => setState(() {
                    if (_strokes.isNotEmpty) _strokes.last.add(e.localPosition);
                  }),
                  child: CustomPaint(painter: _PadPainter(_strokes, Color(_ink), _penWidth), size: Size.infinite),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            _inkRow(),
            const Spacer(),
            const Text('Pen', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            SizedBox(
              width: 110,
              child: Slider(value: _penWidth, min: 1.5, max: 8, onChanged: (v) => setState(() => _penWidth = v)),
            ),
            TextButton.icon(
              onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Clear'),
            ),
          ]),
        ]),
      );

  Widget _uploadTab() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image_outlined, size: 16),
              label: const Text('Choose image...'),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(_uploadName ?? 'PNG or JPG of your signature on white paper', style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
          ]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _transparent,
            onChanged: (v) => setState(() => _transparent = v ?? true),
            title: const Text('Make the white background transparent and trim the edges', style: TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
              child: _upload == null
                  ? const Center(child: Text('Preview', style: TextStyle(color: Colors.black38)))
                  : Padding(
                      padding: const EdgeInsets.all(8),
                      child: Image.memory(_transparent ? removeBackground(_upload!) : _upload!, fit: BoxFit.contain),
                    ),
            ),
          ),
        ]),
      );
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes, this.color, this.width);
  final List<List<Offset>> strokes;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    // baseline guide
    canvas.drawLine(Offset(16, size.height * 0.72), Offset(size.width - 16, size.height * 0.72),
        Paint()..color = const Color(0x22000000)..strokeWidth = 1);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, width / 2, Paint()..color = color);
      } else if (s.length > 1) {
        final path = Path()..moveTo(s.first.dx, s.first.dy);
        for (final o in s.skip(1)) {
          path.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(path, p);
      }
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}

// -------------------------------------------------------------------- stamp ---

Future<StoredAsset?> stampDialog(BuildContext context, AssetStore store) =>
    showDialog<StoredAsset>(context: context, builder: (_) => _StampDialog(store: store));

class _StampDialog extends StatefulWidget {
  const _StampDialog({required this.store});
  final AssetStore store;
  @override
  State<_StampDialog> createState() => _StampDialogState();
}

class _StampDialogState extends State<_StampDialog> {
  final _text = TextEditingController(text: 'Reviewed');
  int _color = 0xFFD32F2F;
  Future<Uint8List>? _preview;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _preview = _text.text.trim().isEmpty ? null : renderStamp(_text.text, _color));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgSecondary,
      title: const Text('New stamp', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _text, autofocus: true, decoration: const InputDecoration(labelText: 'Stamp text'), onChanged: (_) => _refresh()),
          const SizedBox(height: 12),
          Row(children: [
            for (final c in const [0xFFD32F2F, 0xFF2E7D32, 0xFF1565C0, 0xFFEF6C00, 0xFF111111])
              GestureDetector(
                onTap: () {
                  _color = c;
                  _refresh();
                },
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(color: _color == c ? AppColors.accentBlue : AppColors.border, width: _color == c ? 2.5 : 1),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Container(
            height: 110,
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
            padding: const EdgeInsets.all(10),
            child: FutureBuilder<Uint8List>(
              future: _preview,
              builder: (_, snap) => snap.hasData ? Image.memory(snap.data!, fit: BoxFit.contain) : const SizedBox(),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _text.text.trim().isEmpty
              ? null
              : () async {
                  final nav = Navigator.of(context);
                  final png = await renderStamp(_text.text, _color);
                  nav.pop(await widget.store.add(png));
                },
          child: const Text('Save stamp'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- apply ---

enum ApplyChoice { saveAs, replaceOriginal, keepEditing }

Future<ApplyChoice?> applyChangesDialog(BuildContext context,
    {required String fileName, required int sizeBytes, required bool canReplace}) {
  final mb = sizeBytes >= 1024 * 1024 ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  return showDialog<ApplyChoice>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.bgSecondary,
      title: const Row(children: [
        Icon(Icons.check_circle_rounded, color: AppColors.profitGreen, size: 22),
        SizedBox(width: 10),
        Text('Changes applied', style: TextStyle(fontSize: 16)),
      ]),
      content: Text('$fileName is ready ($mb). Save it to keep your edits.\nThe original file stays untouched unless you replace it.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, ApplyChoice.keepEditing), child: const Text('Keep editing')),
        if (canReplace) OutlinedButton(onPressed: () => Navigator.pop(context, ApplyChoice.replaceOriginal), child: const Text('Replace original')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, ApplyChoice.saveAs),
          icon: const Icon(Icons.download_rounded, size: 16),
          label: const Text('Save as...'),
        ),
      ],
    ),
  );
}
