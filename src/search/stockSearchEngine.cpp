#include "search/stockSearchEngine.hpp"
#include <algorithm>
#include <ranges>
#include <cctype>
#include <cstdio>
#include <array>

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
    if (onlineThread_.joinable()) onlineThread_.join();
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
}

std::vector<SearchResult> StockSearchEngine::search(const std::string& query, int maxResults) const {
    if (query.empty() || tickers_.empty()) return {};

    std::string q = toLower(query);
    std::vector<SearchResult> results;
    results.reserve(maxResults * 2);

    auto lower = std::ranges::lower_bound(tickers_, q, {}, &TickerEntry::symbolLower);
    for (auto it = lower; it != tickers_.end(); ++it) {
        if (!it->symbolLower.starts_with(q)) break;
        results.push_back({&(*it), 100});
    }

    for (const auto& t : tickers_) {
        if (t.symbolLower.starts_with(q)) continue;
        if (t.symbolLower.find(q) != std::string::npos) {
            results.push_back({&t, 50});
        } else if (t.nameLower.find(q) != std::string::npos) {
            results.push_back({&t, 25});
        }
    }

    std::ranges::sort(results, std::greater{}, &SearchResult::score);
    if (static_cast<int>(results.size()) > maxResults) results.resize(maxResults);
    return results;
}

void StockSearchEngine::requestOnline(const std::string& query, int maxResults) {
    if (pythonPath_.empty() || query.size() < 2) return;

    unsigned newId = ++requestId_;
    onlineReady_.store(false);

    if (onlineThread_.joinable()) onlineThread_.join();

    onlineBusy_.store(true);
    onlineThread_ = std::thread(&StockSearchEngine::runOnlineSearch, this,
        query, maxResults, newId);
}

void StockSearchEngine::runOnlineSearch(std::string query, int maxResults, unsigned reqId) {
    std::string cmd = "\"" + pythonPath_ + "\" scripts/search_symbols.py "
        + query + " 2>nul";

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

} // namespace search
