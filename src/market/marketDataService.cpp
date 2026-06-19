#include "market/marketDataService.hpp"

#include <utility>

namespace market {

MarketDataService::~MarketDataService() {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        stop_ = true;
        hasPending_ = true;
    }
    cv_.notify_one();
    if (worker_.joinable()) worker_.join();
}

void MarketDataService::setApiKey(std::string apiKey) {
    client_.setApiKey(std::move(apiKey));
}

void MarketDataService::startWorker() {
    if (worker_.joinable()) return;
    stop_ = false;
    worker_ = std::thread(&MarketDataService::workerLoop, this);
}

std::string MarketDataService::makeKey(const std::string& symbol, Timeframe timeframe) {
    return symbol + "|" + std::to_string(static_cast<int>(timeframe));
}

void MarketDataService::requestSnapshot(const std::string& symbol, Timeframe timeframe) {
    if (symbol.empty() || !client_.hasApiKey()) return;

    std::string key = makeKey(symbol, timeframe);
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (auto it = cache_.find(key); it != cache_.end()) {
            latest_ = it->second;
            latest_->loading = false;
            latest_->valid = true;
            return;
        }
        pendingSymbol_ = symbol;
        pendingTimeframe_ = timeframe;
        hasPending_ = true;
        latest_ = Snapshot{};
        latest_->symbol = symbol;
        latest_->timeframe = timeframe;
        latest_->valid = true;
        latest_->loading = true;
        ++requestId_;
    }

    startWorker();
    cv_.notify_one();
}

std::optional<Snapshot> MarketDataService::takeLatestSnapshot() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!latest_) return std::nullopt;
    auto out = std::move(latest_);
    latest_.reset();
    return out;
}

bool MarketDataService::hasLatestSnapshot() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return latest_.has_value();
}

void MarketDataService::workerLoop() {
    for (;;) {
        std::string symbol;
        Timeframe timeframe = Timeframe::day1;
        unsigned id = 0;

        {
            std::unique_lock<std::mutex> lock(mutex_);
            cv_.wait(lock, [this] { return stop_ || hasPending_; });
            if (stop_) return;
            symbol = pendingSymbol_;
            timeframe = pendingTimeframe_;
            hasPending_ = false;
            id = requestId_;
        }

        Snapshot snapshot;
        snapshot.symbol = symbol;
        snapshot.timeframe = timeframe;
        snapshot.loading = false;

        std::string error;
        bool quoteOk = client_.fetchQuote(symbol, snapshot.quote, error);
        bool profileOk = client_.fetchProfile(symbol, snapshot.profile, error);
        bool candlesOk = client_.fetchCandles(symbol, timeframe, snapshot.candles, error);
        if (!quoteOk && !profileOk && !candlesOk && error.empty()) {
            error = "Failed to retrieve market data.";
        }
        snapshot.valid = !snapshot.candles.empty() || snapshot.quote.current > 0.0;
        snapshot.error = error;

        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (id != requestId_) continue;
            cache_[makeKey(symbol, timeframe)] = snapshot;
            latest_ = cache_[makeKey(symbol, timeframe)];
        }
    }
}

} // namespace market
