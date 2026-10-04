import 'dart:typed_data';

/// Anything that can turn image bytes into recognized text. Lets OcrService
/// and PdfExtractor stay agnostic to which engine is actually doing the
/// work - today that's TesseractClient (works with zero setup beyond the
/// tesseract.exe install), with OcrSidecarClient (PaddleOCR, higher
/// accuracy, needs the optional Python build step) as a future upgrade
/// once it's wired up in main.dart's engine selection.
abstract class ImageRecognizer {
  Future<String> recognize(Uint8List imageBytes);
}
