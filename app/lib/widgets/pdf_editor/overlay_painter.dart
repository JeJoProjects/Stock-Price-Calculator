import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../pdfedit/edit_model.dart';
import 'page_renderer.dart';

/// Flutter font family used to preview a PDF font family.
String previewFontFamily(String family) => switch (family) {
      'Helvetica' => 'Arial',
      'Times' => 'Times New Roman',
      'Courier' => 'Courier New',
      _ => family,
    };

TextStyle previewTextStyle(String family, double size, bool bold, bool italic, int argb) => TextStyle(
      fontFamily: previewFontFamily(family),
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: Color(argb),
      height: 1.2,
      leadingDistribution: TextLeadingDistribution.even,
    );

/// Lays out [op]'s text and returns the painter plus the distance from its
/// top to the first baseline, so the baseline can be placed exactly.
(TextPainter, double) layoutText(TextOp op) {
  final tp = TextPainter(
    text: TextSpan(text: op.text, style: previewTextStyle(op.fontFamily, op.size, op.bold, op.italic, op.argb)),
    textDirection: TextDirection.ltr,
  )..layout();
  return (tp, tp.computeDistanceToActualBaseline(TextBaseline.alphabetic));
}

/// Measured width of the op's longest line, in points.
double measureTextWidth(TextOp op) => layoutText(op).$1.width;

const paper = Color(0xFFFFFFFF);

/// Paints the overlay edits of one page. Works in page points: the canvas is
/// scaled by [scale] (pixels per point) before drawing.
class OverlayPainter extends CustomPainter {
  OverlayPainter({
    required this.ops,
    required this.scale,
    required this.selected,
    required this.onImageReady,
    this.preview,
    this.hoverBox,
    this.hoverIsImage = false,
    this.hideAnnotations = false,
    this.hiddenOpId,
    this.extraCover = const [],
    super.repaint,
  });

  final List<EditOp> ops;
  final double scale;
  final Set<String> selected;
  final void Function() onImageReady;
  final EditOp? preview;
  final Box? hoverBox;
  final bool hoverIsImage;
  final bool hideAnnotations;

  /// Op being edited inline (its text is drawn by the editor instead).
  final String? hiddenOpId;

  /// Page areas painted paper-white (original text under inline edit).
  final List<Box> extraCover;

  static const handlePx = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    for (final c in extraCover) {
      canvas.drawRect(_rect(c).inflate(0.5), Paint()..color = paper);
    }
    for (final op in ops) {
      if (op.id == hiddenOpId) {
        if (op is TextOp) _paintCover(canvas, op);
        continue;
      }
      if (hideAnnotations && (op is MarkupOp || op is InkOp || op is ShapeOp)) continue;
      _paintOp(canvas, op);
    }
    if (preview != null) _paintOp(canvas, preview!, isPreview: true);
    if (hoverBox != null) {
      final r = _rect(hoverBox!);
      canvas.drawRect(
        r.inflate(1),
        Paint()
          ..color = const Color(0xFF2962FF).withValues(alpha: hoverIsImage ? 0.18 : 0.12)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        r.inflate(1),
        Paint()
          ..color = const Color(0xFF2962FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale,
      );
    }
    canvas.restore();

    for (final op in ops) {
      if (selected.contains(op.id)) _paintSelection(canvas, op);
    }
  }

  static Rect _rect(Box b) => Rect.fromLTRB(b.l, b.t, b.r, b.b);

  void _paintCover(Canvas canvas, TextOp op) {
    for (final c in op.cover) {
      canvas.drawRect(_rect(c).inflate(0.5), Paint()..color = paper);
    }
  }

