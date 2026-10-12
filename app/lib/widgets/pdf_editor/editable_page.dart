import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../pdfedit/doc_session.dart';
import '../../pdfedit/edit_model.dart';
import '../../pdfedit/fonts.dart';
import '../../pdfedit/pdf_baker.dart';
import '../../theme/app_theme.dart';
import 'editor_controller.dart';
import 'overlay_painter.dart';
import 'page_renderer.dart';

class PageCallbacks {
  const PageCallbacks({required this.askLinkUrl});

  /// Asks the user for a link target; null = cancelled.
  final Future<String?> Function() askLinkUrl;
}

enum _Drag { none, create, move, resize, ink }

class _Editing {
  _Editing({
    required this.family,
    required this.size,
    required this.bold,
    required this.italic,
    required this.argb,
    required this.x,
    required this.baselineY,
    required String text,
    this.existingOpId,
    this.removeObjects = const [],
    this.cover = const [],
    this.isNew = false,
  })  : controller = TextEditingController(text: text),
        focus = FocusNode(),
        originalText = text,
        origFamily = family,
        origSize = size,
        origBold = bold,
        origItalic = italic,
        origArgb = argb;

  String family;
  double size;
  bool bold, italic;
  int argb;
  final double x, baselineY;
  final String? existingOpId;
  final List<int> removeObjects;
  final List<Box> cover;
  final bool isNew;
  final String originalText;
  final String origFamily;
  final double origSize;
  final bool origBold, origItalic;
  final int origArgb;
  final TextEditingController controller;

  bool get styleChanged =>
      family != origFamily || size != origSize || bold != origBold || italic != origItalic || argb != origArgb;
  final FocusNode focus;

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

/// One page: rendered bitmap + overlay edits + all tool interaction.
class EditablePage extends StatefulWidget {
  const EditablePage({
    super.key,
    required this.session,
    required this.ctrl,
    required this.pageIndex,
    required this.scale,
    required this.callbacks,
  });

  final PdfDocSession session;
  final EditorController ctrl;
  final int pageIndex;

  /// Pixels per PDF point.
  final double scale;
  final PageCallbacks callbacks;

  @override
  State<EditablePage> createState() => _EditablePageState();
}

class _EditablePageState extends State<EditablePage> {
  ui.Image? _image;
  int _imageWidthPx = 0;
  Future<void>? _loading;
  PageInfo? _info;
  String _infoKey = '';

  // interaction
  _Drag _drag = _Drag.none;
  Offset? _start, _cur;
  final List<Offset> _ink = [];
  String? _handle;
  Map<String, EditOp> _orig = {};
  List<EditOp> _before = const [];
  Offset _grab = Offset.zero;
  Box? _hoverBox;
  bool _hoverIsImage = false;
  _Editing? _editing;
  bool _shift = false;
  int _seenTick = 0;

  PdfDocSession get s => widget.session;
  EditorController get c => widget.ctrl;
  double get scale => widget.scale;
  (double, double) get pageSize => s.pageSize(widget.pageIndex);

  @override
  void initState() {
    super.initState();
    c.addListener(_onCtrl);
    _seenTick = c.commitTick;
    s.addListener(_onSession);
    _ensureInfo();
  }

