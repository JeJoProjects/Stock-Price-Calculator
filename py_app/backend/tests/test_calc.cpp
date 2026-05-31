#include "calc_engine.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
#include <string>

static int tests_passed = 0;
static int tests_failed = 0;

#define ASSERT_NEAR(a, b, eps) \
    if (std::fabs((a) - (b)) > (eps)) { \
        std::cerr << "FAIL: " << #a << " = " << (a) << ", expected ~" << (b) \
                  << " at line " << __LINE__ << "\n"; \
        tests_failed++; \
    } else { tests_passed++; }

#define ASSERT_EQ(a, b) \
    if ((a) != (b)) { \
        std::cerr << "FAIL: " << #a << " = " << (a) << ", expected " << (b) \
                  << " at line " << __LINE__ << "\n"; \
        tests_failed++; \
    } else { tests_passed++; }

using namespace stockcalc;

void test_infer_shares_from_investment_and_price() {
    PanelInput input{10000.0, 200.0, 0.0, 250.0, 0, 0};
    auto r = calculate_panel(input);
    ASSERT_NEAR(r.total_shares, 50.0, 0.01);
    ASSERT_EQ(r.inferred_field, 3);
    ASSERT_NEAR(r.profit_plus_invest, 12500.0, 0.01);
    ASSERT_NEAR(r.profit, 2500.0, 0.01);
    ASSERT_NEAR(r.gain_percent, 25.0, 0.01);
}

void test_infer_price_from_investment_and_shares() {
    PanelInput input{10000.0, 0.0, 50.0, 300.0, 0, 0};
    auto r = calculate_panel(input);
    ASSERT_NEAR(r.share_price, 200.0, 0.01);
    ASSERT_EQ(r.inferred_field, 2);
}

void test_infer_investment_from_price_and_shares() {
    PanelInput input{0.0, 200.0, 50.0, 0.0, 0, 0};
    auto r = calculate_panel(input);
    ASSERT_NEAR(r.total_investment, 10000.0, 0.01);
    ASSERT_EQ(r.inferred_field, 1);
}

void test_last_changed_investment_with_price() {
    PanelInput input{10000.0, 200.0, 100.0, 0.0, 1, 0};
    auto r = calculate_panel(input);
    ASSERT_NEAR(r.total_shares, 50.0, 0.01);
    ASSERT_EQ(r.inferred_field, 3);
}

void test_last_changed_shares_with_second_investment() {
    PanelInput input{10000.0, 200.0, 40.0, 0.0, 3, 1};
    auto r = calculate_panel(input);
    ASSERT_NEAR(r.share_price, 250.0, 0.01);
    ASSERT_EQ(r.inferred_field, 2);
}

void test_last_changed_share_price() {
    PanelInput input{10000.0, 250.0, 50.0, 0.0, 2, 0};
    auto r = calculate_panel(input);
    ASSERT_NEAR(r.total_shares, 40.0, 0.01);
    ASSERT_EQ(r.inferred_field, 3);
}

void test_no_target_price() {
    PanelInput input{10000.0, 200.0, 0.0, 0.0, 0, 0};
    auto r = calculate_panel(input);
    ASSERT_NEAR(r.profit_plus_invest, 0.0, 0.01);
    ASSERT_NEAR(r.profit, 0.0, 0.01);
    ASSERT_NEAR(r.gain_percent, 0.0, 0.01);
}

void test_negative_profit() {
    PanelInput input{10000.0, 200.0, 0.0, 150.0, 0, 0};
    auto r = calculate_panel(input);
    ASSERT_NEAR(r.total_shares, 50.0, 0.01);
    ASSERT_NEAR(r.profit, -2500.0, 0.01);
    ASSERT_NEAR(r.gain_percent, -25.0, 0.01);
}

void test_combined_two_panels() {
    PanelResult panels[2] = {
        {10000.0, 200.0, 50.0, 12500.0, 2500.0, 25.0, 0},
        {5000.0, 100.0, 50.0, 7500.0, 2500.0, 50.0, 0},
    };
    auto c = calculate_combined(panels, 2);
    ASSERT_EQ(c.valid_count, 2);
    ASSERT_NEAR(c.total_investment, 15000.0, 0.01);
    ASSERT_NEAR(c.total_shares, 100.0, 0.01);
    ASSERT_NEAR(c.total_profit, 5000.0, 0.01);
    ASSERT_NEAR(c.avg_profit, 2500.0, 0.01);
    ASSERT_NEAR(c.avg_share_price, 150.0, 0.01);
}

void test_combined_skips_invalid() {
    PanelResult panels[2] = {
        {10000.0, 200.0, 50.0, 0.0, 2500.0, 0.0, 0},
        {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0},
    };
    auto c = calculate_combined(panels, 2);
    ASSERT_EQ(c.valid_count, 1);
    ASSERT_NEAR(c.total_investment, 10000.0, 0.01);
}

void test_all_zeros() {
    PanelInput input{0.0, 0.0, 0.0, 0.0, 0, 0};
    auto r = calculate_panel(input);
    ASSERT_NEAR(r.total_investment, 0.0, 0.01);
    ASSERT_NEAR(r.share_price, 0.0, 0.01);
    ASSERT_NEAR(r.total_shares, 0.0, 0.01);
    ASSERT_EQ(r.inferred_field, 0);
}

int main() {
    test_infer_shares_from_investment_and_price();
    test_infer_price_from_investment_and_shares();
    test_infer_investment_from_price_and_shares();
    test_last_changed_investment_with_price();
    test_last_changed_shares_with_second_investment();
    test_last_changed_share_price();
    test_no_target_price();
    test_negative_profit();
    test_combined_two_panels();
    test_combined_skips_invalid();
    test_all_zeros();

    std::cout << "\n=== C++ Test Results ===\n";
    std::cout << "Passed: " << tests_passed << "\n";
    std::cout << "Failed: " << tests_failed << "\n";
    return tests_failed > 0 ? 1 : 0;
}