  void _paintOp(Canvas canvas, EditOp op, {bool isPreview = false}) {
    switch (op) {
      case TextOp():
        _paintCover(canvas, op);
        if (op.text.isEmpty) return;
        final (tp, base) = layoutText(op);
        tp.paint(canvas, Offset(op.x, op.baselineY - base));
      case WhiteoutOp():
        canvas.drawRect(_rect(op.box), Paint()..color = Color(op.argb));
        if (isPreview) {
          canvas.drawRect(
              _rect(op.box),
              Paint()
                ..color = const Color(0x552962FF)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1 / scale);
        }
      case ShapeOp():
        _paintShape(canvas, op);
      case MarkupOp():
        for (final r in op.rects) {
          final rect = _rect(r);
          switch (op.kind) {
            case MarkupKind.highlight:
              canvas.drawRect(
                  rect,
                  Paint()
                    ..color = Color(op.argb).withValues(alpha: 0.55)
                    ..blendMode = BlendMode.multiply);
            case MarkupKind.underline:
              canvas.drawLine(Offset(rect.left, rect.bottom - 0.5), Offset(rect.right, rect.bottom - 0.5),
                  Paint()..color = Color(op.argb)..strokeWidth = 1);
            case MarkupKind.strikeout:
              canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy),
                  Paint()..color = Color(op.argb)..strokeWidth = 1);
          }
        }
      case InkOp():
        if (op.points.length < 2) return;
        final path = Path()..moveTo(op.points.first.$1, op.points.first.$2);
        for (final p in op.points.skip(1)) {
          path.lineTo(p.$1, p.$2);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = op.highlight ? Color(op.argb).withValues(alpha: 0.4) : Color(op.argb)
            ..style = PaintingStyle.stroke
            ..strokeWidth = op.width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..blendMode = op.highlight ? BlendMode.multiply : BlendMode.srcOver,
        );
      case ImageOp():
        final img = OverlayImageCache.instance.get(op.data, onImageReady);
        if (img != null) {
          canvas.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            _rect(op.box),
            Paint()..filterQuality = FilterQuality.medium,
          );
        } else {
          canvas.drawRect(_rect(op.box), Paint()..color = const Color(0x22000000));
        }
      case SymbolOp():
        _paintSymbol(canvas, op);
      case LinkOp():
        final r = _rect(op.box);
        canvas.drawRect(r, Paint()..color = const Color(0x142962FF));
        canvas.drawRect(
            r,
            Paint()
              ..color = const Color(0xAA2962FF)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1 / scale);
      case DeleteImageOp():
        canvas.drawRect(_rect(op.box), Paint()..color = paper);
    }
  }

  void _paintShape(Canvas canvas, ShapeOp s) {
    final stroke = Paint()
      ..color = Color(s.strokeArgb)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = s.fillArgb == null ? null : (Paint()..color = Color(s.fillArgb!));
    final b = Box.fromCorners(s.x1, s.y1, s.x2, s.y2);
    switch (s.kind) {
      case ShapeKind.rectangle:
        if (fill != null) canvas.drawRect(_rect(b), fill);
        canvas.drawRect(_rect(b), stroke);
      case ShapeKind.ellipse:
        if (fill != null) canvas.drawOval(_rect(b), fill);
        canvas.drawOval(_rect(b), stroke);
      case ShapeKind.line:
        canvas.drawLine(Offset(s.x1, s.y1), Offset(s.x2, s.y2), stroke);
      case ShapeKind.arrow:
        canvas.drawLine(Offset(s.x1, s.y1), Offset(s.x2, s.y2), stroke);
        final ang = math.atan2(s.y2 - s.y1, s.x2 - s.x1);
        final len = math.max(8.0, s.width * 4);
        Offset head(double da) => Offset(s.x2 - len * math.cos(ang + da), s.y2 - len * math.sin(ang + da));
        canvas.drawPath(
            Path()
              ..moveTo(head(0.45).dx, head(0.45).dy)
              ..lineTo(s.x2, s.y2)
              ..lineTo(head(-0.45).dx, head(-0.45).dy),
            stroke);
    }
  }

  void _paintSymbol(Canvas canvas, SymbolOp s) {
    final b = s.box;
    final w = math.max(1.0, math.min(b.w, b.h) * 0.14);
    final p = Paint()
      ..color = Color(s.argb)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (s.kind) {
      case SymbolKind.cross:
        canvas.drawLine(Offset(b.l + b.w * .12, b.t + b.h * .12), Offset(b.r - b.w * .12, b.b - b.h * .12), p);
        canvas.drawLine(Offset(b.r - b.w * .12, b.t + b.h * .12), Offset(b.l + b.w * .12, b.b - b.h * .12), p);
      case SymbolKind.check:
        canvas.drawPath(
            Path()
              ..moveTo(b.l + b.w * .1, b.t + b.h * .55)
              ..lineTo(b.l + b.w * .38, b.b - b.h * .12)
              ..lineTo(b.r - b.w * .08, b.t + b.h * .12),
            p);
      case SymbolKind.square:
        canvas.drawRect(_rect(b), Paint()..color = Color(s.argb));
      case SymbolKind.dot:
        canvas.drawOval(_rect(b), Paint()..color = Color(s.argb));
    }
  }

  /// Selection frame and resize handles, drawn in pixels (not points).
  void _paintSelection(Canvas canvas, EditOp op) {
    final b = op.bounds;
    final r = Rect.fromLTRB(b.l * scale, b.t * scale, b.r * scale, b.b * scale);
    final frame = Paint()
      ..color = const Color(0xFF2962FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRect(r, frame);
    for (final h in selectionHandles(op)) {
      final c = Offset(h.$2 * scale, h.$3 * scale);
      final hr = Rect.fromCenter(center: c, width: handlePx, height: handlePx);
      canvas.drawRect(hr, Paint()..color = Colors.white);
      canvas.drawRect(hr, frame);
    }
  }

  @override
  bool shouldRepaint(OverlayPainter old) => true;
}

/// Where resize handles sit for [op], in page points: (id, x, y).
List<(String, double, double)> selectionHandles(EditOp op) {
  final b = op.bounds;
  switch (op) {
    case ShapeOp(kind: ShapeKind.line) || ShapeOp(kind: ShapeKind.arrow):
      final s = op;
      return [('p1', s.x1, s.y1), ('p2', s.x2, s.y2)];
    case TextOp():
      return [('br', b.r, b.b)]; // drag to change font size
    case MarkupOp() || InkOp() || DeleteImageOp():
      return const [];
    default:
      return [
        ('tl', b.l, b.t),
        ('t', b.cx, b.t),
        ('tr', b.r, b.t),
        ('r', b.r, b.cy),
        ('br', b.r, b.b),
        ('b', b.cx, b.b),
        ('bl', b.l, b.b),
        ('l', b.l, b.cy),
      ];
  }
}
