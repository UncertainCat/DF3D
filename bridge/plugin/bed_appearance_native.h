#pragma once
#include <cstdint>
#include <string>
namespace df { struct item; }
struct lua_State;
namespace df3d_bed {
struct Choices {
    int32_t sheet = -1;
    int32_t pillow = -1;
    int32_t color = -1; // zero-based descriptor color; -1 means no color
};
// Safe-point caller. Uses owned generator state, never renderer RNG/cache.
bool choices(int32_t itemId, int32_t colorCount, Choices& result);
struct Facts {
    int8_t sheet = -1, pillow = -1;
    std::string baseColor, sheetColor;
    friend bool operator==(const Facts&, const Facts&) = default;
};
// Owned semantic values. Unknown/non-bed inputs return absent variants.
Facts facts(df::item* item);
int nativeFacts(lua_State* L);
}
