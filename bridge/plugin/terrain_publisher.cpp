#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "df/building_doorst.h"
#include "df/building_grate_wallst.h"
#include "df/building_bars_verticalst.h"
#include "df/buildings_other_id.h"
#include "map_warning_policy.h"
#include "terrain_publisher.h"
#include "PluginManager.h"
#include "TileTypes.h"
#include "modules/MapCache.h"
#include "modules/Maps.h"
#include "modules/Materials.h"
#include "df/block_square_event_grassst.h"
#include "df/block_square_event_designation_priorityst.h"
#include "df/builtin_mats.h"
#include "df/block_square_event_mineralst.h"
#include "df/construction.h"
#include "df/engraving.h"
#include "df/feature_init.h"
#include "df/inorganic_raw.h"
#include "df/job.h"
#include "df/job_type.h"
#include "df/map_block.h"
#include "df/map_block_column.h"
#include "df/material.h"
#include "df/plant.h"
#include "df/plant_raw.h"
#include "df/plant_root_tile.h"
#include "df/plant_tree_info.h"
#include "df/plant_tree_tile.h"
#include "df/unit.h"
#include "df/world.h"
#include "ground_spatters.h"
#include "job_list_stamp.h"
#include "pending_work.h"
#include "scan_schedule.h"
#include "track_terrain.h"
#include "terrain_util.h"
#include "entity_util.h"
#include "shm_layout.h"
#include <algorithm>
#include <chrono>
#include <cstring>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#endif
using namespace DFHack;
using df::global::world;
using std::string;
using std::vector;
namespace mir = df3d::mirror;
namespace shm = df3d::shm;
namespace {
using Clock = std::chrono::steady_clock;
double usSince(Clock::time_point start) {
    return std::chrono::duration<double,std::micro>(Clock::now()-start).count();
}
}
struct TerrainPublisher::Impl {
    // ---- terrain change detection state ----

    // Raw shadow of what we last classified from a block: the tiletype array,
    // the designation bits that feed the published TileState and a per-tile
    // signature of the occupancy / temperature / priority inputs of the
    // designation details. Comparing these per block is the cheap gate in
    // front of the expensive designationDetails() pass and reclassification.
    struct ShadowBlock {
        uint8_t allocated = 0;  // block pointer was non-null when last scanned
        uint8_t scanned = 0;    // scanned at least once (0 = grid block never written)
        uint8_t pad[6] = {};
        uint16_t tiletype[256] = {};
        uint32_t dsgn[256] = {};
        uint16_t signature[256] = {};   // blockSignature(): occupancy, traffic, warm, priority
        uint32_t dampBits[8] = {};      // miningDampSource() per tile: neighbours depend on it
        uint32_t designationDetails[256] = {};
    };
    static_assert(sizeof(ShadowBlock) == 8 + 512 + 1024 + 512 + 32 + 1024, "shadow layout");

    // Designation bits that influence the published tile: liquid amount/type,
    // dig designation, smooth, hidden, outside, aquifer. Everything else
    // (piles, light, biome, ...) changing must not trigger a reclassification;
    // traffic rides in the signature below.
    static constexpr uint32_t kDsgnMask =
        df::tile_designation::mask_flow_size | df::tile_designation::mask_dig |
        df::tile_designation::mask_smooth | df::tile_designation::mask_hidden |
        df::tile_designation::mask_outside | df::tile_designation::mask_liquid_type |
        df::tile_designation::mask_water_table;

    struct TerrainState {
#ifdef _WIN32
        HANDLE mapping = nullptr;
#endif
        shm::TerrainHeader* grid = nullptr;
        uint64_t epoch = 0;
        int32_t sizeX = 0, sizeY = 0, sizeZ = 0;
        int32_t blocksX = 0, blocksY = 0;
        uint32_t blockCount = 0;

        vector<ShadowBlock> shadow;
        uint32_t scanCursor = 0;
        uint32_t sliceBlocks = 256;   // amortized rescan: blocks per update (scan_schedule.h clamps)
        uint32_t rescanRemaining = 0; // `df3d rescan`: blocks still owed, spread over updates

        // Blocks to scan this update regardless of the slice (dig hints etc).
        vector<uint32_t> hinted;
        vector<uint8_t> hintMark;
        // Blocks whose designation details depend on something that changed
        // elsewhere (a neighbour's damp source, a door closing): the cheap
        // raw compare cannot see it, so their details are recomputed once.
        vector<uint32_t> detailHinted;
        vector<uint8_t> detailHintMark;
        // Job list identity at the last pending-work rebuild (job_list_stamp.h).
        df3d_job_list_stamp::Stamp jobStamp;
        bool jobStampValid = false;
        // Grid blocks changed since their last appearance in a ring Delta, in
        // change order. A FIFO with a head index (spill queue).
        vector<uint32_t> pendingDelta;
        size_t pendingHead = 0;
        vector<uint8_t> pendingMark;
        // Repeat window: a block that went out in a Delta is
        // re-sent in the following kEntityRepeatFrames - 1 Deltas so a client
        // polling slower than the bridge publishes does not lose it (the ring
        // is latest-only). repeatUntil[idx] = last frame to re-send it (-1 =
        // not in `repeat`); byte-identical re-sends are not changes client
        // side.
        vector<uint32_t> repeat;
        vector<int32_t> repeatUntil;
        vector<uint32_t> deltaList;  // per-frame scratch: new blocks + repeats

        // Material interning: raw identifier -> grid material index, plus
        // caches keyed by DF material ids so hot tiles never build strings.
        std::unordered_map<string, uint16_t> materialIds;
        vector<int32_t> inorganicIds;                     // inorganic index -> grid id (-1 unknown)
        std::unordered_map<int64_t, int32_t> matPairIds;  // (type<<32|index) -> grid id
        vector<uint16_t> remap;                           // grid id -> snapshot-local index
        vector<uint16_t> remapTouched;
        vector<const char*> gridStr;                      // grid material table walked lazily per snapshot
        vector<uint16_t> gridLen;
        bool warnedMaterialTableFull = false;

        // Geology / biome tables (MapCache builds them from the world data; we
        // only use its biome table, never its per-block caches).
        std::unique_ptr<MapExtras::MapCache> geo;

        size_t engravingsSeen = 0;

        // per-frame scratch
        vector<shm::TerrainTile> classifyBuf = vector<shm::TerrainTile>(256);
        std::unordered_set<uint64_t> engravedPos;
        std::unordered_set<uint64_t> closedWarningBuildings;
        df3d_track_terrain::ClearanceIndex trackClearance,trackHorizontal;
        bool engravedPosBuilt = false;
        df3d_pending_work::Index pendingWork;
        df3d_pending_work::Index pendingOperations;
        df3d_pending_work::Index pendingTracks;
        vector<df::block_square_event_mineralst*> veins;
        vector<df::block_square_event_grassst*> grasses;
        df::plant* plantAt[256] = {};

        // counters (df3d status)
        uint64_t blocksScanned = 0;
        uint64_t blocksReclassified = 0;
        uint64_t blocksChanged = 0;
        uint64_t fullPasses = 0;
        uint64_t deltasPublished = 0;
        uint64_t deltaBlocksPublished = 0;
        uint64_t repeatBlocksPublished = 0;
        uint64_t spills = 0;
        double initialScanMs = 0.0;
    };


    TerrainState terrain;
    uint64_t epochCounter = 0;
    size_t nNew = 0, nBlocks = 0;
    vector<flatbuffers::Offset<mir::MapBlock>> blockOffsets;
    vector<flatbuffers::Offset<flatbuffers::String>> materialOffsets;
    ~Impl() {
#ifdef _WIN32
        if (terrain.grid) UnmapViewOfFile(terrain.grid);
        if (terrain.mapping) CloseHandle(terrain.mapping);
#endif
    }
    void destroyTerrain(shm::RegionHeader* region) {
        df3d_ground_spatters::reset();
        TerrainState& t = terrain;
#ifdef _WIN32
        if (t.grid) {
            UnmapViewOfFile(t.grid);
            t.grid = nullptr;
        }
        if (t.mapping) {
            CloseHandle(t.mapping);
            t.mapping = nullptr;
        }
#endif
        if (region) {
            // Invalidate the old ring before publishing an absent/new grid epoch.
            // Same-world map reload reuses the region and otherwise leaves its
            // previous snapshot visible until the first new simulated frame.
            shm::atomicStoreRelease(&region->terrainEpoch, 0);
            shm::invalidateSnapshots(region);
        }
        t.epoch = 0;
        t.blockCount = 0;
        vector<ShadowBlock>().swap(t.shadow);
        t.hinted.clear();
        t.hintMark.clear();
        t.detailHinted.clear();
        t.detailHintMark.clear();
        t.jobStamp = {};
        t.jobStampValid = false;
        t.pendingDelta.clear();
        t.pendingHead = 0;
        t.pendingMark.clear();
        t.repeat.clear();
        t.repeatUntil.clear();
        t.deltaList.clear();
        t.materialIds.clear();
        t.inorganicIds.clear();
        t.matPairIds.clear();
        t.remap.clear();
        t.remapTouched.clear();
        t.gridStr.clear();
        t.gridLen.clear();
        t.geo.reset();
        t.engravedPos.clear();
        t.pendingWork = {};
        t.pendingOperations = {};
        t.pendingTracks = {};
        t.engravingsSeen = 0;
        t.scanCursor = 0;
        t.rescanRemaining = 0;
    }

