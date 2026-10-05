import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'image_recognizer.dart';
import 'number_consensus.dart';
import 'ocr_models.dart';

/// Talks to the local Python OCR sidecar (PaddleOCR) over HTTP. The
/// sidecar is launched by OcrSidecarLauncher - this client assumes it's
/// already reachable and just does the recognize() call itself.
class OcrSidecarClient implements ImageRecognizer, BoxRecognizer {
  final String baseUrl;
  final http.Client _http;

  OcrSidecarClient({this.baseUrl = 'http://127.0.0.1:8091', http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  // The sidecar already parallelizes internally and serializes requests.
  @override
  int get preferredConcurrency => 1;

  Future<Map<String, dynamic>> _post(Uint8List imageBytes) async {
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$baseUrl/ocr'),
            headers: {'content-type': 'application/octet-stream'},
            body: imageBytes,
          )
          .timeout(const Duration(seconds: 90));
    } on Exception {
      throw const OcrException(
          OcrErrorKind.engineUnavailable, 'The OCR engine is not reachable right now.');
    }

    if (res.statusCode == 503) {
      throw const OcrException(
          OcrErrorKind.engineUnavailable, 'The OCR engine is still warming up - try again shortly.');
    }
    if (res.statusCode != 200) {
      throw OcrException(
          OcrErrorKind.extractionFailed, 'OCR engine returned an error (${res.statusCode}).');
    }

    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      throw OcrException(OcrErrorKind.extractionFailed, 'OCR engine returned an unreadable response: $e');
    }
  }

  @override
  Future<String> recognize(Uint8List imageBytes) async {
    final body = await _post(imageBytes);
    final text = body['text'];
    if (text is! String) {
      throw const OcrException(
          OcrErrorKind.extractionFailed, 'OCR engine response was missing recognized text.');
    }
    return text;
  }

  /// Per-line boxes from the sidecar's `items` field. Each is a whole text
  /// line (PaddleOCR detects lines, not words), which is enough to confirm
  /// the numbers inside it by position.
  @override
  Future<List<OcrBox>> recognizeBoxes(Uint8List imageBytes) async {
    final body = await _post(imageBytes);
    final items = body['items'];
    if (items is! List) return const [];
    return [
      for (final i in items)
        if (i is Map<String, dynamic> && i['t'] is String)
          OcrBox(i['t'] as String, (i['x'] as num).toDouble(), (i['y'] as num).toDouble(),
              ((i['x2'] as num) - (i['x'] as num)).toDouble(), (i['h'] as num).toDouble()),
    ];
  }
}
