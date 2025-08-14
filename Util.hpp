#include <windows.h>
#include <string>
#include <sstream>
#include <iomanip>
#include <cmath>
#include <array>
#include <algorithm>
#include <ranges>
#include <utility>
#include <vector>
#include <memory>

enum class ControlId : short
{
    none = 0,
    totalInvestment = 1,
    sharePrice = 2,
    totalShares = 3,
    targetPrice = 4,
    profitInvest = 5,
    profit = 6,
    percent = 7,
    resetButton = 8,
    newBuyButton = 100,
    combinedAvgSharePrice = 200,
    combinedTotalInvestment = 201,
    combinedTotalShares = 202,
    combinedAvgProfit = 203,
    combinedTotalProfit = 204,
    combinedResetButton = 205
};

inline constexpr std::array excluded_fields
{
    ControlId::none, ControlId::profit,
    ControlId::profitInvest, ControlId::targetPrice
};


template <typename T>
inline constexpr HMENU toHMENU(T id) noexcept
{
    return (HMENU)(INT_PTR)(static_cast<int>(id));
}
