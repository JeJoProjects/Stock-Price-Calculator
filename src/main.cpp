#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_opengl3.h"

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>
#include "imgui_impl_opengl3_loader.h"
#include <cstdio>

#ifdef _WIN32
#include <windows.h>
#endif

#include "app/application.hpp"
#include "config/settingsManager.hpp"
#include "ui/theme.hpp"

static void glfwErrorCallback(int error, const char* description) {
    std::fprintf(stderr, "GLFW Error %d: %s\n", error, description);
}

#ifdef _WIN32
int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int) {
#else
int main() {
#endif
    auto settings = config::loadSettings();

    glfwSetErrorCallback(glfwErrorCallback);
    if (!glfwInit()) return 1;

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    GLFWwindow* window = glfwCreateWindow(
        settings.windowWidth, settings.windowHeight,
        "Stock Price Calculator", nullptr, nullptr);
    if (!window) {
        glfwTerminate();
        return 1;
    }

    if (settings.windowX >= 0 && settings.windowY >= 0) {
        glfwSetWindowPos(window, settings.windowX, settings.windowY);
    }

    glfwMakeContextCurrent(window);
    glfwSwapInterval(1);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.IniFilename = nullptr;

    ImGui_ImplGlfw_InitForOpenGL(window, true);
    ImGui_ImplOpenGL3_Init("#version 330");

    theme::loadFonts(settings.fontSize);
    theme::applyTradingViewTheme(settings.fontSize);

    Application app(window, settings);

    while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();

        if (glfwGetWindowAttrib(window, GLFW_ICONIFIED)) {
            glfwWaitEvents();
            continue;
        }

        // Rebuild fonts between frames (before NewFrame) to avoid atlas crash
        if (app.needsFontRebuild()) {
            theme::loadFonts(app.fontSize());
            theme::applyTradingViewTheme(app.fontSize());
            app.clearFontRebuild();
        }

        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();

        app.update();

        ImGui::Render();
        int displayW, displayH;
        glfwGetFramebufferSize(window, &displayW, &displayH);
        glViewport(0, 0, displayW, displayH);
        glClearColor(0.075f, 0.09f, 0.133f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

        glfwSwapBuffers(window);
    }

    int winX, winY, winW, winH;
    glfwGetWindowPos(window, &winX, &winY);
    glfwGetWindowSize(window, &winW, &winH);
    app.saveSettings(winW, winH, winX, winY);

    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    glfwDestroyWindow(window);
    glfwTerminate();
    return 0;
}
