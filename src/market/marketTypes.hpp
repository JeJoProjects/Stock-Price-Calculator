#pragma once

#include <string>
#include <vector>

namespace market {

enum class Timeframe {
    day1,
    week1,
    month1,
    month6,
    year1,
    max
};

struct Candle {
    long long time = 0;
    double open = 0.0;
    double high = 0.0;
    double low = 0.0;
    double close = 0.0;
    double volume = 0.0;
};

struct Quote {
    double current = 0.0;
    double change = 0.0;
    double percent = 0.0;
    double high = 0.0;
    double low = 0.0;
    double open = 0.0;
    double previousClose = 0.0;
};

struct CompanyProfile {
    std::string name;
    std::string exchange;
    std::string currency;
    double marketCap = 0.0;
};

struct Snapshot {
    std::string symbol;
    Timeframe timeframe = Timeframe::day1;
    Quote quote{};
    CompanyProfile profile{};
    std::vector<Candle> candles;
    bool valid = false;
    bool loading = false;
    std::string error;
};

[[nodiscard]] const char* timeframeLabel(Timeframe timeframe);
[[nodiscard]] const char* timeframeResolution(Timeframe timeframe);
[[nodiscard]] int timeframeLookbackDays(Timeframe timeframe);

} // namespace market
