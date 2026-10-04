import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/ocr/file_classifier.dart';
import 'package:stockcalc/ocr/ocr_models.dart';

void main() {
  group('classifyByPath', () {
    test('images', () {
      for (final ext in ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif']) {
        expect(classifyByPath('photo.$ext'), OcrInputKind.imageForOcr, reason: ext);
      }
    });

    test('excel/csv', () {
      for (final ext in ['xlsx', 'xls', 'csv']) {
        expect(classifyByPath('sheet.$ext'), OcrInputKind.excel, reason: ext);
      }
    });

    test('pdf resolves to a placeholder digitalPdf kind', () {
      expect(classifyByPath('doc.pdf'), OcrInputKind.digitalPdf);
    });

    test('is case-insensitive', () {
      expect(classifyByPath('PHOTO.PNG'), OcrInputKind.imageForOcr);
      expect(classifyByPath('SHEET.XLSX'), OcrInputKind.excel);
    });

    test('unknown extension is unsupported', () {
      expect(classifyByPath('notes.txt'), OcrInputKind.unsupported);
      expect(classifyByPath('archive.docx'), OcrInputKind.unsupported);
    });

    test('no extension is unsupported', () {
      expect(classifyByPath('README'), OcrInputKind.unsupported);
      expect(classifyByPath('trailing.'), OcrInputKind.unsupported);
    });
  });

  group('isPdfPath', () {
    test('matches regardless of case', () {
      expect(isPdfPath('a.pdf'), isTrue);
      expect(isPdfPath('a.PDF'), isTrue);
      expect(isPdfPath('a.png'), isFalse);
    });
  });

  group('isSupportedPath', () {
    test('true for every supported kind, false for unsupported', () {
      expect(isSupportedPath('a.png'), isTrue);
      expect(isSupportedPath('a.xlsx'), isTrue);
      expect(isSupportedPath('a.pdf'), isTrue);
      expect(isSupportedPath('a.docx'), isFalse);
    });
  });
}
