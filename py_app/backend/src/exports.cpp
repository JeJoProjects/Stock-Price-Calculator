#include "calc_engine.hpp"

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

extern "C" {

EXPORT void calc_panel(
    double total_investment, double share_price, double total_shares,
    double target_price, int last_changed, int second_last_changed,
    double* out_investment, double* out_price, double* out_shares,
    double* out_profit_invest, double* out_profit, double* out_gain_pct,
    int* out_inferred_field
) {
    stockcalc::PanelInput input{
        total_investment, share_price, total_shares,
        target_price, last_changed, second_last_changed
    };
    auto result = stockcalc::calculate_panel(input);
    *out_investment = result.total_investment;
    *out_price = result.share_price;
    *out_shares = result.total_shares;
    *out_profit_invest = result.profit_plus_invest;
    *out_profit = result.profit;
    *out_gain_pct = result.gain_percent;
    *out_inferred_field = result.inferred_field;
}

EXPORT void calc_combined(
    const double* investments, const double* prices, const double* shares,
    const double* profits, int count,
    double* out_avg_price, double* out_total_invest, double* out_total_shares,
    double* out_total_profit, double* out_avg_profit, int* out_valid_count
) {
    std::vector<stockcalc::PanelResult> panels(count);
    for (int i = 0; i < count; ++i) {
        panels[i].total_investment = investments[i];
        panels[i].share_price = prices[i];
        panels[i].total_shares = shares[i];
        panels[i].profit = profits[i];
    }
    auto result = stockcalc::calculate_combined(panels.data(), count);
    *out_avg_price = result.avg_share_price;
    *out_total_invest = result.total_investment;
    *out_total_shares = result.total_shares;
    *out_total_profit = result.total_profit;
    *out_avg_profit = result.avg_profit;
    *out_valid_count = result.valid_count;
}

} // extern "C"
