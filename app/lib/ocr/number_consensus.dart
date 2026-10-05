/// Position-aware numeric consensus between several OCR readings of the same
/// page. Digits are the one thing OCR must not get wrong, and single-pass
/// Tesseract occasionally flips one ("1.277,52" -> "1.271,52"), drops a comma
/// ("4,75" -> "475") or reads a zero as "O". Independent readings (other
/// Tesseract scales, PaddleOCR) rarely make the *same* mistake at the same
/// spot, so a number is replaced only when a weighted majority of the other
/// readings, found at the same page position, agrees on a close variant.
library;

import 'dart:math' as math;

/// One recognized word with its box in original-image pixel coordinates.
class OcrBox {
  final String text;
  final double left, top, width, height;

  const OcrBox(this.text, this.left, this.top, this.width, this.height);

  double get cx => left + width / 2;
  double get cy => top + height / 2;

  OcrBox scaled(double factor) =>
      OcrBox(text, left * factor, top * factor, width * factor, height * factor);
}

/// A numeric token located inside an [OcrBox] (the box text may hold more,
/// e.g. "154,81E" or "(Nr.4.8").
class NumToken {
  final String text;
  final double cx, cy, h;

  const NumToken(this.text, this.cx, this.cy, this.h);
}

/// Another reading of the page, trusted with [weight] votes.
class NumberVoter {
  final List<OcrBox> boxes;
  final double weight;

  const NumberVoter(this.boxes, this.weight);
}

/// One accepted correction, kept for diagnostics and tests.
class NumberFix {
  final String from, to;
  final double x, y;

  const NumberFix(this.from, this.to, this.x, this.y);

  @override
  String toString() => '$from -> $to @ (${x.round()},${y.round()})';
}

class ConsensusResult {
  final String text;
  final List<NumberFix> fixes;

  const ConsensusResult(this.text, this.fixes);
}

final _numberRe = RegExp(r'[+\-]?\d[\d.,]*\d|\d');
/// Extracts numeric tokens from [boxes], one per number inside a word.
List<NumToken> numericTokens(List<OcrBox> boxes) {
  final tokens = <NumToken>[];
  for (final b in boxes) {
    final n = math.max(1, b.text.length);
    for (final m in _numberRe.allMatches(b.text)) {
      final frac = (m.start + m.end) / 2 / n;
      tokens.add(NumToken(m.group(0)!, b.left + b.width * frac, b.cy, b.height));
    }
  }
  return tokens;
}

String _canon(String t) => t.replaceAll(RegExp(r'[^\d.,+\-]'), '');

int _editDistance(String a, String b) {
  if (a == b) return 0;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = <int>[i];
    for (var j = 1; j <= b.length; j++) {
      cur.add(math.min(
        math.min(prev[j] + 1, cur[j - 1] + 1),
        prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      ));
    }
    prev = cur;
  }
  return prev.last;
}

final _germanAmountRe = RegExp(r'^\d{1,3}(?:\.\d{3})*,\d{2}$');

/// Guards against "fixing" noise: a replacement must look like an OCR slip
/// of the same number, not a different number.
bool _plausibleFix(String a, String b) {
  final da = a.replaceAll(RegExp(r'\D'), '');
  final db = b.replaceAll(RegExp(r'\D'), '');
  if (da.isEmpty || db.isEmpty) return false;
  // Never turn a well-formed German amount ("1.277,52") into a malformed one
  // ("1.277.52"): neural readers sometimes swap the decimal comma for a dot.
  if (_germanAmountRe.hasMatch(a) && !_germanAmountRe.hasMatch(b)) return false;
  // Only separators differ ("475" <-> "4,75", "1.277.52" <-> "1.277,52").
  if (da == db) return da.length >= 2;
  // Run of zeros collapsed to a single zero ("00 EUR" read for "0 EUR").
  if (RegExp(r'^0{2,}$').hasMatch(da) && db == '0') return true;
  return da.length >= 2 &&
      a.length >= 3 &&
      (da.length - db.length).abs() <= 1 &&
      _editDistance(a, b) <= 2;
}

