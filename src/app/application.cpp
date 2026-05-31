#include "app/application.hpp"
#include "ui/imguiHelpers.hpp"
#include "imgui_stdlib.h"
#include "imgui_internal.h"

#include <GLFW/glfw3.h>
#include <cstdio>
#include <algorithm>
#include <cctype>

static constexpr float kPanelSpacing = 16.0f;
static constexpr float kTopBarHeight = 48.0f;
static constexpr float kSearchBarHeight = 52.0f;
static constexpr float kStatsBarHeight = 72.0f;
static constexpr float kCardRadius = 12.0f;
static constexpr float kInputRadius = 6.0f;
static constexpr float kPanelPadding = 16.0f;

static float panelWidth(float fontSize) {
    // Measure based on the widest content that must fit:
    // label (~80px) + gap + value like "+$888,888.88" in mono font + padding
    ImFont* mono = theme::getMonoFont();
    float valueWidth = 0;
    if (mono) {
        ImGui::PushFont(mono);
        valueWidth = ImGui::CalcTextSize("+$888,888.88").x;
        ImGui::PopFont();
    } else {
        valueWidth = ImGui::CalcTextSize("+$888,888.88").x;
    }
    float labelWidth = ImGui::CalcTextSize("Investment").x;
    float minWidth = labelWidth + valueWidth + kPanelPadding * 2 + 24.0f;
    // Also ensure input fields have room (they fill width)
    float inputMin = ImGui::CalcTextSize("Total Investment ($)").x + kPanelPadding * 2 + 16.0f;
    return std::max(minWidth, inputMin);
    (void)fontSize;
}

static float panelMinHeight(float /*fontSize*/) {
    // Let ImGui auto-size; we just need a reasonable minimum
    float lineH = ImGui::GetTextLineHeightWithSpacing();
    // ~20 lines of content: title, ticker, separator, 4 inputs with labels, badge, separator, 6 output rows, button
    return lineH * 22.0f + kPanelPadding * 2;
}

static int numericInputFilter(ImGuiInputTextCallbackData* data) {
    if (data->EventChar < 256) {
        char c = static_cast<char>(data->EventChar);
        if (c == '.' || (c >= '0' && c <= '9')) return 0;
    }
    return 1;
}

Application::Application(GLFWwindow* window, const AppSettings& settings)
    : window_(window) {
    state_.fontSize = settings.fontSize;
    state_.maxSearchResults = settings.maxSearchResults;
    state_.showExchangeBadges = settings.showExchangeBadges;
    state_.showStatsBar = settings.showStatsBar;
    searchEngine_.load("data/us_tickers_full.json");
    addPanel();
}

void Application::saveSettings(int winW, int winH, int winX, int winY) {
    AppSettings s;
    s.fontSize = state_.fontSize;
    s.maxSearchResults = state_.maxSearchResults;
    s.showExchangeBadges = state_.showExchangeBadges;
    s.showStatsBar = state_.showStatsBar;
    s.windowWidth = winW;
    s.windowHeight = winH;
    s.windowX = winX;
    s.windowY = winY;
    config::saveSettings(s);
}

void Application::update() {
    handleShortcuts();

    const ImGuiViewport* viewport = ImGui::GetMainViewport();
    ImGui::SetNextWindowPos(viewport->WorkPos);
    ImGui::SetNextWindowSize(viewport->WorkSize);

    ImGuiWindowFlags flags = ImGuiWindowFlags_NoTitleBar
        | ImGuiWindowFlags_NoCollapse
        | ImGuiWindowFlags_NoResize
        | ImGuiWindowFlags_NoMove
        | ImGuiWindowFlags_NoBringToFrontOnFocus
        | ImGuiWindowFlags_NoNavFocus
        | ImGuiWindowFlags_MenuBar;

    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 0));
    ImGui::Begin("##MainWindow", nullptr, flags);
    ImGui::PopStyleVar();

    renderMenuBar();
    renderMainWindow();

    ImGui::End();

    if (state_.showPreferences) renderPreferencesDialog();
    if (state_.showAbout) renderAboutDialog();

}

void Application::renderMainWindow() {
    renderTopBar();
    renderSearchBar();
    if (state_.searchDropdownOpen) renderSearchDropdown();

    float statsH = (state_.showStatsBar && state_.combined.validCount > 0) ? kStatsBarHeight : 0.0f;
    ImGui::BeginChild("##PanelArea", ImVec2(0, -statsH), ImGuiChildFlags_None);
    renderPanelArea();
    ImGui::EndChild();

    if (state_.showStatsBar && state_.combined.validCount > 0) {
        renderCombinedStatsBar();
    }
}

