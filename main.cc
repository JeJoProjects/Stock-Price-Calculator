#include <windows.h>
#include <string>
#include <sstream>
#include <iomanip>
#include <cmath>

#define ID_TOTAL_INVESTMENT 1001
#define ID_SHARE_PRICE 1002
#define ID_TOTAL_SHARES 1003
#define ID_TARGET_PRICE 1004
#define ID_PROFIT_INVEST 1005
#define ID_PROFIT 1006
#define ID_RESET_BUTTON 1007

class ProfitCalculator 
{
private:
    HWND hwnd;
    HWND totalInvestmentEdit, sharePriceEdit, totalSharesEdit;
    HWND targetPriceEdit, profitInvestEdit, profitEdit;
    HWND resetButton;
    bool updating = false;
    int lastChangedField = 0; // Track which field was last changed

public:
    ProfitCalculator(HWND mainWindow) : hwnd(mainWindow) {}

    void CreateControls() {
        CreateWindow(L"STATIC", L"Total Investment Amount:", WS_VISIBLE | WS_CHILD,
            20, 20, 200, 20, hwnd, nullptr, nullptr, nullptr);
        totalInvestmentEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
            250, 18, 150, 25, hwnd, (HMENU)ID_TOTAL_INVESTMENT, nullptr, nullptr);

