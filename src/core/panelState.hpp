#pragma once

#include <string>
#include <charconv>

struct PanelState {
    int id = 0;
    int displayIndex = 0;

    std::string investmentText;
    std::string priceText;
    std::string sharesText;
    std::string targetText;

    std::string tickerSymbol;
    std::string companyName;
    std::string exchange;
    std::string matchPreview;

    int lastChanged = 0;
    int secondLastChanged = 0;

    [[nodiscard]] double parseValue(const std::string& text) const {
        if (text.empty()) return 0.0;
        double val = 0.0;
        auto [ptr, ec] = std::from_chars(text.data(), text.data() + text.size(), val);
        return ec == std::errc{} ? val : 0.0;
    }

    [[nodiscard]] double investmentValue() const { return parseValue(investmentText); }
    [[nodiscard]] double priceValue() const { return parseValue(priceText); }
    [[nodiscard]] double sharesValue() const { return parseValue(sharesText); }
    [[nodiscard]] double targetValue() const { return parseValue(targetText); }

    void updateFieldTracking(int fieldId) {
        if (fieldId != lastChanged) {
            secondLastChanged = lastChanged;
            lastChanged = fieldId;
        }
    }

    void reset() {
        investmentText.clear();
        priceText.clear();
        sharesText.clear();
        targetText.clear();
        tickerSymbol.clear();
        companyName.clear();
        exchange.clear();
        matchPreview.clear();
        lastChanged = 0;
        secondLastChanged = 0;
    }
};
