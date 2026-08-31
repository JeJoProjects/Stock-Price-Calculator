import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Ported from Application::renderNewPurchaseCard (dashed placeholder card,
/// 8px dash / 6px gap, hover turns accent blue, click adds a panel).
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
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: kPanelWidth,
          child: CustomPaint(
            painter: _DashedBorderPainter(color: color, radius: kCardRadius),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 32, color: color),
                  const SizedBox(height: 8),
                  Text('New Purchase', style: TextStyle(color: color, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height.clamp(0, 400));
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const dashWidth = 8.0;
    const dashGap = 6.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}
