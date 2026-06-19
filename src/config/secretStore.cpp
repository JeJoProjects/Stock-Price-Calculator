#include "config/secretStore.hpp"

#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#include <wincrypt.h>
#endif

namespace secure {

namespace {

std::string toHex(const std::vector<unsigned char>& bytes) {
    static constexpr char kDigits[] = "0123456789ABCDEF";
    std::string out;
    out.reserve(bytes.size() * 2);
    for (unsigned char byte : bytes) {
        out.push_back(kDigits[(byte >> 4) & 0x0F]);
        out.push_back(kDigits[byte & 0x0F]);
    }
    return out;
}

std::vector<unsigned char> fromHex(const std::string& hex) {
    auto nibble = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
        if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
        return -1;
    };

    std::vector<unsigned char> bytes;
    if (hex.size() % 2 != 0) return bytes;
    bytes.reserve(hex.size() / 2);

    for (std::size_t i = 0; i < hex.size(); i += 2) {
        int hi = nibble(hex[i]);
        int lo = nibble(hex[i + 1]);
        if (hi < 0 || lo < 0) return {};
        bytes.push_back(static_cast<unsigned char>((hi << 4) | lo));
    }
    return bytes;
}

} // namespace

std::string SecretStore::encrypt(const std::string& plainText) {
#ifdef _WIN32
    if (plainText.empty()) return {};

    DATA_BLOB in{};
    in.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(plainText.data()));
    in.cbData = static_cast<DWORD>(plainText.size());

    DATA_BLOB out{};
    if (!CryptProtectData(&in, L"StockPriceCalculator", nullptr, nullptr, nullptr, 0, &out)) {
        return {};
    }

    std::vector<unsigned char> bytes(out.pbData, out.pbData + out.cbData);
    LocalFree(out.pbData);
    return toHex(bytes);
#else
    return plainText;
#endif
}

std::string SecretStore::decrypt(const std::string& cipherText) {
#ifdef _WIN32
    if (cipherText.empty()) return {};

    auto bytes = fromHex(cipherText);
    if (bytes.empty()) return {};

    DATA_BLOB in{};
    in.pbData = bytes.data();
    in.cbData = static_cast<DWORD>(bytes.size());

    DATA_BLOB out{};
    if (!CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr, 0, &out)) {
        return {};
    }

    std::string plain(reinterpret_cast<char*>(out.pbData), out.cbData);
    LocalFree(out.pbData);
    return plain;
#else
    return cipherText;
#endif
}

} // namespace secure