    // ---- terrain: material interning ----

    uint16_t internMaterial(const string& token) {
        TerrainState& t = terrain;
        if (!t.grid)
            return shm::kTerrainNoMaterial;  // no grid (creation failed): no material table
        auto it = t.materialIds.find(token);
        if (it != t.materialIds.end())
            return it->second;
        const uint16_t id = shm::terrainAppendMaterial(t.grid, token.data(), token.size());
        if (id != shm::kTerrainNoMaterial) {
            t.materialIds.emplace(token, id);
            if (t.remap.size() <= id) {
                t.remap.resize(id + 1, shm::kTerrainNoMaterial);
            }
        }
        return id;
    }

    uint16_t inorganicMaterial(int32_t idx) {
        TerrainState& t = terrain;
        if (idx < 0)
            return shm::kTerrainNoMaterial;
        if (static_cast<size_t>(idx) >= t.inorganicIds.size())
            t.inorganicIds.resize(static_cast<size_t>(idx) + 1, -1);
        if (t.inorganicIds[idx] >= 0)
            return static_cast<uint16_t>(t.inorganicIds[idx]);
        const df::inorganic_raw* raw = df::inorganic_raw::find(idx);
        if (!raw)
            return shm::kTerrainNoMaterial;
        const uint16_t id = internMaterial("INORGANIC:" + raw->id);
        if (id != shm::kTerrainNoMaterial)
            t.inorganicIds[idx] = id;
        return id;
    }

    // Any DF (mat_type, mat_index) pair via DFHack's MaterialInfo token:
    // "INORGANIC:GRANITE", "PLANT:OAK:WOOD", "CREATURE:DWARF:BONE", builtin
    // ids such as "WATER". Cached per pair.
    uint16_t pairMaterial(int16_t type, int32_t index) {
        TerrainState& t = terrain;
        if (type < 0)
            return shm::kTerrainNoMaterial;
        const int64_t key = (static_cast<int64_t>(type) << 32) | static_cast<uint32_t>(index);
        auto it = t.matPairIds.find(key);
        if (it != t.matPairIds.end())
            return static_cast<uint16_t>(it->second);
        MaterialInfo mi(type, index);
        if (!mi.isValid())
            return shm::kTerrainNoMaterial;
        const uint16_t id = internMaterial(mi.getToken());
        if (id != shm::kTerrainNoMaterial)
            t.matPairIds.emplace(key, id);
        return id;
    }

    // Soil vs stone for a layer inorganic.
    mir::MaterialKind inorganicKind(int32_t idx, mir::MaterialKind fallback) {
        const df::inorganic_raw* raw = df::inorganic_raw::find(idx);
        if (!raw)
            return fallback;
        if (raw->flags.is_set(df::inorganic_flags::SOIL_ANY))
            return mir::MaterialKind::Soil;
        if (raw->material.flags.is_set(df::material_flags::IS_GEM))
            return mir::MaterialKind::Gem;
        return fallback;
    }

    // ---- terrain: classification ----

    mir::TileShape mapShape(df::tiletype_shape s) {
        using S = df::tiletype_shape;
        using mir::TileShape;
        switch (s) {
        case S::EMPTY: return TileShape::Empty;
        case S::FLOOR: return TileShape::Floor;
        case S::BOULDER: return TileShape::Boulder;
        case S::PEBBLES: return TileShape::Pebbles;
        case S::WALL: return TileShape::Wall;
        case S::FORTIFICATION: return TileShape::Fortification;
        case S::STAIR_UP: return TileShape::StairUp;
        case S::STAIR_DOWN: return TileShape::StairDown;
        case S::STAIR_UPDOWN: return TileShape::StairUpDown;
        case S::RAMP: return TileShape::Ramp;
        case S::RAMP_TOP: return TileShape::RampTop;
        case S::BROOK_BED: return TileShape::Wall;   // the bed under a brook (basic shape Wall)
        case S::BROOK_TOP: return TileShape::Floor;  // walkable brook surface
        case S::BRANCH: return TileShape::TreeBranch;
        case S::TRUNK_BRANCH: return TileShape::TreeTrunk;
        case S::TWIG: return TileShape::TreeBranch;
        case S::SAPLING: return TileShape::Sapling;
        case S::SHRUB: return TileShape::Shrub;
        case S::ENDLESS_PIT: return TileShape::Empty;
        default: return TileShape::Unknown;
        }
    }

    uint64_t posKey(int32_t x, int32_t y, int32_t z) {
        return (static_cast<uint64_t>(static_cast<uint32_t>(z)) << 42) |
               (static_cast<uint64_t>(static_cast<uint32_t>(y) & 0x1FFFFF) << 21) |
               (static_cast<uint32_t>(x) & 0x1FFFFF);
    }

    // Engraved tiles are not distinguishable from tiletype alone; DF keeps
    // engravings in world->engravings. Built lazily once per update, only
    // when a block with smoothed tiles is being classified.
    const std::unordered_set<uint64_t>& engravedPositions() {
        TerrainState& t = terrain;
        if (!t.engravedPosBuilt) {
            t.engravedPos.clear();
            for (const df::engraving* e : df::engraving::get_vector())
                t.engravedPos.insert(posKey(e->pos.x, e->pos.y, e->pos.z));
            t.engravedPosBuilt = true;
        }
        return t.engravedPos;
    }

    // Fills plantAt[] for one block from its map-block column (the same walk
    // as MapExtras::BlockInfo::prepare, without the per-block cache objects).
    void gatherPlants(const df::map_block* blk) {
        TerrainState& t = terrain;
        std::memset(t.plantAt, 0, sizeof(t.plantAt));
        const int32_t bx0 = blk->map_pos.x, by0 = blk->map_pos.y, bz = blk->map_pos.z;
        if (!world->map.column_index)
            return;
        df::map_block_column* col = world->map.column_index[(bx0 / 48) * 3][(by0 / 48) * 3];
        if (!col)
            return;
        for (df::plant* pp : col->plants) {
            if (!pp->tree_info) {
                if (pp->pos.z == bz && pp->pos.x >= bx0 && pp->pos.x < bx0 + 16 &&
                    pp->pos.y >= by0 && pp->pos.y < by0 + 16)
                    t.plantAt[(pp->pos.y - by0) * 16 + (pp->pos.x - bx0)] = pp;
                continue;
            }
            const df::plant_tree_info& info = *pp->tree_info;
            if (!(pp->pos.z - info.roots_depth <= bz && pp->pos.z + info.body_height > bz))
                continue;
            const int32_t zDiff = bz - pp->pos.z;
            const int32_t originX = pp->pos.x - info.dim_x / 2;
            const int32_t originY = pp->pos.y - info.dim_y / 2;
            // Clip the tree's slice to this block.
            const int32_t xs = std::max(0, bx0 - originX), xe = std::min<int32_t>(info.dim_x, bx0 + 16 - originX);
            const int32_t ys = std::max(0, by0 - originY), ye = std::min<int32_t>(info.dim_y, by0 + 16 - originY);
            for (int32_t yy = ys; yy < ye; ++yy) {
                for (int32_t xx = xs; xx < xe; ++xx) {
                    bool has = false;
                    if (zDiff >= 0) {
                        const df::plant_tree_tile tile = info.body[zDiff][xx + yy * info.dim_x];
                        has = tile.whole && !tile.bits.blocked;
                    } else {
                        const df::plant_root_tile tile = info.roots[-1 - zDiff][xx + yy * info.dim_x];
                        has = tile.whole && !tile.bits.blocked;
                    }
                    if (has)
                        t.plantAt[(originY + yy - by0) * 16 + (originX + xx - bx0)] = pp;
                }
            }
        }
    }

    uint16_t plantBasicMaterial(const df::plant* p) {
        if (!p)
            return shm::kTerrainNoMaterial;
        const df::plant_raw* raw = df::plant_raw::find(p->material);
        if (!raw)
            return shm::kTerrainNoMaterial;
        return pairMaterial(raw->material_defs.type[df::plant_material_def::basic_mat],
                            raw->material_defs.idx[df::plant_material_def::basic_mat]);
    }

