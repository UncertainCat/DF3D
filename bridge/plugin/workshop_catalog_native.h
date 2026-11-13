#pragma once
#include "workshop_job_native.h"
#include "df/job_item_filter.h"
#include "df/item_boulderst.h"
#include "df/item_barst.h"
#include "df/inorganic_raw.h"
#include "df/reaction_reagent.h"
#include "df/reaction_category.h"
#include <memory>

namespace df3d_production {
struct WorkshopReactionCategory {
    std::string code,caption;
    int32_t hotkey=-1;
};
// Native8c4380..8c47a4 walks permitted reaction ancestry before constructing
// category buttons. Compose that inline branch using owned visited strings;
// only simulation raws and the native permission leaf are consulted.
inline std::optional<std::vector<WorkshopReactionCategory>> workshopReactionCategories(
    df::building* building,const std::string& parent) {
    static const bool supported=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x8c4380,0x424,UINT64_C(0xab15df898db74b83)},
            {0x8c29d0,0xd8,UINT64_C(0x6e575de3e979203e)},
            {0x1615870,0xd,UINT64_C(0xcd56f05c0ea1035c)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported || !building || !df::global::world || !df::global::plotinfo ||
       !df::global::plotinfo->main.fortress_entity)return std::nullopt;
    const auto& raws=df::global::world->raws.reactions;
    const auto find=[&](const std::string& code)->const df::reaction_category* {
        for(const auto* category:raws.reaction_categories)
            if(category && category->id==code)return category;
        return nullptr;
    };
    std::vector<std::string> visited;
    std::vector<WorkshopReactionCategory> result;
    for(size_t index=0;index<raws.reactions.size();++index) {
        const auto* reaction=raws.reactions[index];
        if(!reaction || reaction->category.empty())continue;
        const auto allowed=workshopReactionAllowed(int32_t(index));
        if(!allowed)return std::nullopt;
        if(!*allowed)continue;
        const auto& restrictions=reaction->building;
        if(restrictions.type.size()!=restrictions.subtype.size() ||
           restrictions.type.size()!=restrictions.custom.size())return std::nullopt;
        bool matches=false;
        for(size_t n=restrictions.type.size();n>0;--n) {
            const auto i=n-1;
            if(restrictions.type[i]==building->getType() && restrictions.subtype[i]==building->getSubtype() &&
               restrictions.custom[i]==building->getCustomType()){matches=true;break;}
        }
        if(!matches || std::find(visited.begin(),visited.end(),reaction->category)!=visited.end())continue;
        visited.push_back(reaction->category);
        const auto* category=find(reaction->category);
        if(!category)return std::nullopt;
        while(category->parent!=parent) {
            category=find(category->parent);
            if(!category)break;
            if(std::find(visited.begin(),visited.end(),category->id)!=visited.end()){category=nullptr;break;}
            visited.push_back(category->id);
        }
        if(!category)continue;
        // Native8c29d0 uses the first matching nonempty category name, else ID.
        std::string caption=category->id;
        for(const auto* raw:raws.reaction_categories)
            if(raw && raw->id==category->id && !raw->name.empty()){caption=raw->name;break;}
        const auto* base=reinterpret_cast<const char*>(GetModuleHandleW(nullptr));
        caption.append(base+0x1615870,13);
        result.push_back({category->id,std::move(caption),int32_t(category->key)});
    }
    return result;
}
inline bool workshopInventoryReady() {
    static const bool ready=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1fb050,0x123,UINT64_C(0x3ea393db12f2c677)},
            {0xed7490,0x3f3,UINT64_C(0xfaa78e37515c7a6b)},
            {0xa29630,0x177b,UINT64_C(0xd483c9c32e4f7fc5)},
            {0xa26990,0x12c3,UINT64_C(0x33e9d093964f527a)},
            {0xa27c60,0x19c4,UINT64_C(0x2810b30401cba53e)},
            {0xc93380,0x98,UINT64_C(0x9455ba082ba604c4)},
            {0x14d3600,0x109,UINT64_C(0xb164e558947da80d)},
            {0x14d34c0,0x13f,UINT64_C(0xf55df28a48d0f031)},
            {0x16beb70,0xa,UINT64_C(0x5e405a170a87e776)},
            {0x16beb80,0xf,UINT64_C(0x3680f8580bd330c1)},
            {0x15fd690,0x1,UINT64_C(0xaf64104c860244e8)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
struct WorkshopReactionRow {
    int32_t rawIndex=-1;
    std::string code,caption,objection;
    bool available=false;
};
// Native8c3fe0 composes reaction availability inline. Its item-search routines
// and reagent methods operate on independent filter/collector/precalc storage.
// The world supplies read-only item/raw records, never native menu vectors.
inline std::optional<std::vector<WorkshopReactionRow>> workshopReactionRows(
    df::building* building,const std::string& category) {
    if(!building || !df::global::world || !workshopInventoryReady())return std::nullopt;
    static_assert(sizeof(df::job_item_filter)==0x110);
    static_assert(offsetof(df::job_item_filter,item_vector)==0x10);
    static_assert(offsetof(df::job_item_filter,building)==0xd0);
    static_assert(offsetof(df::inorganic_raw,metal_ore.mat_index)==0x68);
    static_assert(offsetof(df::inorganic_raw,material.reaction_class)==0x650);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    df3d_creature::InventoryRandomRestore random(base);
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    using Init=void (*)(df::job_item_filter*);
    using Collect=void (*)(df::job_item_filter*,std::vector<df::item*>*);
    using Find=df::item* (*)(df::job_item_filter*);
    const auto& inorganics=df::global::world->raws.inorganics.all;
    std::vector<int32_t> counts(inorganics.size()),ores(inorganics.size()),classCounts;
    std::vector<std::unique_ptr<std::string>> classStorage;
    std::vector<std::string*> classes;
    std::vector<df::item*> boulders(df::global::world->items.other.BOULDER.begin(),df::global::world->items.other.BOULDER.end()),found;
    df::job_item_filter filter;
    reinterpret_cast<Init>(base+0x1fb050)(&filter);
    filter.item_vector=&boulders;
    reinterpret_cast<Collect>(base+0xa29630)(&filter,&found);
    for(auto it=found.rbegin();it!=found.rend();++it) {
        auto* item=*it;if(!item || item->getMaterial()!=0)continue;
        const auto index=item->getMaterialIndex();
        if(index<0 || size_t(index)>=counts.size() || counts[index]>=100)continue;
        ++counts[index];const auto* raw=inorganics[index];if(!raw)continue;
        for(auto ore:raw->metal_ore.mat_index) {
            if(ore<0 || size_t(ore)>=ores.size())return std::nullopt;
            ++ores[ore];
        }
        for(auto itClass=raw->material.reaction_class.rbegin();itClass!=raw->material.reaction_class.rend();++itClass) {
            if(!*itClass)return std::nullopt;
            size_t i=0;while(i<classes.size() && *classes[i]!=**itClass)++i;
            if(i==classes.size()) {
                classStorage.push_back(std::make_unique<std::string>(**itClass));
                classes.push_back(classStorage.back().get());classCounts.push_back(0);
            }
            ++classCounts[i];
        }
    }
    bool fuel=building->needsMagma();
    if(!fuel) {
        std::vector<df::item*> bars(df::global::world->items.other.BAR.begin(),df::global::world->items.other.BAR.end());
        df::job_item_filter fuelFilter;reinterpret_cast<Init>(base+0x1fb050)(&fuelFilter);
        fuelFilter.item_type=df::item_type(0);fuelFilter.mat_type=7;fuelFilter.item_vector=&bars;
        fuelFilter.building=building;fuelFilter.pos=df::coord(building->x1,building->y1,building->z);
        fuel=reinterpret_cast<Find>(base+0xa26990)(&fuelFilter)!=nullptr;
    }
    std::vector<WorkshopReactionRow> result;
    const auto& reactions=df::global::world->raws.reactions.reactions;
    for(size_t i=0;i<reactions.size();++i) {
        auto* reaction=reactions[i];if(!reaction || reaction->category!=category)continue;
        const auto allowed=workshopReactionAllowed(int32_t(i));if(!allowed)return std::nullopt;
        if(!*allowed)continue;
        bool matches=false;
        for(size_t n=reaction->building.type.size();n>0;--n) {
            const auto at=n-1;
            if(at>=reaction->building.subtype.size() || at>=reaction->building.custom.size())return std::nullopt;
            if(reaction->building.type[at]==building->getType() && reaction->building.subtype[at]==building->getSubtype() &&
               reaction->building.custom[at]==building->getCustomType()){matches=true;break;}
        }
        if(!matches)continue;
        df::job job;job.job_type=df::job_type::CustomReaction;job.reaction_name=reaction->code;
        const auto caption=workshopJobCaption(job);if(!caption)return std::nullopt;
        WorkshopReactionRow row{int32_t(i),reaction->code,*caption,{},true};
        if(reaction->flags.is_set(df::reaction_flags::FUEL) && !fuel) {
            row.available=false;row.objection.assign(reinterpret_cast<const char*>(base+0x16beb80),15);
        } else for(auto it=reaction->reagents.rbegin();it!=reaction->reagents.rend();++it) {
            auto* reagent=*it;if(!reagent)return std::nullopt;
            if(reagent->flags.bits.IN_CONTAINER)continue;
            if(reagent->have_enough_from_precalc_info(building,&counts,&ores,&classes,&classCounts,reaction->index))continue;
            std::string description;reagent->getDescription(&description,reaction->index);
            row.available=false;row.objection.assign(reinterpret_cast<const char*>(base+0x16beb70),10);
            row.objection+=description;row.objection.append(reinterpret_cast<const char*>(base+0x15fd690),1);break;
        }
        result.push_back(std::move(row));
    }
    return result;
}
}
