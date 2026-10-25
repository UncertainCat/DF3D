#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <vector>
namespace df3d_hover {
struct Description {
    std::string text;
    int16_t foreground = 7, background = 0;
    bool bright = false;
    uint8_t kind = 0;
    int32_t id = -1;
};
enum class ObjectKind { Item, Unit, Building };
// Caller holds the DF safe point. No native cursor, hover list or viewscreen inputs.
std::optional<std::string> terrain(int32_t x, int32_t y, int32_t z);
// Owned native fortress hover entries; unavailable/hidden targets have no result.
std::optional<std::vector<Description>> collect(int32_t x, int32_t y, int32_t z);
// Formats an independently identified object. Does not establish hover eligibility.
std::optional<Description> object(ObjectKind kind, int32_t id);
}