    // Classifies one map block into `out` (256 tiles, row-major, local y outer).
    // A null block (never allocated by DF) is all Empty.
    // Priority is a map-block event, marker-only work an occupancy bit. Neither is
    // native UI state. The scan compares compact metadata without per-tile job-map
    // lookups; classification publishes it only for actual pending operations.
    // Native warning walkability rejects closed doors, wall grates and vertical
    // bars on Dynamic-occupied tiles. Index the three source vectors once per
    // bridge terrain scan, never search all buildings for each map tile.
    // A tile whose dynamic barrier (closed door / grate / bars, forbidden
    // hatch) entered or left one of the three indexes changes its details
    // without any raw block change: schedule a details refresh of its block.
    template<class Decode>
    void hintIndexDifference(const std::unordered_set<uint64_t>& before, const std::unordered_set<uint64_t>& after, Decode decode) {
        if (terrain.shadow.empty()) return;
        for (const auto key : after) if (!before.count(key)) { int x,y,z; decode(key,x,y,z); hintDetails(x>>4,y>>4,z); }
        for (const auto key : before) if (!after.count(key)) { int x,y,z; decode(key,x,y,z); hintDetails(x>>4,y>>4,z); }
    }
    void refreshWarningBuildings() {
        auto trackDecode=[](uint64_t key,int& x,int& y,int& z) { x=int(int16_t(key&0xFFFF)); y=int(int16_t((key>>16)&0xFFFF)); z=int(int16_t((key>>32)&0xFFFF)); };
        auto posDecode=[](uint64_t key,int& x,int& y,int& z) { x=int(key&0x1FFFFF); y=int((key>>21)&0x1FFFFF); z=int(key>>42); };
        auto clearance=df3d_track_terrain::buildClearanceIndex();
        hintIndexDifference(terrain.trackClearance,clearance,trackDecode);
        terrain.trackClearance=std::move(clearance);
        auto horizontal=df3d_track_terrain::buildHorizontalIndex();
        hintIndexDifference(terrain.trackHorizontal,horizontal,trackDecode);
        terrain.trackHorizontal=std::move(horizontal);
        std::unordered_set<uint64_t> closed;
        auto add=[&](const df::building* b) { closed.insert(posKey(b->centerx,b->centery,b->z)); };
        for(auto* b:world->buildings.other[df::buildings_other_id::DOOR])
            if(auto* door=virtual_cast<df::building_doorst>(b); door && door->door_flags.bits.closed) add(door);
        for(auto* b:world->buildings.other[df::buildings_other_id::GRATE_WALL])
            if(auto* grate=virtual_cast<df::building_grate_wallst>(b); grate && grate->gate_flags.bits.closed) add(grate);
        for(auto* b:world->buildings.other[df::buildings_other_id::BARS_VERTICAL])
            if(auto* bars=virtual_cast<df::building_bars_verticalst>(b); bars && bars->gate_flags.bits.closed) add(bars);
        hintIndexDifference(terrain.closedWarningBuildings,closed,posDecode);
        terrain.closedWarningBuildings=std::move(closed);
    }

    // Cheap per-tile inputs of designationDetails() that live outside the
    // tiletype / designation arrays: occupancy bits (marker, auto-dig, track
    // carving, building occupancy), traffic, the warm-stone threshold of the
    // temperature and the block's priority event. Plus the damp-source
    // predicate the neighbouring blocks' warnings read (dampBits).
    void blockSignature(const df::map_block* block, uint16_t* sig, uint32_t* damp) {
        std::fill(sig,sig+256,uint16_t(0));
        std::fill(damp,damp+8,0u);
        if (!block) return;
        const df::block_square_event_designation_priorityst* priority = nullptr;
        for (auto* event : block->block_events)
            if ((priority=virtual_cast<df::block_square_event_designation_priorityst>(event))) break;
        for (int y=0;y<16;++y) for (int x=0;x<16;++x) {
            const auto occ=block->occupancy[x][y].bits;
            const auto des=block->designation[x][y].bits;
            const int raw=priority ? priority->priority[x][y]/1000 : 4;
            const uint16_t prio=uint16_t(raw>=1 && raw<=7 ? raw : 4);
            sig[y*16+x]=uint16_t((occ.dig_marked?1:0) | (occ.dig_auto?2:0) |
                (occ.carve_track_north?4:0) | (occ.carve_track_south?8:0) | (occ.carve_track_east?16:0) | (occ.carve_track_west?32:0) |
                (uint16_t(occ.building)<<6) | (uint16_t(des.traffic)<<9) |
                (block->temperature_1[x][y]>=10075 ? 1u<<11 : 0u) | (prio<<12));
            if (miningDampSource(block,x,y)) damp[(y*16+x)>>5] |= 1u<<((y*16+x)&31);
        }
    }

    // Native 53.16 helper 0x149f0b0: water or aquifer-bearing natural walls in
    // the 3x3 same-level neighborhood, plus the tile directly above. Smooth walls
    // are intentionally excluded from the aquifer branch; water itself is enough.
    bool miningDampSource(const df::map_block* block, int x, int y) {
        if(!block) return false;
        const auto d=block->designation[x][y].bits;
        if(d.flow_size && d.liquid_type==df::tile_liquid::Water) return true;
        if(!d.water_table) return false;
        switch(block->tiletype[x][y]) {
        case df::tiletype::StoneWall: case df::tiletype::SoilWall:
        case df::tiletype::LavaWall: case df::tiletype::FeatureWall: case df::tiletype::MineralWall:
        case df::tiletype::StoneWallWorn1: case df::tiletype::StoneWallWorn2: case df::tiletype::StoneWallWorn3:
        case df::tiletype::LavaWallWorn1: case df::tiletype::LavaWallWorn2: case df::tiletype::LavaWallWorn3:
        case df::tiletype::FeatureWallWorn1: case df::tiletype::FeatureWallWorn2: case df::tiletype::FeatureWallWorn3:
        case df::tiletype::MineralWallWorn1: case df::tiletype::MineralWallWorn2: case df::tiletype::MineralWallWorn3:
            return true;
        default: return false;
        }
    }

    void designationDetails(const df::map_block* block, uint32_t* out) {
        std::fill(out,out+256,uint16_t(0));
        if (!block) return;
        // Bounded block lookups once per scan, never per neighbor/tile. Recompute
        // warning bits during shadow scans so neighboring water/aquifer changes
        // cannot leave an unchanged target block's warning stale.
        const df::map_block* neighborhood[3][3] = {};
        const int bx=block->map_pos.x/16, by=block->map_pos.y/16, z=block->map_pos.z;
        for(int dx=-1;dx<=1;++dx) for(int dy=-1;dy<=1;++dy)
            neighborhood[dx+1][dy+1]=Maps::getBlock(bx+dx,by+dy,z);
        const auto* above=Maps::getBlock(bx,by,z+1);
        bool damp[18][18] = {};
        for(int x=-1;x<=16;++x) for(int y=-1;y<=16;++y)
            damp[x+1][y+1]=miningDampSource(neighborhood[x<0?0:x>=16?2:1][y<0?0:y>=16?2:1],x&15,y&15);
        const df::block_square_event_designation_priorityst* priority = nullptr;
        for (auto* event : block->block_events)
            if ((priority=virtual_cast<df::block_square_event_designation_priorityst>(event))) break;
        for (int y=0;y<16;++y) for (int x=0;x<16;++x) {
            const int raw=priority ? priority->priority[x][y]/1000 : 4;
            const uint8_t value=raw>=1 && raw<=7 ? uint8_t(raw) : 4;
            const auto occ=block->occupancy[x][y].bits;
            const uint8_t track=(occ.carve_track_north?1:0)|(occ.carve_track_south?2:0)|
                (occ.carve_track_east?4:0)|(occ.carve_track_west?8:0)|
                terrain.pendingTracks.at({block->map_pos.x+x,block->map_pos.y+y,z});
            uint8_t warning=0;
            const auto des=block->designation[x][y].bits;
            // Hide undiscovered hazard locations unless the player has already
            // designated this tile. The presentation additionally gates by tool.
            const auto shape=tileShape(block->tiletype[x][y]);
            // Native 0x1436f30 walkability: walls (including tree columns and
            // pillars), trunk branches and brook beds are non-walkable. The
            // caller's 0x14c9be0 fortification exclusion also admits those here.
            const bool solidTarget=shape==df::tiletype_shape::WALL ||
                shape==df::tiletype_shape::FORTIFICATION ||
                shape==df::tiletype_shape::TRUNK_BRANCH || shape==df::tiletype_shape::BROOK_BED;
            const bool closedDynamic=occ.building==df::tile_building_occ::Dynamic &&
                terrain.closedWarningBuildings.count(posKey(block->map_pos.x+x,block->map_pos.y+y,z));
            const bool blocked=df3d_map_indicators::buildingBlocksMiningWarning(uint8_t(occ.building),closedDynamic);
            if((solidTarget || blocked) && (!des.hidden || des.dig!=df::tile_dig_designation::No)) {
                warning=df3d_map_indicators::miningWarning(block->temperature_1[x][y],
                    [&](int dx,int dy,int dz) { return dz ? miningDampSource(above,x,y) : damp[x+dx+1][y+dy+1]; });
            }
            out[y*16+x]=shm::terrainDesignation(0,value,occ.dig_marked) |
                (uint16_t(track)<<8) | (uint16_t(des.traffic)<<12) | (uint16_t(warning)<<14) | (uint32_t(occ.dig_auto)<<16) |
                (uint32_t(df3d_track_terrain::clearanceBlocked(block,x,y,terrain.trackClearance))<<17) |
                (uint32_t(df3d_track_terrain::horizontalBlocked(block,x,y,terrain.trackHorizontal))<<18) |
                (uint32_t(tileShape(block->tiletype[x][y])==df::tiletype_shape::WALL || tileShape(block->tiletype[x][y])==df::tiletype_shape::FORTIFICATION)<<19) |
                (uint32_t(block->tiletype[x][y]==df::tiletype::OpenSpace || block->tiletype[x][y]==df::tiletype::Chasm || block->tiletype[x][y]==df::tiletype::EeriePit)<<20);
        }
    }

