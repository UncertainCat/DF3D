// Offline compatibility probe: takes the pinned executable's extracted routine.
// Never executes it or ships the game bytes. Extraction stays in ignored output.
#include "../../bridge/plugin/location_value_guard.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    std::ifstream file(argv[1], std::ios::binary);
    std::vector<uint8_t> bytes{std::istreambuf_iterator<char>(file), {}};
    const auto matches = [&](uint16_t machine = 0x8664, uint32_t time = 0x6a70a6d9,
                             uint32_t size = 0x2711000) {
        return df3d_area::matchesLocationRefresh(machine, time, size, bytes.data(), bytes.size());
    };
    if (!matches()) { std::cerr << "Pinned native routine did not match\n"; return 1; }
    size_t checks = 1;
    for (size_t i = 0; i < bytes.size(); ++i) {
        bytes[i] ^= 1;
        if (matches()) { std::cerr << "Modified code accepted at " << i << '\n'; return 1; }
        bytes[i] ^= 1; ++checks;
    }
    for (unsigned bit = 0; bit < 32; ++bit) {
        const auto mask = uint32_t{1} << bit;
        if (matches(0x8664, 0x6a70a6d9 ^ mask) || matches(0x8664, 0x6a70a6d9, 0x2711000 ^ mask)) return 1;
        checks += 2;
    }
    for (unsigned bit = 0; bit < 16; ++bit) {
        if (matches(static_cast<uint16_t>(0x8664 ^ (uint16_t{1} << bit)))) return 1;
        ++checks;
    }
    for (size_t n = 0; n < bytes.size(); ++n) {
        if (df3d_area::matchesLocationRefresh(0x8664, 0x6a70a6d9, 0x2711000, bytes.data(), n)) return 1;
        ++checks;
    }
    bytes.push_back(0);
    if (matches() || df3d_area::matchesLocationRefresh(0x8664, 0x6a70a6d9, 0x2711000, nullptr, df3d_area::kLocationRefreshBytes)) return 1;
    std::cout << "LOCATION_GUARD_PASS " << checks + 2 << " checks\n";
}
