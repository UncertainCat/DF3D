#pragma once
#include "building_item_native.h"
#include "df/unit_inventory_item.h"
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
struct InventoryDescriptionRow {
    int32_t id=-1;
    std::string caption,role;
};
// Diagnostic acceptance entry point, not yet a complete Items page: contained
// objects and spatters are separate native rows and must be added before wiring.
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
        rows.push_back(std::move(row));
    }
    return rows;
}
} // namespace df3d_creature
