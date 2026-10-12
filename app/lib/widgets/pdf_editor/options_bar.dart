import 'package:flutter/material.dart';
import '../../pdfedit/doc_session.dart';
import '../../pdfedit/edit_model.dart';
import '../../pdfedit/fonts.dart';
import '../../theme/app_theme.dart';
import 'editor_controller.dart';

const _palette = [
  0xFF000000, 0xFF424242, 0xFF9E9E9E, 0xFFFFFFFF, //
  0xFFE53935, 0xFFFB8C00, 0xFFFFEB3B, 0xFF43A047, //
  0xFF00897B, 0xFF29B6F6, 0xFF1E3A8A, 0xFF8E24AA,
];

/// Context-sensitive properties bar: shows exactly the controls that matter
/// for the active tool or the selected object, and applies edits to the
/// selection immediately (plus remembers them as the defaults for next time).
class OptionsBar extends StatelessWidget {
  const OptionsBar({super.key, required this.ctrl, required this.session, required this.onDelete});

  final EditorController ctrl;
  final PdfDocSession? session;
  final VoidCallback onDelete;

  List<EditOp> get _selection {
    final s = session;
    if (s == null) return const [];
    return [for (final id in ctrl.selected) if (s.opById(id) != null) s.opById(id)!];
  }

  void _applyToSelection<T extends EditOp>(T Function(T) f) {
    final s = session;
    if (s == null) return;
    final sel = _selection.whereType<T>().toList();
    if (sel.isEmpty) return;
    s.addOpsReplacing([for (final o in sel) f(o)]);
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selection;
    final tool = ctrl.tool;
    final children = <Widget>[];

    final textSel = sel.whereType<TextOp>().toList();
    final shapeSel = sel.whereType<ShapeOp>().toList();
    final isText = textSel.isNotEmpty || (sel.isEmpty && tool == EditorTool.text);
    final isShape = shapeSel.isNotEmpty || (sel.isEmpty && tool.isShape);

    if (isText) {
      final t = textSel.isNotEmpty ? textSel.first : null;
      final family = t?.fontFamily ?? ctrl.fontFamily;
      final size = t?.size ?? ctrl.fontSize;
      final bold = t?.bold ?? ctrl.bold;
      final italic = t?.italic ?? ctrl.italic;
      final color = t?.argb ?? ctrl.textColor;
      children.addAll([
        _label('Font'),
        _FamilyDropdown(
          value: family,
          onChanged: (f) {
            ctrl.fontFamily = f;
            _applyToSelection<TextOp>((o) => o.copyWith(fontFamily: f));
            ctrl.changed();
          },
        ),
        _label('Size'),
        _SizeStepper(
          value: size,
          onChanged: (v) {
            ctrl.fontSize = v;
            _applyToSelection<TextOp>((o) => o.copyWith(size: v));
            ctrl.changed();
          },
        ),
        _toggle('B', bold, FontWeight.bold, FontStyle.normal, 'Bold', () {
          ctrl.bold = !bold;
          _applyToSelection<TextOp>((o) => o.copyWith(bold: !bold));
          ctrl.changed();
        }),
        _toggle('I', italic, FontWeight.normal, FontStyle.italic, 'Italic', () {
          ctrl.italic = !italic;
          _applyToSelection<TextOp>((o) => o.copyWith(italic: !italic));
          ctrl.changed();
        }),
        _label('Colour'),
        ColorButton(
          color: color,
          onChanged: (c) {
            ctrl.textColor = c!;
            _applyToSelection<TextOp>((o) => o.copyWith(argb: c));
            ctrl.changed();
          },
        ),
      ]);
    } else if (isShape) {
      final sh = shapeSel.isNotEmpty ? shapeSel.first : null;
      final stroke = sh?.strokeArgb ?? ctrl.strokeColor;
      final fill = sh != null ? sh.fillArgb : ctrl.fillColor;
      final width = sh?.width ?? ctrl.strokeWidth;
      final closed = sh == null ? (tool == EditorTool.ellipse || tool == EditorTool.rectangle) : (sh.kind == ShapeKind.ellipse || sh.kind == ShapeKind.rectangle);
      children.addAll([
        _label('Border'),
        ColorButton(
          color: stroke,
          onChanged: (c) {
            ctrl.strokeColor = c!;
            _applyToSelection<ShapeOp>((o) => o.copyWith(strokeArgb: c));
            ctrl.changed();
          },
        ),
        if (closed) ...[
          _label('Fill'),
          ColorButton(
            color: fill,
            allowNone: true,
            onChanged: (c) {
              ctrl.fillColor = c;
              _applyToSelection<ShapeOp>((o) => o.copyWith(fillArgb: c));
              ctrl.changed();
            },
          ),
        ],
        _label('Width'),
        SizedBox(
          width: 130,
          child: Slider(
            value: width.clamp(0.5, 12),
            min: 0.5,
            max: 12,
            onChanged: (v) {
              ctrl.strokeWidth = v;
              _applyToSelection<ShapeOp>((o) => o.copyWith(width: v));
              ctrl.changed();
            },
          ),
        ),
        Text(width.toStringAsFixed(1), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ]);
    } else if (tool.isMarkup || tool.isFreehand || tool == EditorTool.symbol || tool == EditorTool.whiteout || sel.any((o) => o is MarkupOp || o is InkOp || o is SymbolOp || o is WhiteoutOp)) {
      final key = sel.isNotEmpty
          ? switch (sel.first) {
              MarkupOp(kind: MarkupKind.strikeout) => EditorTool.strikeout,
              MarkupOp(kind: MarkupKind.underline) => EditorTool.underline,
              MarkupOp() => EditorTool.highlight,
              InkOp(highlight: true) => EditorTool.freeHighlight,
              InkOp() => EditorTool.draw,
              SymbolOp() => EditorTool.symbol,
              _ => EditorTool.whiteout,
            }
          : tool;
      final color = sel.isNotEmpty ? _opColor(sel.first) : ctrl.annotationColors[key]!;
      children.addAll([
        _label(tool == EditorTool.whiteout || key == EditorTool.whiteout ? 'Cover colour' : 'Colour'),
        ColorButton(
          color: color,
          onChanged: (c) {
            ctrl.annotationColors[key] = c!;
            _recolorSelection(c);
            ctrl.changed();
          },
        ),
        if (key == EditorTool.draw) ...[
          _label('Pen'),
          SizedBox(
            width: 130,
            child: Slider(value: ctrl.strokeWidth.clamp(0.5, 12), min: 0.5, max: 12, onChanged: (v) {
              ctrl.strokeWidth = v;
              ctrl.changed();
            }),
          ),
        ],
      ]);
    }

    final hint = sel.isNotEmpty ? 'Selected: ${_describe(sel)}' : tool.hint;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(sel.isNotEmpty ? 'Properties' : tool.label,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              if (children.isNotEmpty) Container(width: 1, height: 18, color: AppColors.border),
              ...children,
              if (children.isEmpty)
                Text(hint, style: const TextStyle(color: AppColors.textMuted, fontSize: 12))
              else
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(sel.isNotEmpty ? '' : '', style: const TextStyle(fontSize: 1)),
                ),
            ],
          ),
        ),
        if (sel.isNotEmpty)
          TextButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.lossRed),
          ),
      ]),
    );
  }

  int _opColor(EditOp o) => switch (o) {
        MarkupOp() => o.argb,
        InkOp() => o.argb,
        SymbolOp() => o.argb,
        WhiteoutOp() => o.argb,
        _ => 0xFF000000,
      };

  void _recolorSelection(int c) {
    final s = session;
    if (s == null) return;
    final next = <EditOp>[];
    for (final o in _selection) {
      switch (o) {
        case MarkupOp():
          next.add(MarkupOp(id: o.id, page: o.page, kind: o.kind, rects: o.rects, argb: c));
        case InkOp():
          next.add(InkOp(id: o.id, page: o.page, points: o.points, argb: c, width: o.width, highlight: o.highlight));
        case SymbolOp():
          next.add(SymbolOp(o.id, o.page, o.kind, o.box, c));
        case WhiteoutOp():
          next.add(WhiteoutOp(o.id, o.page, o.box, argb: c));
        default:
      }
    }
    if (next.isNotEmpty) s.addOpsReplacing(next);
  }

  String _describe(List<EditOp> sel) {
    if (sel.length > 1) return '${sel.length} objects';
    return switch (sel.first) {
      TextOp() => 'text',
      WhiteoutOp() => 'whiteout',
      ShapeOp(kind: final k) => k.name,
      MarkupOp(kind: final k) => k.name,
      InkOp() => 'drawing',
      ImageOp() => 'image',
      SymbolOp() => 'symbol',
      LinkOp() => 'link',
      DeleteImageOp() => 'removed image',
    };
  }

  Widget _label(String t) => Text(t, style: const TextStyle(color: AppColors.textMuted, fontSize: 12));

  Widget _toggle(String label, bool on, FontWeight w, FontStyle st, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.accentBlue : AppColors.bgInput,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label, style: TextStyle(fontWeight: w, fontStyle: st, fontSize: 14, color: on ? Colors.white : AppColors.textPrimary)),
          ),
        ),
      );
}

