#pragma once
#include "building_item_native.h"
#include "df/unit_inventory_item.h"
#include "df/unit_spatter.h"
#include "df/general_ref.h"
#include <array>
#include <cstring>

namespace df3d_creature {
// The inventory formatter's Pet branch seeds SplitMix. Its two-handed Weapon
// branch can draw from MT while selecting a usable grasp. Preserve every stream,
// including buffers changed by a twist, just as the native hover adapter does.
class InventoryRandomRestore {
    uint8_t* base;
    std::array<uint8_t,0x6180> mt;
    std::array<uint8_t,40> indices;
    int16_t stream;
    uint64_t split;
public:
    explicit InventoryRandomRestore(uint8_t* b):base(b) {
        std::memcpy(mt.data(),b+0x234e990,mt.size());
        std::memcpy(indices.data(),b+0x2131b30,indices.size());
        std::memcpy(&stream,b+0x2159084,sizeof(stream));
        std::memcpy(&split,b+0x18adf98,sizeof(split));
    }
    ~InventoryRandomRestore() {
        std::memcpy(base+0x234e990,mt.data(),mt.size());
        std::memcpy(base+0x2131b30,indices.data(),indices.size());
        std::memcpy(base+0x2159084,&stream,sizeof(stream));
        std::memcpy(base+0x18adf98,&split,sizeof(split));
    }
    InventoryRandomRestore(const InventoryRandomRestore&)=delete;
    InventoryRandomRestore& operator=(const InventoryRandomRestore&)=delete;
};

// Only semantic inputs reachable from1393900 are populated. Native body/nerve
// refreshes mutate the copied components, enemy vectors, flags and cache. Wounds,
// body-plan raws, jobs and items are read-only references in this call graph.
// Never copy a unit's mutex or memcpy its owning containers.
class InventoryDescriptionContext {
    struct OwnedUnit final:df::unit { OwnedUnit():df::unit(){} } owned;
    std::vector<df::unit_inventory_item> entries;
public:
    explicit InventoryDescriptionContext(const df::unit& source) {
        owned.race=source.race;owned.caste=source.caste;
        owned.id=source.id;owned.name=source.name;owned.custom_profession=source.custom_profession;
        owned.hist_figure_id=source.hist_figure_id;owned.civ_id=source.civ_id;
        owned.sex=source.sex;owned.training_level=source.training_level;
        owned.relationship_ids=source.relationship_ids;
        owned.uwss_use_display_name=source.uwss_use_display_name;
        owned.uwss_display_name_sing=source.uwss_display_name_sing;
        owned.uwss_display_name_plur=source.uwss_display_name_plur;
        owned.uwss_display_name_adj=source.uwss_display_name_adj;
        owned.flags1=source.flags1;owned.flags2=source.flags2;
        owned.flags3=source.flags3;owned.flags4=source.flags4;
        owned.job=source.job;owned.body=source.body;owned.enemy=source.enemy;
        owned.cache=source.cache;
        owned.uwss_add_caste_flag=source.uwss_add_caste_flag;
        owned.uwss_remove_caste_flag=source.uwss_remove_caste_flag;
        entries.reserve(source.inventory.size());
        for(const auto* entry:source.inventory)entries.push_back(*entry);
        for(auto& entry:entries)owned.inventory.push_back(&entry);
    }
    df::unit* unit() {return &owned;}
    const std::vector<df::unit_inventory_item>& inventory() const {return entries;}
    InventoryDescriptionContext(const InventoryDescriptionContext&)=delete;
    InventoryDescriptionContext& operator=(const InventoryDescriptionContext&)=delete;
};

inline bool inventoryDescriptionReady() {
    static const bool ready=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1393900,0xe24,UINT64_C(0x3e7908712b100d57)},
            {0x13345d0,0x249,UINT64_C(0xf4075bbdb4b3eb77)},
            {0x135edf0,0x20,UINT64_C(0x48a428d1a5aeb8dd)},
            {0x13869f0,0x2f8,UINT64_C(0x3a4c7f2fb4d241a1)},
            {0x1385b10,0x816,UINT64_C(0xd0d397ea8681b007)},
            {0x1383f50,0xe82,UINT64_C(0xbc4789871636eb21)},
            {0x1383b40,0x74,UINT64_C(0x4a98ff11e04d1ce9)},
            {0x13243b0,0x56,UINT64_C(0xc7c182f36e56f3bb)},
            {0x13ec760,0x3ca,UINT64_C(0xa85f2be064b4fe01)},
            {0xeb68b0,0x1e3,UINT64_C(0x4bcd46a418e7a7bb)},
            {0xd09a30,0x52,UINT64_C(0xa2896c40eeeb58bc)},
            {0x657f90,0x43c,UINT64_C(0x5aae53cc785d2be6)},
            {0x14add70,0x12f,UINT64_C(0x01f897b15772d540)},
            {0xc3a4f0,0x98,UINT64_C(0x90965a9fe84783f6)},
            {0x72570,0x98,UINT64_C(0xa69932c0f279084a)},
            {0xa946e0,0x7c2,UINT64_C(0xdbc3db5f052419ee)},
            {0x1330c30,0x688,UINT64_C(0x0e165ee31decf426)},
            {0x132f980,0x8de,UINT64_C(0x64c00c9b84e68e70)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    return ready;
}
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
