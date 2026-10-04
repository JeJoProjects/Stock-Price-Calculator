import 'dart:io';
import 'dart:ui' as ui;
import 'package:pdfrx/pdfrx.dart';
import 'image_recognizer.dart';
import 'ocr_models.dart';

/// Minimum characters of extracted text layer a page needs before it's
/// trusted as "digital" rather than scanned/image-only. A handful of
/// stray characters (e.g. a page number watermark) shouldn't count.
const _digitalPageTextThreshold = 8;

/// Per-page PDF handling: pages with a real text layer are extracted
/// directly (exactly as accurate as the source PDF); pages that come back
/// near-empty are treated as scanned and rasterized for OCR. [recognizer]
/// is optional so the UI shell can work before an OCR engine is available -
/// scanned pages fall back to a clear placeholder when it's null.
class PdfExtractor {
  final ImageRecognizer? recognizer;

  PdfExtractor({this.recognizer});

  Future<OcrResult> extract(File file) async {
    final PdfDocument doc;
    try {
      doc = await PdfDocument.openFile(file.path);
    } catch (e) {
      throw OcrException(OcrErrorKind.extractionFailed, 'Could not open this PDF: $e');
    }

    try {
      final pageTexts = <String>[];
      var digitalPages = 0;
      var scannedPages = 0;
      final warnings = <String>[];

      for (var i = 0; i < doc.pages.length; i++) {
        final page = doc.pages[i];
        final pageText = await page.loadText();
        final text = pageText.fullText.trim();

        if (text.length >= _digitalPageTextThreshold) {
          digitalPages++;
          pageTexts.add(text);
          continue;
        }

        scannedPages++;
        if (recognizer == null) {
          pageTexts.add('[Page ${i + 1}: scanned/image content - OCR engine not available]');
          warnings.add('Page ${i + 1} needs OCR, which is not wired up yet.');
          continue;
        }

        final image = await page.render();
        if (image == null) {
          pageTexts.add('[Page ${i + 1}: could not render for OCR]');
          warnings.add('Page ${i + 1} could not be rasterized.');
          continue;
        }
        ui.Image? uiImage;
        try {
          uiImage = await image.createImage();
          final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
          final pngBytes = byteData!.buffer.asUint8List();
          final ocrText = await recognizer!.recognize(pngBytes);
          pageTexts.add(ocrText.trim());
        } finally {
          uiImage?.dispose();
          image.dispose();
        }
      }

      final kind = switch ((digitalPages > 0, scannedPages > 0)) {
        (true, false) => OcrInputKind.digitalPdf,
        (false, true) => OcrInputKind.scannedPdf,
        _ => OcrInputKind.mixedPdf,
      };

      final multiPage = doc.pages.length > 1;
      final text = multiPage
          ? [
              for (var i = 0; i < pageTexts.length; i++) '--- Page ${i + 1} ---\n${pageTexts[i]}',
            ].join('\n\n')
          : pageTexts.join('\n\n');

      return OcrResult(
        text: text.trim(),
        source: kind,
        pageCount: doc.pages.length,
        warnings: warnings,
      );
    } finally {
      doc.dispose();
    }
  }
}
