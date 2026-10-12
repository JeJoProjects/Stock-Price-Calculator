import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../pdfedit/asset_store.dart';
import '../../pdfedit/edit_model.dart';
import '../../theme/app_theme.dart';
import 'editor_controller.dart';

/// What the toolbar can ask the panel to do (anything that needs dialogs,
/// files or the document session).
class ToolbarActions {
  const ToolbarActions({
    required this.findReplace,
    required this.newSignature,
    required this.placeSignature,
    required this.deleteSignature,
    required this.newImage,
    required this.newStamp,
    required this.placeStamp,
    required this.deleteStamp,
    required this.formFieldSoon,
    required this.undo,
    required this.redo,
  });

  final VoidCallback findReplace, newSignature, newImage, newStamp, undo, redo;
  final void Function(StoredAsset) placeSignature, deleteSignature, deleteStamp;
  final void Function(Uint8List png) placeStamp;
  final void Function(String what) formFieldSoon;
}

/// A stamp offered in the Images menu.
class StampEntry {
  const StampEntry(this.label, this.png, {this.asset});
  final String label;
  final Uint8List png;

  /// Non-null for user-made stamps (can be deleted).
  final StoredAsset? asset;
}

const _annotationPalette = [0xFFFFEB3B, 0xFFE53935, 0xFF43A047, 0xFF29B6F6, 0xFF111111];

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.ctrl,
    required this.actions,
    required this.signatures,
    required this.stamps,
    required this.canUndo,
    required this.canRedo,
    required this.hasDoc,
  });

  final EditorController ctrl;
  final ToolbarActions actions;
  final List<StoredAsset> signatures;
  final List<StampEntry> stamps;
  final bool canUndo, canRedo, hasDoc;

  @override
  Widget build(BuildContext context) {
    final t = ctrl.tool;
    return MenuTheme(
      data: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.bgSecondary),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Group(children: [
            _SplitTool(
              label: 'Text',
              icon: Icons.text_fields_rounded,
              active: t == EditorTool.text,
              enabled: hasDoc,
              onPressed: () => ctrl.setTool(EditorTool.text),
              menu: (close) => [
                _item(Icons.find_replace_rounded, 'Find & Replace', () {
                  close();
                  actions.findReplace();
                }),
              ],
            ),
            _ToolButton(
              label: 'Links',
              icon: Icons.link_rounded,
              active: t == EditorTool.links,
              enabled: hasDoc,
              onPressed: () => ctrl.setTool(EditorTool.links),
            ),
            _MenuTool(
              label: 'Forms',
              icon: Icons.list_alt_rounded,
              active: t == EditorTool.symbol,
              enabled: hasDoc,
              menu: _formsMenu,
            ),
            _MenuTool(
              label: 'Images',
              icon: Icons.image_outlined,
              active: t == EditorTool.placeImage || t == EditorTool.deleteImage,
              enabled: hasDoc,
              menu: _imagesMenu,
            ),
            _MenuTool(
              label: 'Sign',
              icon: Icons.draw_outlined,
              active: false,
              enabled: hasDoc,
              menu: _signMenu,
            ),
            _ToolButton(
              label: 'Whiteout',
              icon: Icons.auto_fix_normal_outlined,
              active: t == EditorTool.whiteout,
              enabled: hasDoc,
              onPressed: () => ctrl.setTool(EditorTool.whiteout),
            ),
            _MenuTool(
              label: 'Annotate',
              icon: Icons.brush_outlined,
              active: t.isMarkup || t.isFreehand,
              enabled: hasDoc,
              menu: _annotateMenu,
            ),
            _MenuTool(
              label: 'Shapes',
              icon: Icons.category_outlined,
              active: t.isShape,
              enabled: hasDoc,
              menu: _shapesMenu,
            ),
            _ToolButton(
              label: 'Undo',
              icon: Icons.undo_rounded,
              active: false,
              enabled: hasDoc && canUndo,
              onPressed: actions.undo,
              tooltip: 'Undo (Ctrl+Z)',
            ),
            _ToolButton(
              label: 'Redo',
              icon: Icons.redo_rounded,
              active: false,
              enabled: hasDoc && canRedo,
              onPressed: actions.redo,
              tooltip: 'Redo (Ctrl+Y)',
            ),
          ]),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ menus ---

  List<Widget> _formsMenu(VoidCallback close) => [
        const _Section('ADD TEXT AND SYMBOLS'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _IconChip(
              tooltip: 'Text',
              child: const Icon(Icons.text_fields_rounded, size: 18),
              onTap: () {
                close();
                ctrl.setTool(EditorTool.text);
              },
            ),
            const SizedBox(width: 18),
            for (final (k, g, tip) in const [
              (SymbolKind.cross, '✕', 'Cross'),
              (SymbolKind.check, '✓', 'Check mark'),
              (SymbolKind.square, '■', 'Filled square'),
              (SymbolKind.dot, '●', 'Dot'),
            ])
              _IconChip(
                tooltip: tip,
                child: Text(g, style: const TextStyle(fontSize: 18, color: AppColors.textPrimary)),
                onTap: () {
                  close();
                  ctrl.pickSymbol(k);
                },
              ),
          ]),
        ),
        const _Section('ADD NEW FORM FIELDS'),
        for (final (icon, label) in const [
          (Icons.text_snippet_outlined, 'Text'),
          (Icons.radio_button_checked_rounded, 'Radio button'),
          (Icons.notes_rounded, 'Text multiline'),
          (Icons.check_box_outlined, 'Checkbox'),
          (Icons.arrow_drop_down_circle_outlined, 'Drop-down list'),
          (Icons.border_color_outlined, 'Signature box'),
        ])
          _item(icon, label, () {
            close();
            actions.formFieldSoon(label);
          }, soon: true),
        _item(Icons.auto_awesome_outlined, 'Detect fields', () {
          close();
          actions.formFieldSoon('Detect fields');
        }, soon: true),
        const _Section('CHANGE EXISTING FORM FIELDS'),
        _item(Icons.toggle_off_outlined, 'Form Edit mode', () {
          close();
          actions.formFieldSoon('Form Edit mode');
        }, soon: true),
        _item(Icons.swap_vert_rounded, 'Change tab order', () {
          close();
          actions.formFieldSoon('Change tab order');
        }, soon: true),
      ];

  List<Widget> _imagesMenu(VoidCallback close) => [
        const _Section('STAMPS'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: SizedBox(
            width: 250,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final st in stamps)
                Stack(clipBehavior: Clip.none, children: [
                  Tooltip(
                    message: 'Place "${st.label}"',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        close();
                        actions.placeStamp(st.png);
                      },
                      child: Container(
                        height: 40,
                        constraints: const BoxConstraints(minWidth: 70),
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                        child: Image.memory(st.png, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  if (st.asset != null)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: _RoundX(onTap: () {
                        close();
                        actions.deleteStamp(st.asset!);
                      }),
                    ),
                ]),
            ]),
          ),
        ),
        const Divider(height: 14, color: AppColors.border),
        _item(Icons.add_rounded, 'New Image', () {
          close();
          actions.newImage();
        }),
        _item(Icons.hide_image_outlined, 'Delete existing image', () {
          close();
          ctrl.setTool(EditorTool.deleteImage);
        }),
        const Divider(height: 14, color: AppColors.border),
        _item(Icons.approval_rounded, 'New Stamp', () {
          close();
          actions.newStamp();
        }),
      ];

  List<Widget> _signMenu(VoidCallback close) => [
        if (signatures.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Text('No saved signatures yet.\nCreate one - it will be remembered.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4)),
          ),
        for (final a in signatures)
          InkWell(
            onTap: () {
              close();
              actions.placeSignature(a);
            },
            child: Container(
              width: 270,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(children: [
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                    alignment: Alignment.centerLeft,
                    child: Image.memory(a.bytes, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Delete this signature',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () {
                    close();
                    actions.deleteSignature(a);
                  },
                  icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                ),
              ]),
            ),
          ),
        const Divider(height: 10, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: OutlinedButton.icon(
            onPressed: () {
              close();
              actions.newSignature();
            },
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('New Signature'),
          ),
        ),
      ];

  List<Widget> _annotateMenu(VoidCallback close) => [
        CheckboxMenuButton(
          value: ctrl.showAnnotations,
          onChanged: (_) {
            ctrl.toggleAnnotations();
            close();
          },
          child: const Text('Show annotations'),
        ),
        const _Section('TEXT'),
        _colorRow(Icons.strikethrough_s_rounded, 'Strike out', EditorTool.strikeout, const [0xFFE53935, 0xFF29B6F6, 0xFFFFEB3B], close),
        _colorRow(Icons.border_color_rounded, 'Highlight', EditorTool.highlight, _annotationPalette, close),
        _colorRow(Icons.format_underlined_rounded, 'Underline', EditorTool.underline, _annotationPalette, close),
        const _Section('FREEHAND'),
        _colorRow(Icons.border_color_rounded, 'Highlight', EditorTool.freeHighlight, _annotationPalette, close),
        _colorRow(Icons.gesture_rounded, 'Draw', EditorTool.draw, _annotationPalette, close),
      ];

  Widget _colorRow(IconData icon, String label, EditorTool tool, List<int> palette, VoidCallback close) {
    final current = ctrl.annotationColors[tool];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: SizedBox(
        width: 250,
        child: Row(children: [
          InkWell(
            onTap: () {
              close();
              ctrl.setTool(tool);
            },
            child: SizedBox(
              width: 120,
              child: Row(children: [
                Icon(icon, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ),
          const Spacer(),
          for (final c in palette)
            GestureDetector(
              onTap: () {
                ctrl.annotationColors[tool] = c;
                close();
                ctrl.setTool(tool);
              },
              child: Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Color(c), width: 1.6),
                  color: current == c && ctrl.tool == tool ? Color(c) : Colors.transparent,
                ),
              ),
            ),
        ]),
      ),
    );
  }

  List<Widget> _shapesMenu(VoidCallback close) => [
        for (final (icon, label, tool) in const [
          (Icons.circle_outlined, 'Ellipse', EditorTool.ellipse),
          (Icons.crop_square_rounded, 'Rectangle', EditorTool.rectangle),
          (Icons.horizontal_rule_rounded, 'Line', EditorTool.line),
          (Icons.arrow_right_alt_rounded, 'Arrow', EditorTool.arrow),
        ])
          _item(icon, label, () {
            close();
            ctrl.setTool(tool);
          }),
      ];

  Widget _item(IconData icon, String label, VoidCallback onTap, {bool soon = false}) => MenuItemButton(
        onPressed: onTap,
        leadingIcon: Icon(icon, size: 17, color: soon ? AppColors.textMuted : AppColors.textPrimary),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 13, color: soon ? AppColors.textMuted : AppColors.textPrimary)),
          if (soon) ...[
            const SizedBox(width: 8),
            const Text('soon', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ]),
      );
}

