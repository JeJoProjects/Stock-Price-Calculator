import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/ocr/excel_extractor.dart';
import 'package:stockcalc/ocr/ocr_models.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('ocr_excel_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  test('extracts a single-sheet workbook as tab-separated rows', () async {
    final workbook = Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet()!;
    workbook.rename(defaultSheet, 'Sheet1');
    workbook.appendRow('Sheet1', [TextCellValue('Symbol'), TextCellValue('Price')]);
    workbook.appendRow('Sheet1', [TextCellValue('AAPL'), IntCellValue(150)]);

    final file = File('${tempDir.path}/one_sheet.xlsx')..writeAsBytesSync(workbook.encode()!);

    final result = await ExcelExtractor().extract(file);

    expect(result.source, OcrInputKind.excel);
    expect(result.text, 'Symbol\tPrice\nAAPL\t150');
  });

  test('prefixes each sheet name when there are multiple sheets', () async {
    final workbook = Excel.createExcel();
    final first = workbook.getDefaultSheet()!;
    workbook.rename(first, 'Alpha');
    workbook.appendRow('Alpha', [TextCellValue('a1')]);
    workbook['Beta'].appendRow([TextCellValue('b1')]);

    final file = File('${tempDir.path}/two_sheets.xlsx')..writeAsBytesSync(workbook.encode()!);

    final result = await ExcelExtractor().extract(file);

    expect(result.text, contains('--- Alpha ---'));
    expect(result.text, contains('--- Beta ---'));
    expect(result.text, contains('a1'));
    expect(result.text, contains('b1'));
  });

  test('extracts csv as plain text', () async {
    final file = File('${tempDir.path}/data.csv')..writeAsStringSync('a,b,c\n1,2,3\n');

    final result = await ExcelExtractor().extract(file);

    expect(result.source, OcrInputKind.excel);
    expect(result.text, 'a,b,c\n1,2,3');
  });

  test('throws extractionFailed for a corrupt xlsx', () async {
    final file = File('${tempDir.path}/corrupt.xlsx')..writeAsBytesSync([1, 2, 3, 4]);

    await expectLater(
      ExcelExtractor().extract(file),
      throwsA(isA<OcrException>().having((e) => e.kind, 'kind', OcrErrorKind.extractionFailed)),
    );
  });
}
