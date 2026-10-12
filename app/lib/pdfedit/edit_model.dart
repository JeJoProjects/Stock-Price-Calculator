/// Immutable edit objects. Coordinates are *display space*: points (1/72"),
/// origin top-left of the page as shown (after /Rotate), y down. The baker
/// converts them to PDF user space. Everything here is plain Dart (sendable
/// to isolates, JSON-serialisable for drafts).
library;

import 'dart:convert';
import 'dart:typed_data';

class Box {
  final double l, t, r, b;
  const Box(this.l, this.t, this.r, this.b);

  double get w => r - l;
  double get h => b - t;
  double get cx => (l + r) / 2;
  double get cy => (t + b) / 2;

  bool contains(double x, double y) => x >= l && x <= r && y >= t && y <= b;
  bool overlaps(Box o) => l < o.r && r > o.l && t < o.b && b > o.t;
  Box inflate(double d) => Box(l - d, t - d, r + d, b + d);
  Box shift(double dx, double dy) => Box(l + dx, t + dy, r + dx, b + dy);
  Box union(Box o) => Box(l < o.l ? l : o.l, t < o.t ? t : o.t, r > o.r ? r : o.r, b > o.b ? b : o.b);

  /// Rectangle spanned by two arbitrary corners.
  factory Box.fromCorners(double x1, double y1, double x2, double y2) =>
      Box(x1 < x2 ? x1 : x2, y1 < y2 ? y1 : y2, x1 < x2 ? x2 : x1, y1 < y2 ? y2 : y1);

  List<double> toJson() => [l, t, r, b];
  factory Box.fromJson(List<dynamic> j) => Box((j[0] as num).toDouble(), (j[1] as num).toDouble(),
      (j[2] as num).toDouble(), (j[3] as num).toDouble());

  @override
  bool operator ==(Object other) => other is Box && other.l == l && other.t == t && other.r == r && other.b == b;
  @override
  int get hashCode => Object.hash(l, t, r, b);
  @override
  String toString() => 'Box($l,$t,$r,$b)';
}

enum ShapeKind { rectangle, ellipse, line, arrow }

enum MarkupKind { highlight, underline, strikeout }

enum SymbolKind { cross, check, square, dot }

/// Base of every overlay edit.
sealed class EditOp {
  const EditOp(this.id, this.page);

  /// Unique within a document session (used for selection/identity).
  final String id;

  /// 0-based page index in the *current working file*.
  final int page;

  /// Bounding box in display space (selection frame / hit test).
  Box get bounds;

  Map<String, dynamic> toJson();

  EditOp moved(double dx, double dy);

