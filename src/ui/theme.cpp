#include "ui/theme.hpp"
#include "ui/imguiHelpers.hpp"

static ImFont* sDefaultFont = nullptr;
static ImFont* sMonoFont = nullptr;
static ImFont* sBoldFont = nullptr;

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

    io.Fonts->Build();
}

void applyTradingViewTheme(float /*fontSize*/) {
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

    style.WindowRounding    = 0.0f;
    style.ChildRounding     = 12.0f;
    style.FrameRounding     = 6.0f;
    style.GrabRounding      = 4.0f;
    style.PopupRounding     = 8.0f;
    style.ScrollbarRounding = 4.0f;
    style.TabRounding       = 4.0f;

    style.WindowBorderSize  = 0.0f;
    style.ChildBorderSize   = 1.0f;
    style.FrameBorderSize   = 0.0f;
    style.FramePadding      = ImVec2(8.0f, 6.0f);
    style.ItemSpacing       = ImVec2(8.0f, 6.0f);
    style.ItemInnerSpacing  = ImVec2(6.0f, 4.0f);
    style.ScrollbarSize     = 8.0f;
    style.GrabMinSize       = 8.0f;
}

ImFont* getDefaultFont() { return sDefaultFont; }
ImFont* getMonoFont()    { return sMonoFont; }
ImFont* getBoldFont()    { return sBoldFont; }

} // namespace theme
