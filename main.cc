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
#if 1
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
#endif


#if 0
#include <windows.h>
#include <winhttp.h>
#include <commctrl.h>
#include <string>
#include <thread>
#include <chrono>
#include <regex>
#include <format>
#include <atomic>
#include <sstream>
#include <locale>
#include <codecvt>

#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "comctl32.lib")

// Window controls
constexpr int ID_EDIT_EUR = 1001;
constexpr int ID_EDIT_USD = 1002;
constexpr int ID_STATIC_RATE = 1003;
constexpr int ID_TIMER_UPDATE = 1004;
constexpr int WM_RATE_UPDATED = WM_USER + 1;
constexpr int WM_ERROR_OCCURRED = WM_USER + 2;

class CurrencyConverter 
{
private:
   HWND hWndMain{};
   HWND hEditEUR{}, hEditUSD{}, hStaticRate{};
   std::atomic<double> currentRate{ 0.0 };
   std::atomic<bool> isUpdating{ false };
   std::thread updateThread;
   std::wstring lastError;
   std::atomic<bool> isUpdatingRate{ false };

public:
   CurrencyConverter() = default;
   ~CurrencyConverter() {
      if (updateThread.joinable()) {
         updateThread.join();
      }
   }

   bool CreateMainWindow(HINSTANCE hInstance) 
   {
      constexpr auto className = L"CurrencyConverterClass";

      WNDCLASSEXW wc{};
      wc.cbSize = sizeof(WNDCLASSEXW);
      wc.style = CS_HREDRAW | CS_VREDRAW;
      wc.lpfnWndProc = WindowProc;
      wc.hInstance = hInstance;
      wc.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
      wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
      wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
      wc.lpszClassName = className;
      wc.hIconSm = LoadIconW(nullptr, IDI_APPLICATION);

      if (!RegisterClassExW(&wc)) {
         return false;
      }

      hWndMain = CreateWindowExW(
         0, className, L"Real-Time USD/EUR Currency Converter",
         WS_OVERLAPPEDWINDOW & ~WS_MAXIMIZEBOX & ~WS_THICKFRAME,
         CW_USEDEFAULT, CW_USEDEFAULT, 450, 350,
         nullptr, nullptr, hInstance, this
      );

      if (!hWndMain) {
         return false;
      }

      ShowWindow(hWndMain, SW_SHOW);
      UpdateWindow(hWndMain);
      return true;
   }

private:
   static LRESULT CALLBACK WindowProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
      CurrencyConverter* pThis = nullptr;

      if (uMsg == WM_NCCREATE) {
         auto pCreate = reinterpret_cast<CREATESTRUCT*>(lParam);
         pThis = static_cast<CurrencyConverter*>(pCreate->lpCreateParams);
         SetWindowLongPtrW(hWnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(pThis));
      }
      else {
         pThis = reinterpret_cast<CurrencyConverter*>(GetWindowLongPtrW(hWnd, GWLP_USERDATA));
      }

      if (pThis) {
         return pThis->HandleMessage(hWnd, uMsg, wParam, lParam);
      }