    void classifyBlock(const df::map_block* blk, shm::TerrainTile* out, const uint32_t* details) {
        using mir::MaterialKind;
        using mir::TileShape;
        TerrainState& t = terrain;

        for (int i = 0; i < 256; ++i) {
            out[i] = shm::TerrainTile{};
            out[i].material = shm::kTerrainNoMaterial;
        }
        if (!blk)
            return;

        // Per-block preparation, only for what this block actually needs.
        bool needVeins = false, needGrass = false, needPlants = false, needFeature = false,
             needEngraving = false;
        for (int lx = 0; lx < 16; ++lx) {
            for (int ly = 0; ly < 16; ++ly) {
                const df::tiletype tt = blk->tiletype[lx][ly];
                switch (tileMaterial(tt)) {
                case df::tiletype_material::MINERAL: needVeins = true; break;
                case df::tiletype_material::GRASS_LIGHT:
                case df::tiletype_material::GRASS_DARK:
                case df::tiletype_material::GRASS_DRY:
                case df::tiletype_material::GRASS_DEAD: needGrass = true; break;
                case df::tiletype_material::TREE:
                case df::tiletype_material::ROOT:
                case df::tiletype_material::MUSHROOM:
                case df::tiletype_material::PLANT: needPlants = true; break;
                case df::tiletype_material::FEATURE: needFeature = true; break;
                default: break;
                }
                if (tileSpecial(tt) == df::tiletype_special::SMOOTH)
                    needEngraving = true;
            }
        }
        if (needVeins || needGrass) {
            t.veins.clear();
            t.grasses.clear();
            Maps::SortBlockEvents(const_cast<df::map_block*>(blk), needVeins ? &t.veins : nullptr,
                                  nullptr, nullptr, needGrass ? &t.grasses : nullptr);
        }
        if (needPlants)
            gatherPlants(blk);
        df::feature_init* localFeature = nullptr;
        df::feature_init* globalFeature = nullptr;
        if (needFeature) {
            localFeature = Maps::getLocalInitFeature(blk->region_pos, blk->local_feature);
            globalFeature = Maps::getGlobalInitFeature(blk->global_feature);
        }
        const std::unordered_set<uint64_t>* engraved = needEngraving ? &engravedPositions() : nullptr;

        for (int ly = 0; ly < 16; ++ly) {
            for (int lx = 0; lx < 16; ++lx) {
                const df::tiletype tt = blk->tiletype[lx][ly];
                const df::tile_designation des = blk->designation[lx][ly];
                shm::TerrainTile& o = out[ly * 16 + lx];

                const df::tiletype_shape shape = tileShape(tt);
                const df::tiletype_material tm = tileMaterial(tt);
                // DF's tree trunks (and cap/root columns) are WALL-shaped tiles of
                // TREE/MUSHROOM/ROOT material; the schema's TreeTrunk is that
                // shape. Constructed wood walls keep CONSTRUCTION material and
                // stay Wall.
                const bool woodyColumn = tm == df::tiletype_material::TREE ||
                                         tm == df::tiletype_material::MUSHROOM ||
                                         tm == df::tiletype_material::ROOT;
                o.shape = static_cast<uint8_t>(shape == df::tiletype_shape::WALL && woodyColumn
                                                   ? mir::TileShape::TreeTrunk
                                                   : mapShape(shape));

                // Material.
                MaterialKind kind = MaterialKind::None;
                uint16_t mat = shm::kTerrainNoMaterial;
                const MapExtras::BiomeInfo* biome = nullptr;
                auto biomeAt = [&]() -> const MapExtras::BiomeInfo& {
                    if (!biome) {
                        int idx = des.bits.biome;
                        idx = idx < 9 ? blk->region_offset[idx] : -1;
                        biome = &t.geo->getBiomeByIndex(idx < 0 ? 0xFFFFFFFFu : static_cast<unsigned>(idx));
                    }
                    return *biome;
                };
                auto layerMaterial = [&](bool wantSoil) -> int32_t {
                    const MapExtras::BiomeInfo& b = biomeAt();
                    int32_t idx = b.layer_stone[des.bits.geolayer_index];
                    const bool isSoil = idx >= 0 && isSoilInorganic(idx);
                    if (wantSoil && !isSoil && b.default_soil >= 0) idx = b.default_soil;
                    if (!wantSoil && isSoil && b.default_stone >= 0) idx = b.default_stone;
                    return idx;
                };
                switch (tm) {
                case df::tiletype_material::AIR:
                case df::tiletype_material::NONE:
                    break;
                case df::tiletype_material::SOIL: {
                    const int32_t idx = layerMaterial(true);
                    kind = inorganicKind(idx, MaterialKind::Soil);
                    mat = inorganicMaterial(idx);
                    break;
                }
                case df::tiletype_material::STONE: {
                    const int32_t idx = layerMaterial(false);
                    kind = inorganicKind(idx, MaterialKind::Stone);
                    mat = inorganicMaterial(idx);
                    break;
                }
                case df::tiletype_material::LAVA_STONE: {
                    const int32_t idx = biomeAt().lava_stone;
                    kind = MaterialKind::Stone;
                    mat = inorganicMaterial(idx);
                    break;
                }
                case df::tiletype_material::MINERAL: {
                    int32_t idx = -1;
                    for (df::block_square_event_mineralst* v : t.veins)
                        if (v->getassignment(lx, ly)) idx = v->inorganic_mat;  // later events win
                    if (idx < 0) {
                        idx = layerMaterial(false);
                        kind = inorganicKind(idx, MaterialKind::Stone);
                    } else {
                        kind = inorganicKind(idx, MaterialKind::Mineral);
                    }
                    mat = inorganicMaterial(idx);
                    break;
                }
                case df::tiletype_material::FEATURE: {
                    int16_t mt = -1;
                    int32_t mi = -1;
                    if (des.bits.feature_local && localFeature) localFeature->getMaterial(&mt, &mi);
                    else if (des.bits.feature_global && globalFeature) globalFeature->getMaterial(&mt, &mi);
                    kind = mt == 0 ? inorganicKind(mi, MaterialKind::Stone) : MaterialKind::Stone;
                    mat = mt == 0 ? inorganicMaterial(mi) : pairMaterial(mt, mi);
                    break;
                }
                case df::tiletype_material::FROZEN_LIQUID:
                    kind = MaterialKind::Ice;
                    mat = pairMaterial(df::builtin_mats::WATER, -1);
                    break;
                case df::tiletype_material::CONSTRUCTION: {
                    kind = MaterialKind::Constructed;
                    const df::coord pos(blk->map_pos.x + lx, blk->map_pos.y + ly, blk->map_pos.z);
                    if (const df::construction* c = df::construction::find(pos))
                        mat = pairMaterial(c->mat_type, c->mat_index);
                    break;
                }
                case df::tiletype_material::GRASS_LIGHT:
                case df::tiletype_material::GRASS_DARK:
                case df::tiletype_material::GRASS_DRY:
                case df::tiletype_material::GRASS_DEAD: {
                    kind = MaterialKind::Grass;
                    int32_t plantIdx = -1;
                    int amount = -1;
                    for (const df::block_square_event_grassst* g : t.grasses) {
                        if (g->amount[lx][ly] > amount) {
                            amount = g->amount[lx][ly];
                            plantIdx = g->plant_index;
                        }
                    }
                    if (const df::plant_raw* raw = df::plant_raw::find(plantIdx))
                        mat = pairMaterial(raw->material_defs.type[df::plant_material_def::basic_mat],
                                           raw->material_defs.idx[df::plant_material_def::basic_mat]);
                    break;
                }
                case df::tiletype_material::TREE:
                case df::tiletype_material::ROOT:
                case df::tiletype_material::MUSHROOM:
                    kind = MaterialKind::Wood;
                    mat = plantBasicMaterial(t.plantAt[ly * 16 + lx]);
                    break;
                case df::tiletype_material::PLANT:
                    kind = MaterialKind::Plant;
                    mat = plantBasicMaterial(t.plantAt[ly * 16 + lx]);
                    break;
                case df::tiletype_material::MAGMA:  // semi-molten rock: the tile's own substance
                    kind = MaterialKind::Magma;
                    break;
                case df::tiletype_material::POOL:
                case df::tiletype_material::BROOK:
                case df::tiletype_material::RIVER: {
                    const int32_t idx = layerMaterial(false);
                    kind = inorganicKind(idx, MaterialKind::Stone);
                    mat = inorganicMaterial(idx);
                    break;
                }
                case df::tiletype_material::ASHES:
                case df::tiletype_material::FIRE:
                case df::tiletype_material::CAMPFIRE:
                    kind = MaterialKind::Unknown;
                    mat = pairMaterial(df::builtin_mats::ASH, -1);
                    break;
                case df::tiletype_material::DRIFTWOOD:
                    kind = MaterialKind::Wood;
                    break;
                default:  // HFS, UNDERWORLD_GATE, ...
                    kind = MaterialKind::Unknown;
                    break;
                }
                // A shape that carries no substance never reports a material.
                if (shape == df::tiletype_shape::EMPTY || shape == df::tiletype_shape::RAMP_TOP ||
                    shape == df::tiletype_shape::ENDLESS_PIT) {
                    kind = MaterialKind::None;
                    mat = shm::kTerrainNoMaterial;
                }
                o.material_kind = static_cast<uint8_t>(kind);
                o.material = mat;

                // Liquids.
                const uint8_t flow = static_cast<uint8_t>(des.bits.flow_size);
                o.liquid_level = flow > mir::kMaxLiquidLevel ? mir::kMaxLiquidLevel : flow;
                o.liquid_kind = static_cast<uint8_t>(
                    flow == 0 ? mir::LiquidKind::None
                              : (des.bits.liquid_type == df::tile_liquid::Magma ? mir::LiquidKind::Magma
                                                                                : mir::LiquidKind::Water));

                // Flags.
                uint8_t flags = 0;
                if (des.bits.hidden) flags |= static_cast<uint8_t>(mir::TileFlags::Hidden);
                if (des.bits.dig != df::tile_dig_designation::No)
                    flags |= static_cast<uint8_t>(mir::TileFlags::DigDesignated);
                const auto pending = t.pendingWork.at({blk->map_pos.x+lx,blk->map_pos.y+ly,blk->map_pos.z});
                auto operation=static_cast<mir::DesignationKind>(t.pendingOperations.at({blk->map_pos.x+lx,blk->map_pos.y+ly,blk->map_pos.z}));
                if (operation==mir::DesignationKind::None) {
                    if(des.bits.smooth==2) operation=mir::DesignationKind::Engrave;
                    else if(des.bits.smooth==1) operation=mir::DesignationKind::Smooth;
                    else switch(des.bits.dig) {
                    case df::tile_dig_designation::Default:
                        if(needPlants && t.plantAt[ly*16+lx])
                            operation=t.plantAt[ly*16+lx]->tree_info ? mir::DesignationKind::Chop : mir::DesignationKind::Gather;
                        else operation=mir::DesignationKind::Dig;
                        break;
                    case df::tile_dig_designation::Channel: operation=mir::DesignationKind::Channel; break;
                    case df::tile_dig_designation::Ramp: operation=mir::DesignationKind::Ramp; break;
                    case df::tile_dig_designation::UpStair: operation=mir::DesignationKind::StairUp; break;
                    case df::tile_dig_designation::DownStair: operation=mir::DesignationKind::StairDown; break;
                    case df::tile_dig_designation::UpDownStair: operation=mir::DesignationKind::StairUpDown; break;
                    default: break;
                    }
                }
                const auto detail=details[ly*16+lx];
                o.track_blockers=uint8_t((detail>>17)&15);
                if(detail & (1u<<16)) flags |= static_cast<uint8_t>(mir::TileFlags::DigAuto);
                o.track=(detail>>8)&15; o.traffic=(detail>>12)&3; o.warnings=(detail>>14)&3;
                o.designation=static_cast<uint8_t>(operation) | ((operation!=mir::DesignationKind::None || o.track) ? uint8_t(detail) : 0);
                using PendingKind = df3d_pending_work::Kind;
                if (pending & (uint8_t(PendingKind::Dig)|uint8_t(PendingKind::Chop)|uint8_t(PendingKind::Gather)))
                    flags |= static_cast<uint8_t>(mir::TileFlags::DigDesignated);
                if (pending & uint8_t(PendingKind::Smooth)) flags |= static_cast<uint8_t>(mir::TileFlags::SmoothDesignated);
                if (pending & uint8_t(PendingKind::Engrave)) flags |= static_cast<uint8_t>(mir::TileFlags::EngraveDesignated);
                if(operation==mir::DesignationKind::RemoveConstruction || operation==mir::DesignationKind::Fortify)
                    flags |= static_cast<uint8_t>(mir::TileFlags::DigDesignated);
                // Pending smooth / engrave designations (v6): 1 = smooth, 2 =
                // engrave (DF DETAIL bits); the finished state is Smooth below.
                if (des.bits.smooth == 1) flags |= static_cast<uint8_t>(mir::TileFlags::SmoothDesignated);
                else if (des.bits.smooth == 2) flags |= static_cast<uint8_t>(mir::TileFlags::EngraveDesignated);
                const df::tiletype_special special = tileSpecial(tt);
                if (special == df::tiletype_special::SMOOTH ||
                    special == df::tiletype_special::SMOOTH_DEAD ||
                    special == df::tiletype_special::TRACK) {
                    flags |= static_cast<uint8_t>(mir::TileFlags::Smooth);
                    if (engraved && engraved->count(posKey(blk->map_pos.x + lx, blk->map_pos.y + ly,
                                                           blk->map_pos.z)))
                        flags |= static_cast<uint8_t>(mir::TileFlags::Engraved);
                }
                if (des.bits.outside) flags |= static_cast<uint8_t>(mir::TileFlags::Outside);
                o.flags = flags;
            }
        }
    }

