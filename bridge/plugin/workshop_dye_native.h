#pragma once
#include "work_order_dye_native.h"

namespace df3d_production {
struct WorkshopDyeTarget {int32_t color=-1,available=0,alphaOrder=0;bool tint=false;std::string caption,info;int32_t first=-1,second=-1;};

// Native8c597d..8c6cbb builds these lists inline. Only its semantic inventory
// search and color mixer are invoked; all filters, vectors and counts are owned.
// Workshop searches include building/position, unlike global Work orders.
inline std::optional<std::vector<WorkshopDyeTarget>> workshopDyeTargets(df::building* building,int32_t job,int32_t target=-1) {
    if(!building || int(building->getType())!=13 || building->getSubtype()!=21 ||
       (job!=190 && job!=191 && job!=244 && job!=243) || !df::global::world || !workOrderDyeReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x133e;++i){hash^=base[0x8c597d+i];hash*=UINT64_C(1099511628211);}
        if(hash!=UINT64_C(0x0a41fe9bfc54aa4e))return false;
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x8c2670,0x1ed,UINT64_C(0xeb925a19dec78106)},
            {0x52c2b0,0xd8,UINT64_C(0x38b6489e35387929)},
            {0x16159c0,6,UINT64_C(0x8a94945c77812366)},
            {0x161596c,5,UINT64_C(0xbaa2b8c96e977ba9)},
            {0x1615838,5,UINT64_C(0x5844e24667cb6035)},
            {0x1615870,14,UINT64_C(0x8bbdc86cdb98b554)},
            {0x16bec70,12,UINT64_C(0x0391cf9dbe18bb00)},
            {0x16bec80,13,UINT64_C(0x6daea43b911a405c)},
            {0x16bec48,14,UINT64_C(0xc1fa53db19023321)},
            {0x1615890,10,UINT64_C(0xca2c9a7d776f5771)},
            {0x1615860,11,UINT64_C(0x8517038a788c3c2a)},
            {0x16beb38,15,UINT64_C(0x88fca6f071e154f8)},
            {0x16beb48,21,UINT64_C(0x9548569b1f223a6d)},
            {0x16bec18,23,UINT64_C(0x2549936d31f9bdce)},
            {0x16bec30,22,UINT64_C(0xd89520d19424a34b)},
        };
        for(const auto& pin:pins) {
            hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported)return std::nullopt;
    auto& colors=df::global::world->raws.descriptors.colors;
    const size_t count=colors.size();if(count>1024 || target< -1 || (target>=0 && size_t(target)>=count))return std::nullopt;
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
    if(target<0)for(int32_t a=0;size_t(a)<count;++a)if(first[a]>0)
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
    if(target>=0) {
        if(mixing && colors[target]->id=="CLEAR")return std::nullopt;
        // Native8c5c70..8c6022: tint uses ordered substrate/dye pairs; Mix
        // uses unordered dye pairs. Emit once for the first matching result.
        for(int pass=0;pass<2;++pass)for(int32_t a=0;size_t(a)<count;++a) {
            if(a==target)continue;
            for(int32_t b=mixing?a+1:0;size_t(b)<count;++b) {
                if(b==target || b==a)continue;
                const bool stocked=first[a]>0 && dyes[b]>0;
                if(stocked!=(pass==0))continue;
                std::array<int32_t,7> results;results.fill(-1);
                reinterpret_cast<void(*)(std::vector<df::descriptor_color*>*,int32_t,int32_t,int32_t*)>(base+0x7dc570)(&colors,a,b,results.data());
                if(std::find(results.begin(),results.end(),target)==results.end())continue;
                if(rows.size()>=16384)return std::nullopt;
                WorkshopDyeTarget row;row.color=target;row.available=stocked?std::min(first[a],dyes[b]):0;
                row.alphaOrder=pass;row.first=a;row.second=b;rows.push_back(std::move(row));
            }
        }
    }
    if(target<0)for(int pass=0;pass<2;++pass)for(int32_t c=0;size_t(c)<count;++c)
        if((tints[c]>0)==(pass==0) && (!mixing || colors[c]->id!="CLEAR"))
            rows.push_back({c,tints[c],mixing?pass:2*pass+1,true});
    if(target<0 && !mixing)for(int pass=0;pass<2;++pass)for(int32_t c=0;size_t(c)<count;++c)
        if((dyes[c]>0)==(pass==0))rows.push_back({c,dyes[c],2*pass,false});
    const auto literal=[base](size_t rva){return std::string(reinterpret_cast<const char*>(base+rva));};
    for(auto& row:rows) {
        if(row.tint) {
            // Inline text8c2670 uses only job kind, raw color name and literals.
            row.caption=literal(mixing?0x161596c:job==191?0x16bec70:job==190?0x16bec80:0x16bec48)+colors[row.color]->name;
            if(mixing)row.caption+=literal(0x1615838);
            row.caption+=literal(0x1615870);
        } else {
            df::job descriptor;descriptor.job_type=df::job_type(job);
            descriptor.item_type=df::item_type(-1);descriptor.item_subtype=-1;
            descriptor.mat_type=-1;descriptor.mat_index=-1;descriptor.material_category.whole=0;descriptor.specflag.whole=0;
            descriptor.specdata.hist_figure_id=mixing?-1:row.color;descriptor.art_spec.type=df::job_art_specifier_type(-1);
            if(mixing)descriptor.mat_index=row.color;
            descriptor.art_spec.id=row.first;descriptor.art_spec.subid=target>=0?row.second:row.color;
            const auto caption=workshopJobCaption(descriptor);if(!caption)return std::nullopt;
            row.caption=*caption;
        }
        if(row.available>0) {
            std::string number;
            reinterpret_cast<void(*)(int32_t,std::string*)>(base+(mixing || target>=0?0x52c130:0x52c2b0))(row.available,&number);
            row.info=(target>=0?std::string{}:literal(0x1615890))+number+literal(mixing || target>=0?0x1615860:!row.tint?0x16beb38:job==191?0x16beb48:job==244?0x16bec18:0x16bec30);
        }
    }
    for(size_t i=1;i<rows.size();++i) {
        auto row=rows[i];size_t at=i;
        while(at>0) {
            const auto& prior=rows[at-1];bool less;
            if(row.tint!=prior.tint)less=row.tint;
            else if(row.alphaOrder!=prior.alphaOrder)less=row.alphaOrder<prior.alphaOrder;
            else {const auto compared=workshopCaptionLess(row.caption,prior.caption);if(!compared)return std::nullopt;less=*compared;}
            if(!less)break;
            rows[at]=prior;--at;
        }
        rows[at]=std::move(row);
    }
    return rows;
}
}
