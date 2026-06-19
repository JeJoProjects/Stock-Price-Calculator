#pragma once

#include "market/marketTypes.hpp"
#include <string>

namespace market {

class FinnhubClient {
public:
    void setApiKey(std::string apiKey);
    [[nodiscard]] bool hasApiKey() const { return !apiKey_.empty(); }

    [[nodiscard]] bool fetchQuote(const std::string& symbol, Quote& quote, std::string& error) const;
    [[nodiscard]] bool fetchProfile(const std::string& symbol, CompanyProfile& profile, std::string& error) const;
    [[nodiscard]] bool fetchCandles(const std::string& symbol, Timeframe timeframe,
        std::vector<Candle>& candles, std::string& error) const;

private:
    std::string apiKey_;

    [[nodiscard]] std::string request(const std::string& path, std::string& error) const;
    [[nodiscard]] static std::string urlEncode(const std::string& text);
    [[nodiscard]] static double readDouble(const std::string& json, const std::string& key, double fallback = 0.0);
    [[nodiscard]] static std::string readString(const std::string& json, const std::string& key);
};

} // namespace market
