#pragma once

#include <array>
#include <algorithm>
#include <ranges>
#include <span>

namespace stockcalc {

enum class FieldId : int {
    none = 0,
    totalInvestment = 1,
    sharePrice = 2,
    totalShares = 3,
    targetPrice = 4,
    profitInvest = 5,
    profit = 6,
    percent = 7,
};

inline constexpr std::array kExcludedFields{
    FieldId::none, FieldId::profit,
    FieldId::profitInvest, FieldId::targetPrice
};

struct PanelInput {
    double totalInvestment = 0.0;
    double sharePrice = 0.0;
    double totalShares = 0.0;
    double targetPrice = 0.0;
    int lastChanged = 0;
    int secondLastChanged = 0;
};

struct PanelResult {
    double totalInvestment = 0.0;
    double sharePrice = 0.0;
    double totalShares = 0.0;
    double profitPlusInvest = 0.0;
    double profit = 0.0;
    double gainPercent = 0.0;
    int inferredField = 0;
};

struct CombinedResult {
    double avgSharePrice = 0.0;
    double totalInvestment = 0.0;
    double totalShares = 0.0;
    double totalProfit = 0.0;
    double avgProfit = 0.0;
    int validCount = 0;
};

[[nodiscard]] PanelResult calculatePanel(const PanelInput& input);
[[nodiscard]] CombinedResult calculateCombined(std::span<const PanelResult> panels);

constexpr bool isValidTrackingField(FieldId field) {
    return std::ranges::find(kExcludedFields, field) == kExcludedFields.end();
}

} // namespace stockcalc