// ── Top Bar ──────────────────────────────────────────────────────────────────

void Application::renderTopBar() {
    ImGui::PushStyleColor(ImGuiCol_ChildBg, helpers::toVec4(theme::kBgSecondary));
    ImGui::BeginChild("##TopBar", ImVec2(0, kTopBarHeight), ImGuiChildFlags_None);

    ImGui::SetCursorPos(ImVec2(24.0f, (kTopBarHeight - ImGui::GetTextLineHeight()) * 0.5f));

    ImFont* bold = theme::getBoldFont();
    if (bold) ImGui::PushFont(bold);
    ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextPrimary));
    ImGui::TextUnformatted("\xe2\x86\x97 StockCalc");
    ImGui::PopStyleColor();
    if (bold) ImGui::PopFont();

    ImGui::EndChild();
    ImGui::PopStyleColor();

    ImDrawList* dl = ImGui::GetWindowDrawList();
    ImVec2 p = ImGui::GetCursorScreenPos();
    dl->AddLine(ImVec2(p.x, p.y - 1), ImVec2(p.x + ImGui::GetWindowWidth(), p.y - 1),
        theme::kBorder, 1.0f);
}

// ── Menu Bar ─────────────────────────────────────────────────────────────────

void Application::renderMenuBar() {
    if (ImGui::BeginMenuBar()) {
        if (ImGui::BeginMenu("File")) {
            if (ImGui::MenuItem("New Panel", "Ctrl+N")) addPanel();
            if (ImGui::MenuItem("Reset All", "Ctrl+R")) resetAll();
            ImGui::Separator();
            if (ImGui::MenuItem("Quit", "Ctrl+Q")) glfwSetWindowShouldClose(window_, GLFW_TRUE);
            ImGui::EndMenu();
        }
        if (ImGui::BeginMenu("Edit")) {
            if (ImGui::MenuItem("Preferences", "Ctrl+,")) state_.showPreferences = true;
            if (ImGui::MenuItem("Focus Search", "Ctrl+F")) state_.searchFocusRequested = true;
            ImGui::EndMenu();
        }
        if (ImGui::BeginMenu("View")) {
            ImGui::MenuItem("Stats Bar", nullptr, &state_.showStatsBar);
            ImGui::MenuItem("Exchange Badges", nullptr, &state_.showExchangeBadges);
            ImGui::EndMenu();
        }
        if (ImGui::BeginMenu("Help")) {
            if (ImGui::MenuItem("About")) state_.showAbout = true;
            ImGui::EndMenu();
        }
        ImGui::EndMenuBar();
    }
}

// ── Search Bar ───────────────────────────────────────────────────────────────

