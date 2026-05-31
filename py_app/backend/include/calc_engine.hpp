#pragma once

#include <cstdint>
#include <vector>
#include <cmath>
#include <algorithm>
#include <array>
#include <ranges>

namespace stockcalc {

enum class FieldId : int {
    none = 0,
    total_investment = 1,
    share_price = 2,
    total_shares = 3,
    target_price = 4,
    profit_invest = 5,
    profit = 6,
    percent = 7,
};

inline constexpr std::array excluded_fields{
    FieldId::none, FieldId::profit,
    FieldId::profit_invest, FieldId::target_price
};

struct PanelInput {
    double total_investment;
    double share_price;
    double total_shares;
    double target_price;
    int last_changed;
    int second_last_changed;
};

struct PanelResult {
    double total_investment;
    double share_price;
    double total_shares;
    double profit_plus_invest;
    double profit;
    double gain_percent;
    int inferred_field;
};

struct CombinedResult {
    double avg_share_price;
    double total_investment;
    double total_shares;
    double total_profit;
    double avg_profit;
    int valid_count;
};

PanelResult calculate_panel(const PanelInput& input);
CombinedResult calculate_combined(const PanelResult* panels, int count);

constexpr bool is_valid_tracking_field(FieldId field) {
    return std::ranges::find(excluded_fields, field) == excluded_fields.end();
}

} // namespace stockcalc
