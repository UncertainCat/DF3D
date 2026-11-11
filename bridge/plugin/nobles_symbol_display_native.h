#pragma once
#include "nobles_symbols_native.h"
#include "building_item_native.h"

namespace df3d_nobles {
struct SymbolDisplay {
    int32_t itemId=-1;
    std::string caption,officeCaption,valueCaption;
};
// Native425d10/425e42/425fd1. Sorting uses c66c30; displayed value uses
// c66020 including contents, then broker appraisal and native77f920 formatting.
// e64560 reads semantic office/unit state and can refresh the broker's semantic
// vision/body caches through133e7a0; no menu or rendering cache is involved.
inline std::optional<std::vector<SymbolDisplay>> symbolDisplay(Context& owned,uint32_t offset,uint32_t limit) {
    if(!symbolsReady() || !limit || limit>64)return std::nullopt;
    const auto& value=owned.value;const auto count=value.cand_symbol.size();
    if(offset>count || value.cand_symbol_new_ind.size()!=count)return std::nullopt;
    auto* base=owned.base;
    if(reinterpret_cast<const void*>(df::global::gamemode)!=base+0x189c298 ||
       reinterpret_cast<const void*>(&df::global::world->raws.creatures.all)!=base+0x24eca68)return std::nullopt;
    static const bool pinned=[base]{
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xe64560,0x18a,UINT64_C(0xd245c7df2218be4d)},
            {0xc66020,0x12e,UINT64_C(0xfe0378c306832ca2)},
            {0x77f920,0x2b0,UINT64_C(0x9ad2d1d0985ca611)},
            {0x133e7a0,0x32d,UINT64_C(0xb3c6cbdbc8f6dade)},
            {0x13835e0,0x5d,UINT64_C(0x8a4ea09c08f7a30c)},
            {0x13241d0,0xa0,UINT64_C(0x546b9aa664537305)},
            {0x13a50f0,0x1d7,UINT64_C(0x4a0a07ed2a5fafff)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!pinned)return std::nullopt;
    df3d_creature::InventoryRandomRestore random(base);
    const int32_t appraisal=reinterpret_cast<int32_t(*)()>(base+0xe64560)();
    std::vector<SymbolDisplay> rows;
    for(size_t i=offset;i<std::min(count,size_t(offset)+limit);++i) {
        auto* item=value.cand_symbol[i];if(!item)return std::nullopt;
        const auto caption=df3d_production::buildingItemCaption(item);if(!caption)return std::nullopt;
        SymbolDisplay row;row.itemId=item->id;row.caption=*caption;
        const auto selected=value.cand_symbol_new_ind[i];
        if(selected!=-1) {
            if(selected<0 || size_t(selected)>=value.noblelist.size())return std::nullopt;
            const auto* office=value.noblelist[selected];if(!office || !office->ep)return std::nullopt;
            row.officeCaption=office->ep->land_name.empty()?office->ep->name[0]:office->ep->land_name;
            reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&row.officeCaption);
        }
        if(appraisal>0) {
            const auto amount=reinterpret_cast<int32_t(*)(df::item*,void*,void*,bool,bool)>(base+0xc66020)(item,nullptr,nullptr,false,false);
            reinterpret_cast<void(*)(std::string*,int32_t,int32_t)>(base+0x77f920)(&row.valueCaption,amount,appraisal-1);
            row.valueCaption.insert(0,reinterpret_cast<const char*>(base+0x15fe080),7);
        }
        rows.push_back(std::move(row));
    }
    return rows;
}
}
