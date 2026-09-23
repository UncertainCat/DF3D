#include "commands.h"

#include "DataDefs.h"
#include "TileTypes.h"

#include "modules/Designations.h"
#include "modules/Items.h"
#include "modules/Maps.h"
#include "modules/MapCache.h"
#include "modules/Materials.h"
#include "modules/Job.h"
#include "pending_work.h"
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

// Walk the job list once per removal command, never once per selected tile.
// DFHack removes worker/job links too; merely clearing the tile bit leaves an
// already-created job alive (and may report that no designation was present).
std::set<df3d_pending_work::Tile> removePendingJobs(const mir::TileRect& rect, bool detail, int32_t maxZ = -1) {
    std::set<df3d_pending_work::Tile> removed;
    for(auto* link=world->jobs.list.next;link;) {
        auto* next=link->next;
        auto* job=link->item;
        if(job) {
            const df3d_pending_work::Tile tile{job->pos.x,job->pos.y,job->pos.z};
            if((df3d_pending_work::matchesRemoval(df3d_pending_work::classify(job->job_type),detail) || (detail && job->job_type==df::job_type::CarveTrack) || (!detail && (job->job_type==df::job_type::FellTree || job->job_type==df::job_type::GatherPlants))) &&
               tile[2]>=rect.z() && tile[2]<=(maxZ==-1?rect.z():maxZ) &&
               df3d_pending_work::inRect(tile,rect.x1(),rect.y1(),rect.x2(),rect.y2(),tile[2])) {
                if(Job::removeJob(job)) {
                    removed.insert(tile);
                    hintBlock(tile[0],tile[1],tile[2]);
                }
            }
        }
        link=next;
    }
    return removed;
}

// Convert pending jobs back into native designations before holding an area.
// DF can consume designation bits when it creates a job; preserving only bits
// would lose work and leave assigned workers executing supposedly held plans.
void restoreAndHoldJobs(const mir::TileRect& r, const std::set<df3d_pending_work::Tile>* replaced = nullptr, int32_t maxZ = -1) {
    for (auto* link = world->jobs.list.next; link;) {
        auto* next = link->next;
        auto* job = link->item;
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
                    if(!Job::removeJob(job)) { des=originalDes; occ=originalOcc; }
                }
            }
        }
        link=next;
    }
}