  @override
  void didUpdateWidget(EditablePage old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_onSession);
      widget.session.addListener(_onSession);
    }
  }

  @override
  void dispose() {
    c.removeListener(_onCtrl);
    s.removeListener(_onSession);
    _editing?.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    _ensureInfo();
    setState(() {});
  }

  void _onCtrl() {
    if (!mounted) return;
    if (c.commitTick != _seenTick) {
      _seenTick = c.commitTick;
      _commitEditing();
    }
    final e = _editing;
    if (e != null) {
      // options-bar changes apply live to the text being edited
      e.family = c.fontFamily;
      e.size = c.fontSize;
      e.bold = c.bold;
      e.italic = c.italic;
      e.argb = c.textColor;
    }
    if (c.tool != EditorTool.text && _editing != null) _commitEditing();
    setState(() {});
  }

  void _ensureInfo() {
    final key = '${s.renderKey}:${widget.pageIndex}';
    if (key == _infoKey) return;
    _infoKey = key;
    final want = key;
    s.pageInfo(widget.pageIndex).then((i) {
      if (mounted && _infoKey == want) setState(() => _info = i);
    }, onError: (Object _) {});
  }

  // ---------------------------------------------------------------- image ---

  void _ensureImage(double dpr) {
    final pxW = math.max(1, (pageSize.$1 * scale * dpr).round());
    final pxH = math.max(1, (pageSize.$2 * scale * dpr).round());
    final hit = PageImageCache.instance.peek(s, widget.pageIndex, pxW, annotations: c.showAnnotations);
    if (hit != null) {
      _image = hit;
      _imageWidthPx = pxW;
      return;
    }
    _image ??= PageImageCache.instance.anySize(s, widget.pageIndex, annotations: c.showAnnotations);
    if (_imageWidthPx == pxW && _loading != null) return;
    _imageWidthPx = pxW;
    final job = PageImageCache.instance.get(s, widget.pageIndex, pxW, pxH, annotations: c.showAnnotations).then((img) {
      if (mounted && _imageWidthPx == pxW) setState(() => _image = img);
    }, onError: (Object _) {});
    _loading = job;
  }

  // ----------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    _ensureImage(dpr);
    final w = pageSize.$1 * scale, h = pageSize.$2 * scale;
    final ops = s.opsOnPage(widget.pageIndex);
    final preview = _previewOp();
    final selected = c.selected;

    final editorCover = _editing?.cover ?? const <Box>[];

    return SizedBox(
      width: w,
      height: h,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: MouseRegion(
          cursor: _cursor(),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerHover: _onHover,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _PageImagePainter(_image)),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: OverlayPainter(
                      ops: ops,
                      scale: scale,
                      selected: selected,
                      preview: preview,
                      hoverBox: _hoverBox,
                      hoverIsImage: _hoverIsImage,
                      hideAnnotations: !c.showAnnotations,
                      hiddenOpId: _editing?.existingOpId,
                      extraCover: editorCover,
                      onImageReady: () {
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ),
                if (_editing != null) _buildEditor(_editing!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  MouseCursor _cursor() {
    switch (c.tool) {
      case EditorTool.text:
        return SystemMouseCursors.text;
      case EditorTool.select:
        return _hoverBox != null ? SystemMouseCursors.move : SystemMouseCursors.basic;
      case EditorTool.deleteImage:
        return _hoverBox != null ? SystemMouseCursors.click : SystemMouseCursors.basic;
      default:
        return SystemMouseCursors.precise;
    }
  }

  // -------------------------------------------------------------- preview ---

  EditOp? _previewOp() {
    final a = _start, b = _cur;
    if (_drag == _Drag.ink && _ink.length > 1) {
      final hl = c.tool == EditorTool.freeHighlight;
      return InkOp(
        id: '_preview',
        page: widget.pageIndex,
        points: [for (final p in _ink) (p.dx, p.dy)],
        argb: c.annotationColors[c.tool] ?? 0xFFE53935,
        width: hl ? 12 : c.strokeWidth,
        highlight: hl,
      );
    }
    if (_drag != _Drag.create || a == null || b == null) return null;
    final box = Box.fromCorners(a.dx, a.dy, b.dx, b.dy);
    switch (c.tool) {
      case EditorTool.whiteout:
        return WhiteoutOp('_preview', widget.pageIndex, box, argb: c.annotationColors[EditorTool.whiteout]!);
      case EditorTool.links:
        return LinkOp('_preview', widget.pageIndex, box, '');
      case EditorTool.ellipse || EditorTool.rectangle || EditorTool.line || EditorTool.arrow:
        return _shapeFrom(a, b, '_preview');
      case EditorTool.strikeout || EditorTool.highlight || EditorTool.underline:
        final rects = _markupRects(box);
        return MarkupOp(
          id: '_preview',
          page: widget.pageIndex,
          kind: _markupKind(c.tool),
          rects: rects,
          argb: c.annotationColors[c.tool] ?? 0xFFFFEB3B,
        );
      default:
        return null;
    }
  }

  MarkupKind _markupKind(EditorTool t) => switch (t) {
        EditorTool.strikeout => MarkupKind.strikeout,
        EditorTool.underline => MarkupKind.underline,
        _ => MarkupKind.highlight,
      };

  ShapeOp _shapeFrom(Offset a, Offset b0, String id) {
    var b = b0;
    if (_shift) {
      if (c.tool == EditorTool.line || c.tool == EditorTool.arrow) {
        final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
        final snapped = (ang / (math.pi / 4)).round() * (math.pi / 4);
        final len = (b - a).distance;
        b = a + Offset(math.cos(snapped), math.sin(snapped)) * len;
      } else {
        final d = math.max((b.dx - a.dx).abs(), (b.dy - a.dy).abs());
        b = Offset(a.dx + d * (b.dx >= a.dx ? 1 : -1), a.dy + d * (b.dy >= a.dy ? 1 : -1));
      }
    }
    return ShapeOp(
      id: id,
      page: widget.pageIndex,
      kind: switch (c.tool) {
        EditorTool.ellipse => ShapeKind.ellipse,
        EditorTool.rectangle => ShapeKind.rectangle,
        EditorTool.line => ShapeKind.line,
        _ => ShapeKind.arrow,
      },
      x1: a.dx,
      y1: a.dy,
      x2: b.dx,
      y2: b.dy,
      strokeArgb: c.strokeColor,
      fillArgb: (c.tool == EditorTool.ellipse || c.tool == EditorTool.rectangle) ? c.fillColor : null,
      width: c.strokeWidth,
    );
  }

  /// Text-run boxes touched by [drag] (falls back to the drag rectangle).
  List<Box> _markupRects(Box drag) {
    final hit = <Box>[];
    for (final line in _info?.lines ?? const <TextLineInfo>[]) {
      for (final r in line.runs) {
        if (r.box.overlaps(drag)) hit.add(r.box);
      }
    }
    return hit.isEmpty ? [drag] : hit;
  }

  // -------------------------------------------------------------- hit tests ---

  Offset _pt(PointerEvent e) => e.localPosition / scale;

  EditOp? _hitOp(Offset p) {
    final tol = 4 / scale;
    for (final op in s.opsOnPage(widget.pageIndex).reversed) {
      if (op is DeleteImageOp) continue;
      if (op is ShapeOp && (op.kind == ShapeKind.line || op.kind == ShapeKind.arrow)) {
        if (_distToSegment(p, Offset(op.x1, op.y1), Offset(op.x2, op.y2)) <= tol + op.width) return op;
        continue;
      }
      if (op is InkOp) {
        for (var i = 1; i < op.points.length; i++) {
          final a = op.points[i - 1], b = op.points[i];
          if (_distToSegment(p, Offset(a.$1, a.$2), Offset(b.$1, b.$2)) <= tol + op.width) return op;
        }
        continue;
      }
      if (op is MarkupOp) {
        if (op.rects.any((r) => r.inflate(tol).contains(p.dx, p.dy))) return op;
        continue;
      }
      if (op.bounds.inflate(tol).contains(p.dx, p.dy)) return op;
    }
    return null;
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  TextLineInfo? _lineAt(Offset p) {
    final replaced = <int>{for (final o in s.opsOnPage(widget.pageIndex)) if (o is TextOp) ...o.removeObjects};
    for (final line in _info?.lines ?? const <TextLineInfo>[]) {
      if (line.objectIndices.every(replaced.contains)) continue;
      if (line.box.inflate(2).contains(p.dx, p.dy)) return line;
    }
    return null;
  }

  PageImageInfo? _imageAt(Offset p) {
    final removed = <int>{for (final o in s.opsOnPage(widget.pageIndex)) if (o is DeleteImageOp) o.objectIndex};
    for (final i in (_info?.images ?? const <PageImageInfo>[]).reversed) {
      if (!removed.contains(i.objectIndex) && i.box.contains(p.dx, p.dy)) return i;
    }
    return null;
  }

  String? _handleAt(Offset p) {
    if (c.selected.length != 1) return null;
    final op = s.opById(c.selected.first);
    if (op == null || op.page != widget.pageIndex) return null;
    final r = OverlayPainter.handlePx / scale;
    for (final h in selectionHandles(op)) {
      if ((p.dx - h.$2).abs() <= r && (p.dy - h.$3).abs() <= r) return h.$1;
    }
    return null;
  }

  // ----------------------------------------------------------- pointer events ---

  void _onHover(PointerHoverEvent e) {
    final p = _pt(e);
    Box? hb;
    var isImg = false;
    switch (c.tool) {
      case EditorTool.text:
        final op = _hitOp(p);
        hb = op is TextOp ? op.bounds : _lineAt(p)?.box;
      case EditorTool.deleteImage:
        hb = _imageAt(p)?.box;
        isImg = true;
      case EditorTool.select:
        final op = _hitOp(p);
        if (op != null && !c.selected.contains(op.id)) hb = op.bounds;
        if (op != null && c.selected.contains(op.id)) hb = op.bounds;
      default:
    }
    if (hb != _hoverBox || isImg != _hoverIsImage) {
      setState(() {
        _hoverBox = hb;
        _hoverIsImage = isImg;
      });
    }
  }

  void _onDown(PointerDownEvent e) {
    _shift = HardwareKeyboard.instance.isShiftPressed;
    c.commitEditingRequest();
    c.setCurrentPage(widget.pageIndex);
    final p = _pt(e);

    if (e.buttons == kSecondaryMouseButton) {
      _contextMenu(e, p);
      return;
    }
    if (e.buttons != kPrimaryMouseButton) return;

    switch (c.tool) {
      case EditorTool.select:
        _selectDown(p);
      case EditorTool.text:
        _textDown(p);
      case EditorTool.links ||
            EditorTool.whiteout ||
            EditorTool.strikeout ||
            EditorTool.highlight ||
            EditorTool.underline ||
            EditorTool.ellipse ||
            EditorTool.rectangle ||
            EditorTool.line ||
            EditorTool.arrow:
        _drag = _Drag.create;
        _start = _cur = p;
        setState(() {});
      case EditorTool.draw || EditorTool.freeHighlight:
        _drag = _Drag.ink;
        _ink
          ..clear()
          ..add(p);
        setState(() {});
      case EditorTool.symbol:
        final size = 18.0;
        final op = SymbolOp(s.newId(), widget.pageIndex, c.symbolKind,
            Box(p.dx - size / 2, p.dy - size / 2, p.dx + size / 2, p.dy + size / 2), c.annotationColors[EditorTool.symbol]!);
        s.addOp(op);
        c.select({op.id});
      case EditorTool.placeImage:
        final pl = c.placing;
        if (pl == null) return;
        final w = pl.widthPt, h = pl.widthPt / pl.aspect;
        final op = ImageOp(s.newId(), widget.pageIndex, Box(p.dx - w / 2, p.dy - h / 2, p.dx + w / 2, p.dy + h / 2), pl.bytes);
        s.addOp(op);
        c.placing = null;
        c.setTool(EditorTool.select);
        c.select({op.id});
      case EditorTool.deleteImage:
        final img = _imageAt(p);
        if (img != null) {
          s.addOp(DeleteImageOp(s.newId(), widget.pageIndex, img.objectIndex, img.box));
          setState(() => _hoverBox = null);
        }
    }
  }

  void _selectDown(Offset p) {
    final handle = _handleAt(p);
    if (handle != null) {
      final op = s.opById(c.selected.first)!;
      _drag = _Drag.resize;
      _handle = handle;
      _orig = {op.id: op};
      _before = s.ops;
      _start = p;
      return;
    }
    final op = _hitOp(p);
    if (op == null) {
      c.select({});
      return;
    }
    if (!c.selected.contains(op.id)) {
      c.select(HardwareKeyboard.instance.isShiftPressed ? {...c.selected, op.id} : {op.id});
    }
    _drag = _Drag.move;
    _orig = {for (final id in c.selected) if (s.opById(id) != null) id: s.opById(id)!};
    _before = s.ops;
    _grab = p;
  }

  void _onMove(PointerMoveEvent e) {
    _shift = HardwareKeyboard.instance.isShiftPressed;
    final p = _pt(e);
    switch (_drag) {
      case _Drag.create:
        setState(() => _cur = p);
      case _Drag.ink:
        if (_ink.isEmpty || (_ink.last - p).distance > 0.6 / math.max(scale, 0.3)) {
          setState(() => _ink.add(p));
        }
      case _Drag.move:
        final d = p - _grab;
        for (final o in _orig.values) {
          s.updateOp(o.moved(d.dx, d.dy), record: false);
        }
      case _Drag.resize:
        final o = _orig.values.first;
        final n = _resized(o, _handle!, p);
        if (n != null) s.updateOp(n, record: false);
      case _Drag.none:
        break;
    }
  }

  void _onUp(PointerUpEvent e) {
    final p = _pt(e);
    final drag = _drag;
    _drag = _Drag.none;
    switch (drag) {
      case _Drag.create:
        _finishCreate(_start!, p);
      case _Drag.ink:
        if (_ink.length > 1) {
          final hl = c.tool == EditorTool.freeHighlight;
          final op = InkOp(
            id: s.newId(),
            page: widget.pageIndex,
            points: [for (final q in _ink) (q.dx, q.dy)],
            argb: c.annotationColors[c.tool] ?? 0xFFE53935,
            width: hl ? 12 : c.strokeWidth,
            highlight: hl,
          );
          s.addOp(op);
        }
        _ink.clear();
      case _Drag.move || _Drag.resize:
        if ((_orig.isNotEmpty) && !identical(_before, s.ops)) s.commit(_before);
        _orig = {};
      case _Drag.none:
        break;
    }
    _start = _cur = null;
    setState(() {});
  }

  void _finishCreate(Offset a, Offset b) {
    final box = Box.fromCorners(a.dx, a.dy, b.dx, b.dy);
    final tiny = box.w < 3 && box.h < 3;
    switch (c.tool) {
      case EditorTool.whiteout:
        if (tiny) return;
        final op = WhiteoutOp(s.newId(), widget.pageIndex, box, argb: c.annotationColors[EditorTool.whiteout]!);
        s.addOp(op);
        c.select({op.id});
      case EditorTool.links:
        if (tiny) return;
        widget.callbacks.askLinkUrl().then((url) {
          if (url == null || url.trim().isEmpty || !mounted) return;
          s.addOp(LinkOp(s.newId(), widget.pageIndex, box, url.trim()));
        });
      case EditorTool.strikeout || EditorTool.highlight || EditorTool.underline:
        if (tiny) return;
        s.addOp(MarkupOp(
          id: s.newId(),
          page: widget.pageIndex,
          kind: _markupKind(c.tool),
          rects: _markupRects(box),
          argb: c.annotationColors[c.tool] ?? 0xFFFFEB3B,
        ));
      case EditorTool.ellipse || EditorTool.rectangle || EditorTool.line || EditorTool.arrow:
        if (tiny) return;
        final op = _shapeFrom(a, b, s.newId());
        s.addOp(op);
        c.select({op.id});
        c.setTool(EditorTool.select);
      default:
    }
  }

  EditOp? _resized(EditOp o, String h, Offset p) {
    if (o is TextOp && h == 'br') {
      final width = math.max(o.bounds.w, 1);
      final f = ((p.dx - o.x) / width).clamp(0.2, 8.0);
      return o.copyWith(size: (o.size * f).clamp(4.0, 300.0), width: o.width * f);
    }
    if (o is ShapeOp && (o.kind == ShapeKind.line || o.kind == ShapeKind.arrow)) {
      return h == 'p1' ? o.copyWith(x1: p.dx, y1: p.dy) : o.copyWith(x2: p.dx, y2: p.dy);
    }
    var b = o.bounds;
    if (o is ShapeOp) b = Box.fromCorners(o.x1, o.y1, o.x2, o.y2);
    var l = b.l, t = b.t, r = b.r, bt = b.b;
    if (h.contains('l')) l = p.dx;
    if (h.contains('r')) r = p.dx;
    if (h == 't' || h == 'tl' || h == 'tr') t = p.dy;
    if (h == 'b' || h == 'bl' || h == 'br') bt = p.dy;
    if (o is ImageOp && h.length == 2) {
      final aspect = b.w / math.max(b.h, 0.01);
      final w = (r - l).abs();
      final hh = w / aspect;
      if (h.contains('t')) {
        t = bt - hh;
      } else {
        bt = t + hh;
      }
    }
    var nb = Box.fromCorners(l, t, r, bt);
    if (nb.w < 3) nb = Box(nb.l, nb.t, nb.l + 3, nb.b);
    if (nb.h < 3) nb = Box(nb.l, nb.t, nb.r, nb.t + 3);
    return switch (o) {
      WhiteoutOp() => o.withBox(nb),
      ImageOp() => o.withBox(nb),
      SymbolOp() => o.withBox(nb),
      LinkOp() => o.withBox(nb),
      ShapeOp() => o.copyWith(x1: nb.l, y1: nb.t, x2: nb.r, y2: nb.b),
      _ => null,
    };
  }

  // ------------------------------------------------------------ context menu ---

  Future<void> _contextMenu(PointerDownEvent e, Offset p) async {
    final op = _hitOp(p);
    if (op == null) return;
    if (!c.selected.contains(op.id)) c.select({op.id});
    final pos = e.position;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      color: AppColors.bgSecondary,
      items: const [
        PopupMenuItem(value: 'dup', child: Text('Duplicate')),
        PopupMenuItem(value: 'del', child: Text('Delete')),
      ],
    );
    if (choice == 'del') s.removeOps(c.selected);
    if (choice == 'dup') {
      final copies = <EditOp>[for (final id in c.selected) s.opById(id)!.moved(10, 10)];
      final fresh = [for (final o in copies) _withNewId(o)];
      s.addOps(fresh);
      c.select({for (final o in fresh) o.id});
    }
  }

  EditOp _withNewId(EditOp o) {
    final j = o.toJson()..['id'] = s.newId();
    return EditOp.fromJson(j);
  }

  // --------------------------------------------------------------- text editing ---

  void _textDown(Offset p) {
    final op = _hitOp(p);
    if (op is TextOp) {
      _startEditing(_Editing(
        family: op.fontFamily,
        size: op.size,
        bold: op.bold,
        italic: op.italic,
        argb: op.argb,
        x: op.x,
        baselineY: op.baselineY,
        text: op.text,
        existingOpId: op.id,
        removeObjects: op.removeObjects,
        cover: op.cover,
      ));
      return;
    }
    final line = _lineAt(p);
    if (line != null) {
      final r = line.first;
      _startEditing(_Editing(
        family: FontCatalog.guessFamily(r.fontName),
        size: r.fontSize,
        bold: r.bold,
        italic: r.italic,
        argb: r.argb,
        x: r.originX,
        baselineY: r.baselineY,
        text: line.text,
        removeObjects: line.objectIndices,
        cover: [line.box],
      ));
      return;
    }
    _startEditing(_Editing(
      family: c.fontFamily,
      size: c.fontSize,
      bold: c.bold,
      italic: c.italic,
      argb: c.textColor,
      x: p.dx,
      baselineY: p.dy + c.fontSize * 0.3,
      text: '',
      isNew: true,
    ));
  }

  void _startEditing(_Editing e) {
    _editing?.dispose();
    setState(() {
      _editing = e;
      _hoverBox = null;
    });
    // push the style of what is being edited into the options bar
    c.adoptTextStyle(e.family, e.size, e.bold, e.italic, e.argb);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing == e) {
        e.focus.requestFocus();
        e.controller.selection = TextSelection(baseOffset: 0, extentOffset: e.controller.text.length);
      }
    });
  }

  void _cancelEditing() {
    _editing?.dispose();
    setState(() => _editing = null);
  }

  /// Called when anything outside the editor is clicked, or the tool changes.
  void commitEditing() => _commitEditing();

  void _commitEditing() {
    final e = _editing;
    if (e == null) return;
    final text = e.controller.text;
    _editing = null;
    EditOp? result;
    if (e.existingOpId != null) {
      final old = s.opById(e.existingOpId!);
      if (old is TextOp) {
        final next = old.copyWith(
          text: text,
          fontFamily: e.family,
          size: e.size,
          bold: e.bold,
          italic: e.italic,
          argb: e.argb,
        );
        final measured = next.copyWith(width: measureTextWidth(next));
        if (text.isEmpty && old.removeObjects.isEmpty) {
          s.removeOps([old.id]);
        } else if (measured.text != old.text ||
            measured.size != old.size ||
            measured.fontFamily != old.fontFamily ||
            measured.bold != old.bold ||
            measured.italic != old.italic ||
            measured.argb != old.argb) {
          s.updateOp(measured);
        }
      }
    } else if (e.isNew) {
      if (text.trim().isNotEmpty) {
        final op = TextOp(
          id: s.newId(),
          page: widget.pageIndex,
          x: e.x,
          baselineY: e.baselineY,
          text: text,
          fontFamily: e.family,
          size: e.size,
          bold: e.bold,
          italic: e.italic,
          argb: e.argb,
        );
        result = op.copyWith(width: measureTextWidth(op));
      }
    } else if (text != e.originalText || e.styleChanged) {
      final op = TextOp(
        id: s.newId(),
        page: widget.pageIndex,
        x: e.x,
        baselineY: e.baselineY,
        text: text,
        fontFamily: e.family,
        size: e.size,
        bold: e.bold,
        italic: e.italic,
        argb: e.argb,
        removeObjects: e.removeObjects,
        cover: e.cover,
      );
      result = op.copyWith(width: measureTextWidth(op));
    }
    e.dispose();
    if (result != null) s.addOp(result);
    if (mounted) setState(() {});
  }

  Widget _buildEditor(_Editing e) {
    final style = previewTextStyle(e.family, e.size * scale, e.bold, e.italic, e.argb);
    final probe = TextPainter(text: TextSpan(text: 'Ag', style: style), textDirection: TextDirection.ltr)..layout();
    final ascent = probe.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    const pad = 3.0;
    final maxW = math.max(80.0, (pageSize.$1 - e.x) * scale);
    return Positioned(
      left: e.x * scale - pad,
      top: e.baselineY * scale - ascent - pad,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 48, maxWidth: maxW),
        child: IntrinsicWidth(
          child: Container(
            padding: const EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: e.isNew ? const Color(0x11FFFFFF) : Colors.white,
              border: Border.all(color: AppColors.accentBlue, width: 1.2),
            ),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _cancelEditing,
                const SingleActivator(LogicalKeyboardKey.enter, control: true): _commitEditing,
              },
              child: EditableText(
                controller: e.controller,
                focusNode: e.focus,
                style: style,
                cursorColor: AppColors.accentBlue,
                backgroundCursorColor: Colors.grey,
                selectionColor: AppColors.accentBlue.withValues(alpha: 0.3),
                maxLines: null,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageImagePainter extends CustomPainter {
  _PageImagePainter(this.image);
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null) return;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_PageImagePainter old) => old.image != image;
}
