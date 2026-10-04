import 'dart:io';
import 'excel_extractor.dart';
import 'file_classifier.dart';
import 'image_recognizer.dart';
import 'ocr_models.dart';
import 'pdf_extractor.dart';

const _maxFileSizeBytes = 50 * 1024 * 1024; // 50MB

/// The single entry point the OCR tab calls: classifies a file and routes
/// it to the right extractor. [recognizer] is optional so the tab works
/// (for Excel and digitally-generated PDFs) before an OCR engine is
/// available, and is whichever engine main.dart resolved at startup -
/// TesseractClient today, OcrSidecarClient (PaddleOCR) once that's built.
class OcrService {
  final ImageRecognizer? recognizer;

  OcrService({this.recognizer});

  int get concurrency => recognizer?.preferredConcurrency ?? 1;

  Future<OcrResult> extract(File file) async {
    final length = await file.length();
    if (length > _maxFileSizeBytes) {
      throw OcrException(
        OcrErrorKind.fileTooLarge,
        'This file is ${(length / (1024 * 1024)).toStringAsFixed(1)}MB - '
            'the limit is ${_maxFileSizeBytes ~/ (1024 * 1024)}MB.',
      );
    }

    final path = file.path;
    if (isPdfPath(path)) {
      return PdfExtractor(recognizer: recognizer).extract(file);
    }

    final kind = classifyByPath(path);
    switch (kind) {
      case OcrInputKind.excel:
        return ExcelExtractor().extract(file);
      case OcrInputKind.imageForOcr:
        return _extractImage(file);
      case OcrInputKind.digitalPdf:
      case OcrInputKind.scannedPdf:
      case OcrInputKind.mixedPdf:
      case OcrInputKind.unsupported:
        throw const OcrException(
            OcrErrorKind.unsupportedType, 'This file type is not supported yet.');
    }
  }

  Future<OcrResult> _extractImage(File file) async {
    if (recognizer == null) {
      throw const OcrException(
          OcrErrorKind.engineUnavailable, 'No OCR engine found. Install Tesseract (winget install UB-Mannheim.TesseractOCR) '
              'and restart the app, or build the PaddleOCR sidecar with run_flutter.bat --rebuild-ocr.');
    }
    final bytes = await file.readAsBytes();
    final text = await recognizer!.recognize(bytes);
    return OcrResult(text: text.trim(), source: OcrInputKind.imageForOcr);
  }
}