// ------------------------------------------------------------------ widgets ---

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Container(width: 1, height: 30, color: AppColors.border),
            children[i],
          ],
        ]),
      );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.enabled,
    required this.onPressed,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final bool active, enabled;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final color = !enabled ? AppColors.textMuted.withValues(alpha: 0.5) : (active ? Colors.white : AppColors.textPrimary);
    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          color: active ? AppColors.accentBlue : Colors.transparent,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12.5, color: color)),
          ]),
        ),
      ),
    );
  }
}

/// A button that opens a dropdown menu (Forms, Images, Sign, Annotate, Shapes).
class _MenuTool extends StatelessWidget {
  const _MenuTool({required this.label, required this.icon, required this.active, required this.enabled, required this.menu});

  final String label;
  final IconData icon;
  final bool active, enabled;
  final List<Widget> Function(VoidCallback close) menu;

  @override
  Widget build(BuildContext context) {
    final controller = MenuController();
    return MenuAnchor(
      controller: controller,
      menuChildren: menu(controller.close),
      builder: (context, c, _) {
        final color = !enabled ? AppColors.textMuted.withValues(alpha: 0.5) : (active ? Colors.white : AppColors.textPrimary);
        return InkWell(
          onTap: !enabled ? null : () => c.isOpen ? c.close() : c.open(),
          child: Container(
            height: 34,
            padding: const EdgeInsets.only(left: 11, right: 6),
            color: active ? AppColors.accentBlue : Colors.transparent,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, color: color)),
              Icon(Icons.arrow_drop_down_rounded, size: 18, color: color),
            ]),
          ),
        );
      },
    );
  }
}

