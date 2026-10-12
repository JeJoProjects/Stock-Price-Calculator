import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Handwriting fonts bundled for typed signatures (SIL OFL).
const signatureFonts = <(String family, String label)>[
  ('SigGreatVibes', 'Great Vibes'),
  ('SigAllura', 'Allura'),
  ('SigSacramento', 'Sacramento'),
  ('SigKristi', 'Kristi'),
  ('SigMrDafoe', 'Mr Dafoe'),
  ('SigPacifico', 'Pacifico'),
];

Future<Uint8List> _toPng(ui.Picture pic, int w, int h) async {
  final image = await pic.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  pic.dispose();
  return data!.buffer.asUint8List();
}

/// A typed signature as a tightly cropped transparent PNG.
Future<Uint8List> renderTypedSignature(String text, String fontFamily, int argb, {double fontSize = 96}) async {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontFamily: fontFamily, fontSize: fontSize, color: Color(argb))),
    textDirection: TextDirection.ltr,
  )..layout();
  const pad = 16.0;
  final w = (tp.width + pad * 2).ceil(), h = (tp.height + pad * 2).ceil();
  final rec = ui.PictureRecorder();
  tp.paint(Canvas(rec), const Offset(pad, pad));
  return _toPng(rec.endRecording(), w, h);
}

/// Freehand strokes (in any coordinate space) as a cropped transparent PNG.
Future<Uint8List> renderStrokes(List<List<Offset>> strokes, int argb, double width) async {
  final pts = [for (final s in strokes) ...s];
  if (pts.isEmpty) throw const FormatException('Nothing drawn.');
  var l = pts.first.dx, r = l, t = pts.first.dy, b = t;
  for (final p in pts) {
    if (p.dx < l) l = p.dx;
    if (p.dx > r) r = p.dx;
    if (p.dy < t) t = p.dy;
    if (p.dy > b) b = p.dy;
  }
  final pad = width * 2 + 8;
  final w = (r - l + pad * 2).ceil().clamp(8, 4000), h = (b - t + pad * 2).ceil().clamp(8, 4000);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)..translate(pad - l, pad - t);
  final paint = Paint()
    ..color = Color(argb)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  for (final s in strokes) {
    if (s.length == 1) {
      canvas.drawCircle(s.first, width / 2, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    } else if (s.length > 1) {
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length - 1; i++) {
        // smooth through midpoints for a natural pen line
        final mid = Offset((s[i].dx + s[i + 1].dx) / 2, (s[i].dy + s[i + 1].dy) / 2);
        path.quadraticBezierTo(s[i].dx, s[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(s.last.dx, s.last.dy);
      canvas.drawPath(path, paint);
    }
  }
  return _toPng(rec.endRecording(), w, h);
}

/// A rubber-stamp style label: bold caps in a rounded frame, slightly rotated.
Future<Uint8List> renderStamp(String text, int argb, {double fontSize = 64}) async {
  final label = text.trim().toUpperCase();
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
          fontFamily: 'Arial', fontSize: fontSize, fontWeight: FontWeight.w900, color: Color(argb), letterSpacing: fontSize * 0.08),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final padX = fontSize * 0.5, padY = fontSize * 0.32, frame = fontSize * 0.09;
  final w = (tp.width + padX * 2 + frame * 2).ceil(), h = (tp.height + padY * 2 + frame * 2).ceil();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final rect = Rect.fromLTWH(frame, frame, w - frame * 2, h - frame * 2);
  final rr = RRect.fromRectAndRadius(rect, Radius.circular(fontSize * 0.2));
  canvas.drawRRect(
      rr,
      Paint()
        ..color = Color(argb)
        ..style = PaintingStyle.stroke
        ..strokeWidth = frame);
  tp.paint(canvas, Offset(frame + padX, frame + padY));
  return _toPng(rec.endRecording(), w, h);
}

/// Built-in stamp presets: label and colour.
const stampPresets = <(String, int)>[
  ('Draft', 0xFFD32F2F),
  ('Approved', 0xFF2E7D32),
  ('Confidential', 0xFFD32F2F),
  ('Paid', 0xFF2E7D32),
  ('Copy', 0xFF1565C0),
  ('Final', 0xFF1565C0),
  ('Not approved', 0xFFD32F2F),
];