    // ---- terrain: scanning ----

    void blockCoords(uint32_t idx, int32_t& bx, int32_t& by, int32_t& bz) {
        const TerrainState& t = terrain;
        bx = static_cast<int32_t>(idx % t.blocksX);
        const uint32_t rest = idx / t.blocksX;
        by = static_cast<int32_t>(rest % t.blocksY);
        bz = static_cast<int32_t>(rest / t.blocksY);
    }

    void hintBlock(int32_t bx, int32_t by, int32_t bz) {
        TerrainState& t = terrain;
        if (bx < 0 || by < 0 || bz < 0 || bx >= t.blocksX || by >= t.blocksY || bz >= t.sizeZ)
            return;
        const uint32_t idx = shm::terrainBlockIndex(t.grid, bx, by, bz);
        if (t.hintMark[idx]) return;
        t.hintMark[idx] = 1;
        t.hinted.push_back(idx);
    }
    void hintDetails(int32_t bx, int32_t by, int32_t bz) {
        TerrainState& t = terrain;
        if (bx < 0 || by < 0 || bz < 0 || bx >= t.blocksX || by >= t.blocksY || bz >= t.sizeZ)
            return;
        const uint32_t idx = shm::terrainBlockIndex(t.grid, bx, by, bz);
        if (t.detailHintMark[idx]) return;
        t.detailHintMark[idx] = 1;
        t.detailHinted.push_back(idx);
    }
    // Blocks whose mining warnings read this block's damp sources: the 3x3
    // same-level neighbourhood and the block below (it reads its `above`).
    void hintDampDependents(int32_t bx, int32_t by, int32_t bz) {
        for (int dy=-1;dy<=1;++dy) for (int dx=-1;dx<=1;++dx) hintDetails(bx+dx,by+dy,bz);
        hintDetails(bx,by,bz-1);
    }

    // Hints every block touching the 3x3x3 tile neighbourhood of `pos` (digging
    // reveals neighbours, which may live in an adjacent block).
    void hintAround(df::coord pos) {
        for (int dz = -1; dz <= 1; ++dz)
            for (int dy = -1; dy <= 1; ++dy)
                for (int dx = -1; dx <= 1; ++dx)
                    hintBlock((pos.x + dx) >> 4, (pos.y + dy) >> 4, pos.z + dz);
    }

