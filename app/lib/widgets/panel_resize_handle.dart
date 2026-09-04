import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A thin, draggable vertical splitter that sits between two side-by-side
/// panels - lets the user resize a fixed-width rail (like the screener
/// panel) instead of it being permanently locked at one width. The visible
/// line is 1px by default and thickens/turns accent-blue on hover or drag,
/// but the actual hit area is wider (10px) so it's easy to grab.
class PanelResizeHandle extends StatefulWidget {
  final ValueChanged<double> onDragDelta;
  final VoidCallback? onDragEnd;

  const PanelResizeHandle({super.key, required this.onDragDelta, this.onDragEnd});

  @override
  State<PanelResizeHandle> createState() => _PanelResizeHandleState();
}

class _PanelResizeHandleState extends State<PanelResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) => widget.onDragDelta(details.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd?.call();
        },
        child: SizedBox(
          width: 10,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: active ? 3 : 1,
              decoration: BoxDecoration(
                color: active ? AppColors.accentBlue : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