void Application::renderSearchBar() {
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(24, 6));
    ImGui::BeginChild("##SearchBarArea", ImVec2(0, kSearchBarHeight), ImGuiChildFlags_None);

    ImGui::SetCursorPosY((kSearchBarHeight - ImGui::GetFrameHeight()) * 0.5f);

    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 8.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(12, 8));

    ImGui::PushItemWidth(-1);
    if (state_.searchFocusRequested) {
        ImGui::SetKeyboardFocusHere();
        state_.searchFocusRequested = false;
    }

    bool changed = ImGui::InputTextWithHint("##SearchBar",
        "Search symbol or company name...",
        &state_.searchQuery, ImGuiInputTextFlags_AutoSelectAll);

    bool focused = ImGui::IsItemFocused();
    ImGui::PopItemWidth();
    ImGui::PopStyleVar(2);

    if (!state_.searchQuery.empty()) {
        ImGui::SameLine();
        ImGui::SetCursorPosX(ImGui::GetCursorPosX() - 32);
        ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextMuted));
        ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0, 0, 0, 0));
        if (ImGui::SmallButton("X##clear")) {
            state_.searchQuery.clear();
            state_.searchDropdownOpen = false;
            state_.searchResults.clear();
            state_.searchFocusRequested = true;
        }
        ImGui::PopStyleColor(4);
    }

    ImGui::EndChild();
    ImGui::PopStyleVar();

    if (changed && !state_.searchQuery.empty()) {
        state_.searchResults.clear();

        // Try online search first (2+ chars to avoid spamming on single char)
        if (state_.searchQuery.size() >= 2) {
            auto online = searchEngine_.searchOnline(state_.searchQuery, state_.maxSearchResults);
            for (auto& r : online) {
                state_.searchResults.push_back({
                    std::move(r.symbol), std::move(r.name), std::move(r.exchange), 200
                });
            }
        }

        // Fill remaining slots with offline results
        if (static_cast<int>(state_.searchResults.size()) < state_.maxSearchResults) {
            int remaining = state_.maxSearchResults - static_cast<int>(state_.searchResults.size());
            auto offline = searchEngine_.search(state_.searchQuery, remaining);
            for (const auto& r : offline) {
                bool duplicate = false;
                for (const auto& existing : state_.searchResults) {
                    if (existing.symbol == r.entry->symbol) { duplicate = true; break; }
                }
                if (!duplicate) {
                    state_.searchResults.push_back({
                        r.entry->symbol, r.entry->name, r.entry->exchange, r.score
                    });
                }
            }
        }

        state_.searchDropdownOpen = !state_.searchResults.empty();
        state_.searchSelectedIndex = 0;
    } else if (state_.searchQuery.empty()) {
        state_.searchDropdownOpen = false;
        state_.searchResults.clear();
    }

    if (focused && state_.searchDropdownOpen) {
        if (ImGui::IsKeyPressed(ImGuiKey_DownArrow)) {
            state_.searchSelectedIndex = std::min(
                state_.searchSelectedIndex + 1,
                static_cast<int>(state_.searchResults.size()) - 1);
        }
        if (ImGui::IsKeyPressed(ImGuiKey_UpArrow)) {
            state_.searchSelectedIndex = std::max(state_.searchSelectedIndex - 1, 0);
        }
        if (ImGui::IsKeyPressed(ImGuiKey_Enter) && state_.searchSelectedIndex >= 0
            && state_.searchSelectedIndex < static_cast<int>(state_.searchResults.size())) {
            auto& sel = state_.searchResults[state_.searchSelectedIndex];
            search::TickerEntry entry{sel.symbol, sel.name, sel.exchange, {}, {}};
            applySearchResult(entry);
            state_.searchQuery.clear();
            state_.searchDropdownOpen = false;
            state_.searchResults.clear();
        }
        if (ImGui::IsKeyPressed(ImGuiKey_Escape)) {
            state_.searchDropdownOpen = false;
            state_.searchResults.clear();
        }
    }
}

// ── Autocomplete Dropdown ────────────────────────────────────────────────────

void Application::renderSearchDropdown() {
    ImGui::PushStyleColor(ImGuiCol_ChildBg, helpers::toVec4(theme::kBgSecondary));
    ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 8.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 4));

    float itemHeight = ImGui::GetTextLineHeightWithSpacing() + 8.0f;
    float footerHeight = ImGui::GetTextLineHeightWithSpacing() + 8.0f;
    float maxHeight = 340.0f;
    float contentHeight = static_cast<float>(state_.searchResults.size()) * itemHeight + footerHeight + 8.0f;
    float dropdownHeight = std::min(contentHeight, maxHeight);

    ImGui::SetCursorPosX(24.0f);
    ImGui::BeginChild("##SearchDropdown", ImVec2(-24, dropdownHeight), ImGuiChildFlags_Borders);

    for (int i = 0; i < static_cast<int>(state_.searchResults.size()); ++i) {
        const auto& r = state_.searchResults[i];
        bool selected = (i == state_.searchSelectedIndex);

        if (selected) {
            ImVec2 p = ImGui::GetCursorScreenPos();
            ImDrawList* dl = ImGui::GetWindowDrawList();
            dl->AddRectFilled(p, ImVec2(p.x + ImGui::GetContentRegionAvail().x, p.y + itemHeight),
                helpers::withAlpha(theme::kAccentBlue, 0.12f));
            dl->AddRectFilled(p, ImVec2(p.x + 3, p.y + itemHeight),
                theme::kAccentBlue);
        }

        ImGui::PushID(i);
        ImGui::SetCursorPosX(ImGui::GetCursorPosX() + 12.0f);

        ImFont* mono = theme::getMonoFont();
        if (mono) ImGui::PushFont(mono);
        ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kWhite));
        ImGui::TextUnformatted(r.symbol.c_str());
        ImGui::PopStyleColor();
        if (mono) ImGui::PopFont();

        ImGui::SameLine(92);
        ImGui::TextUnformatted(r.name.c_str());

        if (state_.showExchangeBadges) {
            ImGui::SameLine();
            ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextMuted));

            ImVec2 badgePos = ImGui::GetCursorScreenPos();
            ImVec2 badgeSize = ImGui::CalcTextSize(r.exchange.c_str());
            ImDrawList* dl = ImGui::GetWindowDrawList();
            dl->AddRectFilled(
                ImVec2(badgePos.x - 4, badgePos.y - 1),
                ImVec2(badgePos.x + badgeSize.x + 4, badgePos.y + badgeSize.y + 1),
                IM_COL32(0x36, 0x3C, 0x4E, 0xFF), 3.0f);
            ImGui::TextUnformatted(r.exchange.c_str());
            ImGui::PopStyleColor();
        }

        ImVec2 cursorAfterRow = ImGui::GetCursorPos();
        float padY = itemHeight - (cursorAfterRow.y - (ImGui::GetCursorStartPos().y + i * itemHeight));
        if (padY > 0) ImGui::SetCursorPosY(cursorAfterRow.y + padY * 0.5f);

        if (ImGui::InvisibleButton("##sel", ImVec2(-1, 1))) {
            search::TickerEntry entry{r.symbol, r.name, r.exchange, {}, {}};
            applySearchResult(entry);
            state_.searchQuery.clear();
            state_.searchDropdownOpen = false;
            state_.searchResults.clear();
            ImGui::PopID();
            ImGui::EndChild();
            ImGui::PopStyleVar(2);
            ImGui::PopStyleColor();
            return;
        }

        ImGui::PopID();
    }

    ImGui::Spacing();
    ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextMuted));
    helpers::textCentered("\xe2\x86\x91\xe2\x86\x93 navigate  \xe2\x80\xa2  Enter select  \xe2\x80\xa2  Esc close");
    ImGui::PopStyleColor();

    ImGui::EndChild();
    ImGui::PopStyleVar(2);
    ImGui::PopStyleColor();
}

