#include "market/marketTypes.hpp"

namespace market {

const char* timeframeLabel(Timeframe timeframe) {
    switch (timeframe) {
    case Timeframe::day1: return "1D";
    case Timeframe::week1: return "1W";
    case Timeframe::month1: return "1M";
    case Timeframe::month6: return "6M";
    case Timeframe::year1: return "1Y";
    case Timeframe::max: return "MAX";
    }
    return "1D";
}

const char* timeframeResolution(Timeframe timeframe) {
    switch (timeframe) {
    case Timeframe::day1: return "5";
    case Timeframe::week1: return "15";
    case Timeframe::month1: return "60";
    case Timeframe::month6: return "D";
    case Timeframe::year1: return "D";
    case Timeframe::max: return "W";
    }
    return "5";
}

int timeframeLookbackDays(Timeframe timeframe) {
    switch (timeframe) {
    case Timeframe::day1: return 10;
    case Timeframe::week1: return 30;
    case Timeframe::month1: return 90;
    case Timeframe::month6: return 180;
    case Timeframe::year1: return 365;
    case Timeframe::max: return 3650;
    }
    return 30;
}

} // namespace market
