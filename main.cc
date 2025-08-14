#include <windows.h>
#include <string>
#include <sstream>
#include <iomanip>
#include <cmath>
#include <array>
#include <algorithm>
#include <ranges>
#include <utility>
#include <vector>
#include <memory>

#include "Util.hpp"
#include "ProfitCalculator.hpp"
#include "MultiCalculatorManager.hpp"

LRESULT CALLBACK WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
{
    static MultiCalculatorManager* manager = nullptr;

    switch (uMsg)
    {
    case WM_CREATE:
        manager = new MultiCalculatorManager(hwnd);
        manager->CreateControls();
        return 0;

    case WM_COMMAND:
        if (manager) {
            manager->HandleCommand(wParam);
        }
        return 0;

    case WM_DESTROY:
        delete manager;
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProc(hwnd, uMsg, wParam, lParam);
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE, LPSTR, int nCmdShow)
{
    const wchar_t CLASS_NAME[] = L"ProfitCalculatorWindow";

    WNDCLASS wc = {};
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = CLASS_NAME;
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);

    RegisterClass(&wc);

    HWND hwnd = CreateWindowEx(
        0,
        CLASS_NAME,
        L"Share Profit Calculator",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 600, 550,
        nullptr, nullptr, hInstance, nullptr
    );

    if (!hwnd) return 0;

    ShowWindow(hwnd, nCmdShow);

    MSG msg = {};
    while (GetMessage(&msg, nullptr, 0, 0))
    {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    return 0;
}