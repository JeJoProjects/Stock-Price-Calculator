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

enum class ControlId : short
{
    none = 0,
    totalInvestment = 1,
    sharePrice = 2,
    totalShares = 3,
    targetPrice = 4,
    profitInvest = 5,
    profit = 6,
    percent = 7,
    resetButton = 8,
    newBuyButton = 100,
    combinedAvgSharePrice = 200,
    combinedTotalInvestment = 201,
    combinedTotalShares = 202,
    combinedAvgProfit = 203,
    combinedTotalProfit = 204,
    combinedResetButton = 205
};

inline constexpr std::array excluded_fields
{
    ControlId::none, ControlId::profit,
    ControlId::profitInvest, ControlId::targetPrice
};


template <typename T>
inline constexpr HMENU toHMENU(T id) noexcept
{
    return (HMENU)(INT_PTR)(static_cast<int>(id));
}

class ProfitCalculator
{
private:
    HWND hwnd;
    HWND totalInvestmentEdit, sharePriceEdit, totalSharesEdit;
    HWND targetPriceEdit, profitInvestEdit, profitEdit, percentEdit;
    HWND resetButton;
    bool updating = false;
    ControlId lastChangedField = ControlId::none;
    ControlId secondLastChangedField = ControlId::none;
    int baseId;
    int xOffset;

public:
    ProfitCalculator(HWND mainWindow, int calcIndex, int x = 0)
        : hwnd(mainWindow), baseId(calcIndex * 100 + 1000), xOffset(x) {
    }

    void CreateControls()
    {
        // Title
        CreateWindow(L"STATIC", (L"Purchase #" + std::to_wstring((baseId - 1000) / 100 + 1)).c_str(),
            WS_VISIBLE | WS_CHILD, xOffset + 20, 5, 200, 20, hwnd, nullptr, nullptr, nullptr);

        CreateWindow(L"STATIC", L"Total Investment Amount:", WS_VISIBLE | WS_CHILD,
            xOffset + 20, 30, 200, 20, hwnd, nullptr, nullptr, nullptr);
        totalInvestmentEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
            xOffset + 250, 28, 150, 25, hwnd, toHMENU(baseId + 1), nullptr, nullptr);

