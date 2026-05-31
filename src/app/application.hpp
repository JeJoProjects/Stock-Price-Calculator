#pragma once

#include "imgui.h"
#include "app/appState.hpp"
#include "config/settingsManager.hpp"
#include "ui/theme.hpp"
#include "search/stockSearchEngine.hpp"

struct GLFWwindow;

class Application {
public:
    Application(GLFWwindow* window, const AppSettings& settings);
    void update();
    void saveSettings(int winW, int winH, int winX, int winY);

private:
    GLFWwindow* window_;
    AppState state_;
    search::StockSearchEngine searchEngine_;

    void renderMainWindow();
    void renderTopBar();
    void renderMenuBar();
    void renderSearchBar();
    void renderSearchDropdown();
    void renderPanelArea();
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
    void applySearchResult(const search::TickerEntry& entry);
};
