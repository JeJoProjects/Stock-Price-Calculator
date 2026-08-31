/// Per-panel mutable state, ported from src/core/panelState.hpp.
/// Field parsing intentionally mirrors the old std::from_chars behavior:
/// no comma-stripping, so a typed comma silently parses as 0 (matches the
/// old app's actual behavior, not its idealized one).
class PanelState {
  final int id;
  int displayIndex;

  String investmentText = '';
  String priceText = '';
  String sharesText = '';
  String targetText = '';

  String tickerSymbol = '';
  String companyName = '';
  String exchange = '';
  String matchPreview = '';

  int lastChanged = 0;
  int secondLastChanged = 0;

  PanelState({required this.id, this.displayIndex = 0});

  static double _parse(String text) {
    if (text.isEmpty) return 0.0;
    return double.tryParse(text) ?? 0.0;
  }

  double get investmentValue => _parse(investmentText);
  double get priceValue => _parse(priceText);
  double get sharesValue => _parse(sharesText);
  double get targetValue => _parse(targetText);

  void updateFieldTracking(int fieldId) {
    if (fieldId != lastChanged) {
      secondLastChanged = lastChanged;
      lastChanged = fieldId;
    }
  }

  void reset() {
    investmentText = '';
    priceText = '';
    sharesText = '';
    targetText = '';
    tickerSymbol = '';
    companyName = '';
    exchange = '';
    matchPreview = '';
    lastChanged = 0;
    secondLastChanged = 0;
  }
}
