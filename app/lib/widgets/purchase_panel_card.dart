import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/calc_engine.dart';
import '../core/formatting.dart';
import '../core/panel_state.dart';
import '../theme/app_theme.dart';

/// One calculator card. Ported from Application::renderSinglePanel
/// (src/app/application.cpp:470-710): 4 numeric inputs with smart-inference
/// highlighting, then a profit/gain/shares summary once a result exists.
class PurchasePanelCard extends StatefulWidget {
  final PanelState panel;
  final PanelResult result;
  final bool canDelete;
  final void Function(int fieldId, String text) onFieldChanged;
  final VoidCallback onReset;
  final VoidCallback onDelete;

  const PurchasePanelCard({
    super.key,
    required this.panel,
    required this.result,
    required this.canDelete,
    required this.onFieldChanged,
    required this.onReset,
    required this.onDelete,
  });

  @override
  State<PurchasePanelCard> createState() => _PurchasePanelCardState();
}

class _PurchasePanelCardState extends State<PurchasePanelCard> {
  late final TextEditingController _investment;
  late final TextEditingController _price;
  late final TextEditingController _shares;
  late final TextEditingController _target;

  @override
  void initState() {
    super.initState();
    _investment = TextEditingController(text: widget.panel.investmentText);
    _price = TextEditingController(text: widget.panel.priceText);
    _shares = TextEditingController(text: widget.panel.sharesText);
    _target = TextEditingController(text: widget.panel.targetText);
  }

  @override
  void didUpdateWidget(covariant PurchasePanelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Inferred values get written back into the field (matches old
    // recalculateAll() writing helpers::formatValue into the text field).
    _syncIfExternallyChanged(_investment, widget.panel.investmentText);
    _syncIfExternallyChanged(_price, widget.panel.priceText);
    _syncIfExternallyChanged(_shares, widget.panel.sharesText);
    _syncIfExternallyChanged(_target, widget.panel.targetText);
  }

  void _syncIfExternallyChanged(TextEditingController c, String value) {
    if (c.text != value) {
      c.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  void dispose() {
    _investment.dispose();
    _price.dispose();
    _shares.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.panel;
    final r = widget.result;
    final hasTicker = p.tickerSymbol.isNotEmpty;
    final hasResult =
        r.totalInvestment > 0 || r.sharePrice > 0 || r.totalShares > 0 || r.profitPlusInvest != 0;

    return Container(
      width: kPanelWidth,
      margin: const EdgeInsets.only(right: kPanelSpacing),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Purchase ${p.displayIndex + 1}',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                if (widget.canDelete)
                  _HoverIconButton(
                    icon: Icons.close,
                    hoverColor: AppColors.lossRed,
                    onTap: widget.onDelete,
                  ),
              ],
            ),
            if (hasTicker) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(p.tickerSymbol,
                      style: const TextStyle(
                          color: AppColors.accentBlue,
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.companyName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ),
                ],
              ),
              if (p.matchPreview.isNotEmpty)
                Text(p.matchPreview,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
            const SizedBox(height: 12),
            _numericField('Total Investment (\$)', _investment, 1),
            const SizedBox(height: 10),
            _numericField('Share Price (\$)', _price, 2),
            const SizedBox(height: 10),
            _numericField('Number of Shares', _shares, 3),
            const SizedBox(height: 10),
            _numericField('Target Price (\$)', _target, 4),
            if (hasResult) ...[
              const SizedBox(height: 16),
              _summaryStrip(r),
              const SizedBox(height: 12),
              _detailRows(r),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: _ResetButton(onTap: widget.onReset),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numericField(String label, TextEditingController controller, int fieldId) {
    final isInferred = widget.result.inferredField == fieldId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kInputRadius),
            border: isInferred ? Border.all(color: AppColors.accentBlue, width: 2) : null,
          ),
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: TextStyle(
              color: isInferred ? AppColors.textMuted : AppColors.textPrimary,
              fontFamily: 'Consolas',
            ),
            onChanged: (text) => widget.onFieldChanged(fieldId, text),
          ),
        ),
        if (isInferred)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('AUTO: ${_fieldName(fieldId)}',
                style: const TextStyle(
                    color: AppColors.accentBlue, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }

  String _fieldName(int fieldId) => switch (fieldId) {
        1 => 'Investment',
        2 => 'Share Price',
        3 => 'Shares',
        _ => '',
      };

  Widget _summaryStrip(PanelResult r) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(8),
        border: const Border(top: BorderSide(color: AppColors.accentBlue, width: 2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _chip('Profit', formatProfit(r.profit), _profitColor(r.profit)),
          _chip('Gain', formatGain(r.gainPercent), _profitColor(r.gainPercent)),
          _chip('Shares', formatNumber(r.totalShares, decimals: 0), AppColors.textPrimary),
        ],
      ),
    );
  }

  Color _profitColor(double v) {
    if (v.abs() < 0.005) return AppColors.textMuted;
    return v > 0 ? AppColors.profitGreen : AppColors.lossRed;
  }

  Widget _chip(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
        Text(value,
            style: TextStyle(color: color, fontFamily: 'Consolas', fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _detailRows(PanelResult r) {
    final rows = <Widget>[];
    if (r.totalInvestment > 0) rows.add(_detailRow('Investment', formatCurrency(r.totalInvestment)));
    if (r.sharePrice > 0) rows.add(_detailRow('Price', formatCurrency(r.sharePrice)));
    if (r.totalShares > 0) rows.add(_detailRow('Shares', formatNumber(r.totalShares, decimals: 0)));
    if (r.profitPlusInvest != 0) {
      rows.add(_detailRow('Return', formatCurrency(r.profitPlusInvest)));
      rows.add(_detailRow('Profit', formatProfit(r.profit), color: _profitColor(r.profit)));
      rows.add(_detailRow('Gain %', formatGain(r.gainPercent), color: _profitColor(r.gainPercent)));
    }
    return Column(children: rows);
  }

  Widget _detailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          Text(value,
              style: TextStyle(
                  color: color ?? AppColors.textPrimary, fontFamily: 'Consolas', fontSize: 12)),
        ],
      ),
    );
  }
}

class _HoverIconButton extends StatefulWidget {
  final IconData icon;
  final Color hoverColor;
  final VoidCallback onTap;
  const _HoverIconButton({required this.icon, required this.hoverColor, required this.onTap});

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Icon(widget.icon,
            size: 16, color: _hover ? widget.hoverColor : AppColors.textMuted),
      ),
    );
  }
}

class _ResetButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ResetButton({required this.onTap});

  @override
  State<_ResetButton> createState() => _ResetButtonState();
}

class _ResetButtonState extends State<_ResetButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 60,
          padding: const EdgeInsets.symmetric(vertical: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _hover ? AppColors.lossRed : AppColors.border),
          ),
          child: Text('Reset',
              style: TextStyle(
                  fontSize: 11, color: _hover ? AppColors.lossRed : AppColors.textMuted)),
        ),
      ),
    );
  }
}
