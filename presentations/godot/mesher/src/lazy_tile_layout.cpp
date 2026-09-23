#include "df3d_mesher/lazy_tile_layout.h"
#include <limits>
#include <string_view>

namespace df3d::mesher {
DepthTile LazyTileLayoutCache::blockOf(DepthTile tile) {
    const auto [z,x,y] = tile;
    return {z,x/16-(x%16<0),y/16-(y%16<0)};
}
void LazyTileLayoutCache::addOccupiedTile(DepthTile tile) {
    occupiedBlocks_[blockOf(tile)].insert(tile);
}
void LazyTileLayoutCache::removeOccupiedTile(DepthTile tile) {
    const auto found = occupiedBlocks_.find(blockOf(tile));
    found->second.erase(tile);
    if (found->second.empty()) occupiedBlocks_.erase(found);
}
std::vector<DepthTile> LazyTileLayoutCache::occupiedTiles(DepthTile minimum, DepthTile maximum) {
    const auto [z0,x0,y0] = minimum; const auto [z1,x1,y1] = maximum;
    if (z0>z1 || x0>x1 || y0>y1) return {};
    const auto [unused0,bx0,by0] = blockOf(minimum);
    const auto [unused1,bx1,by1] = blockOf(maximum);
    std::vector<DepthTile> result;
    for (int64_t z=z0;z<=z1;++z) for (int64_t x=bx0;x<=bx1;++x) for (int64_t y=by0;y<=by1;++y) {
        ++counters_.candidateBlockChecks;
        const auto found = occupiedBlocks_.find({int(z),int(x),int(y)});
        if (found == occupiedBlocks_.end()) continue;
        for (const auto& tile : found->second) {
            ++counters_.candidateTileChecks;
            const auto [tz,tx,ty] = tile;
            if (tx>=x0 && tx<=x1 && ty>=y0 && ty<=y1) result.push_back(tile);
        }
    }
    std::sort(result.begin(),result.end());
    return result;
}
bool LazyTileLayoutCache::equal(const DepthPiece& a, const DepthPiece& b) {
    const auto& x = a.footprint; const auto& y = b.footprint;
    return a.id == b.id && a.order == b.order && a.parent == b.parent &&
        std::tie(x.x,x.y,x.halfX,x.halfY,x.z,x.category) ==
        std::tie(y.x,y.y,y.halfX,y.halfY,y.z,y.category);
}
bool LazyTileLayoutCache::before(const DepthPiece* a, const DepthPiece* b) {
    if (a->id.category != b->id.category) return a->id.category < b->id.category;
    if (a->id.category == 2) {
        const auto order = [](const DepthPiece& p) {
            return std::tuple{p.order.rank,p.order.kind,std::string_view(p.order.subtypeRaw),
                p.order.subtypeRaw.empty() ? p.order.subtype : uint16_t(UINT16_MAX),
                p.id.entity,p.id.fragment};
        };
        return order(*a) < order(*b);
    }
    return a->id < b->id;
}
void LazyTileLayoutCache::invalidate(const std::set<DepthTile>& tiles, uint8_t categories) {
    counters_.invalidatedTiles += tiles.size();
    for (const auto& tile : tiles) {
        invalidated_.insert(tile);
        if(categories&12)pendingCategories_[tile]|=categories&12;
        if (auto found = layouts_.find(tile); found != layouts_.end()) { found->second.dirty = true; found->second.categoryDirty |= categories; }
    }
}
bool LazyTileLayoutCache::replace(DepthEntityKey owner, std::vector<DepthPiece> pieces) {
    if (owner.kind != DepthEntityKind::Building && owner.kind != DepthEntityKind::Item && owner.kind != DepthEntityKind::Unit)
        throw std::invalid_argument("invalid lazy depth owner domain");
    if (pieces.empty()) return remove(owner);
    // Validate before removing anything; caller errors never leave half an owner.
    std::set<DepthPieceId> identities;
    for (auto& p : pieces) {
        const int category = p.id.category;
        const bool domain = owner.kind == DepthEntityKind::Building ?
            (category == 0 || category == 1 || category == 4) :
            owner.kind == DepthEntityKind::Item ? category == 2 : category == 3;
        const auto coordinate = [](float value) {
            return std::isfinite(value) && double(std::floor(value)) >= std::numeric_limits<int>::min() &&
                double(std::floor(value)) <= std::numeric_limits<int>::max();
        };
        if (!domain || p.id.entity != owner.entity || !identities.insert(p.id).second ||
            !coordinate(p.footprint.x) || !coordinate(p.footprint.y) ||
            !std::isfinite(p.footprint.halfX) || !std::isfinite(p.footprint.halfY) ||
            p.footprint.halfX < 0 || p.footprint.halfY < 0)
            throw std::invalid_argument("invalid lazy depth contribution identity or footprint");
        p.footprint.category = category;
    }
    std::sort(pieces.begin(),pieces.end(),[](const auto& a,const auto& b){return a.id < b.id;});
    const auto old = owners_.find(owner);
    if (old != owners_.end() && old->second.size() == pieces.size() &&
        std::equal(pieces.begin(),pieces.end(),old->second.begin(),equal)) {
        ++counters_.equalReplacements;
        return false;
    }
    std::set<DepthTile> touched;
    if (old != owners_.end()) for (const auto& p : old->second) {
        const auto tile = depthTile(p.footprint);
        touched.insert(tile);
        auto bucket = occupancy_.find(tile);
        bucket->second.erase(p.id);
        --counts_.at(tile)[p.id.category];
        if (bucket->second.empty()) { occupancy_.erase(bucket); counts_.erase(tile); removeOccupiedTile(tile); }
    }
    for (const auto& p : pieces) {
        const auto tile = depthTile(p.footprint);
        touched.insert(tile);
        auto [bucket, inserted] = occupancy_.try_emplace(tile);
        if (inserted) addOccupiedTile(tile);
        bucket->second.emplace(p.id,p);
        ++counts_[tile][p.id.category];
    }
    owners_[owner] = std::move(pieces);
    invalidate(touched,owner.kind==DepthEntityKind::Building ? 19 : owner.kind==DepthEntityKind::Item ? 4 : 8);
    ++counters_.replacements;
    return true;
}
bool LazyTileLayoutCache::remove(DepthEntityKey owner) {
    const auto found = owners_.find(owner);
    if (found == owners_.end()) return false;
    std::set<DepthTile> touched;
    for (const auto& p : found->second) {
        const auto tile = depthTile(p.footprint);
        touched.insert(tile);
        auto bucket = occupancy_.find(tile);
        bucket->second.erase(p.id);
        --counts_.at(tile)[p.id.category];
        if (bucket->second.empty()) { occupancy_.erase(bucket); counts_.erase(tile); removeOccupiedTile(tile); }
    }
    owners_.erase(found);
    invalidate(touched,owner.kind==DepthEntityKind::Building ? 19 : owner.kind==DepthEntityKind::Item ? 4 : 8);
    ++counters_.removals;
    return true;
}

size_t LazyTileLayoutCache::categoryCount(DepthTile tile,int category) const {
    const auto found=counts_.find(tile);
    return found==counts_.end()?0:found->second.at(category);
}
uint8_t LazyTileLayoutCache::dirtyCategories(DepthTile tile) const {
    const auto found=pendingCategories_.find(tile);
    return found==pendingCategories_.end()?0:found->second;
}
const std::vector<DepthPieceAllocation>& LazyTileLayoutCache::queryCategory(DepthTile tile,int category) {
    if(category<0 || category>4)throw std::invalid_argument("invalid depth category");
    ++counters_.queries;
    auto [found,inserted]=layouts_.try_emplace(tile);
    auto& cached=found->second;
    if(inserted) { recent_.push_front(tile);cached.recent=recent_.begin(); }
    else recent_.splice(recent_.begin(),recent_,cached.recent);
    auto& result=cached.categories[category];
    if(!(cached.categoryDirty&(1<<category))) { ++counters_.cacheHits;return result; }
    result.clear();
    std::vector<const DepthPiece*> pieces;
    if(const auto occupied=occupancy_.find(tile);occupied!=occupancy_.end()) {
        for(auto p=occupied->second.lower_bound({category,0,0});p!=occupied->second.end() && p->first.category==category;++p)
            pieces.push_back(&p->second);
    }
    counters_.contributorsVisited+=pieces.size();
    std::sort(pieces.begin(),pieces.end(),before);
    for(size_t i=0;i<pieces.size();++i)result.push_back({pieces[i]->id,{float(i),.12f},false});
    cached.categoryDirty&=uint8_t(~(1<<category));
    if(auto pending=pendingCategories_.find(tile);pending!=pendingCategories_.end()) {
        pending->second&=uint8_t(~(1<<category));
        if(!pending->second)pendingCategories_.erase(pending);
    }
    ++counters_.layoutsBuilt;evict();return result;
}
const std::vector<DepthPieceAllocation>& LazyTileLayoutCache::query(DepthTile tile) {
    ++counters_.queries;
    auto [found, inserted] = layouts_.try_emplace(tile);
    auto& cached = found->second;
    if (inserted) {
        recent_.push_front(tile);
        cached.recent = recent_.begin();
    } else recent_.splice(recent_.begin(),recent_,cached.recent);
    if (!cached.dirty) { ++counters_.cacheHits; return cached.pieces; }
    cached.pieces.clear();
    std::vector<const DepthPiece*> pieces;
    if (const auto occupants = occupancy_.find(tile); occupants != occupancy_.end()) {
        pieces.reserve(occupants->second.size());
        for (const auto& [id,p] : occupants->second) pieces.push_back(&p);
    }
    counters_.contributorsVisited += pieces.size();
    std::sort(pieces.begin(),pieces.end(),before);
    size_t decals = 0;
    while (decals < pieces.size() && pieces[decals]->id.category == 0) {
        ++decals;
    }
    float support = 0;
    cached.pieces.reserve(pieces.size());
    for (size_t i = 0; i < decals; ++i) {
        const auto& p = *pieces[i];
        const DepthInterval interval{kInstallationBottom,0};
        cached.pieces.push_back({p.id,interval,false});
        support = std::max(support,interval.bottom);
    }
    std::vector<DepthFootprint> volumes;
    std::vector<int> parents;
    std::map<DepthPieceId,int> indices;
    for (size_t i = decals; i < pieces.size(); ++i) {
        const auto& p = *pieces[i];
        const auto parent = p.parent ? indices.find(*p.parent) : indices.end();
        parents.push_back(parent == indices.end() ? -1 : parent->second);
        indices.emplace(p.id,int(volumes.size()));
        volumes.push_back(p.footprint);
    }
    const auto intervals = drawDepthLayout(volumes,parents,std::vector<float>(volumes.size(),support));
    for (size_t i = 0; i < intervals.size(); ++i) {
        const auto& p = *pieces[decals+i];
        cached.pieces.push_back({p.id,intervals[i],p.id.category == 4 && parents[i] >= 0});
    }
    cached.dirty = false;
    cached.revision = ++revision_;
    ++counters_.layoutsBuilt;
    evict();
    return cached.pieces;
}
std::vector<DepthTile> LazyTileLayoutCache::consumeDirtyTiles() {
    std::vector<DepthTile> result(invalidated_.begin(),invalidated_.end());
    invalidated_.clear();
    return result;
}
bool LazyTileLayoutCache::needsLayout(DepthTile tile) const {
    const auto found = layouts_.find(tile);
    return found == layouts_.end() || found->second.dirty;
}
uint64_t LazyTileLayoutCache::layoutRevision(DepthTile tile) const {
    const auto found = layouts_.find(tile);
    return found == layouts_.end() ? 0 : found->second.revision;
}
void LazyTileLayoutCache::evict() {
    while (layouts_.size() > capacity_) {
        layouts_.erase(recent_.back()); recent_.pop_back(); ++counters_.evictions;
    }
}
void LazyTileLayoutCache::setCapacity(size_t capacity) {
    capacity_ = std::max(size_t(1),capacity);
    evict();
}
void LazyTileLayoutCache::clear(uint64_t epoch) {
    owners_.clear(); pendingCategories_.clear(); counts_.clear(); occupancy_.clear(); occupiedBlocks_.clear(); layouts_.clear(); invalidated_.clear(); recent_.clear();
    epoch_ = epoch;
    // Revisions stay monotonic across epochs and ID reuse.
}
LazyTileLayoutStats LazyTileLayoutCache::stats() const {
    auto out = counters_;
    out.owners = owners_.size(); out.occupiedTiles = occupancy_.size();
    out.residentLayouts = layouts_.size(); out.pendingInvalidations = invalidated_.size();
    return out;
}
}