Result execDig(const mir::Command& cmd) {
    const mir::DesignateDig* d = cmd.payload_as_DesignateDig();
    const mir::TileRect* r = d->rect();
    MapExtras::MapCache cache;
    if(d->kind()==mir::DigKind::Mark) restoreAndHoldJobs(*r,nullptr,d->max_z());
    const int32_t prio = static_cast<int32_t>(d->priority()) * 1000;
    const auto removedJobs = d->kind()==mir::DigKind::Remove ? removePendingJobs(*r,false,d->max_z()) : std::set<df3d_pending_work::Tile>{};
    std::set<df3d_pending_work::Tile> held;
    uint64_t visited = 0, applied = 0, notDiggable = 0, noBlock = 0, border = 0;
    const int32_t maxZ=d->max_z()==-1?r->z():d->max_z();
    for(int32_t z=r->z(); z<=maxZ; ++z) {
    for (int32_t y = r->y1(); y <= r->y2(); ++y) {
        for (int32_t x = r->x1(); x <= r->x2(); ++x) {
            ++visited;
            df::map_block* blk = Maps::getTileBlock(x, y, z);
            if (!blk) {
                ++noBlock;
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
                    if(z==r->z() ? !wall : !(wall || floor || up)) { ++notDiggable; continue; }
                    if(kind==mir::DigKind::StairsUpDown && floor) kind=mir::DigKind::StairsDown;
                }
            }
            auto &occ=blk->occupancy[lx][ly];
            if(d->kind()==mir::DigKind::Activate || d->kind()==mir::DigKind::Mark) {
                if(des.bits.dig==df::tile_dig_designation::No && !des.bits.smooth && !occ.bits.carve_track_north && !occ.bits.carve_track_south && !occ.bits.carve_track_east && !occ.bits.carve_track_west) continue;
                occ.bits.dig_marked=d->kind()==mir::DigKind::Mark;
            } else if (d->kind() == mir::DigKind::Remove) {
                if (des.bits.dig == df::tile_dig_designation::No && !removedJobs.count({x,y,z})) continue;
                des.bits.dig = df::tile_dig_designation::No;
                occ.bits.dig_auto=false;
                if(!des.bits.smooth) occ.bits.dig_marked=false;
            } else {
                if (onMapBorder(x, y)) {
                    ++border;
                    continue;
                }
                if (!digAllowed(blk->tiletype[lx][ly], des, kind)) {
                    ++notDiggable;
                    continue;
                }
                if(d->mining_mode()!=0) {
                    const auto mat=cache.baseMaterialAt(df::coord(x,y,z));
                    MaterialInfo info(mat);
                    const bool gem=info.material && info.material->flags.is_set(df::material_flags::IS_GEM);
                    // DFHack Materials::isOre includes both smelted and strand-extracted metals.
                    const bool ore=info.inorganic && (!info.inorganic->metal_ore.mat_index.empty() || !info.inorganic->thread_metal.mat_index.empty());
                    const bool matches=d->mining_mode()==1 ? tileMaterial(blk->tiletype[lx][ly])==df::tiletype_material::MINERAL : (gem || (d->mining_mode()==2 && ore));
                    if(des.bits.hidden || !matches) { ++notDiggable; continue; }
                }
                des.bits.dig = mapDig(kind);
                occ.bits.dig_auto=d->mining_mode()==1 && d->kind()==mir::DigKind::Dig;
                occ.bits.dig_marked=d->marker();
                if (auto* ev = priorityEvent(blk, true)) ev->priority[lx][ly] = prio;
            }
            blk->flags.bits.designated = true;
            ++applied;
            if(d->marker()) held.insert({x,y,z});
            hintBlock(x, y, z);
        }
    }
    }
    if(!held.empty()) restoreAndHoldJobs(*r,&held);
    g_stats.tilesVisited += visited;
    g_stats.tilesApplied += applied;
    const uint64_t skipped = notDiggable + noBlock + border;
    const char* reason = notDiggable ? "not diggable" : (border ? "map border" : "no map block");
    if (applied == 0) {
        if (d->kind() == mir::DigKind::Remove) return rejected(cmd.seq(), "no dig designation in the rect");
        return rejected(cmd.seq(), countMessage("tiles", 0, visited, skipped, reason));
    }
    return Result{cmd.seq(), mir::CommandStatus::Ok, countMessage("tiles", applied, visited, skipped, reason)};
}

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
    for(const auto& tile:path) {
        const auto [x,y,z]=tile.point;
        auto* block=Maps::getTileBlock(x,y,z);
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
    }
    if(!held.empty()) restoreAndHoldJobs(*r,&held);
    g_stats.tilesApplied+=path.size(); g_stats.tilesVisited+=path.size();
    return Result{cmd.seq(),mir::CommandStatus::Ok,std::to_string(path.size())+" track tiles"};
}

