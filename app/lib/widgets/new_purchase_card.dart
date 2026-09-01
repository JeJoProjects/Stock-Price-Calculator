import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Compact "add panel" button - a circular icon button rather than a
/// full-size dashed card, so it doesn't compete for space with real
/// purchase panels (redesigned per user feedback: the old full-card
/// placeholder wasted horizontal space and added visual clutter).
class NewPurchaseCard extends StatefulWidget {
  final VoidCallback onTap;
  const NewPurchaseCard({super.key, required this.onTap});

  @override
  State<NewPurchaseCard> createState() => _NewPurchaseCardState();
}

class _NewPurchaseCardState extends State<NewPurchaseCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = _hover ? AppColors.accentBlue : AppColors.textMuted;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: 'New Purchase (Ctrl+N)',
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hover ? AppColors.accentBlue.withValues(alpha: 0.14) : AppColors.bgSecondary,
              border: Border.all(color: color, width: 1.5),
            ),
            child: Icon(Icons.add_rounded, size: 26, color: color),
          ),
        ),
      ),
    );
  }
}
