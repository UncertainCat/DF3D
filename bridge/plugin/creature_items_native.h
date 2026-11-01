#pragma once
#include "building_item_native.h"
#include "unit_description_native.h"
#include "df/unit_inventory_item.h"
#include "df/unit_spatter.h"
#include "df/general_ref.h"
#include <array>
#include <cstring>

namespace df3d_creature {
struct InventoryContainedRow {
    int32_t kind=0,id=-1; // 1 item, 2 creature; unresolved refs still occupy a row.
    std::string caption;
};
struct InventoryDescriptionRow {
    int32_t id=-1;
    std::string caption,role;
    std::vector<InventoryContainedRow> contents;
};
// Native16a7d2..16b8a0 interleaves immediate contained refs after each inventory
// entry. It does not recurse; each matching ref consumes a row even if unresolved.
// Creature captions include the native sex/training suffix (third argument true).
inline std::optional<std::vector<InventoryDescriptionRow>> inventoryDescriptions(const df::unit* source) {
    if(!source||!inventoryDescriptionReady()||!source->body.body_plan||
       source->inventory.size()>10000||source->body.components.body_part_status.size()>32767)return std::nullopt;
    for(const auto* entry:source->inventory)if(!entry||!entry->item)return std::nullopt;
    static_assert(offsetof(df::unit,inventory)==0x408);
    static_assert(offsetof(df::unit,body)+offsetof(df::unit::T_body,components)==0x4f0);
    static_assert(offsetof(df::unit,enemy)+offsetof(df::unit::T_enemy,body_part_useable)==0x12d8);
    static_assert(offsetof(df::unit,cache)==0x1430);
    InventoryDescriptionContext context(*source);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    InventoryRandomRestore restore(base);
    using Describe=void (*)(df::unit*,std::string*,df::unit_inventory_item*);
    std::vector<InventoryDescriptionRow> rows;
    for(const auto& entry:context.inventory()) {
        auto caption=df3d_production::buildingItemCaption(entry.item);
        if(!caption)return std::nullopt;
        InventoryDescriptionRow row;row.id=entry.item->id;row.caption=std::move(*caption);
        auto input=entry;
        reinterpret_cast<Describe>(base+0x1393900)(context.unit(),&row.role,&input);
        if(row.caption.size()>4096||row.role.size()>4096)return std::nullopt;
        if(entry.item->flags.bits.container) {
            if(entry.item->general_refs.size()>10000)return std::nullopt;
            for(auto* ref:entry.item->general_refs) {
                if(!ref)return std::nullopt;
                const auto type=ref->getType();
                if(type!=df::general_ref_type::CONTAINS_ITEM&&type!=df::general_ref_type::CONTAINS_UNIT)continue;
                InventoryContainedRow child;child.kind=type==df::general_ref_type::CONTAINS_ITEM?1:2;
                if(child.kind==1) {
                    if(auto* item=ref->getItem()) {
                        auto caption=df3d_production::buildingItemCaption(item);if(!caption)return std::nullopt;
                        child.id=item->id;child.caption=std::move(*caption);
                    }
                }else if(auto* creature=ref->getUnit()) {
                    if(creature->inventory.size()>10000||!creature->body.body_plan)return std::nullopt;
                    for(auto* held:creature->inventory)if(!held||!held->item)return std::nullopt;
                    InventoryDescriptionContext contained(*creature);
                    using Name=void (*)(df::unit*,std::string*,bool);
                    reinterpret_cast<Name>(base+0x1330c30)(contained.unit(),&child.caption,true);
                    child.id=creature->id;
                }
                if(child.caption.size()>4096)return std::nullopt;
                row.contents.push_back(std::move(child));
            }
        }
        rows.push_back(std::move(row));
    }
    return rows;
}
struct InventorySpatterRow {
    int32_t sourceIndex=-1,bodyPart=-1;
    std::string caption,bodyPartCaption;
};
// Native16b96c includes external spatters only, in body.spatters vector order.
// 16bba6 formats spatter_common;16bd5b formats the body part without title case.
// The caption graph reads material raws and historical-figure/identity names,
// with all string storage owned. Material lookup may lazily populate semantic
// historical-material caches. No native sheet or rendering state is used.
inline std::optional<std::vector<InventorySpatterRow>> inventorySpatters(const df::unit* source) {
    if(!source||!inventoryDescriptionReady()||!source->body.body_plan||
       source->body.spatters.size()>10000)return std::nullopt;
    static_assert(offsetof(df::unit_spatter,body_part_id)==0x18);
    static_assert(offsetof(df::unit_spatter,flags)==0x1a);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    using Caption=void (*)(df::spatter_common*,std::string*);
    using BodyPart=void (*)(const df::unit*,std::string*,int16_t,int32_t,int16_t);
    InventoryRandomRestore restore(base);
    std::vector<InventorySpatterRow> rows;
    for(size_t i=0;i<source->body.spatters.size();++i) {
        const auto* spatter=source->body.spatters[i];
        if(!spatter)return std::nullopt;
        if(!spatter->flags.bits.external)continue;
        auto input=spatter->base;
        InventorySpatterRow row;row.sourceIndex=static_cast<int32_t>(i);row.bodyPart=spatter->body_part_id;
        reinterpret_cast<Caption>(base+0x657f90)(&input,&row.caption);
        if(row.bodyPart>=0)
            reinterpret_cast<BodyPart>(base+0x13345d0)(source,&row.bodyPartCaption,spatter->body_part_id,0,2);
        if(row.caption.size()>4096||row.bodyPartCaption.size()>4096)return std::nullopt;
        rows.push_back(std::move(row));
    }
    return rows;
}
} // namespace df3d_creature
