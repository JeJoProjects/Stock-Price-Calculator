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

class ProfitCalculator
{
private:
   HWND mHwnd{ nullptr };
   HWND mTotalInvestmentEdit{ nullptr }, mSharePriceEdit{ nullptr }, mTotalSharesEdit{ nullptr };
   HWND mTargetPriceEdit{ nullptr }, mProfitInvestEdit{ nullptr }, mProfitEdit{ nullptr }, mPercentEdit{ nullptr };
   HWND mResetButton{ nullptr };
   bool mUpdating{ false };
   ControlId mLastChangedField{ ControlId::none };
   ControlId mSecondLastChangedField{ ControlId::none };
   int mBaseId{};
   int mXOffset{};

public:
   explicit ProfitCalculator(HWND mainWindow, int calcIndex, int x = 0)
      : mHwnd{ mainWindow }, mBaseId{ calcIndex * 100 + 1000 }, mXOffset{ x }
   {}

   void CreateControls()
   {
      // Title
      CreateWindow(L"STATIC", (L"Purchase #" + std::to_wstring((mBaseId - 1000) / 100 + 1)).c_str(),
         WS_VISIBLE | WS_CHILD, mXOffset + 20, 5, 200, 20, mHwnd, nullptr, nullptr, nullptr);

      CreateWindow(L"STATIC", L"Total Investment Amount:", WS_VISIBLE | WS_CHILD,
         mXOffset + 20, 30, 200, 20, mHwnd, nullptr, nullptr, nullptr);
      mTotalInvestmentEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
         mXOffset + 250, 28, 150, 25, mHwnd, toHMENU(mBaseId + 1), nullptr, nullptr);

