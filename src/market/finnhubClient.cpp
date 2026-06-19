#include "market/finnhubClient.hpp"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <sstream>

#ifdef _WIN32
#include <windows.h>
#include <winhttp.h>
#endif

namespace market {

void FinnhubClient::setApiKey(std::string apiKey) {
    apiKey_ = std::move(apiKey);
}

std::string FinnhubClient::urlEncode(const std::string& text) {
    std::string out;
    out.reserve(text.size() * 3);
    for (unsigned char c : text) {
        if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            out.push_back(static_cast<char>(c));
        } else {
            char buf[4];
            std::snprintf(buf, sizeof(buf), "%%%02X", c);
            out += buf;
        }
    }
    return out;
}

std::string FinnhubClient::request(const std::string& path, std::string& error) const {
#ifdef _WIN32
    if (apiKey_.empty()) {
        error = "Finnhub API key is not configured.";
        return {};
    }

    HINTERNET session = WinHttpOpen(L"StockPriceCalculator/1.0",
        WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session) {
        error = "Failed to open WinHTTP session.";
        return {};
    }

    HINTERNET connect = WinHttpConnect(session, L"finnhub.io", INTERNET_DEFAULT_HTTPS_PORT, 0);
    if (!connect) {
        WinHttpCloseHandle(session);
        error = "Failed to connect to Finnhub.";
        return {};
    }

    std::wstring widePath(path.begin(), path.end());
    HINTERNET requestHandle = WinHttpOpenRequest(connect, L"GET", widePath.c_str(), nullptr,
        WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (!requestHandle) {
        WinHttpCloseHandle(connect);
        WinHttpCloseHandle(session);
        error = "Failed to open request.";
        return {};
    }

    BOOL sent = WinHttpSendRequest(requestHandle, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
        WINHTTP_NO_REQUEST_DATA, 0, 0, 0);
    if (!sent || !WinHttpReceiveResponse(requestHandle, nullptr)) {
        WinHttpCloseHandle(requestHandle);
        WinHttpCloseHandle(connect);
        WinHttpCloseHandle(session);
        error = "Finnhub request failed.";
        return {};
    }

    std::string response;
    DWORD available = 0;
    while (WinHttpQueryDataAvailable(requestHandle, &available) && available > 0) {
        std::string chunk(available, '\0');
        DWORD read = 0;
        if (!WinHttpReadData(requestHandle, chunk.data(), available, &read)) break;
        chunk.resize(read);
        response += chunk;
    }

    WinHttpCloseHandle(requestHandle);
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    return response;
#else
    error = "Finnhub client is Windows-only.";
    return {};
#endif
}

double FinnhubClient::readDouble(const std::string& json, const std::string& key, double fallback) {
    auto kp = "\"" + key + "\"";
    auto pos = json.find(kp);
    if (pos == std::string::npos) return fallback;
    pos = json.find(':', pos + kp.size());
    if (pos == std::string::npos) return fallback;
    ++pos;
    while (pos < json.size() && std::isspace(static_cast<unsigned char>(json[pos]))) ++pos;
    char* end = nullptr;
    double value = std::strtod(json.c_str() + pos, &end);
    return end && end != json.c_str() + pos ? value : fallback;
}

std::string FinnhubClient::readString(const std::string& json, const std::string& key) {
    auto kp = "\"" + key + "\"";
    auto pos = json.find(kp);
    if (pos == std::string::npos) return {};
    pos = json.find(':', pos + kp.size());
    if (pos == std::string::npos) return {};
    pos = json.find('"', pos);
    if (pos == std::string::npos) return {};
    ++pos;
    auto end = json.find('"', pos);
    if (end == std::string::npos) return {};
    return json.substr(pos, end - pos);
}

bool FinnhubClient::fetchQuote(const std::string& symbol, Quote& quote, std::string& error) const {
    auto response = request("/api/v1/quote?symbol=" + urlEncode(symbol) + "&token=" + apiKey_, error);
    if (response.empty()) return false;

    quote.current = readDouble(response, "c", 0.0);
    quote.change = readDouble(response, "d", 0.0);
    quote.percent = readDouble(response, "dp", 0.0);
    quote.high = readDouble(response, "h", 0.0);
    quote.low = readDouble(response, "l", 0.0);
    quote.open = readDouble(response, "o", 0.0);
    quote.previousClose = readDouble(response, "pc", 0.0);
    return quote.current > 0.0;
}

bool FinnhubClient::fetchProfile(const std::string& symbol, CompanyProfile& profile, std::string& error) const {
    auto response = request("/api/v1/stock/profile2?symbol=" + urlEncode(symbol) + "&token=" + apiKey_, error);
    if (response.empty()) return false;

    profile.name = readString(response, "name");
    profile.exchange = readString(response, "exchange");
    profile.currency = readString(response, "currency");
    profile.marketCap = readDouble(response, "marketCapitalization", 0.0);
    return !profile.name.empty();
}

bool FinnhubClient::fetchCandles(const std::string& symbol, Timeframe timeframe,
    std::vector<Candle>& candles, std::string& error) const {
    const int lookback = timeframeLookbackDays(timeframe);
    const int to = static_cast<int>(std::time(nullptr));
    const int from = to - lookback * 24 * 60 * 60;
    const char* resolution = timeframeResolution(timeframe);

    std::ostringstream path;
    path << "/api/v1/stock/candle?symbol=" << urlEncode(symbol)
         << "&resolution=" << resolution
         << "&from=" << from
         << "&to=" << to
         << "&token=" << apiKey_;

    auto response = request(path.str(), error);
    if (response.empty()) return false;

    auto status = readString(response, "s");
    if (status != "ok") {
        error = "No chart data returned.";
        return false;
    }

    auto readArray = [&](const std::string& key) {
        std::vector<double> values;
        auto kp = "\"" + key + "\"";
        auto pos = response.find(kp);
        if (pos == std::string::npos) return values;
        pos = response.find('[', pos + kp.size());
        if (pos == std::string::npos) return values;
        ++pos;
        while (pos < response.size()) {
            while (pos < response.size() && (response[pos] == ' ' || response[pos] == ',')) ++pos;
            if (pos >= response.size() || response[pos] == ']') break;
            char* end = nullptr;
            double value = std::strtod(response.c_str() + pos, &end);
            if (!end || end == response.c_str() + pos) break;
            values.push_back(value);
            pos = static_cast<std::size_t>(end - response.c_str());
        }
        return values;
    };

    auto times = readArray("t");
    auto opens = readArray("o");
    auto highs = readArray("h");
    auto lows = readArray("l");
    auto closes = readArray("c");
    auto volumes = readArray("v");

    std::size_t count = std::min({times.size(), opens.size(), highs.size(), lows.size(), closes.size(), volumes.size()});
    candles.clear();
    candles.reserve(count);
    for (std::size_t i = 0; i < count; ++i) {
        candles.push_back(Candle{
            static_cast<long long>(times[i]),
            opens[i], highs[i], lows[i], closes[i], volumes[i]
        });
    }
    return !candles.empty();
}

} // namespace market
