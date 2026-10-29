#pragma once
#include "farm_native.h"
#include "df/buildingitemst.h"
#include "df/item.h"

namespace df3d_production {
// Common building-sheet caption at 19d4ae calls this semantic formatter with
// independently owned string storage. The body spans two unwind entries.
inline std::optional<std::string> buildingItemCaption(df::item* item) {
    using Caption=void (*)(df::item*,std::string*,bool,int32_t);
    static const auto caption=[]()->Caption {
        if(!farmFunctions())return nullptr;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0xaba;++i){hash^=base[0xc65450+i];hash*=UINT64_C(1099511628211);}
        if(hash!=UINT64_C(0x47fa672b7bbcd332))return nullptr;
        return reinterpret_cast<Caption>(base+0xc65450);
    }();
    if(!caption||!item)return std::nullopt;
    std::string result;caption(item,&result,false,-1);return result;
}
// Native common building-sheet item actions. Call at a safe point, with a
// freshly validated contained item. No selector, input or viewscreen scratch.
struct BuildingItemFunctions {
    using Predicate=bool (*)(df::item*);
    using Action=void (*)(df::item*);
    using Forbid=void (*)(df::item*,int8_t);
    Predicate canDump=nullptr,canMelt=nullptr;
    Action toggleDump=nullptr,markMelt=nullptr;
    Predicate cancelMelt=nullptr;
    Forbid forbid=nullptr;
    explicit operator bool() const {return canDump&&canMelt&&toggleDump&&markMelt&&cancelMelt&&forbid;}
};
inline const BuildingItemFunctions& buildingItemFunctions() {
    static const auto functions=[]()->BuildingItemFunctions {
        if(!farmFunctions())return {};
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        // Dump spans unwind entries. Forbid includes its local jump tables.
        // These pinned complete ranges contain no PE base relocations.
        if(hash(0xfc270,0xb)!=UINT64_C(0x61cf0dc9d24aeb0a) ||
           hash(0xcab7c0,0x92)!=UINT64_C(0xeec8852fcfd06c80) ||
           hash(0xcb2060,0x88)!=UINT64_C(0x03f2a24ee82efb8b) ||
           hash(0xc634f0,0x1044)!=UINT64_C(0x9e5389b911a7fbab) ||
           hash(0xcabe10,0xe2)!=UINT64_C(0x318b651ccb834c58) ||
           hash(0xcb2020,0x35)!=UINT64_C(0xd69ef21a72216341))return {};
        return {reinterpret_cast<BuildingItemFunctions::Predicate>(base+0xfc270),
            reinterpret_cast<BuildingItemFunctions::Predicate>(base+0xcab7c0),
            reinterpret_cast<BuildingItemFunctions::Action>(base+0xcb2060),
            reinterpret_cast<BuildingItemFunctions::Action>(base+0xcb2020),
            reinterpret_cast<BuildingItemFunctions::Predicate>(base+0xcabe10),
            reinterpret_cast<BuildingItemFunctions::Forbid>(base+0xc634f0)};
    }();return functions;
}
enum class BuildingItemAction { Forbid, Dump, Melt, Hidden };
inline bool buildingItemValue(df::item* item,BuildingItemAction action) {
    switch(action) {
    case BuildingItemAction::Forbid:return item->flags.bits.forbid;
    case BuildingItemAction::Dump:return item->flags.bits.dump;
    case BuildingItemAction::Melt:return item->flags.bits.melt;
    case BuildingItemAction::Hidden:return item->flags.bits.hidden;
    }return false;
}
// false promises no entry/effect. Caller must treat exceptions after entry as
// Unknown, observe a fresh receipt, and never retry an uncertain operation.
inline bool setBuildingItemFlag(df::item* item,BuildingItemAction action,bool value) {
    const auto& native=buildingItemFunctions();if(!native||!item)return false;
    if(action==BuildingItemAction::Dump&&!native.canDump(item))return false;
    if(action==BuildingItemAction::Melt&&!native.canMelt(item))return false;
    if(buildingItemValue(item,action)==value)return true;
    switch(action) {
    case BuildingItemAction::Forbid:
        item->flags.bits.forbid=value;
        if(value)native.forbid(item,3);
        else {item->stockpile_countdown=0;item->stockpile_delay=0;}
        return true;
    case BuildingItemAction::Dump:native.toggleDump(item);return true;
    case BuildingItemAction::Melt:
        if(value)native.markMelt(item);else native.cancelMelt(item);
        return true;
    case BuildingItemAction::Hidden:item->flags.bits.hidden=value;return true;
    }return false;
}
}
