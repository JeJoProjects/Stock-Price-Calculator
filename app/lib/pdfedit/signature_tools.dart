/// Pure-Dart image helpers for signatures (no UI dependency, unit-testable).
library;

import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Turns the (near-)white paper of a scanned/photographed signature into
/// transparency and trims the empty border, so it can sit on any page.
/// Dark ink keeps full opacity; light grey fades out smoothly.
Uint8List removeBackground(Uint8List encoded, {int whiteThreshold = 235, int padding = 6}) {
  final img.Image? src;
  try {
    src = img.decodeImage(encoded);
  } on Object {
    throw const FormatException('Unsupported image.');
  }
  if (src == null) throw const FormatException('Unsupported image.');
  final im = src.convert(numChannels: 4, format: img.Format.uint8);
  var minX = im.width, minY = im.height, maxX = -1, maxY = -1;
  for (final p in im) {
    final lum = (p.r * 0.299 + p.g * 0.587 + p.b * 0.114);
    var alpha = p.a.toInt();
    if (lum >= whiteThreshold) {
      alpha = 0;
    } else if (lum > whiteThreshold - 60) {
      // soft edge: fade between "ink" and "paper"
      alpha = (alpha * (whiteThreshold - lum) / 60).round().clamp(0, 255);
    }
    p.a = alpha;
    if (alpha > 8) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
  }
  if (maxX < 0) return Uint8List.fromList(img.encodePng(im)); // all paper: nothing to crop
  final x = (minX - padding).clamp(0, im.width - 1);
  final y = (minY - padding).clamp(0, im.height - 1);
  final w = (maxX + padding).clamp(0, im.width - 1) - x + 1;
  final h = (maxY + padding).clamp(0, im.height - 1) - y + 1;
  return Uint8List.fromList(img.encodePng(img.copyCrop(im, x: x, y: y, width: w, height: h)));
}

/// Width / height of an encoded image, or null if it cannot be decoded.
double? imageAspect(Uint8List encoded) {
  try {
    final d = img.decodeImage(encoded);
    if (d == null || d.height == 0) return null;
    return d.width / d.height;
  } on Object {
    return null; // the decoder throws on some malformed input
  }
}
