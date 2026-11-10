#pragma once
#include "farm_native.h"
#include "appearance.h"
#include "zone_native.h"
#include "building_item_transaction.h"
#include "item_transaction.h"
#include "item_owner_native.h"
#include "item_uses_native.h"
#include "df/building_stockpilest.h"
#include "df/building_floodgatest.h"
#include "df/building_doorst.h"
#include "df/buildingitemst.h"
#include "df/item.h"
#include "df/item_coinst.h"
#include "df/item_slabst.h"
#include "df/item_critter.h"
#include "df/coin_batch.h"
#include "df/world.h"
#include "df/world_data.h"
#include "df/world_object_data.h"
#include "df/job.h"
#include "df/specific_ref.h"
#include "modules/Buildings.h"
#include "modules/Materials.h"
#include "modules/Items.h"
#include "df/itemdef.h"
#include "df/unit.h"
#include "df/descriptor_color.h"
#include "df/descriptor_pattern.h"
#include "df/item_boxst.h"
#include "df/item_toolst.h"
#include "df/itemdef_toolst.h"
#include "df/item_toyst.h"
#include "df/itemdef_toyst.h"
#include "df/item_siegeammost.h"
#include "df/itemdef_siegeammost.h"
#include "df/item_trapcompst.h"
#include "df/itemdef_trapcompst.h"

#include "df/item_foodst.h"
#include "df/itemdef_foodst.h"
#include "df/food_ingredientst.h"
#include "df/item_ammost.h"
#include "df/item_weaponst.h"
#include "df/item_shieldst.h"
#include "df/itemdef_weaponst.h"
#include "df/itemdef_shieldst.h"
#include "df/itemdef_ammost.h"
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
#include "df/squad.h"
#include "df/squad_ammo_spec.h"
#include "df/historical_entity.h"
#include "df/game_mode.h"
#include "df/general_ref.h"
#include "df/material.h"
#include "df/material_flags.h"
#include "df/tool_uses.h"
#include "df/item_powder_miscst.h"
#include "df/plant_raw.h"

