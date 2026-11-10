#pragma once
#include "item_transaction.h"
#include "item_written_native.h"
#include "item_corpse_native.h"
#include "workshop_catalog_native.h"
#include "stone_use_native.h"
#include "df/reaction.h"
#include <cstddef>

namespace df3d_production {
inline bool itemDescriptionDispatch(df::item* item);
struct ItemUses {std::string description;std::vector<ItemUseRow> rows;};
// Native1a8df0 writes only timestamp, description, description-scroll offset
// and these output vectors in its supplied context. Do not pass view_sheets.
// Global inputs are gamemode, fortress reaction resources and simulation raws.
struct ItemUsesContext {
    std::array<std::byte,0x110> prefix{};
    uint32_t timestamp=0;
    std::array<std::byte,0x1e10-0x114> gap{};
    std::string description;
    std::array<std::byte,0x30> descriptionLayout{};
    std::vector<std::string*> uses;
    std::vector<int32_t> reactions;
    uint8_t* base;
    explicit ItemUsesContext(uint8_t* value):base(value){}
    ~ItemUsesContext(){reinterpret_cast<void(*)(void*)>(base+0xbb9b0)(&uses);}
    ItemUsesContext(const ItemUsesContext&)=delete;
    ItemUsesContext& operator=(const ItemUsesContext&)=delete;
};
static_assert(offsetof(ItemUsesContext,description)==0x1e10);
static_assert(offsetof(ItemUsesContext,uses)==0x1e60);
static_assert(offsetof(ItemUsesContext,reactions)==0x1e78);
static_assert(offsetof(df::plotinfost,main)+offsetof(df::plotinfost::T_main,fortress_entity)==0x8fb8);

inline std::optional<ItemUses> itemUses(df::item* item) {
    if(!itemDescriptionDispatch(item) || !workshopInventoryReady())return std::nullopt;
    auto* base=df3d_stone_use::supportedBase();
    if(!base || !df::global::world || !df::global::plotinfo)return std::nullopt;
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1a8df0,0xec6,UINT64_C(0x1b1ddf4c0ba672c0)},
            {0xed7a40,0x1cf,UINT64_C(0x54ba97c663a2e8bc)},
            {0xc75000,0x46aa,UINT64_C(0xd5969f2286ee8a96)},
            {0x67040,0x3,UINT64_C(0xa3703b1a918cfbeb)},
            {0x67050,0x3,UINT64_C(0x62941518298855c4)},
            {0xc5ff40,0xc,UINT64_C(0x800b25d79ffc1cd3)},
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!pinned)return std::nullopt;
    const auto* table=*reinterpret_cast<const uint8_t* const*>(item);
    const auto buildMat=*reinterpret_cast<const void* const*>(table+0x1b8);
    if(buildMat!=base+0x67040 && buildMat!=base+0x67050 && buildMat!=base+0xc5ff40)return std::nullopt;
    // matchesRoot ed7a40 owns a job_item_filter and delegates to the same
    // a27c60 predicate used by native construction/workshop inventory queries.
    // Reject unrecognized reagent dispatch before entering the builder.
    const auto& reactions=df::global::world->raws.reactions.reactions;
    for(const auto* reaction:reactions){
        if(!reaction)return std::nullopt;
        for(const auto* reagent:reaction->reagents){
            if(!reagent)return std::nullopt;
            const auto* dispatch=*reinterpret_cast<const uint8_t* const*>(reagent);
            if(dispatch!=base+0x17374d0 && dispatch!=base+0x17373f0)return std::nullopt;
            const auto target=*reinterpret_cast<const void* const*>(dispatch+0x28);
            if(target!=(dispatch==base+0x17374d0?base+0xed7a40:base+0x67050))return std::nullopt;
        }
    }
    const auto* entity=df::global::plotinfo->main.fortress_entity;
    if(entity)for(const auto index:entity->resources.reaction_idx)
        if(index<0 || size_t(index)>=reactions.size())return std::nullopt;
    std::unique_ptr<df3d_creature::KnowledgeMaterialCacheRestore> writtenCache;
    if(writtenItem(item))writtenCache=std::make_unique<df3d_creature::KnowledgeMaterialCacheRestore>(df::global::world->raws.creatures.hist_fig_to_creature_map);
    ItemUsesContext owned(base);
    CorpseCaptionScope corpseScope(item);if(!corpseScope.ready)return std::nullopt;
    reinterpret_cast<void(*)(void*,df::item*)>(base+0x1a8df0)(&owned,item);
    if(owned.uses.size()!=owned.reactions.size() || owned.uses.size()>4096 || owned.description.size()>128*1024)return std::nullopt;
    ItemUses result;result.description=std::move(owned.description);
    for(size_t i=0;i<owned.uses.size();++i){
        const auto* caption=owned.uses[i];const auto reaction=owned.reactions[i];
        if(!caption || caption->size()>16384 || reaction< -1 ||
           (reaction>=0 && size_t(reaction)>=reactions.size()))return std::nullopt;
        result.rows.push_back({*caption,reaction});
    }
    return result;
}
}
