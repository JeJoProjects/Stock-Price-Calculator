#include "search/stockSearchEngine.hpp"
#include <algorithm>
#include <ranges>
#include <cctype>
#include <cstdio>
#include <array>
#include <utility>

#ifdef _WIN32
#define popen _popen
#define pclose _pclose
#endif

namespace search {

static std::string toLower(std::string_view sv) {
    std::string result;
    result.reserve(sv.size());
    for (char c : sv) result += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return result;
}

static bool startsWithWord(const std::string& text, const std::string& query) {
    if (text.starts_with(query)) return true;
    auto pos = text.find(query);
    if (pos == std::string::npos) return false;
    return pos == 0 || !std::isalnum(static_cast<unsigned char>(text[pos - 1]));
}

static std::string extractJsonString(const std::string& json, std::size_t startPos, const std::string& key) {
    auto kp = "\"" + key + "\"";
    auto pos = json.find(kp, startPos);
    if (pos == std::string::npos) return {};
    pos = json.find('"', pos + kp.size() + 1);
    if (pos == std::string::npos) return {};
    ++pos;
    auto end = json.find('"', pos);
    if (end == std::string::npos) return {};
    return json.substr(pos, end - pos);
}

StockSearchEngine::~StockSearchEngine() {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        stopWorker_ = true;
        hasPendingRequest_ = true;
    }
    cv_.notify_one();
    if (onlineWorker_.joinable()) onlineWorker_.join();
}

void StockSearchEngine::findPython() {
    const char* candidates[] = {
        "C:\\ProgramData\\miniconda3\\python.exe",
        "C:\\Python312\\python.exe",
        "C:\\Python311\\python.exe",
        "C:\\Python310\\python.exe",
        "python",
    };
    for (const auto* path : candidates) {
        std::string cmd = std::string("\"") + path + "\" --version >nul 2>&1";
        if (std::system(cmd.c_str()) == 0) {
            pythonPath_ = path;
            return;
        }
    }
}

void StockSearchEngine::load(const std::string& jsonPath) {
    tickers_ = loadTickers(jsonPath);
    findPython();
    queryCache_.clear();
    onlineCache_.clear();
    if (!pythonPath_.empty()) startWorker();
}

void StockSearchEngine::startWorker() {
    if (onlineWorker_.joinable()) return;
    stopWorker_ = false;
    onlineWorker_ = std::thread(&StockSearchEngine::workerLoop, this);
}

std::vector<SearchResult> StockSearchEngine::search(const std::string& query, int maxResults) const {
    if (query.empty() || tickers_.empty()) return {};

    std::string q = normalizeQuery(query);
    if (auto cacheIt = queryCache_.find(q); cacheIt != queryCache_.end()) {
        auto cached = cacheIt->second;
        if (static_cast<int>(cached.size()) > maxResults) cached.resize(maxResults);
        return cached;
    }

    std::vector<SearchResult> results;
    results.reserve(maxResults * 2);

    auto lower = std::ranges::lower_bound(tickers_, q, {}, &TickerEntry::symbolLower);
    for (auto it = lower; it != tickers_.end(); ++it) {
        if (!it->symbolLower.starts_with(q)) break;
        int score = 130;
        MatchKind kind = MatchKind::exactSymbol;
        if (it->symbolLower != q) {
            score = 120;
            kind = MatchKind::prefixSymbol;
        }
        results.push_back({&(*it), score, kind, kindPreview(kind)});
    }

    if (static_cast<int>(results.size()) < maxResults) {
        for (const auto& t : tickers_) {
            if (t.symbolLower.starts_with(q)) continue;

            if (t.symbolLower.find(q) != std::string::npos) {
                results.push_back({&t, 90, MatchKind::symbolSubstring, kindPreview(MatchKind::symbolSubstring)});
            } else if (startsWithWord(t.nameLower, q)) {
                results.push_back({&t, 70, MatchKind::prefixName, kindPreview(MatchKind::prefixName)});
            } else if (t.nameLower.find(q) != std::string::npos) {
                results.push_back({&t, 55, MatchKind::nameSubstring, kindPreview(MatchKind::nameSubstring)});
            }

            if (static_cast<int>(results.size()) >= maxResults * 3) break;
        }
    }

    std::ranges::sort(results, [](const SearchResult& lhs, const SearchResult& rhs) {
        if (lhs.score != rhs.score) return lhs.score > rhs.score;
        return lhs.entry->symbol < rhs.entry->symbol;
    });
    if (static_cast<int>(results.size()) > maxResults) results.resize(maxResults);
    queryCache_.insert_or_assign(q, results);
    if (queryCache_.size() > 96) queryCache_.clear();
    return results;
}

