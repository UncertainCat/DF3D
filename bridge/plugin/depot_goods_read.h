#pragma once
#include "depot_selection_native.h"

namespace df3d_production {
struct DepotGoodsCategory {int16_t type=-1;std::string caption;};
struct DepotGoodsDetail {DepotGoodsRow facts;std::string caption;};
struct DepotGoodsRead {
    int32_t depotId=-1;uint64_t revision=0;int16_t category=-1;
    std::vector<DepotGoodsCategory> categories;
    std::vector<DepotSelectedGroup> groups;
    std::vector<DepotGoodsDetail> items;
};
// Safe-point read only. Retains no native pointers, menu state or search storage.
// The source revision covers hauling eligibility/order and group facts, not a
// mutation authorization. A future commit must validate its own complete intent.
inline std::optional<DepotGoodsRead> readDepotGoods(df::building* building,int16_t category,
    const std::string& query,bool distance,bool pending,bool exclude,const std::vector<int32_t>& ids) {
    if(!building || category<-1 || category>=93 || query.size()>512 || ids.size()>64 || (category==-1 && !ids.empty()))return {};
    auto* tile=DFHack::Maps::getTileDesignation(building->centerx,building->centery,building->z);
    if(!tile || tile->bits.hidden)return {};
    const auto available=depotFacts(building);if(!available || !available->goods)return {};
    const auto goods=depotGoods(building);if(!goods)return {};
    const auto categories=depotCategories(*goods,query,exclude);if(!categories)return {};
    DepotGoodsRead result;result.depotId=building->id;result.category=category;
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value){for(unsigned i=0;i<8;++i){hash^=uint8_t(value>>(8*i));hash*=UINT64_C(1099511628211);}};
    add(uint32_t(building->id));add(goods->rows.size());
    for(const auto& row:goods->rows){auto* item=df::item::find(row.id);if(!item)return {};
        add(uint32_t(row.id));add(uint32_t(row.distance));add(uint32_t(row.value));add(uint8_t(row.tag));add(row.prohibited);add(item->flags.whole);}
    add(goods->groups.size());
    for(const auto& group:goods->groups){add(uint16_t(group.type));add(uint16_t(group.subtype));add(uint16_t(group.subcat1));add(uint16_t(group.subcat2));add(uint32_t(group.amount));add(group.expanded);}
    result.revision=(hash&uint64_t(INT64_MAX));if(!result.revision)result.revision=1;
    for(auto type:*categories){auto caption=depotGroupCaption(type);if(!caption)return {};result.categories.push_back({type,std::move(*caption)});}
    if(category==-1)return result;
    auto selection=depotSelection(*goods,category,query,distance,pending,exclude);if(!selection)return {};
    std::vector<int32_t> seen;
    for(auto id:ids){
        if(id<0 || std::find(seen.begin(),seen.end(),id)!=seen.end())return {};seen.push_back(id);
        const auto at=std::find(selection->ids.begin(),selection->ids.end(),id);
        if(at==selection->ids.end())return {};
        const auto row=std::find_if(goods->rows.begin(),goods->rows.end(),[&](const auto& value){return value.id==id;});
        if(row==goods->rows.end())return {};
        result.items.push_back({*row,selection->itemCaptions[size_t(at-selection->ids.begin())]});
    }
    result.groups=std::move(selection->groups);
    return result;
}
}