    // Scans one block: cheap raw compare against the shadow (tiletype,
    // designation mask, signature), then the expensive designation details
    // only when the raw state changed or `detailsRefresh` says a dependency
    // did; reclassify on change, write to the grid on classified change.
    // `batchOpen` tracks the grid seqlock across the calling loop. Returns
    // true if the grid changed.
    bool scanBlock(uint32_t idx, bool force, bool& batchOpen, bool queueDelta, bool detailsRefresh = false) {
        TerrainState& t = terrain;
        ++t.blocksScanned;
        int32_t bx, by, bz;
        blockCoords(idx, bx, by, bz);
        const df::map_block* blk = Maps::getBlock(bx, by, bz);
        df3d_ground_spatters::scan(idx,bx,by,bz,blk,
            world ? uint64_t(std::max(0,world->frame_counter)) : 0,[this](int16_t type, int32_t index) { return pairMaterial(type,index); });
        ShadowBlock& sh = t.shadow[idx];
        const uint8_t allocated = blk ? 1 : 0;
        uint16_t signature[256];
        uint32_t dampBits[8];
        blockSignature(blk, signature, dampBits);

        bool rawSame = false;
        if (!force && sh.scanned && allocated == sh.allocated) {
            if (!blk) return false;
            static_assert(sizeof(blk->tiletype) == sizeof(sh.tiletype), "tiletype array");
            if (std::memcmp(&blk->tiletype, sh.tiletype, sizeof(sh.tiletype)) == 0 &&
                std::memcmp(signature, sh.signature, sizeof(signature)) == 0) {
                rawSame = true;
                const uint32_t* d = reinterpret_cast<const uint32_t*>(&blk->designation);
                for (int i = 0; i < 256; ++i) {
                    if ((d[i] & kDsgnMask) != sh.dsgn[i]) { rawSame = false; break; }
                }
            }
            if (rawSame && !detailsRefresh) return false;
        }

        // Raw state differs, a dependency changed, or first look: the
        // expensive pass (neighbourhood lookups, per-tile indexes).
        uint32_t details[256];
        designationDetails(blk,details);
        if (rawSame && std::memcmp(details,sh.designationDetails,sizeof(details))==0) return false;

        const bool dampChanged = !sh.scanned || std::memcmp(dampBits, sh.dampBits, sizeof(dampBits)) != 0;
        sh.scanned = 1;
        sh.allocated = allocated;
        std::memcpy(sh.designationDetails,details,sizeof(details));
        std::memcpy(sh.signature,signature,sizeof(signature));
        std::memcpy(sh.dampBits,dampBits,sizeof(dampBits));
        if (blk) {
            std::memcpy(sh.tiletype, &blk->tiletype, sizeof(sh.tiletype));
            const uint32_t* d = reinterpret_cast<const uint32_t*>(&blk->designation);
            for (int i = 0; i < 256; ++i) sh.dsgn[i] = d[i] & kDsgnMask;
        } else {
            std::memset(sh.tiletype, 0, sizeof(sh.tiletype));
            std::memset(sh.dsgn, 0, sizeof(sh.dsgn));
        }
        // The initial pass (queueDelta false) visits every block anyway.
        if (dampChanged && queueDelta) hintDampDependents(bx, by, bz);
        ++t.blocksReclassified;
        shm::TerrainTile* fresh = t.classifyBuf.data();
        classifyBlock(blk, fresh, details);
        if (std::memcmp(fresh, shm::terrainBlockTiles(t.grid, idx), 256 * sizeof(shm::TerrainTile)) == 0)
            return false;

        if (!batchOpen) {
            shm::terrainBeginWrite(t.grid);
            batchOpen = true;
        }
        shm::terrainWriteBlock(t.grid, idx, fresh);
        ++t.blocksChanged;
        if (queueDelta && !t.pendingMark[idx]) {
            t.pendingMark[idx] = 1;
            t.pendingDelta.push_back(idx);
        }
        return true;
    }

    // One update's worth of terrain maintenance: hinted blocks, then the
    // rotating slice. Runs paused or not so the grid stays current for
    // late-attaching clients even while the sim is stopped.
    void refreshPendingWork() {
        TerrainState& t=terrain;
        // One linear walk stamps the list; the three maps and their set
        // differences are rebuilt only when it changed (a paused game with a
        // static job list costs the walk alone).
        df3d_job_list_stamp::Stamp stamp;
        for(auto* link=world->jobs.list.next;link;link=link->next) {
            const auto* job=link->item;
            if(job) stamp.add(job->id,int32_t(job->job_type),job->pos.x,job->pos.y,job->pos.z,
                job->job_type==df::job_type::CarveTrack ? job->specflag.carve_track_flags.whole : 0u);
        }
        if(t.jobStampValid && stamp==t.jobStamp) return;
        t.jobStamp=stamp;
        t.jobStampValid=true;
        df3d_pending_work::Tiles next;
        df3d_pending_work::Tiles nextOperations;
        df3d_pending_work::Tiles nextTracks;
        for(auto* link=world->jobs.list.next;link;link=link->next) {
            const auto* job=link->item;
            if(job) {
                const df3d_pending_work::Tile tile{job->pos.x,job->pos.y,job->pos.z};
                df3d_pending_work::add(next,tile,df3d_pending_work::classify(job->job_type),{t.sizeX,t.sizeY,t.sizeZ});
                if(job->job_type==df::job_type::CarveTrack && df3d_pending_work::valid(tile,{t.sizeX,t.sizeY,t.sizeZ})) {
                    const auto flags=job->specflag.carve_track_flags.bits;
                    nextTracks[tile] |= (flags.carve_track_north?1:0)|(flags.carve_track_south?2:0)|(flags.carve_track_east?4:0)|(flags.carve_track_west?8:0);
                }
                const auto operation=df3d_pending_work::operation<mir::DesignationKind>(job->job_type);
                if(operation!=mir::DesignationKind::None && df3d_pending_work::valid(tile,{t.sizeX,t.sizeY,t.sizeZ}))
                    nextOperations[tile]=std::max(nextOperations[tile],uint8_t(operation));
            }
        }
        auto changed=t.pendingWork.replace(std::move(next));
        const auto operationsChanged=t.pendingOperations.replace(std::move(nextOperations));
        changed.insert(operationsChanged.begin(),operationsChanged.end());
        const auto tracksChanged=t.pendingTracks.replace(std::move(nextTracks));
        changed.insert(tracksChanged.begin(),tracksChanged.end());
        for(const auto& block:changed) {
            // Job creation/removal can leave every raw designation bit unchanged.
            // Only affected blocks bypass the raw shadow shortcut on this update.
            const auto index=shm::terrainBlockIndex(t.grid,block[0],block[1],block[2]);
            t.shadow[index].scanned=0;
            hintBlock(block[0],block[1],block[2]);
        }
    }

    void scanTerrain(uint64_t tick, void (*hintRecentCombat)(uint64_t)) {
        TerrainState& t = terrain;
        if (!t.grid) return;
        t.engravedPosBuilt = false;
        refreshPendingWork();
        refreshWarningBuildings();
        for(const auto* unit:world->units.active) if(unit && unit->pos.x>=0 && unit->pos.y>=0) {
            const auto* job=unit->job.current_job;
            if(!unit->body.wounds.empty() || (job && (job->job_type==df::job_type::Clean ||
                job->job_type==df::job_type::CleanPatient || job->job_type==df::job_type::CleanSelf)))
                hintBlock(unit->pos.x>>4,unit->pos.y>>4,unit->pos.z);
        }
        if (hintRecentCombat) hintRecentCombat(tick);

        // New engravings do not change tiletype or designation: hint their blocks.
        const auto& engravings = df::engraving::get_vector();
        const size_t nEngr = engravings.size();
        if (nEngr < t.engravingsSeen) {
            t.engravingsSeen = 0;  // shrank (deconstructed?): let the slice pick it up
        }
        for (size_t i = t.engravingsSeen; i < nEngr; ++i) {
            const df::coord p = engravings[i]->pos;
            hintBlock(p.x >> 4, p.y >> 4, p.z);
        }
        t.engravingsSeen = nEngr;

        bool batchOpen = false;
        for (uint32_t idx : t.hinted) {
            t.hintMark[idx] = 0;
            scanBlock(idx, false, batchOpen, true);
        }
        t.hinted.clear();

        // A requested full rescan is spread over updates (scan_schedule.h).
        const uint32_t n = df3d_scan_schedule::sliceThisUpdate(t.sliceBlocks, t.rescanRemaining, t.blockCount);
        t.rescanRemaining -= std::min(n, t.rescanRemaining);
        for (uint32_t i = 0; i < n; ++i) {
            scanBlock(t.scanCursor, false, batchOpen, true);
            if (++t.scanCursor >= t.blockCount) {
                t.scanCursor = 0;
                ++t.fullPasses;
            }
        }
        // Dependency refreshes, including those the scans above produced
        // (a refresh that finds a raw change may append more; marks bound it).
        for (size_t i = 0; i < t.detailHinted.size(); ++i) {
            const uint32_t idx = t.detailHinted[i];
            t.detailHintMark[idx] = 0;
            scanBlock(idx, false, batchOpen, true, true);
        }
        t.detailHinted.clear();
        if (batchOpen)
            shm::terrainEndWrite(t.grid, tick);
    }

