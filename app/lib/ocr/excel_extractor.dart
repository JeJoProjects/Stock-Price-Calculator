import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'ocr_models.dart';

/// Direct cell-text extraction for spreadsheet files - no OCR involved,
/// so this is exactly as accurate as the source file's own text.
class ExcelExtractor {
  Future<OcrResult> extract(File file) async {
    final path = file.path.toLowerCase();
    if (path.endsWith('.csv')) return _extractCsv(file);
    return _extractWorkbook(file);
  }

  Future<OcrResult> _extractCsv(File file) async {
    final text = await file.readAsString();
    return OcrResult(text: text.trim(), source: OcrInputKind.excel);
  }

  Future<OcrResult> _extractWorkbook(File file) async {
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on IOException catch (e) {
      throw OcrException(OcrErrorKind.extractionFailed, 'Could not read the file: $e');
    }

    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (e) {
      throw OcrException(OcrErrorKind.extractionFailed, 'Could not parse this spreadsheet: $e');
    }

    final buffer = StringBuffer();
    final multiSheet = workbook.sheets.length > 1;
    for (final sheetName in workbook.sheets.keys) {
      final sheet = workbook.sheets[sheetName]!;
      if (multiSheet) {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.writeln('--- $sheetName ---');
      }
      for (final row in sheet.rows) {
        final cells = row.map((cell) => cell?.value?.toString() ?? '').toList();
        // Drop fully-empty trailing cells so sparse sheets don't produce
        // rows of bare tabs.
        while (cells.isNotEmpty && cells.last.isEmpty) {
          cells.removeLast();
        }
        if (cells.isEmpty) continue;
        buffer.writeln(cells.join('\t'));
      }
    }

    return OcrResult(text: buffer.toString().trim(), source: OcrInputKind.excel);
  }
}
