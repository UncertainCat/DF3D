#pragma once
#include "justice_native.h"
#include "zone_native.h"
namespace df3d_justice {
struct CandidatePresentation {
    std::string name,witnessLabel,deceased;
    uint32_t witnessCount=0;uint8_t witnessColor=6;
    df3d_area::ZoneOwnerNameColor nameColor;
};
// Native46eb60 configures one_line_only on the standard unit-name widget.
// Its renderer14237a0 calls the plain name/abbreviation routines below, but
// stores output in global drawing strings. Only owned strings/units are used
// here. The witness label is inline in46eb60, with no standalone formatter.
inline std::optional<CandidatePresentation> candidatePresentation(const df::crime* crime,df::unit* unit,int32_t columns) {
    if(!crime || !unit || columns<3 || columns>2048 || crime->witnesses.size()>1048576 ||
       !df3d_creature::inventoryDescriptionReady())return std::nullopt;
    const auto& text=df3d_area::staffOrderingFunctions();if(!text)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x46eb60,0x570,UINT64_C(0x3c4f68da97f9af0b)},
            {0x14237a0,0x83f,UINT64_C(0xbc38168cc5c544cd)},
            {0x52d910,0x5c4,UINT64_C(0x3cc66a9b45f7baa9)},
            {0x52c130,0xb3,UINT64_C(0xf2e358ad54df1c09)},
        };
        for(const auto& p:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){hash^=base[p.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=p.hash)return false;}
        return true;
    }();
    if(!pinned || unit->inventory.size()>10000)return std::nullopt;
    for(const auto* entry:unit->inventory)if(!entry)return std::nullopt;
    CandidatePresentation result;
    for(const auto* report:crime->witnesses){if(!report)return std::nullopt;
        if(report->accused_id==unit->id)++result.witnessCount;}
    df3d_creature::InventoryRandomRestore restore(base);
    df3d_creature::InventoryDescriptionContext owned(*unit);
    text.name(owned.unit(),&result.name,true);
    if(result.name.size()>16384)return std::nullopt;
    if(result.name.size()>size_t(columns)) {
        reinterpret_cast<void(*)(std::string*,int32_t)>(base+0x52d910)(&result.name,columns);
        if(result.name.size()>size_t(columns)){result.name.resize(columns);result.name.replace(columns-3,3,"...");}
    }
    const auto color=df3d_area::nativeZoneOwnerNameColor(*owned.unit());if(!color)return std::nullopt;
    result.nameColor=*color;
    if(!result.witnessCount)result.witnessLabel="No witnesses";
    else {
        result.witnessColor=10;
        if(result.witnessCount==1)result.witnessLabel="1 witness";
        else {reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c130)(int32_t(result.witnessCount),&result.witnessLabel);
            result.witnessLabel+=" witnesses";}
    }
    // Native46ec05 tests flags1 bit1, including inactive off-map units.
    if(unit->flags1.bits.inactive)result.deceased="Deceased";
    return result;
}
}
