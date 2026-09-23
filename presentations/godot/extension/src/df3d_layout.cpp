#include "df3d_world.h"
#include "df3d_mesher/item_stack.h"
#include "df3d_mesher/piece_policy.h"
#include "df3d_mesher/terrain_support.h"
#include <godot_cpp/classes/time.hpp>

namespace df3d_godot {
namespace mesher=df3d::mesher;
namespace assets=df3d::assets;
namespace {
uint64_t fragmentKey(int x,int y) { return uint64_t(uint32_t(x))<<32 | uint32_t(y); }
}

void Df3dWorld::set_presentation_region(godot::Rect2i region) {
    const bool enabled=region.size.x>0 && region.size.y>0;
    if (enabled) {
        const auto size = source_.model().mapSize();
        if (size.x > 0 && size.y > 0) {
            // Compare actual map demand. Oversized frusta often cover the same
            // map despite changing block-snapped bounds during camera motion.
            region = region.intersection(godot::Rect2i(0, 0, size.x, size.y));
        }
    }
    if(enabled==presentationRegionEnabled_ && (!enabled || region==presentationRegion_))return;
    PerfScope profile("items.region_invalidation", nullptr, df3d::profiling::detailed());
    presentationRegionEnabled_=enabled;presentationRegion_=region;
    itemsDirty_=true;layoutViewDirty_=true;lastRenderedTick_=UINT64_MAX;
}

int Df3dWorld::presentation_art_margin() const {
    const uint64_t assetHash=assets_?assets_->index.contentHash:0;
    if(assetHash==presentationArtHash_ && presentationAppearanceVersion_==source_.model().itemAppearanceVersion())return presentationArtMargin_;
    presentationArtHash_=assetHash;presentationAppearanceVersion_=source_.model().itemAppearanceVersion();
    int extent=2;
    const auto sprite=[&](const assets::SpriteRef& s){extent=std::max({extent,s.w,s.h});};
    if(assets_) {
        const auto& index=assets_->index;
        for(const auto& [name,variants]:index.tileGraphics)for(const auto& s:variants)sprite(s);
        for(const auto& [name,item]:index.itemDefs) {sprite(item.base);for(const auto& [key,s]:item.variants)sprite(s);}
        for(const auto& [name,plant]:index.plants) {sprite(plant.picked);sprite(plant.seed);sprite(plant.growthPicked);}
        for(const auto& [name,creature]:index.creatures)for(const auto& [key,s]:creature.states)sprite(s);
        for(const auto& [name,creature]:index.creatureCastes)for(const auto& [key,s]:creature.states)sprite(s);
        for(const auto& [name,s]:index.boulderGraphics)sprite(s);
        for(const auto& [name,s]:index.barsGraphics)sprite(s);
        for(const auto& [name,s]:index.roughGemGraphics)sprite(s);
    }
    source_.model().forEachItemAppearance([&](auto,const auto& appearance) {
        for(const auto& layer:appearance.layers)
            extent=std::max({extent,int(layer.cellsX)+std::abs(int(layer.offsetX)),int(layer.cellsY)+std::abs(int(layer.offsetY))});
    });
    // Full diameter accommodates unions of oppositely offset layers.
    presentationArtMargin_=extent*2;
    return presentationArtMargin_;
}

void Df3dWorld::syncLayoutBuilding(wm::BuildingId id) {
    const auto* b=source_.model().building(id);
    const mesher::DepthEntityKey owner{mesher::DepthEntityKind::Building,id};
    std::vector<mesher::DepthPiece> pieces;
    if(const auto old=layoutBuildingBlocks_.find(id);old!=layoutBuildingBlocks_.end()) {
        for(const auto& block:old->second) {
            auto owners=layoutBuildingsByBlock_.find(block);
            if(owners!=layoutBuildingsByBlock_.end()) {
                owners->second.erase(id);
                if(owners->second.empty())layoutBuildingsByBlock_.erase(owners);
            }
        }
        layoutBuildingBlocks_.erase(old);
    }
    if(b && zInWindow(b->z)) {
        auto found=buildingFootprintCache_.find(id);
        if(found==buildingFootprintCache_.end() || found->second.version!=b->version) {
            PerfScope timer{"buildings.footprint", &perfFootprintMs_};
            found=buildingFootprintCache_.insert_or_assign(id,resolveBuildingFootprint(*b)).first;
        } else ++perfFootprintHits_;
        const int category=mesher::isFurniturePiece(b->kind)?1:0;
        for(const auto& [lx,ly]:found->second.cells) {
            const int x=b->x1+lx,y=b->y1+ly;
            const LayoutBlock block{b->z,int(std::floor(double(x)/16)),int(std::floor(double(y)/16))};
            layoutBuildingBlocks_[id].insert(block);layoutBuildingsByBlock_[block].insert(id);
            // Artwork-only spill tracks visibility, but never supports a pile.
            if(!b->occupies(x,y) || !tileVisible({x,y,b->z}))continue;
            mesher::DepthPiece piece;
            piece.id={category,id,fragmentKey(x,y)};
            piece.footprint={x+.5f,y+.5f,.5f,.5f,b->z,category};
            pieces.push_back(piece);
        }
    }
    tileLayouts_.replace(owner,std::move(pieces));
}

void Df3dWorld::syncLayoutItem(wm::ItemId id) {
    const auto* item=source_.model().item(id);
    std::vector<mesher::DepthPiece> pieces;
    if(item && zInWindow(item->pos.z) && tileVisible(item->pos)) {
        for(int quantity=0;quantity<(item->stack>1?2:1);++quantity) {
            mesher::DepthPiece piece;
            piece.id={2,id,uint64_t(quantity)};
            const auto p=item->pos;
            piece.footprint={p.x+.5f,p.y+.5f,.5f,.5f,p.z,2};
            piece.order={mesher::itemStackRank(item->kind),int(item->kind),item->subtypeRaw,
                item->subtypeRaw.empty()?item->subtype:wm::kNoSubtype};
            pieces.push_back(std::move(piece));
        }
    }
    tileLayouts_.replace({mesher::DepthEntityKind::Item,id},std::move(pieces));
}

void Df3dWorld::resetLayoutScope() {
    tileLayouts_.clear(source_.model().sessionGeneration());
    layoutUnitTiles_.clear();unitDepthById_.clear();unitStackOrdinalById_.clear();
    const auto size=source_.model().mapSize();
    stackAtlas_.reset(size.x,size.y,std::max(0,topZ_-windowDepth_+1),topZ_-std::max(0,topZ_-windowDepth_+1)+1);
    terrainSupportDependencies_.clear();
    for(int z=std::max(0,topZ_-windowDepth_+1);z<=topZ_;++z)
        for(int y=0;y<size.y;y+=16)for(int x=0;x<size.x;x+=16)
            if(source_.model().block({x/16,y/16,z}))refreshTerrainSupport({x/16,y/16,z},false);
    layoutBuildingBlocks_.clear();layoutBuildingsByBlock_.clear();
    layoutBuildingChanges_.clear();layoutItemChanges_.clear();
    source_.model().forEachBuilding([&](const auto& b){if(zInWindow(b.z))syncLayoutBuilding(b.id);});
    source_.model().forEachItemInZRange(std::max(0,topZ_-windowDepth_+1),topZ_,[&](const auto& item){syncLayoutItem(item.id);});
    layoutScopeDirty_=false;
    layoutViewDirty_=true;
}

godot::Vector3 Df3dWorld::ground_support(godot::Vector3 p) const {
    const int x=int(std::floor(p.x)),y=int(std::floor(p.z)),z=int(std::floor(p.y));
    const auto s=mesher::rampSupport(stackAtlas_.ground(x,y,z),p.x-x,p.z-y);
    return {s.dx,s.lift,s.dy};
}

void Df3dWorld::refreshTerrainSupport(wm::BlockPos block,bool invalidateBuildings) {
    if(!zInWindow(block.bz))return;
    const auto view=source_.model().block(block);
    const auto changed=terrainSupportDependencies_.observe(block,view?view->tiles:nullptr,revealHidden_);
    ++supportBlocksChecked_;
    if(changed.none()) { ++supportBlocksSkipped_;return; }
    const auto affected=[&](int x,int y) {
        const int lx=x-block.bx*16,ly=y-block.by*16;
        return lx>=0 && ly>=0 && lx<16 && ly<16 && changed.test(wm::tileIndexInBlock(lx,ly));
    };
    const auto size=source_.model().mapSize();
    // Fetch neighboring blocks once. Initial scope population must not perform
    // a world-model map lookup for every tile (or every ramp neighbor).
    std::array<std::optional<wm::BlockView>,9> neighbors;
    for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx)
        neighbors[(dy+1)*3+dx+1]=dx==0 && dy==0?view:source_.model().block({block.bx+dx,block.by+dy,block.bz});
    const auto read=[&](wm::TilePos p)->std::optional<wm::TileState> {
        if(p.x<0 || p.y<0 || p.x>=size.x || p.y>=size.y)return {};
        const auto& b=neighbors[(p.y/16-block.by+1)*3+p.x/16-block.bx+1];
        if(!b)return {};
        return b->tiles[wm::tileIndexInBlock(p.x%16,p.y%16)];
    };
    // A changed edge wall also changes the ramp in the adjacent block.
    for(int y=std::max(0,block.by*16-1);y<std::min(size.y,block.by*16+17);++y)
        for(int x=std::max(0,block.bx*16-1);x<std::min(size.x,block.bx*16+17);++x) {
            if(!affected(x,y) && !affected(x-1,y) && !affected(x+1,y) && !affected(x,y-1) && !affected(x,y+1))continue;
            ++supportTilesEvaluated_;
            const int code=mesher::rampSupportCode(wm::TilePos{x,y,block.bz},read,revealHidden_);
            if(!stackAtlas_.setGround(x,y,block.bz,code))continue;
            ++supportTilesChanged_;
            if(!invalidateBuildings)continue;
            const auto owners=layoutBuildingsByBlock_.find({block.bz,x/16,y/16});
            if(owners==layoutBuildingsByBlock_.end())continue;
            for(auto id:owners->second) {
                const auto* b=source_.model().building(id);
                const auto art=buildingFootprintCache_.find(id);
                if(!b || art==buildingFootprintCache_.end())continue;
                if(std::find(art->second.cells.begin(),art->second.cells.end(),std::pair{x-b->x1,y-b->y1})!=art->second.cells.end())enqueueBuilding(id,submission::Layout);
            }
        }
}

