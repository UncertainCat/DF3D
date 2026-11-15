#pragma once
#include "depot_native.h"
#include "df/map_block.h"
#include "df/item.h"
#include "df/items_other_id.h"
#include "df/tradegoodslistst.h"
#include "df/assign_trade_itemlistst.h"
#include "df/assign_trade_interfacest.h"
#include "df/job_item_ref.h"
#include "df/buildingitemst.h"
#include "df/mandate.h"
#include <algorithm>
#include <memory>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <vector>

namespace df3d_production {
// Safe-point only. DF's depot flood accepts a building, not a menu. Preserve
// shared simulation search storage as construction_material_native.cpp does.
namespace depot_goods_detail {
constexpr size_t frontierBytes=2*120000*12;
struct SearchStorage {
    struct Block {df::map_block* block;decltype(df::map_block::path_cost) costs;};
    df::world* world;int32_t generation;int8_t clear;uint8_t* frontier;
    std::vector<uint8_t> bytes;std::vector<Block> blocks;
    SearchStorage(df::world* w,uint8_t* base):world(w),generation(w->pathfinder.pathstart),
        clear(w->pathfinder.pathclear),frontier(base+0x1bb3700),bytes(frontier,frontier+frontierBytes) {
        if(w->map.map_blocks.size()>250000)throw std::runtime_error("depot search storage limit");
        blocks.reserve(w->map.map_blocks.size());
        for(auto* block:w->map.map_blocks)if(block)blocks.push_back({block,block->path_cost});
    }
    ~SearchStorage() {
        for(auto& b:blocks)b.block->path_cost=b.costs;
        std::memcpy(frontier,bytes.data(),frontierBytes);
        world->pathfinder.pathstart=generation;world->pathfinder.pathclear=clear;
    }
};
inline uint64_t storageHash() {
    uint64_t h=UINT64_C(14695981039346656037);
    auto add=[&](const void* p,size_t n){auto* b=static_cast<const uint8_t*>(p);while(n--){h^=*b++;h*=UINT64_C(1099511628211);}};
    auto* w=df::global::world;auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    add(&w->pathfinder.pathstart,sizeof(w->pathfinder.pathstart));add(&w->pathfinder.pathclear,sizeof(w->pathfinder.pathclear));
    add(base+0x1bb3700,frontierBytes);
    for(auto* b:w->map.map_blocks)if(b)add(&b->path_cost,sizeof(b->path_cost));
    return h;
}
}
struct DepotItemDistance {int32_t id=-1,distance=-1,rawDistance=-30000;};
inline std::optional<std::vector<DepotItemDistance>> depotItemDistances(df::building* building,const std::vector<df::item*>& items) {
    auto* depot=virtual_cast<df::building_tradedepotst>(building);auto* world=df::global::world;
    if(!depotNativeReady() || !world || !DFHack::Maps::IsValid() || !depot ||
       depot->getBuildStage()!=depot->getMaxBuildStage() || items.size()>1048576)return {};
    for(auto* job:depot->jobs)if(!job || job->job_type==df::job_type::DestroyBuilding)return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        auto hash=[&](size_t rva,size_t length){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<length;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;};
        return hash(0x5ae710,0x91b)==UINT64_C(0xd87056fdb75e2934) &&
            hash(0xc8baa0,0x11a)==UINT64_C(0x2c62fce4a0555c66);
    }();
    if(!ready)return {};
    try {
        // Resolve positions before entering shared search storage.
        std::vector<df::coord> positions;positions.reserve(items.size());
        for(auto* item:items) {
            if(!item)return {};
            int16_t x=-30000,y=-30000,z=-30000;
            reinterpret_cast<void (*)(df::item*,int16_t*,int16_t*,int16_t*)>(base+0xc8baa0)(item,&x,&y,&z);
            positions.emplace_back(x,y,z);
        }
        std::vector<DepotItemDistance> result;result.reserve(items.size());
        depot_goods_detail::SearchStorage restore(world,base);
        constexpr size_t tails[]={(120000-1)*12,120000*12+(120000-1)*12};
        constexpr int16_t sentinel=std::numeric_limits<int16_t>::min();
        for(auto offset:tails)std::memcpy(restore.frontier+offset,&sentinel,sizeof(sentinel));
        reinterpret_cast<void (*)(df::building_tradedepotst*)>(base+0x5ae710)(depot);
        for(auto offset:tails){int16_t value;std::memcpy(&value,restore.frontier+offset,sizeof(value));if(value!=sentinel)return {};}
        const int64_t generation=world->pathfinder.pathstart;
        for(size_t i=0;i<items.size();++i) {
            const auto p=positions[i];auto* block=DFHack::Maps::getTileBlock(p);
            const int64_t cost=block?block->path_cost[p.x&15][p.y&15]:-1;
            result.push_back({items[i]->id,cost>=generation && cost<generation+1250000?int32_t(cost-generation):-1,
                p.x==-30000?-30000:int32_t((block?cost:0)-generation)});
        }
        return result;
    }catch(const std::exception&){return {};}
}
// Native36c610 visits IN_PLAY, then ac9a10 inserts by native type/material order.
// This is only the unassigned portion;
// already delivered goods and BringItemToDepot jobs are separate native lists.
inline std::optional<std::vector<DepotItemDistance>> depotUnassignedGoods(df::building* building) {
    if(!depotNativeReady() || !df::global::world)return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        auto hash=[&](size_t rva,size_t length){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<length;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;};
        return hash(0xc93160,0x213)==UINT64_C(0x07d957dea30ed105) &&
            hash(0x30cc60,0x199)==UINT64_C(0x4c3ab48da40ca430) &&
            hash(0xac9a10,0x104)==UINT64_C(0x25af1dba04ec4da1) &&
            hash(0xac9230,0x270)==UINT64_C(0xc0aa91d772b24530);
    }();
    if(!ready)return {};
    const auto& source=df::global::world->items.other[df::items_other_id::IN_PLAY];
    if(source.size()>1048576)return {};
    std::vector<df::item*> candidates;candidates.reserve(source.size());
    for(auto* item:source) {
        if(!item)return {};
        if(!reinterpret_cast<bool (*)(df::item*)>(base+0xc93160)(item) &&
           reinterpret_cast<bool (*)(df::item*,bool)>(base+0x30cc60)(item,false))candidates.push_back(item);
    }
    auto distances=depotItemDistances(building,candidates);if(!distances)return {};
    distances->erase(std::remove_if(distances->begin(),distances->end(),[](const auto& row){return row.distance<0;}),distances->end());
    std::vector<df::tradegoodslistst> records(distances->size());
    df::assign_trade_itemlistst ordered;ordered.tgi.reserve(records.size());
    for(size_t i=0;i<records.size();++i) {
        records[i].it=df::item::find((*distances)[i].id);if(!records[i].it)return {};
        records[i].dist=(*distances)[i].distance;
        reinterpret_cast<void (*)(df::assign_trade_itemlistst*,df::tradegoodslistst*)>(base+0xac9a10)(&ordered,&records[i]);
    }
    distances->clear();
    for(auto* row:ordered.tgi)distances->push_back({row->it->id,row->dist});
    return distances;
}
struct DepotGoodsRow {int32_t id=-1,distance=0,value=0;int8_t tag=0;bool prohibited=false;};
struct DepotGoodsGroup {int16_t type=-1,subtype=-1,subcat1=-1,subcat2=-1;int32_t amount=0;bool expanded=false;};
struct DepotGoods {std::vector<DepotGoodsRow> rows;std::vector<DepotGoodsGroup> groups;};
inline bool depotGoodsValuesReady() {
    if(!depotNativeReady())return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        auto hash=[&](size_t rva,size_t length){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<length;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;};
        return hash(0xe5d5b0,0xcf)==UINT64_C(0xa6feeb7ed97addaa) &&
            hash(0xc66020,0x12e)==UINT64_C(0xfe0378c306832ca2) &&
            hash(0xac9c30,0x50a)==UINT64_C(0x7fbce42d6c033414);
    }();
    return ready;
}
inline std::optional<DepotGoods> depotGoods(df::building* building) {
    auto unassigned=depotUnassignedGoods(building);if(!unassigned)return {};
    auto* depot=virtual_cast<df::building_tradedepotst>(building);auto* world=df::global::world;
    if(!depot || !world || depot->contained_items.size()>1048576 || depot->jobs.size()>1048576 || world->mandates.all.size()>1048576 || !depotGoodsValuesReady())return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    std::vector<df::item*> pending;
    for(auto it=depot->jobs.rbegin();it!=depot->jobs.rend();++it) {
        auto* job=*it;if(!job)return {};
        if(job->job_type!=df::job_type::BringItemToDepot)continue;
        if(job->items.empty() || !job->items.front() || !job->items.front()->item)return {};
        pending.push_back(job->items.front()->item);
    }
    auto distances=depotItemDistances(building,pending);if(!distances)return {};
    std::vector<df::tradegoodslistst> records;records.reserve(depot->contained_items.size()+pending.size()+unassigned->size());
    auto add=[&](df::item* item,int8_t tag,int32_t distance) {
        df::tradegoodslistst record;record.it=item;record.tag=tag;record.dist=distance;
        record.value=reinterpret_cast<int32_t (*)(df::item*,void*,void*,bool,bool)>(base+0xc66020)(item,nullptr,nullptr,false,false);
        for(auto* mandate:world->mandates.all)if(mandate && int(mandate->mode)==0 &&
            reinterpret_cast<bool (*)(df::mandate*,df::item*)>(base+0xe5d5b0)(mandate,item)){record.prohibited=true;break;}
        records.push_back(record);
    };
    for(auto* entry:depot->contained_items) {
        if(!entry || !entry->item)return {};
        if(int(entry->use_mode)==0 && (entry->item->flags.whole&0x88020)==0x20)add(entry->item,3,0);
    }
    for(size_t i=0;i<pending.size();++i)add(pending[i],2,(*distances)[i].rawDistance);
    for(const auto& row:*unassigned){auto* item=df::item::find(row.id);if(!item)return {};add(item,0,row.distance);}
    df::assign_trade_itemlistst ordered;ordered.tgi.reserve(records.size());
    df::abstractitemlistst groups;
    for(auto& record:records) {
        reinterpret_cast<void (*)(df::assign_trade_itemlistst*,df::tradegoodslistst*)>(base+0xac9a10)(&ordered,&record);
        reinterpret_cast<void (*)(df::abstractitemlistst*,df::item*)>(base+0xac9c30)(&groups,record.it);
    }
    DepotGoods result;result.rows.reserve(records.size());
    for(auto* record:ordered.tgi)result.rows.push_back({record->it->id,record->dist,record->value,record->tag,record->prohibited});
    const auto count=groups.type.size();
    if(groups.subtype.size()!=count || groups.subcat1.size()!=count || groups.subcat2.size()!=count || groups.amount.size()!=count || groups.expanded.size()!=count)return {};
    for(size_t i=0;i<count;++i)result.groups.push_back({groups.type[i],groups.subtype[i],groups.subcat1[i],groups.subcat2[i],groups.amount[i],groups.expanded[i]});
    return result;
}
// Semantic commit leaf36b0c0. Validate the entire explicit intent before any
// simulation mutation. Draft records/context are owned; native menu state is not
// an input. A public transport receipt must still bind these intents to its epoch.
struct DepotHaulIntent {int32_t id=-1;uint64_t expectedFlags=0;bool desired=false;};
inline DepotSettingOutcome depotSetHaulBatch(df::building* building,const std::vector<DepotHaulIntent>& intents) {
    auto* depot=virtual_cast<df::building_tradedepotst>(building);
    if(!depotNativeReady() || !depot || intents.empty() || intents.size()>1048576 ||
       depot->getBuildStage()!=depot->getMaxBuildStage() || depot->jobs.size()>1048576 ||
       depot->contained_items.size()>1048576)return DepotSettingOutcome::Rejected;
    auto* tile=DFHack::Maps::getTileDesignation(depot->centerx,depot->centery,depot->z);
    if(!tile || tile->bits.hidden)return DepotSettingOutcome::Rejected;
    for(auto* job:depot->jobs)if(!job || job->job_type==df::job_type::DestroyBuilding)return DepotSettingOutcome::Rejected;
    struct Pending {df::item* item;bool desired,delivered;int8_t tag;};
    std::vector<Pending> pending;pending.reserve(intents.size());
    std::vector<int32_t> seen;seen.reserve(intents.size());
    bool needsCandidates=false;
    for(const auto& intent:intents) {
        auto* item=df::item::find(intent.id);
        if(!item || item->flags.whole!=intent.expectedFlags)return DepotSettingOutcome::Rejected;
        seen.push_back(intent.id);
        size_t matches=0,delivered=0;
        for(auto* job:depot->jobs)if(job->job_type==df::job_type::BringItemToDepot && !job->items.empty() &&
            job->items.front() && job->items.front()->item==item)++matches;
        for(auto* entry:depot->contained_items)if(entry && entry->item==item && int(entry->use_mode)==0 &&
            (item->flags.whole&0x88020)==0x20)++delivered;
        if(matches>1 || delivered>1 || (matches && delivered))return DepotSettingOutcome::Rejected;
        const bool changed=intent.desired ? matches==0 && delivered==0 : matches!=0 || delivered!=0;
        needsCandidates|=changed && intent.desired;
        pending.push_back({item,intent.desired,delivered!=0,int8_t(changed?(intent.desired?1:(delivered?-2:-1)):0)});
    }
    std::sort(seen.begin(),seen.end());
    if(std::adjacent_find(seen.begin(),seen.end())!=seen.end())return DepotSettingOutcome::Rejected;
    if(needsCandidates) {
        const auto candidates=depotUnassignedGoods(building);if(!candidates)return DepotSettingOutcome::Rejected;
        std::vector<int32_t> eligible;eligible.reserve(candidates->size());
        for(const auto& row:*candidates)eligible.push_back(row.id);
        std::sort(eligible.begin(),eligible.end());
        for(const auto& row:pending)if(row.tag==1 && !std::binary_search(eligible.begin(),eligible.end(),row.item->id))return DepotSettingOutcome::Rejected;
    }
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        uint64_t h=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x4c8;++i){h^=base[0x36b0c0+i];h*=UINT64_C(1099511628211);}
        return h==UINT64_C(0x05547ce04e52e1ee);
    }();
    if(!ready)return DepotSettingOutcome::Rejected;
    static_assert(offsetof(df::assign_trade_interfacest,master_i_list)==0xa8);
    static_assert(offsetof(df::assign_trade_interfacest,trade_depot_bld)==8);
    df::assign_trade_interfacest context;context.trade_depot_bld=depot;
    std::vector<std::unique_ptr<df::tradegoodslistst>> records;
    records.reserve(pending.size());context.master_i_list.tgi.reserve(pending.size());
    for(const auto& row:pending)if(row.tag) {
        std::unique_ptr<df::tradegoodslistst> record(df::allocate<df::tradegoodslistst>());
        record->it=row.item;record->tag=row.tag;records.push_back(std::move(record));
    }
    if(records.empty())return DepotSettingOutcome::Applied;
    // All allocations and validation precede ownership transfer. Native commit
    // retires records via30ce00; after entry, uncertain outcomes never replay.
    for(auto& record:records)context.master_i_list.tgi.push_back(record.release());
    try {reinterpret_cast<void (*)(df::assign_trade_interfacest*)>(base+0x36b0c0)(&context);}
    catch(...){return DepotSettingOutcome::Unknown;}
    for(const auto& row:pending) {
        size_t matches=0;
        for(auto* job:depot->jobs)if(job && job->job_type==df::job_type::BringItemToDepot &&
            !job->items.empty() && job->items.front() && job->items.front()->item==row.item)++matches;
        if(matches!=size_t(row.desired && !row.delivered) ||
           (row.delivered && row.item->flags.bits.in_building!=row.desired))return DepotSettingOutcome::Unknown;
    }
    return DepotSettingOutcome::Applied;
}
inline DepotSettingOutcome depotSetHaul(df::building* building,df::item* item,uint64_t expectedFlags,bool desired) {
    if(!item)return DepotSettingOutcome::Rejected;
    return depotSetHaulBatch(building,{{item->id,expectedFlags,desired}});
}
}