// ── Panel Area ───────────────────────────────────────────────────────────────

void Application::renderPanelArea() {
    float pw = panelWidth(state_.fontSize);
    float ph = panelMinHeight(state_.fontSize);

    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(24, 24));
    ImGui::BeginChild("##PanelScroll", ImVec2(0, 0), ImGuiChildFlags_None,
        ImGuiWindowFlags_HorizontalScrollbar);

    for (int i = 0; i < static_cast<int>(state_.panels.size()); ++i) {
        if (i > 0) ImGui::SameLine(0, kPanelSpacing);

        ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, kCardRadius);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(16, 16));
        ImGui::PushStyleColor(ImGuiCol_ChildBg, helpers::toVec4(theme::kBgSecondary));

        ImGui::BeginChild(state_.panels[i].id + 1000,
            ImVec2(pw, ph), ImGuiChildFlags_Borders);
        renderSinglePanel(i);
        ImGui::EndChild();

        ImGui::PopStyleColor();
        ImGui::PopStyleVar(2);
    }

    ImGui::SameLine(0, kPanelSpacing);
    renderNewPurchaseCard();

    ImGui::EndChild();
    ImGui::PopStyleVar();

    if (state_.panelToDelete >= 0) {
        removePanel(state_.panelToDelete);
        state_.panelToDelete = -1;
    }
}

// ── Single Panel Card ────────────────────────────────────────────────────────

