import 'package:flutter/foundation.dart';
import '../../pdfedit/edit_model.dart';

/// Every tool in the toolbar. Menu entries that only differ by a variant
/// (markup colour, shape kind...) are separate values so the options bar and
/// canvas can react to exactly what is active.
enum EditorTool {
  select,
  text,
  links,
  symbol,
  placeImage,
  whiteout,
  strikeout,
  highlight,
  underline,
  freeHighlight,
  draw,
  ellipse,
  rectangle,
  line,
  arrow,
  deleteImage,
}

extension EditorToolInfo on EditorTool {
  String get label => switch (this) {
        EditorTool.select => 'Select',
        EditorTool.text => 'Text',
        EditorTool.links => 'Links',
        EditorTool.symbol => 'Symbol',
        EditorTool.placeImage => 'Place',
        EditorTool.whiteout => 'Whiteout',
        EditorTool.strikeout => 'Strike out',
        EditorTool.highlight => 'Highlight',
        EditorTool.underline => 'Underline',
        EditorTool.freeHighlight => 'Freehand highlight',
        EditorTool.draw => 'Draw',
        EditorTool.ellipse => 'Ellipse',
        EditorTool.rectangle => 'Rectangle',
        EditorTool.line => 'Line',
        EditorTool.arrow => 'Arrow',
        EditorTool.deleteImage => 'Delete existing image',
      };

  /// Shown in the status bar while the tool is active.
  String get hint => switch (this) {
        EditorTool.select => 'Click an object to select it. Drag to move, drag the handles to resize, Delete removes it.',
        EditorTool.text => 'Click existing text to edit it, or click anywhere to add new text. Esc cancels.',
        EditorTool.links => 'Drag a rectangle where the link should be, then enter the address.',
        EditorTool.symbol => 'Click to place the symbol. Drag a handle afterwards to resize.',
        EditorTool.placeImage => 'Click where the image should go. Press Esc to cancel.',
        EditorTool.whiteout => 'Drag over anything you want to cover with a white box.',
        EditorTool.strikeout => 'Drag across the text you want to strike out.',
        EditorTool.highlight => 'Drag across the text you want to highlight.',
        EditorTool.underline => 'Drag across the text you want to underline.',
        EditorTool.freeHighlight => 'Draw with the highlighter anywhere on the page.',
        EditorTool.draw => 'Draw freehand anywhere on the page.',
        EditorTool.ellipse => 'Drag to draw an ellipse. Hold Shift for a circle.',
        EditorTool.rectangle => 'Drag to draw a rectangle. Hold Shift for a square.',
        EditorTool.line => 'Drag to draw a line. Hold Shift to snap the angle.',
        EditorTool.arrow => 'Drag to draw an arrow. Hold Shift to snap the angle.',
        EditorTool.deleteImage => 'Click an existing image to remove it from the page.',
      };

  bool get isMarkup =>
      this == EditorTool.strikeout || this == EditorTool.highlight || this == EditorTool.underline;
  bool get isShape =>
      this == EditorTool.ellipse || this == EditorTool.rectangle || this == EditorTool.line || this == EditorTool.arrow;
  bool get isFreehand => this == EditorTool.draw || this == EditorTool.freeHighlight;
}

/// A pending placement: the next click on a page drops this image there.
class PlacingImage {
  const PlacingImage(this.bytes, this.aspect, {this.widthPt = 150});
  final Uint8List bytes;

  /// width / height
  final double aspect;
  final double widthPt;
}

/// Tool, options and view state shared by the whole editor tab. Per-document
/// state (edits, history) lives in `PdfDocSession`.
class EditorController extends ChangeNotifier {
  EditorTool _tool = EditorTool.text;
  EditorTool get tool => _tool;

  // -- text options
  String fontFamily = 'Helvetica';
  double fontSize = 12;
  bool bold = false;
  bool italic = false;
  int textColor = 0xFF000000;

  // -- shape / draw options
  int strokeColor = 0xFFE53935;
  int? fillColor;
  double strokeWidth = 2;

  // -- annotation colours per tool
  final Map<EditorTool, int> annotationColors = {
    EditorTool.strikeout: 0xFFE53935,
    EditorTool.highlight: 0xFFFFEB3B,
    EditorTool.underline: 0xFF1E88E5,
    EditorTool.freeHighlight: 0xFFFFEB3B,
    EditorTool.draw: 0xFFE53935,
    EditorTool.symbol: 0xFF000000,
    EditorTool.whiteout: 0xFFFFFFFF,
  };

  SymbolKind symbolKind = SymbolKind.check;
  PlacingImage? placing;
  bool showAnnotations = true;

  // -- selection and view
  Set<String> selected = {};
  double zoom = 1.0;
  bool fitWidth = true;
  int currentPage = 0;

  /// Page the canvas should scroll to when [scrollTick] changes.
  int scrollToPage = 0;
  int scrollTick = 0;

  static const minZoom = 0.25, maxZoom = 5.0;

  void setTool(EditorTool t) {
    if (t != EditorTool.placeImage) placing = null;
    if (_tool == t && t != EditorTool.symbol) return;
    _tool = t;
    if (t != EditorTool.select) selected = {};
    notifyListeners();
  }

  void startPlacing(PlacingImage p) {
    placing = p;
    selected = {};
    _tool = EditorTool.placeImage;
    notifyListeners();
  }

  void pickSymbol(SymbolKind k) {
    symbolKind = k;
    _tool = EditorTool.symbol;
    selected = {};
    notifyListeners();
  }

  void select(Set<String> ids) {
    selected = ids;
    notifyListeners();
  }

  void setZoom(double z, {bool fit = false}) {
    zoom = z.clamp(minZoom, maxZoom);
    fitWidth = fit;
    notifyListeners();
  }

  void zoomBy(double factor) => setZoom(zoom * factor);

  void setCurrentPage(int p) {
    if (p == currentPage) return;
    currentPage = p;
    notifyListeners();
  }

  void requestScrollTo(int page) {
    scrollToPage = page;
    scrollTick++;
    currentPage = page;
    notifyListeners();
  }

  void toggleAnnotations() {
    showAnnotations = !showAnnotations;
    notifyListeners();
  }

  /// Bumped to make every page commit an open inline text editor.
  int commitTick = 0;
  void commitEditingRequest() {
    commitTick++;
    notifyListeners();
  }

  /// The options bar mirrors the style of the text being edited.
  void adoptTextStyle(String family, double size, bool b, bool i, int argb) {
    fontFamily = family;
    fontSize = size;
    bold = b;
    italic = i;
    textColor = argb;
    notifyListeners();
  }

  void changed() => notifyListeners();
}
