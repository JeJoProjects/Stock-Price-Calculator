#pragma once

#include "search/tickerData.hpp"
#include <string>
#include <vector>

namespace search {

struct SearchResult {
    const TickerEntry* entry = nullptr;
    int score = 0;
};

struct OnlineResult {
    std::string symbol;
    std::string name;
    std::string exchange;
};

class StockSearchEngine {
public:
    void load(const std::string& jsonPath);
    [[nodiscard]] std::vector<SearchResult> search(const std::string& query, int maxResults = 12) const;
    [[nodiscard]] std::vector<OnlineResult> searchOnline(const std::string& query, int maxResults = 12) const;
    [[nodiscard]] std::size_t tickerCount() const { return tickers_.size(); }

private:
    std::vector<TickerEntry> tickers_;
    std::string pythonPath_;
    void findPython();
};

} // namespace search