void StockSearchEngine::requestOnline(const std::string& query, int maxResults) {
    if (pythonPath_.empty() || query.size() < 2) return;

    std::string q = normalizeQuery(query);
    if (auto cacheIt = onlineCache_.find(q); cacheIt != onlineCache_.end()) {
        std::lock_guard<std::mutex> lock(mutex_);
        onlineResults_ = cacheIt->second;
        if (static_cast<int>(onlineResults_.size()) > maxResults) onlineResults_.resize(maxResults);
        onlineReady_.store(true);
        onlineBusy_.store(false);
        return;
    }

    startWorker();

    {
        std::lock_guard<std::mutex> lock(mutex_);
        pendingQuery_ = query;
        pendingMaxResults_ = maxResults;
        hasPendingRequest_ = true;
        onlineReady_.store(false);
        onlineBusy_.store(true);
        requestId_.fetch_add(1, std::memory_order_relaxed);
    }
    cv_.notify_one();
}

void StockSearchEngine::workerLoop() {
    for (;;) {
        std::string query;
        int maxResults = 12;
        unsigned reqId = 0;

        {
            std::unique_lock<std::mutex> lock(mutex_);
            cv_.wait(lock, [this] { return stopWorker_ || hasPendingRequest_; });
            if (stopWorker_) return;

            query = std::move(pendingQuery_);
            maxResults = pendingMaxResults_;
            reqId = requestId_.load(std::memory_order_relaxed);
            hasPendingRequest_ = false;
        }

        runOnlineSearch(std::move(query), maxResults, reqId);
    }
}

void StockSearchEngine::runOnlineSearch(std::string query, int maxResults, unsigned reqId) {
    std::string sanitizedQuery = query;
    for (char& c : sanitizedQuery) {
        if (c == '"') c = ' ';
    }

    std::string cmd = "\"" + pythonPath_ + "\" scripts/search_symbols.py \""
        + sanitizedQuery + "\" 2>nul";

    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        onlineBusy_.store(false);
        return;
    }

    std::string output;
    std::array<char, 4096> buf{};
    while (std::fgets(buf.data(), static_cast<int>(buf.size()), pipe)) {
        output += buf.data();
    }
    pclose(pipe);

    // Stale request — a newer one was fired while this ran
    if (reqId != requestId_.load()) {
        onlineBusy_.store(false);
        return;
    }

    std::vector<OnlineResult> results;
    if (!output.empty() && output[0] == '[') {
        std::size_t pos = 0;
        while ((pos = output.find('{', pos)) != std::string::npos) {
            auto end = output.find('}', pos);
            if (end == std::string::npos) break;

            OnlineResult r;
            r.symbol = extractJsonString(output, pos, "symbol");
            r.name = extractJsonString(output, pos, "name");
            r.exchange = extractJsonString(output, pos, "exchange");

            if (!r.symbol.empty()) results.push_back(std::move(r));
            pos = end + 1;
            if (static_cast<int>(results.size()) >= maxResults) break;
        }
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        onlineResults_ = std::move(results);
        onlineCache_.insert_or_assign(normalizeQuery(query), onlineResults_);
        if (onlineCache_.size() > 96) onlineCache_.clear();
    }
    onlineReady_.store(true);
    onlineBusy_.store(false);
}

bool StockSearchEngine::hasOnlineResults() const {
    return onlineReady_.load();
}

std::vector<OnlineResult> StockSearchEngine::takeOnlineResults() {
    std::lock_guard<std::mutex> lock(mutex_);
    onlineReady_.store(false);
    return std::move(onlineResults_);
}

std::string StockSearchEngine::normalizeQuery(const std::string& query) {
    std::string result = toLower(query);
    while (!result.empty() && std::isspace(static_cast<unsigned char>(result.front()))) {
        result.erase(result.begin());
    }
    while (!result.empty() && std::isspace(static_cast<unsigned char>(result.back()))) {
        result.pop_back();
    }
    return result;
}

const char* StockSearchEngine::kindPreview(MatchKind kind) {
    switch (kind) {
    case MatchKind::exactSymbol: return "Exact symbol";
    case MatchKind::prefixSymbol: return "Symbol prefix";
    case MatchKind::symbolSubstring: return "Symbol contains query";
    case MatchKind::prefixName: return "Company name prefix";
    case MatchKind::nameSubstring: return "Company name contains query";
    case MatchKind::online: return "Online result";
    }
    return "Match";
}

} // namespace search
