import 'dart:typed_data';

/// Anything that can turn image bytes into recognized text. Lets OcrService
/// and PdfExtractor stay agnostic to which engine is actually doing the
/// work - today that's TesseractClient (works with zero setup beyond the
/// tesseract.exe install), with OcrSidecarClient (PaddleOCR, higher
/// accuracy, needs the optional Python build step) as a future upgrade
/// once it's wired up in main.dart's engine selection.
abstract class ImageRecognizer {
  Future<String> recognize(Uint8List imageBytes);

  /// How many recognize() calls may safely run at once. Engines that already
  /// use every core internally (or serialize requests) keep the default of 1.
  int get preferredConcurrency => 1;
}