/// Main click selects the tool; the arrow opens extra options (Text -> Find & Replace).
class _SplitTool extends StatelessWidget {
  const _SplitTool({
    required this.label,
    required this.icon,
    required this.active,
    required this.enabled,
    required this.onPressed,
    required this.menu,
  });

  final String label;
  final IconData icon;
  final bool active, enabled;
  final VoidCallback onPressed;
  final List<Widget> Function(VoidCallback close) menu;

  @override
  Widget build(BuildContext context) {
    final controller = MenuController();
    final color = !enabled ? AppColors.textMuted.withValues(alpha: 0.5) : (active ? Colors.white : AppColors.textPrimary);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Tooltip(
        message: 'Text tool: click text to edit it, or click anywhere to add text (T)',
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Container(
            height: 34,
            padding: const EdgeInsets.only(left: 11, right: 8),
            color: active ? AppColors.accentBlue : Colors.transparent,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, color: color)),
            ]),
          ),
        ),
      ),
      Container(width: 1, height: 20, color: active ? Colors.white24 : AppColors.border),
      MenuAnchor(
        controller: controller,
        menuChildren: menu(controller.close),
        builder: (context, c, _) => InkWell(
          onTap: !enabled ? null : () => c.isOpen ? c.close() : c.open(),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            color: active ? AppColors.accentBlue : Colors.transparent,
            child: Icon(Icons.arrow_drop_down_rounded, size: 18, color: color),
          ),
        ),
      ),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: 250,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        color: AppColors.bgInput.withValues(alpha: 0.55),
        child: Text(text, style: const TextStyle(fontSize: 10, letterSpacing: 0.6, color: AppColors.textMuted)),
      );
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.child, required this.onTap, required this.tooltip});
  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(6), child: child),
        ),
      );
}

class _RoundX extends StatelessWidget {
  const _RoundX({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(color: AppColors.lossRed, shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, size: 11, color: Colors.white),
        ),
      );
}