void Df3dWorld::applyTileLayout(mesher::DepthTile tile,bool forceItems) {
    PerfScope profile("layout.tile", nullptr, df3d::profiling::detailed());
    const int objects=int(tileLayouts_.categoryCount(tile,2));
    const int creatures=int(tileLayouts_.categoryCount(tile,3));
    const float support=tileLayouts_.categoryCount(tile,1)>0
        ?mesher::kBuildingBottom+mesher::kBuildingThickness+mesher::kBuildingSpillBias
        :tileLayouts_.categoryCount(tile,0)>0?mesher::kInstallationBottom:0;
    const auto [z,x,y]=tile;
    stackAtlas_.set(x,y,z,support,objects,creatures);
    int probeItems=0,probeUnits=0,probeChanged=0;
    if(forceItems || (tileLayouts_.dirtyCategories(tile)&4)) {
        for(const auto& piece:tileLayouts_.queryCategory(tile,2)) {
            ++probeItems;
            const auto found=itemInstanceIndices_.find(wm::ItemId(piece.id.entity));
            if(found==itemInstanceIndices_.end() || piece.id.fragment>=found->second.size())continue;
            const int index=found->second[piece.id.fragment];
            auto p=itemPositions_[index];p.y=float(z)+mesher::kFloorHeight;
            const float ordinal=piece.interval.bottom;
            if(p!=itemPositions_[index] || itemThicknesses_[index]!=.12f || itemStackOrdinals_[index]!=ordinal) {
                itemPositions_.set(index,p);itemThicknesses_.set(index,.12f);itemStackOrdinals_.set(index,ordinal);
                markItemInstanceChanged(index);++probeChanged;
            }
        }
    }
    // Unit lists are small and independent. Item membership can alter their
    // resolved CPU depths for picking without walking/reordering the items.
    for(const auto& piece:tileLayouts_.queryCategory(tile,3)) {
        ++probeUnits;
        const auto id=wm::UnitId(piece.id.entity);
        unitStackOrdinalById_[id]=piece.interval.bottom;
        unitDepthById_[id]=mesher::sharedStackInterval(support,objects,creatures,3,int(piece.interval.bottom));
    }
    if(layoutCausalProbe_.active)layoutCausalProbe_.applied(tile,probeItems,probeUnits,probeChanged);
}

