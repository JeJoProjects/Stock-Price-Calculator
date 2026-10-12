import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/pdfedit/doc_session.dart';
import 'package:stockcalc/pdfedit/edit_model.dart';
import 'package:stockcalc/pdfedit/pdf_baker.dart';
import 'package:stockcalc/pdfedit/pdfium_edit.dart';
import 'package:stockcalc/pdfedit/workspace.dart';

bool get _haveDll => File('build/windows/x64/runner/Release/pdfium.dll').existsSync();
const _skip = 'needs pdfium.dll (build the Windows app once: setup_flutter.bat)';

Uint8List sample({int pages = 1}) {
  final doc = PdfiumDoc.createBlank(pages: pages);
  final p = doc.loadPage(0);
  p.addText('Kontostand 1.234,56 €', 72, 700, 14, doc.standardFont('Helvetica'), 0xFF000000);
  p.generateContent();
  p.close();
  final b = doc.save();
  doc.close();
  return b;
}

Future<File> tempPdf(Directory dir, String name, Uint8List bytes) async =>
    File('${dir.path}${Platform.pathSeparator}$name')..writeAsBytesSync(bytes);

void main() {
  late Directory dir;

  setUpAll(() {
    if (_haveDll) PdfiumLib.overridePath = File('build/windows/x64/runner/Release/pdfium.dll').absolute.path;
  });
  setUp(() => dir = Directory.systemTemp.createTempSync('pdfedit_session'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('undo/redo over overlay edits, with dirty tracking', () async {
    final f = await tempPdf(dir, 'a.pdf', sample());
    final s = await PdfDocSession.open(f.path);
    expect((s.pageCount, s.canUndo, s.dirty), (1, false, false));

    s.addOp(const WhiteoutOp('w1', 0, Box(0, 0, 10, 10)));
    s.addOp(const WhiteoutOp('w2', 0, Box(5, 5, 20, 20)));
    expect((s.ops.length, s.dirty, s.canUndo, s.canRedo), (2, true, true, false));
    s.undo();
    expect(s.ops.map((o) => o.id), ['w1']);
    expect(s.canRedo, isTrue);
    s.redo();
    expect(s.ops.length, 2);
    s.undo();
    s.undo();
    expect(s.ops, isEmpty);
    expect(s.dirty, isFalse, reason: 'back at the opened state = clean');
    s.addOp(const WhiteoutOp('w3', 0, Box(0, 0, 1, 1)));
    expect(s.canRedo, isFalse, reason: 'a new edit discards the redo branch');
    s.dispose();
  }, skip: _haveDll ? false : _skip);

  test('drag updates are previewed without history, then commit as ONE undo step', () async {
    final s = await PdfDocSession.open((await tempPdf(dir, 'a.pdf', sample())).path);
    s.addOp(const WhiteoutOp('w', 0, Box(0, 0, 10, 10)));
    final before = s.ops;
    for (var i = 1; i <= 20; i++) {
      s.updateOp(const WhiteoutOp('w', 0, Box(0, 0, 10, 10)).moved(i.toDouble(), 0), record: false);
    }
    s.commit(before);
    expect((s.opById('w')! as WhiteoutOp).box.l, 20);
    s.undo(); // one step back = before the drag, not 19 steps
    expect((s.opById('w')! as WhiteoutOp).box.l, 0);
    s.undo();
    expect(s.ops, isEmpty);
    s.dispose();
  }, skip: _haveDll ? false : _skip);

  test('page actions bake overlays first and undo/redo restore both file and overlays', () async {
    final s = await PdfDocSession.open((await tempPdf(dir, 'a.pdf', sample(pages: 3))).path);
    s.addOp(const ShapeOp(id: 's', page: 1, kind: ShapeKind.line, x1: 0, y1: 0, x2: 50, y2: 50));
    await s.applyStructure(const DeletePages([0]));
    expect(s.pageCount, 2);
    expect(s.ops, isEmpty, reason: 'overlays were baked into the new working file');
    expect(s.revision, 1);

    s.undo();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(s.pageCount, 3);
    expect(s.ops.map((o) => o.id), ['s'], reason: 'unbaked overlay is back');
    s.redo();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(s.pageCount, 2);

    await s.applyStructure(const InsertBlank(1));
    expect(s.pageCount, 3);
    s.undo();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await s.applyStructure(const RotatePages([0], 90)); // new branch after undo
    expect(s.canRedo, isFalse);
    expect(s.pageCount, 2);
    expect((await s.pageInfo(0)).rotation, 90);
    s.dispose();
  }, skip: _haveDll ? false : _skip);

  test('save writes a real PDF with the edits baked in; dirty clears', () async {
    final f = await tempPdf(dir, 'a.pdf', sample());
    final s = await PdfDocSession.open(f.path);
    final info = await s.pageInfo(0);
    final line = info.lines.single;
    s.addOp(TextOp(
        id: 't', page: 0, x: line.first.originX, baselineY: line.first.baselineY, text: 'Kontostand 7,00 €',
        size: line.first.fontSize, removeObjects: line.objectIndices));
    expect(s.dirty, isTrue);
    final out = '${dir.path}${Platform.pathSeparator}out.pdf';
    await s.saveTo(out);
    expect((s.dirty, s.savedPath), (false, out));
    final re = analyzePages(File(out).readAsBytesSync(), [0]).single;
    expect(re.lines.map((l) => l.text), ['Kontostand 7,00 €']);
    // the original file is untouched
    expect(analyzePages(f.readAsBytesSync(), [0]).single.lines.single.text, 'Kontostand 1.234,56 €');
    s.dispose();
  }, skip: _haveDll ? false : _skip);

  test('drafts resume everything: page actions + overlays', () async {
    final f = await tempPdf(dir, 'a.pdf', sample(pages: 3));
    final s = await PdfDocSession.open(f.path);
    s.addOp(const WhiteoutOp('w0', 0, Box(1, 1, 5, 5)));
    await s.applyStructure(const DeletePages([2]));
    await s.applyStructure(const RotatePages([0], 180));
    s.addOp(const SymbolOp('c', 0, SymbolKind.check, Box(10, 10, 30, 30), 0xFF000000));
    final draft = '${dir.path}${Platform.pathSeparator}a.pdfedit';
    await s.saveDraft(draft);

    final r = await PdfDocSession.openDraft(draft);
    expect(r.pageCount, 2);
    expect(r.ops.map((o) => o.id), ['c']);
    expect((await r.pageInfo(0)).rotation, 180);
    expect(r.dirty, isFalse, reason: 'a freshly resumed draft matches what was saved');
    // and it keeps the full history for undo
    r.undo();
    expect(r.ops, isEmpty);
    s.dispose();
    r.dispose();
  }, skip: _haveDll ? false : _skip);

  test('workspace: opens many files and a whole folder (recursive, natural order), reports bad files', () async {
    await tempPdf(dir, 'p10.pdf', sample());
    await tempPdf(dir, 'p2.pdf', sample());
    Directory('${dir.path}${Platform.pathSeparator}sub').createSync();
    await tempPdf(Directory('${dir.path}${Platform.pathSeparator}sub'), 'p1.pdf', sample());
    File('${dir.path}${Platform.pathSeparator}notes.txt').writeAsStringSync('x');
    File('${dir.path}${Platform.pathSeparator}broken.pdf').writeAsStringSync('not a pdf');

    final ws = PdfWorkspace();
    await ws.openPaths([dir.path]);
    // by full path: root files (natural order), then sub-folders
    expect(ws.docs.map((d) => d.title), ['p2.pdf', 'p10.pdf', 'p1.pdf']);
    expect(ws.lastFailures.map((f) => f.path.split(RegExp(r'[\\/]')).last), ['broken.pdf']);
    expect(ws.activeIndex, 0);

    // opening the same file again just activates it
    await ws.openPaths(['${dir.path}${Platform.pathSeparator}p2.pdf']);
    expect(ws.docs.length, 3);
    expect(ws.activeIndex, 0);

    await ws.newBlank();
    expect(ws.docs.last.title, 'Untitled.pdf');
    expect(ws.activeIndex, 3);
    ws.close(3);
    expect(ws.activeIndex, 2);
    ws.dispose();
  }, skip: _haveDll ? false : _skip);
}
