#pragma once
#include "farm_native.h"
#include "building_item_transaction.h"
#include "df/buildingitemst.h"
#include "df/item.h"
#include "df/job.h"
#include "df/specific_ref.h"
#include "modules/Buildings.h"
#include "modules/Materials.h"
#include "modules/Items.h"
#include "df/itemdef.h"

namespace df3d_production {
// Native follow loops35e7b6/8b6b76 use these independently owned outputs.
// Reference getters may initialize semantic cached indices, never UI state.
inline std::optional<df::coord> itemPosition(df::item* item) {
    using Resolve=void (*)(df::item*,int16_t*,int16_t*,int16_t*);
    static const auto resolve=[]()->Resolve {
        if(!farmFunctions())return nullptr;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        if(hash(0xc8baa0,0x11a)!=UINT64_C(0x2c62fce4a0555c66) ||
           hash(0x1367430,0xc6)!=UINT64_C(0xc0292be8a6dacf2c) ||
           hash(0xedfa60,0xbd)!=UINT64_C(0x2f89116df6b958cc) ||
           hash(0xedfb20,0x13)!=UINT64_C(0xa222e60f2f8301e4) ||
           hash(0x14db50,0xb1)!=UINT64_C(0x4b9c987ca0656b35) ||
           hash(0x14dc10,0x5a)!=UINT64_C(0xfb6e6c7bccbf765b) ||
           hash(0x67270,6)!=UINT64_C(0x7dce27ae257f083d) ||
           hash(0x7a840,6)!=UINT64_C(0xeff4222c8d49c252))return nullptr;
        return reinterpret_cast<Resolve>(base+0xc8baa0);
    }();
    if(!resolve||!item)return std::nullopt;
    int16_t x=-30000,y=-30000,z=-30000;
    resolve(item,&x,&y,&z);
    return df::coord(x,y,z);
}
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
struct ItemBuildingHolder {
    int32_t id=-1,type=-1;
    std::string name;
};
// Native item sheet153bec resolves BUILDING_HOLDER through the semantic general
// reference lookup. Renderer1567ed calls holder->getName into owned text storage.
inline std::optional<ItemBuildingHolder> itemBuildingHolder(df::item* item) {
    using Find=df::building* (*)(df::item*,int32_t);
    static const auto find=[]()->Find {
        if(!farmFunctions())return nullptr;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x63;++i){hash^=base[0xcb16b0+i];hash*=UINT64_C(1099511628211);}
        if(hash!=UINT64_C(0xaf4453f988ab95f7))return nullptr;
        return reinterpret_cast<Find>(base+0xcb16b0);
    }();
    if(!find||!item)return std::nullopt;
    ItemBuildingHolder result;
    if(auto* building=find(item,0x24)) {
        result.id=building->id;result.type=static_cast<int32_t>(building->getType());
        building->getName(&result.name);
        if(result.name.size()>512)return std::nullopt;
    }
    return result;
}
// Item-sheet renderer154c84 calls this owned-string weight formatter. Native
// lazy computation may populate weight caches on this item and its contents.
inline std::optional<std::string> itemWeightCaption(df::item* item) {
    using Format=void (*)(df::item*,std::string*);
    static const auto format=[]()->Format {
        if(!farmFunctions())return nullptr;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        if(hash(0x14d8e0,0x58)!=UINT64_C(0x739fc70478cf6b3f) ||
           hash(0xc65f10,0x106)!=UINT64_C(0x440442082189ed12))return nullptr;
        return reinterpret_cast<Format>(base+0x14d8e0);
    }();
    if(!format||!item)return std::nullopt;
    std::string result;format(item,&result);return result;
}
// Seed-specific virtual targets used by c75000. Pin both dispatch and complete
// leaf bodies before relying on type/quality/construction/image exclusions.
inline bool seedDescriptionDispatch(df::item* item) {
    if(!item||!farmFunctions())return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(*reinterpret_cast<const void* const*>(item)!=base+0x16d06e0)return false;
    static const bool pinned=[base]() {
        struct Pin {size_t slot,target,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x0,0x103de0,6,UINT64_C(0x5fc4dbfcbf4a7f23)}, // getType
            {0x10,0xfca10,8,UINT64_C(0xfc97df6278270fbf)}, // getMaterial
            {0x18,0xfca20,7,UINT64_C(0x5ca530bad2557b5a)}, // getMaterialIndex
            {0x38,0xfca10,8,UINT64_C(0xfc97df6278270fbf)}, // getActualMaterial
            {0x40,0xfca20,7,UINT64_C(0x5ca530bad2557b5a)}, // getActualMaterialIndex
            {0x1d8,0xfc240,8,UINT64_C(0xfa411eb4425a85fb)}, // getWear
            {0x1e8,0x66e60,6,UINT64_C(0x62d2efd24138f070)}, // getMaker
            {0x230,0x75f60,9,UINT64_C(0x6aa4478617a62f2e)}, // getImageRef
            {0x448,0x67040,3,UINT64_C(0xa3703b1a918cfbeb)}, // isActual
            {0x478,0xfc190,7,UINT64_C(0xf985d8151da86506)}, // getStackSize
            {0x508,0x66e90,3,UINT64_C(0x58389c18233078ff)}, // getQuality
            {0x590,0x66e60,6,UINT64_C(0x62d2efd24138f070)}, // getMakerRace
            {0x5a8,0x67050,3,UINT64_C(0x62941518298855c4)}, // isConstructed
            {0x5e0,0xfc1c0,8,UINT64_C(0x2d52a42a21f4c0e4)}, // getMagic
            {0x6b0,0x66e60,6,UINT64_C(0x62d2efd24138f070)}, // getColorWhetherDyedOrNot
            {0x6c0,0x67050,3,UINT64_C(0x62941518298855c4)}, // isCritter
            {0x750,0x66e60,6,UINT64_C(0x62d2efd24138f070)}, // getFaceUp
        };
        for(const auto& pin:pins) {
            if(*reinterpret_cast<const void* const*>(base+0x16d06e0+pin.slot)!=base+pin.target)return false;
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.target+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        // Semantic material/name dependencies. Historical material resolution
        // may populate creature_handler::hist_fig_to_creature_map; no UI cache.
        struct Helper {size_t rva,length;uint64_t hash;};
        constexpr Helper helpers[]={
            {0x14d1920,0x459,UINT64_C(0xf48e28715360ed9a)},
            {0x14add70,0x12f,UINT64_C(0x01f897b15772d540)},
            {0x701e70,0x20e,UINT64_C(0xead0193006374e44)},
            {0x725c70,0x2b9,UINT64_C(0xec840d94b839c6b5)},
            {0xc3a4f0,0x98,UINT64_C(0x90965a9fe84783f6)},
            {0x72570,0x98,UINT64_C(0xa69932c0f279084a)},
            {0xa946e0,0x7c2,UINT64_C(0xdbc3db5f052419ee)},
            {0x52d3c0,0x288,UINT64_C(0x6e1fbc2416fba9fc)},
            {0xd2cb50,0xf0,UINT64_C(0xf7ab8eceaadda09f)},
            {0x1bb2e0,0x45,UINT64_C(0xc7976f8e247d7d17)},
            {0x1bb330,0xcc,UINT64_C(0x22cd601a57c49cb0)},
        };
        for(const auto& helper:helpers) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<helper.length;++i){hash^=base[helper.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=helper.hash)return false;
        }
        return true;
    }();
    return pinned;
}
// Seed-specific owned description. General item branches can initialize art
// or grant adventure knowledge and must not use this seed-only entry point.
inline std::optional<std::string> seedItemDescription(df::item* item) {
    using Describe=void (*)(df::item*,std::string*,bool,bool,bool,int32_t);
    if(!seedDescriptionDispatch(item))return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base]() {
        uint64_t value=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x46aa;++i){value^=base[0xc75000+i];value*=UINT64_C(1099511628211);}
        return value==UINT64_C(0xd5969f2286ee8a96);
    }();
    if(!pinned)return std::nullopt;
    std::string result;
    reinterpret_cast<Describe>(base+0xc75000)(item,&result,true,true,false,0);
    return result;
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
inline bool buildingItemValue(df::item* item,BuildingItemAction action) {
    switch(action) {
    case BuildingItemAction::Forbid:return item->flags.bits.forbid;
    case BuildingItemAction::Dump:return item->flags.bits.dump;
    case BuildingItemAction::Melt:return item->flags.bits.melt;
    case BuildingItemAction::Hidden:return item->flags.bits.hidden;
    }return false;
}
inline std::optional<BuildingContentsSnapshot> buildingContents(df::building_actual* building) {
    const auto& native=buildingItemFunctions();if(!native||!building)return std::nullopt;
    BuildingContentsSnapshot snapshot;snapshot.buildingId=building->id;
    snapshot.completed=building->getBuildStage()==building->getMaxBuildStage();
    snapshot.removing=DFHack::Buildings::markedForRemoval(building);
    snapshot.rows.reserve(building->contained_items.size());
    for(auto* held:building->contained_items) {
        if(!held||!held->item)return std::nullopt;
        auto* item=held->item;auto caption=buildingItemCaption(item);if(!caption)return std::nullopt;
        BuildingContentsRow row;row.id=item->id;row.role=static_cast<int32_t>(held->use_mode);
        row.caption=std::move(*caption);row.flags=item->flags.whole;
        row.itemType=static_cast<int32_t>(item->getType());
        DFHack::MaterialInfo material(item->getMaterial(),item->getMaterialIndex());
        if(material.isValid())row.materialToken=material.getToken();
        if(auto* subtype=DFHack::Items::getSubtypeDef(item->getType(),item->getSubtype()))row.subtypeRaw=subtype->id;
        row.countdown=item->stockpile_countdown;row.delay=item->stockpile_delay;
        row.forbid=item->flags.bits.forbid;row.dump=item->flags.bits.dump;
        row.melt=item->flags.bits.melt;row.hidden=item->flags.bits.hidden;
        row.canDump=native.canDump(item);row.canMelt=native.canMelt(item);
        for(auto* ref:item->specific_refs) {
            if(!ref)return std::nullopt;
            if(ref->type!=df::specific_ref_type::JOB)continue;
            auto* job=ref->data.job;if(!job)return std::nullopt;
            row.jobs.push_back({job->id,static_cast<int32_t>(job->job_type),job->flags.whole});
        }
        snapshot.rows.push_back(std::move(row));
    }
    snapshot.revision=buildingContentsRevision(snapshot);
    if(!validBuildingContents(snapshot))return std::nullopt;
    return snapshot;
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
