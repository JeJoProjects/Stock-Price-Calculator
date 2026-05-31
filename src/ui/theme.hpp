#pragma once

#include "imgui.h"

namespace theme {

inline constexpr ImU32 kBgPrimary   = IM_COL32(0x13, 0x17, 0x22, 0xFF);
inline constexpr ImU32 kBgSecondary = IM_COL32(0x1E, 0x22, 0x2D, 0xFF);
inline constexpr ImU32 kBgInput     = IM_COL32(0x2A, 0x2E, 0x39, 0xFF);
inline constexpr ImU32 kBgHover     = IM_COL32(0x36, 0x3C, 0x4E, 0xFF);
inline constexpr ImU32 kBorder      = IM_COL32(0x36, 0x3C, 0x4E, 0xFF);
inline constexpr ImU32 kTextPrimary = IM_COL32(0xD1, 0xD4, 0xDC, 0xFF);
inline constexpr ImU32 kTextMuted   = IM_COL32(0x78, 0x7B, 0x86, 0xFF);
inline constexpr ImU32 kAccentBlue  = IM_COL32(0x29, 0x62, 0xFF, 0xFF);
inline constexpr ImU32 kProfitGreen = IM_COL32(0x08, 0x99, 0x81, 0xFF);
inline constexpr ImU32 kLossRed    = IM_COL32(0xF2, 0x36, 0x45, 0xFF);
inline constexpr ImU32 kWhite      = IM_COL32(0xFF, 0xFF, 0xFF, 0xFF);

void applyTradingViewTheme(float fontSize);
void loadFonts(float fontSize);

ImFont* getDefaultFont();
ImFont* getMonoFont();
ImFont* getBoldFont();

} // namespace theme
