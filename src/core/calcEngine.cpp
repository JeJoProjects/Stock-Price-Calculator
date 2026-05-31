#include "core/calcEngine.hpp"

namespace stockcalc {

PanelResult calculatePanel(const PanelInput& input) {
    double investment = input.totalInvestment;
    double price = input.sharePrice;
    double shares = input.totalShares;
    double target = input.targetPrice;
    auto last = static_cast<FieldId>(input.lastChanged);
    auto second = static_cast<FieldId>(input.secondLastChanged);
    int inferred = 0;

    if (last == FieldId::totalInvestment) {
        if (second == FieldId::totalShares && shares > 0.0) {
            investment = price * shares;
            inferred = 1;
        } else if (price > 0.0) {
            shares = investment / price;
            inferred = 3;
        }
    } else if (last == FieldId::sharePrice) {
        if (investment > 0.0 && price > 0.0) {
            shares = investment / price;
            inferred = 3;
        }
    } else if (last == FieldId::totalShares) {
        if (second == FieldId::totalInvestment && investment > 0.0 && shares > 0.0) {
            price = investment / shares;
            inferred = 2;
        } else if (price > 0.0) {
            investment = price * shares;
            inferred = 1;
        }
    } else {
        int nonzero = (investment > 0.0) + (price > 0.0) + (shares > 0.0);
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

    PanelResult result{};
    result.totalInvestment = investment;
    result.sharePrice = price;
    result.totalShares = shares;
    result.inferredField = inferred;

    if (target > 0.0 && shares > 0.0) {
        result.profitPlusInvest = target * shares;
        result.profit = result.profitPlusInvest - investment;
    }
    if (target > 0.0 && price > 0.0) {
        result.gainPercent = ((target - price) * 100.0) / price;
    }

    return result;
}

CombinedResult calculateCombined(std::span<const PanelResult> panels) {
    CombinedResult combined{};
    double weightedPrice = 0.0;

    for (const auto& p : panels) {
        bool valid = p.totalInvestment > 0.0 && p.sharePrice > 0.0 && p.totalShares > 0.0;
        if (valid) {
            combined.totalInvestment += p.totalInvestment;
            combined.totalShares += p.totalShares;
            combined.totalProfit += p.profit;
            weightedPrice += p.sharePrice * p.totalShares;
            combined.validCount++;
        }
    }

    if (combined.validCount > 0) {
        combined.avgSharePrice = combined.totalShares > 0.0
            ? weightedPrice / combined.totalShares : 0.0;
        combined.avgProfit = combined.totalProfit / combined.validCount;
    }

    return combined;
}

} // namespace stockcalc
