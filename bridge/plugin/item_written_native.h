#pragma once
#include "written_detail_native.h"
#include "df/item_constructed.h"
#include "df/item_bookst.h"
#include "df/itemimprovement_writingst.h"
#include "df/itemimprovement_pagesst.h"
#include "df/game_mode.h"

namespace df3d_production {
inline bool writtenItem(df::item* item) {
    return item && (item->getType()==df::item_type::BOOK || item->getType()==df::item_type::SHEET);
}
// c77ddd and c75a83 use semantic writing/page improvements. Native knowledge
// gates are adventure-only; never satisfy them using a native view or menu.
inline bool itemWrittenInputsReady(df::item* item) {
    if(!writtenItem(item))return true;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(!df::global::world || !df::global::gamemode ||
       reinterpret_cast<const void*>(df::global::gamemode)!=base+0x189c298 ||
       *df::global::gamemode!=df::game_mode::DWARF)return false;
    static const bool pinned=[base]{
        struct Pin{size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xcc7020,0x5d8,UINT64_C(0x0d5d4dc2df4ecc45)},
            {0xcc6a10,0x610,UINT64_C(0x899e28a94029e30f)},
            {0xc3a4f0,0x98,UINT64_C(0x90965a9fe84783f6)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return df3d_creature::writtenDescriptionReady();
    }();
    if(!pinned)return false;
    static_assert(offsetof(df::item_bookst,title)==0xe8);
    static_assert(offsetof(df::itemimprovement_writingst,contents)==0x28);
    static_assert(offsetof(df::itemimprovement_pagesst,contents)==0x30);
    const auto& improvements=static_cast<const df::item_constructed*>(item)->improvements;
    if(improvements.size()>4096)return false;
    for(const auto* improvement:improvements){
        if(!improvement)return false;
        const auto* table=*reinterpret_cast<const void* const*>(improvement);
        const std::vector<int32_t>* ids=nullptr;
        if(table==base+0x17034c0)ids=&static_cast<const df::itemimprovement_pagesst*>(improvement)->contents;
        if(table==base+0x16fa430)ids=&static_cast<const df::itemimprovement_writingst*>(improvement)->contents;
        if(!ids)continue;
        if(ids->size()>4096)return false;
        // Both formatters resolve content only for a singleton ID. Preserve
        // native missing/multiple-content wording instead of inventing prose.
        if(ids->size()==1)if(const auto* content=df::written_content::find(ids->front()))
            if(!df3d_creature::writtenContentInputsValid(*content))return false;
    }
    return true;
}
}
