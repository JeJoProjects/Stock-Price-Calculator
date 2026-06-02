#include "ui/theme.hpp"
#include "ui/imguiHelpers.hpp"

static ImFont* sDefaultFont = nullptr;
static ImFont* sMonoFont = nullptr;
static ImFont* sBoldFont = nullptr;
static ImFont* sStatsFont = nullptr;

static constexpr float kStatsFontSize = 34.0f;

namespace theme {

void loadFonts(float fontSize) {
    auto& io = ImGui::GetIO();
    io.Fonts->Clear();

    ImFontConfig cfg{};
    cfg.OversampleH = 2;
    cfg.OversampleV = 1;

    sDefaultFont = io.Fonts->AddFontFromFileTTF("C:\\Windows\\Fonts\\segoeui.ttf", fontSize, &cfg);
    if (!sDefaultFont) {
        sDefaultFont = io.Fonts->AddFontDefault();
    }

    sMonoFont = io.Fonts->AddFontFromFileTTF("C:\\Windows\\Fonts\\consola.ttf", fontSize, &cfg);
    if (!sMonoFont) {
        sMonoFont = sDefaultFont;
    }

    ImFontConfig boldCfg{};
    boldCfg.OversampleH = 2;
    boldCfg.OversampleV = 1;
    sBoldFont = io.Fonts->AddFontFromFileTTF("C:\\Windows\\Fonts\\segoeuib.ttf", fontSize, &boldCfg);
    if (!sBoldFont) {
        sBoldFont = sDefaultFont;
    }

    // Stats bar font — always 34px for high visibility
    ImFontConfig statsCfg{};
    statsCfg.OversampleH = 2;
    statsCfg.OversampleV = 1;
    sStatsFont = io.Fonts->AddFontFromFileTTF("C:\\Windows\\Fonts\\consolab.ttf", kStatsFontSize, &statsCfg);
    if (!sStatsFont) {
        sStatsFont = io.Fonts->AddFontFromFileTTF("C:\\Windows\\Fonts\\consola.ttf", kStatsFontSize, &statsCfg);
    }
    if (!sStatsFont) {
        sStatsFont = sMonoFont;
    }

    io.Fonts->Build();
}

void applyTradingViewTheme(float fontSize) {
    auto& style = ImGui::GetStyle();
    auto* colors = style.Colors;

    auto v4 = [](ImU32 c) { return helpers::toVec4(c); };

    colors[ImGuiCol_WindowBg]           = v4(kBgPrimary);
    colors[ImGuiCol_ChildBg]            = ImVec4(0, 0, 0, 0);
    colors[ImGuiCol_PopupBg]            = v4(kBgSecondary);
    colors[ImGuiCol_Border]             = v4(kBorder);
    colors[ImGuiCol_BorderShadow]       = ImVec4(0, 0, 0, 0);

    colors[ImGuiCol_FrameBg]            = v4(kBgInput);
    colors[ImGuiCol_FrameBgHovered]     = v4(kBgHover);
    colors[ImGuiCol_FrameBgActive]      = v4(kBgHover);

    colors[ImGuiCol_TitleBg]            = v4(kBgSecondary);
    colors[ImGuiCol_TitleBgActive]      = v4(kBgSecondary);
    colors[ImGuiCol_TitleBgCollapsed]   = v4(kBgSecondary);

    colors[ImGuiCol_MenuBarBg]          = v4(kBgSecondary);

    colors[ImGuiCol_ScrollbarBg]        = v4(kBgPrimary);
    colors[ImGuiCol_ScrollbarGrab]      = v4(kBorder);
    colors[ImGuiCol_ScrollbarGrabHovered] = v4(kTextMuted);
    colors[ImGuiCol_ScrollbarGrabActive]  = v4(kTextPrimary);

    colors[ImGuiCol_CheckMark]          = v4(kAccentBlue);
    colors[ImGuiCol_SliderGrab]         = v4(kAccentBlue);
    colors[ImGuiCol_SliderGrabActive]   = v4(kAccentBlue);

    colors[ImGuiCol_Button]             = v4(kBgInput);
    colors[ImGuiCol_ButtonHovered]      = v4(kBgHover);
    colors[ImGuiCol_ButtonActive]       = v4(kAccentBlue);

    colors[ImGuiCol_Header]             = v4(kBgInput);
    colors[ImGuiCol_HeaderHovered]      = v4(kBgHover);
    colors[ImGuiCol_HeaderActive]       = v4(kAccentBlue);

    colors[ImGuiCol_Separator]          = v4(kBorder);
    colors[ImGuiCol_SeparatorHovered]   = v4(kAccentBlue);
    colors[ImGuiCol_SeparatorActive]    = v4(kAccentBlue);

    colors[ImGuiCol_ResizeGrip]         = ImVec4(0, 0, 0, 0);
    colors[ImGuiCol_ResizeGripHovered]  = v4(kAccentBlue);
    colors[ImGuiCol_ResizeGripActive]   = v4(kAccentBlue);

    colors[ImGuiCol_Tab]                = v4(kBgSecondary);
    colors[ImGuiCol_TabHovered]         = v4(kBgHover);

    colors[ImGuiCol_Text]               = v4(kTextPrimary);
    colors[ImGuiCol_TextDisabled]       = v4(kTextMuted);

    colors[ImGuiCol_NavHighlight]       = v4(kAccentBlue);

    // Scale spacing/padding with font size
    float scale = fontSize / 28.0f;

    style.WindowRounding    = 0.0f;
    style.ChildRounding     = 12.0f * scale;
    style.FrameRounding     = 6.0f * scale;
    style.GrabRounding      = 4.0f * scale;
    style.PopupRounding     = 8.0f * scale;
    style.ScrollbarRounding = 4.0f * scale;
    style.TabRounding       = 4.0f * scale;

    style.WindowBorderSize  = 0.0f;
    style.ChildBorderSize   = 1.0f;
    style.FrameBorderSize   = 0.0f;
    style.FramePadding      = ImVec2(10.0f * scale, 8.0f * scale);
    style.ItemSpacing       = ImVec2(10.0f * scale, 8.0f * scale);
    style.ItemInnerSpacing  = ImVec2(8.0f * scale, 6.0f * scale);
    style.ScrollbarSize     = 10.0f * scale;
    style.GrabMinSize       = 10.0f * scale;
}

ImFont* getDefaultFont() { return sDefaultFont; }
ImFont* getMonoFont()    { return sMonoFont; }
ImFont* getBoldFont()    { return sBoldFont; }
ImFont* getStatsFont()   { return sStatsFont; }

} // namespace theme
