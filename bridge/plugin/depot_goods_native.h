#pragma once
#include "depot_native.h"
#include "df/map_block.h"
#include "df/item.h"
#include "df/items_other_id.h"
#include "df/tradegoodslistst.h"
#include "df/assign_trade_itemlistst.h"
#include <algorithm>
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
struct DepotItemDistance {int32_t id=-1,distance=-1;};
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
            result.push_back({items[i]->id,cost>=generation && cost<generation+1250000?int32_t(cost-generation):-1});
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
}
