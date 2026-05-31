#pragma once

#include <string>

struct AppSettings {
    float fontSize = 15.0f;
    int maxSearchResults = 12;
    bool showExchangeBadges = true;
    bool showStatsBar = true;
    int windowWidth = 1280;
    int windowHeight = 720;
    int windowX = -1;
    int windowY = -1;
};

namespace config {

[[nodiscard]] AppSettings loadSettings(const std::string& path = "stockcalc_settings.json");
void saveSettings(const AppSettings& settings, const std::string& path = "stockcalc_settings.json");

} // namespace config
