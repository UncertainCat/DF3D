#include "stockpile_native.h"
#include "df/global_objects.h"
#include <windows.h>
#include <cstdint>

namespace df3d_area {
namespace {
uint64_t hash(const uint8_t* bytes, size_t size) {
    uint64_t value=14695981039346656037ULL;
    while(size--){value^=*bytes++;value*=1099511628211ULL;}
    return value;
}
bool supported(const uint8_t* base) {
    const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>4096)return false;
    const auto* pe=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
    if(pe->Signature!=IMAGE_NT_SIGNATURE || pe->FileHeader.Machine!=0x8664 ||
       pe->FileHeader.TimeDateStamp!=0x6a70a6d9 || pe->OptionalHeader.SizeOfImage!=0x2711000)return false;
    // DF53.16 Steam: preset dispatch, category initialization, clear, its two
    // leaf clear helpers, food defaults, remaining category defaults, vector resize.
    // Category initialization reads world raw vectors only. Defaults write only
    // the supplied settings. No viewscreen, menu, cursor, RNG or search scratch.
    static constexpr struct {size_t rva,size;uint64_t digest;} spans[]={
        {0x30dde0,0x284,0x2416b7f890dcc5c8ULL},
        {0x30e070,0x8de,0x0b6339ac229308d2ULL},
        {0x30e950,0x30a,0xbf6b4d07a83d3047ULL},
        {0x30d3a0,0x1e0,0x1a07cecec065344eULL},
        {0x30d670,0x9f,0x157142509d361a48ULL},
        {0x589990,0x700,0x2cffdef38e85d382ULL},
        {0x58a090,0xba8,0x976d41b1575bf126ULL},
        {0x1b9fb0,0x7d,0x8d074f444d49cc3eULL},
    };
    for(const auto& span:spans)if(hash(base+span.rva,span.size)!=span.digest)return false;
    return true;
}
}
std::optional<df::stockpile_settings> nativeStockpilePreset(
    const df::stockpile_settings& source,int preset) {
    if(!df::global::world || preset<1 || preset>19)return std::nullopt;
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return std::nullopt;
    static const bool compatible=supported(base);
    if(!compatible)return std::nullopt;
    static_assert(sizeof(df::stockpile_settings)==0x7e0);
    // Wire order is category-bit order; native stockpile_list includes Ore at6.
    // Native All=19 and None=-1. The UI call site is34a77f/34a7aa.
    static constexpr int16_t modes[]={19,0,1,2,3,4,5,7,8,9,10,11,12,13,14,15,16,17,-1};
    auto owned=source;
    using Clear=void (*)(df::stockpile_settings*);
    using Initialize=void (*)(df::stockpile_settings*,int16_t);
    reinterpret_cast<Clear>(base+0x30e950)(&owned);
    reinterpret_cast<Initialize>(base+0x30dde0)(&owned,modes[preset-1]);
    return owned;
}
}
