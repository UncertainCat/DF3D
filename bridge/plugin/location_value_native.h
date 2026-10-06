#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include "df/abstract_building_contents.h"
#include "location_value_guard.h"

namespace df3d_area {
using LocationRefresh = void (*)(df::abstract_building_contents*, int32_t, bool);

// Supported Steam 53.16 binary: SHA256
// 205770918fd54c96cbbcf89223ebd449e2e113c7c873ed81177c4511a3450db7.
// Native callers pass getContents(), abstract_building::id, true, then reset
// update_timer/update_count. This routine also updates supply counts/need flags.
// It reads semantic world data; no viewscreen or selector state is supplied.
// Fail before publishing a location on an unrecognized executable.
inline LocationRefresh locationRefreshFunction() {
    static_assert(offsetof(df::abstract_building_contents, location_value) == 0x38);
    static_assert(offsetof(df::abstract_building_contents, building_ids) == 0x70);
    auto* base = reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if (!base) return nullptr;
    auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 0x1000) return nullptr;
    auto* pe = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    if (pe->Signature != IMAGE_NT_SIGNATURE || pe->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64 ||
        pe->FileHeader.TimeDateStamp != 0x6a70a6d9 || pe->OptionalHeader.SizeOfImage != 0x2711000) return nullptr;
    if (!matchesLocationRefresh(pe->FileHeader.Machine, pe->FileHeader.TimeDateStamp,
        pe->OptionalHeader.SizeOfImage, base + kLocationRefreshRva, kLocationRefreshBytes)) return nullptr;
    return reinterpret_cast<LocationRefresh>(const_cast<uint8_t*>(base + kLocationRefreshRva));
}
}