void Application::renderSinglePanel(int index) {
    auto& panel = state_.panels[index];

    // Header row
    char titleBuf[64];
    std::snprintf(titleBuf, sizeof(titleBuf), "Purchase %d", index + 1);

    ImFont* bold = theme::getBoldFont();
    if (bold) ImGui::PushFont(bold);
    ImGui::TextUnformatted(titleBuf);
    if (bold) ImGui::PopFont();

    if (state_.panels.size() > 1) {
        ImGui::SameLine(ImGui::GetContentRegionAvail().x - 16);
        ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextMuted));
        ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0, 0, 0, 0));
        char delId[32];
        std::snprintf(delId, sizeof(delId), "\xe2\x9c\x95##del%d", panel.id);
        bool hovered = false;
        if (ImGui::SmallButton(delId)) {
            state_.panelToDelete = index;
        }
        hovered = ImGui::IsItemHovered();
        ImGui::PopStyleColor(4);
        if (hovered) {
            ImGui::GetStyle().Colors[ImGuiCol_Text] = helpers::toVec4(theme::kLossRed);
        }
    }

    // Ticker info
    if (!panel.tickerSymbol.empty()) {
        ImFont* mono = theme::getMonoFont();
        if (mono) ImGui::PushFont(mono);
        ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kAccentBlue));
        ImGui::TextUnformatted(panel.tickerSymbol.c_str());
        ImGui::PopStyleColor();
        if (mono) ImGui::PopFont();

        if (!panel.companyName.empty()) {
            ImGui::SameLine();
            ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextMuted));
            ImGui::TextUnformatted(panel.companyName.c_str());
            ImGui::PopStyleColor();
        }
    }

    ImGui::Spacing();
    ImGui::Separator();
    ImGui::Spacing();

    // Get result for inferred field highlighting
    int inferredField = 0;
    if (index < static_cast<int>(state_.results.size())) {
        inferredField = state_.results[index].inferredField;
    }

    auto inputField = [&](const char* fieldLabel, std::string& text, int fieldId) {
        ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextMuted));
        ImGui::TextUnformatted(fieldLabel);
        ImGui::PopStyleColor();

        char inputId[64];
        std::snprintf(inputId, sizeof(inputId), "##field%d_%d", panel.id, fieldId);

        bool isInferred = (inferredField == fieldId);
        if (isInferred) {
            ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextMuted));
            ImGui::PushStyleColor(ImGuiCol_Border, helpers::toVec4(theme::kAccentBlue));
            ImGui::PushStyleVar(ImGuiStyleVar_FrameBorderSize, 2.0f);
        }

        ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, kInputRadius);
        ImGui::PushItemWidth(-1);
        if (ImGui::InputText(inputId, &text, ImGuiInputTextFlags_CallbackCharFilter,
                numericInputFilter)) {
            panel.updateFieldTracking(fieldId);
            recalculateAll();
        }
        ImGui::PopItemWidth();
        ImGui::PopStyleVar();

        if (isInferred) {
            ImGui::PopStyleVar();
            ImGui::PopStyleColor(2);
        }
    };

    inputField("Total Investment ($)", panel.investmentText, 1);
    inputField("Share Price ($)", panel.priceText, 2);
    inputField("Number of Shares", panel.sharesText, 3);

    ImGui::Spacing();
    inputField("Target Price ($)", panel.targetText, 4);

    // Auto-inference badge
    if (inferredField > 0) {
        ImGui::Spacing();
        const char* inferredNames[] = {"", "Investment", "Share Price", "Shares"};
        char badgeBuf[64];
        std::snprintf(badgeBuf, sizeof(badgeBuf), "AUTO: %s", inferredNames[inferredField]);

        ImVec2 badgePos = ImGui::GetCursorScreenPos();
        ImVec2 badgeSize = ImGui::CalcTextSize(badgeBuf);
        ImDrawList* dl = ImGui::GetWindowDrawList();
        dl->AddRectFilled(
            ImVec2(badgePos.x, badgePos.y - 2),
            ImVec2(badgePos.x + badgeSize.x + 8, badgePos.y + badgeSize.y + 2),
            helpers::withAlpha(theme::kAccentBlue, 0.12f), 3.0f);

        ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kAccentBlue));
        ImGui::SetCursorPosX(ImGui::GetCursorPosX() + 4);
        ImGui::TextUnformatted(badgeBuf);
        ImGui::PopStyleColor();
    }

    ImGui::Spacing();
    ImGui::Separator();
    ImGui::Spacing();

    // Output section
    if (index < static_cast<int>(state_.results.size())) {
        const auto& res = state_.results[index];

        ImFont* mono = theme::getMonoFont();

        auto outputRow = [mono](const char* lbl, const std::string& val, ImU32 color = 0) {
            ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextMuted));
            ImGui::TextUnformatted(lbl);
            ImGui::PopStyleColor();

            // Measure value width using the mono font it will be rendered in
            float valWidth;
            if (mono) {
                ImGui::PushFont(mono);
                valWidth = ImGui::CalcTextSize(val.c_str()).x;
                ImGui::PopFont();
            } else {
                valWidth = ImGui::CalcTextSize(val.c_str()).x;
            }

            // Right-align: position = window content width - value width
            float windowWidth = ImGui::GetWindowContentRegionMax().x;
            ImGui::SameLine(windowWidth - valWidth);

            if (mono) ImGui::PushFont(mono);
            if (color) ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(color));
            ImGui::TextUnformatted(val.c_str());
            if (color) ImGui::PopStyleColor();
            if (mono) ImGui::PopFont();
        };

        if (res.totalInvestment > 0.0)
            outputRow("Investment", helpers::formatCurrency(res.totalInvestment));
        if (res.sharePrice > 0.0)
            outputRow("Price", helpers::formatCurrency(res.sharePrice));
        if (res.totalShares > 0.0)
            outputRow("Shares", helpers::formatNumber(res.totalShares));

        if (res.profitPlusInvest != 0.0) {
            ImGui::Spacing();
            outputRow("Return", helpers::formatCurrency(res.profitPlusInvest), theme::kTextPrimary);

            ImU32 profitColor = (std::fabs(res.profit) < 0.005) ? theme::kTextMuted
                : (res.profit > 0.0 ? theme::kProfitGreen : theme::kLossRed);
            outputRow("Profit", helpers::formatProfit(res.profit), profitColor);
            outputRow("Gain %", helpers::formatGain(res.gainPercent), profitColor);
        }
    }

    // Push reset button to bottom
    float remaining = ImGui::GetContentRegionAvail().y - ImGui::GetFrameHeightWithSpacing() - 4;
    if (remaining > 0) ImGui::SetCursorPosY(ImGui::GetCursorPosY() + remaining);

    ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0, 0, 0, 0));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0, 0, 0, 0));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0, 0, 0, 0));
    ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextMuted));
    ImGui::PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, kInputRadius);

    float btnWidth = 60.0f;
    ImGui::SetCursorPosX(ImGui::GetCursorPosX() + ImGui::GetContentRegionAvail().x - btnWidth);
    char resetId[32];
    std::snprintf(resetId, sizeof(resetId), "Reset##p%d", panel.id);
    if (ImGui::Button(resetId, ImVec2(btnWidth, 0))) {
        panel.reset();
        recalculateAll();
    }
    bool resetHovered = ImGui::IsItemHovered();
    ImGui::PopStyleVar(2);
    ImGui::PopStyleColor(4);

    if (resetHovered) {
        ImDrawList* dl = ImGui::GetWindowDrawList();
        ImVec2 min = ImGui::GetItemRectMin();
        ImVec2 max = ImGui::GetItemRectMax();
        dl->AddRect(min, max, theme::kLossRed, kInputRadius, 0, 1.0f);
    }
}

