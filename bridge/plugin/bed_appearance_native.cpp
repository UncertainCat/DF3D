#include "bed_appearance_native.h"
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <algorithm>
#include <cstddef>
#include <climits>
#include "df/item.h"
#include "df/item_type.h"
#include "df/descriptor_color.h"
#include "df/descriptor_pattern.h"
#include "df/material.h"
#include "df/matter_state.h"
#include "modules/Materials.h"
#include "lua.h"
namespace df3d_bed {
namespace {
uint64_t fingerprint(const uint8_t* p, size_t n) {
    uint64_t h = 14695981039346656037ULL;
    while (n--) { h ^= *p++; h *= 1099511628211ULL; }
    return h;
}
}
bool choices(int32_t itemId, int32_t colorCount, Choices& result) {
    result = {};
    if (itemId < 0 || colorCount < 0) return false;
    auto* base = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if (!base) return false;
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 4096) return false;
    const auto* pe = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    if (pe->Signature != IMAGE_NT_SIGNATURE || pe->FileHeader.Machine != 0x8664 ||
        pe->FileHeader.TimeDateStamp != 0x6a70a6d9 || pe->OptionalHeader.SizeOfImage != 0x2711000 ||
        fingerprint(base + 0x2471c0, 75) != 0xa34702d10f978500ULL ||
        fingerprint(base + 0xc80546, 0x222) != 0xc3579fae15bb6e53ULL) return false;
    // DF seeds from item.id and draws sheet, pillow, then descriptor color.
    // The fingerprinted leaf modifies only the supplied uint64 state.
    using Draw = uint64_t (*)(uint64_t*);
    const auto draw = reinterpret_cast<Draw>(base + 0x2471c0);
    uint64_t state = static_cast<uint64_t>(itemId);
    result.sheet = static_cast<int32_t>((draw(&state) >> 32) & 1);
    result.pillow = static_cast<int32_t>((draw(&state) >> 32) % 3);
    if (colorCount > 0)
        result.color = static_cast<int32_t>((draw(&state) >> 32) % std::min(colorCount, 254));
    return true;
}
Facts facts(df::item* item) {
    Facts result;
    if (!item || item->getType()!=df::item_type::BED) return result;
    const auto& colors=df::descriptor_color::get_vector();
    if (colors.size()>INT_MAX) return result;
    Choices selected;
    if (!choices(item->id,static_cast<int32_t>(colors.size()),selected)) return result;
    result.sheet=static_cast<int8_t>(selected.sheet);
    result.pillow=static_cast<int8_t>(selected.pillow);
    if (selected.color>=0 && colors[selected.color]) result.sheetColor=colors[selected.color]->id;
    // Native bed rendering uses the material's solid-state pattern's first
    // color, rather than the item's dye override. No renderer palette is read.
    DFHack::MaterialInfo material(item);
    if (material.isValid() && material.material) {
        const auto* pattern=df::descriptor_pattern::find(material.material->state_color[df::matter_state::Solid]);
        if (pattern && !pattern->colors.empty()) {
            const int color=pattern->colors.front();
            if (color>=0 && color<255 && size_t(color)<colors.size() && colors[color])
                result.baseColor=colors[color]->id;
        }
    }
    return result;
}
int nativeFacts(lua_State* L) {
    if (!lua_isinteger(L,1) || lua_tointeger(L,1)<0 || lua_tointeger(L,1)>INT_MAX) {
        lua_pushnil(L); return 1;
    }
    const auto value=facts(df::item::find(static_cast<int32_t>(lua_tointeger(L,1))));
    if (value.sheet<0) { lua_pushnil(L); return 1; }
    lua_createtable(L,0,4);
    lua_pushinteger(L,value.sheet); lua_setfield(L,-2,"sheet");
    lua_pushinteger(L,value.pillow); lua_setfield(L,-2,"pillow");
    lua_pushlstring(L,value.baseColor.data(),value.baseColor.size()); lua_setfield(L,-2,"base_color");
    lua_pushlstring(L,value.sheetColor.data(),value.sheetColor.size()); lua_setfield(L,-2,"sheet_color");
    return 1;
}
}
