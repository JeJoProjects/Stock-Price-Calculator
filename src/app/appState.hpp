#pragma once

#include <string>
#include <vector>
#include "core/calcEngine.hpp"
#include "core/panelState.hpp"
#include "market/marketTypes.hpp"

struct SearchResultEntry {
    std::string symbol;
    std::string name;
    std::string exchange;
    std::string preview;
    int score = 0;
};

struct AppState {
    std::vector<PanelState> panels;
    std::vector<stockcalc::PanelResult> results;
    stockcalc::CombinedResult combined{};
    int nextPanelId = 1;

    std::string searchQuery;
    std::vector<SearchResultEntry> searchResults;
    int searchSelectedIndex = -1;
    bool searchDropdownOpen = false;
    bool searchFocusRequested = false;

    bool showPreferences = false;
    bool showAbout = false;
    bool showStatsBar = true;
    int panelToDelete = -1;
    std::string finnhubApiKey;
    std::string chartSymbol;
    market::Timeframe chartTimeframe = market::Timeframe::day1;

    float fontSize = 15.0f;
    bool showExchangeBadges = true;
    int maxSearchResults = 12;
    bool fontRebuildNeeded = false;
};
