/// Font selection for text written into PDFs.
///
/// Plain Latin text uses the PDF "standard 14" fonts (tiny, no embedding,
/// every viewer has them). Anything else (other families, characters outside
/// WinAnsi) embeds a Windows TrueType font through PDFium so any Unicode
/// symbol the font contains survives.
library;

import 'dart:io';

class FontChoice {
  /// PDF standard font name (e.g. "Helvetica-Bold") or null.
  final String? standardName;

  /// Absolute path of a TrueType file to embed, or null.
  final String? ttfPath;

  const FontChoice.standard(String name)
      : standardName = name,
        ttfPath = null;
  const FontChoice.ttf(String path)
      : ttfPath = path,
        standardName = null;

  String get key => standardName ?? ttfPath!;
}

abstract final class FontCatalog {
  static const standardFamilies = ['Helvetica', 'Times', 'Courier'];

  /// Windows family -> [regular, bold, italic, bold-italic] file names.
  static const _windows = <String, List<String>>{
    'Arial': ['arial.ttf', 'arialbd.ttf', 'ariali.ttf', 'arialbi.ttf'],
    'Times New Roman': ['times.ttf', 'timesbd.ttf', 'timesi.ttf', 'timesbi.ttf'],
    'Courier New': ['cour.ttf', 'courbd.ttf', 'couri.ttf', 'courbi.ttf'],
    'Calibri': ['calibri.ttf', 'calibrib.ttf', 'calibrii.ttf', 'calibriz.ttf'],
    'Consolas': ['consola.ttf', 'consolab.ttf', 'consolai.ttf', 'consolaz.ttf'],
    'Georgia': ['georgia.ttf', 'georgiab.ttf', 'georgiai.ttf', 'georgiaz.ttf'],
    'Segoe UI': ['segoeui.ttf', 'segoeuib.ttf', 'segoeuii.ttf', 'segoeuiz.ttf'],
    'Tahoma': ['tahoma.ttf', 'tahomabd.ttf', 'tahoma.ttf', 'tahomabd.ttf'],
    'Trebuchet MS': ['trebuc.ttf', 'trebucbd.ttf', 'trebucit.ttf', 'trebucbi.ttf'],
    'Verdana': ['verdana.ttf', 'verdanab.ttf', 'verdanai.ttf', 'verdanaz.ttf'],
    'Comic Sans MS': ['comic.ttf', 'comicbd.ttf', 'comici.ttf', 'comicz.ttf'],
  };

  /// Overridable for tests.
  static String? fontsDir =
      Platform.isWindows ? '${Platform.environment['WINDIR'] ?? r'C:\Windows'}${Platform.pathSeparator}Fonts' : null;

  static String? _file(String family, int style) {
    final dir = fontsDir;
    final names = _windows[family];
    if (dir == null || names == null) return null;
    for (final n in [names[style], names[0]]) {
      final p = '$dir${Platform.pathSeparator}$n';
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  /// Families offered in the UI: the three standard ones plus every installed
  /// Windows family from the curated list.
  static List<String> availableFamilies() => [
        ...standardFamilies,
        for (final f in _windows.keys)
          if (!{'Arial', 'Times New Roman', 'Courier New'}.contains(f) && _file(f, 0) != null) f,
      ];

  /// Best UI family for an original PDF font name ("ABCDEF+Arial-BoldMT").
  static String guessFamily(String pdfFontName) {
    final n = pdfFontName.toLowerCase();
    if (n.contains('courier') || n.contains('mono') || n.contains('consolas')) {
      return n.contains('consolas') ? 'Consolas' : 'Courier';
    }
    if (n.contains('times') || n.contains('serif') && !n.contains('sans') || n.contains('minion') || n.contains('garamond')) {
      return 'Times';
    }
    for (final f in const ['Calibri', 'Segoe UI', 'Verdana', 'Tahoma', 'Georgia', 'Trebuchet']) {
      if (n.contains(f.toLowerCase().split(' ').first)) return f == 'Trebuchet' ? 'Trebuchet MS' : f;
    }
    return 'Helvetica';
  }

  static const _cp1252Extra = {
    0x20AC, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x017D, //
    0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x017E, 0x0178,
  };

  /// True when every character is representable in Windows-1252, which is
  /// what PDF standard fonts support.
  static bool isWinAnsi(String s) {
    for (final u in s.runes) {
      if (u == 0x0A || u == 0x0D || u == 0x09) continue;
      if (u >= 0x20 && u <= 0x7E) continue;
      if (u >= 0xA0 && u <= 0xFF) continue;
      if (_cp1252Extra.contains(u)) continue;
      return false;
    }
    return true;
  }

  static FontChoice resolve(String family, bool bold, bool italic, String text) {
    final style = (bold ? 1 : 0) + (italic ? 2 : 0);
    final std = switch (family) {
      'Helvetica' || 'Arial' => const ['Helvetica', 'Helvetica-Bold', 'Helvetica-Oblique', 'Helvetica-BoldOblique'],
      'Times' || 'Times New Roman' => const ['Times-Roman', 'Times-Bold', 'Times-Italic', 'Times-BoldItalic'],
      'Courier' || 'Courier New' => const ['Courier', 'Courier-Bold', 'Courier-Oblique', 'Courier-BoldOblique'],
      _ => null,
    };
    if (std != null) {
      if (isWinAnsi(text)) return FontChoice.standard(std[style]);
      final win = switch (family) {
        'Helvetica' || 'Arial' => 'Arial',
        'Times' || 'Times New Roman' => 'Times New Roman',
        _ => 'Courier New',
      };
      final f = _file(win, style);
      return f != null ? FontChoice.ttf(f) : FontChoice.standard(std[style]);
    }
    final f = _file(family, style);
    return f != null ? FontChoice.ttf(f) : FontChoice.standard(const ['Helvetica', 'Helvetica-Bold', 'Helvetica-Oblique', 'Helvetica-BoldOblique'][style]);
  }
}
