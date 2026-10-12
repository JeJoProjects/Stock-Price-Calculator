// Writes a synthetic, statement-like PDF (invented data) for trying out the
// PDF Editor tab:  dart run tool/make_sample_pdf.dart <output.pdf> [pages]
import 'dart:io';
import 'package:stockcalc/pdfedit/pdfium_edit.dart';

void main(List<String> args) {
  final out = args.isNotEmpty ? args[0] : 'sample_statement.pdf';
  final pages = args.length > 1 ? int.parse(args[1]) : 2;
  final doc = PdfiumDoc.createBlank(pages: pages);
  final helv = doc.standardFont('Helvetica');
  final bold = doc.standardFont('Helvetica-Bold');
  for (var i = 0; i < pages; i++) {
    final p = doc.loadPage(i);
    p.addText('Example Bank AG', 56, 790, 20, bold, 0xFF0D47A1);
    p.addText('Max Mustermann', 56, 750, 12, bold, 0xFF000000);
    p.addText('Musterstrasse 1', 56, 735, 12, helv, 0xFF000000);
    p.addText('12345 Musterstadt', 56, 720, 12, helv, 0xFF000000);
    p.addText('Account statement ${i + 1}/$pages', 56, 670, 16, bold, 0xFF000000);
    p.addPolyline([(56, 640), (539, 640), (539, 600), (56, 600)], fillArgb: 0xFFEEEEEE, closed: true);
    p.addText('Balance', 66, 616, 14, bold, 0xFF000000);
    p.addText('1.234,56 \u20AC', 440, 616, 14, bold, 0xFF000000);
    var y = 570.0;
    for (final (d, t, a) in const [
      ('03.08.', 'Transfer Example Shop', '-45,90 \u20AC'),
      ('05.08.', 'Direct debit Utilities GmbH', '-123,00 \u20AC'),
      ('12.08.', 'Salary Example Corp', '+2.450,00 \u20AC'),
      ('19.08.', 'Card payment Supermarket', '-67,35 \u20AC'),
      ('28.08.', 'Transfer Rent', '-850,00 \u20AC'),
    ]) {
      p.addText(d, 56, y, 11, helv, 0xFF000000);
      p.addText(t, 110, y, 11, helv, 0xFF000000);
      p.addText(a, 450, y, 11, helv, 0xFF000000);
      y -= 22;
    }
    p.addText('Page ${i + 1} of $pages', 250, 40, 9, helv, 0xFF666666);
    p.generateContent();
    p.close();
  }
  File(out).writeAsBytesSync(doc.save());
  doc.close();
  stdout.writeln('wrote $out');
}