      return DefWindowProcW(hWnd, uMsg, wParam, lParam);
   }

   LRESULT HandleMessage(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
      switch (uMsg) {
      case WM_CREATE:
         CreateControls(hWnd);
         StartRealTimeUpdates();
         return 0;

      case WM_COMMAND:
         if (HIWORD(wParam) == EN_CHANGE && !isUpdating.load()) {
            HandleEditChange(LOWORD(wParam));
         }
         return 0;

      case WM_TIMER:
         if (wParam == ID_TIMER_UPDATE) {
            // Show that we're updating
            SetWindowTextW(hStaticRate, L"Updating exchange rate...");
            UpdateExchangeRate();
         }
         return 0;

      case WM_RATE_UPDATED:
         UpdateRateDisplay();
         return 0;

      case WM_ERROR_OCCURRED:
         DisplayError();
         return 0;

      case WM_DESTROY:
         KillTimer(hWnd, ID_TIMER_UPDATE);
         PostQuitMessage(0);
         return 0;
      }

      return DefWindowProcW(hWnd, uMsg, wParam, lParam);
   }

   void CreateControls(HWND hWnd) {
      // Create font
      HFONT hFont = CreateFontW(16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
         DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
         DEFAULT_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

      // EUR input section
      auto hStaticEUR = CreateWindowW(L"STATIC", L"EUR Amount:",
         WS_VISIBLE | WS_CHILD,
         20, 20, 100, 20, hWnd, nullptr, nullptr, nullptr);
      SendMessageW(hStaticEUR, WM_SETFONT, reinterpret_cast<WPARAM>(hFont), TRUE);

      hEditEUR = CreateWindowW(L"EDIT", L"100.00",
         WS_VISIBLE | WS_CHILD | WS_BORDER | ES_RIGHT,
         20, 45, 150, 30, hWnd, (HMENU)(UINT_PTR)ID_EDIT_EUR, nullptr, nullptr);

      // USD input section
      auto hStaticUSD = CreateWindowW(L"STATIC", L"USD Amount:",
         WS_VISIBLE | WS_CHILD,
         220, 20, 100, 20, hWnd, nullptr, nullptr, nullptr);
      SendMessageW(hStaticUSD, WM_SETFONT, reinterpret_cast<WPARAM>(hFont), TRUE);

      hEditUSD = CreateWindowW(L"EDIT", L"0.00",
         WS_VISIBLE | WS_CHILD | WS_BORDER | ES_RIGHT,
         220, 45, 150, 30, hWnd, (HMENU)(UINT_PTR)ID_EDIT_USD, nullptr, nullptr);

      // Exchange rate display
      auto hStaticRateLabel = CreateWindowW(L"STATIC", L"Exchange Rate:",
         WS_VISIBLE | WS_CHILD,
         20, 95, 120, 20, hWnd, nullptr, nullptr, nullptr);
      SendMessageW(hStaticRateLabel, WM_SETFONT, reinterpret_cast<WPARAM>(hFont), TRUE);

      hStaticRate = CreateWindowW(L"STATIC", L"Connecting to API...",
         WS_VISIBLE | WS_CHILD | SS_LEFT,
         20, 120, 400, 80, hWnd, (HMENU)(UINT_PTR)ID_STATIC_RATE, nullptr, nullptr);


      // Status
      auto hStaticStatus = CreateWindowW(L"STATIC", L"📊 Real-time updates every 30 seconds",
         WS_VISIBLE | WS_CHILD | SS_CENTER,
         20, 220, 400, 20, hWnd, nullptr, nullptr, nullptr);
      SendMessageW(hStaticStatus, WM_SETFONT, reinterpret_cast<WPARAM>(hFont), TRUE);

      // Instructions
      auto hStaticInstr = CreateWindowW(L"STATIC", L"Enter amount in either field for instant conversion",
         WS_VISIBLE | WS_CHILD | SS_CENTER,
         20, 245, 400, 20, hWnd, nullptr, nullptr, nullptr);
      SendMessageW(hStaticInstr, WM_SETFONT, reinterpret_cast<WPARAM>(hFont), TRUE);
   }

   void StartRealTimeUpdates() {
      // Initial rate fetch
      UpdateExchangeRate();
      // Set timer for periodic updates (30 seconds)
      SetTimer(hWndMain, ID_TIMER_UPDATE, 30000, nullptr);
   }

   void UpdateExchangeRate() {
      // Check if already updating using the class member variable
      if (isUpdatingRate.load()) {
         return; // Already updating
      }

      // Run in separate thread to avoid blocking UI
      if (updateThread.joinable()) {
         updateThread.join();
      }

      updateThread = std::thread([this]() {
         isUpdatingRate.store(true);

         // Try multiple APIs
         double rate = 0.0;

         // Try exchangerate.host first
         rate = FetchFromExchangeRateHost();

         // If that fails, try freeforexapi.com
         if (rate <= 0) {
            rate = FetchFromFreeForexAPI();
         }

         // If that fails, try a hardcoded fallback (you can remove this in production)
         if (rate <= 0) {
            rate = 0.92; // Approximate EUR/USD rate as fallback
            lastError = L"Using fallback rate - check internet connection";
            PostMessageW(hWndMain, WM_ERROR_OCCURRED, 0, 0);
         }

         if (rate > 0) {
            currentRate.store(rate);
            PostMessageW(hWndMain, WM_RATE_UPDATED, 0, 0);
         }

         isUpdatingRate.store(false);
         });
      updateThread.detach();
   }

   double FetchFromExchangeRateHost() {
      return FetchExchangeRate(L"api.exchangerate.host", L"/convert?from=USD&to=EUR&amount=1", "result");
   }

   double FetchFromFreeForexAPI() {
      return FetchExchangeRate(L"freeforexapi.com", L"/api/live?pairs=USDEUR", "rates.USDEUR");
   }

   double FetchExchangeRate(const wchar_t* host, const wchar_t* path, const char* jsonField) {
      HINTERNET hSession = nullptr, hConnect = nullptr, hRequest = nullptr;
      double rate = 0.0;

      try {
         // Initialize WinHTTP
         hSession = WinHttpOpen(L"CurrencyConverter/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME,
            WINHTTP_NO_PROXY_BYPASS, 0);

         if (!hSession) {
            lastError = L"Failed to initialize WinHTTP";
            return 0.0;
         }

         // Connect to API
         hConnect = WinHttpConnect(hSession, host, 443, 0);
         if (!hConnect) {
            lastError = std::format(L"Failed to connect to {}", host);
            return 0.0;
         }

         // Create request
         hRequest = WinHttpOpenRequest(hConnect, L"GET", path,
            nullptr, WINHTTP_NO_REFERER,
            WINHTTP_DEFAULT_ACCEPT_TYPES,
            WINHTTP_FLAG_SECURE);

         if (!hRequest) {
            lastError = L"Failed to create HTTP request";
            return 0.0;
         }

         // Send request
         if (!WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
            WINHTTP_NO_REQUEST_DATA, 0, 0, 0)) {
            lastError = L"Failed to send HTTP request";
            return 0.0;
         }

         // Receive response
         if (!WinHttpReceiveResponse(hRequest, nullptr)) {
            lastError = L"Failed to receive HTTP response";
            return 0.0;
         }

         // Check status code
         DWORD statusCode = 0;
         DWORD statusCodeSize = sizeof(statusCode);
         WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
            nullptr, &statusCode, &statusCodeSize, nullptr);

         if (statusCode != 200) {
            lastError = std::format(L"HTTP Error: {}", statusCode);
            return 0.0;
         }

         // Read response data
         std::string response;
         DWORD bytesRead = 0;
         char buffer[4096];

         do {
            if (!WinHttpReadData(hRequest, buffer, sizeof(buffer), &bytesRead)) {
               break;
            }
            response.append(buffer, bytesRead);
         } while (bytesRead > 0);

         if (response.empty()) {
            lastError = L"Empty response from API";
            return 0.0;
         }

         // Parse JSON response
         rate = ParseExchangeRate(response, jsonField);

         if (rate <= 0) {
            lastError = L"Failed to parse exchange rate from response";
         }

      }
      catch (const std::exception& e) {
         // Convert std::string to std::wstring
         std::string errorStr = e.what();
         lastError = std::wstring(errorStr.begin(), errorStr.end());
      }
      catch (...) {
         lastError = L"Unknown error occurred";
      }

      // Cleanup
      if (hRequest) WinHttpCloseHandle(hRequest);
      if (hConnect) WinHttpCloseHandle(hConnect);
      if (hSession) WinHttpCloseHandle(hSession);

      return rate;
   }

   double ParseExchangeRate(const std::string& json, const char* field) 
   {
      try {
         // Create regex pattern for the field
         std::string pattern = std::format(R"("{}"[^:]*:\s*([0-9]+\.?[0-9]*))", field);
         std::regex resultRegex(pattern);
         std::smatch match;

         if (std::regex_search(json, match, resultRegex)) {
            return std::stod(match[1].str());
         }

         // Also try without quotes for nested fields like rates.USDEUR
         if (std::string(field).find('.') != std::string::npos) {
            std::string simplePattern = R"(([0-9]+\.?[0-9]*))";
            size_t pos = json.find("USDEUR");
            if (pos != std::string::npos) {
               std::string substr = json.substr(pos + 6, 20);
               std::regex simpleRegex(simplePattern);
               if (std::regex_search(substr, match, simpleRegex)) {
                  return std::stod(match[1].str());
               }
            }
         }
      }
      catch (...) {
         return 0.0;
      }
      return 0.0;
   }

   void UpdateRateDisplay() 
   {
      double rate = currentRate.load();
      if (rate > 0) {
         auto rateText = std::format(
            L"1 USD = {:.4f} EUR\n1 EUR = {:.4f} USD\nLast updated: {}",
            rate, 1.0 / rate, GetCurrentTimeString()
         );
         SetWindowTextW(hStaticRate, rateText.c_str());
      }
   }

   void DisplayError() 
   {
      auto errorText = std::format(L"Error: {}\nRetrying in 30 seconds...", lastError);
      SetWindowTextW(hStaticRate, errorText.c_str());
   }

   void HandleEditChange(int controlId) {
      double rate = currentRate.load();
      if (rate <= 0) return;

      wchar_t buffer[256];
      double value = 0.0;

      isUpdating.store(true);

      if (controlId == ID_EDIT_EUR)
      {
         GetWindowTextW(hEditEUR, buffer, std::size(buffer));
         value = _wtof(buffer);
         double usdValue = value / rate;

         auto usdStr = std::format(L"{:.2f}", usdValue);
         SetWindowTextW(hEditUSD, usdStr.c_str());
      }
      else if (controlId == ID_EDIT_USD) 
      {
         GetWindowTextW(hEditUSD, buffer, std::size(buffer));
         value = _wtof(buffer);
         double eurValue = value * rate;

         auto eurStr = std::format(L"{:.2f}", eurValue);
         SetWindowTextW(hEditEUR, eurStr.c_str());
      }

      isUpdating.store(false);
   }

   std::wstring GetCurrentTimeString() 
   {
      auto now = std::chrono::system_clock::now();
      auto time_t = std::chrono::system_clock::to_time_t(now);

      std::tm tm{};
      localtime_s(&tm, &time_t);

      return std::format(L"{:02d}:{:02d}:{:02d}",
         tm.tm_hour, tm.tm_min, tm.tm_sec);
   }
};

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE, LPWSTR, int) 
{
   InitCommonControls();

   CurrencyConverter app;
   if (!app.CreateMainWindow(hInstance)) {
      MessageBoxW(nullptr, L"Failed to create main window!", L"Error", MB_OK | MB_ICONERROR);
      return -1;
   }

   MSG msg{};
   while (GetMessageW(&msg, nullptr, 0, 0)) {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
   }

   return static_cast<int>(msg.wParam);
}

