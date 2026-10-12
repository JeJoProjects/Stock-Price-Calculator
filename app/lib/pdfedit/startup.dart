import 'dart:io';

/// PDF files or folders given on the command line (Windows "Open with") or
/// via STOCKCALC_PDF_OPEN (semicolon separated). They open in the PDF Editor
/// tab at startup.
final List<String> startupPdfPaths = [];

void collectStartupPdfPaths(List<String> args) {
  final env = Platform.environment['STOCKCALC_PDF_OPEN'];
  final raw = [...args, if (env != null) ...env.split(';')];
  for (final a in raw) {
    final p = a.trim();
    if (p.isEmpty) continue;
    final lower = p.toLowerCase();
    if (lower.endsWith('.pdf') || lower.endsWith('.pdfedit') || FileSystemEntity.isDirectorySync(p)) {
      startupPdfPaths.add(p);
    }
  }
}
