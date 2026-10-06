#pragma once
#include <cstddef>
#include <cstdint>
#include <windows.h>
#include "df/creature_graphics_layer_setst.h"
#include "df/layer_set_templatest.h"
#include "df/creature_raw.h"
#include "df/caste_raw.h"

namespace df3d_appearance {
using ExpandGraphicsTemplate = void (*)(df::creature_graphics_layer_setst*,
    df::layer_set_templatest*,df::creature_raw*,df::caste_raw*);

// Steam53.16: native map/portrait resolvers call723720 with set, template,
// creature and caste (71e42d..71e439 and71a5b7..71a5c4). It substitutes arguments
// into copied template lines and invokes the raw parser; no unit texture or UI
// is an input. Both complete routines have no PE base relocations.
inline ExpandGraphicsTemplate graphicsTemplateFunction() {
    static const auto function=[]()->ExpandGraphicsTemplate {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        if(!base)return nullptr;
        const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>0x1000)return nullptr;
        const auto* pe=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
        if(pe->Signature!=IMAGE_NT_SIGNATURE || pe->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64 ||
            pe->FileHeader.TimeDateStamp!=0x6a70a6d9 || pe->OptionalHeader.SizeOfImage!=0x2711000)return nullptr;
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        if(hash(0x723720,0xfa9)!=UINT64_C(0x81ae48a4ba3f13b9) ||
            hash(0x1146550,0x1d66eb)!=UINT64_C(0x9d6bba53eae205dd))return nullptr;
        return reinterpret_cast<ExpandGraphicsTemplate>(const_cast<uint8_t*>(base+0x723720));
    }();
    return function;
}
}