        CreateWindow(L"STATIC", L"Single Share Price:", WS_VISIBLE | WS_CHILD,
            xOffset + 20, 70, 200, 20, hwnd, nullptr, nullptr, nullptr);
        sharePriceEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
            xOffset + 250, 68, 150, 25, hwnd, toHMENU(baseId + 2), nullptr, nullptr);

        CreateWindow(L"STATIC", L"Total Number of Shares:", WS_VISIBLE | WS_CHILD,
            xOffset + 20, 110, 200, 20, hwnd, nullptr, nullptr, nullptr);
        totalSharesEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
            xOffset + 250, 108, 150, 25, hwnd, toHMENU(baseId + 3), nullptr, nullptr);

        CreateWindow(L"STATIC", L"When share price reaches at:", WS_VISIBLE | WS_CHILD,
            xOffset + 20, 150, 200, 20, hwnd, nullptr, nullptr, nullptr);
        targetPriceEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
            xOffset + 250, 148, 150, 25, hwnd, toHMENU(baseId + 4), nullptr, nullptr);

        CreateWindow(L"STATIC", L"Profit + Invest:", WS_VISIBLE | WS_CHILD,
            xOffset + 20, 190, 200, 20, hwnd, nullptr, nullptr, nullptr);
        profitInvestEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
            xOffset + 250, 188, 150, 25, hwnd, toHMENU(baseId + 5), nullptr, nullptr);

        CreateWindow(L"STATIC", L"Profit:", WS_VISIBLE | WS_CHILD,
            xOffset + 20, 230, 200, 20, hwnd, nullptr, nullptr, nullptr);
        profitEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
            xOffset + 250, 228, 150, 25, hwnd, toHMENU(baseId + 6), nullptr, nullptr);

        CreateWindow(L"STATIC", L"%:", WS_VISIBLE | WS_CHILD,
            xOffset + 420, 230, 30, 20, hwnd, nullptr, nullptr, nullptr);
        percentEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
            xOffset + 450, 228, 100, 25, hwnd, toHMENU(baseId + 7), nullptr, nullptr);

        resetButton = CreateWindow(L"BUTTON", L"Reset", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
            xOffset + 350, 270, 60, 30, hwnd, toHMENU(baseId + 8), nullptr, nullptr);
    }

    double GetEditValue(HWND edit) const {
        std::wstring text(256, L'\0');
        int length = GetWindowText(edit, text.data(), 256);
        text.resize(length);

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

    void Calculate()
    {
        if (updating) return;
        updating = true;

        double totalInvestment = GetEditValue(totalInvestmentEdit);
        double sharePrice = GetEditValue(sharePriceEdit);
        double totalShares = GetEditValue(totalSharesEdit);
        double targetPrice = GetEditValue(targetPriceEdit);

        // Calculate based on which field was last changed
        if (lastChangedField == ControlId::totalInvestment)
        {
            if (secondLastChangedField == ControlId::totalShares && totalShares > 0.0)
            {
                totalInvestment = sharePrice * totalShares;
                SetEditValue(totalInvestmentEdit, totalInvestment);
            }
            else if (sharePrice > 0)
            {
                totalShares = totalInvestment / sharePrice;
                SetEditValue(totalSharesEdit, totalShares);
            }
        }
        else if (lastChangedField == ControlId::sharePrice)
        {
            if (totalInvestment > 0) {
                totalShares = totalInvestment / sharePrice;
                SetEditValue(totalSharesEdit, totalShares);
            }
        }
        else if (lastChangedField == ControlId::totalShares)
        {
            if (secondLastChangedField == ControlId::totalInvestment && totalInvestment > 0.0)
            {
                sharePrice = totalInvestment / totalShares;
                SetEditValue(sharePriceEdit, sharePrice);
            }
            else if (sharePrice > 0)
            {
                totalInvestment = sharePrice * totalShares;
                SetEditValue(totalInvestmentEdit, totalInvestment);
            }
        }
        else
        {
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
        sharePrice = GetEditValue(sharePriceEdit);
        totalShares = GetEditValue(totalSharesEdit);

        // Calculate profit if target price is provided
        if (0.0 < targetPrice)
        {
            if (0.0 < totalShares)
            {
                const double profitPlusInvest = targetPrice * totalShares;
                SetEditValue(profitInvestEdit, profitPlusInvest);
                SetEditValue(profitEdit, (profitPlusInvest - totalInvestment));
            }
            if (0.0 < sharePrice) SetEditValue(percentEdit, (((targetPrice - sharePrice) * 100.0) / sharePrice));
        }
        else
        {
            SetEditValue(profitInvestEdit, 0);
            SetEditValue(profitEdit, 0);
        }

        updating = false;
    }

    void Reset()
    {
        updating = true;
        lastChangedField = ControlId::none;
        secondLastChangedField = ControlId::none;
        SetWindowText(totalInvestmentEdit, L"");
        SetWindowText(sharePriceEdit, L"");
        SetWindowText(totalSharesEdit, L"");
        SetWindowText(targetPriceEdit, L"");
        SetWindowText(profitInvestEdit, L"");
        SetWindowText(profitEdit, L"");
        SetWindowText(percentEdit, L"");
        updating = false;
    }

    bool HandleCommand(WPARAM wParam)
    {
        int cmdId = LOWORD(wParam);

        if (HIWORD(wParam) == EN_CHANGE && cmdId >= baseId && cmdId < baseId + 100)
        {
            ControlId newChangedField = static_cast<ControlId>(cmdId - baseId);

            constexpr auto is_valid_field = [](ControlId field) constexpr {
                return !std::ranges::contains(excluded_fields, field);
                };

            if (newChangedField != lastChangedField
                || newChangedField != secondLastChangedField
                && is_valid_field(newChangedField)
                && is_valid_field(lastChangedField)
                )
            {
                secondLastChangedField = std::exchange(lastChangedField, newChangedField);
            }

            Calculate();
            return true;
        }
        else if (HIWORD(wParam) == BN_CLICKED && cmdId == baseId + 8)
        {
            Reset();
            return true;
        }

        return false;
    }

    // Getters for combined calculations
    double GetTotalInvestment() const { return GetEditValue(totalInvestmentEdit); }
    double GetSharePrice() const { return GetEditValue(sharePriceEdit); }
    double GetTotalShares() const { return GetEditValue(totalSharesEdit); }
    double GetProfit() const { return GetEditValue(profitEdit); }
    bool HasValidData() const {
        return GetTotalInvestment() > 0 && GetSharePrice() > 0 && GetTotalShares() > 0;
    }
};

class MultiCalculatorManager
{
private:
    HWND hwnd{ nullptr };
    std::vector<std::unique_ptr<ProfitCalculator>> calculators{};
    HWND newBuyButton{ nullptr };
    HWND combinedAvgSharePriceEdit{ nullptr }, combinedTotalInvestmentEdit{ nullptr }, combinedTotalSharesEdit{ nullptr };
    HWND combinedAvgProfitEdit{ nullptr }, combinedTotalProfitEdit{ nullptr }, combinedResetButton{ nullptr };
    int currentWidth{ 600 };
    bool updating{ false };

   
public:
    MultiCalculatorManager(HWND mainWindow) : hwnd(mainWindow)
    {
        // Create first calculator
        calculators.push_back(std::make_unique<ProfitCalculator>(hwnd, 0, 0));
        calculators[0]->CreateControls();
    }

    void CreateControls()
    {
        // New Buy button
        newBuyButton = CreateWindow(L"BUTTON", L"New Buy", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
            420, 5, 80, 30, hwnd, toHMENU(ControlId::newBuyButton), nullptr, nullptr);

        CreateCombinedSection();
    }

    void CreateCombinedSection()
    {
        int yOffset = 320;

        // Combined section title
        CreateWindow(L"STATIC", L"Combined Average Calculations:", WS_VISIBLE | WS_CHILD,
            20, yOffset, 300, 20, hwnd, nullptr, nullptr, nullptr);

        // Average share price
        CreateWindow(L"STATIC", L"Avg Share Price:", WS_VISIBLE | WS_CHILD,
            20, yOffset + 30, 150, 20, hwnd, nullptr, nullptr, nullptr);
        combinedAvgSharePriceEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
            180, yOffset + 28, 150, 25, hwnd, toHMENU(ControlId::combinedAvgSharePrice), nullptr, nullptr);

        // Total investment
        CreateWindow(L"STATIC", L"Total Investment:", WS_VISIBLE | WS_CHILD,
            350, yOffset + 30, 150, 20, hwnd, nullptr, nullptr, nullptr);
        combinedTotalInvestmentEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
            510, yOffset + 28, 150, 25, hwnd, toHMENU(ControlId::combinedTotalInvestment), nullptr, nullptr);

        // Total shares
        CreateWindow(L"STATIC", L"Total Shares:", WS_VISIBLE | WS_CHILD,
            20, yOffset + 70, 150, 20, hwnd, nullptr, nullptr, nullptr);
        combinedTotalSharesEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
            180, yOffset + 68, 150, 25, hwnd, toHMENU(ControlId::combinedTotalShares), nullptr, nullptr);

        // Average profit
        CreateWindow(L"STATIC", L"Avg Profit:", WS_VISIBLE | WS_CHILD,
            350, yOffset + 70, 150, 20, hwnd, nullptr, nullptr, nullptr);
        combinedAvgProfitEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
            510, yOffset + 68, 150, 25, hwnd, toHMENU(ControlId::combinedAvgProfit), nullptr, nullptr);

        // Total profit
        CreateWindow(L"STATIC", L"Total Profit:", WS_VISIBLE | WS_CHILD,
            20, yOffset + 110, 150, 20, hwnd, nullptr, nullptr, nullptr);
        combinedTotalProfitEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
            180, yOffset + 108, 150, 25, hwnd, toHMENU(ControlId::combinedTotalProfit), nullptr, nullptr);

        // Combined reset button
        combinedResetButton = CreateWindow(L"BUTTON", L"Reset All", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
            350, yOffset + 150, 80, 30, hwnd, toHMENU(ControlId::combinedResetButton), nullptr, nullptr);
    }

    void SetEditValue(HWND edit, double value) {
        static bool updating = false;
        if (updating) return;

        updating = true;
        if (value == 0.0) {
            SetWindowText(edit, L"");
        }
        else {
            std::wostringstream oss;
            oss << std::fixed << std::setprecision(3) << value;
            SetWindowText(edit, oss.str().c_str());
        }
        updating = false;
    }

    void CalculateCombined()
    {
        if (updating) return;

        double totalInvestment = 0.0;
        double totalShares = 0.0;
        double totalProfit = 0.0;
        double weightedSharePrice = 0.0;
        int validCalculators = 0;

        for (const auto& calc : calculators) {
            if (calc->HasValidData()) {
                double investment = calc->GetTotalInvestment();
                double shares = calc->GetTotalShares();
                double sharePrice = calc->GetSharePrice();
                double profit = calc->GetProfit();

                totalInvestment += investment;
                totalShares += shares;
                totalProfit += profit;
                weightedSharePrice += sharePrice * shares;
                validCalculators++;
            }
        }

        if (validCalculators > 0) {
            double avgSharePrice = totalShares > 0 ? weightedSharePrice / totalShares : 0.0;
            double avgProfit = totalProfit / validCalculators;

            SetEditValue(combinedAvgSharePriceEdit, avgSharePrice);
            SetEditValue(combinedTotalInvestmentEdit, totalInvestment);
            SetEditValue(combinedTotalSharesEdit, totalShares);
            SetEditValue(combinedAvgProfitEdit, avgProfit);
            SetEditValue(combinedTotalProfitEdit, totalProfit);
        }
        else {
            SetEditValue(combinedAvgSharePriceEdit, 0);
            SetEditValue(combinedTotalInvestmentEdit, 0);
            SetEditValue(combinedTotalSharesEdit, 0);
            SetEditValue(combinedAvgProfitEdit, 0);
            SetEditValue(combinedTotalProfitEdit, 0);
        }
    }

    void AddNewCalculator()
    {
        int calcIndex = static_cast<int>(calculators.size());
        int xOffset = calcIndex * 580; // Space calculators 580px apart

        calculators.push_back(std::make_unique<ProfitCalculator>(hwnd, calcIndex, xOffset));
        calculators.back()->CreateControls();

        // Expand window width
        currentWidth = xOffset + 600;
        SetWindowPos(hwnd, nullptr, 0, 0, currentWidth, 550, SWP_NOMOVE | SWP_NOZORDER);

        // Move the New Buy button
        SetWindowPos(newBuyButton, nullptr, xOffset + 420, 5, 0, 0, SWP_NOSIZE | SWP_NOZORDER);
    }

    void ResetAll()
    {
        updating = true;
        for (auto& calc : calculators) {
            calc->Reset();
        }
        CalculateCombined();
        updating = false;
    }

    void HandleCommand(WPARAM wParam)
    {
        bool handled = false;

        // Try each calculator
        for (auto& calc : calculators) {
            if (calc->HandleCommand(wParam)) {
                handled = true;
                break;
            }
        }

        if (handled) {
            CalculateCombined();
            return;
        }

        // Handle manager-specific commands
        if (HIWORD(wParam) == BN_CLICKED) {
            int cmdId = LOWORD(wParam);

            if (cmdId == static_cast<int>(ControlId::newBuyButton)) {
                AddNewCalculator();
            }
            else if (cmdId == static_cast<int>(ControlId::combinedResetButton)) {
                ResetAll();
            }
        }
    }
};

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