#elif 0
#include <iostream>
#include <fstream>
#include <string>
#include <set>

int main() {
   // Use the WSL path directly
   std::string inputFile = "\\\\wsl.localhost\\Ubuntu-22.04\\home\\joj4fe\\PRJ_DRIVING\\logDoc.txt";
   std::string outputFile = "out.txt";

   std::ifstream inFile(inputFile.c_str());
   if (!inFile.is_open()) {
      std::cerr << "Error: Could not open input file: " << inputFile << std::endl;
      std::cerr << "Make sure WSL is running and the file exists at the specified path" << std::endl;
      return 1;
   }

   std::set<std::string> unknownOptions;
   std::string line;
   std::string searchPattern = "unknown option:";

   while (std::getline(inFile, line)) {
      size_t pos = line.find(searchPattern);
      if (pos != std::string::npos) {
         size_t quoteStart = line.find('"', pos + searchPattern.length());
         if (quoteStart != std::string::npos) {
            size_t quoteEnd = line.find('"', quoteStart + 1);
            if (quoteEnd != std::string::npos) {
               std::string option = line.substr(quoteStart + 1, quoteEnd - quoteStart - 1);
               unknownOptions.insert(option);
            }
         }
      }
   }

   inFile.close();

   std::ofstream outFile(outputFile.c_str());
   if (!outFile.is_open()) {
      std::cerr << "Error: Could not create output file: " << outputFile << std::endl;
      return 1;
   }

   std::cout << "Found " << unknownOptions.size() << " unique unknown options:" << std::endl;

   for (std::set<std::string>::const_iterator it = unknownOptions.begin();
      it != unknownOptions.end(); ++it) {
      std::cout << "  " << *it << std::endl;
      outFile << *it << std::endl;
   }

   outFile.close();
   std::cout << "Results saved to: " << outputFile << std::endl;

   // Keep console open to see the output
   std::cout << "Press Enter to exit...";
   std::cin.get();

   return 0;
}

#endif