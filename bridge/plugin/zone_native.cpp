#include "zone_native.h"
#include "df/building_civzonest.h"
#include "df/building_archerytargetst.h"
#include "df/world.h"
#include <windows.h>
#include <cstdint>
#include <cstdlib>
#include <climits>

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
            hash(base+0x3579af,0x80)==0xd862207edcc7f2bbULL &&
            hash(base+0x357a2f,0x461)==0x6df7802f8dfd9811ULL &&
            hash(base+0x5587b0,0x79)==0x14b4f3f138690067ULL;
    }();
    return compatible;
}
bool nativeZoneDefaults(df::building_civzonest& zone) {
    if(!nativeZoneDefaultsReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    // DF53.16 creation calls this leaf at356f16/357765. All branches write
    // only the supplied type and settings union; no globals, calls or scratch.
    using Initialize=void (*)(df::building_civzonest*,df::civzone_type);
    reinterpret_cast<Initialize>(base+0x30f550)(&zone,zone.type);
    // These two post-creation effects are inline at3579e7..357a2a.
    // Pond's check_occupants bit is distinct from its user-facing fill mode.
    if(zone.type==df::civzone_type::Pen)zone.zone_settings.pen.flags.bits.check_occupants=true;
    if(zone.type==df::civzone_type::Pond)zone.zone_settings.pond.flag.bits.check_occupants=true;
    if(zone.type==df::civzone_type::ArcheryRange) {
        if(!df::global::world || !zone.room.extents || zone.x1<0 || zone.y1<0 || zone.z<0 ||
           zone.x2<zone.x1 || zone.y2<zone.y1 || zone.x2>32767 || zone.y2>32767 || zone.z>32767 ||
           int64_t(zone.x2-zone.x1+1)*(zone.y2-zone.y1+1)>32768)return false;
        // Native357a2f..357e90 has no independent direction entry point.
        // Its inclusion tests call5587b0 with the actual zone; that leaf reads
        // only supplied bounds/extents. Do not substitute usable-tile counts.
        using Contains=bool (*)(df::building*,int16_t,int16_t,int16_t);
        const auto contains=reinterpret_cast<Contains>(base+0x5587b0);
        int64_t cells=0,cellX=0,cellY=0,targets=0,targetX=0,targetY=0;
        for(int32_t x=zone.x1;x<=zone.x2;++x)for(int32_t y=zone.y1;y<=zone.y2;++y) {
            if(!contains(&zone,int16_t(x),int16_t(y),int16_t(zone.z)))continue;
            ++cells;cellX+=x;cellY+=y;
        }
        for(const auto* target:df::global::world->buildings.other.ARCHERY_TARGET) {
            if(!target)return false;
            if(!contains(&zone,int16_t(target->centerx),int16_t(target->centery),int16_t(target->z)))continue;
            ++targets;targetX+=target->centerx;targetY+=target->centery;
            if(targets>INT32_MAX || targetX>INT32_MAX || targetY>INT32_MAX)return false;
        }
        // No targets retains DF's initializer default. Native truncates each
        // mean before comparing, resolves axis ties toward X, and center ties
        // toward negative X. These are observed native choices, not UX policy.
        if(cells && targets) {
            const auto dx=cellX/cells-targetX/targets,dy=cellY/cells-targetY/targets;
            auto& range=zone.zone_settings.archery;
            if(std::abs(dx)>=std::abs(dy)){range.dir_x=dx<0?1:-1;range.dir_y=0;}
            else {range.dir_x=0;range.dir_y=dy<0?1:-1;}
        }
    }
    return true;
}
bool nativeZoneCreateReady() {
    if(!nativeZoneDefaultsReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=
        hash(base+0x28b650,0x23)==0x1bc97f28bb55040dULL &&
        hash(base+0x28b710,0xb2)==0x0a9c60d382679201ULL &&
        hash(base+0x54bb60,0x110)==0xad02785ff295fa9bULL &&
        hash(base+0x577040,0x3500)==0x758911d1932d14dbULL &&
        hash(base+0x57fc70,0xcb)==0x9c1f8dc48a9760b0ULL &&
        hash(base+0x558550,0x13b)==0x60e1b99a5ab1f65dULL &&
        hash(base+0x558690,0x111)==0x36b85ab14744745bULL &&
        hash(base+0x558830,0xfa)==0xc5a7534fb1c71db4ULL;
    return compatible;
}
df::building_civzonest* nativeZoneAllocate() {
    if(!df::global::world || !nativeZoneCreateReady())return nullptr;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Allocate=df::building_civzonest* (*)();
    return reinterpret_cast<Allocate>(base+0x28b650)();
}
bool nativeZoneComplete(df::building_civzonest& zone) {
    if(!df::global::world || !nativeZoneCreateReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Complete=void (*)(df::building*,bool);
    using Relationships=void (*)(df::building*);
    // Native357948..3579a4: completion, categorization, relationship refresh.
    // The relationship routines use semantic world lists and supplied extents.
    // In particular558830 tests candidate x1/y1, not the DFHack center heuristic.
    reinterpret_cast<Complete>(base+0x577040)(&zone,true);
    zone.categorize(true);
    reinterpret_cast<Relationships>(base+0x558550)(&zone);
    reinterpret_cast<Relationships>(base+0x558690)(&zone);
    reinterpret_cast<Relationships>(base+0x558830)(&zone);
    return true;
}
}