// ── New Purchase Placeholder Card ────────────────────────────────────────────

void Application::renderNewPurchaseCard() {
    float pw = panelWidth(state_.fontSize);
    float ph = panelMinHeight(state_.fontSize);

    ImVec2 startPos = ImGui::GetCursorScreenPos();

    // Full-area invisible button FIRST so the entire card is clickable
    bool clicked = ImGui::InvisibleButton("##addPanelBtn", ImVec2(pw, ph));
    bool hovered = ImGui::IsItemHovered();

    ImU32 borderColor = hovered ? theme::kAccentBlue : theme::kBorder;
    ImU32 textColor = hovered ? theme::kAccentBlue : theme::kTextMuted;

    // Draw dashed border over the invisible button area
    ImDrawList* dl = ImGui::GetWindowDrawList();
    ImVec2 min = startPos;
    ImVec2 max = ImVec2(min.x + pw, min.y + ph);

    float dashLen = 8.0f;
    float gapLen = 6.0f;
    float r = kCardRadius;

    auto drawDashedLine = [&](float x1, float y1, float x2, float y2) {
        float dx = x2 - x1, dy = y2 - y1;
        float len = std::sqrt(dx * dx + dy * dy);
        if (len < 0.01f) return;
        float nx = dx / len, ny = dy / len;
        float pos = 0;
        while (pos < len) {
            float segEnd = std::min(pos + dashLen, len);
            dl->AddLine(ImVec2(x1 + nx * pos, y1 + ny * pos),
                ImVec2(x1 + nx * segEnd, y1 + ny * segEnd), borderColor, 2.0f);
            pos = segEnd + gapLen;
        }
    };

    drawDashedLine(min.x + r, min.y, max.x - r, min.y);
    drawDashedLine(max.x, min.y + r, max.x, max.y - r);
    drawDashedLine(max.x - r, max.y, min.x + r, max.y);
    drawDashedLine(min.x, max.y - r, min.x, min.y + r);

    // Draw centered "+" and "New Purchase" text over the button
    float centerY = startPos.y + ph * 0.35f;
    ImFont* font = ImGui::GetFont();
    float baseSize = ImGui::GetFontSize();

    const char* plusText = "+";
    float plusSize = baseSize * 2.0f;
    ImVec2 plusTextSize = font->CalcTextSizeA(plusSize, FLT_MAX, 0, plusText);
    dl->AddText(font, plusSize,
        ImVec2(startPos.x + (pw - plusTextSize.x) * 0.5f, centerY),
        textColor, plusText);

    const char* label = "New Purchase";
    ImVec2 labelSize = font->CalcTextSizeA(baseSize, FLT_MAX, 0, label);
    float labelY = centerY + plusSize + 8.0f;
    dl->AddText(font, baseSize,
        ImVec2(startPos.x + (pw - labelSize.x) * 0.5f, labelY),
        textColor, label);

    if (clicked) {
        addPanel();
    }
}

