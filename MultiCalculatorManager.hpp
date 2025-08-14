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

class MultiCalculatorManager
{
private:
   HWND mHwnd{ nullptr };
   std::vector<std::unique_ptr<ProfitCalculator>> mCalculators{};
   HWND mNewBuyButton{ nullptr };
   HWND mCombinedAvgSharePriceEdit{ nullptr }, mCombinedTotalInvestmentEdit{ nullptr }, mCombinedTotalSharesEdit{ nullptr };
   HWND mCombinedAvgProfitEdit{ nullptr }, mCombinedTotalProfitEdit{ nullptr }, mCombinedResetButton{ nullptr };
   int currentWidth{ 600 };
   bool updating{ false };


public:
   explicit MultiCalculatorManager(HWND mainWindow)
      : mHwnd{ mainWindow }
   {
      // Create first calculator
      mCalculators.emplace_back(std::make_unique<ProfitCalculator>(mHwnd, 0, 0));
      mCalculators[0]->CreateControls();
   }

   void CreateControls()
   {
      // New Buy button
      mNewBuyButton = CreateWindow(L"BUTTON", L"New Buy", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
         420, 5, 80, 30, mHwnd, toHMENU(ControlId::newBuyButton), nullptr, nullptr);

      CreateCombinedSection();
   }

   void CreateCombinedSection()
   {
      int yOffset = 320;

      // Combined section title
      CreateWindow(L"STATIC", L"Combined Average Calculations:", WS_VISIBLE | WS_CHILD,
         20, yOffset, 300, 20, mHwnd, nullptr, nullptr, nullptr);

      // Average share price
      CreateWindow(L"STATIC", L"Avg Share Price:", WS_VISIBLE | WS_CHILD,
         20, yOffset + 30, 150, 20, mHwnd, nullptr, nullptr, nullptr);
      mCombinedAvgSharePriceEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
         180, yOffset + 28, 150, 25, mHwnd, toHMENU(ControlId::combinedAvgSharePrice), nullptr, nullptr);

      // Total investment
      CreateWindow(L"STATIC", L"Total Investment:", WS_VISIBLE | WS_CHILD,
         350, yOffset + 30, 150, 20, mHwnd, nullptr, nullptr, nullptr);
      mCombinedTotalInvestmentEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
         510, yOffset + 28, 150, 25, mHwnd, toHMENU(ControlId::combinedTotalInvestment), nullptr, nullptr);

      // Total shares
      CreateWindow(L"STATIC", L"Total Shares:", WS_VISIBLE | WS_CHILD,
         20, yOffset + 70, 150, 20, mHwnd, nullptr, nullptr, nullptr);
      mCombinedTotalSharesEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
         180, yOffset + 68, 150, 25, mHwnd, toHMENU(ControlId::combinedTotalShares), nullptr, nullptr);

      // Average profit
      CreateWindow(L"STATIC", L"Avg Profit:", WS_VISIBLE | WS_CHILD,
         350, yOffset + 70, 150, 20, mHwnd, nullptr, nullptr, nullptr);
      mCombinedAvgProfitEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
         510, yOffset + 68, 150, 25, mHwnd, toHMENU(ControlId::combinedAvgProfit), nullptr, nullptr);

      // Total profit
      CreateWindow(L"STATIC", L"Total Profit:", WS_VISIBLE | WS_CHILD,
         20, yOffset + 110, 150, 20, mHwnd, nullptr, nullptr, nullptr);
      mCombinedTotalProfitEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
         180, yOffset + 108, 150, 25, mHwnd, toHMENU(ControlId::combinedTotalProfit), nullptr, nullptr);

      // Combined reset button
      mCombinedResetButton = CreateWindow(L"BUTTON", L"Reset All", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
         350, yOffset + 150, 80, 30, mHwnd, toHMENU(ControlId::combinedResetButton), nullptr, nullptr);
   }

   void SetEditValue(HWND edit, double value)
   {
      static bool updating = false;
      if (updating) return;

      updating = true;
      if (value == 0.0)
      {
         SetWindowText(edit, L"");
      }
      else
      {
         SetWindowText(edit, toStdString(value).c_str());
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
      std::size_t validCalculators = 0u;

      for (const auto& calc : mCalculators)
      {
         if (calc->HasValidData())
         {
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

      if (validCalculators > 0u)
      {
         double avgSharePrice = totalShares > 0.0 ? weightedSharePrice / totalShares : 0.0;
         double avgProfit = totalProfit / validCalculators;

         SetEditValue(mCombinedAvgSharePriceEdit, avgSharePrice);
         SetEditValue(mCombinedTotalInvestmentEdit, totalInvestment);
         SetEditValue(mCombinedTotalSharesEdit, totalShares);
         SetEditValue(mCombinedAvgProfitEdit, avgProfit);
         SetEditValue(mCombinedTotalProfitEdit, totalProfit);
      }
      else {
         SetEditValue(mCombinedAvgSharePriceEdit, 0);
         SetEditValue(mCombinedTotalInvestmentEdit, 0);
         SetEditValue(mCombinedTotalSharesEdit, 0);
         SetEditValue(mCombinedAvgProfitEdit, 0);
         SetEditValue(mCombinedTotalProfitEdit, 0);
      }
   }

   void AddNewCalculator()
   {
      int calcIndex = static_cast<int>(mCalculators.size());
      int xOffset = calcIndex * 580; // Space calculators 580px apart

      auto& lastCalulcator = mCalculators.emplace_back(
         std::make_unique<ProfitCalculator>(mHwnd, calcIndex, xOffset));
      lastCalulcator->CreateControls();

      // Expand window width
      currentWidth = xOffset + 600;
      SetWindowPos(mHwnd, nullptr, 0, 0, currentWidth, 550, SWP_NOMOVE | SWP_NOZORDER);

      // Move the New Buy button
      SetWindowPos(mNewBuyButton, nullptr, xOffset + 420, 5, 0, 0, SWP_NOSIZE | SWP_NOZORDER);
   }

   void ResetAll()
   {
      updating = true;
      for (auto& calc : mCalculators)
      {
         calc->Reset();
      }
      CalculateCombined();
      updating = false;
   }

   void HandleCommand(WPARAM wParam)
   {
      // Try each calculator
      const bool handled = std::ranges::any_of(mCalculators, [wParam](const auto& calc) {
            return calc->HandleCommand(wParam);
         }
      );

      if (handled)
      {
         CalculateCombined();
         return;
      }

      // Handle manager-specific commands
      if (HIWORD(wParam) == BN_CLICKED)
      {
         const int cmdId = LOWORD(wParam);

         if (cmdId == static_cast<int>(ControlId::newBuyButton))
         {
            AddNewCalculator();
         }
         else if (cmdId == static_cast<int>(ControlId::combinedResetButton))
         {
            ResetAll();
         }
      }
   }
};
