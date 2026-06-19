#pragma once

#include "search/tickerData.hpp"
#include <string>
#include <vector>
#include <unordered_map>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>

namespace search {

template <typename Key, typename Value>
[[nodiscard]] const Value* findCachedValue(const std::unordered_map<Key, Value>& cache, const Key& key) {
    if (auto it = cache.find(key); it != cache.end()) {
        return &it->second;
    }
    return nullptr;
}

enum class MatchKind {
    exactSymbol,
    prefixSymbol,
    symbolSubstring,
    prefixName,
    nameSubstring,
    online
};

struct SearchResult {
    const TickerEntry* entry = nullptr;
    int score = 0;
    MatchKind kind = MatchKind::nameSubstring;
    std::string preview;
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
    mutable std::unordered_map<std::string, std::vector<SearchResult>> queryCache_;
    mutable std::unordered_map<std::string, std::vector<OnlineResult>> onlineCache_;

    std::thread onlineWorker_;
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    std::vector<OnlineResult> onlineResults_;
    std::atomic<bool> onlineReady_{false};
    std::atomic<bool> onlineBusy_{false};
    std::atomic<unsigned> requestId_{0};
    std::string pendingQuery_;
    int pendingMaxResults_ = 12;
    bool hasPendingRequest_ = false;
    bool stopWorker_ = false;

    void findPython();
    void startWorker();
    void workerLoop();
    void runOnlineSearch(std::string query, int maxResults, unsigned reqId);
    [[nodiscard]] static std::string normalizeQuery(const std::string& query);
    [[nodiscard]] static const char* kindPreview(MatchKind kind);
};

} // namespace search
