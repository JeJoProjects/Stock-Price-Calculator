#pragma once

#include "imgui.h"
#include <cstdio>
#include <string>
#include <cmath>
#include <algorithm>

namespace helpers {

inline double parseDouble(const std::string& text) {
    if (text.empty()) return 0.0;
    std::string cleaned;
    cleaned.reserve(text.size());
    for (char c : text) {
        if (c != ',') cleaned += c;
    }
    try { return std::stod(cleaned); } catch (...) { return 0.0; }
}

inline std::string addCommas(const std::string& numStr) {
    auto dot = numStr.find('.');
    std::string intPart = (dot != std::string::npos) ? numStr.substr(0, dot) : numStr;
    std::string decPart = (dot != std::string::npos) ? numStr.substr(dot) : "";

    bool negative = (!intPart.empty() && intPart[0] == '-');
    if (negative) intPart = intPart.substr(1);

    std::string result;
    int count = 0;
    for (int i = static_cast<int>(intPart.size()) - 1; i >= 0; --i) {
        if (count > 0 && count % 3 == 0) result += ',';
        result += intPart[i];
        ++count;
    }
    std::reverse(result.begin(), result.end());

    if (negative) result = "-" + result;
    return result + decPart;
}

inline std::string formatCurrency(double value) {
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.2f", std::fabs(value));
    std::string formatted = addCommas(buf);
    if (value < 0.0)
        return "-$" + formatted;
    return "$" + formatted;
}

inline std::string formatProfit(double value) {
    if (std::fabs(value) < 0.005) return "\xe2\x80\x94";
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.2f", std::fabs(value));
    std::string formatted = addCommas(buf);
    if (value > 0.0) return "+$" + formatted;
    return "-$" + formatted;
}

inline std::string formatGain(double value) {
    if (std::fabs(value) < 0.005) return "\xe2\x80\x94";
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.2f%%", std::fabs(value));
    if (value > 0.0) return std::string("+") + buf;
    return std::string("-") + buf;
}

inline std::string formatPercent(double value) {
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.2f%%", value);
    return buf;
}

inline std::string formatNumber(double value, int decimals = 2) {
    char buf[64];
    char fmt[16];
    std::snprintf(fmt, sizeof(fmt), "%%.%df", decimals);
    std::snprintf(buf, sizeof(buf), fmt, value);
    return addCommas(buf);
}

inline std::string formatValue(double value) {
    if (value == 0.0) return "";
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.2f", value);
    return buf;
}

inline void textCentered(const char* text) {
    auto windowWidth = ImGui::GetWindowSize().x;
    auto textWidth = ImGui::CalcTextSize(text).x;
    ImGui::SetCursorPosX((windowWidth - textWidth) * 0.5f);
    ImGui::TextUnformatted(text);
}

inline void textRight(const char* text) {
    auto regionWidth = ImGui::GetContentRegionAvail().x;
    auto textWidth = ImGui::CalcTextSize(text).x;
    ImGui::SetCursorPosX(ImGui::GetCursorPosX() + regionWidth - textWidth);
    ImGui::TextUnformatted(text);
}

inline ImVec4 toVec4(ImU32 col) {
    return ImVec4(
        static_cast<float>((col >> 0) & 0xFF) / 255.0f,
        static_cast<float>((col >> 8) & 0xFF) / 255.0f,
        static_cast<float>((col >> 16) & 0xFF) / 255.0f,
        static_cast<float>((col >> 24) & 0xFF) / 255.0f
    );
}

inline ImU32 withAlpha(ImU32 col, float alpha) {
    return (col & 0x00FFFFFF) | (static_cast<ImU32>(alpha * 255.0f) << 24);
}

} // namespace helpers