        CreateWindow(L"STATIC", L"Single Share Price:", WS_VISIBLE | WS_CHILD,
            20, 60, 200, 20, hwnd, nullptr, nullptr, nullptr);
        sharePriceEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
            250, 58, 150, 25, hwnd, (HMENU)ID_SHARE_PRICE, nullptr, nullptr);

        CreateWindow(L"STATIC", L"Total Number of Shares:", WS_VISIBLE | WS_CHILD,
            20, 100, 200, 20, hwnd, nullptr, nullptr, nullptr);
        totalSharesEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
            250, 98, 150, 25, hwnd, (HMENU)ID_TOTAL_SHARES, nullptr, nullptr);

        CreateWindow(L"STATIC", L"When share price reaches at:", WS_VISIBLE | WS_CHILD,
            20, 140, 200, 20, hwnd, nullptr, nullptr, nullptr);
        targetPriceEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
            250, 138, 150, 25, hwnd, (HMENU)ID_TARGET_PRICE, nullptr, nullptr);

        CreateWindow(L"STATIC", L"Profit + Invest:", WS_VISIBLE | WS_CHILD,
            20, 180, 200, 20, hwnd, nullptr, nullptr, nullptr);
        profitInvestEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
            250, 178, 150, 25, hwnd, (HMENU)ID_PROFIT_INVEST, nullptr, nullptr);

        CreateWindow(L"STATIC", L"Profit:", WS_VISIBLE | WS_CHILD,
            20, 220, 200, 20, hwnd, nullptr, nullptr, nullptr);
        profitEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
            250, 218, 150, 25, hwnd, (HMENU)ID_PROFIT, nullptr, nullptr);

        resetButton = CreateWindow(L"BUTTON", L"Reset", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
            350, 260, 60, 30, hwnd, (HMENU)ID_RESET_BUTTON, nullptr, nullptr);
    }

    double GetEditValue(HWND edit) {
        wchar_t buffer[256];
        GetWindowText(edit, buffer, 256);
        std::wstring text(buffer);
        if (text.empty()) return 0.0;
        try {
            return std::stod(text);
        }
        catch (...) {
            return 0.0;
        }
    }

    void SetEditValue(HWND edit, double value) 
    {
        if (value == 0.0) {
            SetWindowText(edit, L"");
            return;
        }
        std::wostringstream oss;
        oss << std::fixed << std::setprecision(3) << value;
        SetWindowText(edit, oss.str().c_str());
    }

    void Calculate() {
        if (updating) return;
        updating = true;

        double totalInvestment = GetEditValue(totalInvestmentEdit);
        double sharePrice = GetEditValue(sharePriceEdit);
        double totalShares = GetEditValue(totalSharesEdit);
        double targetPrice = GetEditValue(targetPriceEdit);

        // Calculate based on which field was last changed
        if (lastChangedField == ID_TOTAL_INVESTMENT) {
            // Total investment changed, update total shares if share price exists
            if (sharePrice > 0) {
                totalShares = totalInvestment / sharePrice;
                SetEditValue(totalSharesEdit, totalShares);
            }
        }
        else if (lastChangedField == ID_SHARE_PRICE) {
            // Share price changed, update total shares if total investment exists
            if (totalInvestment > 0) {
                totalShares = totalInvestment / sharePrice;
                SetEditValue(totalSharesEdit, totalShares);
            }
        }
        else if (lastChangedField == ID_TOTAL_SHARES) {
            // Total shares changed
            if (totalInvestment > 0) {
                // Calculate share price (preserving total investment)
                sharePrice = totalInvestment / totalShares;
                SetEditValue(sharePriceEdit, sharePrice);
            }
            else if (sharePrice > 0) {
                // Calculate total investment
                totalInvestment = sharePrice * totalShares;
                SetEditValue(totalInvestmentEdit, totalInvestment);
            }
        }
        else {
            // Initial calculation when no specific field was changed
            int nonZeroCount = 0;
            if (totalInvestment > 0) nonZeroCount++;
            if (sharePrice > 0) nonZeroCount++;
            if (totalShares > 0) nonZeroCount++;

            if (nonZeroCount == 2) {
                if (totalInvestment <= 0 && sharePrice > 0 && totalShares > 0) {
                    totalInvestment = sharePrice * totalShares;
                    SetEditValue(totalInvestmentEdit, totalInvestment);
                }
                else if (sharePrice <= 0 && totalInvestment > 0 && totalShares > 0) {
                    sharePrice = totalInvestment / totalShares;
                    SetEditValue(sharePriceEdit, sharePrice);
                }
                else if (totalShares <= 0 && totalInvestment > 0 && sharePrice > 0) {
                    totalShares = totalInvestment / sharePrice;
                    SetEditValue(totalSharesEdit, totalShares);
                }
            }
        }

        // Refresh values after potential updates
        totalInvestment = GetEditValue(totalInvestmentEdit);
        totalShares = GetEditValue(totalSharesEdit);

        // Calculate profit if target price is provided
        if (targetPrice > 0 && totalShares > 0) {
            double profitPlusInvest = targetPrice * totalShares;
            double profit = profitPlusInvest - totalInvestment;

            SetEditValue(profitInvestEdit, profitPlusInvest);
            SetEditValue(profitEdit, profit);
        }
        else {
            SetEditValue(profitInvestEdit, 0);
            SetEditValue(profitEdit, 0);
        }

        updating = false;
    }

    void Reset() 
    {
        updating = true;
        lastChangedField = 0;
        SetWindowText(totalInvestmentEdit, L"");
        SetWindowText(sharePriceEdit, L"");
        SetWindowText(totalSharesEdit, L"");
        SetWindowText(targetPriceEdit, L"");
        SetWindowText(profitInvestEdit, L"");
        SetWindowText(profitEdit, L"");
        updating = false;
    }

    void HandleCommand(WPARAM wParam) {
        if (HIWORD(wParam) == EN_CHANGE) {
            lastChangedField = LOWORD(wParam); // Track which field changed
            Calculate();
        }
        else if (HIWORD(wParam) == BN_CLICKED && LOWORD(wParam) == ID_RESET_BUTTON) {
            Reset();
        }
    }
};

LRESULT CALLBACK WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    static ProfitCalculator* calculator = nullptr;

    switch (uMsg) {
    case WM_CREATE:
        calculator = new ProfitCalculator(hwnd);
        calculator->CreateControls();
        return 0;

    case WM_COMMAND:
        if (calculator) {
            calculator->HandleCommand(wParam);
        }
        return 0;

    case WM_DESTROY:
        delete calculator;
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
        CW_USEDEFAULT, CW_USEDEFAULT, 450, 320,
        nullptr, nullptr, hInstance, nullptr
    );

    if (!hwnd) return 0;

    ShowWindow(hwnd, nCmdShow);

    MSG msg = {};
    while (GetMessage(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    return 0;
}