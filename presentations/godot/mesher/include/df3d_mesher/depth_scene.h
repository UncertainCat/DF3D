#pragma once
// Independent whole-scene oracle for tests and explicit diagnostics only.
// Production layout uses LazyTileLayoutCache; no ingestion worker calls this.
#include "df3d_mesher/depth_layout.h"
#include "df3d_mesher/item_stack.h"
#include "df3d_mesher/piece_policy.h"
#include <set>

namespace df3d::mesher {
using BuildingDepthCell = std::tuple<wm::BuildingId,int,int>;
struct BuildingFootprintSource {
    uint64_t version=0;
    std::vector<std::pair<int,int>> cells, foreground;
};
struct DepthSceneSources {
    uint64_t generation=0;
    int top=-1, window=1;
    bool reveal=false, sliceUnits=true;
    std::map<wm::BuildingId,BuildingFootprintSource> buildings;
};
struct PreparedDepthScene {
    bool valid=false;
    std::vector<wm::UnitId> units;
    std::vector<wm::ItemId> items;
    std::vector<int> unitZ, itemZ;
    std::vector<DepthInterval> unitDepth, itemDepth;
    std::map<BuildingDepthCell,DepthInterval> buildings, foreground;
};

inline PreparedDepthScene prepareDepthScene(const wm::WorldModel& model,const DepthSceneSources& source) {
    PreparedDepthScene out;
    if(source.top<0 || source.generation!=model.sessionGeneration()) return out;
    const auto inWindow=[&](int z){return z<=source.top && z>source.top-source.window;};
    const auto visible=[&](wm::TilePos p){const auto t=model.tileAt(p);return source.reveal || !t || !(t->flags&wm::kTileHidden);};
    std::vector<const wm::Building*> buildings;
    model.forEachBuilding([&](const wm::Building& b){if(inWindow(b.z))buildings.push_back(&b);});
    std::sort(buildings.begin(),buildings.end(),[](auto* a,auto* b){return std::tuple(isFurniturePiece(a->kind),a->id)<std::tuple(isFurniturePiece(b->kind),b->id);});
    std::vector<BuildingDepthCell> cells;
    std::set<BuildingDepthCell> foreground;
    std::vector<DepthFootprint> footprints;
    for(const auto* b:buildings) {
        const auto found=source.buildings.find(b->id);
        if(found==source.buildings.end() || found->second.version!=b->version)return out;
        for(const auto& [x,y]:found->second.foreground)foreground.emplace(b->id,b->x1+x,b->y1+y);
        for(const auto& [lx,ly]:found->second.cells) {
            const int x=b->x1+lx,y=b->y1+ly;
            if(!b->occupies(x,y) || !visible({x,y,b->z}))continue;
            cells.emplace_back(b->id,x,y);
            footprints.push_back({x+.5f,y+.5f,.5f,.5f,b->z,isFurniturePiece(b->kind)?1:0});
        }
    }
    for(const auto& layer:visibleItemStackLayers(model,source.top,source.window,source.reveal)) {
        const auto& p=layer.item->pos;
        out.items.push_back(layer.item->id);out.itemZ.push_back(p.z);
        footprints.push_back({p.x+.5f,p.y+.5f,.5f,.5f,p.z,2});
    }
    size_t decals=0;
    while(decals<cells.size() && footprints[decals].category==0) {
        ++decals;
    }
    std::vector<DepthInterval> staticDepth(footprints.size());
    std::unordered_map<DepthTile,float,DepthTileHash> support;
    support.reserve(decals);
    for(size_t i=0;i<decals;++i) {
        const auto& p=footprints[i];
        staticDepth[i]={kInstallationBottom,0};
        auto& value=support[depthTile(p)];value=std::max(value,staticDepth[i].bottom);
    }
    const auto supportAt=[&](const DepthFootprint& p){const auto it=support.find(depthTile(p));return it==support.end()?0.0f:it->second;};
    std::vector<DepthFootprint> volumes(footprints.begin()+decals,footprints.end());
    std::vector<float> supports;
    for(const auto& p:volumes)supports.push_back(supportAt(p));
    const size_t staticCount=volumes.size();
    for(auto id:model.unitIds()) {
        const auto r=model.evaluate(id,double(model.latestTick()));
        if(r.presence!=wm::Presence::Present)continue;
        if(source.sliceUnits && model.hasTerrain() && !inWindow(int(r.pos.z)))continue;
        out.units.push_back(id);out.unitZ.push_back(int(r.pos.z));
        volumes.push_back({r.pos.x+.5f,r.pos.y+.5f,.5f,.5f,int(r.pos.z),3});
        supports.push_back(supportAt(volumes.back()));
    }
    const size_t unitEnd=volumes.size();
    std::vector<int> parents(volumes.size(),-1);
    std::vector<BuildingDepthCell> foregroundKeys;
    for(size_t i=decals;i<cells.size();++i)if(foreground.count(cells[i])) {
        auto p=footprints[i];p.category=4;
        volumes.push_back(p);supports.push_back(supportAt(p));
        parents.push_back(int(i-decals));foregroundKeys.push_back(cells[i]);
    }
    const auto allocated=drawDepthLayout(volumes,parents,supports);
    std::copy(allocated.begin(),allocated.begin()+staticCount,staticDepth.begin()+decals);
    for(size_t i=0;i<cells.size();++i)out.buildings[cells[i]]=staticDepth[i];
    for(size_t i=0;i<foregroundKeys.size();++i)out.foreground[foregroundKeys[i]]=allocated[unitEnd+i];
    out.unitDepth.assign(allocated.begin()+staticCount,allocated.begin()+unitEnd);
    out.itemDepth.assign(staticDepth.begin()+cells.size(),staticDepth.end());
    out.valid=true;
    return out;
}
} // namespace df3d::mesher
