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
#include "df/building_extents_type.h"
#include "location_dance_guard.h"

namespace df3d_area {
using LocationDance = void (*)(const df::building_extents_type*,int32_t,int32_t,int32_t,
    int32_t,int32_t,int32_t*,int32_t*);

// Supported Steam 53.16 binary: SHA256
// 205770918fd54c96cbbcf89223ebd449e2e113c7c873ed81177c4511a3450db7.
// Native Details initializer3ad230 calls this with room extents, x/y/z and size.
// It reads terrain/occupancy and writes only output dimensions; no native UI state.
// Pin the complete routine (no base relocations), including all rectangle ranking.
inline LocationDance locationDanceFunction() {
    static_assert(sizeof(df::building_extents_type)==1);
    auto* base = reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if (!base) return nullptr;
    auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0 || dos->e_lfanew > 0x1000) return nullptr;
    auto* pe = reinterpret_cast<const IMAGE_NT_HEADERS64*>(base + dos->e_lfanew);
    if (pe->Signature != IMAGE_NT_SIGNATURE || pe->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64 ||
        pe->FileHeader.TimeDateStamp != 0x6a70a6d9 || pe->OptionalHeader.SizeOfImage != 0x2711000) return nullptr;
    if (!matchesLocationDance(pe->FileHeader.Machine, pe->FileHeader.TimeDateStamp,
        pe->OptionalHeader.SizeOfImage, base + kLocationDanceRva, kLocationDanceBytes)) return nullptr;
    return reinterpret_cast<LocationDance>(const_cast<uint8_t*>(base + kLocationDanceRva));
}
}
