import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/ocr/number_consensus.dart';
import 'package:stockcalc/ocr/tesseract_client.dart';

const kVerifierWeight = TesseractClient.verifierWeight;

/// One-line page: words laid out left to right at y=100.
List<OcrBox> row(List<String> words, {double y = 100, double x0 = 100}) {
  final out = <OcrBox>[];
  var x = x0;
  for (final w in words) {
    final width = w.length * 12.0;
    out.add(OcrBox(w, x, y, width, 20));
    x += width + 14;
  }
  return out;
}

String fix(String text, List<OcrBox> primary, List<NumberVoter> voters) =>
    applyNumberConsensus(text, primary, voters, 1600).text;

void main() {
  const text = 'Garantierte Rente 1.271,52 EUR\n';
  const fixedText = 'Garantierte Rente 1.277,52 EUR\n';
  final primary = row(['Garantierte', 'Rente', '1.271,52', 'EUR']);
  final right = row(['Garantierte', 'Rente', '1.277,52', 'EUR']);
  final wrongAgain = row(['Garantierte', 'Rente', '1.271,52', 'EUR']);

  test('a digit slip is corrected when the other readings agree', () {
    expect(fix(text, primary, [NumberVoter(right, 1), NumberVoter(right, 1)]), fixedText);
  });

  test('one dissenting voter cannot overrule the primary reading', () {
    expect(fix(text, primary, [NumberVoter(right, 1)]), text); // 1 vs 1: tie keeps primary
  });

  test('verifier + one Tesseract pass beat primary + one pass', () {
    expect(
      fix(text, primary,
          [NumberVoter(wrongAgain, 1), NumberVoter(right, 1), NumberVoter(right, kVerifierWeight)]),
      fixedText,
    );
  });

  test('the verifier alone cannot overrule unanimous Tesseract readings', () {
    expect(
      fix(text, primary,
          [NumberVoter(wrongAgain, 1), NumberVoter(wrongAgain, 1), NumberVoter(right, kVerifierWeight)]),
      text,
    );
  });

  test('a well-formed amount is never rewritten into a dot-decimal one', () {
    final dotted = row(['Garantierte', 'Rente', '1.271.52', 'EUR']);
    final good = row(['Garantierte', 'Rente', '1.277,52', 'EUR']);
    // Verifier + one pass say "1.271.52" (comma->dot slip) against primary + one pass.
    expect(
      fix('Garantierte Rente 1.277,52 EUR\n', good, [NumberVoter(good, 1), NumberVoter(dotted, 1), NumberVoter(dotted, kVerifierWeight)]),
      'Garantierte Rente 1.277,52 EUR\n',
    );
  });

  test('first digit may be corrected when the majority agrees', () {
    const t = 'Summe 4.277,52 EUR\n';
    final p = row(['Summe', '4.277,52', 'EUR']);
    final v = row(['Summe', '1.277,52', 'EUR']);
    expect(fix(t, p, [NumberVoter(v, 1), NumberVoter(v, 1)]), 'Summe 1.277,52 EUR\n');
  });

  test('dropped decimal comma is restored', () {
    const t = 'Beitrag 475 EUR\n';
    final p = row(['Beitrag', '475', 'EUR']);
    final v = row(['Beitrag', '4,75', 'EUR']);
    expect(fix(t, p, [NumberVoter(v, 1), NumberVoter(v, 1)]), 'Beitrag 4,75 EUR\n');
  });

  test('voters on a different line or far-away column are ignored', () {
    final otherLine = row(['Garantierte', 'Rente', '1.277,52', 'EUR'], y: 400);
    final otherColumn = row(['1.277,52'], x0: 1000);
    expect(fix(text, primary, [NumberVoter(otherLine, 5), NumberVoter(otherColumn, 5)]), text);
  });

  test('a totally different number is not "corrected" into existence', () {
    final v = row(['Garantierte', 'Rente', '9.999,99', 'EUR']);
    expect(fix(text, primary, [NumberVoter(v, 3)]), text);
  });

  test('tiny tokens are never rewritten (noise guard)', () {
    const t = 'Seite 3 von 8\n';
    final p = row(['Seite', '3', 'von', '8']);
    final v = row(['Seite', '00', 'von', '8']);
    expect(fix(t, p, [NumberVoter(v, 3)]), t);
  });

  test('repeated identical numbers are mapped back in order', () {
    const t = 'A 0,00 B 1.271,52 C 0,00\n';
    final p = row(['A', '0,00', 'B', '1.271,52', 'C', '0,00']);
    final v = row(['A', '0,00', 'B', '1.277,52', 'C', '0,00']);
    expect(fix(t, p, [NumberVoter(v, 2)]), 'A 0,00 B 1.277,52 C 0,00\n');
  });

  test('layout of the primary text is preserved exactly', () {
    const t = 'Rente      1.271,52   EUR\n\n  Fußnote\n';
    final p = row(['Rente', '1.271,52', 'EUR', 'Fußnote']);
    final v = row(['Rente', '1.277,52', 'EUR', 'Fußnote']);
    expect(fix(t, p, [NumberVoter(v, 2)]), 'Rente      1.277,52   EUR\n\n  Fußnote\n');
  });

  test('"O €" and "00 €" become "0 €" but real amounts are untouched', () {
    expect(normalizeZeroAmounts('davon garantiert O€, 0€, 00 €, OO €'),
        'davon garantiert 0€, 0€, 0 €, 0 €');
    expect(normalizeZeroAmounts('0,00 € 100 € 1.000 € 20 €'), '0,00 € 100 € 1.000 € 20 €');
    expect(normalizeZeroAmounts('Ort 5 Oder'), 'Ort 5 Oder');
  });

  group('recovery of values the primary pass missed', () {
    String recover(String t, List<OcrBox> p, List<OcrBox> items) =>
        applyNumberConsensus(t, p, const [], 1600, recoverFrom: items).text;

    test('a garbled cell ("nt") is replaced by the verifier\'s number', () {
      final p = row(['2049', '103,11', '34,55', '597,80', 'nt']);
      final items = [OcrBox('7,77', p.last.left, p.last.top, 40, 20)];
      expect(recover('2049 103,11 34,55 597,80 nt\n', p, items), '2049 103,11 34,55 597,80 7,77\n');
    });

    test('a value nowhere in the primary text is inserted at its column', () {
      final p = row(['Aktueller', 'Stand']);
      final items = [OcrBox('Stand ab 01.05.2026', 600, 100, 200, 20)];
      expect(recover('Aktueller Stand\n', p, items), 'Aktueller Stand Stand ab 01.05.2026\n');
    });

    test('a missed line is inserted below the line above it', () {
      final first = row(['Kopfzeile'], y: 100);
      final last = row(['Fußzeile'], y: 300);
      final items = [OcrBox('Summe 12,50', 100, 200, 150, 20)];
      expect(recover('Kopfzeile\nFußzeile\n', [...first, ...last], items), 'Kopfzeile\nSumme 12,50\nFußzeile\n');
    });

    test('items the primary already read, and non-money noise, are left alone', () {
      final p = row(['Betrag', '12,50']);
      final already = OcrBox('12,50', p.last.left, p.last.top, p.last.width, 20);
      final barcode = OcrBox('0017389/1000000', 5, 100, 80, 20);
      expect(recover('Betrag 12,50\n', p, [already, barcode]), 'Betrag 12,50\n');
    });

    test('a short garble is only replaced by a bare number, never by a phrase', () {
      final p = row(['Wert', 'nt']);
      final phrase = OcrBox('Stand 12,50', p.last.left, p.last.top, 50, 20);
      expect(recover('Wert nt\n', p, [phrase]), 'Wert nt\n');
    });
  });

  test('cents split off by a space are rejoined, only before a euro sign', () {
    expect(normalizeAmounts('Anlagevermögen 2.460, 48 €'), 'Anlagevermögen 2.460,48 €');
    expect(normalizeAmounts('Wert 12, 34€'), 'Wert 12,34€');
    expect(normalizeAmounts('Seite 2, 48 weitere Zeilen'), 'Seite 2, 48 weitere Zeilen');
    expect(normalizeAmounts('Beträge 1.000, 20 und 5 €'), 'Beträge 1.000, 20 und 5 €');
  });
}
