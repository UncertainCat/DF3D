#pragma once
#include "farm_native.h"
#include "building_item_transaction.h"
#include "item_transaction.h"
#include "df/building_stockpilest.h"
#include "df/buildingitemst.h"
#include "df/item.h"
#include "df/job.h"
#include "df/specific_ref.h"
#include "modules/Buildings.h"
#include "modules/Materials.h"
#include "modules/Items.h"
#include "df/itemdef.h"
#include "df/unit.h"
#include "df/descriptor_color.h"
#include "df/item_boxst.h"
#include "df/item_helmst.h"
#include "df/itemdef_helmst.h"
#include "df/item_armorst.h"
#include "df/itemdef_armorst.h"
#include "df/item_shoesst.h"
#include "df/itemdef_shoesst.h"
#include "df/item_pantsst.h"
#include "df/itemdef_pantsst.h"
#include "df/item_glovesst.h"
#include "df/itemdef_glovesst.h"
#include "df/item_instrumentst.h"
#include "df/itemdef_instrumentst.h"
#include "df/job_skill.h"
#include "df/instrument_flags.h"
#include "df/itemimprovement.h"

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
// Follow's visibility guard uses the effective position, including holders.
// This native designation reader only reads world map data; item.hidden is
// deliberately not a follow restriction (native interface-invisible flag).
inline std::optional<df::coord> itemFollowPosition(df::item* item) {
    using Designation=uint32_t (*)(df::world*,int16_t,int16_t,int16_t);
    static const auto designation=[]()->Designation {
        if(!farmFunctions())return nullptr;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x86;++i){hash^=base[0x7dc40+i];hash*=UINT64_C(1099511628211);}
        if(hash!=UINT64_C(0x396b58fb95c29f02))return nullptr;
        return reinterpret_cast<Designation>(base+0x7dc40);
    }();
    if(!designation||!df::global::world)return std::nullopt;
    const auto pos=itemPosition(item);
    if(!pos||!pos->isValid()||pos->x<0||pos->y<0||pos->z<0)return std::nullopt;
    if(designation(df::global::world,pos->x,pos->y,pos->z)&0x200)return std::nullopt;
    return pos;
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
using ItemBuildingHolder=ItemLocationLink;
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
// Independently owned semantic appearance, also used for off-map installed items.
inline std::optional<ItemInspectionAppearance> itemAppearance(df::item* item) {
    if(!item)return std::nullopt;
    ItemInspectionAppearance appearance;
    DFHack::MaterialInfo material(item->getMaterial(),item->getMaterialIndex());
    if(!material.isValid())return std::nullopt;appearance.materialToken=material.getToken();
    if(auto* subtype=DFHack::Items::getSubtypeDef(item->getType(),item->getSubtype()))appearance.subtypeRaw=subtype->id;
    const auto color=item->getColorWhetherDyedOrNot();
    if(color>=0){auto* descriptor=df::descriptor_color::find(color);if(!descriptor)return std::nullopt;appearance.colorToken=descriptor->id;}
    else if(color!=-1)return std::nullopt;
    if(item->getType()==df::item_type::INSTRUMENT) {
        auto* definition=virtual_cast<df::itemdef_instrumentst>(DFHack::Items::getSubtypeDef(item->getType(),item->getSubtype()));
        if(!definition)return std::nullopt;
        // Native c855b9..c856a9 uses definition music_skill and PLACED_AS_BUILDING.
        switch(definition->music_skill) {
        case df::job_skill::PLAY_KEYBOARD_INSTRUMENT:appearance.instrumentFamily=0;break;
        case df::job_skill::PLAY_STRINGED_INSTRUMENT:appearance.instrumentFamily=1;break;
        case df::job_skill::PLAY_WIND_INSTRUMENT:appearance.instrumentFamily=2;break;
        case df::job_skill::PLAY_PERCUSSION_INSTRUMENT:appearance.instrumentFamily=3;break;
        default:return std::nullopt;
        }
        appearance.instrumentPlaced=definition->flags.is_set(df::instrument_flags::PLACED_AS_BUILDING)?1:0;
    }
    appearance.stack=item->getStackSize();appearance.flags=(item->flags.bits.artifact?32:0)|(item->flags.bits.spider_web?64:0);
    if(appearance.materialToken.empty()||appearance.materialToken.size()>256||appearance.subtypeRaw.size()>128||appearance.colorToken.size()>128||appearance.stack<1)return std::nullopt;
    return appearance;
}
// Native item renderer153c06/153c20 resolves semantic general references.
// The displayed carrier prefers an item container over a unit; a building
// holder takes precedence over both in the caller. No UI state is an input.
inline std::optional<ItemCarrier> itemCarrier(df::item* item) {
    using FindItem=df::item* (*)(df::item*,int32_t);
    using FindUnit=df::unit* (*)(df::item*,int32_t);
    using Name=void (*)(df::unit*,std::string*,bool);
    struct Functions { FindItem container=nullptr;FindUnit unit=nullptr;Name name=nullptr; };
    static const auto functions=[]()->Functions {
        if(!farmFunctions())return {};
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        if(hash(0xcb15d0,0x63)!=UINT64_C(0x092eaa3e70951baf) ||
           hash(0xcb1640,0x63)!=UINT64_C(0x576ff7966803ca67) ||
           hash(0x1330c30,0x688)!=UINT64_C(0x0e165ee31decf426))return {};
        return {reinterpret_cast<FindItem>(base+0xcb15d0),reinterpret_cast<FindUnit>(base+0xcb1640),reinterpret_cast<Name>(base+0x1330c30)};
    }();
    if(!item||!functions.container||!functions.unit||!functions.name)return std::nullopt;
    ItemCarrier result;
    if(auto* container=functions.container(item,0xb)) {
        const auto caption=buildingItemCaption(container);if(!caption)return std::nullopt;
        result.kind=1;result.id=container->id;result.itemType=static_cast<int32_t>(container->getType());result.name=*caption;
        result.appearance=itemAppearance(container);if(!result.appearance)return std::nullopt;
    }else if(auto* unit=functions.unit(item,0x12)) {
        result.kind=2;result.id=unit->id;functions.name(unit,&result.name,false);
    }
    if(result.name.size()>512)return std::nullopt;
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
// Seed/bar virtual targets used by c75000. Pin both dispatch and complete
// leaf bodies before relying on type/quality/construction/image exclusions.
inline bool simpleItemDescriptionDispatch(df::item* item) {
    if(!item||!farmFunctions())return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto* table=*reinterpret_cast<const void* const*>(item);
    if(table!=base+0x16d06e0 && table!=base+0x16f6da0)return false;
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
        // BAR shares the seed exclusions: no image reference, construction,
        // maker, critter or face-up branch. Only type and material getters differ.
        // Native c7527b adjusts BAR grammar; all text still comes from c75000.
        for(const size_t table:{size_t(0x16d06e0),size_t(0x16f6da0)})for(auto pin:pins) {
            if(table==0x16f6da0) {
                if(pin.slot==0)pin={0,0x66e90,3,UINT64_C(0x58389c18233078ff)};
                else if(pin.slot==0x10 || pin.slot==0x38)
                    pin={pin.slot,0x5453d0,8,UINT64_C(0xe3389d0d7d85b545)};
            }
            if(*reinterpret_cast<const void* const*>(base+table+pin.slot)!=base+pin.target)return false;
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
// Native constructed-item dispatch. Lazy art owns semantic world records, not
// native UI state; observations are built after those native effects.
inline bool constructedItemDescriptionDispatch(df::item* item) {
    if(!item||!farmFunctions())return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto* table=*reinterpret_cast<const void* const*>(item);
    if(table!=base+0x1623198 && table!=base+0x16c6cf0 && table!=base+0x161dd98 &&
       table!=base+0x161f840 && table!=base+0x1621b88 && table!=base+0x1624818 &&
       table!=base+0x161edd8)return false;
    static const bool pinned=[base]() {
        struct Pin {size_t slot,target,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x0,0x28ab30,0x6,UINT64_C(0x22af2ed68286925e)},
            {0x10,0xfca10,0x8,UINT64_C(0xfc97df6278270fbf)},
            {0x18,0xfca20,0x7,UINT64_C(0x5ca530bad2557b5a)},
            {0x38,0xfca10,0x8,UINT64_C(0xfc97df6278270fbf)},
            {0x40,0xfca20,0x7,UINT64_C(0x5ca530bad2557b5a)},
            {0x1d8,0xfc240,0x8,UINT64_C(0xfa411eb4425a85fb)},
            {0x1e8,0xfcbe0,0x7,UINT64_C(0x8ab43c085bfbc45e)},
            {0x230,0x75f60,0x9,UINT64_C(0x6aa4478617a62f2e)},
            {0x448,0x67040,0x3,UINT64_C(0xa3703b1a918cfbeb)},
            {0x478,0xfc190,0x7,UINT64_C(0xf985d8151da86506)},
            {0x508,0xfcc20,0x8,UINT64_C(0xa97ace58e6e5d46d)},
            {0x590,0xfcc30,0x8,UINT64_C(0xc2d890ade184a267)},
            {0x5a8,0x67040,0x3,UINT64_C(0xa3703b1a918cfbeb)},
            {0x5e0,0xfc1c0,0x8,UINT64_C(0x2d52a42a21f4c0e4)},
            {0x6b0,0xcaeb90,0x13d,UINT64_C(0x6d30f4cd8ac4c4c7)},
            {0x6c0,0x67050,0x3,UINT64_C(0x62941518298855c4)},
            {0x750,0x66e60,0x6,UINT64_C(0x62d2efd24138f070)},
        };
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        // Clothing shares every listed constructed-item virtual except getType.
        // c75000 has no clothing-specific branch; subtype is a semantic raw.
        for(size_t table:{size_t(0x1623198),size_t(0x16c6cf0),size_t(0x161dd98),
                         size_t(0x161f840),size_t(0x1621b88),size_t(0x1624818),size_t(0x161edd8)})for(auto pin:pins) {
            if(table==0x16c6cf0 && pin.slot==0)pin={0,0x673c0,6,UINT64_C(0x6470dd592ae1062b)};
            if(pin.slot==0) {
                if(table==0x161dd98)pin={0,0x28a840,6,UINT64_C(0x3c0e712b7d27ecd8)};
                if(table==0x161f840)pin={0,0x7b5d0,6,UINT64_C(0x621a1caaf5147c67)};
                if(table==0x1621b88)pin={0,0x776a0,6,UINT64_C(0x556c3b8077c6c86a)};
                if(table==0x1624818)pin={0,0x722d0,6,UINT64_C(0xd1ead67b27153938)};
                if(table==0x161edd8)pin={0,0x28a950,6,UINT64_C(0x2f5f1000ffd7ac5b)};
            }
            if(*reinterpret_cast<const void* const*>(base+table+pin.slot)!=base+pin.target || hash(pin.target,pin.length)!=pin.hash)return false;
        }
        for(size_t table:{size_t(0x16c6cf0),size_t(0x161dd98),size_t(0x161f840),
                         size_t(0x1621b88),size_t(0x1624818),size_t(0x161edd8)})
            if(*reinterpret_cast<const void* const*>(base+table+8)!=base+0xfd0c0)return false;
        if(hash(0xfd0c0,12)!=UINT64_C(0xf68164ec06d8d50a))return false;
        if(hash(0x67520,0x6)!=UINT64_C(0x18580e5a3b056825))return false;
        if(hash(0x67540,0x6)!=UINT64_C(0x2505ef84b8531c22))return false;
        if(hash(0x14e1ec0,0xb68)!=UINT64_C(0x1d38184423ba8a35))return false;
        if(hash(0x14d1920,0x459)!=UINT64_C(0xf48e28715360ed9a))return false;
        if(hash(0x14add70,0x12f)!=UINT64_C(0x01f897b15772d540))return false;
        struct Improvement {size_t table,image,type,length;uint64_t hash;};
        constexpr Improvement improvements[]={
            {0x1702ce8,0xcabd70,0x66e90,0x3,UINT64_C(0x58389c18233078ff)},
            {0x16f5e48,0x66e90,0x67520,0x6,UINT64_C(0x18580e5a3b056825)},
            {0x16fd188,0x66e90,0x67530,0x6,UINT64_C(0xe59b01b045c53219)},
            {0x16f7ca0,0x66e90,0x7b7a0,0x6,UINT64_C(0x57c0fc2ead8fec2e)},
            {0x16f8c50,0x66e90,0x67500,0x6,UINT64_C(0x31b5d0af35a4361f)},
            {0x16ff810,0xcabd70,0x671f0,0x6,UINT64_C(0x8a7e08d8a2d0223a)},
            {0x16f8bf8,0x66e90,0x673c0,0x6,UINT64_C(0x6470dd592ae1062b)},
            {0x16f0a68,0x66e90,0x67270,0x6,UINT64_C(0x7dce27ae257f083d)},
            {0x16f4e98,0x66e90,0x67a50,0x6,UINT64_C(0xfef8c40540640013)},
            {0x17034c0,0x66e90,0x676d0,0x6,UINT64_C(0x972bea03201dd637)},
            {0x16fe860,0x66e90,0x67540,0x6,UINT64_C(0x2505ef84b8531c22)},
            {0x16f8d58,0xcabd70,0x67860,0x6,UINT64_C(0xa3dbcb2d9d6ef034)},
            {0x16ff7b8,0x66e90,0x67a40,0x6,UINT64_C(0x0ba8a52fbdb51a10)},
            {0x16f4ef0,0x66e90,0x67b90,0x6,UINT64_C(0xf24ae2dac3164c16)},
            {0x16fa430,0x66e90,0x67490,0x6,UINT64_C(0x711ebe83a82eba28)},
        };
        for(const auto& pin:improvements)if(*reinterpret_cast<const void* const*>(base+pin.table)!=base+pin.image ||
            *reinterpret_cast<const void* const*>(base+pin.table+0x28)!=base+pin.type || hash(pin.type,pin.length)!=pin.hash)return false;
        if(hash(0x66e90,0x3)!=UINT64_C(0x58389c18233078ff))return false;
        if(hash(0xcabd70,0x9b)!=UINT64_C(0x9d40a9da4ede71df))return false;
        if(hash(0xcabb50,0x21e)!=UINT64_C(0xee57b9bc216cc548))return false;
        if(hash(0xcc83e0,0xe6)!=UINT64_C(0x153208913b9388eb))return false;
        if(hash(0x1453130,0xf8)!=UINT64_C(0x8908ab4dc6f55824))return false;
        if(hash(0x1451b10,0x161c)!=UINT64_C(0x5afdbfca1604e13b))return false;
        return true;
    }();
    if(!pinned)return false;
    if(table==base+0x16c6cf0) {
        const auto* instrument=static_cast<df::item_instrumentst*>(item);
        // c7691f reads component definitions; c795a9 appends the definition's
        // native description. Both are semantic raw data, never UI scratch.
        if(!instrument->subtype || DFHack::Items::getSubtypeDef(df::item_type::INSTRUMENT,item->getSubtype())!=instrument->subtype)return false;
    }
    const df::itemdef* clothingSubtype=nullptr;
    if(table==base+0x161dd98)clothingSubtype=static_cast<df::item_helmst*>(item)->subtype;
    if(table==base+0x161f840)clothingSubtype=static_cast<df::item_armorst*>(item)->subtype;
    if(table==base+0x1621b88)clothingSubtype=static_cast<df::item_shoesst*>(item)->subtype;
    if(table==base+0x1624818)clothingSubtype=static_cast<df::item_pantsst*>(item)->subtype;
    if(table==base+0x161edd8)clothingSubtype=static_cast<df::item_glovesst*>(item)->subtype;
    if(table!=base+0x1623198 && table!=base+0x16c6cf0 &&
       (!clothingSubtype || DFHack::Items::getSubtypeDef(item->getType(),item->getSubtype())!=clothingSubtype))return false;
    const auto* box=static_cast<df::item_constructed*>(item);
    if(int(box->quality)<0 || int(box->quality)>int(df::item_quality::Artifact))return false;
    for(const auto* improvement:box->improvements) {
        if(!improvement)return false;
        const auto* table=*reinterpret_cast<const void* const*>(improvement);
        if(table!=base+0x1702ce8 && table!=base+0x16f5e48 && table!=base+0x16fd188 && table!=base+0x16f7ca0 && table!=base+0x16f8c50 && table!=base+0x16ff810 && table!=base+0x16f8bf8 && table!=base+0x16f0a68 && table!=base+0x16f4e98 && table!=base+0x17034c0 && table!=base+0x16fe860 && table!=base+0x16f8d58 && table!=base+0x16ff7b8 && table!=base+0x16f4ef0 && table!=base+0x16fa430)return false;
        if(int(improvement->quality)<0 || int(improvement->quality)>int(df::item_quality::Artifact))return false;
    }
    return true;
}
inline bool boxItemDescriptionDispatch(df::item* item) {
    return item && item->getType()==df::item_type::BOX && constructedItemDescriptionDispatch(item);
}
inline bool itemDescriptionDispatch(df::item* item) {
    return simpleItemDescriptionDispatch(item) || constructedItemDescriptionDispatch(item);
}
// Native sheet options with owned output. BOX may initialize semantic art;
// retain native effects and observe item facts only after formatting.
inline std::optional<std::string> itemDescription(df::item* item) {
    using Describe=void (*)(df::item*,std::string*,bool,bool,bool,int32_t);
    if(!itemDescriptionDispatch(item))return std::nullopt;
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
inline std::optional<ItemFacts> itemFacts(df::item* item) {
    const auto& native=buildingItemFunctions();if(!native||!item)return std::nullopt;
    auto caption=buildingItemCaption(item);if(!caption)return std::nullopt;
    ItemFacts row;row.id=item->id;
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
    return row;
}
// Item renderer153c72..153da5 scans STOCKPILE forward and calls5587b0.
// Generic a82b00 scans in reverse and has additional occupancy filtering.
inline std::optional<ItemLocationLink> itemStockpile(df::coord position) {
    using Contains=uint8_t (*)(df::building*,int16_t,int16_t,int16_t);
    static const auto contains=[]()->Contains {
        if(!farmFunctions())return nullptr;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x79;++i){hash^=base[0x5587b0+i];hash*=UINT64_C(1099511628211);}
        if(hash!=UINT64_C(0x14b4f3f138690067))return nullptr;
        return reinterpret_cast<Contains>(base+0x5587b0);
    }();
    if(!contains||!df::global::world)return std::nullopt;
    for(auto* pile:df::global::world->buildings.other.STOCKPILE) {
        if(!pile)return std::nullopt;
        if(!contains(pile,position.x,position.y,position.z))continue;
        ItemLocationLink link;link.id=pile->id;link.type=static_cast<int32_t>(pile->getType());
        pile->getName(&link.name);return link;
    }
    return ItemLocationLink{};
}
inline std::optional<ItemObservation> observeItem(df::item* item) {
    if(!itemDescriptionDispatch(item))return std::nullopt;
    const auto position=itemFollowPosition(item);if(!position)return std::nullopt;
    const auto description=itemDescription(item),weight=itemWeightCaption(item);
    const auto holder=itemBuildingHolder(item),stockpile=itemStockpile(*position);
    if(!description||!weight||!holder||!stockpile)return std::nullopt;
    // Observe facts after native lazy formatting, without borrowing a UI owner.
    auto facts=itemFacts(item);if(!facts)return std::nullopt;
    ItemObservation value;value.item=std::move(*facts);value.weight=*weight;value.description=*description;
    if(value.item.itemType==30||value.item.itemType==13){value.appearance=itemAppearance(item);if(!value.appearance)return std::nullopt;}
    if(holder->id>=0)value.buildingHolder=*holder;
    else {const auto carrier=itemCarrier(item);if(!carrier)return std::nullopt;if(carrier->kind)value.carrier=*carrier;}
    if(stockpile->id>=0){
        auto* pile=virtual_cast<df::building_stockpilest>(df::building::find(stockpile->id));if(!pile)return std::nullopt;
        value.stockpile=*stockpile;value.stockpileCategories=pile->settings.flags.whole;
    }
    value.revision=itemObservationRevision(value);
    if(!validItemObservation(value))return std::nullopt;
    return value;
}
inline std::optional<BuildingContentsSnapshot> buildingContents(df::building_actual* building) {
    const auto& native=buildingItemFunctions();if(!native||!building)return std::nullopt;
    BuildingContentsSnapshot snapshot;snapshot.buildingId=building->id;
    snapshot.completed=building->getBuildStage()==building->getMaxBuildStage();
    snapshot.removing=DFHack::Buildings::markedForRemoval(building);
    snapshot.rows.reserve(building->contained_items.size());
    for(auto* held:building->contained_items) {
        if(!held||!held->item)return std::nullopt;
        auto facts=itemFacts(held->item);if(!facts)return std::nullopt;
        BuildingContentsRow row;static_cast<ItemFacts&>(row)=std::move(*facts);
        row.role=static_cast<int32_t>(held->use_mode);
        if(row.itemType==13||row.itemType==30){row.appearance=itemAppearance(held->item);if(!row.appearance)return std::nullopt;}
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
