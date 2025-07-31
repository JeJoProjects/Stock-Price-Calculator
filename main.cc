#include <windows.h>
#include <string>
#include <sstream>
#include <iomanip>
#include <cmath>
#include <array>
#include <algorithm>
#include <ranges>
#include <utility>

enum class ControlId : short 
{
   none = 0,
   totalInvestment = 1,
   sharePrice = 2,
   totalShares = 3,
   targetPrice = 4,
   profitInvest = 5,
   profit = 6,
   resetButton = 7
};

inline constexpr std::array excluded_fields
{
    ControlId::none, ControlId::profit,
    ControlId::profitInvest, ControlId::targetPrice
};

class ProfitCalculator
{
private:
   HWND hwnd;
   HWND totalInvestmentEdit, sharePriceEdit, totalSharesEdit;
   HWND targetPriceEdit, profitInvestEdit, profitEdit;
   HWND resetButton;
   bool updating = false;
   ControlId lastChangedField = ControlId::none;
   ControlId secondLastChangedField = ControlId::none;

public:
   ProfitCalculator(HWND mainWindow) : hwnd(mainWindow) {}

   void CreateControls()
   {
      CreateWindow(L"STATIC", L"Total Investment Amount:", WS_VISIBLE | WS_CHILD,
         20, 20, 200, 20, hwnd, nullptr, nullptr, nullptr);
      totalInvestmentEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
         250, 18, 150, 25, hwnd, (HMENU)static_cast<int>(ControlId::totalInvestment), nullptr, nullptr);

      CreateWindow(L"STATIC", L"Single Share Price:", WS_VISIBLE | WS_CHILD,
         20, 60, 200, 20, hwnd, nullptr, nullptr, nullptr);
      sharePriceEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
         250, 58, 150, 25, hwnd, (HMENU)static_cast<int>(ControlId::sharePrice), nullptr, nullptr);

      CreateWindow(L"STATIC", L"Total Number of Shares:", WS_VISIBLE | WS_CHILD,
         20, 100, 200, 20, hwnd, nullptr, nullptr, nullptr);
      totalSharesEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
         250, 98, 150, 25, hwnd, (HMENU)static_cast<int>(ControlId::totalShares), nullptr, nullptr);

      CreateWindow(L"STATIC", L"When share price reaches at:", WS_VISIBLE | WS_CHILD,
         20, 140, 200, 20, hwnd, nullptr, nullptr, nullptr);
      targetPriceEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
         250, 138, 150, 25, hwnd, (HMENU)static_cast<int>(ControlId::targetPrice), nullptr, nullptr);

      CreateWindow(L"STATIC", L"Profit + Invest:", WS_VISIBLE | WS_CHILD,
         20, 180, 200, 20, hwnd, nullptr, nullptr, nullptr);
      profitInvestEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
         250, 178, 150, 25, hwnd, (HMENU)static_cast<int>(ControlId::profitInvest), nullptr, nullptr);

      CreateWindow(L"STATIC", L"Profit:", WS_VISIBLE | WS_CHILD,
         20, 220, 200, 20, hwnd, nullptr, nullptr, nullptr);
      profitEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
         250, 218, 150, 25, hwnd, (HMENU)static_cast<int>(ControlId::profit), nullptr, nullptr);

      resetButton = CreateWindow(L"BUTTON", L"Reset", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
         350, 260, 60, 30, hwnd, (HMENU)static_cast<int>(ControlId::resetButton), nullptr, nullptr);
   }

   double GetEditValue(HWND edit) {
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
         // Total investment changed, update total shares if share price exists
         if (secondLastChangedField == ControlId::totalShares && totalShares > 0.0)
         {
            // If total investment was changed before, preserve it and calculate share price
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
         // Share price changed, update total shares if total investment exists
         if (totalInvestment > 0) {
            totalShares = totalInvestment / sharePrice;
            SetEditValue(totalSharesEdit, totalShares);
         }
      }
      else if (lastChangedField == ControlId::totalShares)
      {
         // Total shares changed - use secondLastChangedField to decide calculation priority
         if (secondLastChangedField == ControlId::totalInvestment && totalInvestment > 0.0) 
         {
            // If total investment was changed before, preserve it and calculate share price
            sharePrice = totalInvestment / totalShares;
            SetEditValue(sharePriceEdit, sharePrice);
         }
         else if (sharePrice > 0) 
         {
            // Default: calculate total investment
            totalInvestment = sharePrice * totalShares;
            SetEditValue(totalInvestmentEdit, totalInvestment);
         }
      }
      else
      {
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
      sharePrice = GetEditValue(sharePriceEdit);
      totalShares = GetEditValue(totalSharesEdit);

      // Calculate profit if target price is provided
      if (targetPrice > 0.0 && totalShares > 0.0) {
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
      lastChangedField = ControlId::none;
      secondLastChangedField = ControlId::none;
      SetWindowText(totalInvestmentEdit, L"");
      SetWindowText(sharePriceEdit, L"");
      SetWindowText(totalSharesEdit, L"");
      SetWindowText(targetPriceEdit, L"");
      SetWindowText(profitInvestEdit, L"");
      SetWindowText(profitEdit, L"");
      updating = false;
   }

   void HandleCommand(WPARAM wParam)
   {
      if (HIWORD(wParam) == EN_CHANGE) 
      {
         ControlId newChangedField = static_cast<ControlId>(LOWORD(wParam));

         constexpr auto is_valid_field = [](ControlId field) constexpr {
            return !std::ranges::contains(excluded_fields, field);
         };
         // Update field change history
		 if (newChangedField != lastChangedField
             || newChangedField != secondLastChangedField
             && is_valid_field(newChangedField)
             && is_valid_field(lastChangedField)
            )
         {
             secondLastChangedField = std::exchange(lastChangedField, newChangedField);
         }

         Calculate();
      }
      else if (HIWORD(wParam) == BN_CLICKED && LOWORD(wParam) == static_cast<int>(ControlId::resetButton))
      {
         Reset();
      }
   }
};

LRESULT CALLBACK WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) 
{
   static ProfitCalculator* calculator = nullptr;

   switch (uMsg) 
   {
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
   while (GetMessage(&msg, nullptr, 0, 0))
   {
      TranslateMessage(&msg);
      DispatchMessage(&msg);
   }

   return 0;
}