namespace df3d_production {
// Native BIN c7e08d..c7e109: material resolver, solid-state pattern, first
// descriptor color. BARREL additionally uses actual material and liquid state.
// Some item classes leave their color virtual at -1.
inline std::optional<int32_t> itemContentsMaterialColor(df::item* item,bool actual=false,int state=0) {
    using Resolve=df::material* (*)(df::world*,int16_t,int32_t);
    static const auto resolve=[]()->Resolve {
        if(!farmFunctions())return nullptr;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x12f;++i){hash^=base[0x14add70+i];hash*=UINT64_C(1099511628211);}
        if(hash!=UINT64_C(0x01f897b15772d540))return nullptr;
        return reinterpret_cast<Resolve>(base+0x14add70);
    }();
    if(!resolve || !item)return std::nullopt;
    static_assert(offsetof(df::material,state_color)==0x9c);
    static_assert(offsetof(df::descriptor_pattern,colors)==0x20);
    auto* material=resolve(df::global::world,actual?item->getActualMaterial():item->getMaterial(),
        actual?item->getActualMaterialIndex():item->getMaterialIndex());
    if(!material)return -1;
    auto* pattern=df::descriptor_pattern::find(material->state_color[state]);
    if(!pattern || pattern->colors.empty())return -1;
    return int32_t(pattern->colors.front());
}
// BAG c7e33a..c7e4c3 selects only the last item reference, even when it
// resolves to null, and does not consult the container flag. This is distinct
// from BIN's all-reference consensus and dyed contents color.
inline std::optional<ItemContainerContentsFacts> itemBagContents(df::item* item) {
    if(!item || !farmFunctions() || item->getType()!=df::item_type::BAG)return std::nullopt;
    ItemContainerContentsFacts result;result.container=item->flags.bits.container;
    for(auto it=item->general_refs.rbegin();it!=item->general_refs.rend();++it) {
        auto* ref=*it;if(!ref)return std::nullopt;
        if(ref->getType()!=df::general_ref_type::CONTAINS_ITEM)continue;
        ItemContainerContentFacts entry;
        if(auto* child=ref->getItem()) {
            const auto type=child->getType();entry.itemType=int16_t(type);
            if(type==df::item_type::SEEDS || type==df::item_type::PLANT || type==df::item_type::POWDER_MISC) {
                std::optional<int32_t> color;
                if(type==df::item_type::POWDER_MISC) {
                    auto* powder=virtual_cast<df::item_powder_miscst>(child);if(!powder)return std::nullopt;
                    static_assert(offsetof(df::item_powder_miscst,dye_profile)==0xc8);
                    if(powder->dye_profile.color_index!=-1)color=powder->dye_profile.color_index;
                }
                if(!color)color=itemContentsMaterialColor(child,true);
                if(!color)return std::nullopt;
                if(*color>=0 && *color<255) {
                    auto* descriptor=df::descriptor_color::find(*color);if(!descriptor)return std::nullopt;
                    entry.colorToken=descriptor->id;
                    if(entry.colorToken.size()>128)return std::nullopt;
                }
            }
        }
        result.entries.push_back(std::move(entry));break;
    }
    return result;
}
// BARREL c7c500..c7c900: owned simulation facts only. Do not call the
// packed selector: its later branches read graphics vectors and mutate RNG.
inline std::optional<ItemContainerContentsFacts> itemBarrelContents(df::item* item) {
    if(!item || !farmFunctions() || item->getType()!=df::item_type::BARREL)return std::nullopt;
    ItemContainerContentsFacts result;result.container=item->flags.bits.container;
    result.materialInorganic=item->getActualMaterial()==0?1:0;
    const auto assignColor=[](const std::optional<int32_t>& color,std::string& token) {
        if(!color)return false;
        if(*color>=0 && *color<255) {
            auto* descriptor=df::descriptor_color::find(*color);if(!descriptor)return false;
            token=descriptor->id;if(token.size()>128)return false;
        }
        return true;
    };
    if(!assignColor(itemContentsMaterialColor(item,true),result.solidColor))return std::nullopt;
    if(!result.container)return result;
    for(auto it=item->general_refs.rbegin();it!=item->general_refs.rend();++it) {
        auto* ref=*it;if(!ref)return std::nullopt;
        if(ref->getType()!=df::general_ref_type::CONTAINS_ITEM)continue;
        ItemContainerContentFacts entry;
        if(auto* child=ref->getItem()) {
            const auto type=child->getType();entry.itemType=int16_t(type);
            entry.liquid=child->isLiquid();
            if(entry.liquid && !assignColor(itemContentsMaterialColor(child,true,1),entry.colorToken))return std::nullopt;
            if(type==df::item_type::PLANT || type==df::item_type::PLANT_GROWTH) {
                if(auto* plant=df::plant_raw::find(child->getMaterialIndex()))
                    entry.subterraneanPlant=plant->flags.is_set(df::plant_raw_flags::BIOME_SUBTERRANEAN_WATER) ||
                        plant->flags.is_set(df::plant_raw_flags::BIOME_SUBTERRANEAN_CHASM) ||
                        plant->flags.is_set(df::plant_raw_flags::BIOME_SUBTERRANEAN_LAVA);
            }
        }
        result.entries.push_back(std::move(entry));break;
    }
    return result;
}
// Direct simulation references and native virtual getters, never the item
// renderer's packed graphics keys or cache. Preserve reference order and
// unknown/unit entries because they participate in mixed-content rendering.
inline std::optional<ItemContainerContentsFacts> itemContainerContents(df::item* item) {
    if(!item || !farmFunctions() || item->getType()!=df::item_type::BIN)return std::nullopt;
    ItemContainerContentsFacts result;result.container=item->flags.bits.container;
    if(!result.container)return result;
    for(auto* ref:item->general_refs) {
        if(!ref)return std::nullopt;
        const auto type=ref->getType();
        if(type!=df::general_ref_type::CONTAINS_ITEM && type!=df::general_ref_type::CONTAINS_UNIT)continue;
        ItemContainerContentFacts entry;
        if(type==df::general_ref_type::CONTAINS_ITEM)if(auto* child=ref->getItem()) {
            const auto kind=child->getType();entry.itemType=int16_t(kind);
            DFHack::MaterialInfo material(child->getMaterial(),child->getMaterialIndex());
            if(material.isValid()) {
                entry.materialToken=material.getToken();
                entry.metal=material.material->flags.is_set(df::material_flags::IS_METAL);
            }
            entry.coal=child->getMaterial()==7;
            // The native color getter follows dye/covering improvements before
            // base material for constructed items (AMMO virtual214,
            // caeb90..caeccc). Other families need the native BIN fallback.
            auto color=child->getColorWhetherDyedOrNot();
            if(color==-1) {
                const auto fallback=itemContentsMaterialColor(child);
                if(!fallback)return std::nullopt;
                color=*fallback;
            }
            if(color>=0 && color<255) {
                auto* descriptor=df::descriptor_color::find(color);
                if(!descriptor)return std::nullopt;
                entry.colorToken=descriptor->id;
            }
            switch(kind) {
            case df::item_type::ARMOR:case df::item_type::SHOES:case df::item_type::HELM:
            case df::item_type::GLOVES:case df::item_type::PANTS:
                entry.effectiveArmorLevel=child->getEffectiveArmorLevel();break;
            case df::item_type::BAG:
                if(child->flags.bits.container)for(auto* nested:child->general_refs) {
                    if(!nested)return std::nullopt;
                    if(nested->getType()==df::general_ref_type::CONTAINS_ITEM)
                        if(auto* value=nested->getItem();value && value->getType()==df::item_type::POWDER_MISC) {
                            entry.containsPowder=true;break;
                        }
                }
                break;
            case df::item_type::TOOL:
                entry.rollsSheets=child->hasToolUse(df::tool_uses::ROLL_UP_SHEET);
                entry.protectsFoldedSheets=child->hasToolUse(df::tool_uses::PROTECT_FOLDED_SHEETS);
                entry.containsWriting=child->hasToolUse(df::tool_uses::CONTAIN_WRITING);break;
            default:break;
            }
            if(entry.materialToken.size()>256 || entry.colorToken.size()>128)return std::nullopt;
        }
        result.entries.push_back(std::move(entry));
    }
    return result;
}
// Item-sheet153daa..154052 derives allocation from simulation equipment, not
// the native sheet. Preserve its assigned-list gate and hunter precedence.
inline std::optional<ItemAmmunitionAssignment> itemAmmunitionAssignment(df::item* item) {
    if(!item || !farmFunctions() || !df::global::plotinfo || !df::global::gamemode)return std::nullopt;
    ItemAmmunitionAssignment result;
    if(*df::global::gamemode!=df::game_mode::DWARF || item->getType()!=df::item_type::AMMO)return result;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[base]{
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0xb9f70,0x25,UINT64_C(0xe6e732b038db044e)},
            {0x75500,0x6f,UINT64_C(0x223b74ce0823a28d)},
            {0xa946e0,0x7c2,UINT64_C(0xdbc3db5f052419ee)}};
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return std::string(reinterpret_cast<char*>(base+0x15fe220))=="Assigned to hunters" &&
            std::string(reinterpret_cast<char*>(base+0x15fe210))=="Assigned to ";
    }();
    if(!supported)return std::nullopt;
    const auto contains=[base](int32_t id,const std::vector<int32_t>& ids){
        return reinterpret_cast<int32_t(*)(int32_t,const std::vector<int32_t>*)>(base+0xb9f70)(id,&ids)!=-1;};
    const auto& equipment=df::global::plotinfo->equipment;
    if(!contains(item->id,equipment.items_assigned[int(df::item_type::AMMO)]))return result;
    for(const auto* spec:equipment.hunter_ammunition){if(!spec)return std::nullopt;
        if(contains(item->id,spec->assigned)){result.kind=1;result.caption=reinterpret_cast<char*>(base+0x15fe220);return result;}}
    const auto* entity=df::global::plotinfo->main.fortress_entity;if(!entity)return std::nullopt;
    for(auto id:entity->squads){auto* squad=df::squad::find(id);if(!squad)continue;
        for(const auto* spec:squad->ammo.ammunition){if(!spec)return std::nullopt;
            if(!contains(item->id,spec->assigned))continue;
            result.kind=2;result.squadId=id;result.caption=reinterpret_cast<char*>(base+0x15fe210);
            std::string name=squad->alias;
            if(name.empty()){auto owned=squad->name;reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&owned,&name,true,false);}
            result.caption+=name;return result;}}
    return result;
}
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
    CorpseCaptionScope corpseScope(item);if(!corpseScope.ready)return std::nullopt;
    std::string result;caption(item,&result,false,-1);return result;
}
using ItemBuildingHolder=ItemLocationLink;
// Native item sheet153bec resolves BUILDING_HOLDER through the semantic general
// reference lookup. Renderer1567ed calls holder->getName into owned text storage.
using FindItemBuilding=df::building* (*)(df::item*,int32_t);
inline FindItemBuilding itemBuildingLookup() {
    using Find=FindItemBuilding;
    static const auto find=[]()->Find {
        if(!farmFunctions())return nullptr;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x63;++i){hash^=base[0xcb16b0+i];hash*=UINT64_C(1099511628211);}
        if(hash!=UINT64_C(0xaf4453f988ab95f7))return nullptr;
        return reinterpret_cast<Find>(base+0xcb16b0);
    }();
    return find;
}
inline std::optional<ItemBuildingHolder> itemBuildingHolder(df::item* item) {
    const auto find=itemBuildingLookup();
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
inline DFHack::MaterialInfo itemInspectionMaterial(df::item* item) {
    // Creature items expose race/caste through nominal getters. Use their
    // native actual material consistently in both item facts and appearance.
    const auto type=item->getType();
    const bool actual=type==df::item_type::FISH || type==df::item_type::FISH_RAW ||
        type==df::item_type::EGG || type==df::item_type::REMAINS ||
        type==df::item_type::PET || type==df::item_type::VERMIN ||
        type==df::item_type::CORPSE || type==df::item_type::CORPSEPIECE;
    return DFHack::MaterialInfo(actual?item->getActualMaterial():item->getMaterial(),
        actual?item->getActualMaterialIndex():item->getMaterialIndex());
}
inline std::optional<ItemAppearanceRecipe> ownedItemRecipe(const df3d_appearance::Result& source) {
    if(source.layers.empty() || source.layers.size()>256)return std::nullopt;
    ItemAppearanceRecipe recipe;
    const auto intern=[](auto& names,const std::string& name){
        const auto it=std::find(names.begin(),names.end(),name);
        if(it!=names.end())return int32_t(it-names.begin());
        names.push_back(name);return int32_t(names.size()-1);
    };
    for(const auto& l:source.layers){
        if(!l.page)return std::nullopt;
        recipe.layers.push_back({intern(recipe.pages,df3d_appearance::pageToken(l.page)),l.tileX,l.tileY,l.cellsX,l.cellsY,
            l.palette?intern(recipe.palettes,df3d_appearance::paletteInstallPath(l.palette)):65535,l.row,l.keyRow,l.offX,l.offY});
    }
    size_t bytes=0;if(!validItemRecipe(recipe,bytes))return std::nullopt;
    return recipe;
}
inline std::optional<ItemInspectionAppearance> itemAppearance(df::item* item) {
    if(!item)return std::nullopt;
    ItemInspectionAppearance appearance;
    if(item->getType()==df::item_type::CORPSE) {
        df3d_appearance::Result recipe;
        if(df3d_appearance::resolveCorpseItemSelector(item,recipe))appearance.corpseSelector=ownedItemRecipe(recipe);
    }
    if(item->getType()==df::item_type::CORPSEPIECE) {
        df3d_appearance::Result recipe;
        const auto art=corpsePieceArtwork(item);
        if(art && df3d_appearance::resolveOriginalItemTile(art->tile,recipe,art->color)) {
            bool ready=true;
            if(art->overlay>0) {
                df3d_appearance::Result overlay;
                ready=df3d_appearance::resolveOriginalItemTile(art->overlay,overlay,art->overlayColor);
                if(ready)recipe.layers.insert(recipe.layers.end(),overlay.layers.begin(),overlay.layers.end());
            }
            if(ready)appearance.corpseSelector=ownedItemRecipe(recipe);
        }
    }
    if(item->getType()==df::item_type::PET || item->getType()==df::item_type::VERMIN){
        df3d_appearance::Result recipe;
        if(df3d_appearance::resolveCritterItemPortrait(item,recipe))appearance.portrait=ownedItemRecipe(recipe);
    }
    const auto material=itemInspectionMaterial(item);
    if(!material.isValid())return std::nullopt;appearance.materialToken=material.getToken();
    if(auto* subtype=DFHack::Items::getSubtypeDef(item->getType(),item->getSubtype()))appearance.subtypeRaw=subtype->id;
    const auto nativeColor=item->getType()==df::item_type::BAG?itemContentsMaterialColor(item):std::optional<int32_t>(item->getColorWhetherDyedOrNot());
    if(!nativeColor)return std::nullopt;
    const auto color=item->getType()==df::item_type::BAG && (*nativeColor<0 || *nativeColor>=255)?-1:*nativeColor;
    if(color>=0){auto* descriptor=df::descriptor_color::find(color);if(!descriptor)return std::nullopt;appearance.colorToken=descriptor->id;}
    else if(color!=-1)return std::nullopt;
    if(item->getType()==df::item_type::BUCKET) {
        // Native c7d7a0..c7d8af: last qualifying liquid reference, without
        // a container-flag gate. Unlike BIN, always use solid material color.
        appearance.bucketLiquid=0;
        for(auto it=item->general_refs.rbegin();it!=item->general_refs.rend();++it) {
            auto* ref=*it;if(!ref)return std::nullopt;
            if(ref->getType()!=df::general_ref_type::CONTAINS_ITEM)continue;
            auto* child=ref->getItem();if(!child || !child->isLiquid())continue;
            appearance.bucketLiquid=1;
            const auto color=itemContentsMaterialColor(child);if(!color)return std::nullopt;
            if(*color>=0 && *color<255) {
                auto* descriptor=df::descriptor_color::find(*color);if(!descriptor)return std::nullopt;
                appearance.bucketLiquidColor=descriptor->id;
                if(appearance.bucketLiquidColor.size()>128)return std::nullopt;
            }
            break;
        }
    }
    if(item->getType()==df::item_type::SLAB) {
        const auto engraving=static_cast<df::item_slabst*>(item)->engraving_type;
        if(int(engraving)<-1 || int(engraving)>26)return std::nullopt;
        appearance.slabEngraving=int8_t(engraving);
    }
    if(item->getType()==df::item_type::CHAIN) {
        const auto restraint=df3d_area::nativeZoneAnimalRestraint(*item);if(!restraint)return std::nullopt;
        appearance.restraintRope=restraint->rope?1:0;appearance.restraintSolidColor=restraint->solidColor;
    }
    if(item->getType()==df::item_type::CAGE) {
        const auto cage=df3d_area::nativeZoneAnimalContainer(*item);if(!cage)return std::nullopt;
        appearance.cageMaterialFamily=int8_t(cage->materialFamily);appearance.cageOccupantEntity=int8_t(cage->occupantEntity);
        appearance.cageOccupantId=cage->occupantId;appearance.cageSolidColor=cage->solidColor;
        df3d_appearance::Result recipe;
        const bool resolved=appearance.cageOccupantEntity==1?df3d_appearance::resolveUnitSelector(df::unit::find(cage->occupantId),recipe):
            appearance.cageOccupantEntity==2 && df3d_appearance::resolveCritterItemSelector(df::item::find(cage->occupantId),recipe);
        if(resolved)appearance.cageOccupant=ownedItemRecipe(recipe);
    }
    if(item->getType()==df::item_type::DOOR) {
        // Native c80c7c..c80cbc: BUILDING_HOLDER, forbidden and positive
        // close_timer (not the closed bit). Wear comes from virtual59.
        const auto find=itemBuildingLookup();if(!find)return std::nullopt;
        static_assert(offsetof(df::building_doorst,door_flags)==0x148);
        static_assert(offsetof(df::building_doorst,close_timer)==0x14a);
        auto* door=virtual_cast<df::building_doorst>(find(item,0x24));
        const auto wear=item->getWear();if(wear<0 || wear>3)return std::nullopt;
        appearance.doorOpen=door && door->close_timer>0 ? 1 : 0;
        appearance.doorForbidden=door && door->door_flags.bits.forbidden ? 1 : 0;
        appearance.doorWear=int8_t(wear);
    }
    if(item->getType()==df::item_type::FLOODGATE) {
        // Native c81fc7..c81ffa: only a linked floodgate's open flag changes
        // the item variant. Loose/workshop-held items use the closed variant.
        const auto find=itemBuildingLookup();if(!find)return std::nullopt;
        auto* holder=find(item,0x24);
        auto* gate=virtual_cast<df::building_floodgatest>(holder);
        appearance.floodgateOpen=gate && !gate->gate_flags.bits.closed ? 1 : 0;
    }
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
    if(item->getType()==df::item_type::BIN){appearance.contents=itemContainerContents(item);if(!appearance.contents || appearance.contents->entries.size()>4096)return std::nullopt;}
    if(item->getType()==df::item_type::BAG){appearance.contents=itemBagContents(item);if(!appearance.contents)return std::nullopt;}
    if(item->getType()==df::item_type::BARREL){appearance.contents=itemBarrelContents(item);if(!appearance.contents)return std::nullopt;}
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
    if(table!=base+0x16d06e0 && table!=base+0x16f6da0 && table!=base+0x15fa918 &&
       table!=base+0x16cad20 && table!=base+0x16b7520 && table!=base+0x16f0ac0 && table!=base+0x16c6570 && table!=base+0x16c9420 &&
       table!=base+0x167b4d0 && table!=base+0x1659a68 && table!=base+0x16c34a0 && table!=base+0x16bdbc0 &&
       table!=base+0x16ba7c0 && table!=base+0x1655c40 && table!=base+0x16b8e88 && table!=base+0x16f2140 &&
       table!=base+0x16c7ab0 && table!=base+0x16589e0 && table!=base+0x16b6698 && table!=base+0x16554c0 && table!=base+0x16bbad0 && table!=base+0x165cd68 &&
       table!=base+0x161d330 && table!=base+0x16f4718 && table!=base+0x16f8db0 && table!=base+0x16f3040)return false;
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
        // BLOCKS shares the seed leaf targets except getType. c750f0 routes
        // its material wording through the owned semantic material formatter.
        // Rough/cut gems share BLOCKS' wording branch c750d2..c75150.
        // WOOD c750af and BOULDER c75244 adjust grammar from owned flags
        // and material getters only. All other used virtuals match SEEDS.
        for(const size_t table:{size_t(0x16d06e0),size_t(0x16f6da0),size_t(0x15fa918),
            size_t(0x16cad20),size_t(0x16b7520),size_t(0x16f0ac0),size_t(0x16c6570),size_t(0x16c9420),size_t(0x167b4d0),size_t(0x1659a68),size_t(0x16c34a0),size_t(0x16bdbc0),size_t(0x16ba7c0),size_t(0x1655c40),size_t(0x16b8e88),size_t(0x16f2140),size_t(0x16c7ab0),size_t(0x16589e0),size_t(0x16b6698),size_t(0x16554c0),size_t(0x16bbad0),size_t(0x165cd68),size_t(0x161d330),size_t(0x16f4718),size_t(0x16f8db0),size_t(0x16f3040)})for(auto pin:pins) {
            // MEAT/PLANT/CHEESE/GLOB share all used SEEDS virtuals except type.
            // c751f7..c75239 chooses food grammar; PLANT c75073 reads raw flag4
            // through the pinned14d880 leaf. GLOB skips contaminants at c792de.
            if(pin.slot==0) {
                if(table==0x161d330)pin={0,0x2896a0,6,UINT64_C(0x466599a7c4a924a9)};
                if(table==0x16f4718)pin={0,0x8f47f0,6,UINT64_C(0x456673e45454fae8)};
                if(table==0x16f8db0)pin={0,0x5c1710,6,UINT64_C(0xf94da4e564795ce2)};
                if(table==0x16f3040)pin={0,0x8f5330,6,UINT64_C(0x1d040fb6a69bef2d)};
                if(table==0x167b4d0)pin={0,0x28cb50,6,UINT64_C(0x9f2dc9d131d5032c)};
                if(table==0x1659a68)pin={0,0x545970,6,UINT64_C(0x5314fad241f96526)};
                if(table==0x16c34a0)pin={0,0x8f2400,6,UINT64_C(0xb9e2b710f1eb72d9)};
                if(table==0x16bdbc0)pin={0,0x106ef0,6,UINT64_C(0x5215dd0ed1a548fd)};
                if(table==0x16cad20)pin={0,0x67a40,6,UINT64_C(0x0ba8a52fbdb51a10)};
                if(table==0x16b7520)pin={0,0x67a50,6,UINT64_C(0xfef8c40540640013)};
                if(table==0x16f0ac0)pin={0,0x67520,6,UINT64_C(0x18580e5a3b056825)};
                if(table==0x16c6570)pin={0,0x67500,6,UINT64_C(0x31b5d0af35a4361f)};
            }
            // Liquid/powder materials use c0/c4 fields. Powder c78d7a reads
            // its raw dye descriptor through the already pinned145c2b0 helper;
            // LIQUID_MISC skips contaminants at c792f1. Other dispatch is SEEDS.
            if(table==0x16ba7c0 || table==0x1655c40 || table==0x16b8e88 || table==0x16f2140) {
                if(pin.slot==0) {
                    if(table==0x16f2140)pin={0,0x1018f0,6,UINT64_C(0x04a5e3251c520944)};
                    if(table==0x16ba7c0)pin={0,0x7dedf0,6,UINT64_C(0xd3407965ec8a40d3)};
                    if(table==0x1655c40)pin={0,0x5450f0,6,UINT64_C(0x6b739f63cc4416f7)};
                    if(table==0x16b8e88)pin={0,0x104610,6,UINT64_C(0xc692983b6f3c8cd6)};
                } else if(pin.slot==0x10 || pin.slot==0x38)
                    pin={pin.slot,0xfcc30,8,UINT64_C(0xc2d890ade184a267)};
                else if(pin.slot==0x18 || pin.slot==0x40)
                    pin={pin.slot,0x545100,7,UINT64_C(0x57f92f5e66bef452)};
            }
            // Fish material fields are race/caste, not a material pair.
            // Actual-material leaves read creature caste raws with bounds checks;
            // caste -1 selects the first caste. Neither leaf uses native UI state.
            if(table==0x16c7ab0 || table==0x16589e0 || table==0x16b6698 || table==0x16554c0 || table==0x16bbad0 || table==0x165cd68) {
                if(pin.slot==0)pin=table==0x16c7ab0
                    ?Pin{0,0x100a70,6,UINT64_C(0x927fe8a6b4874f2f)}
                    :Pin{0,0x67180,6,UINT64_C(0x85d0077c37363532)};
                else if(pin.slot==0x18)pin={pin.slot,0x5453b0,8,UINT64_C(0x6b157bd3663c271d)};
                else if(pin.slot==0x38)pin={pin.slot,0xcb2890,0xb7,UINT64_C(0x2e00af0e1e7040bd)};
                else if(pin.slot==0x40)pin={pin.slot,0xcb2950,0xb7,UINT64_C(0xf96ba04bd7b37069)};
            }
            // c7529b uses the critter's semantic has_name flag for grammar.
            static_assert(offsetof(df::item_critter,name)+offsetof(df::language_name,has_name)==0x13a);
            if(table==0x16bbad0 || table==0x165cd68) {
                if(pin.slot==0)pin=table==0x16bbad0
                    ?Pin{0,0x54b1d0,6,UINT64_C(0x6c72bd273c983320)}
                    :Pin{0,0x1035f0,6,UINT64_C(0x7922a651b9e95ab5)};
                if(pin.slot==0x6c0)pin={pin.slot,0x67040,3,UINT64_C(0xa3703b1a918cfbeb)};
            }
            if(table==0x16554c0 && pin.slot==0)
                pin={0,0x100890,6,UINT64_C(0xe0ef8053da2f8491)};
            // Egg actual-material getters prefer the first stored egg material,
            // then fall back to the caste raw. Pin both complete split bodies.
            if(table==0x16b6698) {
                if(pin.slot==0)pin={0,0x7df660,6,UINT64_C(0x431133361e8afda4)};
                if(pin.slot==0x38)pin={pin.slot,0xcb2a10,0xd1,UINT64_C(0x77376a358a06612e)};
                if(pin.slot==0x40)pin={pin.slot,0xcb2af0,0xd4,UINT64_C(0x1bbd19d5fe042485)};
            }
            // Leather c78767..c78c7c shares THREAD's owned dye/name helpers.
            // Its color leaf reads its dye profile or raw solid-color pattern.
            if(table==0x161d330 && pin.slot==0x6b0)
                pin={pin.slot,0xcae8d0,0xc4,UINT64_C(0x2074115b1d2aa1fd)};
            if(table==0x16c9420) {
                if(pin.slot==0)pin={0,0x101cf0,6,UINT64_C(0xf7f601fa9f00ef47)};
                if(pin.slot==0x6b0)pin={0x6b0,0xcae9a0,0xc4,UINT64_C(0x6d5fdc9d14308894)};
            }
            if(table==0x15fa918 && pin.slot==0)pin={0,0x67540,6,UINT64_C(0x2505ef84b8531c22)};
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
        // THREAD c7515e uses material flags for grammar; c7827b..c7875e
        // formats its semantic dye profile and dyer identity. Pair collection
        // uses owned local vectors; color/name helpers read raws/history only.
        constexpr Helper helpers[]={
            {0x14d880,0x5a,UINT64_C(0x4aa033209ea95fd2)}, // bounded plant raw flag lookup
            {0x145bee0,0x5e,UINT64_C(0x6abc4e374e372eef)},
            {0x145c2b0,0x122,UINT64_C(0x0e578b2e7d721c3a)},
            {0x701e70,0x20e,UINT64_C(0xead0193006374e44)},
            {0x13c900,0x8c,UINT64_C(0xf2ab35fac31e7af2)},
            {0xc0f630,0x2c,UINT64_C(0x2f03e40b0a07e0bf)},
            {0xa94030,0x6a1,UINT64_C(0xd81db68b3c9b33d2)},
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
// These furniture/container types follow the BOX description path in c75000:
// no extra type-specific branch, no subtype raw, and identical pinned virtuals.
inline bool furnitureItemDescriptionTable(const uint8_t* base,const void* table) {
    return table==base+0x16c54c0 ||
           table==base+0x15f7d10 ||
           table==base+0x16fd960 ||
           table==base+0x16c8ca0 ||
           table==base+0x16f56c8 ||
           table==base+0x161c930 || // CLOTH has no subtype; c77fba reads descriptor colors.
           table==base+0x16c8230 ||
           table==base+0x16c2d20 ||
           table==base+0x1625280 ||
           table==base+0x1625a00 ||
           table==base+0x16f9cb0 ||
           table==base+0x1620b48 ||
           table==base+0x16212c8 ||
           table==base+0x16225f0 ||
           table==base+0x16c25a0 ||
           table==base+0x16fe8b8 ||
           table==base+0x16c3fe0 ||
           table==base+0x161e518 ||
           table==base+0x16f37c0 ||
           table==base+0x16fffe8 ||
           table==base+0x1701de8 ||
           table==base+0x16f19c0 ||
           table==base+0x16f7cf8 ||
           table==base+0x16ff868 ||
           table==base+0x16fd1e0 ||
           table==base+0x1702568 ||
           table==base+0x1700768 ||
           table==base+0x16fc288 ||
           table==base+0x16f1240 ||
           table==base+0x16fa488 ||
           table==base+0x1701668 ||
           table==base+0x16f7520 ||
           table==base+0x16fac08 ||
           table==base+0x1624098 ||
           table==base+0x16fb388 ||
           table==base+0x16261f0 ||
           table==base+0x16f9530 ||
           table==base+0x1702d40 ||
           table==base+0x16f4f48 ||
           table==base+0x16b4dc0 ||
           table==base+0x16f8478 ||
           table==base+0x16c5cb0 ||
           table==base+0x16f28c0 ||
           table==base+0x16f3f40 || table==base+0x16ca460 || table==base+0x1700ee8 || table==base+0x16b8268 || table==base+0x16fbb08 || table==base+0x16ff038 || table==base+0x16fe0e0;
}
inline bool constructedItemDescriptionDispatch(df::item* item) {
    if(!item||!farmFunctions())return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto* table=*reinterpret_cast<const void* const*>(item);
    if(table!=base+0x1623198 && table!=base+0x16c6cf0 && table!=base+0x161dd98 &&
       table!=base+0x161f840 && table!=base+0x1621b88 && table!=base+0x1624818 &&
       table!=base+0x161edd8 && table!=base+0x16c9ba0 &&
       table!=base+0x16c4c00 && table!=base+0x15f74b0 &&
       table!=base+0x16f5ea0 && table!=base+0x16fca08 && table!=base+0x16f02e8 &&
       table!=base+0x16f6620 && table!=base+0x1623918 && !furnitureItemDescriptionTable(base,table))return false;
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
        // Clothing and ammunition share every listed constructed-item virtual except getType.
        // c75000 has no clothing-specific branch; subtype is a semantic raw.
        for(size_t table:{size_t(0x1623198),size_t(0x16c6cf0),size_t(0x161dd98),
                         size_t(0x161f840),size_t(0x1621b88),size_t(0x1624818),size_t(0x161edd8),size_t(0x16c9ba0),size_t(0x16c4c00),size_t(0x15f74b0),
                         size_t(0x16c8230),size_t(0x16c2d20),size_t(0x1625280),size_t(0x1625a00),size_t(0x16f9cb0),size_t(0x1620b48),size_t(0x16212c8),size_t(0x16225f0),size_t(0x16c25a0),size_t(0x16fe8b8),size_t(0x16c3fe0),size_t(0x161e518),size_t(0x16f37c0),size_t(0x16fffe8),size_t(0x1701de8),size_t(0x16f19c0),size_t(0x16f7cf8),size_t(0x16ff868),size_t(0x16fd1e0),size_t(0x1702568),size_t(0x1700768),size_t(0x161c930),size_t(0x16c54c0),size_t(0x15f7d10),size_t(0x16fd960),size_t(0x16c8ca0),size_t(0x16f56c8),size_t(0x16f6620),size_t(0x16fc288),size_t(0x16f1240),size_t(0x16fa488),size_t(0x1701668),size_t(0x16f7520),size_t(0x16fac08),size_t(0x1624098),size_t(0x16fb388),size_t(0x16261f0),size_t(0x16f9530),size_t(0x1702d40),size_t(0x16f4f48),size_t(0x16b4dc0),size_t(0x16f8478),size_t(0x16c5cb0),size_t(0x16f28c0),size_t(0x16f3f40),size_t(0x16ca460),size_t(0x1700ee8),size_t(0x16b8268),size_t(0x16f5ea0),size_t(0x16fca08),size_t(0x16f02e8),size_t(0x1623918),size_t(0x16fbb08),size_t(0x16ff038),size_t(0x16fe0e0)})for(auto pin:pins) {
            if(table==0x16c6cf0 && pin.slot==0)pin={0,0x673c0,6,UINT64_C(0x6470dd592ae1062b)};
            if(pin.slot==0) {
                if(table==0x161dd98)pin={0,0x28a840,6,UINT64_C(0x3c0e712b7d27ecd8)};
                if(table==0x161f840)pin={0,0x7b5d0,6,UINT64_C(0x621a1caaf5147c67)};
                if(table==0x1621b88)pin={0,0x776a0,6,UINT64_C(0x556c3b8077c6c86a)};
                if(table==0x1624818)pin={0,0x722d0,6,UINT64_C(0xd1ead67b27153938)};
                if(table==0x16c9ba0)pin={0,0x548fa0,6,UINT64_C(0x7b7766ffefb27e79)};
                if(table==0x16f5ea0)pin={0,0x28d340,6,UINT64_C(0x05fb860fe1c710df)};
                if(table==0x16fca08)pin={0,0x7b7a0,6,UINT64_C(0x57c0fc2ead8fec2e)};
                if(table==0x16f02e8)pin={0,0x8f45f0,6,UINT64_C(0xdff05a9069db5ad0)};
                if(table==0x1623918)pin={0,0x28a0d0,6,UINT64_C(0x9180cae344333306)};
                if(table==0x16ff038)pin={0,0x8f4fb0,6,UINT64_C(0x3661d20ba13abd27)};
                if(table==0x16fe0e0)pin={0,0x8f50d0,6,UINT64_C(0x29b1f0e123e9a32a)};
                if(table==0x16fbb08)pin={0,0xa6af90,6,UINT64_C(0x84d0e9b8c6e21909)};
                if(table==0x16b8268)pin={0,0x103c90,6,UINT64_C(0x5ec3be394ef2fcfa)};
                if(table==0x16ca460)pin={0,0x7a7b0,6,UINT64_C(0xbd391582980cf246)};
                if(table==0x1700ee8)pin={0,0x548f00,6,UINT64_C(0xa1848a7f67a18cf0)};
                if(table==0x16f3f40)pin={0,0xb4e5d0,6,UINT64_C(0xde98bfa5a462facd)};
                if(table==0x16fc288)pin={0,0x5c2320,6,UINT64_C(0x12ab673a5f182adc)};
                if(table==0x16f1240)pin={0,0x8f5450,6,UINT64_C(0x1054268c294ac798)};
                if(table==0x16fa488)pin={0,0x531290,6,UINT64_C(0x13aa8cfdcf6c549d)};
                if(table==0x1701668)pin={0,0x1044f0,6,UINT64_C(0xabddb2fbaf262ac1)};
                if(table==0x16f7520)pin={0,0x549270,6,UINT64_C(0x39b7b07d475b6314)};
                if(table==0x16fac08)pin={0,0x549620,6,UINT64_C(0x205a6e284cbd6e9a)};
                if(table==0x1624098)pin={0,0x28ae30,6,UINT64_C(0x06fca3d3521e9308)};
                if(table==0x16fb388)pin={0,0xb4e0e0,6,UINT64_C(0x1f5ad064dc6878f1)};
                if(table==0x16261f0)pin={0,0x289eb0,6,UINT64_C(0x2c08b18f59b62cee)};
                if(table==0x16f9530)pin={0,0xb51470,6,UINT64_C(0xd0e9b8b7b6bdb70f)};
                if(table==0x1702d40)pin={0,0x7cf90,6,UINT64_C(0x9e2eac0dc180e703)};
                if(table==0x16f4f48)pin={0,0x488980,6,UINT64_C(0x38b892b9d70746eb)};
                if(table==0x16b4dc0)pin={0,0x28ccf0,6,UINT64_C(0xdd9919e2340df78c)};
                if(table==0x16f8478)pin={0,0x5494f0,6,UINT64_C(0x2d07cf52ca0a4917)};
                if(table==0x16c5cb0)pin={0,0x8f2ab0,6,UINT64_C(0xaade0d383ed12780)};
                if(table==0x16f28c0)pin={0,0x7d7d0,6,UINT64_C(0xec9dc3bae72842e5)};
                if(table==0x16f6620)pin={0,0x8f4e90,6,UINT64_C(0x7821808e4991caf4)};
                if(table==0x161edd8)pin={0,0x28a950,6,UINT64_C(0x2f5f1000ffd7ac5b)};
                if(table==0x16c54c0)pin={0,0x724a0,6,UINT64_C(0xc53af550a9c41f3b)};
                if(table==0x15f7d10)pin={0,0xfd300,6,UINT64_C(0x16014dac0538de61)};
                if(table==0x16fd960)pin={0,0xb519d0,6,UINT64_C(0xb78bf662bc1ee915)};
                if(table==0x16c8ca0)pin={0,0x72420,6,UINT64_C(0xb88d14262c766b3e)};
                if(table==0x16c4c00)pin={0,0x7c7c0,6,UINT64_C(0x48bc5a55fa75ae6d)};
                if(table==0x16f56c8)pin={0,0xb514f0,6,UINT64_C(0xc43bd78d39700312)};
                if(table==0x15f74b0)pin={0,0x7b320,6,UINT64_C(0x6ec97dd57264bce4)};
                if(table==0x161c930)pin={0,0x289c00,6,UINT64_C(0xeb4820d021b33b4a)};
                if(table==0x16c8230)pin={0,0x54a180,6,UINT64_C(0xfa4cc2a8d4cd790b)};
                if(table==0x16c2d20)pin={0,0x7a480,6,UINT64_C(0xfca403570a9adc4f)};
                if(table==0x1625280)pin={0,0x67860,6,UINT64_C(0xa3dbcb2d9d6ef034)};
                if(table==0x1625a00)pin={0,0x28ac20,6,UINT64_C(0xd43f97295cde5cfc)};
                if(table==0x16f9cb0)pin={0,0x7a840,6,UINT64_C(0xeff4222c8d49c252)};
                if(table==0x1620b48)pin={0,0x28ad70,6,UINT64_C(0xae3473a9e4f2b485)};
                if(table==0x16212c8)pin={0,0x676d0,6,UINT64_C(0x972bea03201dd637)};
                if(table==0x16225f0)pin={0,0x67b90,6,UINT64_C(0xf24ae2dac3164c16)};
                if(table==0x16c25a0)pin={0,0x67270,6,UINT64_C(0x7dce27ae257f083d)};
                if(table==0x16fe8b8)pin={0,0x67530,6,UINT64_C(0xe59b01b045c53219)};
                if(table==0x16c3fe0)pin={0,0x67490,6,UINT64_C(0x711ebe83a82eba28)};
                if(table==0x161e518)pin={0,0x67200,6,UINT64_C(0xd69657d792aae6c0)};
                if(table==0x16f37c0)pin={0,0x548f80,6,UINT64_C(0x94d6a954ea53d8f3)};
                if(table==0x16fffe8)pin={0,0x76750,6,UINT64_C(0xe34641020ffc0e55)};
                if(table==0x1701de8)pin={0,0x549810,6,UINT64_C(0xc791b5fedf90a8ff)};
                if(table==0x16f19c0)pin={0,0x7a270,6,UINT64_C(0x951648187e7b6cc)};
                if(table==0x16f7cf8)pin={0,0x671f0,6,UINT64_C(0x8a7e08d8a2d0223a)};
                if(table==0x16ff868)pin={0,0x7ae10,6,UINT64_C(0xc9e6f6ad155aa643)};
                if(table==0x16fd1e0)pin={0,0x548f90,6,UINT64_C(0x8827482a6d039876)};
                if(table==0x1702568)pin={0,0x54b450,6,UINT64_C(0xbae254d462406882)};
                if(table==0x1700768)pin={0,0x79ce0,6,UINT64_C(0x4b131b0430423831)};
            }
            if(table==0x1623918 && pin.slot==0x750)
                pin={pin.slot,0x28a360,7,UINT64_C(0x34d5217814fb1d1b)};
            if((table==0x16ca460 || table==0x1700ee8) && pin.slot==0x230)
                pin={pin.slot,0x8f2eb0,0x15,UINT64_C(0xaa49f78932ee531d)};
            if(table==0x16f6620) {
                if(pin.slot==0x5a8)pin={pin.slot,0x67050,3,UINT64_C(0x62941518298855c4)};
                if(pin.slot==0x6b0)pin={pin.slot,0x66e60,6,UINT64_C(0x62d2efd24138f070)};
            }
            if(*reinterpret_cast<const void* const*>(base+table+pin.slot)!=base+pin.target || hash(pin.target,pin.length)!=pin.hash)return false;
        }
        for(size_t table:{size_t(0x16c6cf0),size_t(0x161dd98),size_t(0x161f840),
                         size_t(0x1621b88),size_t(0x1624818),size_t(0x161edd8),size_t(0x16c9ba0),size_t(0x16c4c00),size_t(0x15f74b0),size_t(0x16f5ea0),size_t(0x16fca08),size_t(0x16f02e8),size_t(0x1623918)})
            if(*reinterpret_cast<const void* const*>(base+table+8)!=base+0xfd0c0)return false;
        for(size_t table:{size_t(0x16c8230),size_t(0x16c2d20),size_t(0x1625280),size_t(0x1625a00),size_t(0x16f9cb0),size_t(0x1620b48),size_t(0x16212c8),size_t(0x16225f0),size_t(0x16c25a0),size_t(0x16fe8b8),size_t(0x16c3fe0),size_t(0x161e518),size_t(0x16f37c0),size_t(0x16fffe8),size_t(0x1701de8),size_t(0x16f19c0),size_t(0x16f7cf8),size_t(0x16ff868),size_t(0x16fd1e0),size_t(0x1702568),size_t(0x1700768),size_t(0x161c930),size_t(0x16c54c0),size_t(0x15f7d10),size_t(0x16fd960),size_t(0x16c8ca0),size_t(0x16f56c8),size_t(0x16fc288),size_t(0x16f1240),size_t(0x16fa488),size_t(0x1701668),size_t(0x16f7520),size_t(0x16fac08),size_t(0x1624098),size_t(0x16fb388),size_t(0x16261f0),size_t(0x16f9530),size_t(0x1702d40),size_t(0x16f4f48),size_t(0x16b4dc0),size_t(0x16f8478),size_t(0x16c5cb0),size_t(0x16f28c0),size_t(0x16f3f40),size_t(0x16ca460),size_t(0x1700ee8),size_t(0x16b8268),size_t(0x16fbb08),size_t(0x16ff038),size_t(0x16fe0e0)})
            if(*reinterpret_cast<const void* const*>(base+table+8)!=base+0x66e60)return false;
        // Statue/figurine artwork uses the same world-image generator as
        // constructed improvements. These additional virtuals expose semantic
        // image/creator fields and native-owned description/artwork outputs.
        struct ArtVirtual {size_t table,slot,target,length;uint64_t hash;};
        constexpr ArtVirtual artVirtuals[]={
            {0x16ca460,0x210,0x8f2e80,0x8,UINT64_C(0x36e0d8059cb08762)},
            {0x16ca460,0x218,0x8f2e90,0x8,UINT64_C(0xafee6f2aebfa6a8b)},
            {0x16ca460,0x220,0x8f2ea0,0x8,UINT64_C(0x7d316280f6ba347f)},
            {0x16ca460,0x230,0x8f2eb0,0x15,UINT64_C(0xaa49f78932ee531d)},
            {0x16ca460,0x238,0x8f2ed0,0x12,UINT64_C(0xf10deaa077097b45)},
            {0x1700ee8,0x210,0x8f2e80,0x8,UINT64_C(0x36e0d8059cb08762)},
            {0x1700ee8,0x218,0x66e90,0x3,UINT64_C(0x58389c18233078ff)},
            {0x1700ee8,0x220,0x66e90,0x3,UINT64_C(0x58389c18233078ff)},
            {0x1700ee8,0x230,0x8f2eb0,0x15,UINT64_C(0xaa49f78932ee531d)},
            {0x1700ee8,0x238,0x8f2ed0,0x12,UINT64_C(0xf10deaa077097b45)},
        };
        for(const auto& pin:artVirtuals)
            if(*reinterpret_cast<const void* const*>(base+pin.table+pin.slot)!=base+pin.target ||
               hash(pin.target,pin.length)!=pin.hash)return false;
        if(hash(0xcc84d0,0x347)!=UINT64_C(0x0e907022973b141d))return false;
        if(hash(0x144dcd0,0x3e36)!=UINT64_C(0xdaf8c8b2b95994a8))return false;
        if(hash(0x149690,0x28d)!=UINT64_C(0x11647b5a8193807a))return false;
        if(hash(0x1453230,0x40)!=UINT64_C(0xa030e4c00737e0b4))return false;
        if(hash(0x931860,0x2f9)!=UINT64_C(0x3f40974d82863764))return false;
        if(hash(0xa92860,0x17cb)!=UINT64_C(0x627504395969e689))return false;
        // Coin mint/year/issuer and both native image descriptions.
        if(hash(0x5beeb0,0xa9f)!=UINT64_C(0x8529b92563b16ee0))return false;
        if(hash(0xca0d00,0x55)!=UINT64_C(0x6891982ef52f2367))return false;
        if(hash(0x5be970,0x536)!=UINT64_C(0xd785ec19f3aa4618))return false;
        if(hash(0x52c2b0,0xd8)!=UINT64_C(0x38b6489e35387929))return false;
        if(hash(0xb957b0,0x20f)!=UINT64_C(0xadf68483d402792e))return false;
        // FOOD c7586f..c75a20 walks its ingredient vector and calls the
        // semantic item formatter with owned output. No UI or graphics inputs.
        if(*reinterpret_cast<const void* const*>(base+0x16f6620+8)!=base+0xc60510)return false;
        if(hash(0xc60510,0xc)!=UINT64_C(0x9008a7578cd9bf32) ||
           hash(0x6ee50,0xc)!=UINT64_C(0xe8047875ae27a4aa) ||
           hash(0x6f220,0x8)!=UINT64_C(0x2bba791d9cd7ac1d) ||
           hash(0xa82c10,0x56ec)!=UINT64_C(0x66347214dfd39a0b))return false;
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
        // cc83e0 records changed creation-zone items and clears their world-data
        // association. These are persistent simulation records, not graphics
        // caches. The native routine propagates this effect to related holders.
        static_assert(offsetof(df::world,world_data)==0x11a668);
        static_assert(offsetof(df::world_data,object_data)==0x208);
        static_assert(offsetof(df::world_object_data,altered_items)==8);
        static_assert(sizeof(df::world_object_data)==0x210);
        static_assert(offsetof(df::item,world_data_id)==0x50);
        static_assert(offsetof(df::item,world_data_subid)==0x54);
        static_assert(offsetof(df::building,world_data_id)==0x108);
        if(hash(0xcc83e0,0xe6)!=UINT64_C(0x153208913b9388eb))return false;
        if(hash(0x1453130,0xf8)!=UINT64_C(0x8908ab4dc6f55824))return false;
        if(hash(0x1451b10,0x161c)!=UINT64_C(0x5afdbfca1604e13b))return false;
        return true;
    }();
    if(!pinned)return false;
    if(table==base+0x16fbb08) {
        // c78e30..c79136 appends the slab's semantic inscription. Its
        // adventure knowledge/identity branch is excluded by the actual mode,
        // never by supplying or borrowing an adventure menu context.
        if(!df::global::gamemode || reinterpret_cast<const void*>(df::global::gamemode)!=base+0x189c298 ||
           *df::global::gamemode!=df::game_mode::DWARF)return false;
        static_assert(offsetof(df::item_slabst,description)==0xe8);
        static_assert(offsetof(df::item_slabst,topic)==0x108);
        static_assert(offsetof(df::item_slabst,engraving_type)==0x10c);
        if(static_cast<const df::item_slabst*>(item)->description.size()>32*1024)return false;
    }
    if(table==base+0x16b8268) {
        static_assert(offsetof(df::item_coinst,coin_batch)==0xe8);
        const auto index=static_cast<df::item_coinst*>(item)->coin_batch;
        // Full prose bounds-checks this index, but its short-caption companion
        // does not. Both paths require a resolved issuer/raw unless absent (-1).
        if(index!=-1) {
            if(!df::global::world)return false;
            const auto& batches=df::global::world->coin_batches.all;
            if(index<0 || size_t(index)>=batches.size() || !batches[size_t(index)])return false;
            const auto issuer_id=batches[size_t(index)]->entity;
            if(issuer_id!=-1) {
                const auto* issuer=df::historical_entity::find(issuer_id);
                if(!issuer || !issuer->entity_raw)return false;
            }
        }
    }
    if(table==base+0x16f6620) {
        const auto* food=static_cast<df::item_foodst*>(item);
        static_assert(offsetof(df::item_foodst,ingredients)==0xe0);
        static_assert(offsetof(df::food_ingredientst,quality)==0x10);
        if(!food->subtype || DFHack::Items::getSubtypeDef(df::item_type::FOOD,item->getSubtype())!=food->subtype ||
           int(food->quality)<0 || int(food->quality)>int(df::item_quality::Artifact))return false;
        for(const auto* ingredient:food->ingredients)if(!ingredient ||
            int(ingredient->quality)<0 || int(ingredient->quality)>int(df::item_quality::Artifact))return false;
        return true; // item_crafted, not item_constructed; there is no improvements vector.
    }
    if(table==base+0x16c6cf0) {
        const auto* instrument=static_cast<df::item_instrumentst*>(item);
        // c7691f reads component definitions; c795a9 appends the definition's
        // native description. Both are semantic raw data, never UI scratch.
        if(!instrument->subtype || DFHack::Items::getSubtypeDef(df::item_type::INSTRUMENT,item->getSubtype())!=instrument->subtype)return false;
    }
    const df::itemdef* definition=nullptr;
    // Tool prose reads the raw description; die-face wording reads face_up.
    // Both are semantic item/raw fields. Native bounds-checks the face index.
    static_assert(offsetof(df::item_toolst,subtype)==0xe8);
    static_assert(offsetof(df::item_toolst,face_up)==0x104);
    static_assert(offsetof(df::itemdef_toolst,description)==0x188);
    if(table==base+0x1623918)definition=static_cast<df::item_toolst*>(item)->subtype;
    if(table==base+0x16f5ea0)definition=static_cast<df::item_siegeammost*>(item)->subtype;
    if(table==base+0x16fca08)definition=static_cast<df::item_toyst*>(item)->subtype;
    if(table==base+0x16f02e8)definition=static_cast<df::item_trapcompst*>(item)->subtype;

    if(table==base+0x161dd98)definition=static_cast<df::item_helmst*>(item)->subtype;
    if(table==base+0x161f840)definition=static_cast<df::item_armorst*>(item)->subtype;
    if(table==base+0x1621b88)definition=static_cast<df::item_shoesst*>(item)->subtype;
    if(table==base+0x1624818)definition=static_cast<df::item_pantsst*>(item)->subtype;
    if(table==base+0x16c9ba0)definition=static_cast<df::item_ammost*>(item)->subtype;
    if(table==base+0x161edd8)definition=static_cast<df::item_glovesst*>(item)->subtype;
    if(table==base+0x16c4c00)definition=static_cast<df::item_shieldst*>(item)->subtype;
    if(table==base+0x15f74b0)definition=static_cast<df::item_weaponst*>(item)->subtype;
    if(table!=base+0x1623198 && table!=base+0x16c6cf0 && !furnitureItemDescriptionTable(base,table) &&
       (!definition || DFHack::Items::getSubtypeDef(item->getType(),item->getSubtype())!=definition))return false;
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
    return (simpleItemDescriptionDispatch(item) || constructedItemDescriptionDispatch(item) || corpseItemDescriptionDispatch(item)) && itemWrittenInputsReady(item);
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
    std::unique_ptr<df3d_creature::KnowledgeMaterialCacheRestore> writtenCache;
    if(writtenItem(item))writtenCache=std::make_unique<df3d_creature::KnowledgeMaterialCacheRestore>(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::string result;
    CorpseCaptionScope corpseScope(item);if(!corpseScope.ready)return std::nullopt;
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
    const auto material=itemInspectionMaterial(item);
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
// Item-sheet contents are an ordered, mixed list, unlike BIN artwork facts.
// Renderer1578bf..157a98 scans general_refs forward, accepts CONTAINS_UNIT/ITEM,
// and skips unresolved references. Outer157872..157885 requires container.
// This provider owns every row; no view_sheets list or scroll state is read.
inline std::optional<std::vector<ItemSheetContent>> itemSheetContents(df::item* container) {
    using UnitName=void (*)(df::unit*,std::string*,bool);
    static const auto unitName=[]()->UnitName {
        if(!farmFunctions())return nullptr;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x688;++i){hash^=base[0x1330c30+i];hash*=UINT64_C(1099511628211);}
        if(hash!=UINT64_C(0x0e165ee31decf426))return nullptr;
        return reinterpret_cast<UnitName>(base+0x1330c30);
    }();
    if(!container || !unitName)return std::nullopt;
    std::vector<ItemSheetContent> rows;
    if(!container->flags.bits.container)return rows;
    for(auto* ref:container->general_refs) {
        if(!ref)return std::nullopt;
        ItemSheetContent row;
        if(ref->getType()==df::general_ref_type::CONTAINS_ITEM) {
            auto* child=ref->getItem();if(!child)continue;
            auto facts=itemFacts(child);if(!facts)return std::nullopt;
            row.kind=1;row.id=child->id;row.caption=facts->caption;row.item=std::move(*facts);
            row.appearance=itemAppearance(child);if(!row.appearance)return std::nullopt;
        }else if(ref->getType()==df::general_ref_type::CONTAINS_UNIT) {
            auto* unit=ref->getUnit();if(!unit)continue;
            row.kind=2;row.id=unit->id;
            // Native15832b..15833e passes true, unlike carrier captions.
            unitName(unit,&row.caption,true);
        }else continue;
        if(row.id<0 || row.caption.size()>128*1024)return std::nullopt;
        if(rows.size()>=4096)return std::nullopt; // Bound the full transport list; never truncate.
        rows.push_back(std::move(row));
    }
    return rows;
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
    const auto uses=itemUses(item);const auto weight=itemWeightCaption(item);
    const auto holder=itemBuildingHolder(item),stockpile=itemStockpile(*position);
    if(!uses||!weight||!holder||!stockpile)return std::nullopt;
    // Observe facts after native lazy formatting, without borrowing a UI owner.
    auto facts=itemFacts(item);if(!facts)return std::nullopt;
    ItemObservation value;value.item=std::move(*facts);value.weight=*weight;value.description=uses->description;value.uses=uses->rows;
    switch(item->getType()) {
    case df::item_type::WEAPON:case df::item_type::SHIELD:case df::item_type::BAG:
    case df::item_type::BACKPACK:case df::item_type::QUIVER:
    case df::item_type::SPLINT:case df::item_type::CRUTCH:
    case df::item_type::TOOL:case df::item_type::TOY:case df::item_type::SIEGEAMMO:case df::item_type::TRAPCOMP:
    case df::item_type::SKIN_TANNED:case df::item_type::ROCK:
    case df::item_type::BRANCH:case df::item_type::BALLISTAARROWHEAD:case df::item_type::TOTEM:
    case df::item_type::BALLISTAPARTS:
    case df::item_type::BOLT_THROWER_PARTS:
    case df::item_type::BRACELET:
    case df::item_type::CATAPULTPARTS:
    case df::item_type::CROWN:
    case df::item_type::EARRING:
    case df::item_type::GEM:
    case df::item_type::GRATE:
    case df::item_type::HATCH_COVER:
    case df::item_type::MILLSTONE:
    case df::item_type::ORTHOPEDIC_CAST:
    case df::item_type::PIPE_SECTION:
    case df::item_type::QUERN:
    case df::item_type::RING:
    case df::item_type::TRACTION_BENCH:
    case df::item_type::TRAPPARTS:
    case df::item_type::FISH:case df::item_type::FISH_RAW:
    case df::item_type::EGG:case df::item_type::REMAINS:
    case df::item_type::PET:case df::item_type::VERMIN:
    case df::item_type::CORPSE:case df::item_type::CORPSEPIECE:
    case df::item_type::PLANT_GROWTH:case df::item_type::FOOD:
    case df::item_type::DRINK:case df::item_type::LIQUID_MISC:case df::item_type::POWDER_MISC:
    case df::item_type::MEAT:case df::item_type::PLANT:
    case df::item_type::CHEESE:case df::item_type::GLOB:
    case df::item_type::THREAD:case df::item_type::CLOTH:
    case df::item_type::BAR:case df::item_type::BLOCKS:
    case df::item_type::BOULDER:case df::item_type::WOOD:
    case df::item_type::ROUGH:case df::item_type::SMALLGEM:
    case df::item_type::BOX:case df::item_type::INSTRUMENT:
    case df::item_type::DOOR:
    case df::item_type::FLOODGATE:
    case df::item_type::BED:
    case df::item_type::CHAIR:
    case df::item_type::FLASK:
    case df::item_type::GOBLET:
    case df::item_type::BARREL:
    case df::item_type::BUCKET:
    case df::item_type::TABLE:
    case df::item_type::BIN:
    case df::item_type::CABINET:
    case df::item_type::ANVIL:
    case df::item_type::CHAIN:
    case df::item_type::WINDOW:
    case df::item_type::CAGE:
    case df::item_type::ANIMALTRAP:
    case df::item_type::COFFIN:
    case df::item_type::ARMORSTAND:
    case df::item_type::WEAPONRACK:
    case df::item_type::COIN:
    case df::item_type::BOOK:case df::item_type::SHEET:
    case df::item_type::SLAB:
    case df::item_type::STATUE:case df::item_type::FIGURINE:
    case df::item_type::AMULET:
    case df::item_type::SCEPTER:
    case df::item_type::HELM:case df::item_type::ARMOR:case df::item_type::SHOES:
    case df::item_type::PANTS:case df::item_type::GLOVES:case df::item_type::AMMO:
        value.appearance=itemAppearance(item);if(!value.appearance)return std::nullopt;break;
    default:break;
    }
    if(holder->id>=0)value.buildingHolder=*holder;
    else {const auto carrier=itemCarrier(item);if(!carrier)return std::nullopt;if(carrier->kind)value.carrier=*carrier;}
    if(stockpile->id>=0){
        auto* pile=virtual_cast<df::building_stockpilest>(df::building::find(stockpile->id));if(!pile)return std::nullopt;
        value.stockpile=*stockpile;value.stockpileCategories=pile->settings.flags.whole;
    }
    const auto owner=itemOwnerDescription(item);if(!owner)return std::nullopt;
    if(owner->id>=0)value.owner=*owner;
    if(item->getType()==df::item_type::AMMO){value.ammunitionAssignment=itemAmmunitionAssignment(item);if(!value.ammunitionAssignment)return std::nullopt;}
    value.contents=itemSheetContents(item);if(!value.contents)return std::nullopt;
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
        if(row.itemType==5||row.itemType==13||row.itemType==17||row.itemType==30){row.appearance=itemAppearance(held->item);if(!row.appearance)return std::nullopt;}
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
