#include "commands.h"

#include "DataDefs.h"
#include "TileTypes.h"

#include "modules/Designations.h"
#include "modules/Items.h"
#include "modules/Maps.h"
#include "modules/MapCache.h"
#include "modules/Materials.h"
#include "modules/Job.h"
#include "command_util.h"
#include "pending_work.h"
#include "rect_cursor.h"
#include "track_route.h"
#include "track_terrain.h"

#include "df/block_square_event_designation_priorityst.h"
#include "df/building.h"
#include "df/building_doorst.h"
#include "df/building_hatchst.h"
#include "df/item.h"
#include "df/inorganic_raw.h"
#include "df/material_flags.h"
#include "df/job.h"
#include "df/map_block.h"
#include "df/plant.h"
#include "df/plant_type.h"
#include "df/tile_dig_designation.h"
#include "df/world.h"

#include <chrono>
#include <set>
#include <string>
#include <vector>

using namespace DFHack;
using df::global::world;

namespace df3d_commands {

namespace mir = df3d::mirror;

namespace {

Hooks g_hooks;
Stats g_stats;

using Clock = std::chrono::steady_clock;

double usSince(Clock::time_point t0) {
    return std::chrono::duration<double, std::micro>(Clock::now() - t0).count();
}

void hintBlock(int32_t x, int32_t y, int32_t z) {
    if (g_hooks.hintBlock) g_hooks.hintBlock(x >> 4, y >> 4, z);
}

// DFHack's dig plugin never designates the map border; DF's UI does not
// either.
bool onMapBorder(int32_t x, int32_t y) {
    return x <= 0 || y <= 0 || x >= world->map.x_count - 1 || y >= world->map.y_count - 1;
}

df::tile_dig_designation mapDig(mir::DigKind k) {
    switch (k) {
    case mir::DigKind::RemoveStairsRamps:
    case mir::DigKind::Dig: return df::tile_dig_designation::Default;
    case mir::DigKind::Channel: return df::tile_dig_designation::Channel;
    case mir::DigKind::RampUp: return df::tile_dig_designation::Ramp;
    case mir::DigKind::StairsUp: return df::tile_dig_designation::UpStair;
    case mir::DigKind::StairsDown: return df::tile_dig_designation::DownStair;
    case mir::DigKind::StairsUpDown: return df::tile_dig_designation::UpDownStair;
    default: return df::tile_dig_designation::No;
    }
}

// The block's designation-priority event, allocated on first write (the
// same shape as DFHack's MapCache::getPriorityEvent).
df::block_square_event_designation_priorityst* priorityEvent(df::map_block* block, bool write) {
    std::vector<df::block_square_event_designation_priorityst*> events;
    Maps::SortBlockEvents(block, 0, 0, 0, 0, 0, 0, 0, &events);
    if (!events.empty()) return events[0];
    if (!write) return nullptr;
    auto* event = df::allocate<df::block_square_event_designation_priorityst>();
    block->block_events.push_back(static_cast<df::block_square_event*>(event));
    return event;
}

// Can `kind` be designated on a tile of this shape / material? Mirrors
// native mining tools: Mine only excavates walls; remove ramps/stairs is
// a distinct operation although both use native Default. Hidden tiles are accepted (DF lets the player
// designate undisclosed rock).
bool digAllowed(df::tiletype tt, const df::tile_designation& des, mir::DigKind kind) {
    if (kind == mir::DigKind::RemoveStairsRamps) {
        const auto shape = tileShape(tt);
        return !des.bits.hidden && tileMaterial(tt) != df::tiletype_material::CONSTRUCTION &&
            (shape == df::tiletype_shape::RAMP || shape == df::tiletype_shape::STAIR_UP || shape == df::tiletype_shape::STAIR_UPDOWN);
    }
    if (des.bits.hidden) return true;
    if (tileMaterial(tt) == df::tiletype_material::CONSTRUCTION) return false;
    const df::tiletype_shape ts = tileShape(tt);
    if (ts == df::tiletype_shape::EMPTY) return false;
    const df::tiletype_shape_basic tsb = ENUM_ATTR(tiletype_shape, basic_shape, ts);
    switch (tsb) {
    case df::tiletype_shape_basic::Wall:
        return true;
    case df::tiletype_shape_basic::Floor:
        if (kind != mir::DigKind::Channel && kind != mir::DigKind::StairsDown) return false;
        return ts != df::tiletype_shape::BRANCH && ts != df::tiletype_shape::TRUNK_BRANCH &&
               ts != df::tiletype_shape::TWIG;
    case df::tiletype_shape_basic::Stair:
        return kind == mir::DigKind::Channel || kind==mir::DigKind::StairsDown || kind==mir::DigKind::StairsUpDown;
    case df::tiletype_shape_basic::Ramp:
        return kind == mir::DigKind::Channel || kind==mir::DigKind::StairsDown;
    default:
        return false;
    }
}

std::string countMessage(const char* what, uint64_t applied, uint64_t visited, uint64_t skipped,
                         const char* skipReason) {
    std::string m = std::to_string(applied) + " of " + std::to_string(visited) + " " + what;
    if (skipped) m += " (" + std::to_string(skipped) + " skipped: " + skipReason + ")";
    return m;
}

Result rejected(uint64_t seq, std::string why) {
    return Result{seq, mir::CommandStatus::Rejected, std::move(why)};
}

// Designation-relevant jobs, indexed once per drain (beginDrain) and walked
// by every command of that drain instead of the whole linked list per
// command. Jobs this module removes are nulled so no entry dangles.
//
// Invariant: every entry is either null or a live df::job. Within one drain
// the job list may only change through remove() (which nulls the entry) or
// through a DFHack API followed by invalidate() before the next get(). The
// index cannot be tested without DF, so each mutation site is audited here:
//  - removePendingJobs / restoreAndHoldJobs: remove() only.
//  - stepDig / stepSmooth / execTrack: designation bits only, no jobs.
//  - execPlants: Designations::unmarkPlant frees FellTree / GatherPlants jobs
//    (which this index holds) via Job::removeJob; it invalidates afterwards.
//    Designations::markPlant sets bits only.
//  - execItemFlags / execBuildingFlags: no jobs.
// A stale entry would be dereferenced (job->pos, job->job_type) by the next
// Dig / Smooth command of the same update: use-after-free.
struct JobIndex {
    std::vector<df::job*> jobs;
    bool valid = false;
    const std::vector<df::job*>& get() {
        if (valid) return jobs;
        jobs.clear();
        for (auto* link = world->jobs.list.next; link; link = link->next) {
            auto* job = link->item;
            if (!job) continue;
            const auto type = job->job_type;
            if (df3d_pending_work::classify(type) != df3d_pending_work::Kind::None ||
                df3d_pending_work::operation<mir::DesignationKind>(type) != mir::DesignationKind::None ||
                type == df::job_type::CarveTrack)
                jobs.push_back(job);
        }
        valid = true;
        return jobs;
    }
    void invalidate() { valid = false; jobs.clear(); }
    bool remove(df::job* job) {
        if (!Job::removeJob(job)) return false;
        for (auto& j : jobs) if (j == job) { j = nullptr; break; }
        return true;
    }
};
JobIndex g_jobs;

// DFHack removes worker/job links too; merely clearing the tile bit leaves an
// already-created job alive (and may report that no designation was present).
std::set<df3d_pending_work::Tile> removePendingJobs(const mir::TileRect& rect, bool detail, int32_t maxZ = -1) {
    std::set<df3d_pending_work::Tile> removed;
    auto jobs = g_jobs.get();  // copy: removal edits the index
    for (auto* job : jobs) {
        if (!job) continue;
        const df3d_pending_work::Tile tile{job->pos.x,job->pos.y,job->pos.z};
        if((df3d_pending_work::matchesRemoval(df3d_pending_work::classify(job->job_type),detail) || (detail && job->job_type==df::job_type::CarveTrack) || (!detail && (job->job_type==df::job_type::FellTree || job->job_type==df::job_type::GatherPlants))) &&
           tile[2]>=rect.z() && tile[2]<=(maxZ==-1?rect.z():maxZ) &&
           df3d_pending_work::inRect(tile,rect.x1(),rect.y1(),rect.x2(),rect.y2(),tile[2])) {
            if(g_jobs.remove(job)) {
                removed.insert(tile);
                hintBlock(tile[0],tile[1],tile[2]);
            }
        }
    }
    return removed;
}

// Convert pending jobs back into native designations before holding an area.
// DF can consume designation bits when it creates a job; preserving only bits
// would lose work and leave assigned workers executing supposedly held plans.
void restoreAndHoldJobs(const mir::TileRect& r, const std::set<df3d_pending_work::Tile>* replaced = nullptr, int32_t maxZ = -1) {
    auto jobs = g_jobs.get();  // copy: removal edits the index
    for (auto* job : jobs) {
        if (job && (replaced ? replaced->count({job->pos.x,job->pos.y,job->pos.z})!=0 : (job->pos.z>=r.z() && job->pos.z<=(maxZ==-1?r.z():maxZ) && df3d_pending_work::inRect({job->pos.x,job->pos.y,job->pos.z},r.x1(),r.y1(),r.x2(),r.y2(),job->pos.z)))) {
            auto* block = Maps::getTileBlock(job->pos);
            if (block) {
                auto &des=block->designation[job->pos.x&15][job->pos.y&15];
                auto &occ=block->occupancy[job->pos.x&15][job->pos.y&15];
                const auto originalDes=des;
                const auto originalOcc=occ;
                bool supported=true;
                switch(job->job_type) {
                case df::job_type::Dig: case df::job_type::FellTree: case df::job_type::GatherPlants: des.bits.dig=df::tile_dig_designation::Default; break;
                case df::job_type::DigChannel: des.bits.dig=df::tile_dig_designation::Channel; break;
                case df::job_type::CarveRamp: des.bits.dig=df::tile_dig_designation::Ramp; break;
                case df::job_type::CarveUpwardStaircase: des.bits.dig=df::tile_dig_designation::UpStair; break;
                case df::job_type::CarveDownwardStaircase: des.bits.dig=df::tile_dig_designation::DownStair; break;
                case df::job_type::CarveUpDownStaircase: des.bits.dig=df::tile_dig_designation::UpDownStair; break;
                case df::job_type::SmoothWall: case df::job_type::SmoothFloor: case df::job_type::CarveFortification: des.bits.smooth=1; break;
                case df::job_type::DetailWall: case df::job_type::DetailFloor: des.bits.smooth=2; break;
                case df::job_type::CarveTrack:
                    occ.bits.carve_track_north=job->specflag.carve_track_flags.bits.carve_track_north;
                    occ.bits.carve_track_south=job->specflag.carve_track_flags.bits.carve_track_south;
                    occ.bits.carve_track_east=job->specflag.carve_track_flags.bits.carve_track_east;
                    occ.bits.carve_track_west=job->specflag.carve_track_flags.bits.carve_track_west; break;
                default: supported=false; break;
                }
                if(supported) {
                    if(replaced) { des=originalDes; occ=originalOcc; }
                    occ.bits.dig_marked=true;
                    block->flags.bits.designated=true;
                    if(!g_jobs.remove(job)) { des=originalDes; occ=originalOcc; }
                }
            }
        }
    }
}

// A rectangle command in progress: dig or smooth over up to 65 536 tiles per
// level runs in slices across updates (the between-command budget is soft;
// one command must not blow it). The command bytes are copied because the
// drain buffer is reused; the cursor and counters carry the partial walk.
// Sent is not succeeded: the result is queued only once the walk finished.
struct PendingRect {
    bool active = false;
    bool smooth = false;
    std::vector<uint8_t> buf;
    df3d_rect_cursor::Cursor cursor;
    uint64_t visited = 0, applied = 0, notDiggable = 0, noBlock = 0, border = 0, skipped = 0;
    std::set<df3d_pending_work::Tile> removedJobs, held;
    double us = 0;  // execution time accumulated over slices
};
PendingRect g_pending;
// Tiles between two deadline checks inside a slice.
constexpr uint64_t kDeadlineCheckTiles = 256;

bool smoothableMaterial(df::tiletype tt) {
    switch (tileMaterial(tt)) {
    case df::tiletype_material::STONE:
    case df::tiletype_material::LAVA_STONE:
    case df::tiletype_material::MINERAL:
    case df::tiletype_material::FEATURE:
        return true;
    default:
        return false;
    }
}

void beginDig(const mir::Command& cmd) {
    const mir::DesignateDig* d = cmd.payload_as_DesignateDig();
    const mir::TileRect* r = d->rect();
    PendingRect& p = g_pending;
    if(d->kind()==mir::DigKind::Mark) restoreAndHoldJobs(*r,nullptr,d->max_z());
    if(d->kind()==mir::DigKind::Remove) p.removedJobs = removePendingJobs(*r,false,d->max_z());
    const int32_t maxZ=d->max_z()==-1?r->z():d->max_z();
    p.cursor.begin(r->x1(), r->y1(), r->x2(), r->y2(), r->z(), maxZ);
}

// One slice of the dig walk; false when the deadline passed before the end.
bool stepDig(const mir::Command& cmd, Clock::time_point deadline) {
    const mir::DesignateDig* d = cmd.payload_as_DesignateDig();
    const mir::TileRect* r = d->rect();
    PendingRect& p = g_pending;
    MapExtras::MapCache cache;
    const int32_t prio = static_cast<int32_t>(d->priority()) * 1000;
    const int32_t maxZ = p.cursor.z2;
    uint64_t sinceCheck = 0;
    for (; !p.cursor.done; p.cursor.next()) {
        if (++sinceCheck >= kDeadlineCheckTiles) {
            sinceCheck = 0;
            if (Clock::now() >= deadline) return false;
        }
        const int32_t x = p.cursor.x, y = p.cursor.y, z = p.cursor.z;
        ++p.visited;
        df::map_block* blk = Maps::getTileBlock(x, y, z);
        if (!blk) {
            ++p.noBlock;
            continue;
        }
        const int lx = x & 15, ly = y & 15;
        df::tile_designation& des = blk->designation[lx][ly];
        auto kind=d->kind();
        if(kind==mir::DigKind::StairsSpan) {
            const auto shape=tileShape(blk->tiletype[lx][ly]);
            const auto basic=ENUM_ATTR(tiletype_shape,basic_shape,shape);
            kind=z==r->z()?mir::DigKind::StairsUp:z==maxZ?mir::DigKind::StairsDown:mir::DigKind::StairsUpDown;
            if(!des.bits.hidden) {
                const bool wall=basic==df::tiletype_shape_basic::Wall;
                const bool floor=basic==df::tiletype_shape_basic::Floor || basic==df::tiletype_shape_basic::Ramp;
                const bool up=shape==df::tiletype_shape::STAIR_UP;
                if(z==r->z() ? !wall : !(wall || floor || up)) { ++p.notDiggable; continue; }
                if(kind==mir::DigKind::StairsUpDown && floor) kind=mir::DigKind::StairsDown;
            }
        }
        auto &occ=blk->occupancy[lx][ly];
        if(d->kind()==mir::DigKind::Activate || d->kind()==mir::DigKind::Mark) {
            if(des.bits.dig==df::tile_dig_designation::No && !des.bits.smooth && !occ.bits.carve_track_north && !occ.bits.carve_track_south && !occ.bits.carve_track_east && !occ.bits.carve_track_west) continue;
            occ.bits.dig_marked=d->kind()==mir::DigKind::Mark;
        } else if (d->kind() == mir::DigKind::Remove) {
            if (des.bits.dig == df::tile_dig_designation::No && !p.removedJobs.count({x,y,z})) continue;
            des.bits.dig = df::tile_dig_designation::No;
            occ.bits.dig_auto=false;
            if(!des.bits.smooth) occ.bits.dig_marked=false;
        } else {
            if (onMapBorder(x, y)) {
                ++p.border;
                continue;
            }
            if (!digAllowed(blk->tiletype[lx][ly], des, kind)) {
                ++p.notDiggable;
                continue;
            }
            if(d->mining_mode()!=0) {
                const auto mat=cache.baseMaterialAt(df::coord(x,y,z));
                MaterialInfo info(mat);
                const bool gem=info.material && info.material->flags.is_set(df::material_flags::IS_GEM);
                // DFHack Materials::isOre includes both smelted and strand-extracted metals.
                const bool ore=info.inorganic && (!info.inorganic->metal_ore.mat_index.empty() || !info.inorganic->thread_metal.mat_index.empty());
                const bool matches=d->mining_mode()==1 ? tileMaterial(blk->tiletype[lx][ly])==df::tiletype_material::MINERAL : (gem || (d->mining_mode()==2 && ore));
                if(des.bits.hidden || !matches) { ++p.notDiggable; continue; }
            }
            des.bits.dig = mapDig(kind);
            occ.bits.dig_auto=d->mining_mode()==1 && d->kind()==mir::DigKind::Dig;
            occ.bits.dig_marked=d->marker();
            if (auto* ev = priorityEvent(blk, true)) ev->priority[lx][ly] = prio;
        }
        blk->flags.bits.designated = true;
        ++p.applied;
        if(d->marker()) p.held.insert({x,y,z});
        hintBlock(x, y, z);
    }
    return true;
}

Result finishDig(const mir::Command& cmd) {
    const mir::DesignateDig* d = cmd.payload_as_DesignateDig();
    const mir::TileRect* r = d->rect();
    PendingRect& p = g_pending;
    if(!p.held.empty()) restoreAndHoldJobs(*r,&p.held);
    g_stats.tilesVisited += p.visited;
    g_stats.tilesApplied += p.applied;
    const uint64_t skipped = p.notDiggable + p.noBlock + p.border;
    const char* reason = p.notDiggable ? "not diggable" : (p.border ? "map border" : "no map block");
    if (p.applied == 0) {
        if (d->kind() == mir::DigKind::Remove) return rejected(cmd.seq(), "no dig designation in the rect");
        return rejected(cmd.seq(), countMessage("tiles", 0, p.visited, skipped, reason));
    }
    return Result{cmd.seq(), mir::CommandStatus::Ok, countMessage("tiles", p.applied, p.visited, skipped, reason)};
}

Result execTrack(const mir::Command& cmd) {
    const auto* d=cmd.payload_as_DesignateSmooth();
    const auto* r=d->rect();
    const auto clearance=df3d_track_terrain::buildClearanceIndex();
    const auto horizontal=df3d_track_terrain::buildHorizontalIndex();
    const df3d::track::Point start{d->from_east()?r->x2():r->x1(),d->from_south()?r->y2():r->y1(),r->z()};
    const df3d::track::Point end{d->from_east()?r->x1():r->x2(),d->from_south()?r->y1():r->y2(),d->track_end_z()==-1?r->z():d->track_end_z()};
    const auto lookup=[&](df3d::track::Point p) {
        df3d::track::Terrain out;
        if(onMapBorder(p.x,p.y) || p.z<0 || p.z>=world->map.z_count) return out;
        const auto* block=Maps::getTileBlock(p.x,p.y,p.z);
        if(!block) return out;
        const auto tt=block->tiletype[p.x&15][p.y&15];
        const auto shape=tileShape(tt);
        const auto basic=ENUM_ATTR(tiletype_shape,basic_shape,shape);
        out.ramp=shape==df::tiletype_shape::RAMP;
        out.rampTop=tt==df::tiletype::RampTop;
        out.open=tt==df::tiletype::OpenSpace || tt==df::tiletype::Chasm || tt==df::tiletype::EeriePit;
        out.support=shape==df::tiletype_shape::WALL || shape==df::tiletype_shape::FORTIFICATION;
        out.eligible=!block->designation[p.x&15][p.y&15].bits.hidden && smoothableMaterial(tt) &&
            (basic==df::tiletype_shape_basic::Floor || out.ramp);
        out.clearanceBlocked=df3d_track_terrain::clearanceBlocked(block,p.x&15,p.y&15,clearance);
        out.horizontalBlocked=df3d_track_terrain::horizontalBlocked(block,p.x&15,p.y&15,horizontal);
        return out;
    };
    const auto path=df3d::track::route(start,end,[&](df3d::track::Point p){return lookup(p).eligible;},
        [&](df3d::track::Point from,df3d::track::Point to) {
            return (from==start || !lookup(from).horizontalBlocked) && df3d::track::connected(from,to,lookup);
        });
    if(path.empty()) return rejected(cmd.seq(),"no eligible track route within search limit");
    std::set<df3d_pending_work::Tile> held;
    uint64_t applied=0, noBlock=0;
    for(const auto& tile:path) {
        const auto [x,y,z]=tile.point;
        auto* block=Maps::getTileBlock(x,y,z);
        if(!block) { ++noBlock; continue; }  // routed through an unallocated block: skip, count
        auto& occ=block->occupancy[x&15][y&15];
        occ.bits.carve_track_north|=(tile.mask&1)!=0;
        occ.bits.carve_track_south|=(tile.mask&2)!=0;
        occ.bits.carve_track_east|=(tile.mask&4)!=0;
        occ.bits.carve_track_west|=(tile.mask&8)!=0;
        occ.bits.dig_marked=d->marker();
        priorityEvent(block,true)->priority[x&15][y&15]=int32_t(d->priority())*1000;
        block->flags.bits.designated=true;
        if(d->marker()) held.insert({x,y,z});
        hintBlock(x,y,z);
        ++applied;
    }
    if(!held.empty()) restoreAndHoldJobs(*r,&held);
    g_stats.tilesApplied+=applied; g_stats.tilesVisited+=path.size();
    if(applied==0) return rejected(cmd.seq(),countMessage("track tiles",0,path.size(),noBlock,"no map block"));
    return Result{cmd.seq(),mir::CommandStatus::Ok,countMessage("track tiles",applied,path.size(),noBlock,"no map block")};
}

void beginSmooth(const mir::Command& cmd) {
    const mir::DesignateSmooth* d = cmd.payload_as_DesignateSmooth();
    const mir::TileRect* r = d->rect();
    PendingRect& p = g_pending;
    if(d->kind()==mir::SmoothKind::Remove) p.removedJobs = removePendingJobs(*r,true,d->max_z());
    const int32_t maxZ=d->max_z()==-1?r->z():d->max_z();
    p.cursor.begin(r->x1(), r->y1(), r->x2(), r->y2(), r->z(), maxZ);
}

bool stepSmooth(const mir::Command& cmd, Clock::time_point deadline) {
    const mir::DesignateSmooth* d = cmd.payload_as_DesignateSmooth();
    PendingRect& p = g_pending;
    uint64_t sinceCheck = 0;
    for (; !p.cursor.done; p.cursor.next()) {
        if (++sinceCheck >= kDeadlineCheckTiles) {
            sinceCheck = 0;
            if (Clock::now() >= deadline) return false;
        }
        const int32_t x = p.cursor.x, y = p.cursor.y, z = p.cursor.z;
        ++p.visited;
        df::map_block* blk = Maps::getTileBlock(x, y, z);
        if (!blk) {
            ++p.skipped;
            continue;
        }
        const int lx = x & 15, ly = y & 15;
        df::tile_designation& des = blk->designation[lx][ly];
        if (d->kind() == mir::SmoothKind::Remove) {
            auto &occ=blk->occupancy[lx][ly];
            if (des.bits.smooth == 0 && !occ.bits.carve_track_north && !occ.bits.carve_track_south && !occ.bits.carve_track_east && !occ.bits.carve_track_west && !p.removedJobs.count({x,y,z})) continue;
            des.bits.smooth = 0;
            occ.bits.carve_track_north=occ.bits.carve_track_south=occ.bits.carve_track_east=occ.bits.carve_track_west=0;
            if(des.bits.dig==df::tile_dig_designation::No) occ.bits.dig_marked=false;
        } else {
            const df::tiletype tt = blk->tiletype[lx][ly];
            const df::tiletype_shape ts = tileShape(tt);
            const df::tiletype_shape_basic tsb = ENUM_ATTR(tiletype_shape, basic_shape, ts);
            const df::tiletype_special sp = tileSpecial(tt);
            const bool smooth = sp == df::tiletype_special::SMOOTH ||
                                sp == df::tiletype_special::SMOOTH_DEAD ||
                                sp == df::tiletype_special::TRACK;
            const bool shapeOk = (tsb == df::tiletype_shape_basic::Wall ||
                                  tsb == df::tiletype_shape_basic::Floor) &&
                                 ts != df::tiletype_shape::FORTIFICATION;
            bool ok = !des.bits.hidden && shapeOk && smoothableMaterial(tt);
            if (d->kind() == mir::SmoothKind::Smooth) ok = ok && !smooth;
            else if(d->kind()==mir::SmoothKind::Fortify) ok = ok && smooth && tsb==df::tiletype_shape_basic::Wall;
            else ok = ok && smooth;  // engrave wants a smoothed tile
            if (!ok) {
                ++p.skipped;
                continue;
            }
            des.bits.smooth = d->kind() == mir::SmoothKind::Engrave ? 2 : 1;
            blk->occupancy[lx][ly].bits.dig_marked=d->marker();
            priorityEvent(blk,true)->priority[lx][ly]=int32_t(d->priority())*1000;
        }
        blk->flags.bits.designated = true;
        ++p.applied;
        if(d->marker()) p.held.insert({x,y,z});
        hintBlock(x, y, z);
    }
    return true;
}

Result finishSmooth(const mir::Command& cmd) {
    const mir::DesignateSmooth* d = cmd.payload_as_DesignateSmooth();
    const mir::TileRect* r = d->rect();
    PendingRect& p = g_pending;
    if(!p.held.empty()) restoreAndHoldJobs(*r,&p.held);
    g_stats.tilesVisited += p.visited;
    g_stats.tilesApplied += p.applied;
    const char* reason = d->kind() == mir::SmoothKind::Engrave ? "not smoothed natural stone"
                                                               : "not rough natural stone";
    if (p.applied == 0) {
        if (d->kind() == mir::SmoothKind::Remove) return rejected(cmd.seq(), "no smooth designation in the rect");
        return rejected(cmd.seq(), countMessage("tiles", 0, p.visited, p.skipped, reason));
    }
    return Result{cmd.seq(), mir::CommandStatus::Ok, countMessage("tiles", p.applied, p.visited, p.skipped, reason)};
}

// The outcome of a rectangle whose walk was cut by a map unload: slices
// already applied cannot be reported or reverted, so it is Unknown (never
// replayed automatically, never silently dropped).
Result unloaded(uint64_t seq) {
    return Result{seq, mir::CommandStatus::Unknown, "map unloaded before the designation completed; applied slices are unknown"};
}

// Runs (or continues) the pending rectangle walk; true with `out` filled
// when it finished, false when the deadline stopped it mid-walk.
bool stepPending(Clock::time_point deadline, Result& out) {
    PendingRect& p = g_pending;
    const mir::Command* cmd = mir::parseCommand(p.buf.data(), p.buf.size());
    if (!cmd || !world || !Maps::IsValid()) {
        // The map went away under a partial walk: at least one slice was
        // applied, so the outcome is Unknown, not Rejected.
        out = unloaded(cmd ? cmd->seq() : 0);
        p = PendingRect();
        return true;
    }
    const bool finished = p.smooth ? stepSmooth(*cmd, deadline) : stepDig(*cmd, deadline);
    if (!finished) return false;
    out = p.smooth ? finishSmooth(*cmd) : finishDig(*cmd);
    p = PendingRect();
    return true;
}

// Trees (Chop) or shrubs (Gather) whose designation tile lies in the rect.
Result execPlants(const mir::Command& cmd, const mir::TileRect* r, bool enable, bool trees, uint8_t priority, bool marker, int32_t maxZ) {
    std::set<df3d_pending_work::Tile> held;
    uint64_t candidates = 0, applied = 0, already = 0, noBlock = 0;
    for (df::plant* p : world->plants.all) {
        if (!p) continue;
        const bool isTree = p->tree_info != nullptr;
        const bool isShrub = ENUM_ATTR(plant_type, is_shrub, p->type);
        if (trees ? !isTree : !(isShrub && !isTree)) continue;
        const df::coord pos = Designations::getPlantDesignationTile(p);
        if (pos.z < r->z() || pos.z > (maxZ==-1?r->z():maxZ) || pos.x < r->x1() || pos.x > r->x2() || pos.y < r->y1() || pos.y > r->y2())
            continue;
        ++candidates;
        // A designation tile without an allocated block cannot carry the
        // priority / marker bits: skip the plant entirely and count it.
        auto* blk=Maps::getTileBlock(pos);
        if (!blk) { ++noBlock; continue; }
        bool changed = enable ? Designations::markPlant(p) : Designations::unmarkPlant(p);
        if (enable && (changed || Designations::isPlantMarked(p))) {
            priorityEvent(blk,true)->priority[pos.x&15][pos.y&15]=int32_t(priority)*1000;
            blk->occupancy[pos.x&15][pos.y&15].bits.dig_marked=marker;
            if(marker) {
                blk->designation[pos.x&15][pos.y&15].bits.dig=df::tile_dig_designation::Default;
                held.insert({pos.x,pos.y,pos.z});
            }
            changed=true;
        }
        if (changed) {
            ++applied;
            hintBlock(pos.x, pos.y, pos.z);
        } else {
            ++already;
        }
    }
    // unmarkPlant removed FellTree / GatherPlants jobs behind the index
    // (JobIndex invariant): drop it before anything walks it again, this
    // command's restoreAndHoldJobs included.
    g_jobs.invalidate();
    if(!held.empty()) restoreAndHoldJobs(*r,&held);
    g_stats.plantsMarked += applied;
    const char* what = trees ? "trees" : "shrubs";
    if (candidates == 0) return rejected(cmd.seq(), std::string("no ") + what + " in the rect");
    if (applied == 0) {
        if (already == 0 && noBlock) return rejected(cmd.seq(), std::to_string(noBlock) + " " + what + " skipped: no map block");
        return rejected(cmd.seq(), std::to_string(already) + " " + what + (enable ? " already marked" : " not marked"));
    }
    return Result{cmd.seq(), mir::CommandStatus::Ok,
                  countMessage(what, applied, candidates, already, enable ? "already marked" : "not marked")};
}

Result execItemFlags(const mir::Command& cmd) {
    const mir::SetItemFlags* f = cmd.payload_as_SetItemFlags();
    df::item* it = df::item::find(static_cast<int32_t>(f->item()));
    if (!it || it->flags.bits.removed || it->flags.bits.garbage_collect) {
        return rejected(cmd.seq(), "no such item " + std::to_string(f->item()));
    }
    if (f->melt() == mir::OptionalBool::Set && !it->flags.bits.melt && !Items::canMelt(it, true)) {
        return rejected(cmd.seq(), "item " + std::to_string(f->item()) + " cannot be melted");
    }
    std::string msg = "item " + std::to_string(f->item()) + ":";
    if (f->forbidden() != mir::OptionalBool::Unchanged) {
        it->flags.bits.forbid = f->forbidden() == mir::OptionalBool::Set;
        msg += it->flags.bits.forbid ? " forbid" : " unforbid";
    }
    if (f->dump() != mir::OptionalBool::Unchanged) {
        it->flags.bits.dump = f->dump() == mir::OptionalBool::Set;
        msg += it->flags.bits.dump ? " dump" : " undump";
    }
    if (f->melt() != mir::OptionalBool::Unchanged) {
        if (f->melt() == mir::OptionalBool::Set) Items::markForMelting(it);
        else Items::cancelMelting(it);
        msg += it->flags.bits.melt ? " melt" : " unmelt";
    }
    ++g_stats.entitiesChanged;
    if (g_hooks.hintItem) g_hooks.hintItem(it->id);
    return Result{cmd.seq(), mir::CommandStatus::Ok, msg};
}

Result execBuildingFlags(const mir::Command& cmd) {
    const mir::SetBuildingFlags* f = cmd.payload_as_SetBuildingFlags();
    df::building* b = df::building::find(static_cast<int32_t>(f->building()));
    if (!b) return rejected(cmd.seq(), "no such building " + std::to_string(f->building()));
    std::string msg = "building " + std::to_string(f->building()) + ":";
    if (f->forbidden() != mir::OptionalBool::Unchanged) {
        const bool forbid = f->forbidden() == mir::OptionalBool::Set;
        if (auto* door = virtual_cast<df::building_doorst>(b)) {
            door->door_flags.bits.forbidden = forbid;
        } else if (auto* hatch = virtual_cast<df::building_hatchst>(b)) {
            hatch->door_flags.bits.forbidden = forbid;
        } else {
            return rejected(cmd.seq(), "building " + std::to_string(f->building()) +
                                           " is not a door or hatch (DF has no forbid bit for it)");
        }
        msg += forbid ? " forbid" : " unforbid";
    }
    ++g_stats.entitiesChanged;
    if (g_hooks.hintBuilding) g_hooks.hintBuilding(b->id);
    return Result{cmd.seq(), mir::CommandStatus::Ok, msg};
}

}  // namespace

void setHooks(const Hooks& hooks) { g_hooks = hooks; }
const Stats& stats() { return g_stats; }
void resetStatsMax() { g_stats.execUsMax = 0.0; }
void reset() { g_stats = Stats(); g_pending = PendingRect(); g_jobs.invalidate(); }
void beginDrain() { g_jobs.invalidate(); }
bool pending() { return g_pending.active; }

namespace {
void recordExecution(const Result& res, double us) {
    g_stats.execUsLast = us;
    g_stats.execUsEma = g_stats.execUsEma == 0.0 ? us : g_stats.execUsEma + (us - g_stats.execUsEma) / 16.0;
    if (us > g_stats.execUsMax) g_stats.execUsMax = us;
    ++g_stats.executed;
    if (res.status == mir::CommandStatus::Ok) ++g_stats.ok;
    else if (res.status == mir::CommandStatus::Rejected) ++g_stats.rejected;
    else ++g_stats.unknown;
    g_stats.lastMessage = res.message;
}
}  // namespace

bool abandon(Result& out) {
    if (!g_pending.active) return false;
    // Only the command's own byte copy is touched: the map may already be gone.
    const mir::Command* cmd = mir::parseCommand(g_pending.buf.data(), g_pending.buf.size());
    out = unloaded(cmd ? cmd->seq() : 0);
    const double us = g_pending.us;
    g_pending = PendingRect();
    recordExecution(out, us);
    return true;
}

bool resume(Clock::time_point deadline, Result& out) {
    if (!g_pending.active) return true;
    const auto t0 = Clock::now();
    const double before = g_pending.us;  // stepPending resets the record on completion
    const bool finished = stepPending(deadline, out);
    const double us = usSince(t0);
    if (!finished) { g_pending.us += us; return false; }
    recordExecution(out, before + us);
    return true;
}

bool execute(const uint8_t* buf, size_t len, const mir::Command& cmd, Clock::time_point deadline, Result& out) {
    const auto t0 = Clock::now();
    Result res;
    if (!world || !Maps::IsValid()) {
        res = rejected(cmd.seq(), "no map loaded");
    } else {
        switch (cmd.payload_type()) {
        case mir::CommandPayload::DesignateDig:
        case mir::CommandPayload::DesignateSmooth: {
            const bool smooth = cmd.payload_type() == mir::CommandPayload::DesignateSmooth;
            if (smooth && cmd.payload_as_DesignateSmooth()->kind() == mir::SmoothKind::Track) { res = execTrack(cmd); break; }
            g_pending = PendingRect();
            g_pending.active = true;
            g_pending.smooth = smooth;
            g_pending.buf.assign(buf, buf + len);
            if (smooth) beginSmooth(cmd); else beginDig(cmd);
            if (!stepPending(deadline, res)) {
                g_pending.us = usSince(t0);
                return false;
            }
            break;
        }
        case mir::CommandPayload::DesignateChop:
            res = execPlants(cmd, cmd.payload_as_DesignateChop()->rect(),
                             cmd.payload_as_DesignateChop()->enable(), true, cmd.payload_as_DesignateChop()->priority(), cmd.payload_as_DesignateChop()->marker(), cmd.payload_as_DesignateChop()->max_z());
            break;
        case mir::CommandPayload::DesignateGather:
            res = execPlants(cmd, cmd.payload_as_DesignateGather()->rect(),
                             cmd.payload_as_DesignateGather()->enable(), false, cmd.payload_as_DesignateGather()->priority(), cmd.payload_as_DesignateGather()->marker(), cmd.payload_as_DesignateGather()->max_z());
            break;
        case mir::CommandPayload::SetItemFlags: res = execItemFlags(cmd); break;
        case mir::CommandPayload::SetBuildingFlags: res = execBuildingFlags(cmd); break;
        default:
            res = Result{cmd.seq(), mir::CommandStatus::Unknown,
                         "unknown payload type " + std::to_string(static_cast<int>(cmd.payload_type()))};
            break;
        }
    }
    recordExecution(res, usSince(t0));
    out = res;
    return true;
}

}  // namespace df3d_commands
