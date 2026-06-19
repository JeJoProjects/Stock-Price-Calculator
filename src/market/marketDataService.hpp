#pragma once

#include "market/finnhubClient.hpp"
#include <condition_variable>
#include <mutex>
#include <optional>
#include <thread>
#include <unordered_map>

namespace market {

class MarketDataService {
public:
    ~MarketDataService();

    void setApiKey(std::string apiKey);
    void requestSnapshot(const std::string& symbol, Timeframe timeframe);
    [[nodiscard]] std::optional<Snapshot> takeLatestSnapshot();
    [[nodiscard]] bool hasLatestSnapshot() const;

private:
    FinnhubClient client_;
    std::thread worker_;
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    std::unordered_map<std::string, Snapshot> cache_;
    std::optional<Snapshot> latest_;
    std::string pendingSymbol_;
    Timeframe pendingTimeframe_ = Timeframe::day1;
    bool hasPending_ = false;
    bool stop_ = false;
    unsigned requestId_ = 0;

    void startWorker();
    void workerLoop();
    [[nodiscard]] static std::string makeKey(const std::string& symbol, Timeframe timeframe);
};

} // namespace market