void Df3dWorld::updatePresentationLayout() {
    PerfScope timer{"layout.update", &perfDepthMs_};
    static const bool probeRequested=[] { const auto* value=std::getenv("DF3D_ITEM_PROBE"); return value && std::strcmp(value,"1")==0; }();
    const bool probing=probeRequested && df3d::profiling::global().mode()==df3d::profiling::Mode::Deep;
    layoutCausalProbe_.begin(probing,probing?godot::Time::get_singleton()->get_ticks_usec():0,
        source_.model().latestTick(),layoutScopeDirty_,layoutViewDirty_);
    if(layoutScopeDirty_)resetLayoutScope();
    for(auto id:layoutBuildingChanges_)syncLayoutBuilding(id);
    layoutBuildingChanges_.clear();
    std::set<mesher::DepthTile> requested;
    for(auto id:layoutItemChanges_) {
        if(probing)if(const auto* item=source_.model().item(id))
            layoutCausalProbe_.item({item->pos.z,item->pos.x,item->pos.y});
        syncLayoutItem(id);
        if(const auto* item=source_.model().item(id);item && zInWindow(item->pos.z))
            requested.emplace(item->pos.z,item->pos.x,item->pos.y);
    }
    layoutItemChanges_.clear();
    std::map<wm::UnitId,wm::TilePos> next;
    depthUnitContents_.clear();
    for(int i=0;i<ids_.size();++i) {
        const auto id=wm::UnitId(ids_[i]);
        const auto r=source_.model().evaluate(id,double(source_.model().latestTick()));
        const wm::TilePos p{int(r.pos.x),int(r.pos.y),int(r.pos.z)};
        next[id]=p;depthUnitContents_.emplace_back(id,p.x,p.y,p.z);
        const auto previous=layoutUnitTiles_.find(id);
        if(previous!=layoutUnitTiles_.end() && previous->second==p)continue;
        if(probing) {
            layoutCausalProbe_.arrival({p.z,p.x,p.y});
            if(previous!=layoutUnitTiles_.end()) {
                const auto old=previous->second;
                layoutCausalProbe_.departure({old.z,old.x,old.y});
            }
        }
        mesher::DepthPiece piece;
        piece.id={3,id,0};piece.footprint={p.x+.5f,p.y+.5f,.5f,.5f,p.z,3};
        tileLayouts_.replace({mesher::DepthEntityKind::Unit,id},{piece});
    }
    for(const auto& [id,p]:layoutUnitTiles_)if(!next.count(id)) {
        if(probing)layoutCausalProbe_.departure({p.z,p.x,p.y});
        tileLayouts_.remove({mesher::DepthEntityKind::Unit,id});unitDepthById_.erase(id);unitStackOrdinalById_.erase(id);
    }
    layoutUnitTiles_=std::move(next);
    for(const auto tile:tileLayouts_.consumeDirtyTiles())requested.insert(tile);
    if(layoutViewDirty_) {
        const auto size=source_.model().mapSize();
        const auto p=presentationRegionEnabled_?presentationRegion_.position:godot::Vector2i(0,0);
        const auto end=presentationRegionEnabled_?presentationRegion_.get_end():godot::Vector2i(size.x,size.y);
        for(const auto tile:tileLayouts_.occupiedTiles({std::max(0,topZ_-windowDepth_+1),p.x,p.y},
                {topZ_,end.x-1,end.y-1}))requested.insert(tile);
    }
    const bool forceItems=layoutViewDirty_;
    layoutViewDirty_=false;
    // Animated units remain prepared for interpolation/shadows. Their complete
    // piles participate even outside the item materialization region.
    std::set<mesher::DepthTile> unitTiles;
    for(const auto& [id,p]:layoutUnitTiles_)unitTiles.emplace(p.z,p.x,p.y);
    for(const auto tile:requested) {
        const auto [z,x,y]=tile;
        if(presentationTileDemanded({x,y,z}) || unitTiles.count(tile))applyTileLayout(tile,forceItems);
    }
    stackAtlas_.flush();
    if(!requested.empty())++perfDepthCount_;
    unitDepthBottoms_.resize(ids_.size());unitThicknesses_.resize(ids_.size());
    unitStackOrdinals_.resize(ids_.size());unitStackTiles_.resize(ids_.size());
    auto* thickness=unitThicknesses_.ptrw();
    for(int i=0;i<ids_.size();++i) {
        const auto d=unitDepthById_.at(wm::UnitId(ids_[i]));
        unitDepthBottoms_[i]=d.bottom;thickness[i]=d.thickness;
        const auto id=wm::UnitId(ids_[i]);const auto tile=layoutUnitTiles_.at(id);
        unitStackOrdinals_.set(i,unitStackOrdinalById_.at(id));
        unitStackTiles_.set(i,godot::Vector3(tile.x,tile.z,tile.y));
    }
    updateUnitCutoutPositions();
    if(probing)layoutCausalProbe_.finish();
}
}
