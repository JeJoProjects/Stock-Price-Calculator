import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// A grayscale, resampled copy of the source page, as a binary PGM (which
/// Tesseract reads natively - no PNG encode needed).
class ScaledImage {
  final double scale;
  final Uint8List pgm;

  const ScaledImage(this.scale, this.pgm);
}

class ImageVariants {
  final int width;
  final List<ScaledImage> scaled;

  const ImageVariants(this.width, this.scaled);
}

/// Decodes [bytes] once and produces a grayscale copy at each of [scales].
/// Runs off the UI isolate. Returns null if the bytes aren't a decodable
/// image, so callers can fall back to the single primary pass.
Future<ImageVariants?> makeScaledVariants(Uint8List bytes, List<double> scales) {
  return Isolate.run(() {
    // The decoder throws (not returns null) on some malformed input.
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } on Object {
      return null;
    }
    if (decoded == null) return null;
    final w = decoded.width, h = decoded.height;
    final gray = _toGray(decoded);
    return ImageVariants(w, [
      for (final s in scales) ScaledImage(s, _toPgm(resizeGrayBilinear(gray, w, h, s))),
    ]);
  });
}

Uint8List _toGray(img.Image image) {
  final w = image.width, h = image.height;
  final rgb = image.getBytes(order: img.ChannelOrder.rgb);
  final gray = Uint8List(w * h);
  if (image.numChannels == 1) {
    return Uint8List.fromList(image.getBytes());
  }
  final step = rgb.length ~/ (w * h);
  for (var i = 0, j = 0; i < gray.length; i++, j += step) {
    // Rec.601 luma, integer math.
    gray[i] = (rgb[j] * 77 + rgb[j + 1] * 150 + rgb[j + 2] * 29) >> 8;
  }
  return gray;
}

/// Bilinear resample of an 8-bit grayscale image by [scale].
({Uint8List data, int width, int height}) resizeGrayBilinear(
    Uint8List src, int w, int h, double scale) {
  final nw = (w * scale).round(), nh = (h * scale).round();
  final out = Uint8List(nw * nh);
  final xi0 = Int32List(nw), xi1 = Int32List(nw);
  final xf = Float32List(nw);
  for (var x = 0; x < nw; x++) {
    final fx = ((x + 0.5) / scale - 0.5).clamp(0.0, w - 1.0);
    final x0 = fx.floor();
    xi0[x] = x0;
    xi1[x] = x0 + 1 < w ? x0 + 1 : x0;
    xf[x] = fx - x0;
  }
  for (var y = 0; y < nh; y++) {
    final fy = ((y + 0.5) / scale - 0.5).clamp(0.0, h - 1.0);
    final y0 = fy.floor();
    final y1 = y0 + 1 < h ? y0 + 1 : y0;
    final wy = fy - y0;
    final r0 = y0 * w, r1 = y1 * w, o = y * nw;
    for (var x = 0; x < nw; x++) {
      final a = src[r0 + xi0[x]] + (src[r0 + xi1[x]] - src[r0 + xi0[x]]) * xf[x];
      final b = src[r1 + xi0[x]] + (src[r1 + xi1[x]] - src[r1 + xi0[x]]) * xf[x];
      out[o + x] = (a + (b - a) * wy + 0.5).toInt();
    }
  }
  return (data: out, width: nw, height: nh);
}

Uint8List _toPgm(({Uint8List data, int width, int height}) g) {
  final header = 'P5\n${g.width} ${g.height}\n255\n'.codeUnits;
  return Uint8List(header.length + g.data.length)
    ..setRange(0, header.length, header)
    ..setRange(header.length, header.length + g.data.length, g.data);
}
