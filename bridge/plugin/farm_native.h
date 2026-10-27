#pragma once
#include <array>
#include <cstdint>
#include <windows.h>
#include "df/building_farmplotst.h"
#include "df/plotinfost.h"

namespace df3d_production {
// Semantic readers called by the native farm sheet. No selected building,
// sheet season, crop vector or native menu scratch is an input to either call.
struct FarmFunctions {
    using Eligible=bool (*)(df::building_farmplotst*,int32_t);
    using Seasons=void (*)(int16_t,std::array<uint8_t,4>*);
    using PlantingWarning=bool (*)(df::plotinfost*,int16_t);
    Eligible eligible=nullptr;
    Seasons seasons=nullptr;
    PlantingWarning plantingWarning=nullptr;
    explicit operator bool() const {return eligible && seasons && plantingWarning;}
};
inline const FarmFunctions& farmFunctions() {
    static const auto functions=[]()->FarmFunctions {
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
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
        // Complete semantic bodies and immediate tile predicates; none of
        // these ranges contains PE base relocations. Seasons spans unwind entries.
        if(hash(0x557770,0xdd)!=UINT64_C(0x20402352c38579ef) ||
           hash(0xaae1a0,0x12b)!=UINT64_C(0x8a101112ecf87493) ||
           hash(0x14b1460,0xb7)!=UINT64_C(0xf10a5339f477c759) ||
           hash(0x14b1520,0x202)!=UINT64_C(0x93c5ad7f34f5db75) ||
           hash(0x57c050,0xcb)!=UINT64_C(0x243c738f199909d3))return {};
        return {reinterpret_cast<FarmFunctions::Eligible>(base+0x557770),
                reinterpret_cast<FarmFunctions::Seasons>(base+0xaae1a0),
                reinterpret_cast<FarmFunctions::PlantingWarning>(base+0x57c050)};
    }();
    return functions;
}
}
