#pragma once
#include "wm/world_model.h"
#include <array>
#include <bitset>
#include <list>
#include <map>
#include <limits>
#include <tuple>

namespace df3d_godot {
// Source-local roof evidence shared by every presentation caller. Query bounds
// are discrete DF tile coverage, independent of camera pose and animation.
class SpriteCeilingCache {
public:
    using Bounds = std::array<int,6>; // first x/y/z, last x/y/z (inclusive)
    static constexpr double noCeiling = 1000000.0;
    struct Result { uint64_t revision=0; double ceiling=noCeiling; };
    struct Stats { uint64_t requests=0,hits=0,blockChecks=0,blockSamples=0,tileSamples=0,changes=0,evictions=0; };
    Stats stats;
    explicit SpriteCeilingCache(size_t capacity=8192) : capacity_(std::max(size_t(1),capacity)) {}
    SpriteCeilingCache(const SpriteCeilingCache&)=delete;
    SpriteCeilingCache& operator=(const SpriteCeilingCache&)=delete;
    void clear() { queries_.clear();lru_.clear();blocks_.clear();scope_.reset(); }
    size_t size() const { return queries_.size(); }
    size_t blockCount() const { return blocks_.size(); }
    static bool blocked(const std::optional<wm::TileState>& tile) {
        if(!tile || (tile->flags & wm::kTileHidden))return true;
        return tile->shape!=wm::TileShape::Empty && tile->shape!=wm::TileShape::RampTop && tile->shape!=wm::TileShape::TreeBranch;
    }
    Result query(const wm::WorldModel& model, Bounds bounds, int topZ, int windowDepth) {
        ++stats.requests;
        const auto size=model.mapSize();
        const Scope scope{model.sessionGeneration(),size.x,size.y,size.z,topZ,windowDepth,model.hasTerrain()};
        if(!scope_ || *scope_!=scope) { clear();scope_=scope; }
        bounds[5]=std::min(bounds[5],topZ);
        auto found=queries_.find(bounds);
        if(found==queries_.end()) {
            if(queries_.size()>=capacity_) { queries_.erase(lru_.front());lru_.pop_front();++stats.evictions; }
            lru_.push_back(bounds);
            Entry entry;entry.recency=std::prev(lru_.end());
            if(bounds[0]<=bounds[3] && bounds[1]<=bounds[4] && bounds[2]<=bounds[5]) {
                for(int z=bounds[2];z<=bounds[5];++z)
                    for(int by=blockCoordinate(bounds[1]);by<=blockCoordinate(bounds[4]);++by)
                        for(int bx=blockCoordinate(bounds[0]);bx<=blockCoordinate(bounds[3]);++bx) {
                            Dependency dependency;dependency.position={bx,by,z};
                            for(int y=std::max(bounds[1],by*16);y<=std::min(bounds[4],by*16+15);++y)
                                for(int x=std::max(bounds[0],bx*16);x<=std::min(bounds[3],bx*16+15);++x)
                                    dependency.coverage.set(size_t((y-by*16)*16+x-bx*16));
                            entry.dependencies.push_back(std::move(dependency));
                        }
            }
            found=queries_.emplace(bounds,std::move(entry)).first;
        } else lru_.splice(lru_.end(),lru_,found->second.recency);
        auto& entry=found->second;
        if(entry.terrain==model.terrainVersion()) { ++stats.hits;return entry.result; }
        bool changed=entry.result.revision==0;
        double ceiling=noCeiling;
        for(auto& dependency:entry.dependencies) {
            ++stats.blockChecks;
            const auto& state=block(model,dependency.position);
            const auto relevant=state.occupied & dependency.coverage;
            if(relevant!=dependency.observed) { dependency.observed=relevant;changed=true; }
            if(relevant.any())ceiling=std::min(ceiling,dependency.position.bz-.006);
        }
        entry.terrain=model.terrainVersion();
        if(changed) { entry.result={++nextRevision_,ceiling};++stats.changes; }
        else ++stats.hits;
        return entry.result;
    }
private:
    using Mask=std::bitset<256>;
    using Scope=std::tuple<uint64_t,int,int,int,int,int,bool>;
    struct Block { uint64_t version=UINT64_MAX;Mask occupied; };
    struct Dependency { wm::BlockPos position;Mask coverage,observed; };
    struct Entry {
        uint64_t terrain=UINT64_MAX;Result result;
        std::vector<Dependency> dependencies;
        std::list<Bounds>::iterator recency;
    };
    size_t capacity_;
    uint64_t nextRevision_=0;
    std::optional<Scope> scope_;
    std::map<wm::BlockPos,Block> blocks_;
    std::map<Bounds,Entry> queries_;
    std::list<Bounds> lru_;
    static int blockCoordinate(int tile) { return tile>=0 ? tile/16 : -1-(-(tile+1))/16; }
    const Block& block(const wm::WorldModel& model,wm::BlockPos position) {
        // Queried block residency is bounded independently of source map size.
        // Eviction drops only acceleration data: queries retain their evidence.
        if(blocks_.size()>=65536 && !blocks_.count(position))blocks_.clear();
        auto& cached=blocks_[position];
        const auto version=model.blockVersion(position);
        if(cached.version==version)return cached;
        cached.version=version;++stats.blockSamples;
        const auto view=model.block(position);
        if(!view) { cached.occupied.set();return cached; }
        const auto dimensions=model.mapSize();
        for(int y=0;y<16;++y)for(int x=0;x<16;++x) {
            const size_t tile=size_t(y*16+x);
            cached.occupied[tile]=position.bx*16+x>=dimensions.x || position.by*16+y>=dimensions.y || blocked(view->tiles[tile]);
            ++stats.tileSamples;
        }
        return cached;
    }
};
}
