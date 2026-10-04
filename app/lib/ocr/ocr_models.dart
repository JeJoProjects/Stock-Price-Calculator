/// Shared types for the OCR tab - file classification, the extracted
/// result, and typed failure reasons so the UI can show a specific,
/// actionable message instead of a generic "something went wrong".
library;

/// What kind of handling a dropped/picked/pasted file needs. PDFs resolve
/// to [digitalPdf]/[scannedPdf]/[mixedPdf] only after inspecting their
/// pages - see PdfExtractor.
enum OcrInputKind { imageForOcr, digitalPdf, scannedPdf, mixedPdf, excel, unsupported }

enum OcrErrorKind { unsupportedType, fileTooLarge, engineUnavailable, extractionFailed, timeout }

class OcrException implements Exception {
  final OcrErrorKind kind;
  final String message;

  const OcrException(this.kind, this.message);

  @override
  String toString() => message;
}

/// The outcome of one extract() call. [warnings] surfaces non-fatal notes,
/// e.g. a PDF page whose OCR'd text looked unusually short.
class OcrResult {
  final String text;
  final OcrInputKind source;
  final int pageCount;
  final List<String> warnings;

  const OcrResult({
    required this.text,
    required this.source,
    this.pageCount = 1,
    this.warnings = const [],
  });
}
