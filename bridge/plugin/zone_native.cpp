#include "zone_native.h"
#include "df/building_civzonest.h"
#include <windows.h>
#include <cstdint>

namespace df3d_area {
namespace {
uint64_t hash(const uint8_t* bytes,size_t size) {
    uint64_t value=14695981039346656037ULL;
    while(size--){value^=*bytes++;value*=1099511628211ULL;}
    return value;
}
}
bool nativeZoneDefaultsReady() {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return false;
    static const bool compatible=[&] {
        const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>4096)return false;
        const auto* pe=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
        return pe->Signature==IMAGE_NT_SIGNATURE && pe->FileHeader.Machine==0x8664 &&
            pe->FileHeader.TimeDateStamp==0x6a70a6d9 && pe->OptionalHeader.SizeOfImage==0x2711000 &&
            hash(base+0x30f550,0x5b)==0xed4d0c73606384a4ULL &&
            hash(base+0x3579af,0x80)==0xd862207edcc7f2bbULL;
    }();
    return compatible;
}
bool nativeZoneDefaults(df::building_civzonest& zone) {
    if(!nativeZoneDefaultsReady() || zone.id!=-1)return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    // DF53.16 creation calls this leaf at356f16/357765. All branches write
    // only the supplied type and settings union; no globals, calls or scratch.
    using Initialize=void (*)(df::building_civzonest*,df::civzone_type);
    reinterpret_cast<Initialize>(base+0x30f550)(&zone,zone.type);
    // These two post-creation effects are inline at3579e7..357a2a.
    // Pond's check_occupants bit is distinct from its user-facing fill mode.
    if(zone.type==df::civzone_type::Pen)zone.zone_settings.pen.flags.bits.check_occupants=true;
    if(zone.type==df::civzone_type::Pond)zone.zone_settings.pond.flag.bits.check_occupants=true;
    return true;
}
}
