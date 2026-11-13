#pragma once
#include "work_order_dye_native.h"

namespace df3d_production {
struct WorkshopDyeTarget {int32_t color=-1,available=0,alphaOrder=0;bool tint=false;};

// Native8c597d..8c6cbb builds these lists inline. Only its semantic inventory
// search and color mixer are invoked; all filters, vectors and counts are owned.
// Workshop searches include building/position, unlike global Work orders.
inline std::optional<std::vector<WorkshopDyeTarget>> workshopDyeTargets(df::building* building,int32_t job) {
    if(!building || int(building->getType())!=13 || building->getSubtype()!=21 ||
       (job!=190 && job!=191 && job!=244 && job!=243) || !df::global::world || !workOrderDyeReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x133e;++i){hash^=base[0x8c597d+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x0a41fe9bfc54aa4e);
    }();
    if(!supported)return std::nullopt;
    auto& colors=df::global::world->raws.descriptors.colors;
    const size_t count=colors.size();if(count>1024)return std::nullopt;
    for(const auto* color:colors)if(!color)return std::nullopt;
    df3d_creature::InventoryRandomRestore random(base);
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::vector<int32_t> dyes(count),substrates(count),tints(count);
    const bool mixing=job==243;
    const auto collect=[&](bool dye)->bool {
        df::job_item_filter filter;
        reinterpret_cast<void(*)(df::job_item_filter*)>(base+0x1fb050)(&filter);
        static_assert(offsetof(df::job_item_filter,pos)==0xb4 && offsetof(df::job_item_filter,building)==0xd0);
        filter.pos=df::coord(building->x1,building->y1,building->z);filter.building=building;
        filter.can_steal_haul_items=true;filter.flags2.whole=dye?1:2;filter.use_flags2=true;
        size_t source=0x23e5c60;
        if(dye)filter.flags1.whole=0x10;
        else if(job==191){filter.item_type=df::item_type(58);filter.min_dimension=10000;source=0x23e5f90;}
        else if(job==244){filter.item_type=df::item_type(55);source=0x23e5f48;}
        else {filter.item_type=df::item_type(57);filter.flags1.whole=0x40;filter.min_dimension=15000;source=0x23e5f78;}
        const auto& inventory=*reinterpret_cast<const std::vector<df::item*>*>(base+source);
        std::vector<df::item*> owned(inventory.begin(),inventory.end()),found;filter.item_vector=&owned;
        reinterpret_cast<void(*)(df::job_item_filter*,std::vector<df::item*>*)>(base+0xa29630)(&filter,&found);
        for(auto* item:found) {
            if(!item)return false;
            const int32_t color=dye?item->isDyeColor():item->getColorWhetherDyedOrNot();
            if(color==-1)continue;
            if(color<0 || size_t(color)>=count)return false;
            auto& value=dye?dyes[size_t(color)]:substrates[size_t(color)];
            const int32_t amount=dye?item->getDyeAmount(color):1;
            if(amount<0 || int64_t(value)+amount>INT32_MAX)return false;
            value+=amount;
        }
        return true;
    };
    if(!collect(true) || (!mixing && !collect(false)))return std::nullopt;
    const auto& first=mixing?dyes:substrates;
    for(int32_t a=0;size_t(a)<count;++a)if(first[a]>0)
        for(int32_t b=mixing?a+1:0;size_t(b)<count;++b)if(a!=b && dyes[b]>0) {
            std::array<int32_t,7> results;results.fill(-1);
            reinterpret_cast<void(*)(std::vector<df::descriptor_color*>*,int32_t,int32_t,int32_t*)>(base+0x7dc570)(&colors,a,b,results.data());
            for(const auto color:results) {
                if(color==-1 || color==a || color==b)continue;
                if(color<0 || size_t(color)>=count)return std::nullopt;
                tints[color]=std::max(tints[color],std::min(first[a],dyes[b]));
            }
        }
    std::vector<WorkshopDyeTarget> rows;
    // Native UI groups color selectors before jobs. Each group is independently
    // ordered by availability pass and then its native caption comparator.
    for(int pass=0;pass<2;++pass)for(int32_t c=0;size_t(c)<count;++c)
        if((tints[c]>0)==(pass==0) && (!mixing || colors[c]->id!="CLEAR"))
            rows.push_back({c,tints[c],mixing?pass:2*pass+1,true});
    if(!mixing)for(int pass=0;pass<2;++pass)for(int32_t c=0;size_t(c)<count;++c)
        if((dyes[c]>0)==(pass==0))rows.push_back({c,dyes[c],2*pass,false});
    return rows;
}
}
