#include "calc_engine.hpp"

namespace stockcalc {

PanelResult calculate_panel(const PanelInput& input) {
    double investment = input.total_investment;
    double price = input.share_price;
    double shares = input.total_shares;
    double target = input.target_price;
    auto last = static_cast<FieldId>(input.last_changed);
    auto second = static_cast<FieldId>(input.second_last_changed);
    int inferred = 0;

    if (last == FieldId::total_investment) {
        if (second == FieldId::total_shares && shares > 0.0) {
            investment = price * shares;
            inferred = 1;
        } else if (price > 0.0) {
            shares = investment / price;
            inferred = 3;
        }
    } else if (last == FieldId::share_price) {
        if (investment > 0.0 && price > 0.0) {
            shares = investment / price;
            inferred = 3;
        }
    } else if (last == FieldId::total_shares) {
        if (second == FieldId::total_investment && investment > 0.0 && shares > 0.0) {
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
    result.total_investment = investment;
    result.share_price = price;
    result.total_shares = shares;
    result.inferred_field = inferred;

    if (target > 0.0 && shares > 0.0) {
        result.profit_plus_invest = target * shares;
        result.profit = result.profit_plus_invest - investment;
    }

    if (target > 0.0 && price > 0.0) {
        result.gain_percent = ((target - price) * 100.0) / price;
    }

    return result;
}

CombinedResult calculate_combined(const PanelResult* panels, int count) {
    CombinedResult combined{};
    double weighted_price = 0.0;

    for (int i = 0; i < count; ++i) {
        const auto& p = panels[i];
        bool valid = p.total_investment > 0.0 && p.share_price > 0.0 && p.total_shares > 0.0;
        if (valid) {
            combined.total_investment += p.total_investment;
            combined.total_shares += p.total_shares;
            combined.total_profit += p.profit;
            weighted_price += p.share_price * p.total_shares;
            combined.valid_count++;
        }
    }

    if (combined.valid_count > 0) {
        combined.avg_share_price = combined.total_shares > 0.0
            ? weighted_price / combined.total_shares : 0.0;
        combined.avg_profit = combined.total_profit / combined.valid_count;
    }

    return combined;
}

} // namespace stockcalc
