#include "search/tickerData.hpp"
#include <fstream>
#include <sstream>
#include <algorithm>
#include <cctype>

namespace search {

static std::string toLower(std::string_view sv) {
    std::string result;
    result.reserve(sv.size());
    for (char c : sv) result += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return result;
}

static std::string extractJsonString(const std::string& json, const std::string& key) {
    auto keyPattern = "\"" + key + "\"";
    auto pos = json.find(keyPattern);
    if (pos == std::string::npos) return {};

    pos = json.find('"', pos + keyPattern.size() + 1);
    if (pos == std::string::npos) return {};
    ++pos;

    auto end = json.find('"', pos);
    if (end == std::string::npos) return {};

    return json.substr(pos, end - pos);
}

std::vector<TickerEntry> loadTickers(const std::string& jsonPath) {
    std::ifstream file(jsonPath);
    if (!file.is_open()) return {};

    std::ostringstream ss;
    ss << file.rdbuf();
    std::string content = ss.str();

    std::vector<TickerEntry> tickers;

    std::size_t pos = 0;
    while ((pos = content.find('{', pos)) != std::string::npos) {
        auto end = content.find('}', pos);
        if (end == std::string::npos) break;

        std::string obj = content.substr(pos, end - pos + 1);

        TickerEntry entry;
        entry.symbol = extractJsonString(obj, "symbol");
        entry.name = extractJsonString(obj, "name");
        entry.exchange = extractJsonString(obj, "exchange");

        if (!entry.symbol.empty()) {
            entry.symbolLower = toLower(entry.symbol);
            entry.nameLower = toLower(entry.name);
            tickers.push_back(std::move(entry));
        }

        pos = end + 1;
    }

    std::ranges::sort(tickers, {}, &TickerEntry::symbolLower);
    return tickers;
}

} // namespace search
