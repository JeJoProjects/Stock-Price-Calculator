#pragma once

#include <string>

namespace secure {

class SecretStore {
public:
    [[nodiscard]] static std::string encrypt(const std::string& plainText);
    [[nodiscard]] static std::string decrypt(const std::string& cipherText);
};

} // namespace secure
