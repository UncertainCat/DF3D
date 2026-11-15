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
inline std::optional<uint64_t> depotGoodsRevision(int32_t depotId,const DepotGoods& goods) {
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value){for(unsigned i=0;i<8;++i){hash^=uint8_t(value>>(8*i));hash*=UINT64_C(1099511628211);}};
    add(uint32_t(depotId));add(goods.rows.size());
    for(const auto& row:goods.rows){auto* item=df::item::find(row.id);if(!item)return {};
        // Independent inspection computes weight lazily. Cache validity is not
        // hauling authority; hashing it would invalidate a picker by drawing it.
        auto flags=item->flags;flags.bits.weight_computed=false;
        add(uint32_t(row.id));add(uint32_t(row.distance));add(uint32_t(row.value));add(uint8_t(row.tag));add(row.prohibited);add(flags.whole);}
    add(goods.groups.size());
    for(const auto& group:goods.groups){add(uint16_t(group.type));add(uint16_t(group.subtype));add(uint16_t(group.subcat1));add(uint16_t(group.subcat2));add(uint32_t(group.amount));add(group.expanded);}
    hash&=uint64_t(INT64_MAX);return hash?hash:1;
}
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
    const auto revision=depotGoodsRevision(building->id,*goods);if(!revision)return {};result.revision=*revision;
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
struct DepotGoodsChange {int32_t id=-1;bool desired=false;};
struct DepotGoodsCommit {DepotSettingOutcome outcome=DepotSettingOutcome::Rejected;bool stale=false;uint64_t observedRevision=0;};
// Caller must enforce the transport epoch and saving gate. This safe-point
// preflight binds the entire intent to the same source identity as the read API.
inline DepotGoodsCommit commitDepotGoods(df::building* building,uint64_t expectedRevision,const std::vector<DepotGoodsChange>& changes) {
    DepotGoodsCommit result;
    if(!building || !expectedRevision || expectedRevision>INT64_MAX || changes.empty() || changes.size()>1048576)return result;
    auto* tile=DFHack::Maps::getTileDesignation(building->centerx,building->centery,building->z);
    if(!tile || tile->bits.hidden)return result;
    const auto available=depotFacts(building);if(!available || !available->goods)return result;
    const auto goods=depotGoods(building);if(!goods)return result;
    const auto revision=depotGoodsRevision(building->id,*goods);if(!revision)return result;
    result.observedRevision=*revision;
    if(*revision!=expectedRevision){result.stale=true;return result;}
    std::vector<int32_t> members;members.reserve(goods->rows.size());
    for(const auto& row:goods->rows)members.push_back(row.id);
    std::sort(members.begin(),members.end());
    std::vector<DepotHaulIntent> intents;intents.reserve(changes.size());
    for(const auto& change:changes) {
        if(change.id<0 || !std::binary_search(members.begin(),members.end(),change.id))return result;
        auto* item=df::item::find(change.id);if(!item)return result;
        intents.push_back({change.id,item->flags.whole,change.desired});
    }
    result.outcome=depotSetHaulBatch(building,intents);
    return result;
}

}