    bool createTerrain(color_ostream& out, shm::RegionHeader* region) {
#ifdef _WIN32
        TerrainState& t = terrain;
        if (t.grid)
            destroyTerrain(region);
        if (!Maps::IsValid()) {
            out.printerr("df3d: map not valid; terrain grid not created\n");
            return false;
        }
        t.sizeX = world->map.x_count;
        t.sizeY = world->map.y_count;
        t.sizeZ = world->map.z_count;
        t.blocksX = shm::terrainBlocksAlong(t.sizeX);
        t.blocksY = shm::terrainBlocksAlong(t.sizeY);
        const uint64_t nBlocks = shm::terrainBlockCount(t.sizeX, t.sizeY, t.sizeZ);
        if (nBlocks == 0 || nBlocks > 0x7FFFFFFFu) {
            out.printerr("df3d: unsupported map size {}x{}x{}\n", t.sizeX, t.sizeY, t.sizeZ);
            return false;
        }
        t.blockCount = static_cast<uint32_t>(nBlocks);
        const uint64_t epoch = (static_cast<uint64_t>(GetCurrentProcessId()) << 32) |
                               static_cast<uint32_t>(++epochCounter);
        const size_t size = shm::terrainRegionSize(nBlocks, shm::kDefaultTerrainMaterialsCapacity);
        char name[64];
        shm::terrainRegionName(epoch, name, sizeof(name));
        HANDLE mapping = CreateFileMappingA(
            INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
            static_cast<DWORD>(static_cast<uint64_t>(size) >> 32),
            static_cast<DWORD>(size & 0xFFFFFFFFu), name);
        if (!mapping) {
            out.printerr("df3d: CreateFileMapping(terrain) failed (error {})\n", GetLastError());
            return false;
        }
        void* view = MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, 0);
        if (!view) {
            out.printerr("df3d: MapViewOfFile(terrain) failed (error {})\n", GetLastError());
            CloseHandle(mapping);
            return false;
        }
        t.mapping = mapping;
        t.grid = static_cast<shm::TerrainHeader*>(view);
        t.epoch = epoch;
        shm::initTerrain(t.grid, static_cast<uint32_t>(mir::SchemaVersion::Current), t.sizeX, t.sizeY,
                         t.sizeZ, epoch);
        t.shadow.assign(t.blockCount, ShadowBlock{});
        t.hintMark.assign(t.blockCount, 0);
        t.detailHinted.clear();
        t.detailHintMark.assign(t.blockCount, 0);
        t.jobStampValid = false;
        t.rescanRemaining = 0;
        t.pendingMark.assign(t.blockCount, 0);
        t.pendingDelta.clear();
        t.pendingHead = 0;
        t.repeat.clear();
        t.repeatUntil.assign(t.blockCount, -1);
        t.scanCursor = 0;
        t.geo.reset(new MapExtras::MapCache());
        t.engravingsSeen = 0;
        t.warnedMaterialTableFull = false;

        // Initial scan: every block, no Delta queueing (the grid IS the base).
        refreshPendingWork();
        refreshWarningBuildings();
        const auto t0 = Clock::now();
        bool batchOpen = true;
        shm::terrainBeginWrite(t.grid);
        for (uint32_t idx = 0; idx < t.blockCount; ++idx)
            scanBlock(idx, true, batchOpen, false);
        shm::terrainEndWrite(t.grid, static_cast<uint64_t>(world->frame_counter));
        // Barrier-index differences against the empty pre-map indexes are
        // covered by the forced pass above.
        for (uint32_t idx : t.detailHinted) t.detailHintMark[idx] = 0;
        t.detailHinted.clear();
        t.initialScanMs = usSince(t0) / 1000.0;
        t.blocksChanged = 0;  // the initial scan is not "change"

        // Publish the epoch last: clients attach only to a complete grid.
        shm::atomicStoreRelease(&region->terrainEpoch, epoch);
        out.print("df3d: terrain grid '{}' created: {}x{}x{} tiles, {} blocks, {} MB, "
                  "{} materials, initial scan {:.1f} ms\n",
                  name, t.sizeX, t.sizeY, t.sizeZ, t.blockCount, size / (1024 * 1024),
                  t.grid->materialCount, t.initialScanMs);
        return true;
#else
        (void)out;
        return false;
#endif
    }

    // ---- per-snapshot materials table ----
    //
    // One table per snapshot, shared by terrain blocks, buildings and items:
    // grid material id -> snapshot-local index, interned lazily as referenced.
    // beginSnapshotMaterials() resets the remap, localMaterial() interns,
    // finishSnapshotMaterials() creates the vector (0 when nothing referenced).

    void beginSnapshotMaterials() {
        TerrainState& t = terrain;
        for (uint16_t id : t.remapTouched) t.remap[id] = shm::kTerrainNoMaterial;
        t.remapTouched.clear();
        t.gridStr.clear();
        t.gridLen.clear();
        materialOffsets.clear();
    }

    // Materials table: walk the grid table once per snapshot, lazily, as ids
    // are needed (the glyph tables walk it too).
    void ensureGridStrings() {
        TerrainState& t = terrain;
        if (!t.grid || !t.gridStr.empty()) return;
        const uint64_t n = shm::atomicLoadAcquire(&t.grid->materialCount);
        const uint64_t bytes = shm::atomicLoadAcquire(&t.grid->materialBytes);
        t.gridStr.reserve(n);
        t.gridLen.reserve(n);
        size_t off = 0;
        const char* str = nullptr;
        uint16_t l = 0;
        while (t.gridStr.size() < n &&
               shm::terrainMaterialNext(shm::terrainMaterials(t.grid), bytes, off, &str, &l)) {
            t.gridStr.push_back(str);
            t.gridLen.push_back(l);
        }
    }

    uint16_t localMaterial(flatbuffers::FlatBufferBuilder& fbb, uint16_t m) {
        TerrainState& t = terrain;
        if (m == shm::kTerrainNoMaterial || !t.grid) return mir::kNoMaterial;
        if (m >= t.remap.size()) t.remap.resize(m + 1, shm::kTerrainNoMaterial);
        if (t.remap[m] == shm::kTerrainNoMaterial) {
            ensureGridStrings();
            if (m >= t.gridStr.size()) return mir::kNoMaterial;
            t.remap[m] = static_cast<uint16_t>(materialOffsets.size());
            materialOffsets.push_back(fbb.CreateString(t.gridStr[m], t.gridLen[m]));
            t.remapTouched.push_back(m);
        }
        return t.remap[m];
    }

    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<flatbuffers::String>>>
    finishSnapshotMaterials(flatbuffers::FlatBufferBuilder& fbb) {
        if (materialOffsets.empty()) return 0;
        return fbb.CreateVector(materialOffsets);
    }

    // Serializes grid blocks [blocks, blocks+count) into `fbb`, interning
    // their materials into the current snapshot table. Returns the blocks
    // vector offset.
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mir::MapBlock>>>
    buildBlocks(flatbuffers::FlatBufferBuilder& fbb, const uint32_t* blocks, size_t count) {
        TerrainState& t = terrain;
        blockOffsets.clear();
        blockOffsets.reserve(count);

        mir::TileState tiles[256];
        std::vector<mir::DesignationDetail> details;
        std::vector<mir::MapIndicator> indicators;
        std::vector<uint16_t> trackClearanceBlocked,trackHorizontalBlocked,trackSupport,trackOpen;
        details.reserve(256);
        for (size_t i = 0; i < count; ++i) {
            const uint32_t idx = blocks[i];
            const shm::TerrainTile* src = shm::terrainBlockTiles(t.grid, idx);
            details.clear(); indicators.clear(); trackClearanceBlocked.clear(); trackHorizontalBlocked.clear(); trackSupport.clear(); trackOpen.clear();
            for (int k = 0; k < 256; ++k) {
                if(src[k].track_blockers&1) trackClearanceBlocked.push_back(uint16_t(k));
                if(src[k].track_blockers&4) trackSupport.push_back(uint16_t(k));
                if(src[k].track_blockers&8) trackOpen.push_back(uint16_t(k));
                if(src[k].track_blockers&2) trackHorizontalBlocked.push_back(uint16_t(k));
                const uint16_t m = localMaterial(fbb, src[k].material);
                tiles[k] = mir::TileState(static_cast<mir::TileShape>(src[k].shape),
                                          static_cast<mir::MaterialKind>(src[k].material_kind), m,
                                          src[k].liquid_level,
                                          static_cast<mir::LiquidKind>(src[k].liquid_kind),
                                          static_cast<mir::TileFlags>(src[k].flags), static_cast<mir::DesignationKind>(shm::terrainOperation(src[k].designation)));
                if(src[k].track || src[k].traffic || src[k].warnings)
                    indicators.emplace_back(uint16_t(k),src[k].track,src[k].traffic,src[k].warnings);
                if(shm::terrainPriority(src[k].designation) || shm::terrainMarker(src[k].designation))
                    details.emplace_back(uint16_t(k),shm::terrainPriority(src[k].designation),shm::terrainMarker(src[k].designation));
            }
            int32_t bx, by, bz;
            blockCoords(idx, bx, by, bz);
            auto tilesVec = fbb.CreateVectorOfStructs(tiles, 256);
            blockOffsets.push_back(mir::CreateMapBlock(fbb, bx, by, bz, tilesVec, fbb.CreateVectorOfStructs(details), fbb.CreateVectorOfStructs(indicators), fbb.CreateVector(trackClearanceBlocked), fbb.CreateVector(trackHorizontalBlocked),fbb.CreateVector(trackSupport),fbb.CreateVector(trackOpen)));
        }
        return fbb.CreateVector(blockOffsets);
    }

    // Blocks per ring snapshot that are guaranteed to fit: slot capacity minus
    // a generous reserve for units, appearances, the materials table and the
    // capped entity tables (40 000 records of <= 100 bytes), over the
    // Worst case includes both sparse vectors populated for every tile.
    size_t maxDeltaBlocks(size_t cap) {
        const size_t reserve = 6u * 1024 * 1024;
        if (cap <= reserve) return 0;
        return (cap - reserve) / (256 * (sizeof(mir::TileState)+sizeof(mir::DesignationDetail)+sizeof(mir::MapIndicator)) + 96);
    }


    size_t prepareDelta(int32_t frame, size_t snapshotCapacity) {
        TerrainState& t = terrain;
        // Delta blocks for this frame: the head of the spill queue (new
        // changes), bounded, then the repeat window's blocks that are not
        // already in it (lowest priority: dropped first when the cap binds).
        nNew = 0;
        t.deltaList.clear();
        if (t.grid) {
            const size_t queued = t.pendingDelta.size() - t.pendingHead;
            const size_t cap = maxDeltaBlocks(snapshotCapacity);
            nNew = std::min(queued, cap);
            if (nNew < queued) ++t.spills;
            for (size_t i = 0; i < nNew; ++i) t.deltaList.push_back(t.pendingDelta[t.pendingHead + i]);
            size_t w = 0;
            for (uint32_t idx : t.repeat) {
                if (t.repeatUntil[idx] < frame) {
                    t.repeatUntil[idx] = -1;  // expired: leaves the window
                    continue;
                }
                t.repeat[w++] = idx;
                if (!t.pendingMark[idx] && t.deltaList.size() < cap) t.deltaList.push_back(idx);
            }
            t.repeat.resize(w);
        }
        nBlocks = t.deltaList.size();
        return nBlocks;
    }
    size_t reduceDelta() {
        nNew = nBlocks > nNew ? nNew : nNew / 2;
        nBlocks = nNew;
        ++terrain.spills;
        return nBlocks;
    }
    void published(int32_t frame) {
        TerrainState& t = terrain;
        for (size_t i = 0; i < nNew; ++i) {
            const uint32_t idx = t.pendingDelta[t.pendingHead + i];
            t.pendingMark[idx] = 0;
            // Enter (or extend) the repeat window.
            if (t.repeatUntil[idx] < frame) t.repeat.push_back(idx);
            t.repeatUntil[idx] = frame + static_cast<int32_t>(mir::kEntityRepeatFrames) - 1;
        }
        t.pendingHead += nNew;
        if (t.pendingHead == t.pendingDelta.size()) {
            t.pendingDelta.clear();
            t.pendingHead = 0;
        } else if (t.pendingHead > 4096 && t.pendingHead > t.pendingDelta.size() / 2) {
            t.pendingDelta.erase(t.pendingDelta.begin(),
                                 t.pendingDelta.begin() + static_cast<std::ptrdiff_t>(t.pendingHead));
            t.pendingHead = 0;
        }
        if (nBlocks > 0) {
            ++t.deltasPublished;
            t.deltaBlocksPublished += nBlocks;
            t.repeatBlocksPublished += nBlocks - nNew;
        }
    }
    void printStatus(color_ostream& out) const {
        const TerrainState& t = terrain;
        out.print("  terrain grid:        {}\n", t.grid ? "mapped" : "none");
        if (t.grid) {
            out.print("    epoch / tick:      {:#x} / {}\n", t.epoch, t.grid->gridTick);
            out.print("    map:               {}x{}x{} tiles, {} blocks\n", t.sizeX, t.sizeY, t.sizeZ,
                      t.blockCount);
            out.print("    materials:         {}\n", t.grid->materialCount);
            out.print("    initial scan:      {:.1f} ms\n", t.initialScanMs);
            out.print("    scan slice:        {} blocks/update ({} full passes, cursor {}, rescan owed {})\n",
                      t.sliceBlocks, t.fullPasses, t.scanCursor, t.rescanRemaining);
            out.print("    blocks scanned:    {} (reclassified {}, changed {})\n", t.blocksScanned,
                      t.blocksReclassified, t.blocksChanged);
            out.print("    deltas published:  {} ({} blocks of which {} repeats, {} spills, {} queued, {} in the repeat window)\n",
                      t.deltasPublished, t.deltaBlocksPublished, t.repeatBlocksPublished, t.spills,
                      t.pendingDelta.size() - t.pendingHead, t.repeat.size());
        }

    }
};