/// Finds the token in [pool] closest to [t] on the page, or null if none is
/// at roughly the same line and column.
NumToken? _nearest(NumToken t, List<NumToken> pool, double pageWidth) {
  NumToken? best;
  var bestD = double.infinity;
  final maxDy = 0.7 * math.max(t.h, 12);
  final maxDx = 0.035 * pageWidth;
  for (final p in pool) {
    final dy = (p.cy - t.cy).abs();
    if (dy > maxDy) continue;
    final dx = (p.cx - t.cx).abs();
    if (dx > maxDx) continue;
    final d = dx + 3 * dy;
    if (d < bestD) {
      bestD = d;
      best = p;
    }
  }
  return best;
}

/// Decides the corrected value for each numeric token of [primary]. Returns
/// one entry per token, in order: the new text, or null to keep it.
List<({String? to, NumToken token, Map<String, double> votes})> decide(
  List<OcrBox> primary,
  List<NumberVoter> voters,
  double pageWidth,
) {
  final tokens = numericTokens(primary);
  final pools = [for (final v in voters) numericTokens(v.boxes)];
  final out = <({String? to, NumToken token, Map<String, double> votes})>[];
  for (final t in tokens) {
    final a = _canon(t.text);
    final votes = <String, double>{a: 1.0};
    for (var i = 0; i < voters.length; i++) {
      final n = _nearest(t, pools[i], pageWidth);
      if (n != null) {
        final k = _canon(n.text);
        votes[k] = (votes[k] ?? 0) + voters[i].weight;
      }
    }
    final ranked = votes.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
    final best = ranked.first;
    final replace = best.key != a && best.value > (votes[a] ?? 0) && _plausibleFix(a, best.key);
    out.add((to: replace ? best.key : null, token: t, votes: votes));
  }
  return out;
}

/// Applies the consensus to the primary reading's plain [text]. [primary] are
/// that same reading's word boxes (same recognition run, so the numeric tokens
/// appear in the same order as in [text]); corrections are mapped back onto
/// [text] by walking both in order, which preserves its exact layout.
ConsensusResult applyNumberConsensus(
  String text,
  List<OcrBox> primary,
  List<NumberVoter> voters,
  double pageWidth, {
  List<OcrBox> recoverFrom = const [],
}) {
  if (voters.isEmpty && recoverFrom.isEmpty) {
    return ConsensusResult(normalizeAmounts(text), const []);
  }
  final decisions = decide(primary, voters, pageWidth);
  final matches = _numberRe.allMatches(text).toList();

  final edits = <({int start, int end, String to})>[];
  final fixes = <NumberFix>[];
  var p = 0;
  for (final d in decisions) {
    // Walk forward to the matching occurrence in the text (OCR text and the
    // word list come from the same run, so a small lookahead is enough).
    var found = -1;
    for (var k = p; k < math.min(matches.length, p + 6); k++) {
      if (_canon(matches[k].group(0)!) == _canon(d.token.text) ||
          matches[k].group(0) == d.token.text) {
        found = k;
        break;
      }
    }
    if (found < 0) continue;
    p = found + 1;
    final to = d.to;
    if (to != null) {
      final m = matches[found];
      edits.add((start: m.start, end: m.end, to: to));
      fixes.add(NumberFix(m.group(0)!, to, d.token.cx, d.token.cy));
    }
  }

  edits.addAll(_recoveryEdits(text, primary, recoverFrom, fixes));

  final all = [...edits]..sort((a, b) => b.start.compareTo(a.start));
  var fixed = text;
  for (final e in all) {
    fixed = fixed.replaceRange(e.start, e.end, e.to);
  }
  return ConsensusResult(normalizeAmounts(fixed), fixes);
}

final _zeroAmountRe = RegExp(r'(?<![\w.,])[Oo0]{1,3}(?=\s?€)');

/// "O €", "00 €" and "0O €" can only be a zero amount - a letter O or a
/// double zero directly before a euro sign is never a valid figure - yet
/// Tesseract reads the lone "0" of "0 €" that way. Normalizes them to "0".
String normalizeZeroAmounts(String text) => text.replaceAll(_zeroAmountRe, '0');

// "2.460, 48 €": the cents were split off by a stray space.
final _splitDecimalRe = RegExp(r'(?<![\w.,])(\d{1,3}(?:\.\d{3})*|\d+),\s+(\d{2})(?=\s?€)');

/// Deterministic repairs for euro amounts that cannot be anything else.
String normalizeAmounts(String text) =>
    normalizeZeroAmounts(text.replaceAllMapped(_splitDecimalRe, (m) => '${m[1]},${m[2]}'));