      CreateWindow(L"STATIC", L"Single Share Price:", WS_VISIBLE | WS_CHILD,
         mXOffset + 20, 70, 200, 20, mHwnd, nullptr, nullptr, nullptr);
      mSharePriceEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
         mXOffset + 250, 68, 150, 25, mHwnd, toHMENU(mBaseId + 2), nullptr, nullptr);

      CreateWindow(L"STATIC", L"Total Number of Shares:", WS_VISIBLE | WS_CHILD,
         mXOffset + 20, 110, 200, 20, mHwnd, nullptr, nullptr, nullptr);
      mTotalSharesEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
         mXOffset + 250, 108, 150, 25, mHwnd, toHMENU(mBaseId + 3), nullptr, nullptr);

      CreateWindow(L"STATIC", L"When share price reaches at:", WS_VISIBLE | WS_CHILD,
         mXOffset + 20, 150, 200, 20, mHwnd, nullptr, nullptr, nullptr);
      mTargetPriceEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER,
         mXOffset + 250, 148, 150, 25, mHwnd, toHMENU(mBaseId + 4), nullptr, nullptr);

      CreateWindow(L"STATIC", L"Profit + Invest:", WS_VISIBLE | WS_CHILD,
         mXOffset + 20, 190, 200, 20, mHwnd, nullptr, nullptr, nullptr);
      mProfitInvestEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
         mXOffset + 250, 188, 150, 25, mHwnd, toHMENU(mBaseId + 5), nullptr, nullptr);

      CreateWindow(L"STATIC", L"Profit:", WS_VISIBLE | WS_CHILD,
         mXOffset + 20, 230, 200, 20, mHwnd, nullptr, nullptr, nullptr);
      mProfitEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
         mXOffset + 250, 228, 150, 25, mHwnd, toHMENU(mBaseId + 6), nullptr, nullptr);

      CreateWindow(L"STATIC", L"%:", WS_VISIBLE | WS_CHILD,
         mXOffset + 420, 230, 30, 20, mHwnd, nullptr, nullptr, nullptr);
      mPercentEdit = CreateWindow(L"EDIT", L"", WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY,
         mXOffset + 450, 228, 100, 25, mHwnd, toHMENU(mBaseId + 7), nullptr, nullptr);

      mResetButton = CreateWindow(L"BUTTON", L"Reset", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
         mXOffset + 350, 270, 60, 30, mHwnd, toHMENU(mBaseId + 8), nullptr, nullptr);
   }

   double GetEditValue(HWND edit) const
   {
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
      if (value == 0.0)
      {
         SetWindowText(edit, L"");
         return;
      }
      SetWindowText(edit, toStdString(value).c_str());
   }

   void Calculate()
   {
      if (mUpdating) return;
      mUpdating = true;

      double totalInvestment = GetEditValue(mTotalInvestmentEdit);
      double sharePrice = GetEditValue(mSharePriceEdit);
      double totalShares = GetEditValue(mTotalSharesEdit);
      double targetPrice = GetEditValue(mTargetPriceEdit);

      // Calculate based on which field was last changed
      if (mLastChangedField == ControlId::totalInvestment)
      {
         if (mSecondLastChangedField == ControlId::totalShares && totalShares > 0.0)
         {
            totalInvestment = sharePrice * totalShares;
            SetEditValue(mTotalInvestmentEdit, totalInvestment);
         }
         else if (sharePrice > 0)
         {
            totalShares = totalInvestment / sharePrice;
            SetEditValue(mTotalSharesEdit, totalShares);
         }
      }
      else if (mLastChangedField == ControlId::sharePrice)
      {
         if (totalInvestment > 0) {
            totalShares = totalInvestment / sharePrice;
            SetEditValue(mTotalSharesEdit, totalShares);
         }
      }
      else if (mLastChangedField == ControlId::totalShares)
      {
         if (mSecondLastChangedField == ControlId::totalInvestment && totalInvestment > 0.0)
         {
            sharePrice = totalInvestment / totalShares;
            SetEditValue(mSharePriceEdit, sharePrice);
         }
         else if (sharePrice > 0)
         {
            totalInvestment = sharePrice * totalShares;
            SetEditValue(mTotalInvestmentEdit, totalInvestment);
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
               SetEditValue(mTotalInvestmentEdit, totalInvestment);
            }
            else if (sharePrice <= 0 && totalInvestment > 0 && totalShares > 0) {
               sharePrice = totalInvestment / totalShares;
               SetEditValue(mSharePriceEdit, sharePrice);
            }
            else if (totalShares <= 0 && totalInvestment > 0 && sharePrice > 0) {
               totalShares = totalInvestment / sharePrice;
               SetEditValue(mTotalSharesEdit, totalShares);
            }
         }
      }

      // Refresh values after potential updates
      totalInvestment = GetEditValue(mTotalInvestmentEdit);
      sharePrice = GetEditValue(mSharePriceEdit);
      totalShares = GetEditValue(mTotalSharesEdit);

      // Calculate profit if target price is provided
      if (0.0 < targetPrice)
      {
         if (0.0 < totalShares)
         {
            const double profitPlusInvest = targetPrice * totalShares;
            SetEditValue(mProfitInvestEdit, profitPlusInvest);
            SetEditValue(mProfitEdit, (profitPlusInvest - totalInvestment));
         }
         if (0.0 < sharePrice) SetEditValue(mPercentEdit, (((targetPrice - sharePrice) * 100.0) / sharePrice));
      }
      else
      {
         SetEditValue(mProfitInvestEdit, 0);
         SetEditValue(mProfitEdit, 0);
      }

      mUpdating = false;
   }

   void Reset()
   {
      mUpdating = true;
      mLastChangedField = ControlId::none;
      mSecondLastChangedField = ControlId::none;
      SetWindowText(mTotalInvestmentEdit, L"");
      SetWindowText(mSharePriceEdit, L"");
      SetWindowText(mTotalSharesEdit, L"");
      SetWindowText(mTargetPriceEdit, L"");
      SetWindowText(mProfitInvestEdit, L"");
      SetWindowText(mProfitEdit, L"");
      SetWindowText(mPercentEdit, L"");
      mUpdating = false;
   }

   bool HandleCommand(WPARAM wParam)
   {
      int cmdId = LOWORD(wParam);

      if (HIWORD(wParam) == EN_CHANGE && cmdId >= mBaseId && cmdId < mBaseId + 100)
      {
         ControlId newChangedField = static_cast<ControlId>(cmdId - mBaseId);

         constexpr auto is_valid_field = [](ControlId field) constexpr {
            return !std::ranges::contains(excluded_fields, field);
            };

         if (newChangedField != mLastChangedField
            || newChangedField != mSecondLastChangedField
            && is_valid_field(newChangedField)
            && is_valid_field(mLastChangedField)
            )
         {
            mSecondLastChangedField = std::exchange(mLastChangedField, newChangedField);
         }

         Calculate();
         return true;
      }
      else if (HIWORD(wParam) == BN_CLICKED && cmdId == mBaseId + 8)
      {
         Reset();
         return true;
      }

      return false;
   }

   // Getters for combined calculations
   double GetTotalInvestment() const { return GetEditValue(mTotalInvestmentEdit); }
   double GetSharePrice() const { return GetEditValue(mSharePriceEdit); }
   double GetTotalShares() const { return GetEditValue(mTotalSharesEdit); }
   double GetProfit() const { return GetEditValue(mProfitEdit); }
   bool HasValidData() const 
   {
      return GetTotalInvestment() > 0 && GetSharePrice() > 0 && GetTotalShares() > 0;
   }
};