class _FamilyDropdown extends StatelessWidget {
  const _FamilyDropdown({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final fams = FontCatalog.availableFamilies();
    final items = fams.contains(value) ? fams : [value, ...fams];
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: AppColors.bgInput, borderRadius: BorderRadius.circular(6)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: AppColors.bgSecondary,
          style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
          items: [for (final f in items) DropdownMenuItem(value: f, child: Text(f))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _SizeStepper extends StatelessWidget {
  const _SizeStepper({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, double d, String tip) => Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onChanged((value + d).clamp(4, 300).toDouble()),
            child: Container(
              width: 26,
              height: 28,
              alignment: Alignment.center,
              child: Icon(i, size: 16),
            ),
          ),
        );
    final label = value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);
    return Container(
      height: 28,
      decoration: BoxDecoration(color: AppColors.bgInput, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove_rounded, -1, 'Smaller'),
        SizedBox(width: 30, child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5))),
        btn(Icons.add_rounded, 1, 'Larger'),
      ]),
    );
  }
}

/// Colour swatch that opens a small palette.
class ColorButton extends StatelessWidget {
  const ColorButton({super.key, required this.color, required this.onChanged, this.allowNone = false});

  final int? color;
  final ValueChanged<int?> onChanged;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final controller = MenuController();
    return MenuAnchor(
      controller: controller,
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.bgSecondary),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            width: 176,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (allowNone)
                _dot(null, controller, selected: color == null),
              for (final c in _palette) _dot(c, controller, selected: color == c),
            ]),
          ),
        ),
      ],
      builder: (context, c, _) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => c.isOpen ? c.close() : c.open(),
        child: Container(
          width: 36,
          height: 28,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: AppColors.bgInput, borderRadius: BorderRadius.circular(6)),
          child: Container(
            decoration: BoxDecoration(
              color: color == null ? Colors.transparent : Color(color!),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.border),
            ),
            child: color == null ? const Icon(Icons.block_rounded, size: 14, color: AppColors.textMuted) : null,
          ),
        ),
      ),
    );
  }

  Widget _dot(int? c, MenuController mc, {required bool selected}) => GestureDetector(
        onTap: () {
          mc.close();
          onChanged(c);
        },
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: c == null ? Colors.transparent : Color(c),
            shape: BoxShape.circle,
            border: Border.all(color: selected ? AppColors.accentBlue : AppColors.border, width: selected ? 2.5 : 1),
          ),
          child: c == null ? const Icon(Icons.block_rounded, size: 16, color: AppColors.textMuted) : null,
        ),
      );
}
