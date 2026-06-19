#pragma once

#include <string>

struct AppSettings {
    float fontSize = 28.0f;
    int maxSearchResults = 12;
    bool showExchangeBadges = true;
    bool showStatsBar = true;
    std::string finnhubApiKey;
    int windowWidth = 1600;
    int windowHeight = 900;
    int windowX = -1;
    int windowY = -1;
};

namespace config {

[[nodiscard]] AppSettings loadSettings(const std::string& path = "stockcalc_settings.json");
void saveSettings(const AppSettings& settings, const std::string& path = "stockcalc_settings.json");

} // namespace config