  static EditOp fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    final page = j['page'] as int;
    switch (j['type']) {
      case 'text':
        return TextOp(
          id: id,
          page: page,
          x: (j['x'] as num).toDouble(),
          baselineY: (j['baselineY'] as num).toDouble(),
          text: j['text'] as String,
          fontFamily: j['fontFamily'] as String,
          size: (j['size'] as num).toDouble(),
          bold: j['bold'] as bool,
          italic: j['italic'] as bool,
          argb: j['argb'] as int,
          removeObjects: (j['remove'] as List).cast<int>(),
          cover: [for (final c in j['cover'] as List) Box.fromJson(c as List)],
          width: (j['width'] as num?)?.toDouble() ?? 0,
        );
      case 'whiteout':
        return WhiteoutOp(id, page, Box.fromJson(j['box'] as List), argb: j['argb'] as int);
      case 'shape':
        return ShapeOp(
          id: id,
          page: page,
          kind: ShapeKind.values.byName(j['kind'] as String),
          x1: (j['x1'] as num).toDouble(),
          y1: (j['y1'] as num).toDouble(),
          x2: (j['x2'] as num).toDouble(),
          y2: (j['y2'] as num).toDouble(),
          strokeArgb: j['stroke'] as int,
          fillArgb: j['fill'] as int?,
          width: (j['width'] as num).toDouble(),
        );
      case 'markup':
        return MarkupOp(
          id: id,
          page: page,
          kind: MarkupKind.values.byName(j['kind'] as String),
          rects: [for (final r in j['rects'] as List) Box.fromJson(r as List)],
          argb: j['argb'] as int,
        );
      case 'ink':
        return InkOp(
          id: id,
          page: page,
          points: [for (final p in j['points'] as List) ((p[0] as num).toDouble(), (p[1] as num).toDouble())],
          argb: j['argb'] as int,
          width: (j['width'] as num).toDouble(),
          highlight: j['highlight'] as bool,
        );
      case 'image':
        return ImageOp(id, page, Box.fromJson(j['box'] as List), base64Decode(j['data'] as String));
      case 'symbol':
        return SymbolOp(id, page, SymbolKind.values.byName(j['kind'] as String), Box.fromJson(j['box'] as List), j['argb'] as int);
      case 'link':
        return LinkOp(id, page, Box.fromJson(j['box'] as List), j['uri'] as String);
      case 'deleteImage':
        return DeleteImageOp(id, page, j['objectIndex'] as int, Box.fromJson(j['box'] as List));
    }
    throw FormatException('Unknown edit type ${j['type']}');
  }
}

/// New or replacement text. [x],[baselineY] is the baseline-left origin.
/// [removeObjects] are PDFium object indices of original text deleted at bake
/// time; [cover] are display boxes painted page-white in the preview until then.
class TextOp extends EditOp {
  const TextOp({
    required String id,
    required int page,
    required this.x,
    required this.baselineY,
    required this.text,
    this.fontFamily = 'Helvetica',
    this.size = 12,
    this.bold = false,
    this.italic = false,
    this.argb = 0xFF000000,
    this.removeObjects = const [],
    this.cover = const [],
    this.width = 0,
  }) : super(id, page);

  final double x, baselineY, size;
  final String text, fontFamily;
  final bool bold, italic;
  final int argb;
  final List<int> removeObjects;
  final List<Box> cover;

  /// Measured width in points (set by the UI after layout; used for bounds).
  final double width;

  int get lineCount => '\n'.allMatches(text).length + 1;

  @override
  Box get bounds {
    final lines = text.split('\n');
    final w = width > 0 ? width : lines.fold<double>(0, (m, l) => l.length > m ? l.length.toDouble() : m) * size * 0.55;
    return Box(x, baselineY - size * 0.9, x + w, baselineY + size * 1.2 * (lineCount - 1) + size * 0.3);
  }

  TextOp copyWith({
    double? x,
    double? baselineY,
    String? text,
    String? fontFamily,
    double? size,
    bool? bold,
    bool? italic,
    int? argb,
    List<int>? removeObjects,
    List<Box>? cover,
    double? width,
  }) =>
      TextOp(
        id: id,
        page: page,
        x: x ?? this.x,
        baselineY: baselineY ?? this.baselineY,
        text: text ?? this.text,
        fontFamily: fontFamily ?? this.fontFamily,
        size: size ?? this.size,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        argb: argb ?? this.argb,
        removeObjects: removeObjects ?? this.removeObjects,
        cover: cover ?? this.cover,
        width: width ?? this.width,
      );

  @override
  TextOp moved(double dx, double dy) => copyWith(x: x + dx, baselineY: baselineY + dy);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'text',
        'id': id,
        'page': page,
        'x': x,
        'baselineY': baselineY,
        'text': text,
        'fontFamily': fontFamily,
        'size': size,
        'bold': bold,
        'italic': italic,
        'argb': argb,
        'remove': removeObjects,
        'cover': [for (final c in cover) c.toJson()],
        'width': width,
      };
}

class WhiteoutOp extends EditOp {
  const WhiteoutOp(super.id, super.page, this.box, {this.argb = 0xFFFFFFFF});
  final Box box;
  final int argb;

