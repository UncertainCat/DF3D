#pragma once
// Presentation-only occupancy and lazy layouts. All records own their data;
// no model pointers or engine objects survive a replacement/publication.
#include "df3d_mesher/depth_layout.h"
#include <compare>
#include <array>
#include <cstdint>
#include <list>
#include <map>
#include <optional>
#include <set>
#include <stdexcept>
#include <string>

namespace df3d::mesher {
enum class DepthEntityKind { Building = 0, Item = 1, Unit = 2 };
struct DepthEntityKey {
    DepthEntityKind kind = DepthEntityKind::Building;
    uint64_t entity = 0;
    auto operator<=>(const DepthEntityKey&) const = default;
};
struct DepthPieceId {
    int category = 1; // decal=0, furniture=1, item=2, unit=3, foreground=4
    uint64_t entity = 0, fragment = 0;
    auto operator<=>(const DepthPieceId&) const = default;
};
struct DepthPieceOrder {
    int rank = 0, kind = 0;
    std::string subtypeRaw;
    uint16_t subtype = UINT16_MAX;
    bool operator==(const DepthPieceOrder&) const = default;
};
struct DepthPiece {
    DepthPieceId id;
    DepthFootprint footprint{};
    DepthPieceOrder order; // Used only by item pieces, before entity/quantity ID.
    std::optional<DepthPieceId> parent;
};
struct DepthPieceAllocation {
    DepthPieceId id;
    DepthInterval interval;
    bool collapsed = false;
};
struct LazyTileLayoutStats {
    uint64_t replacements = 0, equalReplacements = 0, removals = 0;
    uint64_t invalidatedTiles = 0, queries = 0, cacheHits = 0;
    uint64_t layoutsBuilt = 0, contributorsVisited = 0, evictions = 0;
    uint64_t candidateBlockChecks = 0, candidateTileChecks = 0;
    size_t owners = 0, occupiedTiles = 0, residentLayouts = 0, pendingInvalidations = 0;
};

class LazyTileLayoutCache {
public:
    explicit LazyTileLayoutCache(size_t capacity = 1024) : capacity_(std::max(size_t(1), capacity)) {}
    LazyTileLayoutCache(const LazyTileLayoutCache&) = delete;
    LazyTileLayoutCache& operator=(const LazyTileLayoutCache&) = delete;
    LazyTileLayoutCache(LazyTileLayoutCache&&) = default;
    LazyTileLayoutCache& operator=(LazyTileLayoutCache&&) = default;
    // Replaces every contribution of this owner atomically. Same records in a
    // different caller order are equal. Invalid identities throw before mutation.
    bool replace(DepthEntityKey owner, std::vector<DepthPiece> pieces);
    bool remove(DepthEntityKey owner);
    // Reference valid until this cache is mutated/queried again. Residency is
    // bounded; occupancy remains indexed even after its computed layout evicts.
    const std::vector<DepthPieceAllocation>& query(DepthTile tile);
    std::vector<DepthTile> consumeDirtyTiles();
    // Category-local ordinal allocation. Changing units never visits/sorts items.
    const std::vector<DepthPieceAllocation>& queryCategory(DepthTile tile, int category);
    size_t categoryCount(DepthTile tile, int category) const;
    uint8_t dirtyCategories(DepthTile tile) const;
    // Inclusive (z,x,y) bounds, enumerating only intersecting 16x16x1 buckets.
    std::vector<DepthTile> occupiedTiles(DepthTile minimum, DepthTile maximum);
    bool needsLayout(DepthTile tile) const;
    uint64_t layoutRevision(DepthTile tile) const;
    void clear(uint64_t epoch);
    uint64_t epoch() const { return epoch_; }
    void setCapacity(size_t capacity);
    LazyTileLayoutStats stats() const;

private:
    struct Cached {
        bool dirty = true;
        uint8_t categoryDirty = 31;
        std::array<std::vector<DepthPieceAllocation>,5> categories;
        uint64_t revision = 0;
        std::vector<DepthPieceAllocation> pieces;
        std::list<DepthTile>::iterator recent;
    };
    static bool equal(const DepthPiece& a, const DepthPiece& b);
    static bool before(const DepthPiece* a, const DepthPiece* b);
    void invalidate(const std::set<DepthTile>& tiles, uint8_t categories);
    void evict();
    static DepthTile blockOf(DepthTile tile);
    void addOccupiedTile(DepthTile tile);
    void removeOccupiedTile(DepthTile tile);
    std::map<DepthEntityKey, std::vector<DepthPiece>> owners_;
    std::unordered_map<DepthTile, std::map<DepthPieceId, DepthPiece>, DepthTileHash> occupancy_;
    std::unordered_map<DepthTile, std::set<DepthTile>, DepthTileHash> occupiedBlocks_;
    std::unordered_map<DepthTile, Cached, DepthTileHash> layouts_;
    std::set<DepthTile> invalidated_;
    std::unordered_map<DepthTile,uint8_t,DepthTileHash> pendingCategories_;
    std::unordered_map<DepthTile,std::array<size_t,5>,DepthTileHash> counts_;
    std::list<DepthTile> recent_;
    size_t capacity_;
    uint64_t epoch_ = 0, revision_ = 0;
    LazyTileLayoutStats counters_;
};
}
