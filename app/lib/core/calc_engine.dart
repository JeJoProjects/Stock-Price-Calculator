/// Pure calculation core, ported 1:1 from the old C++ `stockcalc::calcEngine`
/// (src/core/calcEngine.cpp) for behavioral parity. See the migration plan's
/// "Calc engine" section for the known targetPrice field-tracking quirk this
/// preserves intentionally.
library;

enum FieldId {
  none(0),
  totalInvestment(1),
  sharePrice(2),
  totalShares(3),
  targetPrice(4),
  profitInvest(5),
  profit(6),
  percent(7);

  const FieldId(this.id);
  final int id;

  static FieldId fromId(int id) =>
      FieldId.values.firstWhere((f) => f.id == id, orElse: () => FieldId.none);
}

const kExcludedFields = {
  FieldId.none,
  FieldId.profit,
  FieldId.profitInvest,
  FieldId.targetPrice,
};

bool isValidTrackingField(FieldId field) => !kExcludedFields.contains(field);

class PanelInput {
  final double totalInvestment;
  final double sharePrice;
  final double totalShares;
  final double targetPrice;
  final int lastChanged;
  final int secondLastChanged;

  const PanelInput({
    this.totalInvestment = 0.0,
    this.sharePrice = 0.0,
    this.totalShares = 0.0,
    this.targetPrice = 0.0,
    this.lastChanged = 0,
    this.secondLastChanged = 0,
  });
}

class PanelResult {
  final double totalInvestment;
  final double sharePrice;
  final double totalShares;
  final double profitPlusInvest;
  final double profit;
  final double gainPercent;
  final int inferredField;

  const PanelResult({
    this.totalInvestment = 0.0,
    this.sharePrice = 0.0,
    this.totalShares = 0.0,
    this.profitPlusInvest = 0.0,
    this.profit = 0.0,
    this.gainPercent = 0.0,
    this.inferredField = 0,
  });
}

class CombinedResult {
  final double avgSharePrice;
  final double totalInvestment;
  final double totalShares;
  final double totalProfit;
  final double avgProfit;
  final int validCount;

  const CombinedResult({
    this.avgSharePrice = 0.0,
    this.totalInvestment = 0.0,
    this.totalShares = 0.0,
    this.totalProfit = 0.0,
    this.avgProfit = 0.0,
    this.validCount = 0,
  });
}

PanelResult calculatePanel(PanelInput input) {
  var investment = input.totalInvestment;
  var price = input.sharePrice;
  var shares = input.totalShares;
  final target = input.targetPrice;
  final last = FieldId.fromId(input.lastChanged);
  final second = FieldId.fromId(input.secondLastChanged);
  var inferred = 0;

  if (last == FieldId.totalInvestment) {
    if (second == FieldId.totalShares && shares > 0.0) {
      investment = price * shares;
      inferred = 1;
    } else if (price > 0.0) {
      shares = investment / price;
      inferred = 3;
    }
  } else if (last == FieldId.sharePrice) {
    if (investment > 0.0 && price > 0.0) {
      shares = investment / price;
      inferred = 3;
    }
  } else if (last == FieldId.totalShares) {
    if (second == FieldId.totalInvestment && investment > 0.0 && shares > 0.0) {
      price = investment / shares;
      inferred = 2;
    } else if (price > 0.0) {
      investment = price * shares;
      inferred = 1;
    }
  } else {
    final nonzero =
        (investment > 0.0 ? 1 : 0) + (price > 0.0 ? 1 : 0) + (shares > 0.0 ? 1 : 0);
    if (nonzero == 2) {
      if (investment <= 0.0 && price > 0.0 && shares > 0.0) {
        investment = price * shares;
        inferred = 1;
      } else if (price <= 0.0 && investment > 0.0 && shares > 0.0) {
        price = investment / shares;
        inferred = 2;
      } else if (shares <= 0.0 && investment > 0.0 && price > 0.0) {
        shares = investment / price;
        inferred = 3;
      }
    }
  }

  var profitPlusInvest = 0.0;
  var profit = 0.0;
  var gainPercent = 0.0;

  if (target > 0.0 && shares > 0.0) {
    profitPlusInvest = target * shares;
    profit = profitPlusInvest - investment;
  }
  if (target > 0.0 && price > 0.0) {
    gainPercent = ((target - price) * 100.0) / price;
  }

  return PanelResult(
    totalInvestment: investment,
    sharePrice: price,
    totalShares: shares,
    profitPlusInvest: profitPlusInvest,
    profit: profit,
    gainPercent: gainPercent,
    inferredField: inferred,
  );
}

CombinedResult calculateCombined(List<PanelResult> panels) {
  var totalInvestment = 0.0;
  var totalShares = 0.0;
  var totalProfit = 0.0;
  var weightedPrice = 0.0;
  var validCount = 0;

  for (final p in panels) {
    final valid = p.totalInvestment > 0.0 && p.sharePrice > 0.0 && p.totalShares > 0.0;
    if (valid) {
      totalInvestment += p.totalInvestment;
      totalShares += p.totalShares;
      totalProfit += p.profit;
      weightedPrice += p.sharePrice * p.totalShares;
      validCount++;
    }
  }

  final avgSharePrice = validCount > 0 && totalShares > 0.0 ? weightedPrice / totalShares : 0.0;
  final avgProfit = validCount > 0 ? totalProfit / validCount : 0.0;

  return CombinedResult(
    avgSharePrice: avgSharePrice,
    totalInvestment: totalInvestment,
    totalShares: totalShares,
    totalProfit: totalProfit,
    avgProfit: avgProfit,
    validCount: validCount,
  );
}
