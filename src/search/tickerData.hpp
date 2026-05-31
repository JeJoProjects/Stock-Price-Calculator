#pragma once

#include <string>
#include <vector>

namespace search {

struct TickerEntry {
    std::string symbol;
    std::string name;
    std::string exchange;
    std::string symbolLower;
    std::string nameLower;
};

[[nodiscard]] std::vector<TickerEntry> loadTickers(const std::string& jsonPath);

} // namespace search
