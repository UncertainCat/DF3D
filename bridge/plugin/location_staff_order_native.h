#pragma once
#include <array>
#include <cstdint>
#include <string>
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include "df/unit.h"

namespace df3d_area {
// These stateless native readers take semantic units and caller-owned output.
// No viewscreen, widget, native cursor or staged UI state is read. The tagged
// unit reference matches the native unit/item value ABI; only units are used.
// Capture040156 identifies the callers and pinned routines. Text comparison
// excludes custom professions and normalizes CP437 in place before byte order.
struct StaffUnitReference { df::unit* unit; uint8_t kind=0; uint8_t padding[7]{}; };
static_assert(sizeof(StaffUnitReference)==16);
struct StaffOrderingFunctions {
    using Text=void (*)(df::unit*,std::string*,bool);
    using Normalize=void (*)(std::string*);
    using Category=void (*)(std::array<int32_t,2>*,const StaffUnitReference*);
    Text name=nullptr,profession=nullptr;
    Normalize normalize=nullptr;
    Category category=nullptr;
    explicit operator bool() const {return name && profession && normalize && category;}
};
inline const StaffOrderingFunctions& staffOrderingFunctions() {
    static const auto functions=[]()->StaffOrderingFunctions {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        if(!base)return {};
        const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>0x1000)return {};
        const auto* pe=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
        if(pe->Signature!=IMAGE_NT_SIGNATURE || pe->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64 ||
            pe->FileHeader.TimeDateStamp!=0x6a70a6d9 || pe->OptionalHeader.SizeOfImage!=0x2711000)return {};
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        // Complete reader bodies, normalization/category tables and the two
        // category status predicates. No PE base relocations in these ranges.
        if(
            hash(0x1330c30,0x688)!=UINT64_C(0x0e165ee31decf426) ||
            hash(0x132f980,0x8de)!=UINT64_C(0x64c00c9b84e68e70) ||
            hash(0x1425050,0x11c)!=UINT64_C(0xcfe5fe894265ba13) ||
            hash(0x1376500,0xf0)!=UINT64_C(0x2c5ca25b0abc0a79) ||
            hash(0x138ed20,0xff)!=UINT64_C(0x430951f9f3e403c2) ||
            hash(0x52cee0,0x19e)!=UINT64_C(0xc25c2d8a6eb9fcac) ||
            hash(0xaa0220,0x56c)!=UINT64_C(0xb717aad6385bda8f))return {};
        return {reinterpret_cast<StaffOrderingFunctions::Text>(const_cast<uint8_t*>(base+0x1330c30)),
            reinterpret_cast<StaffOrderingFunctions::Text>(const_cast<uint8_t*>(base+0x132f980)),
            reinterpret_cast<StaffOrderingFunctions::Normalize>(const_cast<uint8_t*>(base+0x52cee0)),
            reinterpret_cast<StaffOrderingFunctions::Category>(const_cast<uint8_t*>(base+0x1425050))};
    }();
    return functions;
}
}