// ── Combined Stats Bar ───────────────────────────────────────────────────────

void Application::renderCombinedStatsBar() {
    const auto& c = state_.combined;

    ImGui::PushStyleColor(ImGuiCol_ChildBg, helpers::toVec4(theme::kBgSecondary));
    ImGui::BeginChild("##StatsBar", ImVec2(0, kStatsBarHeight), ImGuiChildFlags_None);

    ImDrawList* dl = ImGui::GetWindowDrawList();
    ImVec2 p = ImGui::GetCursorScreenPos();
    dl->AddLine(ImVec2(p.x, p.y), ImVec2(p.x + ImGui::GetWindowWidth(), p.y),
        theme::kBorder, 1.0f);

    ImGui::SetCursorPos(ImVec2(24, 8));

    auto statBlock = [this](const char* lbl, const std::string& val, ImU32 valColor = theme::kWhite) {
        ImGui::BeginGroup();
        ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextMuted));
        ImGui::TextUnformatted(lbl);
        ImGui::PopStyleColor();

        ImFont* mono = theme::getMonoFont();
        if (mono) ImGui::PushFont(mono);
        ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(valColor));
        ImGui::TextUnformatted(val.c_str());
        ImGui::PopStyleColor();
        if (mono) ImGui::PopFont();
        ImGui::EndGroup();

        ImGui::SameLine(0, 32);
    };

    statBlock("Avg Price", helpers::formatCurrency(c.avgSharePrice));
    statBlock("Total Investment", helpers::formatCurrency(c.totalInvestment));
    statBlock("Total Shares", helpers::formatNumber(c.totalShares, 3));

    ImU32 profitColor = (std::fabs(c.totalProfit) < 0.005) ? theme::kTextMuted
        : (c.totalProfit > 0.0 ? theme::kProfitGreen : theme::kLossRed);
    statBlock("Total Profit", helpers::formatProfit(c.totalProfit), profitColor);
    statBlock("Avg Profit", helpers::formatProfit(c.avgProfit), profitColor);

    // Reset All button
    ImGui::SameLine();
    float btnY = (kStatsBarHeight - 36) * 0.5f;
    ImGui::SetCursorPosY(btnY);
    ImGui::PushStyleColor(ImGuiCol_Button, helpers::toVec4(theme::kLossRed));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.83f, 0.18f, 0.24f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.70f, 0.16f, 0.20f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kWhite));
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, kInputRadius);

    ImFont* bold = theme::getBoldFont();
    if (bold) ImGui::PushFont(bold);
    if (ImGui::Button("Reset All", ImVec2(100, 36))) {
        resetAll();
    }
    if (bold) ImGui::PopFont();

    ImGui::PopStyleVar();
    ImGui::PopStyleColor(4);

    ImGui::EndChild();
    ImGui::PopStyleColor();
}

// ── Preferences Dialog ──────────────────────────────────────────────────────

void Application::renderPreferencesDialog() {
    ImGui::SetNextWindowSize(ImVec2(400, 320), ImGuiCond_FirstUseEver);
    ImGui::Begin("Preferences", &state_.showPreferences);

    ImFont* bold = theme::getBoldFont();
    if (bold) ImGui::PushFont(bold);
    ImGui::TextUnformatted("Appearance");
    if (bold) ImGui::PopFont();
    ImGui::Separator();
    ImGui::Spacing();

    if (ImGui::SliderFloat("Font Size", &state_.fontSize, 10.0f, 24.0f, "%.0f px")) {
        state_.fontRebuildNeeded = true;
    }

    ImGui::Spacing();
    ImGui::SliderInt("Max Search Results", &state_.maxSearchResults, 5, 25);

    ImGui::Spacing();
    if (bold) ImGui::PushFont(bold);
    ImGui::TextUnformatted("Display");
    if (bold) ImGui::PopFont();
    ImGui::Separator();
    ImGui::Spacing();

    ImGui::Checkbox("Show Exchange Badges", &state_.showExchangeBadges);
    ImGui::Checkbox("Show Stats Bar", &state_.showStatsBar);

    ImGui::Spacing();
    ImGui::Spacing();

    char tickerInfo[64];
    std::snprintf(tickerInfo, sizeof(tickerInfo), "Loaded tickers: %zu",
        searchEngine_.tickerCount());
    ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextMuted));
    ImGui::TextUnformatted(tickerInfo);
    ImGui::PopStyleColor();

    ImGui::End();
}

