#pragma once

#include "search/tickerData.hpp"
#include <string>
#include <vector>
#include <thread>
#include <mutex>
#include <atomic>

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
    ~StockSearchEngine();

    void load(const std::string& jsonPath);

    [[nodiscard]] std::vector<SearchResult> search(const std::string& query, int maxResults = 12) const;

    void requestOnline(const std::string& query, int maxResults = 12);
    [[nodiscard]] bool hasOnlineResults() const;
    [[nodiscard]] std::vector<OnlineResult> takeOnlineResults();

    [[nodiscard]] std::size_t tickerCount() const { return tickers_.size(); }
    [[nodiscard]] bool hasPython() const { return !pythonPath_.empty(); }

private:
    std::vector<TickerEntry> tickers_;
    std::string pythonPath_;

    std::thread onlineThread_;
    mutable std::mutex mutex_;
    std::vector<OnlineResult> onlineResults_;
    std::atomic<bool> onlineReady_{false};
    std::atomic<bool> onlineBusy_{false};
    std::atomic<unsigned> requestId_{0};

    void findPython();
    void runOnlineSearch(std::string query, int maxResults, unsigned reqId);
};

} // namespace search
