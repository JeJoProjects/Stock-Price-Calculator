import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../core/formatting.dart';
import '../market/market_client.dart';
import '../market/market_types.dart';
import '../theme/app_theme.dart';

/// Ported from Application::renderChartPane (application.cpp:880-1163):
/// timeframe controls, candlestick canvas with hover tooltip, quote strip,
/// and quote-details section. Needs a real Finnhub key on the backend to
/// show live data - the empty/error states are otherwise fully functional.
class ChartPane extends StatefulWidget {
  final String? symbol;
  final String companyName;
  final String exchange;
  final MarketDataService client;

  const ChartPane({
    super.key,
    required this.symbol,
    required this.companyName,
    required this.exchange,
    required this.client,
  });

  @override
  State<ChartPane> createState() => _ChartPaneState();
}

class _ChartPaneState extends State<ChartPane> {
  Timeframe _timeframe = Timeframe.day1;
  MarketSnapshot? _snapshot;
  bool _loading = false;
  double? _hoverX;

  @override
  void didUpdateWidget(covariant ChartPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol) _fetch();
  }

  @override
  void initState() {
    super.initState();
    if (widget.symbol != null) _fetch();
  }

  Future<void> _fetch() async {
    final symbol = widget.symbol;
    if (symbol == null) return;
    setState(() => _loading = true);
    final snapshot = await widget.client.fetchSnapshot(symbol, _timeframe);
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
  }

  void _selectTimeframe(Timeframe tf) {
    if (tf == _timeframe) return;
    setState(() => _timeframe = tf);
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 260),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: Timeframe.values.map(_timeframeButton).toList()),
          ),
          const SizedBox(height: 12),
          if (widget.symbol == null)
            const Expanded(
              child: Center(
                child: Text('Search a ticker to load the live chart.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            )
          else ...[
            Expanded(child: _candlestickArea()),
            const SizedBox(height: 12),
            _quoteStrip(),
            if (_snapshot?.error != null) ...[
              const SizedBox(height: 8),
              Text(_snapshot!.error!,
                  style: const TextStyle(color: AppColors.lossRed, fontSize: 11)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _header() {
    final title = widget.symbol == null
        ? 'Search a symbol to load chart data'
        : (widget.companyName.isNotEmpty ? widget.companyName : widget.symbol!);
    final status = _loading ? 'Updating' : (_snapshot?.isValid == true ? 'Live' : 'Offline');
    final statusColor = _loading
        ? AppColors.accentBlue
        : (_snapshot?.isValid == true ? AppColors.profitGreen : AppColors.textMuted);
    return Row(
      children: [
        const Text('Market View',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ),
        Text(status, style: TextStyle(color: statusColor, fontSize: 11)),
      ],
    );
  }

  Widget _timeframeButton(Timeframe tf) {
    final active = tf == _timeframe;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 28),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: active ? AppColors.accentBlue : Colors.transparent,
          foregroundColor: active ? AppColors.white : AppColors.textMuted,
          side: BorderSide(color: active ? AppColors.accentBlue : AppColors.border),
        ),
        onPressed: () => _selectTimeframe(tf),
        child: Text(tf.label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _candlestickArea() {
    final candles = _snapshot?.candles ?? const [];
    if (_loading && candles.isEmpty) {
      return const Center(
          child: Text('Loading chart...', style: TextStyle(color: AppColors.textMuted, fontSize: 12)));
    }
    if (candles.isEmpty) {
      return const Center(
          child: Text('No candle data available.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)));
    }
    return MouseRegion(
      onHover: (e) => setState(() => _hoverX = e.localPosition.dx),
      onExit: (_) => setState(() => _hoverX = null),
      child: CustomPaint(
        painter: _CandlestickPainter(candles: candles, hoverX: _hoverX),
        size: Size.infinite,
      ),
    );
  }

  Widget _quoteStrip() {
    final q = _snapshot?.quote;
    final profile = _snapshot?.profile;
    if (q == null) return const SizedBox.shrink();
    final color = q.change >= 0 ? AppColors.profitGreen : AppColors.lossRed;
    return Row(
      children: [
        _stat('Last', formatCurrency(q.current), color),
        const SizedBox(width: 20),
        _stat('Change', '${q.change >= 0 ? '+' : ''}${formatCurrency(q.change)} (${formatGain(q.percent)})', color),
        const SizedBox(width: 20),
        _stat('Range', '${formatCurrency(q.low)} - ${formatCurrency(q.high)}', AppColors.textPrimary),
        const SizedBox(width: 20),
        if (profile != null && profile.marketCap > 0)
          _stat('Mkt Cap', formatCompactMarketCap(profile.marketCap * 1e6), AppColors.textPrimary),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
        Text(value, style: TextStyle(color: color, fontFamily: 'Consolas', fontSize: 12)),
      ],
    );
  }
}

class _CandlestickPainter extends CustomPainter {
  final List<Candle> candles;
  final double? hoverX;

  _CandlestickPainter({required this.candles, required this.hoverX});

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;
    var minPrice = candles.first.low;
    var maxPrice = candles.first.high;
    for (final c in candles) {
      if (c.low < minPrice) minPrice = c.low;
      if (c.high > maxPrice) maxPrice = c.high;
    }
    if ((maxPrice - minPrice).abs() < 0.01) {
      minPrice -= 0.5;
      maxPrice += 0.5;
    }
    final range = maxPrice - minPrice;

    final priceLabelWidth = 56.0;
    final chartWidth = size.width - priceLabelWidth;
    final slotWidth = chartWidth / candles.length;
    final bodyWidth = (slotWidth * 0.6).clamp(1.0, 12.0);

    double yFor(double price) => size.height - ((price - minPrice) / range) * size.height;

    final guidePaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: AppColors.textMuted.withValues(alpha: 0.8), fontSize: 10);
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(chartWidth, y), guidePaint);
      final price = maxPrice - range * i / 3;
      final tp = TextPainter(
        text: TextSpan(text: formatCurrency(price), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(chartWidth + 4, y - tp.height / 2));
    }

    int? hoverIndex;
    if (hoverX != null) {
      hoverIndex = (hoverX! / slotWidth).floor().clamp(0, candles.length - 1);
    }

    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final x = i * slotWidth + slotWidth / 2;
      final isUp = c.close >= c.open;
      final color = isUp ? AppColors.profitGreen : AppColors.lossRed;
      final wickPaint = Paint()..color = color;
      canvas.drawLine(Offset(x, yFor(c.high)), Offset(x, yFor(c.low)), wickPaint..strokeWidth = 1);

      final bodyTop = yFor(isUp ? c.close : c.open);
      final bodyBottom = yFor(isUp ? c.open : c.close);
      final bodyRect = Rect.fromLTRB(
        x - bodyWidth / 2,
        bodyTop,
        x + bodyWidth / 2,
        (bodyBottom - bodyTop).abs() < 1 ? bodyTop + 1 : bodyBottom,
      );
      canvas.drawRect(bodyRect, Paint()..color = color);

      if (hoverIndex == i) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = AppColors.accentBlue.withValues(alpha: 0.55)
            ..strokeWidth = 1,
        );
      }
    }

    if (hoverIndex != null) {
      final c = candles[hoverIndex];
      final dateStr = DateFormat('MMM d, HH:mm').format(c.dateTime);
      final text =
          '$dateStr\nO ${formatCurrency(c.open)}  H ${formatCurrency(c.high)}\nL ${formatCurrency(c.low)}  C ${formatCurrency(c.close)}\nV ${formatNumber(c.volume, decimals: 0)}';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontFamily: 'Consolas'),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 160);

      var tooltipX = hoverX! + 12;
      if (tooltipX + tp.width > chartWidth) tooltipX = hoverX! - tp.width - 12;
      final tooltipRect = Rect.fromLTWH(tooltipX - 6, 6, tp.width + 12, tp.height + 12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(tooltipRect, const Radius.circular(4)),
        Paint()..color = AppColors.bgPrimary.withValues(alpha: 0.92),
      );
      tp.paint(canvas, Offset(tooltipX, 12));
    }
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter oldDelegate) =>
      oldDelegate.candles != candles || oldDelegate.hoverX != hoverX;
}