TerrainPublisher::TerrainPublisher() : impl_(std::make_unique<Impl>()) {}
TerrainPublisher::~TerrainPublisher() = default;
bool TerrainPublisher::create(color_ostream& out, shm::RegionHeader* region) { return impl_->createTerrain(out,region); }
void TerrainPublisher::reset(shm::RegionHeader* region) { impl_->destroyTerrain(region); }
bool TerrainPublisher::mapped() const { return impl_->terrain.grid != nullptr; }
uint64_t TerrainPublisher::epoch() const { return impl_->terrain.epoch; }
uint32_t TerrainPublisher::blockCount() const { return impl_->terrain.blockCount; }
mir::TilePos TerrainPublisher::dimensions() const {
    const auto& t=impl_->terrain; return {t.sizeX,t.sizeY,t.sizeZ};
}
void TerrainPublisher::hintBlock(int32_t x,int32_t y,int32_t z) {
    if (mapped()) impl_->hintBlock(x,y,z);
}
void TerrainPublisher::hintAround(int32_t x,int32_t y,int32_t z) {
    if (mapped()) impl_->hintAround(df::coord(x,y,z));
}
void TerrainPublisher::scan(uint64_t tick,void (*hintRecentCombat)(uint64_t)) { impl_->scanTerrain(tick,hintRecentCombat); }
void TerrainPublisher::setSliceBlocks(uint32_t n) { impl_->terrain.sliceBlocks=df3d_scan_schedule::clampSlice(n); }
uint32_t TerrainPublisher::sliceBlocks() const { return impl_->terrain.sliceBlocks; }
void TerrainPublisher::requestRescan() { impl_->terrain.rescanRemaining=impl_->terrain.blockCount; }
void TerrainPublisher::printStatus(color_ostream& out) const { impl_->printStatus(out); }
size_t TerrainPublisher::materialCount() const {
    return mapped() ? static_cast<size_t>(shm::atomicLoadAcquire(&impl_->terrain.grid->materialCount)) : 0;
}
size_t TerrainPublisher::materialTokenCount() { impl_->ensureGridStrings(); return impl_->terrain.gridStr.size(); }
std::string_view TerrainPublisher::materialToken(size_t index) {
    impl_->ensureGridStrings(); const auto& t=impl_->terrain;
    return index<t.gridStr.size() ? std::string_view(t.gridStr[index],t.gridLen[index]) : std::string_view{};
}
uint16_t TerrainPublisher::pairMaterial(int16_t type,int32_t index) { return impl_->pairMaterial(type,index); }
void TerrainPublisher::beginSnapshotMaterials() { impl_->beginSnapshotMaterials(); }
uint16_t TerrainPublisher::localMaterial(flatbuffers::FlatBufferBuilder& b,uint16_t id) { return impl_->localMaterial(b,id); }
TerrainPublisher::Materials TerrainPublisher::finishSnapshotMaterials(flatbuffers::FlatBufferBuilder& b) { return impl_->finishSnapshotMaterials(b); }
size_t TerrainPublisher::prepareDelta(int32_t frame,size_t capacity) { return impl_->prepareDelta(frame,capacity); }
size_t TerrainPublisher::reduceDelta() { return impl_->reduceDelta(); }
TerrainPublisher::Blocks TerrainPublisher::buildDelta(flatbuffers::FlatBufferBuilder& b) {
    return impl_->buildBlocks(b,impl_->terrain.deltaList.data(),impl_->nBlocks);
}
TerrainPublisher::Blocks TerrainPublisher::buildFull(flatbuffers::FlatBufferBuilder& b) {
    vector<uint32_t> all(blockCount());
    for (uint32_t i=0;i<all.size();++i) all[i]=i;
    return impl_->buildBlocks(b,all.data(),all.size());
}
void TerrainPublisher::published(int32_t frame) { impl_->published(frame); }