// ── About Dialog ─────────────────────────────────────────────────────────────

void Application::renderAboutDialog() {
    ImGui::SetNextWindowSize(ImVec2(380, 220), ImGuiCond_FirstUseEver);
    if (ImGui::Begin("About Stock Price Calculator", &state_.showAbout)) {
        ImFont* bold = theme::getBoldFont();
        if (bold) ImGui::PushFont(bold);
        ImGui::TextUnformatted("Stock Price Calculator");
        if (bold) ImGui::PopFont();

        ImGui::Spacing();
        ImGui::TextUnformatted("Version 2.0  |  C++23 / ImGui Edition");
        ImGui::Spacing();
        ImGui::TextWrapped("Calculate stock investment profit with multiple purchases, "
            "smart field inference, and US stock symbol search.");
        ImGui::Spacing();

        ImGui::PushStyleColor(ImGuiCol_Text, helpers::toVec4(theme::kTextMuted));
        ImGui::TextUnformatted("Built with Dear ImGui + GLFW + OpenGL3");
        ImGui::TextUnformatted("TradingView-inspired dark theme");
        ImGui::PopStyleColor();
    }
    ImGui::End();
}

// ── Logic ────────────────────────────────────────────────────────────────────

void Application::addPanel() {
    PanelState panel;
    panel.id = state_.nextPanelId++;
    panel.displayIndex = static_cast<int>(state_.panels.size());
    state_.panels.push_back(std::move(panel));
    state_.results.resize(state_.panels.size());
}

void Application::removePanel(int index) {
    if (index < 0 || index >= static_cast<int>(state_.panels.size())) return;
    state_.panels.erase(state_.panels.begin() + index);
    for (int i = 0; i < static_cast<int>(state_.panels.size()); ++i) {
        state_.panels[i].displayIndex = i;
    }
    recalculateAll();
}

void Application::resetAll() {
    state_.panels.clear();
    state_.results.clear();
    state_.combined = {};
    state_.nextPanelId = 1;
    addPanel();
}

void Application::recalculateAll() {
    state_.results.resize(state_.panels.size());
    for (int i = 0; i < static_cast<int>(state_.panels.size()); ++i) {
        auto& p = state_.panels[i];
        stockcalc::PanelInput input{
            .totalInvestment = p.investmentValue(),
            .sharePrice = p.priceValue(),
            .totalShares = p.sharesValue(),
            .targetPrice = p.targetValue(),
            .lastChanged = p.lastChanged,
            .secondLastChanged = p.secondLastChanged,
        };
        auto result = stockcalc::calculatePanel(input);

        // Write inferred values back into text fields (matching Python behavior)
        if (result.inferredField == 1 && result.totalInvestment > 0.0) {
            p.investmentText = helpers::formatValue(result.totalInvestment);
        } else if (result.inferredField == 2 && result.sharePrice > 0.0) {
            p.priceText = helpers::formatValue(result.sharePrice);
        } else if (result.inferredField == 3 && result.totalShares > 0.0) {
            p.sharesText = helpers::formatValue(result.totalShares);
        }

        state_.results[i] = result;
    }
    state_.combined = stockcalc::calculateCombined(state_.results);
}

void Application::handleShortcuts() {
    auto& io = ImGui::GetIO();
    if (io.KeyCtrl) {
        if (ImGui::IsKeyPressed(ImGuiKey_N)) addPanel();
        if (ImGui::IsKeyPressed(ImGuiKey_R)) resetAll();
        if (ImGui::IsKeyPressed(ImGuiKey_Q)) glfwSetWindowShouldClose(window_, GLFW_TRUE);
        if (ImGui::IsKeyPressed(ImGuiKey_F)) state_.searchFocusRequested = true;
        if (ImGui::IsKeyPressed(ImGuiKey_Comma)) state_.showPreferences = true;
    }
}

void Application::applySearchResult(const search::TickerEntry& entry) {
    if (state_.panels.empty()) addPanel();
    auto& panel = state_.panels.back();
    panel.tickerSymbol = entry.symbol;
    panel.companyName = entry.name;
    panel.exchange = entry.exchange;
}
