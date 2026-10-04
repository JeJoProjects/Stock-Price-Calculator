import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'image_recognizer.dart';
import 'ocr_models.dart';

/// Talks to the local Python OCR sidecar (PaddleOCR) over HTTP. The
/// sidecar is launched by OcrSidecarLauncher - this client assumes it's
/// already reachable and just does the recognize() call itself.
class OcrSidecarClient implements ImageRecognizer {
  final String baseUrl;
  final http.Client _http;

  OcrSidecarClient({this.baseUrl = 'http://127.0.0.1:8091', http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  @override
  Future<String> recognize(Uint8List imageBytes) async {
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$baseUrl/ocr'),
            headers: {'content-type': 'application/octet-stream'},
            body: imageBytes,
          )
          .timeout(const Duration(seconds: 30));
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

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      throw OcrException(OcrErrorKind.extractionFailed, 'OCR engine returned an unreadable response: $e');
    }

    final text = body['text'];
    if (text is! String) {
      throw const OcrException(
          OcrErrorKind.extractionFailed, 'OCR engine response was missing recognized text.');
    }
    return text;
  }
}
