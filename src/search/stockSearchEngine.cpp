#include "search/stockSearchEngine.hpp"
#include <algorithm>
#include <ranges>
#include <cctype>

namespace search {

static std::string toLower(std::string_view sv) {
    std::string result;
    result.reserve(sv.size());
    for (char c : sv) result += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return result;
}

void StockSearchEngine::load(const std::string& jsonPath) {
    tickers_ = loadTickers(jsonPath);
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

    if (static_cast<int>(results.size()) > maxResults) {
        results.resize(maxResults);
    }

    return results;
}

} // namespace search