  @override
  Box get bounds => box;

  @override
  WhiteoutOp moved(double dx, double dy) => WhiteoutOp(id, page, box.shift(dx, dy), argb: argb);

  WhiteoutOp withBox(Box b) => WhiteoutOp(id, page, b, argb: argb);

  @override
  Map<String, dynamic> toJson() => {'type': 'whiteout', 'id': id, 'page': page, 'box': box.toJson(), 'argb': argb};
}

class ShapeOp extends EditOp {
  const ShapeOp({
    required String id,
    required int page,
    required this.kind,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.strokeArgb = 0xFFE53935,
    this.fillArgb,
    this.width = 2,
  }) : super(id, page);

  final ShapeKind kind;
  final double x1, y1, x2, y2, width;
  final int strokeArgb;
  final int? fillArgb;

  @override
  Box get bounds => Box.fromCorners(x1, y1, x2, y2).inflate(width + (kind == ShapeKind.arrow ? 8 : 0));

  ShapeOp copyWith({double? x1, double? y1, double? x2, double? y2, int? strokeArgb, Object? fillArgb = _keep, double? width}) =>
      ShapeOp(
        id: id,
        page: page,
        kind: kind,
        x1: x1 ?? this.x1,
        y1: y1 ?? this.y1,
        x2: x2 ?? this.x2,
        y2: y2 ?? this.y2,
        strokeArgb: strokeArgb ?? this.strokeArgb,
        fillArgb: identical(fillArgb, _keep) ? this.fillArgb : fillArgb as int?,
        width: width ?? this.width,
      );

  @override
  ShapeOp moved(double dx, double dy) => copyWith(x1: x1 + dx, y1: y1 + dy, x2: x2 + dx, y2: y2 + dy);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'shape',
        'id': id,
        'page': page,
        'kind': kind.name,
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'stroke': strokeArgb,
        'fill': fillArgb,
        'width': width,
      };
}

const Object _keep = Object();

class MarkupOp extends EditOp {
  const MarkupOp({required String id, required int page, required this.kind, required this.rects, required this.argb})
      : super(id, page);
  final MarkupKind kind;
  final List<Box> rects;
  final int argb;

  @override
  Box get bounds => rects.reduce((a, b) => a.union(b));

  @override
  MarkupOp moved(double dx, double dy) =>
      MarkupOp(id: id, page: page, kind: kind, rects: [for (final r in rects) r.shift(dx, dy)], argb: argb);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'markup',
        'id': id,
        'page': page,
        'kind': kind.name,
        'rects': [for (final r in rects) r.toJson()],
        'argb': argb,
      };
}

class InkOp extends EditOp {
  const InkOp({
    required String id,
    required int page,
    required this.points,
    required this.argb,
    this.width = 2,
    this.highlight = false,
  }) : super(id, page);

  final List<(double, double)> points;
  final int argb;
  final double width;
  final bool highlight;

  @override
  Box get bounds {
    var l = points.first.$1, r = l, t = points.first.$2, b = t;
    for (final p in points) {
      if (p.$1 < l) l = p.$1;
      if (p.$1 > r) r = p.$1;
      if (p.$2 < t) t = p.$2;
      if (p.$2 > b) b = p.$2;
    }
    return Box(l, t, r, b).inflate(width);
  }

  @override
  InkOp moved(double dx, double dy) => InkOp(
        id: id,
        page: page,
        points: [for (final p in points) (p.$1 + dx, p.$2 + dy)],
        argb: argb,
        width: width,
        highlight: highlight,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'ink',
        'id': id,
        'page': page,
        'points': [for (final p in points) [p.$1, p.$2]],
        'argb': argb,
        'width': width,
        'highlight': highlight,
      };
}

class ImageOp extends EditOp {
  const ImageOp(super.id, super.page, this.box, this.data);
  final Box box;

