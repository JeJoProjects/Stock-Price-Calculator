import 'ocr_models.dart';

const _imageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'};
const _excelExtensions = {'xlsx', 'xls', 'csv'};

/// Classifies a file purely by extension. PDFs can't be fully classified
/// this way - [OcrInputKind.digitalPdf]/[scannedPdf]/[mixedPdf] are only
/// decided after inspecting pages (see PdfExtractor), so a `.pdf` here just
/// confirms "this needs PDF handling", not which kind.
OcrInputKind classifyByPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return OcrInputKind.unsupported;
  final ext = path.substring(dot + 1).toLowerCase();

  if (_imageExtensions.contains(ext)) return OcrInputKind.imageForOcr;
  if (_excelExtensions.contains(ext)) return OcrInputKind.excel;
  if (ext == 'pdf') return OcrInputKind.digitalPdf; // placeholder; PdfExtractor refines this
  return OcrInputKind.unsupported;
}

bool isPdfPath(String path) => path.toLowerCase().endsWith('.pdf');

bool isSupportedPath(String path) => classifyByPath(path) != OcrInputKind.unsupported;