// Money ("154,81", "2.412,86") or a date ("01.05.2026"): values worth
// recovering. Barcode digits and page numbers are deliberately excluded.
final _recoverableRe = RegExp(r'\d{1,3}(?:\.\d{3})*,\d{2}(?!\d)|\d{2}\.\d{2}\.\d{4}');
final _pureNumberRe = RegExp(r'^[+\-]?\d[\d.,]*\d€?$');

/// Where each primary word starts in [text] (null if it can't be located).
List<int?> _alignWords(String text, List<OcrBox> words) {
  final out = <int?>[];
  var cursor = 0;
  for (final w in words) {
    final i = text.indexOf(w.text, cursor);
    if (i < 0 || i - cursor > 400) {
      out.add(null);
    } else {
      out.add(i);
      cursor = i + w.text.length;
    }
  }
  return out;
}

double _overlap(double a0, double a1, double b0, double b1) =>
    math.max(0, math.min(a1, b1) - math.max(a0, b0));

/// Values the verifier read that the primary pass missed or garbled:
///  * item sits where the primary has no word at all  -> insert the item;
///  * item is a bare number and the primary has only short non-numeric
///    garble there (e.g. "7,77" read as "nt")        -> replace the garble.
List<({int start, int end, String to})> _recoveryEdits(
  String text,
  List<OcrBox> primary,
  List<OcrBox> items,
  List<NumberFix> fixes,
) {
  final edits = <({int start, int end, String to})>[];
  if (items.isEmpty || primary.isEmpty) return edits;
  final starts = _alignWords(text, primary);

  for (final item in items) {
    if (!_recoverableRe.hasMatch(item.text)) continue;

    // Primary words that sit on this item's box.
    final covering = <int>[];
    for (var i = 0; i < primary.length; i++) {
      final w = primary[i];
      final h = _overlap(w.left, w.left + w.width, item.left, item.left + item.width);
      final v = _overlap(w.top, w.top + w.height, item.top, item.top + item.height);
      if (h >= 0.3 * math.min(w.width, item.width) && v >= 0.5 * math.min(w.height, item.height)) {
        covering.add(i);
      }
    }

    if (covering.isEmpty) {
      // Nothing was read here at all: insert the item on its line.
      final itemCy = item.cy;
      final row = [
        for (var i = 0; i < primary.length; i++)
          if (starts[i] != null && (primary[i].cy - itemCy).abs() <= 0.6 * math.max(item.height, 12)) i,
      ]..sort((a, b) => primary[a].left.compareTo(primary[b].left));
      if (row.isNotEmpty) {
        final before = row.where((i) => primary[i].cx < item.cx).toList();
        if (before.isEmpty) {
          final first = starts[row.first]!;
          edits.add((start: first, end: first, to: '${item.text} '));
        } else {
          final last = before.last;
          final end = starts[last]! + primary[last].text.length;
          edits.add((start: end, end: end, to: ' ${item.text}'));
        }
        fixes.add(NumberFix('', item.text, item.cx, item.cy));
      } else {
        // A line of its own: place it after the last line above it.
        final above = [
          for (var i = 0; i < primary.length; i++)
            if (starts[i] != null && primary[i].cy < itemCy) i,
        ]..sort((a, b) => primary[a].cy.compareTo(primary[b].cy));
        if (above.isEmpty) continue;
        final lineEnd = text.indexOf('\n', starts[above.last]!);
        final at = lineEnd < 0 ? text.length : lineEnd;
        edits.add((start: at, end: at, to: '\n${item.text}'));
        fixes.add(NumberFix('', item.text, item.cx, item.cy));
      }
    } else if (_pureNumberRe.hasMatch(item.text.trim()) &&
        covering.every((i) =>
            starts[i] != null &&
            primary[i].text.length <= 4 &&
            !primary[i].text.contains(RegExp(r'\d')))) {
      final first = covering.first, last = covering.last;
      final start = starts[first]!;
      final end = starts[last]! + primary[last].text.length;
      edits.add((start: start, end: end, to: item.text.trim()));
      fixes.add(NumberFix(text.substring(start, end), item.text.trim(), item.cx, item.cy));
    }
  }
  return edits;
}
