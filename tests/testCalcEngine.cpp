#include "core/calcEngine.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>

static int passed = 0;
static int failed = 0;

#define ASSERT_NEAR(a, b, eps) \
    do { \
        if (std::fabs((a) - (b)) > (eps)) { \
            std::cerr << "FAIL: " << #a << " = " << (a) \
                      << ", expected " << (b) << " (line " << __LINE__ << ")\n"; \
            ++failed; \
        } else { ++passed; } \
    } while(0)

#define ASSERT_EQ(a, b) \
    do { \
        if ((a) != (b)) { \
            std::cerr << "FAIL: " << #a << " = " << (a) \
                      << ", expected " << (b) << " (line " << __LINE__ << ")\n"; \
            ++failed; \
        } else { ++passed; } \
    } while(0)

using namespace stockcalc;

void testBasicProfit() {
    PanelInput in{.totalInvestment = 1000.0, .sharePrice = 50.0,
                  .totalShares = 20.0, .targetPrice = 75.0};
    auto r = calculatePanel(in);
    ASSERT_NEAR(r.profit, 500.0, 0.01);
    ASSERT_NEAR(r.profitPlusInvest, 1500.0, 0.01);
    ASSERT_NEAR(r.gainPercent, 50.0, 0.01);
}

void testInferShares() {
    PanelInput in{.totalInvestment = 1000.0, .sharePrice = 25.0,
                  .lastChanged = 2, .secondLastChanged = 1};
    auto r = calculatePanel(in);
    ASSERT_NEAR(r.totalShares, 40.0, 0.01);
    ASSERT_EQ(r.inferredField, 3);
}

void testInferPrice() {
    PanelInput in{.totalInvestment = 500.0, .totalShares = 10.0,
                  .lastChanged = 3, .secondLastChanged = 1};
    auto r = calculatePanel(in);
    ASSERT_NEAR(r.sharePrice, 50.0, 0.01);
    ASSERT_EQ(r.inferredField, 2);
}

void testInferInvestment() {
    PanelInput in{.sharePrice = 100.0, .totalShares = 5.0,
                  .lastChanged = 3};
    auto r = calculatePanel(in);
    ASSERT_NEAR(r.totalInvestment, 500.0, 0.01);
    ASSERT_EQ(r.inferredField, 1);
}

void testZeroTarget() {
    PanelInput in{.totalInvestment = 1000.0, .sharePrice = 50.0, .totalShares = 20.0};
    auto r = calculatePanel(in);
    ASSERT_NEAR(r.profit, 0.0, 0.01);
    ASSERT_NEAR(r.profitPlusInvest, 0.0, 0.01);
}

void testNegativeProfit() {
    PanelInput in{.totalInvestment = 1000.0, .sharePrice = 50.0,
                  .totalShares = 20.0, .targetPrice = 30.0};
    auto r = calculatePanel(in);
    ASSERT_NEAR(r.profit, -400.0, 0.01);
    ASSERT_NEAR(r.gainPercent, -40.0, 0.01);
}

void testCombinedStats() {
    std::vector<PanelResult> panels;

    PanelResult p1{.totalInvestment = 1000.0, .sharePrice = 50.0,
                   .totalShares = 20.0, .profit = 500.0};
    PanelResult p2{.totalInvestment = 2000.0, .sharePrice = 100.0,
                   .totalShares = 20.0, .profit = -200.0};
    panels.push_back(p1);
    panels.push_back(p2);

    auto c = calculateCombined(panels);
    ASSERT_EQ(c.validCount, 2);
    ASSERT_NEAR(c.totalInvestment, 3000.0, 0.01);
    ASSERT_NEAR(c.totalShares, 40.0, 0.01);
    ASSERT_NEAR(c.totalProfit, 300.0, 0.01);
    ASSERT_NEAR(c.avgProfit, 150.0, 0.01);
    ASSERT_NEAR(c.avgSharePrice, 75.0, 0.01);
}

void testCombinedEmpty() {
    std::vector<PanelResult> panels;
    auto c = calculateCombined(panels);
    ASSERT_EQ(c.validCount, 0);
    ASSERT_NEAR(c.totalInvestment, 0.0, 0.01);
}

void testCombinedSkipsInvalid() {
    std::vector<PanelResult> panels;
    PanelResult valid{.totalInvestment = 500.0, .sharePrice = 25.0,
                      .totalShares = 20.0, .profit = 100.0};
    PanelResult invalid{};
    panels.push_back(valid);
    panels.push_back(invalid);

    auto c = calculateCombined(panels);
    ASSERT_EQ(c.validCount, 1);
    ASSERT_NEAR(c.totalInvestment, 500.0, 0.01);
}

void testInferFallbackTwoNonzero() {
    PanelInput in{.totalInvestment = 0.0, .sharePrice = 40.0, .totalShares = 10.0};
    auto r = calculatePanel(in);
    ASSERT_NEAR(r.totalInvestment, 400.0, 0.01);
    ASSERT_EQ(r.inferredField, 1);
}

void testLargeNumbers() {
    PanelInput in{.totalInvestment = 1000000.0, .sharePrice = 500.0,
                  .totalShares = 2000.0, .targetPrice = 750.0};
    auto r = calculatePanel(in);
    ASSERT_NEAR(r.profit, 500000.0, 0.01);
    ASSERT_NEAR(r.gainPercent, 50.0, 0.01);
}

void testFieldTracking() {
    ASSERT_EQ(isValidTrackingField(FieldId::totalInvestment), true);
    ASSERT_EQ(isValidTrackingField(FieldId::sharePrice), true);
    ASSERT_EQ(isValidTrackingField(FieldId::totalShares), true);
    ASSERT_EQ(isValidTrackingField(FieldId::targetPrice), false);
    ASSERT_EQ(isValidTrackingField(FieldId::none), false);
    ASSERT_EQ(isValidTrackingField(FieldId::profit), false);
    ASSERT_EQ(isValidTrackingField(FieldId::profitInvest), false);
}

int main() {
    testBasicProfit();
    testInferShares();
    testInferPrice();
    testInferInvestment();
    testZeroTarget();
    testNegativeProfit();
    testCombinedStats();
    testCombinedEmpty();
    testCombinedSkipsInvalid();
    testInferFallbackTwoNonzero();
    testLargeNumbers();
    testFieldTracking();

    std::cout << "\n=== Calc Engine Tests ===\n";
    std::cout << "Passed: " << passed << "\n";
    std::cout << "Failed: " << failed << "\n";
    std::cout << "Total:  " << (passed + failed) << "\n";

    return failed > 0 ? 1 : 0;
}