  /// Encoded image (PNG/JPEG/...).
  final Uint8List data;

  @override
  Box get bounds => box;

  ImageOp withBox(Box b) => ImageOp(id, page, b, data);

  @override
  ImageOp moved(double dx, double dy) => withBox(box.shift(dx, dy));

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'image', 'id': id, 'page': page, 'box': box.toJson(), 'data': base64Encode(data)};
}

class SymbolOp extends EditOp {
  const SymbolOp(super.id, super.page, this.kind, this.box, this.argb);
  final SymbolKind kind;
  final Box box;
  final int argb;

  @override
  Box get bounds => box;

  SymbolOp withBox(Box b) => SymbolOp(id, page, kind, b, argb);

  @override
  SymbolOp moved(double dx, double dy) => withBox(box.shift(dx, dy));

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'symbol', 'id': id, 'page': page, 'kind': kind.name, 'box': box.toJson(), 'argb': argb};
}

class LinkOp extends EditOp {
  const LinkOp(super.id, super.page, this.box, this.uri);
  final Box box;
  final String uri;

  @override
  Box get bounds => box;

  LinkOp withBox(Box b) => LinkOp(id, page, b, uri);

  @override
  LinkOp moved(double dx, double dy) => withBox(box.shift(dx, dy));

  @override
  Map<String, dynamic> toJson() => {'type': 'link', 'id': id, 'page': page, 'box': box.toJson(), 'uri': uri};
}

/// Deletes an existing image object from the page (PDFium object index).
class DeleteImageOp extends EditOp {
  const DeleteImageOp(super.id, super.page, this.objectIndex, this.box);
  final int objectIndex;
  final Box box;

  @override
  Box get bounds => box;

  @override
  DeleteImageOp moved(double dx, double dy) => this;

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'deleteImage', 'id': id, 'page': page, 'objectIndex': objectIndex, 'box': box.toJson()};
}

/// Page-level change that rewrites the working file.
sealed class StructAction {
  const StructAction();
  Map<String, dynamic> toJson();

  static StructAction fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'delete':
        return DeletePages((j['pages'] as List).cast<int>());
      case 'rotate':
        return RotatePages((j['pages'] as List).cast<int>(), j['degrees'] as int);
      case 'insertBlank':
        return InsertBlank(j['index'] as int, (j['w'] as num?)?.toDouble(), (j['h'] as num?)?.toDouble());
      case 'insertFrom':
        return InsertFromFile(j['index'] as int, j['path'] as String, j['range'] as String?);
      case 'move':
        return MovePage(j['from'] as int, j['to'] as int);
    }
    throw FormatException('Unknown action ${j['type']}');
  }
}

class DeletePages extends StructAction {
  const DeletePages(this.pages);
  final List<int> pages;
  @override
  Map<String, dynamic> toJson() => {'type': 'delete', 'pages': pages};
}

class RotatePages extends StructAction {
  const RotatePages(this.pages, this.degrees);
  final List<int> pages;
  final int degrees;
  @override
  Map<String, dynamic> toJson() => {'type': 'rotate', 'pages': pages, 'degrees': degrees};
}

class InsertBlank extends StructAction {
  const InsertBlank(this.index, [this.width, this.height]);
  final int index;
  final double? width, height;
  @override
  Map<String, dynamic> toJson() => {'type': 'insertBlank', 'index': index, 'w': width, 'h': height};
}

class InsertFromFile extends StructAction {
  const InsertFromFile(this.index, this.path, [this.range]);
  final int index;
  final String path;
  final String? range;
  @override
  Map<String, dynamic> toJson() => {'type': 'insertFrom', 'index': index, 'path': path, 'range': range};
}

class MovePage extends StructAction {
  const MovePage(this.from, this.to);
  final int from, to;
  @override
  Map<String, dynamic> toJson() => {'type': 'move', 'from': from, 'to': to};
}
