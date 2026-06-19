#pragma once

#include "imgui.h"
#include "app/appState.hpp"
#include "config/settingsManager.hpp"
#include "ui/theme.hpp"
#include "search/stockSearchEngine.hpp"
#include "market/marketDataService.hpp"

#include <optional>

struct GLFWwindow;

class Application {
public:
    Application(GLFWwindow* window, const AppSettings& settings);
    void update();
    void saveSettings(int winW, int winH, int winX, int winY);
    [[nodiscard]] bool needsFontRebuild() const { return state_.fontRebuildNeeded; }
    void clearFontRebuild() { state_.fontRebuildNeeded = false; }
    [[nodiscard]] float fontSize() const { return state_.fontSize; }

private:
    GLFWwindow* window_;
    AppState state_;
    search::StockSearchEngine searchEngine_;
    market::MarketDataService marketData_;
    std::optional<market::Snapshot> currentMarketSnapshot_;
    std::string pendingOnlineQuery_;
    double pendingOnlineRequestAt_ = 0.0;
    bool hasPendingOnlineRequest_ = false;
    std::string lastChartRequestKey_;

    void renderMainWindow();
    void renderTopBar();
    void renderMenuBar();
    void renderSearchBar();
    void renderSearchDropdown();
    void renderPanelArea();
    void renderWorkspace();
    void renderChartPane();
    void renderSinglePanel(int index);
    void renderNewPurchaseCard();
    void renderCombinedStatsBar();
    void renderPreferencesDialog();
    void renderAboutDialog();

    void addPanel();
    void removePanel(int index);
    void resetAll();
    void recalculateAll();
    void handleShortcuts();
    void applySearchResult(const search::TickerEntry& entry, const std::string& preview = {});
    void mergeOnlineResults();
    void dispatchPendingOnlineSearch();
    void syncChartSelection();
};