Result execSmooth(const mir::Command& cmd) {
    const mir::DesignateSmooth* d = cmd.payload_as_DesignateSmooth();
    if(d->kind()==mir::SmoothKind::Track) return execTrack(cmd);
    const mir::TileRect* r = d->rect();
    const auto removedJobs = d->kind()==mir::SmoothKind::Remove ? removePendingJobs(*r,true,d->max_z()) : std::set<df3d_pending_work::Tile>{};
    std::set<df3d_pending_work::Tile> held;
    uint64_t visited = 0, applied = 0, skipped = 0;
    const int32_t maxZ=d->max_z()==-1?r->z():d->max_z();
    for(int32_t z=r->z();z<=maxZ;++z) {
    for (int32_t y = r->y1(); y <= r->y2(); ++y) {
        for (int32_t x = r->x1(); x <= r->x2(); ++x) {
            ++visited;
            df::map_block* blk = Maps::getTileBlock(x, y, z);
            if (!blk) {
                ++skipped;
                continue;
            }
            const int lx = x & 15, ly = y & 15;
            df::tile_designation& des = blk->designation[lx][ly];
            if (d->kind() == mir::SmoothKind::Remove) {
                auto &occ=blk->occupancy[lx][ly];
                if (des.bits.smooth == 0 && !occ.bits.carve_track_north && !occ.bits.carve_track_south && !occ.bits.carve_track_east && !occ.bits.carve_track_west && !removedJobs.count({x,y,z})) continue;
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
                    ++skipped;
                    continue;
                }
                des.bits.smooth = d->kind() == mir::SmoothKind::Engrave ? 2 : 1;
                blk->occupancy[lx][ly].bits.dig_marked=d->marker();
                priorityEvent(blk,true)->priority[lx][ly]=int32_t(d->priority())*1000;
            }
            blk->flags.bits.designated = true;
            ++applied;
            if(d->marker()) held.insert({x,y,z});
            hintBlock(x, y, z);
        }
    }
    }
    if(!held.empty()) restoreAndHoldJobs(*r,&held);
    g_stats.tilesVisited += visited;
    g_stats.tilesApplied += applied;
    const char* reason = d->kind() == mir::SmoothKind::Engrave ? "not smoothed natural stone"
                                                               : "not rough natural stone";
    if (applied == 0) {
        if (d->kind() == mir::SmoothKind::Remove) return rejected(cmd.seq(), "no smooth designation in the rect");
        return rejected(cmd.seq(), countMessage("tiles", 0, visited, skipped, reason));
    }
    return Result{cmd.seq(), mir::CommandStatus::Ok, countMessage("tiles", applied, visited, skipped, reason)};
}

// Trees (Chop) or shrubs (Gather) whose designation tile lies in the rect.
Result execPlants(const mir::Command& cmd, const mir::TileRect* r, bool enable, bool trees, uint8_t priority, bool marker, int32_t maxZ) {
    std::set<df3d_pending_work::Tile> held;
    uint64_t candidates = 0, applied = 0, already = 0;
    for (df::plant* p : world->plants.all) {
        if (!p) continue;
        const bool isTree = p->tree_info != nullptr;
        const bool isShrub = ENUM_ATTR(plant_type, is_shrub, p->type);
        if (trees ? !isTree : !(isShrub && !isTree)) continue;
        const df::coord pos = Designations::getPlantDesignationTile(p);
        if (pos.z < r->z() || pos.z > (maxZ==-1?r->z():maxZ) || pos.x < r->x1() || pos.x > r->x2() || pos.y < r->y1() || pos.y > r->y2())
            continue;
        ++candidates;
        bool changed = enable ? Designations::markPlant(p) : Designations::unmarkPlant(p);
        if (enable && (changed || Designations::isPlantMarked(p))) {
            auto* blk=Maps::getTileBlock(pos);
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
    if(!held.empty()) restoreAndHoldJobs(*r,&held);
    g_stats.plantsMarked += applied;
    const char* what = trees ? "trees" : "shrubs";
    if (candidates == 0) return rejected(cmd.seq(), std::string("no ") + what + " in the rect");
    if (applied == 0) {
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
void reset() { g_stats = Stats(); }

Result execute(const mir::Command& cmd) {
    const auto t0 = Clock::now();
    Result res;
    if (!world || !Maps::IsValid()) {
        res = rejected(cmd.seq(), "no map loaded");
    } else {
        switch (cmd.payload_type()) {
        case mir::CommandPayload::DesignateDig: res = execDig(cmd); break;
        case mir::CommandPayload::DesignateSmooth: res = execSmooth(cmd); break;
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
    const double us = usSince(t0);
    g_stats.execUsLast = us;
    g_stats.execUsEma = g_stats.execUsEma == 0.0 ? us : g_stats.execUsEma + (us - g_stats.execUsEma) / 16.0;
    if (us > g_stats.execUsMax) g_stats.execUsMax = us;
    ++g_stats.executed;
    if (res.status == mir::CommandStatus::Ok) ++g_stats.ok;
    else if (res.status == mir::CommandStatus::Rejected) ++g_stats.rejected;
    else ++g_stats.unknown;
    g_stats.lastMessage = res.message;
    return res;
}

}  // namespace df3d_commands
