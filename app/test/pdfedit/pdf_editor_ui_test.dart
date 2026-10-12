import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stockcalc/pdfedit/asset_store.dart';
import 'package:stockcalc/pdfedit/signature_tools.dart';
import 'package:stockcalc/theme/app_theme.dart';
import 'package:stockcalc/widgets/pdf_editor/editor_controller.dart';
import 'package:stockcalc/widgets/pdf_editor_panel.dart';

void main() {
  testWidgets('the PDF Editor tab starts with a clear call to action', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1300, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: PdfEditorPanel())));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('PDF Editor'), findsOneWidget);
    expect(find.text('Upload PDF files'), findsOneWidget);
    expect(find.text('Open a folder'), findsOneWidget);
    expect(find.text('Start with a blank document'), findsOneWidget);
    expect(find.textContaining('nothing is uploaded'), findsOneWidget);
  });

  test('tool state: selecting a tool clears selection and placing mode, symbols remember their kind', () {
    final c = EditorController();
    c.select({'a'});
    c.setTool(EditorTool.whiteout);
    expect(c.selected, isEmpty);
    c.startPlacing(PlacingImage(Uint8List(1), 2));
    expect(c.tool, EditorTool.placeImage);
    c.setTool(EditorTool.text);
    expect(c.placing, isNull);
    expect(EditorTool.values.every((t) => t.hint.isNotEmpty && t.label.isNotEmpty), isTrue);
    c.setZoom(100);
    expect(c.zoom, EditorController.maxZoom, reason: 'zoom is clamped');
    c.dispose();
  });

  group('signature tools', () {
    test('removeBackground makes white paper transparent, keeps dark ink, and trims', () {
      final im = img.Image(width: 60, height: 40, numChannels: 3)..clear(img.ColorRgb8(255, 255, 255));
      for (var x = 20; x < 30; x++) {
        for (var y = 15; y < 20; y++) {
          im.setPixelRgb(x, y, 10, 10, 120);
        }
      }
      final out = img.decodePng(removeBackground(Uint8List.fromList(img.encodePng(im)), padding: 2))!;
      expect(out.width, 10 + 4);
      expect(out.height, 5 + 4);
      expect(out.getPixel(0, 0).a, 0, reason: 'corner was paper');
      expect(out.getPixel(7, 4).a, 255, reason: 'centre is ink');
    });

    test('imageAspect reads width/height and rejects garbage', () {
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 30, height: 10)));
      expect(imageAspect(png), 3.0);
      expect(imageAspect(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  test('AssetStore remembers saved signatures newest-first and can delete them', () async {
    final dir = Directory.systemTemp.createTempSync('assets');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = AssetStore(Directory('${dir.path}${Platform.pathSeparator}sigs'));
    expect(await store.list(), isEmpty);
    final a = await store.add(Uint8List.fromList([1]));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final b = await store.add(Uint8List.fromList([2]));
    var all = await store.list();
    expect(all.map((e) => e.bytes.first), [2, 1]);
    await store.delete(a);
    all = await store.list();
    expect(all.single.file.path, b.file.path);
  });
}
