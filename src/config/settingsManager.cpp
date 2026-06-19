#include "config/settingsManager.hpp"
#include "config/secretStore.hpp"
#include <fstream>
#include <sstream>
#include <cstdio>
#include <charconv>

namespace config {

static double readJsonDouble(const std::string& json, const std::string& key, double fallback) {
    auto kp = "\"" + key + "\"";
    auto pos = json.find(kp);
    if (pos == std::string::npos) return fallback;
    pos = json.find(':', pos + kp.size());
    if (pos == std::string::npos) return fallback;
    ++pos;
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) ++pos;
    double val = 0.0;
    auto [ptr, ec] = std::from_chars(json.data() + pos, json.data() + json.size(), val);
    return ec == std::errc{} ? val : fallback;
}

static bool readJsonBool(const std::string& json, const std::string& key, bool fallback) {
    auto kp = "\"" + key + "\"";
    auto pos = json.find(kp);
    if (pos == std::string::npos) return fallback;
    pos = json.find(':', pos + kp.size());
    if (pos == std::string::npos) return fallback;
    ++pos;
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) ++pos;
    if (json.compare(pos, 4, "true") == 0) return true;
    if (json.compare(pos, 5, "false") == 0) return false;
    return fallback;
}

static std::string readJsonString(const std::string& json, const std::string& key) {
    auto kp = "\"" + key + "\"";
    auto pos = json.find(kp);
    if (pos == std::string::npos) return {};
    pos = json.find(':', pos + kp.size());
    if (pos == std::string::npos) return {};
    pos = json.find('"', pos + 1);
    if (pos == std::string::npos) return {};
    ++pos;
    std::string out;
    while (pos < json.size()) {
        char c = json[pos++];
        if (c == '"') break;
        if (c == '\\' && pos < json.size()) {
            char esc = json[pos++];
            switch (esc) {
            case '"': out.push_back('"'); break;
            case '\\': out.push_back('\\'); break;
            case '/': out.push_back('/'); break;
            case 'b': out.push_back('\b'); break;
            case 'f': out.push_back('\f'); break;
            case 'n': out.push_back('\n'); break;
            case 'r': out.push_back('\r'); break;
            case 't': out.push_back('\t'); break;
            default: break;
            }
        } else {
            out.push_back(c);
        }
    }
    return out;
}

static std::string escapeJsonString(const std::string& value) {
    std::string out;
    out.reserve(value.size() + 8);
    for (char c : value) {
        switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\b': out += "\\b"; break;
        case '\f': out += "\\f"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default: out.push_back(c); break;
        }
    }
    return out;
}

AppSettings loadSettings(const std::string& path) {
    AppSettings s{};
    std::ifstream file(path);
    if (!file.is_open()) return s;

    std::ostringstream ss;
    ss << file.rdbuf();
    std::string json = ss.str();

    s.fontSize = static_cast<float>(readJsonDouble(json, "fontSize", 15.0));
    s.maxSearchResults = static_cast<int>(readJsonDouble(json, "maxSearchResults", 12.0));
    s.showExchangeBadges = readJsonBool(json, "showExchangeBadges", true);
    s.showStatsBar = readJsonBool(json, "showStatsBar", true);
    s.finnhubApiKey = secure::SecretStore::decrypt(readJsonString(json, "finnhubApiKeyEnc"));
    s.windowWidth = static_cast<int>(readJsonDouble(json, "windowWidth", 1280.0));
    s.windowHeight = static_cast<int>(readJsonDouble(json, "windowHeight", 720.0));
    s.windowX = static_cast<int>(readJsonDouble(json, "windowX", -1.0));
    s.windowY = static_cast<int>(readJsonDouble(json, "windowY", -1.0));

    return s;
}

void saveSettings(const AppSettings& s, const std::string& path) {
    std::ofstream file(path);
    if (!file.is_open()) return;

    char buf[512];
    std::string keyEnc = secure::SecretStore::encrypt(s.finnhubApiKey);
    std::string keyEncEscaped = escapeJsonString(keyEnc);
    std::snprintf(buf, sizeof(buf),
        "{\n"
        "  \"fontSize\": %.1f,\n"
        "  \"maxSearchResults\": %d,\n"
        "  \"showExchangeBadges\": %s,\n"
        "  \"showStatsBar\": %s,\n"
        "  \"finnhubApiKeyEnc\": \"%s\",\n"
        "  \"windowWidth\": %d,\n"
        "  \"windowHeight\": %d,\n"
        "  \"windowX\": %d,\n"
        "  \"windowY\": %d\n"
        "}\n",
        s.fontSize, s.maxSearchResults,
        s.showExchangeBadges ? "true" : "false",
        s.showStatsBar ? "true" : "false",
        keyEncEscaped.c_str(),
        s.windowWidth, s.windowHeight,
        s.windowX, s.windowY);

    file << buf;
}

} // namespace config
