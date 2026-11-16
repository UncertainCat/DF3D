// Keep <windows.h> (needed for CreateFileMapping) from polluting everything.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "PluginManager.h"
#include "df/plant_raw.h"
#include "construction_site_native.h"
#include "tile_description_native.h"
#include "stockpile_native.h"
#include "bed_appearance_native.h"
#include "contact_capture.h"
#include "room_discovery_native.h"
#include "zone_native.h"
#include "df/building_civzonest.h"
#include "room_mutation_native.h"
#include "paint_water_native.h"
#include "location_catalog_native.h"
#include "location_details_native.h"
#include "df/entity_position.h"
#include "location_staff_native.h"
#include "location_staff_page.h"
#include "jsoncpp-ex.h"

#include "modules/Maps.h"
#include "modules/Materials.h"
#include "modules/Units.h"
#include "modules/EventManager.h"
#include <deque>
#include "modules/World.h"

#include "df/caste_raw.h"
#include "df/creature_raw.h"
#include "df/item.h"
#include "df/proj_itemst.h"
#include "df/proj_list_link.h"
#include "df/projectile_type.h"
#include "ground_spatters.h"
#include "simulation_events.h"
#include "df/item_type.h"
#include "df/itemdef_toolst.h"
#include "df/job.h"
#include "df/job_type.h"
#include "df/material.h"
#include "unit_status.h"
#include "unit_status_rules.h"
#include "df/activity_event_performancest.h"
#include "df/activity_event_make_believest.h"
#include "df/soldier_mood_type.h"
#include "df/squad.h"
#include "df/unit_soul.h"
#include "df/misc_trait_type.h"
#include "df/activity_entry.h"
#include "df/army_controller.h"
#include "df/army_controller_goal_campst.h"
#include "df/body_part_raw.h"
#include "df/caste_body_info.h"
#include "df/performance_rolest.h"
#include "df/performance_participant_type.h"
#include "df/mood_type.h"
#include "df/unit.h"
#include "df/unit_action.h"
#include "df/unit_action_type.h"
#include "df/world.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <charconv>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#include "farm_native.h"
#include "door_native.h"
#include "pending_building_native.h"
#include "pending_building_duration_native.h"
#include "building_item_native.h"
#include "funerary_native.h"
#include "machinery_native.h"
#include "well_native.h"
#include "depot_native.h"
#include "trade_entry_native.h"
#include "trade_goods_native.h"
#include "trade_projection_native.h"
#include "trade_row_values_native.h"
#include "trade_value_totals_native.h"
#include "trade_capacity_native.h"
#include "trade_appraisal_native.h"
#include "trade_session_native.h"
#include "trade_catalog_native.h"
#include "trade_owner_native.h"
#include "trade_negotiation_native.h"
#include "depot_goods_native.h"
#include "depot_selection_native.h"
#include "depot_goods_read.h"
#include "building_links_native.h"
#include "lever_native.h"
#include "creature_office_native.h"
#include "creature_header_native.h"
#include "creature_quote_native.h"
#include "creature_follow_native.h"
#include "tile_selection_native.h"
#include "creature_expel_action_native.h"
#include "creature_expel_preview_native.h"
#include "creature_health_native.h"
#include "creature_health_pages_native.h"
#include "creature_skills_native.h"
#include "skills_caption_native.h"
#include "creature_knowledge_native.h"
#include "knowledge_detail_native.h"
#include "engraving_description_native.h"
#include "workshop_catalog_native.h"
#include "workshop_workers_native.h"
#include "workshop_orders_native.h"
#include "work_order_catalog_native.h"
#include "work_order_conditions_native.h"
#include "work_order_details_native.h"
#include "job_settings_native.h"
#include "job_art_native.h"
#include "work_order_dye_native.h"
#include "workshop_dye_native.h"
#include "work_order_art_native.h"
#include "engraving_art_native.h"
#include "df/job_item.h"
#include "musical_detail_native.h"
#include "dance_detail_native.h"
#include "written_detail_native.h"
#include "creature_items_native.h"
#include "item_owner_native.h"
#include "residents_order_native.h"
#include "residents_activity_native.h"
#include "tasks_native.h"
#include "places_native.h"
#include "objects_native.h"
#include "justice_native.h"
#include "justice_guard_native.h"
#include "justice_convicts_native.h"
#include "justice_intelligence_native.h"
#include "justice_intelligence_actors_native.h"
#include "justice_intelligence_graph_native.h"
#include "justice_action_native.h"
#include "justice_presentation_native.h"
#include <sstream>
#include "justice_witness_native.h"
#include "nobles_native.h"
#include "nobles_draft_native.h"
#include "nobles_symbols_native.h"
#include "nobles_symbols_mutation_native.h"
#include "nobles_symbol_name_native.h"
#include "nobles_symbol_display_native.h"
#include "places_action_native.h"
#include "tasks_action_native.h"
#include "residents_activity_description_native.h"
#include "residents_query_native.h"
#include "work_detail_query_native.h"
#include "work_detail_row_native.h"
#include "work_detail_settings_native.h"
#include "standing_orders_native.h"
#include "chores_native.h"
#include "stone_use_native.h"
#include "item_uses_native.h"
#include "stocks_native.h"
#include "kitchen_native.h"
#include "hunter_ammunition_native.h"
#include "hunter_ammunition_captions_native.h"
#include "residents_row_native.h"
#include "residents_specialization_native.h"
#include "modules/Buildings.h"
#endif

// DF3D mirror layer (generated header comes from schema/mirror.fbs via flatc;
// see bridge/plugin/CMakeLists.txt).
#include "appearance_util.h"
#include "command_util.h"
#include "fixture_io.h"
#include "glyph_util.h"
#include "mirror_generated.h"
#include "shm_layout.h"
#include "publication_clock.h"
#include "session.h"
#include "management.h"
#include "terrain_publisher.h"
#include "validate.h"

#include "appearance.h"
#include "appearance_eviction.h"
#include "commands.h"
#include "entities.h"
#include "glyph_cursor.h"
#include "item_visibility_policy.h"
#include "scan_schedule.h"

using std::string;
using std::vector;
using namespace DFHack;

DFHACK_PLUGIN("df3d");
DFHACK_PLUGIN_IS_ENABLED(is_enabled);

REQUIRE_GLOBAL(world);
REQUIRE_GLOBAL(cur_year_tick);

namespace {

namespace mir = df3d::mirror;
namespace shm = df3d::shm;

// ---- unit appearance state ----

namespace app = df3d_appearance;
namespace ent = df3d_entities;
namespace cmdx = df3d_commands;

struct AppEntry {
    uint32_t fingerprint = 0;   // app::fingerprint at last resolve
    uint32_t hash = 0;          // schema version hash of `layers`
    vector<app::Layer> layers;  // latest resolved stack
    bool resolvedOnce = false;
    bool dirty = true;          // changed since last publication
    int32_t lastSeenFrame = 0;
    uint32_t slot = 0;          // rotation slot (assigned on first sight)
};

struct AppearanceState {
    std::unordered_map<int32_t, AppEntry> units;
    // Round-robin of tracked ids for bounded eviction of units no longer
    // walked (appearance_eviction.h: kTtlFrames, kMaxPerCall per update).
    df3d_appearance_eviction::Ring evictionRing;
    uint64_t evicted = 0;
    uint32_t nextSlot = 0;
    uint32_t resolvePeriod = 256;  // frames between forced re-resolves per unit
    uint32_t refreshPeriod = 128;  // frames between forced re-sends per unit
    // palette pointer -> install-relative path (stable for the session)
    std::unordered_map<const void*, string> palettePaths;
    // per-snapshot scratch
    vector<flatbuffers::Offset<mir::UnitAppearance>> appOffsets;
    vector<mir::AppearanceLayer> layerBuf;
    std::unordered_map<const void*, uint16_t> pageIndex;
    std::unordered_map<const void*, uint16_t> paletteIndex;
    vector<flatbuffers::Offset<flatbuffers::String>> pageOffsets;
    vector<flatbuffers::Offset<flatbuffers::String>> paletteOffsets;
    // counters (df3d status)
    uint64_t resolves = 0, changes = 0, sent = 0, sentLayers = 0;
    size_t lastSent = 0;
    double resolveUsLast = 0, resolveUsEma = 0, resolveUsMax = 0;
};

// Classic glyph tables: what has been published so far.
struct GlyphState {
    size_t materialsSent = 0;   // grid material ids below this have a glyph row out
    uint64_t fullsBuilt = 0, deltasBuilt = 0, rowsSent = 0;
    size_t lastFullBytes = 0, lastRows = 0;
    // per-snapshot scratch
    vector<flatbuffers::Offset<mir::CreatureGlyph>> creatures;
    vector<flatbuffers::Offset<mir::MaterialGlyph>> materials;
    vector<flatbuffers::Offset<mir::ItemDefGlyph>> itemdefs;
};

// All mutable plugin state. Everything here is touched either from
// plugin_onupdate (DF simulation thread, core lock held) or from the console
// command handler (which runs with the core suspended), so accesses are
// already serialized by DFHack; the mutex is belt-and-braces for the
// recording file specifically.
struct BridgeState {
    // shared memory region (created on SC_MAP_LOADED)
#ifdef _WIN32
    HANDLE mapping = nullptr;
#endif
    shm::RegionHeader* region = nullptr;

    bool mapLoaded = false;
    // Session channel (load/save lifecycle): another bridge process may own
    // it. Its absence never blocks the mirror; warned once per map load.
    bool sessionAvailable = false;
    bool warnedSessionUnavailable = false;

    // publish bookkeeping
    bool havePublished = false;
    int32_t lastFrame = 0;            // df::global::world->frame_counter at last publish
    uint64_t lastTick = 0;            // tick stamped on the last published snapshot
    size_t lastUnitCount = 0;         // units in the last published snapshot
    size_t lastSnapshotBytes = 0;
    uint64_t snapshotsPublished = 0;
    uint64_t commandsDrained = 0;
    uint64_t commandsSliced = 0;  // commands that needed more than one update

    // per-update timing (microseconds): whole onupdate, terrain scan part,
    // snapshot build+publish part. EMA alpha 1/64; max resets on status.
    double updateUsLast = 0, updateUsEma = 0, updateUsMax = 0;
    double scanUsLast = 0, scanUsEma = 0, scanUsMax = 0;
    double publishUsLast = 0, publishUsEma = 0, publishUsMax = 0;
    uint64_t updates = 0;

    // Entity Full requests: the request counter value last served
    // and whether the next snapshot must be a Full regardless (map load).
    uint64_t entityFullServed = 0;
    bool entityFullPending = true;
    // Newly executed commands need publication even when simulation time is
    // stopped; receipt repeats must not keep an idle paused bridge publishing.
    // Failed writes leave the request outstanding until a successful publication.
    bool commandPublicationPending = false;
    df3d_bridge::PauseTransitionTracker pauseTransitions;
    size_t lastEntityBytes = 0;

    // Command results: queued at the drain, published in the
    // following snapshots for `remaining` publishes each.
    struct PendingResult {
        uint64_t seq = 0;
        mir::CommandStatus status = mir::CommandStatus::Ok;
        string message;
        uint32_t remaining = mir::kCommandResultRepeatFrames;
    };
    vector<PendingResult> results;
    vector<flatbuffers::Offset<mir::CommandResult>> resultOffsets;
    uint64_t resultsQueued = 0, resultsSent = 0;
    size_t lastResultsSent = 0;

    // fixture recording (df3d record start/stop)
    std::mutex recordMutex;
    std::ofstream recordFile;
    string recordPath;
    uint64_t recordCount = 0;

    // once-per-kind log throttles (reset on map load)
    bool warnedCorruptCommand = false;
    bool warnedUnknownCommand = false;
    bool warnedOversizeSnapshot = false;
    bool warnedUnresolvedRace = false;

    // hot-path reuse: builder + scratch vectors survive across frames so the
    // per-frame cost is serialization only, not allocation
    flatbuffers::FlatBufferBuilder fbb{1u << 20};
    vector<flatbuffers::Offset<mir::UnitState>> unitOffsets;
    vector<uint8_t> cmdBuf = vector<uint8_t>(64u * 1024);

    TerrainPublisher terrain;
    AppearanceState appearance;
    GlyphState glyphs;
};

BridgeState state;

// Confirmed outcomes, collected on DF's simulation thread. Repetition in
// snapshots tolerates skipped mirror slots without re-triggering consumers.
struct CombatObservation {
    uint64_t id, tick;
    mir::CombatEventKind kind;
    int32_t attacker, victim, wound;
    mir::TilePos pos;
    int32_t report=-1, sourceAction=-1;
    df3d_events::ItemSource weapon;
};
std::deque<CombatObservation> combatEvents;
uint64_t nextCombatEventId = 1;
void observeCombat(mir::CombatEventKind kind, int32_t attacker, int32_t victim, int32_t wound, int32_t report=-1) {
    if (!is_enabled || !state.mapLoaded || !world) return;
    auto* u = df::unit::find(victim);
    if (!u || u->pos.x < 0 || u->pos.y < 0 || u->pos.z < 0 ||
        u->pos.x >= world->map.x_count || u->pos.y >= world->map.y_count || u->pos.z >= world->map.z_count) return;
    const auto tick = static_cast<uint64_t>(world->frame_counter);
    while (!combatEvents.empty() && tick > combatEvents.front().tick && tick-combatEvents.front().tick > 600)
        combatEvents.pop_front();
    for (const auto& e : combatEvents)
        if (e.kind == kind && e.victim == victim && e.wound == wound) return;
    combatEvents.push_back({nextCombatEventId++, tick, kind, attacker, victim, wound,
                           mir::TilePos(u->pos.x,u->pos.y,u->pos.z)});
    auto& observation=combatEvents.back();
    observation.report=report;
    if(kind==mir::CombatEventKind::Wound) {
        auto source=df3d_events::attackSource(df::unit::find(attacker),victim);
        observation.sourceAction=source.actionId; observation.weapon=std::move(source.weapon);
    }
    if (combatEvents.size() > 256) combatEvents.pop_front();
}
void combatAttack(color_ostream&, void* payload) {
    const auto& e = *static_cast<EventManager::UnitAttackData*>(payload);
    if (e.wound >= 0) observeCombat(mir::CombatEventKind::Wound,e.attacker,e.defender,e.wound,e.report_id);
    else if (auto* u = df::unit::find(e.defender); u && Units::isKilled(u))
        observeCombat(mir::CombatEventKind::Death,e.attacker,e.defender,-1,e.report_id);
}
void combatDeath(color_ostream&, void* payload) {
    observeCombat(mir::CombatEventKind::Death,-1,static_cast<int32_t>(reinterpret_cast<intptr_t>(payload)),-1);
}
void nativeReport(color_ostream&, void* payload) {
    if(is_enabled && state.mapLoaded && world)
        df3d_events::observeReport(static_cast<int32_t>(reinterpret_cast<intptr_t>(payload)));
}
auto buildCombatEvents(flatbuffers::FlatBufferBuilder& fbb, uint64_t tick) {
    while (!combatEvents.empty() && tick > combatEvents.front().tick && tick-combatEvents.front().tick > 600)
        combatEvents.pop_front();
    std::vector<flatbuffers::Offset<mir::CombatEvent>> offsets;
    offsets.reserve(combatEvents.size());
    for (const auto& e : combatEvents) if (e.tick <= tick) {
        const auto weapon=df3d_events::buildItem(fbb,e.weapon);
        offsets.push_back(mir::CreateCombatEvent(fbb,e.id,e.tick,e.kind,e.attacker,e.victim,e.wound,&e.pos,e.report,e.sourceAction,weapon));
    }
    return fbb.CreateVector(offsets);
}

struct ProjectileObservation {
    uint64_t sequence=0, id=0, tick=0;
    int32_t item=-1, firer=-1;
    mir::TilePos pos, previous, origin, target;
    bool active=true, first=false;
    df3d_events::ItemSource ammunition,launcher;
};
std::deque<ProjectileObservation> projectileSamples;
std::map<int32_t,ProjectileObservation> activeProjectiles;
uint64_t nextProjectileSequence=1, sampledProjectileTick=UINT64_MAX;
void resetProjectiles() {
    projectileSamples.clear(); activeProjectiles.clear();
    nextProjectileSequence=1; sampledProjectileTick=UINT64_MAX;
}
auto buildProjectileSamples(flatbuffers::FlatBufferBuilder& fbb, uint64_t tick) {
    if (world && sampledProjectileTick!=tick) {
        sampledProjectileTick=tick;
        std::map<int32_t,ProjectileObservation> next;
        unsigned visited=0;
        for (auto* link=world->projectiles.all.next;link && visited++<4096;link=link->next) {
            auto* base=link->item;
            if (!base || base->id<0 || base->getType()!=df::projectile_type::Item || base->flags.bits.to_be_deleted) continue;
            auto* projectile=static_cast<df::proj_itemst*>(base);
            // The initial presentation supports real ammunition shafts only.
            // Thrown bodies and stones must not acquire an invented bolt shape.
            if (!projectile->item || projectile->item->getType()!=df::item_type::AMMO) continue;
            const auto p=projectile->cur_pos;
            if (p.x<0 || p.y<0 || p.z<0 || p.x>=world->map.x_count || p.y>=world->map.y_count || p.z>=world->map.z_count) continue;
            auto pos=[](const df::coord& value) { return mir::TilePos(value.x,value.y,value.z); };
            ProjectileObservation sample;
            sample.sequence=nextProjectileSequence++;sample.id=uint64_t(projectile->id);sample.tick=tick;
            sample.item=projectile->item->id;sample.firer=projectile->firer?projectile->firer->id:-1;
            sample.pos=pos(p);sample.previous=pos(projectile->prev_pos);sample.origin=pos(projectile->origin_pos);sample.target=pos(projectile->target_pos);
            sample.first=activeProjectiles.count(projectile->id)==0;
            if(sample.first) {
                sample.ammunition=df3d_events::itemSource(projectile->item);
                sample.launcher=df3d_events::itemSource(df::item::find(projectile->bow_id));
            } else {
                const auto& previous=activeProjectiles.at(projectile->id);
                sample.ammunition=previous.ammunition;sample.launcher=previous.launcher;
            }
            next.emplace(projectile->id,sample);projectileSamples.push_back(sample);
        }
        for (const auto& [id,old] : activeProjectiles) if (!next.count(id)) {
            auto end=old;end.sequence=nextProjectileSequence++;end.tick=tick;end.active=false;end.first=false;
            projectileSamples.push_back(end);
        }
        activeProjectiles=std::move(next);
    }
    while (!projectileSamples.empty() && (projectileSamples.size()>512 ||
           (tick>projectileSamples.front().tick && tick-projectileSamples.front().tick>120))) projectileSamples.pop_front();
    std::vector<flatbuffers::Offset<mir::ProjectileSample>> samples;
    samples.reserve(projectileSamples.size());
    for (const auto& p : projectileSamples) if (p.tick<=tick) {
        auto ammunition=df3d_events::buildItem(fbb,p.ammunition),launcher=df3d_events::buildItem(fbb,p.launcher);
        samples.push_back(mir::CreateProjectileSample(fbb,p.sequence,p.id,p.tick,p.item,p.firer,&p.pos,&p.previous,&p.origin,&p.target,p.active,p.first,ammunition,launcher));
    }
    return fbb.CreateVector(samples);
}



using Clock = std::chrono::steady_clock;

double usSince(Clock::time_point t0) {
    return std::chrono::duration<double, std::micro>(Clock::now() - t0).count();
}

void track(double us, double& last, double& ema, double& mx) {
    last = us;
    ema = ema == 0.0 ? us : ema + (us - ema) / 64.0;
    if (us > mx) mx = us;
}

// ---- shared memory region lifecycle ----

void destroyTerrain() { state.terrain.reset(state.region); }

void destroyRegion(color_ostream& out) {
    destroyTerrain();
#ifdef _WIN32
    if (state.region) {
        UnmapViewOfFile(state.region);
        state.region = nullptr;
    }
    if (state.mapping) {
        CloseHandle(state.mapping);
        state.mapping = nullptr;
    }
#endif
    (void)out;
}

bool createRegion(color_ostream& out) {
#ifdef _WIN32
    if (state.region)
        return true;  // already mapped (e.g. map reload within one world)

    const size_t size = shm::regionSize(shm::kDefaultSnapshotCapacity,
                                        shm::kDefaultCommandCapacity, 64u * 1024 * 1024);
    // If a client raced us and the named mapping already exists, we get a
    // handle to the existing object (ERROR_ALREADY_EXISTS); initRegion below
    // re-initializes it either way, which is the correct fresh-session state.
    HANDLE mapping = CreateFileMappingA(
        INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
        static_cast<DWORD>(static_cast<uint64_t>(size) >> 32),
        static_cast<DWORD>(size & 0xFFFFFFFFu),
        shm::kDefaultRegionName);
    if (!mapping) {
        out.printerr("df3d: CreateFileMapping failed (error {})\n", GetLastError());
        return false;
    }
    void* view = MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, size);
    if (!view) {
        out.printerr("df3d: MapViewOfFile failed (error {})\n", GetLastError());
        CloseHandle(mapping);
        return false;
    }
    state.mapping = mapping;
    state.region = static_cast<shm::RegionHeader*>(view);
    shm::initRegion(state.region, static_cast<uint32_t>(mir::SchemaVersion::Current),
                    shm::kDefaultSnapshotCapacity, shm::kDefaultCommandCapacity, 64u * 1024 * 1024);
    out.print("df3d: shared memory region '{}' created ({} bytes)\n",
              shm::kDefaultRegionName, size);
    return true;
#else
    // The shm transport is Windows-only for now (shm_layout.h names a
    // Local\ kernel object); a POSIX shm_open path is future work.
    out.printerr("df3d: shared memory transport not implemented on this platform\n");
    return false;
#endif
}

// ---- fixture recording ----

void stopRecording(color_ostream& out, bool report) {
    std::lock_guard<std::mutex> lock(state.recordMutex);
    if (!state.recordFile.is_open())
        return;
    state.recordFile.flush();
    state.recordFile.close();
    state.recordFile.clear();  // a mid-recording write error must not poison the next start
    if (report)
        out.print("df3d: recording stopped; {} snapshot(s) written to {}\n",
                  state.recordCount, state.recordPath);
    state.recordPath.clear();
}

// ---- job mapping ----
//
// Coarse df::job_type -> df3d::mirror::JobKind mapping. Deliberately small;
// grows with schema coverage. Fight/Flee are not derivable from job_type
// (combat is not a job) and are left for a later slice. Units without a
// current job are Idle.
mir::JobKind mapJob(const df::job* j) {
    using mir::JobKind;
    if (!j)
        return JobKind::Idle;
    const df::job_type jt = j->job_type;
    switch (jt) {
    case df::job_type::ConstructBuilding:
        return JobKind::ConstructBuilding;
    case df::job_type::Sleep:
        return JobKind::Sleep;
    case df::job_type::Eat:
        return JobKind::Eat;
    case df::job_type::Drink:
    case df::job_type::DrinkItem:
        return JobKind::Drink;
    default:
        break;
    }
    switch (ENUM_ATTR(job_type, type, jt)) {
    case df::job_type_class::Digging:
        return JobKind::Mine;
    case df::job_type_class::Hauling:
        return JobKind::HaulItem;
    default:
        return JobKind::Idle;
    }
}

// Material callbacks shared by entity and terrain snapshot serialization.
uint16_t pairMaterial(int16_t type,int32_t index) { return state.terrain.pairMaterial(type,index); }
uint16_t localMaterial(flatbuffers::FlatBufferBuilder& b,uint16_t id) { return state.terrain.localMaterial(b,id); }
void beginSnapshotMaterials() { state.terrain.beginSnapshotMaterials(); }
auto finishSnapshotMaterials(flatbuffers::FlatBufferBuilder& b) { return state.terrain.finishSnapshotMaterials(b); }

// ---- unit appearance resolution ----

const string& palettePath(const df::palette_pagest* pal) {
    AppearanceState& a = state.appearance;
    auto it = a.palettePaths.find(pal);
    if (it != a.palettePaths.end())
        return it->second;
    return a.palettePaths.emplace(pal, app::paletteInstallPath(pal)).first->second;
}

uint32_t hashStack(const vector<app::Layer>& layers) {
    uint32_t h = mir::appearanceHashBegin();
    for (const app::Layer& l : layers) {
        const string& page = app::pageToken(l.page);
        const string* pal = l.palette ? &palettePath(l.palette) : nullptr;
        h = mir::appearanceHashLayer(h, page.data(), page.size(), l.tileX, l.tileY, l.cellsX, l.cellsY,
                                     pal ? pal->data() : "", pal ? pal->size() : 0, l.row, l.keyRow,
                                     l.offX, l.offY);
    }
    return h;
}

bool sameStack(const vector<app::Layer>& a, const vector<app::Layer>& b) {
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i)
        if (!a[i].sameReference(b[i])) return false;
    return true;
}

// Brings the unit's appearance entry up to date (amortized) and returns
// it. `force` re-resolves regardless of fingerprint/rotation.
AppEntry& updateAppearance(df::unit* u, int32_t frame, bool force) {
    AppearanceState& a = state.appearance;
    auto [it, inserted] = a.units.try_emplace(u->id);
    AppEntry& e = it->second;
    if (inserted) {
        e.slot = a.nextSlot++;
        a.evictionRing.push_back(u->id);
    }
    e.lastSeenFrame = frame;
    const uint32_t fp = app::fingerprint(u);
    const bool rotation = a.resolvePeriod > 0 &&
                          ((static_cast<uint32_t>(frame) + e.slot) % a.resolvePeriod) == 0;
    if (!force && e.resolvedOnce && fp == e.fingerprint && !rotation)
        return e;
    app::Result r;
    app::resolve(u, r);
    ++a.resolves;
    e.fingerprint = fp;
    if (!e.resolvedOnce || !sameStack(e.layers, r.layers)) {
        e.layers = std::move(r.layers);
        e.hash = hashStack(e.layers);
        e.dirty = true;
        if (e.resolvedOnce) ++a.changes;
    }
    e.resolvedOnce = true;
    return e;
}

// Per-snapshot page / palette tables, shared by unit and corpse layers:
// begin before serializing any layer of the snapshot, encode
// every layer through encodeLayer (interns the page token and palette
// path), finish once to create the two string vectors.
void beginAppearanceTables() {
    AppearanceState& a = state.appearance;
    a.pageIndex.clear();
    a.paletteIndex.clear();
    a.pageOffsets.clear();
    a.paletteOffsets.clear();
}

mir::AppearanceLayer encodeLayer(flatbuffers::FlatBufferBuilder& fbb, const app::Layer& l) {
    AppearanceState& a = state.appearance;
    uint16_t page;
    auto pit = a.pageIndex.find(l.page);
    if (pit == a.pageIndex.end()) {
        page = static_cast<uint16_t>(a.pageOffsets.size());
        a.pageOffsets.push_back(fbb.CreateString(app::pageToken(l.page)));
        a.pageIndex.emplace(l.page, page);
    } else {
        page = pit->second;
    }
    uint16_t pal = mir::kNoPalette;
    int16_t row = mir::kNoPaletteRow, key = mir::kNoPaletteRow;
    if (l.palette) {
        auto qit = a.paletteIndex.find(l.palette);
        if (qit == a.paletteIndex.end()) {
            pal = static_cast<uint16_t>(a.paletteOffsets.size());
            a.paletteOffsets.push_back(fbb.CreateString(palettePath(l.palette)));
            a.paletteIndex.emplace(l.palette, pal);
        } else {
            pal = qit->second;
        }
        row = l.row < 0 ? 0 : l.row;
        key = l.keyRow < 0 ? 0 : l.keyRow;
    }
    return mir::AppearanceLayer(page, l.tileX, l.tileY, l.cellsX, l.cellsY, pal, row, key, l.offX, l.offY);
}

void finishAppearanceTables(flatbuffers::FlatBufferBuilder& fbb,
                            flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<flatbuffers::String>>>& pages,
                            flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<flatbuffers::String>>>& palettes) {
    AppearanceState& a = state.appearance;
    pages = fbb.CreateVector(a.pageOffsets);
    palettes = fbb.CreateVector(a.paletteOffsets);
}

// Serializes the appearances of the given (unit, entry) pairs into the
// current snapshot's tables (beginAppearanceTables first).
flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mir::UnitAppearance>>>
buildAppearances(flatbuffers::FlatBufferBuilder& fbb, const vector<std::pair<int32_t, AppEntry*>>& send) {
    AppearanceState& a = state.appearance;
    a.appOffsets.clear();
    a.appOffsets.reserve(send.size());
    for (const auto& [id, e] : send) {
        a.layerBuf.clear();
        for (const app::Layer& l : e->layers) a.layerBuf.push_back(encodeLayer(fbb, l));
        auto layersVec = fbb.CreateVectorOfStructs(a.layerBuf);
        a.appOffsets.push_back(mir::CreateUnitAppearance(fbb, static_cast<uint64_t>(id), e->hash, layersVec));
        a.sentLayers += e->layers.size();
    }
    a.sent += send.size();
    a.lastSent = send.size();
    return fbb.CreateVector(a.appOffsets);
}

// ---- classic glyph tables ----

uint8_t glyphColor(int16_t v, int16_t hi) {
    return static_cast<uint8_t>(v < 0 ? 0 : (v > hi ? hi : v));
}

mir::Glyph glyphOf(uint8_t tile, const std::array<int16_t, 3>& color) {
    return mir::Glyph(tile, glyphColor(color[0], mir::kMaxGlyphColor), glyphColor(color[1], mir::kMaxGlyphColor),
                      glyphColor(color[2], 1));
}

struct GlyphBuilt {
    mir::ChangeScope scope = mir::ChangeScope::None;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mir::CreatureGlyph>>> creatures;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mir::MaterialGlyph>>> materials;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mir::ItemDefGlyph>>> itemdefs;
    size_t rows = 0;
    size_t materialsBuiltTo = 0;  // grid materials below this have a row in this build
};

// A material glyph row for one grid material string; false when the token
// does not resolve to a DF material (nothing is published for it).
bool materialGlyphRow(flatbuffers::FlatBufferBuilder& fbb, const char* token, uint16_t len,
                      flatbuffers::Offset<mir::MaterialGlyph>& out) {
    MaterialInfo mi;
    if (!mi.find(string(token, len)) || !mi.material) return false;
    const df::material* m = mi.material;
    const mir::Glyph build = glyphOf(m->tile, m->build_color);
    const mir::Glyph tileColor = glyphOf(m->tile, m->tile_color);
    auto name = fbb.CreateString(token, len);
    out = mir::CreateMaterialGlyph(fbb, name, m->tile, m->item_symbol, glyphColor(m->basic_color[0], mir::kMaxGlyphColor),
                                   glyphColor(m->basic_color[1], 1), &build, &tileColor);
    return true;
}

// Serializes the glyph tables: with `full` every creature raw, every grid
// material and every tool itemdef; else the grid materials interned
// since the last acknowledged publication (scope None when there are none).
// The published-materials mark advances only once the ring snapshot carrying
// the rows is published (glyph_cursor.h): a failed attempt is retried with
// the same rows, and the recording Full never moves it.
void buildGlyphs(flatbuffers::FlatBufferBuilder& fbb, bool full, GlyphBuilt& out) {
    GlyphState& g = state.glyphs;
    auto& t = state.terrain;
    out = GlyphBuilt();
    g.creatures.clear();
    g.materials.clear();
    g.itemdefs.clear();
    const size_t matCount = t.materialTokenCount();
    if (full) {
        for (const df::creature_raw* raw : world->raws.creatures.all) {
            if (!raw || raw->creature_id.empty()) continue;
            const mir::Glyph glyph = glyphOf(raw->creature_tile, raw->color);
            const uint8_t soldier = raw->creature_soldier_tile ? raw->creature_soldier_tile : raw->creature_tile;
            auto name = fbb.CreateString(raw->creature_id);
            g.creatures.push_back(mir::CreateCreatureGlyph(fbb, name, &glyph, soldier));
        }
        for (const df::itemdef_toolst* def : world->raws.itemdefs.tools) {
            if (!def || def->id.empty()) continue;
            auto name = fbb.CreateString(def->id);
            g.itemdefs.push_back(mir::CreateItemDefGlyph(fbb, mir::ItemKind::Tool, name, def->tile));
        }
    }
    const auto range = df3d_glyph_cursor::rowsToBuild(g.materialsSent, matCount, full);
    for (size_t i = range.from; i < range.to; ++i) {
        flatbuffers::Offset<mir::MaterialGlyph> row;
        const auto token = t.materialToken(i);
        if (materialGlyphRow(fbb, token.data(), static_cast<uint16_t>(token.size()), row)) g.materials.push_back(row);
    }
    out.materialsBuiltTo = range.to;
    out.rows = g.creatures.size() + g.materials.size() + g.itemdefs.size();
    if (!full && out.rows == 0) return;
    out.scope = full ? mir::ChangeScope::Full : mir::ChangeScope::Delta;
    out.creatures = fbb.CreateVector(g.creatures);
    out.materials = fbb.CreateVector(g.materials);
    out.itemdefs = fbb.CreateVector(g.itemdefs);
    if (full) ++g.fullsBuilt;
    else ++g.deltasBuilt;
    g.rowsSent += out.rows;
    g.lastRows = out.rows;
}

void resetAppearances() {
    AppearanceState& a = state.appearance;
    a.units.clear();
    a.evictionRing.clear();
    a.nextSlot = 0;
    a.palettePaths.clear();
    app::reset();
    state.glyphs.materialsSent = 0;
}

// The entities module's appearance hooks: palette paths and the
// per-snapshot layer encoder above.
const string& palettePathHook(const df::palette_pagest* pal) { return palettePath(pal); }
mir::AppearanceLayer encodeLayerHook(flatbuffers::FlatBufferBuilder& fbb, const app::Layer& l) {
    return encodeLayer(fbb, l);
}

// ---- snapshot build + publish ----

uint64_t wallClockUnixMs() {
    using namespace std::chrono;
    return static_cast<uint64_t>(
        duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count());
}

// Direct semantic state only. Social attendance is not a speaking/performing
// signal: require an active role belonging to this unit, excluding spectators.
using PerformanceStatuses = std::unordered_map<const df::activity_event*,
    std::unordered_map<int32_t, uint64_t>>;
uint64_t unitStatusFlags(df::unit* unit, PerformanceStatuses& performances) {
    namespace st = df3d::unit_status;
    uint64_t flags = DFHack::Units::isBaby(unit) ? st::Baby : 0;
    const auto* job = unit->job.current_job;
    // Native fortress selector: unconscious Sleep/Rest jobs, or an
    // unalarmed army camp. A dwarf merely walking to bed is not sleeping.
    const auto* army = unit->enemy.army_controller;
    const bool campSleep = army && army->goal == df::army_controller_goal_type::CAMP &&
        army->data.goal_camp && !army->data.goal_camp->camp_flag.bits.ALARM_INTRUDER;
    const bool sleeping = unit->counters.unconscious > 0 &&
        ((job && (job->job_type == df::job_type::Sleep || job->job_type == df::job_type::Rest)) || campSleep);
    if (sleeping) flags |= st::Sleeping;
    if (unit->counters.webbed >= 10) flags |= st::Webbed;
    if (unit->counters.stunned > 0 || unit->counters.dizziness > 0) flags |= st::Stunned;
    if (!sleeping && unit->counters.unconscious > 0) flags |= st::Unconscious;
    if (unit->counters2.paralysis >= 100) flags |= st::Paralyzed;
    if (unit->counters.nausea > 0) flags |= st::Nausea;
    if (unit->counters.winded > 0 && !unit->flags1.bits.drowning) flags |= st::Winded;
    if (unit->counters2.fever > 0) flags |= st::Fevered;
    if (unit->flags3.bits.adv_yield) flags |= st::Yielding;
    if (unit->flags1.bits.projectile) flags |= st::Projectile;
    if (unit->flags1.bits.on_ground) flags |= st::Grounded;
    if (!unit->status.wrestle_items.empty()) flags |= st::Wrestling;
    if (unit->job.climb_hold.x != -30000 || unit->job.hold_itid != -1) flags |= st::Climbing;
    if (Units::getMiscTrait(unit, df::misc_trait_type::Migrant)) flags |= st::Migrant;
    // Fortress atlas selector 53.16, RVA 0x269834: this is a stuck-path
    // warning, not every idle unit. Preserve the original spatial exclusions.
    const bool crazed = !unit->uwss_remove_caste_flag.bits.CRAZED &&
        (unit->uwss_add_caste_flag.bits.CRAZED || unit->enemy.caste_flags.is_set(df::caste_raw_flags::CRAZED));
    const bool fortControlled = Units::isFortControlled(unit) && !crazed &&
        (unit->flags1.bits.tame || unit->civ_id != -1);
    const bool canLearn = !unit->uwss_remove_caste_flag.bits.CAN_LEARN &&
        (unit->uwss_add_caste_flag.bits.CAN_LEARN || unit->enemy.caste_flags.is_set(df::caste_raw_flags::CAN_LEARN));
    if (fortControlled && !unit->enemy.undead && canLearn && !unit->job.hunt_target &&
        unit->path.path.x.empty() && unit->path.dest.x != -30000 &&
        (std::abs(int(unit->pos.x)-unit->idle_area.x)>3 || std::abs(int(unit->pos.y)-unit->idle_area.y)>3) &&
        (std::abs(int(unit->pos.x)-unit->path.dest.x)>1 || std::abs(int(unit->pos.y)-unit->path.dest.y)>1) &&
        !unit->flags3.bits.exit_vehicle1 && !unit->flags3.bits.floundering) {
        flags |= job ? st::NoDestination : st::NoJob;
    }
    if (!unit->flags3.bits.ghostly) {
        const auto& limbs = unit->status2;
        bool criticalOrganLoss = unit->flags2.bits.gutted;
        const auto* plan = unit->body.body_plan;
        if (!criticalOrganLoss && plan) {
            const auto& parts = unit->body.components.body_part_status;
            for (size_t i=0; i<std::min(parts.size(),plan->body_parts.size()); ++i) {
                const auto* part = plan->body_parts[i];
                if (parts[i].bits.organ_loss && part &&
                    (part->flags.is_set(df::body_part_raw_flags::CIRCULATION) ||
                     part->flags.is_set(df::body_part_raw_flags::THROAT) ||
                     part->flags.is_set(df::body_part_raw_flags::BREATHE))) { criticalOrganLoss=true; break; }
            }
        }
        flags |= st::injury(limbs.limbs_grasp_count,limbs.limbs_grasp_max,
            limbs.limbs_stand_count,limbs.limbs_stand_max,unit->flags3.bits.on_crutch,
            unit->body.blood_count,unit->body.blood_max,criticalOrganLoss);
    }
    if (fortControlled) {
        flags |= st::needs(unit->counters2.hunger_timer,unit->counters2.thirst_timer,unit->counters2.sleepiness_timer);
        if (unit->status.current_soul && unit->mood == df::mood_type::None &&
            unit->counters.soldier_mood == df::soldier_mood_type::None) {
            const auto& personality = unit->status.current_soul->personality;
            flags |= st::focus(personality.stress,personality.current_focus,personality.undistracted_focus);
        }
    }

    switch (unit->counters.soldier_mood) {
    case df::soldier_mood_type::Tantrum: flags |= st::Tantrum; break;
    case df::soldier_mood_type::Depressed: flags |= st::Depression; break;
    case df::soldier_mood_type::Oblivious: flags |= st::Oblivious; break;
    case df::soldier_mood_type::Enraged: flags |= st::Enraged; break;
    case df::soldier_mood_type::MartialTrance: flags |= st::MartialTrance; break;
    default: break;
    }

    switch (unit->mood) {
    case df::mood_type::Fey: flags |= st::Fey; break;
    case df::mood_type::Secretive: flags |= st::Secretive; break;
    case df::mood_type::Possessed: flags |= st::Possessed; break;
    case df::mood_type::Macabre: flags |= st::Macabre; break;
    case df::mood_type::Fell: flags |= st::Fell; break;
    case df::mood_type::Melancholy: flags |= st::Melancholy; break;
    case df::mood_type::Raving: flags |= st::Raving; break;
    case df::mood_type::Berserk: flags |= st::Berserk; break;
    case df::mood_type::Traumatized: flags |= st::Traumatized | st::Terrified; break;
    default: break;
    }
    if (unit->flags3.bits.emotionally_overloaded) flags |= st::Terrified;
    for (const auto activityId : unit->social_activities) {
        const auto* activity = df::activity_entry::find(activityId);
        if (!activity) continue;
        for (auto* event : activity->events) {
            if (!event) continue;
            auto [entry, fresh] = performances.try_emplace(event);
            if (fresh) {
                // Resolve participants once per event/publication, not once per
                // actor. Read game events, never a native viewscreen or widget.
                if (const auto* play = virtual_cast<df::activity_event_make_believest>(event)) {
                    for (const auto id : play->participants.units)
                        entry->second.try_emplace(id, st::PlayingMakeBelieve);
                } else if (const auto* performance = virtual_cast<df::activity_event_performancest>(event)) {
                    if (!performance->flags.bits.dismissed && !event->isEmpty() && performance->current_section != -1) {
                        for (const auto* role : performance->participant_actions) {
                            if (!role || role->unit_id < 0) continue;
                            uint64_t roleFlags=0;
                            switch (role->type) {
                            case df::performance_participant_type::STORYTELLER:
                            case df::performance_participant_type::PREACHER: roleFlags=st::TellingStory; break;
                            case df::performance_participant_type::POEM_RECITER: roleFlags=st::RecitingPoetry; break;
                            case df::performance_participant_type::MUSICAL_VOICE: roleFlags=st::PerformingMusic; break;
                            case df::performance_participant_type::DANCER: roleFlags=st::Dancing; break;
                            default: break;
                            }
                            if (roleFlags) entry->second.try_emplace(role->unit_id, roleFlags);
                        }
                    }
                }
            }
            // Native returns the first matching event/role in source order.
            // Do not let a later activity override it through icon priority.
            if (const auto role=entry->second.find(unit->id); role!=entry->second.end())
                return flags | role->second;
        }
    }
    return flags;
}

// Walks live units into `fbb`; also hints terrain blocks around units
// working terrain-changing jobs, and brings each published unit's
// appearance entry up to date (`appearanceSend` collects the entries to
// publish: all of them when `fullAppearances`, else the changed ones plus
// the rotating refresh slice). Returns the units vector offset.
flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mir::UnitState>>>
buildUnits(color_ostream& out, flatbuffers::FlatBufferBuilder& fbb, bool hintTerrain,
           int32_t frame, bool fullAppearances, vector<std::pair<int32_t, AppEntry*>>& appearanceSend) {
    const int32_t mx = world->map.x_count;
    const int32_t my = world->map.y_count;
    const int32_t mz = world->map.z_count;
    state.unitOffsets.clear();
    state.unitOffsets.reserve(world->units.active.size());
    appearanceSend.clear();
    AppearanceState& app_ = state.appearance;
    const auto ta = Clock::now();
    PerformanceStatuses performances;

    for (df::unit* u : world->units.active) {
        // Ghosts remain selectable native creatures. DFHack's isDead includes
        // ghosts, so use the killed flag only for non-ghost corpse exclusion.
        if (!Units::isActive(u) || (u->flags2.bits.killed && !u->flags3.bits.ghostly))
            continue;
        // getPosition resolves caged units to their cage's tile. Units with
        // any negative coordinate (pos sentinel is -30000) are in cages whose
        // position is unresolvable, in transit, or otherwise off-map — the
        // validator requires 0 <= pos < map_size, so skip them.
        const df::coord pos = Units::getPosition(u);
        if (pos.x < 0 || pos.y < 0 || pos.z < 0 ||
            pos.x >= mx || pos.y >= my || pos.z >= mz)
            continue;
        const df::creature_raw* raw = df::creature_raw::find(u->race);
        if (!raw || raw->creature_id.empty()) {
            // Should not happen for a live unit; species is required by the
            // validator, so skip and note it once.
            if (!state.warnedUnresolvedRace) {
                state.warnedUnresolvedRace = true;
                out.printerr("df3d: unit {} has unresolvable race {}; skipping "
                             "(reported once)\n", u->id, u->race);
            }
            continue;
        }
        const df::job* job = u->job.current_job;
        if (hintTerrain && job && state.terrain.mapped()) {
            const df::job_type_class jc = ENUM_ATTR(job_type, type, job->job_type);
            if (jc == df::job_type_class::Digging || jc == df::job_type_class::Building ||
                jc == df::job_type_class::Carving) {
                if (job->pos.x >= 0 && job->pos.y >= 0 && job->pos.z >= 0)
                    state.terrain.hintAround(job->pos.x,job->pos.y,job->pos.z);
            }
        }
        // CreateSharedString dedups identical species strings in the buffer
        // (most units share a handful of races).
        auto species = fbb.CreateSharedString(raw->creature_id);
        const mir::TilePos tile(pos.x, pos.y, pos.z);
        // Only actual melee action intents, never inferred from the current
        // job or combat reports. Lowest action id provides deterministic
        // selection when DF has queued more than one action.
        const df::unit_action* selectedAttack = nullptr;
        for (const auto* action : u->actions) {
            if (!action || action->type != df::unit_action_type::Attack || action->id < 0)
                continue;
            const auto& attack = action->data.attack;
            if (attack.target_unit_id < 0 || attack.target_unit_id == u->id) continue;
            auto* target = df::unit::find(attack.target_unit_id);
            if (!target || !Units::isActive(target) || (target->flags2.bits.killed && !target->flags3.bits.ghostly)) continue;
            const auto tp = Units::getPosition(target);
            const auto* tr = df::creature_raw::find(target->race);
            if (tp.x < 0 || tp.y < 0 || tp.z < 0 || tp.x >= mx || tp.y >= my || tp.z >= mz ||
                !tr || tr->creature_id.empty()) continue;
            if (!selectedAttack || action->id < selectedAttack->id) selectedAttack = action;
        }
        flatbuffers::Offset<mir::UnitAttack> attack;
        if (selectedAttack) {
            const auto& a = selectedAttack->data.attack;
            attack = mir::CreateUnitAttack(fbb, selectedAttack->id, a.target_unit_id, a.timer1, a.timer2);
        }
        state.unitOffsets.push_back(mir::CreateUnitState(
            fbb, static_cast<uint64_t>(u->id), &tile, species, mapJob(job), attack, static_cast<uint32_t>(std::max(0, u->body.size_info.size_cur)), unitStatusFlags(u, performances)));

        // Appearance: amortized resolve; publish on change, on the
        // refresh rotation, or always for a Full.
        AppEntry& e = updateAppearance(u, frame, fullAppearances);
        const bool refresh = app_.refreshPeriod > 0 &&
                             ((static_cast<uint32_t>(frame) + e.slot) % app_.refreshPeriod) == 0;
        if (fullAppearances || e.dirty || refresh) {
            appearanceSend.emplace_back(u->id, &e);
        }
    }
    track(usSince(ta), app_.resolveUsLast, app_.resolveUsEma, app_.resolveUsMax);
    return fbb.CreateVector(state.unitOffsets);
}

// Appends a finished size-prefixed buffer to the fixture file if recording.
void recordBuffer(const uint8_t* buf, size_t len) {
    std::lock_guard<std::mutex> lock(state.recordMutex);
    if (state.recordFile.is_open()) {
        state.recordFile.write(reinterpret_cast<const char*>(buf),
                               static_cast<std::streamsize>(len));
        ++state.recordCount;
    }
}

void buildAndPublishSnapshot(color_ostream& out, int32_t frame) {
    auto& t = state.terrain;
    const int32_t mx = world->map.x_count;
    const int32_t my = world->map.y_count;
    const int32_t mz = world->map.z_count;
    // tick := world->frame_counter. It increments exactly once per simulated
    // frame and never runs while paused, which is precisely the "sim advanced"
    // signal the world model's clock estimator needs. If more than one frame
    // elapsed since our last onupdate we still publish a single snapshot —
    // the world model tolerates tick gaps by design.
    const uint64_t tick = static_cast<uint64_t>(frame);

    size_t nBlocks = t.prepareDelta(frame,state.region->snapshotCapacity);

    // Entities: a Full when a client asked for one since the last
    // served request (or this is the first snapshot of the map), else the
    // due Delta. The walk runs once per frame; a Full is preceded by a
    // complete pass so it is current.
    const uint64_t entityReq = shm::atomicLoadAcquire(&state.region->entityFullRequest);
    const bool entityFull = state.entityFullPending || entityReq != state.entityFullServed;
    ent::scan(frame, entityFull, pairMaterial);

    vector<std::pair<int32_t, AppEntry*>> appSend;
    for (int attempt = 0; attempt < 4; ++attempt) {
        state.fbb.Clear();
        beginSnapshotMaterials();
        beginAppearanceTables();
        // A paused late viewer cannot wait for the rotating appearance resend.
        // Entity bootstrap must carry a current stack for every published unit.
        auto unitsVec = buildUnits(out, state.fbb, true, frame, entityFull, appSend);
        flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mir::MapBlock>>> blocksVec;
        mir::TerrainScope scope = mir::TerrainScope::None;
        if (nBlocks > 0) {
            blocksVec = t.buildDelta(state.fbb);
            scope = mir::TerrainScope::Delta;
        }
        ent::Built built;
        const size_t entityStart = state.fbb.GetSize();
        ent::build(state.fbb, frame, entityFull, localMaterial, built, true);
        const size_t entityBytes = state.fbb.GetSize() - entityStart;
        // Glyph tables: Full with the entity Full, else the materials
        // interned since the last snapshot (the entity scan ran already).
        GlyphBuilt glyphs;
        const size_t glyphStart = state.fbb.GetSize();
        buildGlyphs(state.fbb, entityFull, glyphs);
        const size_t glyphBytes = state.fbb.GetSize() - glyphStart;
        // Command results: every pending result rides along; the
        // repeat window is decremented once the snapshot is published.
        flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mir::CommandResult>>> resultsVec;
        state.resultOffsets.clear();
        for (const BridgeState::PendingResult& r : state.results) {
            auto msg = state.fbb.CreateString(r.message);
            state.resultOffsets.push_back(mir::CreateCommandResult(state.fbb, r.seq, r.status, msg));
        }
        if (!state.resultOffsets.empty()) resultsVec = state.fbb.CreateVector(state.resultOffsets);
        auto spatterVec = df3d_ground_spatters::build(state.fbb,entityFull,tick,localMaterial);
        const auto spatterScope = entityFull ? mir::ChangeScope::Full :
            df3d_ground_spatters::pending.empty() ? mir::ChangeScope::None : mir::ChangeScope::Delta;
        auto matsVec = finishSnapshotMaterials(state.fbb);
        flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mir::UnitAppearance>>> appsVec;
        flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<flatbuffers::String>>> pagesVec, palettesVec;
        mir::AppearanceScope appScope = mir::AppearanceScope::None;
        if (entityFull || !appSend.empty()) {
            appsVec = buildAppearances(state.fbb, appSend);
            appScope = entityFull ? mir::AppearanceScope::Full : mir::AppearanceScope::Delta;
        }
        const bool anyLayers = appScope != mir::AppearanceScope::None || built.itemAppearanceScope != mir::AppearanceScope::None;
        if (anyLayers) finishAppearanceTables(state.fbb, pagesVec, palettesVec);
        const mir::TilePos dims(mx, my, mz);
        auto combatVec = buildCombatEvents(state.fbb, tick);
        auto projectileVec = buildProjectileSamples(state.fbb, tick);
        auto reportVec = df3d_events::buildReports(state.fbb,tick);
        auto contactVec = df3d_contact::build(state.fbb,tick);
        auto attackVec = df3d_contact::buildAttacks(state.fbb,tick);
        auto projectileCombatVec=df3d_contact::buildProjectiles(state.fbb,tick);
        auto snap = mir::CreateSnapshot(
            state.fbb, static_cast<uint32_t>(mir::SchemaVersion::Current), tick, wallClockUnixMs(),
            &dims, unitsVec, scope, nBlocks > 0 ? blocksVec : 0, matsVec,
            appScope, appsVec, anyLayers ? pagesVec : 0,
            anyLayers ? palettesVec : 0, built.buildingScope, built.buildings,
            built.removedBuildings, built.itemScope, built.items, built.removedItems,
            built.itemAppearanceScope, built.itemAppearances, glyphs.scope, glyphs.creatures,
            glyphs.materials, glyphs.itemdefs, state.resultOffsets.empty() ? 0 : resultsVec, combatVec, projectileVec,
            spatterScope,spatterVec,reportVec,df3d_events::reports().dropped,
            contactVec,df3d_contact::dropped(),df3d_contact::available(),
            attackVec,df3d_contact::attacksDropped(),df3d_contact::available(),projectileCombatVec,df3d_contact::projectilesDropped(),df3d_contact::available(),
            df::global::cur_year_tick ? *df::global::cur_year_tick : -1);
        // Size-prefixed on purpose — see the shm convention in the header comment.
        state.fbb.FinishSizePrefixed(snap, mir::SnapshotIdentifier());

        const uint8_t* buf = state.fbb.GetBufferPointer();
        const size_t len = state.fbb.GetSize();

        if (!shm::publishSnapshot(state.region, buf, len, tick, shm::publicationClockMicros())) {
            if (nBlocks > 1) {
                // Should not happen given maxDeltaBlocks; drop the repeats,
                // then halve the new blocks and retry (the remainder spills
                // to later frames).
                nBlocks = t.reduceDelta();
                continue;
            }
            if (!state.warnedOversizeSnapshot) {
                state.warnedOversizeSnapshot = true;
                out.printerr("df3d: snapshot ({} bytes) exceeds shm slot capacity "
                             "({} bytes); publishing stopped for this kind of "
                             "failure (reported once)\n",
                             len, state.region->snapshotCapacity);
            }
            return;
        }

        // Published: the appearances it carried are no longer dirty, the
        // blocks it carried retire from the spill queue, and the entity
        // request (if any) is served.
        for (auto& [id, e] : appSend) e->dirty = false;
        state.lastResultsSent = state.results.size();
        state.commandPublicationPending = false;
        state.resultsSent += state.results.size();
        for (size_t i = 0; i < state.results.size();) {
            if (--state.results[i].remaining == 0) state.results.erase(state.results.begin() + static_cast<std::ptrdiff_t>(i));
            else ++i;
        }
        ent::published(frame, entityFull);
        df3d_ground_spatters::published(tick);
        ent::mutableStats().lastEntityBytes = entityBytes;
        if (entityFull) {
            state.entityFullServed = entityReq;
            state.entityFullPending = false;
            ent::mutableStats().lastFullBytes = entityBytes;
            state.glyphs.lastFullBytes = glyphBytes;
        }
        state.lastEntityBytes = entityBytes;
        t.published(frame);
        state.glyphs.materialsSent = df3d_glyph_cursor::afterPublish(state.glyphs.materialsSent, glyphs.materialsBuiltTo, true);

        state.havePublished = true;
        state.lastFrame = frame;
        state.lastTick = tick;
        state.lastUnitCount = state.unitOffsets.size();
        state.lastSnapshotBytes = len;
        ++state.snapshotsPublished;

        // Fixture recording: the published buffer already has the exact on-disk
        // entry format (size-prefixed Snapshot), so append it verbatim.
        recordBuffer(buf, len);
        return;
    }
}

// Writes a Full terrain snapshot built from the grid straight into the
// fixture file (never to the ring: it exceeds the slot). tick = the last
// published tick so the following ring snapshots stay strictly newer.
bool writeFullToRecording(color_ostream& out) {
    auto& t = state.terrain;
    if (!t.mapped()) {
        out.printerr("df3d: no terrain grid; fixture will carry no terrain\n");
        return true;
    }
    const auto t0 = Clock::now();
    flatbuffers::FlatBufferBuilder fbb(static_cast<size_t>(t.blockCount()) * 2200 + (1u << 20));
    beginSnapshotMaterials();
    beginAppearanceTables();
    // Every unit's appearance rides along (appearance_scope Full), freshly
    // resolved, so the fixture is self-contained from its first entry.
    vector<std::pair<int32_t, AppEntry*>> appSend;
    auto unitsVec = buildUnits(out, fbb, false, state.lastFrame, true, appSend);
    auto blocksVec = t.buildFull(fbb);
    // Buildings and items: a Full of every shadow (the published state as
    // of the last ring snapshot), so the following Deltas apply cleanly;
    // corpse stacks ride with the item records. Glyph tables: Full.
    ent::Built built;
    const size_t entityStart = fbb.GetSize();
    ent::build(fbb, state.lastFrame, true, localMaterial, built, false);
    const size_t entityBytes = fbb.GetSize() - entityStart;
    GlyphBuilt glyphs;
    const size_t glyphStart = fbb.GetSize();
    buildGlyphs(fbb, true, glyphs);  // recording Full: the ring mark is not advanced
    const size_t glyphBytes = fbb.GetSize() - glyphStart;
    auto appsVec = buildAppearances(fbb, appSend);
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<flatbuffers::String>>> pagesVec, palettesVec;
    finishAppearanceTables(fbb, pagesVec, palettesVec);
    auto spatterVec = df3d_ground_spatters::build(fbb,true,state.lastTick,localMaterial);
    auto matsVec = finishSnapshotMaterials(fbb);
    const auto dims = t.dimensions();
    auto combatVec = buildCombatEvents(fbb, state.lastTick);
    auto projectileVec = buildProjectileSamples(fbb, state.lastTick);
    auto reportVec = df3d_events::buildReports(fbb,state.lastTick);
    auto contactVec = df3d_contact::build(fbb,state.lastTick);
    auto attackVec = df3d_contact::buildAttacks(fbb,state.lastTick);
    auto projectileCombatVec=df3d_contact::buildProjectiles(fbb,state.lastTick);
    auto snap = mir::CreateSnapshot(fbb, static_cast<uint32_t>(mir::SchemaVersion::Current),
                                    state.lastTick, wallClockUnixMs(), &dims, unitsVec,
                                    mir::TerrainScope::Full, blocksVec, matsVec,
                                    mir::AppearanceScope::Full, appsVec, pagesVec, palettesVec,
                                    built.buildingScope, built.buildings, built.removedBuildings,
                                    built.itemScope, built.items, built.removedItems,
                                    built.itemAppearanceScope, built.itemAppearances, glyphs.scope,
                                    glyphs.creatures, glyphs.materials, glyphs.itemdefs, 0, combatVec, projectileVec,
                                    mir::ChangeScope::Full,spatterVec,reportVec,df3d_events::reports().dropped,
                                    contactVec,df3d_contact::dropped(),df3d_contact::available(),
                                    attackVec,df3d_contact::attacksDropped(),df3d_contact::available(),projectileCombatVec,df3d_contact::projectilesDropped(),df3d_contact::available(),
            df::global::cur_year_tick ? *df::global::cur_year_tick : -1);
    fbb.FinishSizePrefixed(snap, mir::SnapshotIdentifier());
    recordBuffer(fbb.GetBufferPointer(), fbb.GetSize());
    // The Full's appearances are now the last published stack of every unit.
    for (auto& [id, e] : appSend) e->dirty = false;
    // Blocks queued before the Full are already in it; a Delta re-sending
    // them is harmless (same content), so the queue is left alone.
    out.print("df3d: wrote Full snapshot ({} blocks, {} entity records in {} bytes, {} glyph rows in {} bytes, "
              "{} bytes total, tick {}) in {:.1f} ms\n",
              t.blockCount(), built.count, entityBytes, glyphs.rows, glyphBytes, fbb.GetSize(), state.lastTick,
              usSince(t0) / 1000.0);
    return true;
}

// ---- command drain ----

// Per-update execution budget for commands. Soft between commands; inside a
// dig / smooth rectangle the walk yields at the deadline and resumes on the
// next update (commands.h), so one 65 536-tile command never owns a tick.
constexpr auto kCommandBudget = std::chrono::microseconds(2000);

void queueResult(const cmdx::Result& r) {
    BridgeState::PendingResult res;
    res.seq = r.seq;
    res.status = r.status;
    res.message = r.message;
    state.results.push_back(std::move(res));
    state.commandPublicationPending = true;
    ++state.resultsQueued;
}

// Map / world unload with a dig / smooth rectangle sliced across the
// boundary: at least one slice was applied, so its outcome is Unknown and
// must reach the client rather than vanish. No snapshot can be built
// without a map, so the result is queued and published with the first
// snapshot of the next map (SC_MAP_LOADED keeps queued results). Nothing
// here touches map state.
void abandonPendingCommand() {
    cmdx::Result r;
    if (cmdx::abandon(r)) queueResult(r);
    cmdx::reset();
}

void drainCommands(color_ostream& out) {
    const auto started=Clock::now();
    const auto deadline = started + kCommandBudget;
    cmdx::beginDrain();
    if (cmdx::pending()) {
        // Finish (or advance) the command in progress before popping the
        // next one: commands apply in the order they were sent.
        cmdx::Result r;
        if (!cmdx::resume(deadline, r)) return;
        queueResult(r);
    }
    for (uint32_t count=0; count<mir::kMaxCommandsPerUpdate; ++count) {
        if(count && Clock::now()>=deadline) return;
        const size_t got = shm::popCommand(state.region, state.cmdBuf.data(),
                                           state.cmdBuf.size());
        if (got == 0)
            return;
        if (got == SIZE_MAX) {
            if (!state.warnedCorruptCommand) {
                state.warnedCorruptCommand = true;
                out.printerr("df3d: corrupt/oversized entry in command ring; "
                             "discarding pending commands (reported once)\n");
            }
            // Per shm_layout.h: log and reset tail to head.
            shm::atomicStoreRelease(&state.region->cmdTail,
                                    shm::atomicLoadAcquire(&state.region->cmdHead));
            return;
        }
        ++state.commandsDrained;
        const mir::Command* cmd = mir::parseCommand(state.cmdBuf.data(), got);
        if (!cmd) {
            if (!state.warnedCorruptCommand) {
                state.warnedCorruptCommand = true;
                out.printerr("df3d: command failed FlatBuffers verification; "
                             "ignored (reported once)\n");
            }
            continue;
        }
        BridgeState::PendingResult res;
        res.seq = cmd->seq();
        if (!mir::commandEpochMatches(*cmd, state.mapLoaded ? state.terrain.epoch() : 0)) {
            res.status=mir::CommandStatus::Rejected;
            res.message="World changed or unavailable; command was not applied";
        } else if (df3d_session::saving()) {
            res.status = mir::CommandStatus::Rejected;
            res.message = "Dwarf Fortress is saving; retry after it completes";
        } else if (cmd->payload_type() == mir::CommandPayload::SetPause) {
            const mir::SetPause* sp = cmd->payload_as_SetPause();
            World::SetPauseState(sp->paused());
            res.message = sp->paused() ? "paused" : "unpaused";
        } else {
            // Validate against the live map first (the client validated
            // without a map size); then execute on this thread (core
            // suspended) and queue the outcome.
            const mir::TilePos dims(world ? world->map.x_count : 0, world ? world->map.y_count : 0,
                                    world ? world->map.z_count : 0);
            if (auto err = mir::validateCommand(*cmd, state.mapLoaded ? &dims : nullptr)) {
                res.status = mir::CommandStatus::Rejected;
                res.message = *err;
            } else {
                cmdx::Result r;
                if (!cmdx::execute(state.cmdBuf.data(), got, *cmd, deadline, r)) {
                    // Budget exhausted mid-rectangle: the result is queued
                    // by a later update's resume(); nothing is published yet.
                    ++state.commandsSliced;
                    return;
                }
                res.status = r.status;
                res.message = r.message;
            }
            if (res.status == mir::CommandStatus::Unknown && !state.warnedUnknownCommand) {
                state.warnedUnknownCommand = true;
                out.printerr("df3d: command seq {} has unknown payload type {}; "
                             "answered Unknown (reported once)\n", cmd->seq(),
                             static_cast<int>(cmd->payload_type()));
            }
        }
        state.results.push_back(std::move(res));
        state.commandPublicationPending = true;
        ++state.resultsQueued;
    }
}

// ---- console command ----

command_result cmdStatus(color_ostream& out) {
    auto& t = state.terrain;
    out.print("df3d bridge status:\n");
    out.print("  item contact source: {} (dropped {})\n",df3d_contact::status(),df3d_contact::dropped());
    out.print("  mirroring enabled:   {}\n", is_enabled ? "yes" : "no");
    out.print("  map loaded:          {}\n", state.mapLoaded ? "yes" : "no");
    out.print("  shm region mapped:   {}\n", state.region ? "yes" : "no");
    out.print("  session channel:     {}\n", state.sessionAvailable ? "owned" : "unavailable (another bridge owns it)");
    out.print("  paused:              {}\n", World::ReadPauseState() ? "yes" : "no");
    if (state.havePublished) {
        out.print("  last published tick: {}\n", state.lastTick);
        out.print("  units in last snap:  {}\n", state.lastUnitCount);
        out.print("  last snapshot bytes: {}\n", state.lastSnapshotBytes);
    } else {
        out.print("  last published tick: (none yet)\n");
    }
    out.print("  snapshots published: {}\n", state.snapshotsPublished);
    out.print("  commands drained:    {}\n", state.commandsDrained);
    t.printStatus(out);
    {
        const AppearanceState& a = state.appearance;
        out.print("  appearances:         {} units tracked ({} evicted), {} resolves, {} changes, {} sent ({} layers), last snapshot {}\n",
                  a.units.size(), a.evicted, a.resolves, a.changes, a.sent, a.sentLayers, a.lastSent);
        out.print("    periods:           resolve every {} frames, refresh every {} frames\n",
                  a.resolvePeriod, a.refreshPeriod);
    }
    ent::printStatus(out);
    {
        const auto& r=df3d_events::reports();
        out.print("  report events:       {} retained, {} observed, {} capacity drops, {} repeats, {} continuations\n",
                  r.records.size(),r.nextId-1,r.dropped,r.duplicates,r.continuations);
    }
    ent::resetStatsMax();
    {
        const GlyphState& g = state.glyphs;
        out.print("  glyphs:              {} Fulls, {} Deltas, {} rows sent; last snapshot {} rows; last Full {} bytes; "
                  "{} of {} grid materials published\n",
                  g.fullsBuilt, g.deltasBuilt, g.rowsSent, g.lastRows, g.lastFullBytes, g.materialsSent,
                  state.terrain.materialCount());
    }
    {
        const cmdx::Stats& c = cmdx::stats();
        out.print("  commands:            {} drained; {} executed ({} ok, {} rejected, {} unknown); "
                  "{} tiles applied of {} visited, {} plants, {} entities; results {} queued, {} sent, "
                  "{} pending, last snapshot {}; {} sliced across updates{}\n",
                  state.commandsDrained, c.executed, c.ok, c.rejected, c.unknown, c.tilesApplied,
                  c.tilesVisited, c.plantsMarked, c.entitiesChanged, state.resultsQueued, state.resultsSent,
                  state.results.size(), state.lastResultsSent, state.commandsSliced,
                  cmdx::pending() ? " (one in progress)" : "");
        out.print("    exec (us):         {:.0f} / {:.0f} / {:.0f} (last / ema / max per command); last: {}\n",
                  c.execUsLast, c.execUsEma, c.execUsMax, c.lastMessage);
        cmdx::resetStatsMax();
    }
    df3d_management::printTiming(out);
    out.print("  timing (us, last/ema/max over {} updates):\n", state.updates);
    out.print("    update:            {:.0f} / {:.0f} / {:.0f}\n", state.updateUsLast,
              state.updateUsEma, state.updateUsMax);
    out.print("    terrain scan:      {:.0f} / {:.0f} / {:.0f}\n", state.scanUsLast,
              state.scanUsEma, state.scanUsMax);
    out.print("    snapshot publish:  {:.0f} / {:.0f} / {:.0f}\n", state.publishUsLast,
              state.publishUsEma, state.publishUsMax);
    out.print("    units+appearance:  {:.0f} / {:.0f} / {:.0f}  (part of publish: unit walk + appearance resolve)\n",
              state.appearance.resolveUsLast, state.appearance.resolveUsEma, state.appearance.resolveUsMax);
    state.updateUsMax = state.scanUsMax = state.publishUsMax = 0.0;
    state.appearance.resolveUsMax = 0.0;
    std::lock_guard<std::mutex> lock(state.recordMutex);
    if (state.recordFile.is_open())
        out.print("  recording:           {} ({} snapshot(s) so far)\n",
                  state.recordPath, state.recordCount);
    else
        out.print("  recording:           off\n");
    return CR_OK;
}

command_result cmdRecordStart(color_ostream& out, const string& path) {
    // The first entry is a Full built from the grid, stamped with the last
    // published tick. If nothing has been published yet (map just loaded),
    // publish the current frame first (before the file opens, so it is not
    // recorded ahead of the Full) so the Full has a tick to follow.
    if (state.mapLoaded && state.region && !state.havePublished)
        buildAndPublishSnapshot(out, world->frame_counter);
    {
        std::lock_guard<std::mutex> lock(state.recordMutex);
        if (state.recordFile.is_open()) {
            out.printerr("df3d: already recording to {}; run 'df3d record stop' first\n",
                         state.recordPath);
            return CR_FAILURE;
        }
        state.recordFile.clear();  // reset stale error bits from any earlier failure
        state.recordFile.open(path, std::ios::binary | std::ios::trunc);
        if (!state.recordFile) {
            out.printerr("df3d: cannot open {} for writing\n", path);
            return CR_FAILURE;
        }
        state.recordFile.write(mir::kFixtureMagic, sizeof(mir::kFixtureMagic));
        if (!state.recordFile) {
            out.printerr("df3d: write failed on {}\n", path);
            state.recordFile.close();
            state.recordFile.clear();
            return CR_FAILURE;
        }
        state.recordPath = path;
        state.recordCount = 0;
    }
    if (state.mapLoaded && state.region)
        writeFullToRecording(out);
    out.print("df3d: recording fixture to {}\n", path);
    return CR_OK;
}

// Runs with the core suspended (PluginCommand default), so it cannot race
// plugin_onupdate.
command_result df3d_command(color_ostream& out, vector<string>& parameters) {
    if (parameters.empty() || parameters[0] == "status")
        return cmdStatus(out);
      if(parameters[0]=="pressure-trigger-read") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          uint32_t flags=0;const auto& v=parameters[1];
          const auto parsed=std::from_chars(v.data(),v.data()+v.size(),flags);
          if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          out.print("{{\"support\":{}}}\n",df3d_construction::pressureTrigger(flags));return CR_OK;
      }
      if(parameters[0]=="bridge-tile-read") {
          if(parameters.size()!=5)return CR_WRONG_USAGE;
          int32_t p[4]{};
          for(size_t i=0;i<4;++i) {
              const auto& v=parameters[i+1];const auto parsed=std::from_chars(v.data(),v.data()+v.size(),p[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          if(p[3]<0 || p[3]>1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          out.print("{{\"support\":{}}}\n",df3d_construction::bridgeTile(p[0],p[1],p[2],p[3]!=0));return CR_OK;
      }
      if(parameters[0]=="special-tile-read") {
          if(parameters.size()!=6)return CR_WRONG_USAGE;
          int32_t p[4]{};
          for(size_t i=0;i<4;++i) {
              const auto& v=parameters[i+2];const auto parsed=std::from_chars(v.data(),v.data()+v.size(),p[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          if(p[3]<0 || p[3]>1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          out.print("{{\"support\":{}}}\n",df3d_construction::specialTile(parameters[1],p[0],p[1],p[2],p[3]!=0));return CR_OK;
      }
      if(parameters[0]=="opening-tile-read" || parameters[0]=="extent-tile-read" || parameters[0]=="furniture-tile-read" || parameters[0]=="ordinary-tile-read") {
          if(parameters.size()!=5)return CR_WRONG_USAGE;
          int32_t p[3]{};
          for(size_t i=0;i<3;++i) {
              const auto& v=parameters[i+2];const auto parsed=std::from_chars(v.data(),v.data()+v.size(),p[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int raw=-1;const auto code=parameters[0]=="opening-tile-read"?df3d_construction::openingTile(parameters[1],p[0],p[1],p[2]):parameters[0]=="ordinary-tile-read"?df3d_construction::ordinaryTile(parameters[1],p[0],p[1],p[2]):parameters[0]=="furniture-tile-read"?df3d_construction::furnitureTile(parameters[1],p[0],p[1],p[2]):df3d_construction::extentTile(parameters[1],p[0],p[1],p[2],&raw);
          out.print("{{\"support\":{},\"raw\":{}}}\n",code,raw);return CR_OK;
      }
      if(parameters[0]=="area-connectivity-read" || parameters[0]=="farm-warning-read") {
          if(parameters.size()!=(parameters[0]=="farm-warning-read"?8:7))return CR_WRONG_USAGE;
          int32_t p[5]{};
          for(size_t i=0;i<5;++i) {
              const auto& v=parameters[i+2];const auto parsed=std::from_chars(v.data(),v.data()+v.size(),p[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          if(parameters[0]=="farm-warning-read" && parameters[1]!="FarmPlot")return CR_WRONG_USAGE;
          std::vector<uint8_t> eligible;
          if(parameters[0]=="farm-warning-read")for(char v:parameters[7]) {
              if(v!='0' && v!='1')return CR_WRONG_USAGE;eligible.push_back(uint8_t(v-'0'));
          }
          const int answer=parameters[0]=="farm-warning-read"?df3d_construction::farmWarning(p[0],p[1],p[2],p[3],p[4],eligible):df3d_construction::areaConnectivity(parameters[1],p[0],p[1],p[2],p[3],p[4]);
          out.print("{{\"support\":{}}}\n",answer);return CR_OK;
      }
      if(parameters[0]=="track-terrain-read" || parameters[0]=="track-terrain-oracle-read") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t p[3]{};
          for(size_t i=0;i<3;++i) {
              const auto& v=parameters[i+1];const auto parsed=std::from_chars(v.data(),v.data()+v.size(),p[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const int answer=parameters[0]=="track-terrain-read"?df3d_construction::trackTerrain(p[0],p[1],p[2]):df3d_construction::trackTerrainOracle(p[0],p[1],p[2]);
          out.print("{{\"support\":{}}}\n",answer);return CR_OK;
      }
      if(parameters[0]=="construction-terrain-read") {
          if(parameters.size()!=5 && parameters.size()!=9)return CR_WRONG_USAGE;
          int32_t values[8]={0,0,0,0,-1,-1,1,1};
          for(size_t i=0;i<parameters.size()-1;++i) {
              const auto& v=parameters[i+1];
              const auto parsed=std::from_chars(v.data(),v.data()+v.size(),values[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          out.print("{{\"support\":{}}}\n",df3d_construction::constructionTerrain(values[0],values[1],values[2],values[3],values[4],values[5],values[6],values[7]));
          return CR_OK;
      }
      if(parameters[0]=="bed-choices-read") {
          if(parameters.size()!=3)return CR_WRONG_USAGE;
          int32_t values[2]{};
          for(size_t i=0;i<2;++i) {
              const auto& v=parameters[i+1];
              const auto parsed=std::from_chars(v.data(),v.data()+v.size(),values[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          df3d_bed::Choices result;
          const bool valid=df3d_bed::choices(values[0],values[1],result);
          out.print("{{\"valid\":{},\"sheet\":{},\"pillow\":{},\"color\":{}}}\n",valid,result.sheet,result.pillow,result.color);
          return CR_OK;
      }
      if(parameters[0]=="bars-connections-read") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t p[3]{};
          for(size_t i=0;i<3;++i) {
              const auto& v=parameters[i+1];
              const auto parsed=std::from_chars(v.data(),v.data()+v.size(),p[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          out.print("{{\"connections\":{}}}\n",df3d_construction::verticalBarsConnections(p[0],p[1],p[2]));
          return CR_OK;
      }
        if(parameters[0]=="hover-list-read") {
            if(parameters.size()!=4)return CR_WRONG_USAGE;
            int32_t p[3]{};
            for(size_t i=0;i<3;++i) {
                const auto& raw=parameters[i+1];
                const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),p[i]);
                if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
            }
            if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
            const auto rows=df3d_hover::collect(p[0],p[1],p[2]);
            Json::Value value(Json::objectValue);value["valid"]=rows.has_value();
            value["entries"]=Json::Value(Json::arrayValue);
            if(rows)for(const auto& row:*rows) {
                Json::Value entry(Json::objectValue);
                entry["kind"]=row.kind;entry["id"]=row.id;entry["text"]=row.text;
                entry["foreground"]=row.foreground;entry["background"]=row.background;entry["bright"]=row.bright;
                value["entries"].append(entry);
            }
            out.print("{}",Json::FastWriter().write(value));return CR_OK;
        }
        if(parameters[0]=="hover-object-read") {
            if(parameters.size()!=3)return CR_WRONG_USAGE;
            df3d_hover::ObjectKind kind;
            if(parameters[1]=="Item")kind=df3d_hover::ObjectKind::Item;
            else if(parameters[1]=="Unit")kind=df3d_hover::ObjectKind::Unit;
            else if(parameters[1]=="Building")kind=df3d_hover::ObjectKind::Building;
            else return CR_WRONG_USAGE;
            int32_t id=-1;const auto& raw=parameters[2];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
            if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
            const auto description=df3d_hover::object(kind,id);
            Json::Value value(Json::objectValue);value["valid"]=description.has_value();
            if(description) {
                value["text"]=description->text;value["foreground"]=description->foreground;
                value["background"]=description->background;value["bright"]=description->bright;
            }
            out.print("{}",Json::FastWriter().write(value));return CR_OK;
        }
        if(parameters[0]=="stockpile-link-target-read") {
          if(parameters.size()!=6)return CR_WRONG_USAGE;
          int32_t values[5]{};
          for(size_t i=0;i<5;++i) {
            const auto& raw=parameters[i+1];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(values[0]<0 || values[4]<0 || values[4]>1)return CR_WRONG_USAGE;
          for(size_t i=1;i<4;++i)if(values[i]<0 || values[i]>32767)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          return df3d_management::printStockpileLinkTarget(out,values[0],int16_t(values[1]),int16_t(values[2]),int16_t(values[3]),values[4]!=0)?CR_OK:CR_FAILURE;
        }
        if(parameters[0]=="farm-fertilize") {
          if(parameters.size()!=3)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          const auto& mode=parameters[2];
          if(mode!="toggle" && mode!="seasonal-on" && mode!="seasonal-off")return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          auto* farm=virtual_cast<df::building_farmplotst>(df::building::find(id));
          const bool accepted=mode=="toggle"?df3d_production::toggleFarmFertilization(farm):
            df3d_production::setFarmSeasonalFertilization(farm,mode=="seasonal-on");
          if(!accepted)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["accepted"]=true;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="farm-crop-set") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t values[3]{};
          for(size_t i=0;i<3;++i) {
            const auto& raw=parameters[i+1];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(values[0]<0 || values[1]<0 || values[1]>3 || values[2]<-1 || values[2]>32767)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          auto* farm=virtual_cast<df::building_farmplotst>(df::building::find(values[0]));
          const auto accepted=df3d_production::setFarmCrop(farm,values[1],values[2]);
          if(!accepted)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["accepted"]=*accepted;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="farm-choices-read") {
          if(parameters.size()!=3)return CR_WRONG_USAGE;
          int32_t values[2]{};
          for(size_t i=0;i<2;++i) {
            const auto& raw=parameters[i+1];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(values[0]<0 || values[1]<0 || values[1]>3)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          auto* farm=virtual_cast<df::building_farmplotst>(df::building::find(values[0]));
          const auto choices=df3d_production::farmChoices(farm,values[1]);if(!choices)return CR_FAILURE;
          Json::Value result(Json::objectValue),rows(Json::arrayValue);
          for(const auto& choice:*choices) {
            Json::Value row(Json::objectValue);row["crop_id"]=choice.cropId;row["name"]=DF2UTF(choice.name);
            row["seeds_available"]=choice.seedsAvailable;row["current_season_warning"]=choice.currentSeasonWarning;
            rows.append(std::move(row));
          }
          result["building_id"]=values[0];result["season"]=values[1];result["rows"]=std::move(rows);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-expel-destinations-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto destinations=df3d_creature::expelDestinations();if(!destinations)return CR_FAILURE;
          Json::Value result(Json::arrayValue);for(auto id:*destinations)result.append(id);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-expel-preview-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto preview=df3d_creature::expelPreview(df::unit::find(id));if(!preview)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["unit_id"]=preview->unitId;result["eligible"]=preview->eligible;result["reason"]=preview->reason;
          result["units"]=Json::Value(Json::arrayValue);result["destinations"]=Json::Value(Json::arrayValue);
          for(const auto& row:preview->units) {
            Json::Value value(Json::objectValue);value["id"]=row.id;value["name"]=DF2UTF(row.name);
            for(auto component:row.color.color)value["color"].append(component);
            for(auto component:row.color.alternate)value["alternate"].append(component);
            value["effect"]=row.color.effect;value["source"]=row.color.source;result["units"].append(value);
          }
          for(const auto& row:preview->destinations) {Json::Value value(Json::objectValue);value["id"]=row.id;value["name"]=DF2UTF(row.name);result["destinations"].append(value);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-expel-apply-probe") {
          if(parameters.size()<4 || parameters.size()>10003)return CR_WRONG_USAGE;
          std::vector<int32_t> values;
          for(size_t i=1;i<parameters.size();++i) {
            int32_t value=-1;const auto& raw=parameters[i];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);
            if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||value<(i==2?-1:0))return CR_WRONG_USAGE;
            values.push_back(value);
          }
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const std::vector<int32_t> expected(values.begin()+2,values.end());
          const auto outcome=df3d_creature::applyExpel(df::unit::find(values[0]),values[1],expected);
          Json::Value result(Json::objectValue);result["outcome"]=int(outcome);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="item-owner-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto owner=df3d_production::itemOwnerDescription(df::item::find(id));if(!owner)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["id"]=owner->id;result["name"]=DF2UTF(owner->name);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="poetic-detail-probe" || parameters[0]=="musical-detail-probe" || parameters[0]=="dance-detail-probe" || parameters[0]=="written-detail-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto text=parameters[0]=="poetic-detail-probe" ?
              df3d_creature::poeticDetailProbe(df::poetic_form::find(id)) :
              parameters[0]=="musical-detail-probe" ? df3d_creature::musicalDetailProbe(df::musical_form::find(id)) :
              parameters[0]=="dance-detail-probe" ? df3d_creature::danceDetailProbe(df::dance_form::find(id)) :
              df3d_creature::writtenDetailProbe(df::written_content::find(id));if(!text)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["id"]=id;result["text"]=DF2UTF(*text);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-knowledge-detail-probe" || parameters[0]=="unit-knowledge-cache-probe") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          std::array<int32_t,3> values{};
          for(size_t i=0;i<values.size();++i){
            const auto& raw=parameters[i+1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          if(parameters[0]=="unit-knowledge-cache-probe") {
            const auto probe=df3d_creature::knowledgeCacheProbe(df::unit::find(values[0]),values[1],values[2]);
            if(!probe)return CR_FAILURE;
            Json::Value result(Json::objectValue);result["available"]=bool(probe->text);
            if(probe->text)result["text"]=DF2UTF(*probe->text);
            result["cold_insertions"]=Json::UInt64(probe->coldInsertions);
            result["nested_restored"]=probe->nestedRestored;result["exception_restored"]=probe->exceptionRestored;
            result["original_restored"]=probe->originalRestored;
            out.print("{}",Json::FastWriter().write(result));return CR_OK;
          }
          const auto text=df3d_creature::selectedKnowledgeDetail(df::unit::find(values[0]),values[1],values[2]);
          Json::Value result(Json::objectValue);result["available"]=bool(text);
          result["unit_id"]=values[0];result["kind"]=values[1];result["id"]=values[2];
          if(text)result["text"]=DF2UTF(*text);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-skills-page-probe") {
          if(parameters.size()!=3)return CR_WRONG_USAGE;
          int32_t id=-1,page=-1;
          const auto a=std::from_chars(parameters[1].data(),parameters[1].data()+parameters[1].size(),id);
          const auto b=std::from_chars(parameters[2].data(),parameters[2].data()+parameters[2].size(),page);
          if(a.ec!=std::errc{}||a.ptr!=parameters[1].data()+parameters[1].size()||b.ec!=std::errc{}||b.ptr!=parameters[2].data()+parameters[2].size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto value=df3d_creature::skillsPageProbe(df::unit::find(id),page);if(!value)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["unit_id"]=id;result["page"]=page;
          const auto append=[&](const char* key,const auto& rows){result[key]=Json::Value(Json::arrayValue);for(auto v:rows)result[key].append(v);};
          append("skills",value->skills);append("values",value->values);append("rust_values",value->rustValues);
          append("knowledge_types",value->knowledgeTypes);append("knowledge_ids",value->knowledgeIds);append("knowledge_bits",value->knowledgeBits);
          if(!df3d_creature::skillsCaptionReady())return CR_FAILURE;
          auto* source=df::unit::find(id);result["captions"]=Json::Value(Json::arrayValue);
          result["colors"]=Json::Value(Json::arrayValue);
          for(size_t i=0;i<value->skills.size();++i){
            result["captions"].append(DF2UTF(df3d_creature::nativeSkillCaption(value->skills[i],value->values[i],source->race,source->caste)));
            const auto color=df3d_creature::nativeSkillColor(*source,value->skills[i]);if(!color)return CR_FAILURE;
            Json::Value channels(Json::arrayValue);for(auto channel:*color)channels.append(channel);result["colors"].append(channels);
          }
          for(size_t i=0;i<value->knowledgeTypes.size();++i)result["captions"].append(DF2UTF(df3d_creature::nativeKnowledgeCaption(value->knowledgeTypes[i],value->knowledgeIds[i],value->knowledgeBits[i])));
          result["subtitles"]=Json::Value(Json::arrayValue);
          for(size_t i=0;i<value->knowledgeTypes.size();++i)result["subtitles"].append(DF2UTF(df3d_creature::nativeKnowledgeCategory(value->knowledgeTypes[i],value->knowledgeIds[i])));
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-health-page-probe") {
          if(parameters.size()!=3)return CR_WRONG_USAGE;
          int32_t id=-1,page=-1;
          const auto a=std::from_chars(parameters[1].data(),parameters[1].data()+parameters[1].size(),id);
          const auto b=std::from_chars(parameters[2].data(),parameters[2].data()+parameters[2].size(),page);
          if(a.ec!=std::errc{}||a.ptr!=parameters[1].data()+parameters[1].size()||b.ec!=std::errc{}||b.ptr!=parameters[2].data()+parameters[2].size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto rows=df3d_creature::healthPageProbe(df::unit::find(id),page);if(!rows)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["unit_id"]=id;result["page"]=page;result["rows"]=Json::Value(Json::arrayValue);
          for(const auto& row:*rows)result["rows"].append(DF2UTF(row));
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-items-description-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto rows=df3d_creature::inventoryDescriptions(df::unit::find(id));if(!rows)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["unit_id"]=id;result["rows"]=Json::Value(Json::arrayValue);
          for(const auto& row:*rows) {
            Json::Value value(Json::objectValue);value["id"]=row.id;
            value["caption"]=DF2UTF(row.caption);value["role"]=DF2UTF(row.role);
            value["indicator"]=row.indicator;
            value["contents"]=Json::Value(Json::arrayValue);
            for(const auto& child:row.contents) {
              Json::Value nested(Json::objectValue);nested["kind"]=child.kind;nested["id"]=child.id;
              nested["caption"]=DF2UTF(child.caption);value["contents"].append(nested);
            }
            result["rows"].append(value);
          }
          const auto spatters=df3d_creature::inventorySpatters(df::unit::find(id));if(!spatters)return CR_FAILURE;
          result["spatters"]=Json::Value(Json::arrayValue);
          for(const auto& row:*spatters) {
            Json::Value value(Json::objectValue);value["source_index"]=row.sourceIndex;value["body_part"]=row.bodyPart;
            value["caption"]=DF2UTF(row.caption);value["body_part_caption"]=DF2UTF(row.bodyPartCaption);
            result["spatters"].append(value);
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-expel-eligible-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto eligible=df3d_creature::expelEligible(df::unit::find(id));if(!eligible)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["unit_id"]=id;result["eligible"]=*eligible;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-expel-group-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto group=df3d_creature::expelGroup(df::unit::find(id));
          if(!group)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["unit_id"]=id;result["reason"]=group->reason;
          result["units"]=Json::Value(Json::arrayValue);for(auto value:group->units)result["units"].append(value);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-follow-position-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto position=df3d_creature::followPosition(df::unit::find(id));
          if(!position)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["unit_id"]=id;result["valid"]=position->isValid();
          result["x"]=position->x;result["y"]=position->y;result["z"]=position->z;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="item-position-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto position=df3d_production::itemPosition(df::item::find(id));
          if(!position)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["item_id"]=id;result["valid"]=position->isValid();
          result["x"]=position->x;result["y"]=position->y;result["z"]=position->z;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-header-name-write-probe" || parameters[0]=="unit-header-name-edit-read") {
          const bool read=parameters[0]=="unit-header-name-edit-read";
          if(read?parameters.size()!=2:((parameters.size()!=4 && parameters.size()!=5) ||
             (parameters[2]!="nickname" && parameters[2]!="profession")))return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          auto* unit=df::unit::find(id);
          const auto before=df3d_creature::headerEditSnapshot(unit);if(!before)return CR_FAILURE;
          if(read) {
            Json::Value result;result["revision"]=Json::UInt64(before->revision);
            result["nickname"]=DF2UTF(before->nickname);result["profession"]=DF2UTF(before->profession);
            result["historical_figure_id"]=before->histFigureId;result["has_figure"]=before->hasFigure;
            result["figure_nickname"]=DF2UTF(before->figureNickname);
            out.print("{}",Json::FastWriter().write(result));return CR_OK;
          }
          const auto bytes=UTF2DF(parameters[3]);
          if(DF2UTF(bytes)!=parameters[3])return CR_FAILURE;
          auto expected=before->revision;
          if(parameters.size()==5) {
            const auto& rawRevision=parameters[4];
            const auto parsedRevision=std::from_chars(rawRevision.data(),rawRevision.data()+rawRevision.size(),expected);
            if(parsedRevision.ec!=std::errc{} || parsedRevision.ptr!=rawRevision.data()+rawRevision.size())return CR_WRONG_USAGE;
          }
          const auto result=df3d_creature::finishHeaderNameEdit(*before,expected,parameters[2]=="profession",bytes,
            [&](const std::string& owned){return df3d_creature::setHeaderCustomName(unit,parameters[2]=="profession",owned);},
            [&]{return df3d_creature::headerEditSnapshot(df::unit::find(id));});
          Json::Value output;output["outcome"]=int(result.outcome);output["mutated"]=result.mutated;
          if(result.receipt)output["revision"]=Json::UInt64(result.receipt->revision);
          out.print("{}",Json::FastWriter().write(output));
          return result.outcome==df3d_creature::HeaderEditOutcome::Completed?CR_OK:CR_FAILURE;
        }
        if(parameters[0]=="unit-header-activity-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto row=df3d_creature::headerActivity(df::unit::find(id));if(!row)return CR_FAILURE;
          Json::Value result;result["text"]=DF2UTF(row->text);result["color"]=row->foreground+(row->bright?8:0);result["background"]=row->background;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-customize-captions-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto row=df3d_creature::customizeCaptions(df::unit::find(id));if(!row)return CR_FAILURE;
          Json::Value result;result["name"]=DF2UTF(row->name);result["profession"]=DF2UTF(row->profession);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-header-name-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto row=df3d_creature::headerName(df::unit::find(id));if(!row)return CR_FAILURE;
          Json::Value result;result["combined"]=DF2UTF(row->combined);result["name"]=DF2UTF(row->name);result["profession"]=DF2UTF(row->profession);
          result["translated_name"]=DF2UTF(row->translated);
          result["effect"]=int(row->color.effect);result["source"]=int(row->color.source);
          for(auto c:row->color.color)result["color"].append(int(c));for(auto c:row->color.alternate)result["alternate"].append(int(c));
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-header-status-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto row=df3d_creature::headerStatus(df::unit::find(id));if(!row)return CR_FAILURE;
          Json::Value result;result["text"]=DF2UTF(row->text);result["color"]=row->color;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-header-position-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto row=df3d_creature::headerPositionTitle(df::unit::find(id));if(!row)return CR_FAILURE;
          Json::Value result;result["position_id"]=row->positionId;result["entity_id"]=row->entityId;
          result["spouse"]=row->spouse;result["text"]=DF2UTF(row->text);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-health-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto rows=df3d_creature::overviewHealth(df::unit::find(id));if(!rows)return CR_FAILURE;
          Json::Value result(Json::arrayValue);
          for(const auto& row:*rows){Json::Value value;value["text"]=row.text;value["color"]=row.color;value["flash"]=row.flash;result.append(value);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="unit-room-requirements-probe"||parameters[0]=="unit-room-values-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto values=parameters[0]=="unit-room-values-probe"?df3d_creature::actualRooms(df::unit::find(id)):df3d_creature::requiredRooms(df::unit::find(id));if(!values)return CR_FAILURE;
          Json::Value result(Json::arrayValue);for(auto value:*values)result.append(value);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="box-description-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          auto* item=df::item::find(id);
          if(!df3d_production::boxItemDescriptionDispatch(item))return CR_FAILURE;
          const auto description=df3d_production::itemDescription(item);if(!description)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["item_id"]=id;result["description"]=DF2UTF(*description);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="item-carrier-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          const auto carrier=df3d_production::itemCarrier(df::item::find(id));if(!carrier)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["item_id"]=id;result["kind"]=carrier->kind;
          result["id"]=carrier->id;result["item_type"]=carrier->itemType;result["name"]=DF2UTF(carrier->name);
          if(carrier->appearance){const auto& a=*carrier->appearance;Json::Value look(Json::objectValue);look["material_token"]=DF2UTF(a.materialToken);look["subtype_raw"]=DF2UTF(a.subtypeRaw);look["color_token"]=DF2UTF(a.colorToken);look["stack"]=a.stack;look["flags"]=a.flags;if(a.instrumentFamily>=0){Json::Value instrument(Json::objectValue);instrument["family"]=a.instrumentFamily;instrument["placed"]=a.instrumentPlaced;look["instrument"]=instrument;}result["appearance"]=look;}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="item-sheet-contents-probe") {
          if(parameters.size()!=2 || !state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int32_t id=-1;const auto& raw=parameters[1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          const auto contents=df3d_production::itemSheetContents(df::item::find(id));if(!contents)return CR_FAILURE;
          Json::Value result(Json::objectValue),rows(Json::arrayValue);result["item_id"]=id;
          for(const auto& value:*contents) {
            Json::Value row(Json::objectValue);row["kind"]=value.kind;row["id"]=value.id;row["caption"]=DF2UTF(value.caption);
            if(value.item) {
              const auto& item=*value.item;row["item_type"]=item.itemType;row["flags"]=item.flags;
              row["can_dump"]=item.canDump;row["can_melt"]=item.canMelt;
              row["material_token"]=DF2UTF(item.materialToken);row["subtype_raw"]=DF2UTF(item.subtypeRaw);
              row["stack"]=value.appearance->stack;
            }
            rows.append(row);
          }
          result["rows"]=rows;out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="item-container-contents-probe") {
          if(parameters.size()!=2 || !state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int32_t id=-1;const auto& raw=parameters[1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          const auto value=df3d_production::itemContainerContents(df::item::find(id));if(!value)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["container"]=value->container;
          Json::Value entries(Json::arrayValue);
          for(const auto& entry:value->entries) {
            Json::Value row(Json::objectValue);row["item_type"]=entry.itemType;
            row["material_token"]=entry.materialToken;row["color_token"]=entry.colorToken;
            row["effective_armor_level"]=entry.effectiveArmorLevel;
            row["metal"]=entry.metal;row["coal"]=entry.coal;row["contains_powder"]=entry.containsPowder;
            row["rolls_sheets"]=entry.rollsSheets;row["protects_folded_sheets"]=entry.protectsFoldedSheets;
            row["contains_writing"]=entry.containsWriting;entries.append(row);
          }
          result["entries"]=entries;out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="item-ammunition-assignment-probe") {
          if(parameters.size()!=2 || !state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int32_t id=-1;const auto& raw=parameters[1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          const auto value=df3d_production::itemAmmunitionAssignment(df::item::find(id));if(!value)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["kind"]=value->kind;result["squad_id"]=value->squadId;result["caption"]=DF2UTF(value->caption);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="item-uses-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          auto value=df3d_production::itemUses(df::item::find(id));if(!value)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["description"]=DF2UTF(value->description);
          result["uses"]=Json::Value(Json::arrayValue);
          for(const auto& use:value->rows){Json::Value row(Json::objectValue);
            row["caption"]=DF2UTF(use.caption);row["reaction"]=use.reaction;result["uses"].append(row);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="item-portrait-probe") {
          if(parameters.size()!=2 || !state.mapLoaded || df3d_session::saving())return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          df3d_appearance::Result recipe;
          if(!df3d_appearance::resolveCritterItemPortrait(df::item::find(id),recipe))return CR_FAILURE;
          Json::Value result(Json::objectValue);result["layers"]=Json::Value(Json::arrayValue);
          for(const auto& layer:recipe.layers) {
            Json::Value row(Json::objectValue);row["page"]=df3d_appearance::pageToken(layer.page);
            row["x"]=layer.tileX;row["y"]=layer.tileY;row["width"]=layer.cellsX;row["height"]=layer.cellsY;
            row["offset_x"]=layer.offX;row["offset_y"]=layer.offY;row["palette_row"]=layer.row;
            result["layers"].append(row);
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="item-inspect-probe"||parameters[0]=="item-flag-probe") {
          using namespace df3d_production;
          const bool edit=parameters[0]=="item-flag-probe";
          if(parameters.size()!=(edit?5:2))return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          auto value=observeItem(df::item::find(id));if(!value)return CR_FAILURE;
          Json::Value result(Json::objectValue);
          if(edit) {
            BuildingItemAction action;
            if(parameters[2]=="forbid")action=BuildingItemAction::Forbid;
            else if(parameters[2]=="dump")action=BuildingItemAction::Dump;
            else if(parameters[2]=="melt")action=BuildingItemAction::Melt;
            else if(parameters[2]=="hidden")action=BuildingItemAction::Hidden;
            else return CR_WRONG_USAGE;
            if(parameters[3]!="0"&&parameters[3]!="1")return CR_WRONG_USAGE;
            uint64_t expected=0;const auto& revision=parameters[4];
            const auto read=std::from_chars(revision.data(),revision.data()+revision.size(),expected);
            if(read.ec!=std::errc{}||read.ptr!=revision.data()+revision.size()||!expected||expected>INT64_MAX)return CR_WRONG_USAGE;
            const auto changed=finishItemEdit(*value,expected,action,parameters[3]=="1",
              [&]{return setBuildingItemFlag(df::item::find(id),action,parameters[3]=="1");},
              [&]{return observeItem(df::item::find(id));});
            result["outcome"]=static_cast<int>(changed.outcome);result["mutated"]=changed.mutated;
            value=changed.receipt;
          }
          if(value) {
            const auto& item=value->item;Json::Value snapshot(Json::objectValue);
            snapshot["id"]=item.id;snapshot["revision"]=std::to_string(value->revision);
            if(value->appearance){const auto& a=*value->appearance;Json::Value look(Json::objectValue);look["material_token"]=DF2UTF(a.materialToken);look["subtype_raw"]=DF2UTF(a.subtypeRaw);look["color_token"]=DF2UTF(a.colorToken);look["stack"]=a.stack;look["flags"]=a.flags;if(a.instrumentFamily>=0){Json::Value instrument(Json::objectValue);instrument["family"]=a.instrumentFamily;instrument["placed"]=a.instrumentPlaced;look["instrument"]=instrument;}snapshot["appearance"]=look;}
            snapshot["caption"]=DF2UTF(item.caption);snapshot["description"]=DF2UTF(value->description);snapshot["weight"]=DF2UTF(value->weight);
            snapshot["item_type"]=item.itemType;snapshot["material_token"]=DF2UTF(item.materialToken);
            snapshot["flags"]=Json::UInt(item.flags);snapshot["forbid"]=item.forbid;snapshot["dump"]=item.dump;
            snapshot["melt"]=item.melt;snapshot["hidden"]=item.hidden;snapshot["can_dump"]=item.canDump;snapshot["can_melt"]=item.canMelt;
            const auto link=[](const std::optional<ItemLocationLink>& value) {
              Json::Value result(Json::nullValue);if(value){result["id"]=value->id;result["type"]=value->type;result["name"]=DF2UTF(value->name);}return result;
            };
            snapshot["holder"]=link(value->buildingHolder);snapshot["stockpile"]=link(value->stockpile);snapshot["stockpile_categories"]=value->stockpileCategories;
            if(value->carrier){const auto& c=*value->carrier;Json::Value carrier(Json::objectValue);carrier["kind"]=c.kind;carrier["id"]=c.id;carrier["item_type"]=c.itemType;carrier["name"]=DF2UTF(c.name);if(c.appearance){const auto& a=*c.appearance;Json::Value look(Json::objectValue);look["material_token"]=DF2UTF(a.materialToken);look["subtype_raw"]=DF2UTF(a.subtypeRaw);look["color_token"]=DF2UTF(a.colorToken);look["stack"]=a.stack;look["flags"]=a.flags;if(a.instrumentFamily>=0){Json::Value instrument(Json::objectValue);instrument["family"]=a.instrumentFamily;instrument["placed"]=a.instrumentPlaced;look["instrument"]=instrument;}carrier["appearance"]=look;}snapshot["carrier"]=carrier;}
            result["snapshot"]=std::move(snapshot);
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="farm-item-header-read"||parameters[0]=="farm-item-description-probe") {
          if(parameters.size()!=3)return CR_WRONG_USAGE;
          int32_t ids[2]{};
          for(size_t i=0;i<2;++i) {
            const auto& raw=parameters[i+1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),ids[i]);
            if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||ids[i]<0)return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          auto* farm=virtual_cast<df::building_farmplotst>(df::building::find(ids[0]));
          auto* tile=farm?Maps::getTileDesignation(farm->centerx,farm->centery,farm->z):nullptr;
          if(!tile||tile->bits.hidden)return CR_FAILURE;
          df::item* item=nullptr;
          for(auto* held:farm->contained_items)if(held&&held->item&&held->item->id==ids[1])item=held->item;
          if(!item)return CR_FAILURE;
          const auto caption=df3d_production::buildingItemCaption(item);
          const auto weight=df3d_production::itemWeightCaption(item);
          if(!caption||!weight)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["item_id"]=ids[1];
          result["caption"]=DF2UTF(*caption);result["weight"]=DF2UTF(*weight);
          const auto holder=df3d_production::itemBuildingHolder(item);if(!holder)return CR_FAILURE;
          result["holder"]=Json::Value(Json::nullValue);
          if(holder->id>=0) {
            Json::Value link(Json::objectValue);link["building_id"]=holder->id;
            link["building_type"]=holder->type;link["name"]=DF2UTF(holder->name);
            result["holder"]=std::move(link);
          }
          if(parameters[0]=="farm-item-description-probe") {
            const auto description=df3d_production::itemDescription(item);
            if(!description)return CR_FAILURE;
            result["description"]=DF2UTF(*description);
          }
          // Native lazy weight formatting can change contents revision. Observe
          // authoritative row facts only after all semantic formatting completes.
          const auto contents=df3d_production::buildingContents(farm);if(!contents)return CR_FAILURE;
          const df3d_production::BuildingContentsRow* observed=nullptr;
          for(const auto& row:contents->rows)if(row.id==ids[1]){observed=&row;break;}
          if(!observed)return CR_FAILURE;
          result["contents_revision"]=std::to_string(contents->revision);
          result["building_id"]=contents->buildingId;result["completed"]=contents->completed;
          result["removing"]=contents->removing;
          Json::Value facts(Json::objectValue);facts["item_type"]=observed->itemType;
          facts["material_token"]=DF2UTF(observed->materialToken);facts["subtype_raw"]=DF2UTF(observed->subtypeRaw);
          facts["forbid"]=observed->forbid;facts["dump"]=observed->dump;
          facts["melt"]=observed->melt;facts["hidden"]=observed->hidden;
          facts["can_dump"]=observed->canDump;facts["can_melt"]=observed->canMelt;
          result["facts"]=std::move(facts);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="work-order-filter-choices-probe") {
          if(parameters.size()!=3 || !df::global::world)return CR_WRONG_USAGE;
          int kind=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),kind);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || kind<0 || kind>2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& rawId=parameters[2];
          const auto parsedId=std::from_chars(rawId.data(),rawId.data()+rawId.size(),id);
          if(parsedId.ec!=std::errc{} || parsedId.ptr!=rawId.data()+rawId.size() || id<0)return CR_WRONG_USAGE;
          const auto& all=df::global::world->manager_orders.all;
          const auto found=std::find_if(all.begin(),all.end(),[&](const auto* row){return row && row->id==id;});
          if(found==all.end())return CR_FAILURE;
          const auto choices=df3d_production::nativeWorkOrderFilterChoices(**found,kind);if(!choices)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["rows"]=Json::Value(Json::arrayValue);
          for(const auto& row:*choices) {
            Json::Value value;value["search"]=DF2UTF(row.search);
            value["item_type"]=row.itemType;value["item_subtype"]=row.itemSubtype;
            value["mat_type"]=row.materialType;value["mat_index"]=row.materialIndex;value["mat_state"]=row.materialState;
            if(row.trait) {
              const auto& t=*row.trait;value["caption"]=DF2UTF(t.display_string);
              value["flag"]=t.flg;value["flag_word"]=t.flgn;
              value["reaction_class"]=t.reaction_class;value["reaction_product"]=t.reaction_product_class;
              value["metal_ore"]=t.metal_ore;value["reaction_index"]=t.contains_reaction_index;
              value["reagent_index"]=t.contains_reagent_index;value["tool_use"]=int(t.tool_use);value["dye_color"]=t.dye_color;
            }
            result["rows"].append(value);
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="work-order-suggestions-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0 || !df::global::world)return CR_WRONG_USAGE;
          const auto& all=df::global::world->manager_orders.all;
          const auto it=std::find_if(all.begin(),all.end(),[&](const auto* row){return row && row->id==id;});
          if(it==all.end())return CR_FAILURE;
          const auto rows=df3d_production::nativeWorkOrderSuggestions(**it);if(!rows)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["rows"]=Json::Value(Json::arrayValue);
          for(const auto& row:*rows) {
            Json::Value value;
            const auto caption=df3d_production::nativeWorkOrderConditionCaption(row);if(!caption)return CR_FAILURE;
            value["item_caption"]=DF2UTF(*caption);
            value["compare"]=int(row.compare_type);value["threshold"]=row.compare_val;
            value["item_type"]=int(row.item_type);value["item_subtype"]=row.item_subtype;
            value["mat_type"]=row.mat_type;value["mat_index"]=row.mat_index;
            value["flags1"]=row.flags1.whole;value["flags2"]=row.flags2.whole;value["flags3"]=row.flags3.whole;
            value["flags4"]=row.flags4;value["flags5"]=row.flags5;
            value["reaction_class"]=row.reaction_class;value["material_product"]=row.has_material_reaction_product;
            value["metal_ore"]=row.metal_ore;value["min_dimension"]=row.min_dimension;
            value["reaction_id"]=row.reaction_id;value["tool_use"]=int(row.has_tool_use);value["dye_color"]=row.dye_color;
            value["contains"]=Json::Value(Json::arrayValue);for(auto id:row.contains)value["contains"].append(id);
            result["rows"].append(value);
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-assignments-read") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          const auto entries=df3d_area::observeNativeUnitAssignments(id);if(!entries)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["id"]=id;result["entries"]=Json::Value(Json::arrayValue);
          for(const auto& e:*entries) {Json::Value value(Json::objectValue);value["kind"]=int(e.kind);value["id"]=e.id;value["type"]=e.type;value["subtype"]=e.subtype;value["custom"]=e.custom;value["name"]=e.name;value["custom_code"]=e.customCode;result["entries"].append(value);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-specialization") {
          if(parameters.size()!=2 && parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          Json::Value result(Json::objectValue);result["id"]=id;
          if(parameters.size()==4) {
            uint64_t revision=0;const auto& token=parameters[2];
            const auto number=std::from_chars(token.data(),token.data()+token.size(),revision);
            if(number.ec!=std::errc{} || number.ptr!=token.data()+token.size() || (parameters[3]!="0" && parameters[3]!="1"))return CR_WRONG_USAGE;
            result["outcome"]=int(df3d_residents::setSpecialization(id,revision,parameters[3]=="1"));
          }
          auto* unit=df::unit::find(id);const auto state=df3d_residents::specialization(unit);
          if(!state)return CR_FAILURE;
          result["only_assigned"]=state->onlyAssigned;result["revision"]=std::to_string(state->revision);
          result["labors"]=Json::Value(Json::arrayValue);for(bool labor:unit->status.labors)result["labors"].append(labor);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-row-read") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t values[3];
          for(size_t i=0;i<3;++i) {
            const auto& raw=parameters[i+1];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(values[2]<0 || values[2]>1)return CR_WRONG_USAGE;
          const auto row=df3d_residents::rowText(df::unit::find(values[0]),values[1],values[2]!=0);
          if(!row)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["id"]=values[0];
          result["combined"]=DF2UTF(row->name.combined);result["name"]=DF2UTF(row->name.name);
          result["profession"]=DF2UTF(row->name.profession);
          result["first_line"]=DF2UTF(row->name.firstLine);result["second_line"]=DF2UTF(row->name.secondLine);
          auto& color=result["name_color"];color["effect"]=int(row->nameColor.effect);color["source"]=int(row->nameColor.source);
          for(auto c:row->nameColor.color)color["color"].append(int(c));
          for(auto c:row->nameColor.alternate)color["alternate"].append(int(c));
          auto& activity=result["activity"];activity["caption"]=DF2UTF(row->activity.caption);
          activity["fg"]=row->activity.foreground;activity["bg"]=row->activity.background;
          activity["bright"]=row->activity.bright;
          result["happiness"]=int(row->happiness);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-job-material-copy-probe") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t values[3];
          for(size_t i=1;i<parameters.size();++i) {
            const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<0)return CR_WRONG_USAGE;
          }
          const auto* unit=df::unit::find(values[0]);if(!unit || !unit->job.current_job)return CR_FAILURE;
          const auto& source=*unit->job.current_job;
          const auto before=df3d_production::nativeJobSettings(source,values[1]);if(!before)return CR_FAILURE;
          // Diagnostic edits only independent value/requirement storage. World
          // membership, jobs, reservations and native menus remain untouched.
          std::vector<df::job_item> inputs;inputs.reserve(source.job_items.elements.size());
          for(const auto* item:source.job_items.elements)inputs.push_back(*item);
          df::job copy=source;copy.job_items.elements.clear();for(auto& item:inputs)copy.job_items.elements.push_back(&item);
          const df3d_production::JobSettingsTarget target{source.id,before->buildingId};
          const auto apply=[&](const auto& identity,uint64_t revision,uint64_t choices,int32_t choice) {
            return df3d_production::applyJobSetting(copy,identity,revision,values[1],choices,choice);
          };
          using Outcome=df3d_production::JobSettingsOutcome;
          Json::Value result;
          result["stale_revision_rejected"]=apply(target,before->revision^1,before->choicesRevision,values[2])!=Outcome::Applied;
          result["stale_choices_rejected"]=apply(target,before->revision,before->choicesRevision^1,values[2])!=Outcome::Applied;
          result["wrong_job_rejected"]=apply(df3d_production::JobSettingsTarget{-1,target.buildingId},before->revision,before->choicesRevision,values[2])!=Outcome::Applied;
          result["wrong_holder_rejected"]=apply(df3d_production::JobSettingsTarget{target.jobId,-1},before->revision,before->choicesRevision,values[2])!=Outcome::Applied;
          result["missing_choice_rejected"]=apply(target,before->revision,before->choicesRevision,INT32_MAX)!=Outcome::Applied;
          const auto unchanged=df3d_production::nativeJobSettings(copy,values[1]);
          result["rejections_unchanged"]=unchanged && unchanged->revision==before->revision && unchanged->choicesRevision==before->choicesRevision;
          result["applied"]=apply(target,before->revision,before->choicesRevision,values[2])==Outcome::Applied;
          auto& after=result["after"];after["job_id"]=copy.id;after["mat_type"]=copy.mat_type;after["mat_index"]=copy.mat_index;
          after["inputs"]=Json::Value(Json::arrayValue);
          for(const auto& item:inputs) {
            Json::Value row;row["item_type"]=int(item.item_type);row["item_subtype"]=item.item_subtype;
            row["mat_type"]=item.mat_type;row["mat_index"]=item.mat_index;row["quantity"]=item.quantity;
            row["flags1"]=item.flags1.whole;row["flags2"]=item.flags2.whole;row["flags3"]=item.flags3.whole;
            row["details_flags"]=item.job_details_flags.whole;row["saved_type"]=item.job_details_mat_type;
            row["saved_index"]=item.job_details_mat_index;row["saved_flags2"]=item.job_details_item_flags2.whole;
            after["inputs"].append(row);
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-job-art-draft-commit-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          const auto* unit=df::unit::find(id);if(!unit || !unit->job.current_job)return CR_FAILURE;
          const auto& source=*unit->job.current_job;const auto root=df3d_production::nativeJobSettings(source,-1,{},false);if(!root)return CR_FAILURE;
          int32_t option=-1;for(size_t i=0;i<root->options.size();++i)if(root->options[i].kind==1 || root->options[i].kind==3){option=int32_t(i);break;}if(option<0)return CR_FAILURE;
          auto draft=df3d_production::WorkOrderArtDraft::create();if(!draft)return CR_FAILURE;
          auto choices=draft->choices(7,{});if(!choices || choices->empty() || !draft->generateName())return CR_FAILURE;
          df3d_production::WorkOrderArtDraftValue value;value.name=draft->image().name;
          value.elements.push_back({7,choices->front().first,choices->front().second,1});
          std::vector<df::job_item> inputs;for(const auto* item:source.job_items.elements){if(!item)return CR_FAILURE;inputs.push_back(*item);}
          df::job copy=source;copy.job_items.elements.clear();for(auto& input:inputs)copy.job_items.elements.push_back(&input);
          const auto state=[](const df::job& job){Json::Value v;v["type"]=int(job.art_spec.type);v["id"]=job.art_spec.id;v["subid"]=job.art_spec.subid;v["specdata"]=job.specdata.hist_figure_id;v["requirements"]=Json::UInt(job.job_items.elements.size());return v;};
          const auto before=state(copy);auto& resources=df::global::plotinfo->main.fortress_entity->resources;const auto count=resources.art_image_ids.size();
          using Outcome=df3d_production::JobArtDraftOutcome;
          const df3d_production::JobSettingsTarget target{source.id,root->buildingId};
          const auto apply=[&](df3d_production::JobSettingsTarget t,uint64_t revision,const df3d_production::WorkOrderArtDraftValue& v){return df3d_production::commitJobArtDraft(copy,t,revision,option,v);};
          Json::Value result;result["stale_revision_rejected"]=apply(target,root->revision==1?2:1,value)==Outcome::Stale;
          result["wrong_job_rejected"]=apply({source.id^1,root->buildingId},root->revision,value)==Outcome::Stale;
          result["wrong_holder_rejected"]=apply({source.id,root->buildingId^1},root->revision,value)==Outcome::Stale;
          auto invalid=value;invalid.elements[0].id=INT32_MAX;
          result["invalid_element_rejected"]=apply(target,root->revision,invalid)==Outcome::Rejected;
          result["rejections_unchanged"]=state(copy)==before && resources.art_image_ids.size()==count;
          result["applied"]=apply(target,root->revision,value)==Outcome::Applied;
          result["after"]=state(copy);result["source_unchanged"]=state(source)==before;
          result["one_registered"]=resources.art_image_ids.size()==count+1 && resources.art_image_ids.back()==copy.art_spec.id && resources.art_image_subids.back()==copy.art_spec.subid;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-job-art-draft-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          const auto* unit=df::unit::find(id);if(!unit || !unit->job.current_job)return CR_FAILURE;
          const auto& job=*unit->job.current_job;
          const auto read=[&](int16_t page,df3d_production::WorkOrderArtDraftValue value,uint8_t action,
              const std::optional<df3d_production::WorkOrderArtDraftElementValue>& element=std::nullopt,uint64_t receipt=0) {
            return df3d_production::nativeJobArtDraftPage(job,page,std::move(value),action,element,std::nullopt,-1,{},0,receipt,118);
          };
          auto root=read(6,{},0);auto choices=read(7,{},0);
          if(!root || !choices || choices->page.rows.empty())return CR_FAILURE;
          const auto& row=choices->page.rows.front();
          df3d_production::WorkOrderArtDraftElementValue element{7,row.id,row.secondary,1};
          auto populated=read(7,{},1,element);if(!populated || !populated->page.draftDescription)return CR_FAILURE;
          Json::Value result;result["caption"]=DF2UTF(root->page.caption);result["race"]=row.id;result["caste"]=row.secondary;
          result["total"]=choices->page.total;result["rows"]=Json::Value(Json::arrayValue);result["description"]=Json::Value(Json::arrayValue);
          for(const auto& item:root->page.rows)result["rows"].append(DF2UTF(item.caption));
          for(const auto& line:*populated->page.draftDescription)result["description"].append(DF2UTF(line));
          result["stale_list_rejected"]=!read(7,{},0,std::nullopt,choices->page.listRevision==1?2:1);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-job-art-copy-probe") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t values[3]={};
          for(size_t i=1;i<4;++i){const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<(i==1?0:-1))return CR_WRONG_USAGE;}
          const auto* unit=df::unit::find(values[0]);if(!unit || !unit->job.current_job)return CR_FAILURE;
          const auto& source=*unit->job.current_job;const auto root=df3d_production::nativeJobSettings(source,-1,{},false);if(!root)return CR_FAILURE;
          int32_t option=-1;for(size_t i=0;i<root->options.size();++i)if(root->options[i].kind==1 || root->options[i].kind==3){option=int32_t(i);break;}if(option<0)return CR_FAILURE;
          uint64_t listRevision=0;
          if(values[1]==-1){const auto settings=df3d_production::nativeJobSettings(source,option);if(!settings)return CR_FAILURE;listRevision=settings->choicesRevision;}
          else if(values[1]>0){const auto page=df3d_production::nativeJobArtPage(source,int16_t(values[1]));if(!page)return CR_FAILURE;listRevision=page->page.listRevision;}
          std::vector<df::job_item> inputs;for(const auto* item:source.job_items.elements){if(!item)return CR_FAILURE;inputs.push_back(*item);}
          df::job copy=source;copy.job_items.elements.clear();for(auto& input:inputs)copy.job_items.elements.push_back(&input);
          const auto state=[](const df::job& job){Json::Value value;value["type"]=int(job.art_spec.type);value["id"]=job.art_spec.id;value["subid"]=job.art_spec.subid;value["specdata"]=job.specdata.hist_figure_id;value["requirements"]=Json::UInt(job.job_items.elements.size());return value;};
          const auto apply=[&](df3d_production::JobSettingsTarget target,uint64_t revision,uint64_t receipt,int32_t subject) {
            return values[1]==-1?df3d_production::beginJobArt(copy,target,revision,option,receipt):df3d_production::applyJobArtSubject(copy,target,revision,option,values[1],subject,receipt);
          };
          using Outcome=df3d_production::JobSettingsOutcome;
          const df3d_production::JobSettingsTarget target{source.id,root->buildingId};const auto before=state(copy);
          Json::Value result;result["before"]=before;
          result["stale_revision_rejected"]=apply(target,root->revision==1?2:1,listRevision,values[2])!=Outcome::Applied;
          result["wrong_job_rejected"]=apply({source.id+1,root->buildingId},root->revision,listRevision,values[2])!=Outcome::Applied;
          result["wrong_holder_rejected"]=apply({source.id,root->buildingId+1},root->revision,listRevision,values[2])!=Outcome::Applied;
          if(values[1]!=0)result["stale_list_rejected"]=apply(target,root->revision,listRevision==1?2:1,values[2])!=Outcome::Applied;
          if(values[1]!=-1)result["missing_subject_rejected"]=apply(target,root->revision,listRevision,INT32_MAX)!=Outcome::Applied;
          result["rejections_unchanged"]=state(copy)==before;
          result["applied"]=apply(target,root->revision,listRevision,values[2])==Outcome::Applied;
          result["after"]=state(copy);result["source_unchanged"]=state(source)==before;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-job-art-page-probe") {
          if(parameters.size()!=5 && parameters.size()!=6)return CR_WRONG_USAGE;
          int32_t values[4]={};
          for(size_t i=1;i<5;++i) {
            const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<(i==2?-1:0))return CR_WRONG_USAGE;
          }
          if(values[1]>5 || values[3]>1024)return CR_WRONG_USAGE;
          const auto* unit=df::unit::find(values[0]);if(!unit || !unit->job.current_job)return CR_FAILURE;
          const auto& job=*unit->job.current_job;
          const auto query=parameters.size()==6?parameters[5]:std::string{};
          auto observed=df3d_production::nativeJobArtPage(job,int16_t(values[1]),query,uint32_t(values[2]));if(!observed)return CR_FAILURE;
          if(values[3] && !observed->page.rows.empty()) {
            observed=df3d_production::nativeJobArtPage(job,int16_t(values[1]),query,uint32_t(values[2]),observed->page.listRevision,observed->page.rows.front().id,uint16_t(values[3]));
            if(!observed)return CR_FAILURE;
          }
          Json::Value result;result["job_id"]=observed->jobId;result["building_id"]=observed->buildingId;
          const auto& page=observed->page;result["caption"]=DF2UTF(page.caption);result["revision"]=std::to_string(observed->revision);
          result["list_revision"]=std::to_string(page.listRevision);result["total"]=page.total;result["next_cursor"]=page.nextCursor;
          result["rows"]=Json::Value(Json::arrayValue);result["preview"]=Json::Value(Json::arrayValue);
          for(const auto& row:page.rows){Json::Value value;value["id"]=row.id;value["caption"]=DF2UTF(row.caption);if(row.badge)value["badge"]=DF2UTF(*row.badge);result["rows"].append(value);}
          if(page.preview)for(const auto& line:*page.preview)result["preview"].append(DF2UTF(line));
          result["stale_list_rejected"]=values[1]==-1 || !df3d_production::nativeJobArtPage(job,int16_t(values[1]),query,uint32_t(values[2]),page.listRevision==1?2:1);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-job-art-subjects-probe") {
          if(parameters.size()!=3 && parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t id=-1,kind=-1;
          for(size_t i=1;i<3;++i) {
            auto& value=i==1?id:kind;const auto& raw=parameters[i];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || value<0)return CR_WRONG_USAGE;
          }
          const auto* unit=df::unit::find(id);if(!unit || !unit->job.current_job)return CR_FAILURE;
          const auto observed=df3d_production::nativeJobArtSubjects(*unit->job.current_job,kind,parameters.size()==4?parameters[3]:std::string{});
          if(!observed)return CR_FAILURE;
          Json::Value result;result["job_id"]=observed->jobId;result["building_id"]=observed->buildingId;
          result["caption"]=DF2UTF(observed->caption);result["revision"]=std::to_string(observed->subjects.orderRevision);
          result["list_revision"]=std::to_string(observed->subjects.listRevision);result["ids"]=Json::Value(Json::arrayValue);
          for(auto subject:observed->subjects.ids)result["ids"].append(subject);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-job-settings-probe") {
          if(parameters.size()!=2 && parameters.size()!=3)return CR_WRONG_USAGE;
          int32_t id=-1,selected=-1;
          for(size_t i=1;i<parameters.size();++i) {
            auto& value=i==1?id:selected;const auto& raw=parameters[i];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || value<0)return CR_WRONG_USAGE;
          }
          const auto* unit=df::unit::find(id);if(!unit || !unit->job.current_job)return CR_FAILURE;
          const auto observed=df3d_production::nativeJobSettings(*unit->job.current_job,selected);if(!observed)return CR_FAILURE;
          Json::Value result;result["job_id"]=observed->jobId;result["building_id"]=observed->buildingId;
          result["selected"]=observed->selected;result["caption"]=DF2UTF(observed->caption);
          if(observed->currentValue)result["current_value"]=DF2UTF(*observed->currentValue);
          result["revision"]=std::to_string(observed->revision);result["choices_revision"]=std::to_string(observed->choicesRevision);
          result["search"].append(observed->search.x);result["search"].append(observed->search.y);result["search"].append(observed->search.z);
          result["options"]=Json::Value(Json::arrayValue);result["materials"]=Json::Value(Json::arrayValue);
          for(const auto& row:observed->options){Json::Value value;value["kind"]=row.kind;value["index"]=row.index;value["caption"]=DF2UTF(row.caption);result["options"].append(value);}
          for(const auto& row:observed->materials){Json::Value value;value["type"]=row.type;value["index"]=row.index;value["count"]=row.count;value["caption"]=DF2UTF(row.caption);value["id"]=row.id;value["estimated"]=row.estimated;if(row.countCaption)value["count_caption"]=DF2UTF(*row.countCaption);result["materials"].append(value);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-activity-description-probe") {
          if(parameters.size()!=2 && parameters.size()!=3)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          int32_t columns=0;
          if(parameters.size()==3){
            const auto& width=parameters[2];const auto value=std::from_chars(width.data(),width.data()+width.size(),columns);
            if(value.ec!=std::errc{} || value.ptr!=width.data()+width.size() || columns<1 || columns>1024)return CR_WRONG_USAGE;
          }
          const auto description=df3d_residents::activityDescription(df::unit::find(id),columns);
          if(!description)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["id"]=id;
          result["activity_id"]=description->activityId;result["event_id"]=description->eventId;result["event_type"]=description->eventType;
          result["width"]=description->columns;result["max_y"]=description->maxY;
          result["words"]=Json::Value(Json::arrayValue);result["links"]=Json::Value(Json::arrayValue);
          for(const auto& word:description->words){
            Json::Value value(Json::objectValue);value["text"]=DF2UTF(word.text);value["link"]=word.link;value["flags"]=word.flags;
            value["x"]=word.x;value["y"]=word.y;
            value["rgb"]=Json::Value(Json::arrayValue);value["rgb"].append(word.red);value["rgb"].append(word.green);value["rgb"].append(word.blue);
            result["words"].append(value);
          }
          for(const auto& link:description->links){
            Json::Value value(Json::objectValue);value["type"]=link.type;value["id"]=link.id;value["subid"]=link.subid;result["links"].append(value);
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="tasks-action-probe") {
          if(parameters.size()!=6)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving() || !df::global::pause_state || !*df::global::pause_state)return CR_FAILURE;
          const auto action=parameters[1]=="repeat"?df3d_tasks::Action::Repeat:
              parameters[1]=="suspend"?df3d_tasks::Action::Suspend:
              parameters[1]=="cancel"?df3d_tasks::Action::Cancel:df3d_tasks::Action::RemoveWorker;
          if(parameters[1]!="repeat" && parameters[1]!="suspend" && parameters[1]!="remove-worker" && parameters[1]!="cancel")return CR_WRONG_USAGE;
          int32_t values[4];
          for(size_t i=0;i<4;++i){const auto& raw=parameters[i+2];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;}
          if(values[3]!=0 && values[3]!=1)return CR_WRONG_USAGE;
          const auto result=df3d_tasks::apply(action,values[0],values[1],values[2],values[3]!=0);
          out.print("{}\n",static_cast<int>(result));return CR_OK;
        }
        if(parameters[0]=="places-siege-action-probe") {
          if(parameters.size()!=3)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int32_t values[2];
          for(size_t i=0;i<2;++i){const auto& raw=parameters[i+1];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;}
          const auto outcome=df3d_places::siegeAction(values[0],values[1]);
          out.print("{}\n",int(outcome));return CR_OK;
        }
        if(parameters[0]=="places-building-rows-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto rows=df3d_places::buildingRows();if(!rows)return CR_FAILURE;
          Json::Value result(Json::arrayValue);
          for(const auto& entries:*rows){Json::Value list(Json::arrayValue);for(const auto& entry:entries){
            Json::Value row(Json::objectValue);row["id"]=entry.id;row["name"]=DF2UTF(entry.name);
            row["subtitle_location_id"]=entry.subtitleLocationId;row["subtitle"]=DF2UTF(entry.subtitle);row["job_caption"]=DF2UTF(entry.jobCaption);row["additional_jobs"]=entry.additionalJobs;
            row["status_caption"]=DF2UTF(entry.statusCaption);
            row["secondary_status"]=DF2UTF(entry.secondaryStatus);
            row["status_overlay"]=DF2UTF(entry.statusOverlay);
            row["operator_caption"]=DF2UTF(entry.operatorCaption);row["siege_action"]=entry.siegeAction;
            if(entry.appearance){const auto& recipe=*entry.appearance;auto& art=row["appearance"];
              art["pages"]=Json::Value(Json::arrayValue);art["palettes"]=Json::Value(Json::arrayValue);art["layers"]=Json::Value(Json::arrayValue);
              for(const auto& name:recipe.pages)art["pages"].append(name);
              for(const auto& name:recipe.palettes)art["palettes"].append(name);
              for(const auto& layer:recipe.layers){Json::Value values(Json::arrayValue);for(auto value:layer)values.append(value);art["layers"].append(values);}}
            row["position"]=Json::Value(Json::arrayValue);for(auto v:{entry.position.x,entry.position.y,entry.position.z})row["position"].append(v);
            list.append(row);}result.append(list);}
          out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
        }
        if(parameters[0]=="item-legwear-probe") {
          if(parameters.size()!=2 || !state.mapLoaded || df3d_session::saving())return CR_WRONG_USAGE;
          try {
            const auto tile=df3d_production::legwearOriginalTile(df::item::find(std::stoi(parameters[1])));
            if(!tile)return CR_FAILURE;
            Json::Value result;result["tile"]=*tile;
            out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
          }catch(const std::exception&){return CR_FAILURE;}
        }
        if(parameters[0]=="item-craft-gem-probe") {
          if(parameters.size()!=2 || !state.mapLoaded || df3d_session::saving())return CR_WRONG_USAGE;
          try {
            const auto color=df3d_production::craftGemColor(df::item::find(std::stoi(parameters[1])));
            if(!color)return CR_FAILURE;
            Json::Value result;result["color"]=*color;
            out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
          }catch(const std::exception&){return CR_FAILURE;}
        }
        if(parameters[0]=="nobles-symbol-text-probe") {
          if(parameters.size()!=6)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          try {
            const df3d_nobles::OfficeKey key{std::stoi(parameters[1]),std::stoi(parameters[2]),std::stoi(parameters[3])};
            if(!df3d_nobles::ready())return CR_FAILURE;
            df3d_nobles::Context owned(reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr)));
            if(!df3d_nobles::prepareDraft(owned,{}) || !df3d_nobles::projectSymbols(owned,key))return CR_FAILURE;
            const auto rows=df3d_nobles::symbolDisplay(owned,std::stoul(parameters[4]),std::stoul(parameters[5]));if(!rows)return CR_FAILURE;
            Json::Value result(Json::arrayValue);
            for(const auto& entry:*rows){Json::Value row;row["item_id"]=entry.itemId;row["caption"]=DF2UTF(entry.caption);
              row["office"]=DF2UTF(entry.officeCaption);row["value"]=DF2UTF(entry.valueCaption);result.append(row);}
            out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
          }catch(const std::exception&){return CR_FAILURE;}
        }
        if(parameters[0]=="nobles-symbol-name-probe" || parameters[0]=="nobles-symbol-name-edit-probe") {
          const bool edit=parameters[0]=="nobles-symbol-name-edit-probe";
          if(parameters.size()!=(edit?12:5))return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          try {
            const df3d_nobles::OfficeKey key{std::stoi(parameters[1]),std::stoi(parameters[2]),std::stoi(parameters[3])};
            const auto id=std::stoi(parameters[4]);
            if(edit) {
              const auto mode=std::stoi(parameters[6]);if(mode<0 || mode>3)return CR_WRONG_USAGE;
              out.print("{}\n",int(df3d_nobles::editSymbolName(key,id,std::stoull(parameters[5]),df3d_area::LocationNameEdit(mode),
                std::stoi(parameters[7]),std::stoi(parameters[8]),std::stoi(parameters[9]),std::stoi(parameters[10]),parameters[11])));return CR_OK;
            }
            const auto name=df3d_nobles::observeSymbolName(key,id);if(!name)return CR_FAILURE;
            Json::Value result;result["revision"]=std::to_string(name->revision);result["native"]=DF2UTF(name->nativeHeader);result["english"]=DF2UTF(name->englishHeader);
            result["words"]=Json::Value(Json::arrayValue);for(auto v:name->value.words)result["words"].append(v);
            result["parts"]=Json::Value(Json::arrayValue);for(auto v:name->value.parts)result["parts"].append(v);
            result["first_name"]=DF2UTF(name->value.firstNameCp437);result["nickname"]=DF2UTF(name->value.nicknameCp437);
            result["language"]=name->value.language;result["type"]=name->value.type;result["has_name"]=name->value.hasName;
            out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
          }catch(const std::exception&){return CR_FAILURE;}
        }
        if(parameters[0]=="nobles-symbol-apply-probe" || parameters[0]=="nobles-symbol-continue-probe") {
          const bool continuation=parameters[0]=="nobles-symbol-continue-probe";
          const size_t start=continuation?5:4;
          if(parameters.size()<start+2 || (parameters.size()-start)%2)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving() || !df3d_nobles::symbolApplyReady())return CR_FAILURE;
          try {
            const df3d_nobles::OfficeKey key{std::stoi(parameters[1]),std::stoi(parameters[2]),std::stoi(parameters[3])};
            df3d_nobles::Context owned(reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr)));
            if(!df3d_nobles::prepareDraft(owned,{}))return CR_FAILURE;
            const auto rows=df3d_nobles::projectSymbols(owned,key);if(!rows)return CR_FAILURE;
            std::vector<df3d_nobles::SymbolChoice> edits;
            for(size_t i=start;i<parameters.size();i+=2){const auto selected=std::stoi(parameters[i+1]);
              if(selected!=0 && selected!=1)return CR_WRONG_USAGE;edits.push_back({std::stoi(parameters[i]),selected!=0});}
            const bool staged=continuation?df3d_nobles::stageSymbolContinuation(owned,key,std::stoull(parameters[4]),edits):
              df3d_nobles::stageSymbols(owned,key,df3d_nobles::symbolRevision(*rows),edits);
            if(!staged){Json::Value result;result["outcome"]=int(owned.stale?df3d_nobles::DraftCommitOutcome::Stale:df3d_nobles::DraftCommitOutcome::Rejected);
              out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;}
            const auto effect=df3d_nobles::applySymbolStep(owned,key);
            Json::Value result;result["outcome"]=int(effect.outcome);result["naming_artifact_id"]=effect.namingArtifactId;
            result["continuation_revision"]=std::to_string(effect.continuationRevision);
            result["remaining"]=Json::Value(Json::arrayValue);
            for(const auto& entry:effect.remaining){Json::Value row;row["item_id"]=entry.itemId;row["selected"]=entry.selected;result["remaining"].append(row);}
            out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
          }catch(const std::exception&){return CR_FAILURE;}
        }
        if(parameters[0]=="nobles-symbols-probe" || parameters[0]=="nobles-symbol-stage-probe") {
          const bool stage=parameters[0]=="nobles-symbol-stage-probe";
          if((!stage && parameters.size()!=4) || (stage && (parameters.size()<5 || (parameters.size()-5)%2)))return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving() || !df3d_nobles::symbolsReady())return CR_FAILURE;
          try {
            df3d_nobles::OfficeKey key{std::stoi(parameters[1]),std::stoi(parameters[2]),std::stoi(parameters[3])};
            df3d_nobles::Context owned(reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr)));
            if(!df3d_nobles::prepareDraft(owned,{}))return CR_FAILURE;
            auto rows=df3d_nobles::projectSymbols(owned,key);if(!rows)return CR_FAILURE;
            if(stage) {
              std::vector<df3d_nobles::SymbolChoice> edits;
              for(size_t i=5;i<parameters.size();i+=2){const auto selected=std::stoi(parameters[i+1]);
                if(selected!=0 && selected!=1)return CR_WRONG_USAGE;edits.push_back({std::stoi(parameters[i]),selected!=0});}
              auto revision=std::stoull(parameters[4]);if(!revision)revision=df3d_nobles::symbolRevision(*rows);
              if(!df3d_nobles::stageSymbols(owned,key,revision,edits)) {
                Json::Value result;result["rejected"]=true;result["stale"]=owned.stale;
                out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
              }
              for(size_t i=0;i<rows->size();++i){const auto index=owned.value.cand_symbol_new_ind[i];
                if(index==-1)(*rows)[i].selectedOffice.reset();
                else {const auto* row=owned.value.noblelist[index];(*rows)[i].selectedOffice=df3d_nobles::OfficeKey{
                  row->enid,row->ep->id,row->epp?row->epp->id:-1,owned.slot(row)};}}
            }
            const auto office=[](const std::optional<df3d_nobles::OfficeKey>& key) {
              Json::Value result;if(key){result["entity_id"]=key->entityId;result["position_id"]=key->positionId;
                result["assignment_id"]=key->assignmentId;result["draft_slot"]=key->draftSlot;}return result;
            };
            Json::Value result(Json::arrayValue);
            for(const auto& entry:*rows){Json::Value row;row["item_id"]=entry.itemId;row["value"]=entry.value;
              row["selected_office"]=office(entry.selectedOffice);row["current_office"]=office(entry.currentOffice);result.append(row);}
            out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
          }catch(const std::exception&){return CR_FAILURE;}
        }
        if(parameters[0]=="nobles-accounting-probe") {
          if(parameters.size()!=6)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          try {df3d_nobles::OfficeKey key{std::stoi(parameters[1]),std::stoi(parameters[2]),std::stoi(parameters[3])};
            out.print("{}\n",int(df3d_nobles::setAccounting({},0,key,std::stoi(parameters[4]),std::stoi(parameters[5]))));return CR_OK;}
          catch(...){return CR_WRONG_USAGE;}
        }
        if(parameters[0]=="nobles-draft-probe" || parameters[0]=="nobles-commit-probe") {
          if(parameters.size()<6 || (parameters.size()-1)%5)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          std::vector<df3d_nobles::DraftChoice> choices;
          try {for(size_t i=1;i<parameters.size();i+=5)choices.push_back({std::stoi(parameters[i]),std::stoi(parameters[i+1]),std::stoi(parameters[i+2]),std::stoi(parameters[i+3]),std::stoi(parameters[i+4])});}
          catch(...){return CR_WRONG_USAGE;}
          if(parameters[0]=="nobles-commit-probe") {
            out.print("{}\n",int(df3d_nobles::commitDraft(choices)));return CR_OK;
          }
          const auto rows=df3d_nobles::draftPreview(choices);if(!rows)return CR_FAILURE;
          Json::Value result(Json::arrayValue);
          for(const auto& entry:*rows){Json::Value row(Json::objectValue);
            row["entity_id"]=entry.entityId;row["position_id"]=entry.positionId;row["assignment_id"]=entry.assignmentId;
            row["unit_id"]=entry.unitId;row["nemesis_id"]=entry.nemesisId;row["histfig_id"]=entry.histfigId;result.append(row);}
          out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
        }
        if(parameters[0]=="nobles-candidates-probe" || parameters[0]=="nobles-candidate-text-probe") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int32_t entity=-1,position=-1,assignment=-1;
          try {entity=std::stoi(parameters[1]);position=std::stoi(parameters[2]);assignment=std::stoi(parameters[3]);}catch(...){return CR_WRONG_USAGE;}
          const bool includeText=parameters[0]=="nobles-candidate-text-probe";
          const auto rows=df3d_nobles::candidates(entity,position,assignment,includeText);if(!rows)return CR_FAILURE;
          Json::Value result(Json::arrayValue);
          for(const auto& entry:*rows){Json::Value row(Json::objectValue);row["unit_id"]=entry.unitId;row["value"]=entry.value;
            if(includeText){row["caption"]=DF2UTF(entry.caption);row["no_skills"]=DF2UTF(entry.noSkills);row["skills"]=Json::Value(Json::arrayValue);
              for(const auto& skill:entry.skills){Json::Value text(Json::objectValue);text["id"]=skill.id;text["rating"]=skill.rating;text["caption"]=DF2UTF(skill.caption);row["skills"].append(text);}}
            result.append(row);}
          out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
        }
        if(parameters[0]=="nobles-overview-probe" || parameters[0]=="nobles-help-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto rows=df3d_nobles::overview(parameters[0]=="nobles-help-probe");if(!rows)return CR_FAILURE;
          Json::Value result(Json::arrayValue);
          for(const auto& entry:*rows){Json::Value row(Json::objectValue);
            row["unit_id"]=entry.unitId;row["nemesis_id"]=entry.nemesisId;row["entity_id"]=entry.entityId;
            row["position_id"]=entry.positionId;row["assignment_id"]=entry.assignmentId;row["value"]=entry.value;
            row["position_name"]=DF2UTF(entry.positionName);row["can_appoint"]=entry.canAppoint;
            row["title"]=DF2UTF(entry.title);row["squad_caption"]=DF2UTF(entry.squadCaption);
            row["holder_caption"]=DF2UTF(entry.holderCaption);row["has_room_assessment"]=entry.hasRoomAssessment;
            if(entry.help){Json::Value help(Json::objectValue);help["description"]=DF2UTF(entry.help->description);
              for(const auto& room:entry.help->rooms){Json::Value value(Json::objectValue);value["actual"]=DF2UTF(room.actual);value["required"]=DF2UTF(room.required);value["color"]=room.color;help["rooms"].append(value);}
              for(const auto& room:entry.help->furniture){Json::Value value(Json::objectValue);value["actual"]=DF2UTF(room.actual);value["required"]=DF2UTF(room.required);value["color"]=room.color;help["furniture"].append(value);}
              for(const auto& field:{"demands","mandates"}){help[field]=Json::Value(Json::arrayValue);for(const auto& item:std::string_view(field)=="demands"?entry.help->demands:entry.help->mandates){Json::Value value(Json::objectValue);value["text"]=DF2UTF(item.text);value["color"]=item.color;help[field].append(value);}}
              if(entry.help->accounting){const auto& a=*entry.help->accounting;Json::Value value(Json::objectValue);
                value["setting"]=a.setting;value["level"]=a.level;value["title"]=DF2UTF(a.title);value["examples"]=DF2UTF(a.examples);value["attained"]=DF2UTF(a.attained);value["progress"]=DF2UTF(a.progress);help["accounting"]=value;}
              row["help"]=help;}
            row["demand_status"]=entry.demandStatus;row["mandate_status"]=entry.mandateStatus;
            for(size_t i=0;i<4;++i){row["required_rooms"].append(entry.requiredRooms[i]);row["actual_rooms"].append(entry.actualRooms[i]);
              row["required_furniture"].append(entry.requiredFurniture[i]);row["actual_furniture"].append(entry.actualFurniture[i]);}
            result.append(row);}
          out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
        }
        if(parameters[0]=="objects-names-probe" || parameters[0]=="objects-ownership-probe" || parameters[0]=="objects-destinations-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto lists=df3d_objects::lists();if(!lists)return CR_FAILURE;
          Json::Value result(Json::arrayValue);
          for(const auto& ids:*lists){Json::Value rows(Json::arrayValue);for(auto id:ids){
            const auto names=df3d_objects::names(id);if(!names)return CR_FAILURE;
            Json::Value row(Json::objectValue);row["artifact_id"]=id;row["item_id"]=names->itemId;
            row["native_name"]=DF2UTF(names->nativeName);row["translated_name"]=DF2UTF(names->translatedName);rows.append(row);
            if(parameters[0]=="objects-ownership-probe"){
              const auto caption=df3d_objects::ownership(id);if(!caption)return CR_FAILURE;
              rows[rows.size()-1]["ownership"]=DF2UTF(*caption);
            }
            if(parameters[0]=="objects-destinations-probe"){
              const auto target=df3d_objects::destination(id);if(!target)return CR_FAILURE;
              auto& value=rows[rows.size()-1];value["available"]=target->available;
              if(target->available){value["position"].append(target->position.x);value["position"].append(target->position.y);value["position"].append(target->position.z);}
            }
          }result.append(rows);}
          out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
        }
        if(parameters[0]=="creature-quote-fallback-probe") {
          // Protected oracle only: compare copied inputs to DF's formatter on
          // the real unit at identical random state, restoring its name cache.
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          const char* oracle=std::getenv("DF3D_JUSTICE_SHEET_NAV");
          if(!oracle || std::string(oracle)!="1" || !state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int32_t id=-1;try{id=std::stoi(parameters[1]);}catch(...){return CR_WRONG_USAGE;}
          auto* unit=df::unit::find(id);if(!unit || !unit->status.current_soul)return CR_FAILURE;
          // Exclude the emotion-selection branch and its random thought6 gate;
          // this comparison establishes fallback formatting, not that branch.
          for(const auto* emotion:unit->status.current_soul->personality.emotions) {
            if(int(emotion->thought)==6)return CR_FAILURE;
            if(int(emotion->thought)!=-1 && int(emotion->type)!=-1 && int(emotion->type)!=165 && int(emotion->type)!=166 &&
               !(emotion->flags.whole&0x70) && (emotion->strength>0 || emotion->relative_strength>0))return CR_FAILURE;
          }
          const auto owned=df3d_creature::overviewQuote(unit);if(!owned || owned->empty())return CR_FAILURE;
          auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
          df3d_creature::InventoryRandomRestore random(base);
          df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
          const auto savedIndex=unit->enemy.histfig_vector_idx;
          std::string native;
          reinterpret_cast<void(*)(df::unit*,std::string*,bool)>(base+0x666470)(unit,&native,false);
          unit->enemy.histfig_vector_idx=savedIndex;
          if(reinterpret_cast<bool(*)(void*,int16_t,int16_t,int32_t)>(base+0x72850)(base+0x24eca48,unit->race,unit->caste,0x77))
            reinterpret_cast<void(*)(std::string*)>(base+0x67b6c0)(&native);
          const auto* quote=reinterpret_cast<const char*>(base+0x15e9718);
          native=std::string(quote)+native+quote;
          Json::Value result(Json::objectValue);result["unit_id"]=id;
          result["native"]=DF2UTF(native);result["owned"]=DF2UTF(*owned);result["equal"]=native==*owned;
          out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
        }
        if(parameters[0]=="justice-captions-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          Json::Value rows(Json::arrayValue);
          for(const auto* crime:df::global::world->crimes.all) {
            const auto caption=df3d_justice::caption(crime);if(!caption)return CR_FAILURE;
            Json::Value row(Json::objectValue);row["id"]=crime->id;
            row["mode"]=int(crime->mode);row["caption"]=DF2UTF(*caption);rows.append(row);
          }
          out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),rows));return CR_OK;
        }
        if(parameters[0]=="justice-witness-text-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          try {
            const auto rows=df3d_justice::witnessText(df::crime::find(std::stoi(parameters[1])));if(!rows)return CR_FAILURE;
            Json::Value result(Json::arrayValue);
            for(const auto& row:*rows){Json::Value value(Json::objectValue);value["witness"]=DF2UTF(row.witness);value["description"]=DF2UTF(row.description);
              value["date"]=DF2UTF(row.date);value["reported"]=DF2UTF(row.reported);result.append(value);}
            out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
          }catch(const std::exception&){return CR_WRONG_USAGE;}
        }
        if(parameters[0]=="justice-summary-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          try {
            const auto summary=df3d_justice::caseSummary(df::crime::find(std::stoi(parameters[1])));if(!summary)return CR_FAILURE;
            Json::Value result(Json::objectValue);
            if(summary->injuredParty)result["injured_party"]=DF2UTF(*summary->injuredParty);
            result["status"]=DF2UTF(summary->status);result["resolution"]=int(summary->resolution);
            out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
          }catch(const std::exception&){return CR_WRONG_USAGE;}
        }
        if(parameters[0]=="justice-witness-dates-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          try {
            const auto* crime=df::crime::find(std::stoi(parameters[1]));
            if(!crime || crime->witnesses.size()>1048576)return CR_FAILURE;
            Json::Value result(Json::arrayValue);
            for(const auto* report:crime->witnesses) {
              if(!report)return CR_FAILURE;
              const auto dates=df3d_justice::witnessDates(*report);if(!dates)return CR_FAILURE;
              Json::Value row(Json::objectValue);row["date"]=DF2UTF(dates->date);row["reported"]=DF2UTF(dates->reported);result.append(row);
            }
            out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
          }catch(const std::exception&){return CR_WRONG_USAGE;}
        }
        if(parameters[0]=="justice-candidate-presentation-probe") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          try {
            const auto row=df3d_justice::candidatePresentation(df::crime::find(std::stoi(parameters[1])),
              df::unit::find(std::stoi(parameters[2])),std::stoi(parameters[3]));
            if(!row)return CR_FAILURE;
            Json::Value result(Json::objectValue),color(Json::arrayValue),alternate(Json::arrayValue);
            for(auto value:row->nameColor.color)color.append(int(value));
            for(auto value:row->nameColor.alternate)alternate.append(int(value));
            result["name"]=DF2UTF(row->name);result["witness_label"]=DF2UTF(row->witnessLabel);result["deceased"]=row->deceased;
            result["witness_count"]=row->witnessCount;result["witness_color"]=int(row->witnessColor);
            result["color"]=color;result["alternate"]=alternate;result["effect"]=int(row->nameColor.effect);
            out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
          }catch(const std::exception&){return CR_WRONG_USAGE;}
        }
        if(parameters[0]=="justice-conviction-probe") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          try {
            const auto outcome=df3d_justice::convict(df::crime::find(std::stoi(parameters[1])),
              df::unit::find(std::stoi(parameters[2])),std::stoi(parameters[3]));
            out.print("{}\n",int(outcome));return CR_OK;
          }catch(const std::exception&){return CR_WRONG_USAGE;}
        }
        if(parameters[0]=="justice-interrogation-probe") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          try {
            const int expected=std::stoi(parameters[3]);if(expected<0 || expected>1)return CR_WRONG_USAGE;
            const auto outcome=df3d_justice::toggleInterrogation(df::crime::find(std::stoi(parameters[1])),df::unit::find(std::stoi(parameters[2])),expected!=0);
            out.print("{}\n",int(outcome));return CR_OK;
          }catch(const std::exception&){return CR_WRONG_USAGE;}
        }
        if(parameters[0]=="justice-candidate-facts-probe" || parameters[0]=="justice-conviction-candidates-probe" || parameters[0]=="justice-interrogation-candidates-probe") {
          if(parameters.size()<2 || parameters.size()>4)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          try {
            const auto* crime=df::crime::find(std::stoi(parameters[1]));
            std::vector<df3d_justice::CandidateSort> sorts={{df3d_justice::CandidateColumn::Crime,false},{df3d_justice::CandidateColumn::Name,false}};
            if(parameters.size()==4){sorts.clear();std::istringstream input(parameters[3]);std::string part;
              while(std::getline(input,part,',')){
                if(part.size()!=3 || part[0]<'0' || part[0]>'3' || part[1]!=':' || (part[2]!='0' && part[2]!='1'))return CR_WRONG_USAGE;
                sorts.push_back({df3d_justice::CandidateColumn(part[0]-'0'),part[2]=='1'});
              }}
            const auto facts=parameters[0]=="justice-candidate-facts-probe" ? df3d_justice::candidateFacts(crime) :
              parameters[0]=="justice-interrogation-candidates-probe" ? df3d_justice::interrogationCandidates(crime,parameters.size()>=3?UTF2DF(parameters[2]):std::string{},sorts) :
              df3d_justice::convictionCandidates(crime,parameters.size()>=3?UTF2DF(parameters[2]):std::string{},sorts);if(!facts)return CR_FAILURE;
            Json::Value result(Json::arrayValue);
            for(const auto& fact:*facts){Json::Value row(Json::objectValue);row["unit_id"]=fact.unitId;
              row["rank"]=fact.rank;row["flags"]=fact.flags;result.append(row);}
            out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
          }catch(const std::exception&){return CR_WRONG_USAGE;}
        }
        if(parameters[0]=="justice-intelligence-graph-probe") {
            if(parameters.size()!=1 || !state.mapLoaded || df3d_session::saving())return CR_FAILURE;
            const auto graph=df3d_justice::intelligenceGraph();if(!graph)return CR_FAILURE;
            Json::Value output;output["actors"]=Json::Value(Json::arrayValue);output["organizations"]=Json::Value(Json::arrayValue);output["plots"]=Json::Value(Json::arrayValue);
            const auto ids=[](const auto& values){Json::Value result(Json::arrayValue);for(auto value:values)result.append(value);return result;};
            for(const auto& row:graph->actors){Json::Value value;value["historical_figure"]=row.historicalFigure;value["identity"]=row.identity;value["name"]=DF2UTF(row.name);
                value["aliases"]=ids(row.aliases);value["principal_organization"]=row.principalOrganization;value["organizations"]=ids(row.organizations);value["plots"]=ids(row.plots);value["lines"]=Json::Value(Json::arrayValue);for(const auto& line:row.lines)value["lines"].append(DF2UTF(line));output["actors"].append(value);}
            for(const auto& row:graph->organizations){Json::Value value;value["name"]=DF2UTF(row.name);value["principal_actor"]=row.principalActor;value["nodes"]=Json::Value(Json::arrayValue);
                for(const auto& node:row.nodes){Json::Value n;n["actor"]=node.actor;n["parent"]=node.parent;n["sort"]=node.sort;n["tier"]=node.tier;n["descendants"]=node.descendants;
                    n["label"]=DF2UTF(node.label);n["name"]=DF2UTF(node.name);n["status"]=DF2UTF(node.status);n["foreground"]=node.foreground;n["background"]=node.background;n["bright"]=int(node.bright);value["nodes"].append(n);}
                output["organizations"].append(value);}
            for(const auto& row:graph->plots){Json::Value value;value["agreement"]=row.agreement;value["master"]=row.master;value["organization"]=row.organization;value["name"]=DF2UTF(row.name);output["plots"].append(value);}
            out.print("{}",Json::FastWriter().write(output));return CR_OK;
        }
        if(parameters[0]=="justice-intelligence-actors-probe") {
            if(parameters.size()>2)return CR_WRONG_USAGE;
            const auto query=parameters.size()==2?UTF2DF(parameters[1]):std::string{};if(parameters.size()==2 && DF2UTF(query)!=parameters[1])return CR_WRONG_USAGE;
            const auto rows=df3d_justice::intelligenceActors(query);if(!rows)return CR_FAILURE;
            Json::Value output(Json::arrayValue);for(const auto& row:*rows){Json::Value value;value["historical_figure"]=row.historicalFigure;value["identity"]=row.identity;value["name"]=DF2UTF(row.name);value["aliases"]=Json::Value(Json::arrayValue);for(auto id:row.aliases)value["aliases"].append(id);output.append(value);}
            out.print("{}",Json::FastWriter().write(output));return CR_OK;
        }
        if(parameters[0]=="justice-intelligence-reports-probe") {
            if(parameters.size()!=2)return CR_WRONG_USAGE;
            int columns=0;const auto& argument=parameters[1];const auto parsed=std::from_chars(argument.data(),argument.data()+argument.size(),columns);
            if(parsed.ec!=std::errc{} || parsed.ptr!=argument.data()+argument.size())return CR_WRONG_USAGE;
            const auto rows=df3d_justice::intelligenceReports(columns);if(!rows)return CR_FAILURE;
            Json::Value output(Json::arrayValue);
            for(const auto& row:*rows){Json::Value value;value["index"]=row.index;value["title"]=DF2UTF(row.title);value["officer"]=DF2UTF(row.officer);value["viewed"]=row.viewed;value["lines"]=Json::Value(Json::arrayValue);for(const auto& line:row.lines)value["lines"].append(DF2UTF(line));output.append(value);}
            out.print("{}",Json::FastWriter().write(output));return CR_OK;
        }
        if(parameters[0]=="justice-convicts-probe") {
          if(parameters.size()!=1 || !state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto rows=df3d_justice::convicts();if(!rows)return CR_FAILURE;Json::Value result(Json::arrayValue);
          for(const auto& fact:*rows){const auto detail=df3d_justice::convictDetail(fact.unitId);if(!detail)return CR_FAILURE;
            Json::Value row(Json::objectValue),sentence(Json::arrayValue),crimes(Json::arrayValue);row["unit_id"]=fact.unitId;
            for(const auto& line:detail->sentence)sentence.append(DF2UTF(line));row["sentence"]=sentence;
            if(detail->officer)row["officer"]=DF2UTF(*detail->officer);
            for(const auto& crime:detail->crimes){Json::Value c(Json::objectValue);c["id"]=crime.id;c["caption"]=DF2UTF(crime.caption);if(crime.injuredParty)c["injured_party"]=DF2UTF(*crime.injuredParty);crimes.append(c);}
            row["crimes"]=crimes;result.append(row);}
          out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
        }
        if(parameters[0]=="justice-guard-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto value=df3d_justice::guardOverview();if(!value)return CR_FAILURE;
          Json::Value result(Json::objectValue),rows(Json::arrayValue);
          result["available"]=value->available;result["desired"]=value->desired;
          result["caption"]=DF2UTF(value->caption);result["color"]=value->color;
          for(const auto& fact:value->members){Json::Value row(Json::objectValue);row["unit_id"]=fact.unitId;row["rank"]=fact.rank;rows.append(row);}
          result["members"]=rows;out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
        }
        if(parameters[0]=="justice-cases-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto lists=df3d_justice::cases();if(!lists)return CR_FAILURE;
          Json::Value result(Json::arrayValue);
          for(const auto& ids:*lists) {
            Json::Value rows(Json::arrayValue);
            for(auto id:ids) {
              const auto caption=df3d_justice::caption(df::crime::find(id));if(!caption)return CR_FAILURE;
              Json::Value row(Json::objectValue);row["id"]=id;row["caption"]=DF2UTF(*caption);rows.append(row);
            }
            result.append(rows);
          }
          out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
        }
        if(parameters[0]=="objects-lists-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto lists=df3d_objects::lists();if(!lists)return CR_FAILURE;
          Json::Value result(Json::arrayValue);
          for(const auto& ids:*lists){Json::Value list(Json::arrayValue);for(auto id:ids)list.append(id);result.append(list);}
          out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
        }
        if(parameters[0]=="places-lists-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto lists=df3d_places::lists();if(!lists)return CR_FAILURE;
          Json::Value result(Json::arrayValue);
          for(const auto& ids:*lists){Json::Value list(Json::arrayValue);for(auto id:ids)list.append(id);result.append(list);}
          out.print("{}\n",Json::writeString(Json::StreamWriterBuilder(),result));return CR_OK;
        }
        if(parameters[0]=="tasks-rows-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto rows=df3d_tasks::rows(true);if(!rows)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["rows"]=Json::Value(Json::arrayValue);
          for(const auto& entry:*rows) {
            Json::Value row(Json::objectValue);row["job_id"]=entry.jobId;row["unit_id"]=entry.unitId;
            row["item_id"]=entry.itemId;row["flags"]=entry.flags;
            row["sort_name"]=DF2UTF(entry.professionKey);row["job_sort_name"]=DF2UTF(entry.jobKey);
            row["caption"]=DF2UTF(entry.caption);row["worker_name"]=DF2UTF(entry.workerName);
            row["building_id"]=entry.buildingId;
            row["can_view_job"]=entry.canViewJob;row["can_repeat"]=entry.canRepeat;
            row["can_remove_worker"]=entry.canRemoveWorker;row["can_suspend"]=entry.canSuspend;
            row["can_cancel"]=entry.canCancel;row["repeating"]=entry.repeating;row["suspended"]=entry.suspended;
            row["building_caption"]=DF2UTF(entry.buildingCaption);
            row["building_position"]=Json::Value(Json::arrayValue);row["worker_position"]=Json::Value(Json::arrayValue);
            for(auto v:{entry.buildingPosition.x,entry.buildingPosition.y,entry.buildingPosition.z})row["building_position"].append(v);
            for(auto v:{entry.workerPosition.x,entry.workerPosition.y,entry.workerPosition.z})row["worker_position"].append(v);
            if(entry.workerColor){const auto& c=*entry.workerColor;auto& color=row["worker_color"];
              color["effect"]=int(c.effect);color["source"]=int(c.source);
              for(auto value:c.color)color["color"].append(int(value));
              for(auto value:c.alternate)color["alternate"].append(int(value));}
            const auto writeArt=[&](const auto& source,const char* key){if(!source)return;const auto& recipe=*source;auto& art=row[key];
              art["pages"]=Json::Value(Json::arrayValue);art["palettes"]=Json::Value(Json::arrayValue);art["layers"]=Json::Value(Json::arrayValue);
              for(const auto& name:recipe.pages)art["pages"].append(name);
              for(const auto& name:recipe.palettes)art["palettes"].append(name);
              for(const auto& layer:recipe.layers){Json::Value values(Json::arrayValue);for(auto value:layer)values.append(value);art["layers"].append(values);}};
            writeArt(entry.workerAppearance,"worker_appearance");writeArt(entry.buildingAppearance,"building_appearance");
            result["rows"].append(row);
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-activity-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          const auto ids=df3d_residents::orderedResidents(0,false);if(!ids)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["rows"]=Json::Value(Json::arrayValue);
          for(auto id:*ids) {
            auto* unit=df::unit::find(id);const auto activity=df3d_residents::activityText(unit);
            if(!activity)return CR_FAILURE;
            Json::Value row(Json::objectValue);row["id"]=id;row["caption"]=DF2UTF(activity->caption);
            row["key"]=DF2UTF(activity->key);row["fg"]=activity->foreground;row["bg"]=activity->background;
            row["bright"]=activity->bright;result["rows"].append(row);
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="hunter-ammunition-captions-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto choices=df3d_hunter_ammunition::candidates();
          const auto specs=df3d_hunter_ammunition::snapshot();if(!choices || !specs)return CR_FAILURE;
          Json::Value result(Json::objectValue);
          for(const auto& row:choices->types){
            const auto text=df3d_hunter_ammunition::caption(row.type,row.subtype,{-1,-1,-1},true,row.foreign);
            if(!text)return CR_FAILURE;result["types"].append(DF2UTF(*text));
          }
          if(!specs->empty())for(const auto& row:choices->materials){
            const auto text=df3d_hunter_ammunition::caption(int16_t(specs->front().item_type),int16_t(specs->front().item_subtype),row);
            if(!text)return CR_FAILURE;result["materials"].append(DF2UTF(*text));
          }
          for(const auto& row:*specs){
            const auto text=df3d_hunter_ammunition::caption(int16_t(row.item_type),int16_t(row.item_subtype),{int16_t(row.material_class),int16_t(row.mattype),row.matindex});
            if(!text)return CR_FAILURE;Json::Value spec(Json::objectValue);spec["caption"]=DF2UTF(*text);int64_t total=0;
            for(const auto id:row.assigned){auto* item=df::item::find(id);if(!item)continue;
              const auto name=df3d_hunter_ammunition::stackCaption(item);if(!name)return CR_FAILURE;
              Json::Value stack(Json::objectValue);stack["id"]=id;stack["caption"]=DF2UTF(*name);
              stack["quantity"]=item->getStackSize();total+=item->getStackSize();spec["items"].append(stack);}
            spec["assigned_quantity"]=Json::Int64(total);result["specs"].append(spec);
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="hunter-ammunition-edit-probe") {
          if(parameters.size()!=5)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int32_t index=-1,value=-1;
          for(size_t i=2;i<=3;++i){const auto& raw=parameters[i];auto& target=i==2?index:value;
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),target);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;}
          if(index<0)return CR_WRONG_USAGE;
          Json::Value input;Json::CharReaderBuilder builder;std::string errors;
          const auto reader=std::unique_ptr<Json::CharReader>(builder.newCharReader());
          const auto& raw=parameters[4];
          if(!reader->parse(raw.data(),raw.data()+raw.size(),&input,&errors) || !input.isArray())return CR_WRONG_USAGE;
          df3d_hunter_ammunition::Snapshot expected;
          for(const auto& row:input){
            for(const auto* key:{"item_type","item_subtype","material_class","mattype","matindex","amount","flags"})
              if(!row[key].isInt())return CR_WRONG_USAGE;
            if(!row["assigned"].isArray())return CR_WRONG_USAGE;
            df3d_hunter_ammunition::Spec spec{row["item_type"].asInt(),row["item_subtype"].asInt(),
              row["material_class"].asInt(),row["mattype"].asInt(),row["matindex"].asInt(),row["amount"].asInt(),uint32_t(row["flags"].asInt()),{}};
            for(const auto& id:row["assigned"]){if(!id.isInt())return CR_WRONG_USAGE;spec.assigned.push_back(id.asInt());}
            expected.push_back(std::move(spec));
          }
          df3d_hunter_ammunition::EditResult reply;
          if(parameters[1]=="amount")reply=df3d_hunter_ammunition::setAmount(expected,size_t(index),value);
          else if(parameters[1]=="delete")reply=df3d_hunter_ammunition::remove(expected,size_t(index),std::nullopt);
          else if(parameters[1]=="remove")reply=df3d_hunter_ammunition::remove(expected,size_t(index),value);
          else if(parameters[1]=="add"){
            const auto choices=df3d_hunter_ammunition::candidates();if(!choices)return CR_FAILURE;
            if(value>=0 && size_t(value)<choices->types.size())reply=df3d_hunter_ammunition::add(expected,choices->types[size_t(value)]);
          }
          else if(parameters[1]=="material"){
            const auto choices=df3d_hunter_ammunition::candidates();if(!choices)return CR_FAILURE;
            if(value>=0 && size_t(value)<choices->materials.size())
              reply=df3d_hunter_ammunition::setMaterial(expected,size_t(index),choices->materials[size_t(value)]);
          }else return CR_WRONG_USAGE;
          Json::Value result(Json::objectValue);result["outcome"]=int(reply.outcome);
          result["receipt_count"]=Json::UInt64(reply.specs.size());
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="hunter-ammunition-candidates-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto candidates=df3d_hunter_ammunition::candidates();if(!candidates)return CR_FAILURE;
          Json::Value result(Json::objectValue);
          for(const auto& row:candidates->materials){result["material_class"].append(row.category);
            result["mattype"].append(row.type);result["matindex"].append(row.index);}
          for(const auto& row:candidates->types){result["item_type"].append(row.type);
            result["item_subtype"].append(row.subtype);result["foreign"].append(row.foreign);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="chores-edit-probe") {
          if(parameters.size()!=5)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int32_t args[3]{};
          for(size_t i=1;i<4;++i){const auto& raw=parameters[i];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),args[i-1]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;}
          if(args[2]<0 || args[2]>1)return CR_WRONG_USAGE;
          Json::Value receipt;Json::Reader reader;
          if(!reader.parse(parameters[4],receipt) || !receipt["enabled"].isBool() ||
             !receipt["children"].isArray() || !receipt["exempted"].isArray() || !receipt["labors"].isArray())return CR_WRONG_USAGE;
          df3d_chores::Snapshot expected;expected.enabled=receipt["enabled"].asBool();
          for(const auto& id:receipt["children"]){if(!id.isInt())return CR_WRONG_USAGE;expected.children.push_back(id.asInt());}
          for(const auto& id:receipt["exempted"]){if(!id.isInt())return CR_WRONG_USAGE;expected.exempted.push_back(id.asInt());}
          for(const auto& row:receipt["labors"]){if(!row["id"].isInt() || !row["enabled"].isBool())return CR_WRONG_USAGE;
            expected.labors.emplace_back(row["id"].asInt(),row["enabled"].asBool());}
          bool started=false;Json::Value result(Json::objectValue);
          try {result["outcome"]=int(df3d_chores::apply(df3d_chores::Operation(args[0]),args[1],args[2]!=0,expected,&started));}
          catch(...){result["outcome"]=started?3:0;}
          result["write_started"]=started;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="chores-captions-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto snapshot=df3d_chores::read();if(!snapshot)return CR_FAILURE;
          const auto captions=df3d_chores::captions(*snapshot);if(!captions)return CR_FAILURE;
          Json::Value result(Json::objectValue);
          for(const auto& [key,rows]:{std::pair{"children",&captions->children},std::pair{"labors",&captions->labors}}){
            result[key]=Json::Value(Json::arrayValue);
            for(const auto& row:*rows){Json::Value value(Json::objectValue);value["id"]=row.id;value["caption"]=DF2UTF(row.text);result[key].append(value);}}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="kitchen-display-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto rows=df3d_kitchen::read();if(!rows)return CR_FAILURE;
          const auto details=df3d_kitchen::display(*rows);if(!details)return CR_FAILURE;
          Json::Value result(Json::arrayValue);
          for(size_t i=0;i<rows->size();++i){const auto& row=(*rows)[i];const auto& detail=(*details)[i];Json::Value value(Json::objectValue);
            value["type"]=row.type;value["subtype"]=row.subtype;value["mat"]=row.material;value["matg"]=row.materialIndex;value["name"]=DF2UTF(row.name);
            value["count_caption"]=DF2UTF(detail.countCaption);value["estimated"]=detail.estimated;value["excluded"]=detail.excluded;value["material_token"]=detail.materialToken;result.append(value);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="kitchen-edit-probe") {
          if(parameters.size()!=3 || (parameters[1]!="1" && parameters[1]!="2"))return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          Json::Value receipt;Json::Reader reader;
          if(!reader.parse(parameters[2],receipt) || !receipt["exclusions"].isArray() || receipt["exclusions"].size()>65536)return CR_WRONG_USAGE;
          const auto parseKey=[](const Json::Value& value,df3d_kitchen::Exclusion& key){
            for(const char* name:{"type","subtype","mat","matg"})if(!value[name].isInt())return false;
            for(const char* name:{"type","subtype","mat"})if(value[name].asInt()<-32768 || value[name].asInt()>32767)return false;
            key.type=int16_t(value["type"].asInt());key.subtype=int16_t(value["subtype"].asInt());key.material=int16_t(value["mat"].asInt());key.materialIndex=value["matg"].asInt();return true;};
          df3d_kitchen::Exclusion key{};const auto& row=receipt["target"];
          if(!parseKey(row,key) || !row["count"].isInt() || row["count"].asInt()<0 || !row["capabilities"].isInt() || row["capabilities"].asInt()<1 || row["capabilities"].asInt()>3)return CR_WRONG_USAGE;
          df3d_kitchen::Row target{key.type,key.subtype,key.material,key.materialIndex,row["count"].asInt(),uint8_t(row["capabilities"].asInt()),{}};
          std::vector<df3d_kitchen::Exclusion> expected;
          for(const auto& value:receipt["exclusions"]){df3d_kitchen::Exclusion entry{};
            if(!parseKey(value,entry) || !value["flags"].isInt() || value["flags"].asInt()<0 || value["flags"].asInt()>3)return CR_WRONG_USAGE;
            entry.flags=uint8_t(value["flags"].asInt());expected.push_back(entry);}
          bool started=false;Json::Value result(Json::objectValue);
          try {result["outcome"]=int(df3d_kitchen::apply(target,parameters[1]=="1"?1:2,expected,&started));}
          catch(...){result["outcome"]=started?3:0;}
          result["write_started"]=started;out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="kitchen-probe") {
          if(parameters.size()!=1 && (parameters.size()<4 || parameters.size()>132 || parameters.size()%2!=0))return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          df3d_kitchen::Filter filter;
          if(parameters.size()>=4){
            if(parameters[1]!="-1" && parameters[1]!="0" && parameters[1]!="1" && parameters[1]!="2" && parameters[1]!="3")return CR_WRONG_USAGE;
            if(parameters[2]!="0" && parameters[2]!="1" && parameters[2]!="2" && parameters[2]!="3")return CR_WRONG_USAGE;
            filter.type=static_cast<int8_t>(std::stoi(parameters[1]));filter.capabilities=static_cast<uint8_t>(std::stoi(parameters[2]));filter.query=UTF2DF(parameters[3]);}
          std::vector<df3d_kitchen::Sort> sorts(1);
          if(parameters.size()>4){sorts.clear();for(size_t i=4;i<parameters.size();i+=2){
            if(parameters[i].size()!=1 || parameters[i][0]<'0' || parameters[i][0]>'4' || (parameters[i+1]!="0" && parameters[i+1]!="1"))return CR_WRONG_USAGE;
            sorts.push_back({static_cast<df3d_kitchen::Column>(parameters[i][0]-'0'),parameters[i+1]=="1"});}}
          const auto rows=df3d_kitchen::read(filter,sorts);if(!rows)return CR_FAILURE;
          Json::Value result(Json::arrayValue);
          for(const auto& row:*rows){Json::Value value(Json::objectValue);
            value["type"]=row.type;value["subtype"]=row.subtype;value["mat"]=row.material;value["matg"]=row.materialIndex;
            value["count"]=row.count;value["capabilities"]=row.capabilities;value["name"]=DF2UTF(row.name);result.append(value);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="stone-use-edit-probe") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving() || !df::global::plotinfo)return CR_FAILURE;
          int32_t values[3]{};
          for(size_t i=1;i<4;++i){const auto& raw=parameters[i];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;}
          auto expected=df::global::plotinfo->economic_stone;
          if(values[1]<0 || size_t(values[1])>=expected.size() || values[2]<0 || values[2]>1)return CR_WRONG_USAGE;
          expected[values[1]]=static_cast<char>(values[2]);
          bool started=false;Json::Value result(Json::objectValue);
          try {result["outcome"]=int(df3d_stone_use::apply(values[0],values[1],expected,&started));}
          catch(...){result["outcome"]=started?3:0;}
          result["write_started"]=started;out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="stone-use-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto rows=df3d_stone_use::read();if(!rows)return CR_FAILURE;
          Json::Value result(Json::arrayValue);
          for(const auto& row:*rows){Json::Value value(Json::objectValue);
            value["category"]=row.category;value["index"]=row.index;value["restricted"]=row.restricted;
            value["name"]=DF2UTF(row.name);value["uses"]=DF2UTF(row.uses);value["magma_safe"]=row.magmaSafe;value["material_token"]=row.materialToken;result.append(value);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="chores-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto snapshot=df3d_chores::read();if(!snapshot)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["enabled"]=snapshot->enabled;
          for(const char* key:{"children","exempted","labors"})result[key]=Json::Value(Json::arrayValue);
          for(int32_t id:snapshot->children)result["children"].append(id);
          for(int32_t id:snapshot->exempted)result["exempted"].append(id);
          for(const auto& [id,enabled]:snapshot->labors){Json::Value row(Json::objectValue);
            row["id"]=id;row["enabled"]=enabled;result["labors"].append(row);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="standing-category-probe") {
          if(parameters.size()!=2 && parameters.size()!=5)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int32_t values[4]{};
          for(size_t i=1;i<parameters.size();++i){const auto& raw=parameters[i];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;}
          Json::Value result(Json::objectValue);
          if(parameters.size()==5)result["outcome"]=int(df3d_standing::setCategory(values[0],values[1],values[2],values[3]));
          const auto snapshot=df3d_standing::categorySettings(values[0]);if(!snapshot)return CR_FAILURE;
          result["settings"]=Json::Value(Json::arrayValue);
          for(size_t i=0;i<snapshot->count;++i){const auto& entry=snapshot->rows[i];Json::Value row(Json::objectValue);
            row["id"]=entry.id;row["value"]=int(entry.value);row["visible"]=entry.visible;row["editable"]=entry.editable;
            result["settings"].append(row);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="standing-workshops-probe") {
          if(parameters.size()!=1 && parameters.size()!=4)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          Json::Value result(Json::objectValue);
          if(parameters.size()==4){
            int32_t values[3];
            for(size_t i=1;i<4;++i){const auto& raw=parameters[i];
              const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;}
            result["outcome"]=int(df3d_standing::setWorkshop(values[0],values[1],values[2]));
          }
          const auto snapshot=df3d_standing::workshopSettings();if(!snapshot)return CR_FAILURE;
          result["settings"]=Json::Value(Json::arrayValue);
          for(const auto& entry:*snapshot){Json::Value row(Json::objectValue);row["id"]=entry.id;
            row["value"]=int(entry.value);row["available"]=entry.available;result["settings"].append(row);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="work-detail-settings-probe") {
          if(parameters.size()<2 || parameters.size()>98)return CR_WRONG_USAGE;
          std::vector<int32_t> values;
          for(size_t i=1;i<parameters.size();++i){int32_t value;const auto& raw=parameters[i];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
            values.push_back(value);}
          if(!state.mapLoaded || df3d_session::saving() || !df::global::plotinfo)return CR_FAILURE;
          const auto& all=df::global::plotinfo->labor_info.work_details;
          if(values[0]<0 || size_t(values[0])>=all.size() || !all[size_t(values[0])])return CR_FAILURE;
          const auto catalog=df3d_production::nativeWorkDetailSettings();if(!catalog)return CR_FAILURE;
          const auto original=all[size_t(values[0])]->allowed_labors;auto allowed=original;
          Json::Value result(Json::objectValue);result["catalog"]=Json::Value(Json::arrayValue);
          for(const auto& entry:*catalog){Json::Value row(Json::objectValue);row["id"]=entry.id;
            row["caption"]=DF2UTF(entry.caption);result["catalog"].append(row);}
          result["steps"]=Json::Value(Json::arrayValue);
          for(size_t i=1;i<values.size();++i){
            if(!df3d_production::nativeWorkDetailToggle(allowed,values[i]))return CR_FAILURE;
            Json::Value row(Json::objectValue);row["id"]=values[i];row["labors"]=Json::Value(Json::arrayValue);
            for(size_t id=0;id<allowed.size();++id)if(allowed[id])row["labors"].append(int(id));
            result["steps"].append(row);}
          if(all[size_t(values[0])]->allowed_labors!=original)return CR_FAILURE;
          result["source_unchanged"]=true;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="work-detail-row-probe") {
          if(parameters.size()!=3)return CR_WRONG_USAGE;
          int32_t values[2];
          for(size_t i=1;i<3;++i) {
            const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto rows=df3d_production::workDetailSkillText(values[0],df::unit::find(values[1]));
          if(!rows)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["skills"]=Json::Value(Json::arrayValue);
          for(const auto& skill:*rows){Json::Value row(Json::objectValue);row["id"]=skill.skill;
            row["rating"]=skill.rating;row["caption"]=DF2UTF(skill.caption);result["skills"].append(row);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="stocks-group-edit-probe" || parameters[0]=="stocks-item-edit-probe") {
          const bool individual=parameters[0]=="stocks-item-edit-probe";
          if(parameters.size()!=(individual?10:9))return CR_WRONG_USAGE;
          int32_t itemId=-1;
          if(individual){const auto& raw=parameters[9];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),itemId);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || itemId<0)return CR_WRONG_USAGE;}
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int32_t values[4];for(size_t i=0;i<4;++i){const auto& raw=parameters[i+1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i]<INT16_MIN || values[i]>INT16_MAX)return CR_WRONG_USAGE;}
          df3d_production::BuildingItemAction action;
          if(parameters[5]=="forbid")action=df3d_production::BuildingItemAction::Forbid;
          else if(parameters[5]=="dump")action=df3d_production::BuildingItemAction::Dump;
          else if(parameters[5]=="melt")action=df3d_production::BuildingItemAction::Melt;
          else if(parameters[5]=="hidden")action=df3d_production::BuildingItemAction::Hidden;
          else return CR_WRONG_USAGE;
          if(parameters[6]!="0" && parameters[6]!="1")return CR_WRONG_USAGE;
          uint64_t expected=0;const auto& raw=parameters[7];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),expected);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || !expected || expected>INT64_MAX || parameters[8]!="owned-test")return CR_WRONG_USAGE;
          const df3d_stocks::Group key{int16_t(values[0]),int16_t(values[1]),int16_t(values[2]),int16_t(values[3]),0,false};
          const auto result=individual?df3d_stocks::editItem(key,expected,itemId,action,parameters[6]=="1"):
            df3d_stocks::editGroup(key,expected,action,parameters[6]=="1");
          Json::Value output(Json::objectValue);output["outcome"]=int(result.outcome);output["changed"]=result.changed;output["receipt"]=bool(result.receipt);
          out.print("{}",Json::FastWriter().write(output));return CR_OK;
        }
        if(parameters[0]=="stocks-selection-probe") {
          if(parameters.size()<2 || parameters.size()>3)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int32_t type=-1;try {type=std::stoi(parameters[1]);}catch(...){return CR_WRONG_USAGE;}
          if(type<0 || type>=93)return CR_WRONG_USAGE;
          const auto selected=df3d_stocks::selection(int16_t(type),parameters.size()==3?UTF2DF(parameters[2]):"");if(!selected)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["ids"]=Json::Value(Json::arrayValue);result["groups"]=Json::Value(Json::arrayValue);
          for(auto id:selected->ids)result["ids"].append(id);
          for(const auto& entry:selected->groups){const auto& group=entry.group;Json::Value row(Json::objectValue);
            row["subtype"]=group.subtype;row["subcat1"]=group.subcat1;row["subcat2"]=group.subcat2;row["amount"]=group.amount;
            row["expanded"]=group.expanded;row["on"]=entry.matches;row["flags"]=entry.flags;row["revision"]=std::to_string(entry.revision);row["caption"]=DF2UTF(entry.caption);row["ids"]=Json::Value(Json::arrayValue);
            for(auto id:entry.ids)row["ids"].append(id);result["groups"].append(row);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="stocks-categories-probe") {
          if(parameters.size()>2)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto types=df3d_stocks::categories(parameters.size()==2?UTF2DF(parameters[1]):"");if(!types)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["types"]=Json::Value(Json::arrayValue);
          for(auto type:*types)result["types"].append(type);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="stocks-display-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto rows=df3d_stocks::categoryDisplay();if(!rows)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["rows"]=Json::Value(Json::arrayValue);
          for(const auto& value:*rows){Json::Value row(Json::objectValue);row["type"]=value.type;
            row["caption"]=DF2UTF(value.caption);row["stored"]=value.stored;row["unavailable"]=value.unavailable;result["rows"].append(row);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="stocks-totals-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto totals=df3d_stocks::totals();if(!totals)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["stored"]=Json::Value(Json::arrayValue);result["unavailable"]=Json::Value(Json::arrayValue);
          for(auto value:totals->stored)result["stored"].append(value);
          for(auto value:totals->unavailable)result["unavailable"].append(value);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="stocks-groups-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto groups=df3d_stocks::groups();if(!groups)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["groups"]=Json::Value(Json::arrayValue);
          for(const auto& group:*groups){Json::Value row(Json::objectValue);
            row["type"]=group.type;row["subtype"]=group.subtype;row["subcat1"]=group.subcat1;row["subcat2"]=group.subcat2;
            row["amount"]=group.amount;row["expanded"]=group.expanded;result["groups"].append(row);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="stocks-ordered-inventory-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto ids=df3d_stocks::orderedInventory();if(!ids)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["ids"]=Json::Value(Json::arrayValue);
          for(auto id:*ids)result["ids"].append(id);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="stocks-inventory-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto ids=df3d_stocks::inventory();if(!ids)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["ids"]=Json::Value(Json::arrayValue);
          for(auto id:*ids)result["ids"].append(id);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="work-detail-multisort-probe") {
          if(parameters.size()<5 || parameters.size()>131075 || (parameters.size()-3)%2)return CR_WRONG_USAGE;
          auto integer=[](const std::string& raw,int32_t& value){const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);
            return parsed.ec==std::errc{} && parsed.ptr==raw.data()+raw.size();};
          int32_t index;if(!integer(parameters[1],index))return CR_WRONG_USAGE;
          std::vector<df3d_production::WorkDetailSort> sorts;
          for(size_t i=3;i<parameters.size();i+=2){int32_t column,direction;
            if(!integer(parameters[i],column) || !integer(parameters[i+1],direction) || direction<0 || direction>1)return CR_WRONG_USAGE;
            sorts.push_back({column,direction!=0});}
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto ids=df3d_production::queryWorkDetailWorkers(index,sorts,parameters[2]);if(!ids)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["ids"]=Json::Value(Json::arrayValue);
          for(auto id:*ids)result["ids"].append(id);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="work-detail-query-probe") {
          if(parameters.size()!=4 && parameters.size()!=5)return CR_WRONG_USAGE;
          int32_t values[3];
          for(size_t i=1;i<4;++i) {
            const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(values[2]<0 || values[2]>1)return CR_WRONG_USAGE;
          const auto ids=df3d_production::queryWorkDetailWorkers(values[0],values[1],values[2]!=0,parameters.size()==5?parameters[4]:std::string{});
          if(!ids)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["ids"]=Json::Value(Json::arrayValue);
          for(auto id:*ids)result["ids"].append(id);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="residents-order-probe") {
          if(parameters.size()!=3 && parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t sort=-1,direction=-1;
          for(size_t i=1;i<3;++i) {
            auto& value=i==1?sort:direction;const auto& raw=parameters[i];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(direction<0 || direction>1)return CR_WRONG_USAGE;
          const auto ids=df3d_residents::queryResidents(sort,direction!=0,parameters.size()==4?parameters[3]:std::string{});
          if(!ids)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["ids"]=Json::Value(Json::arrayValue);
          for(auto id:*ids)result["ids"].append(id);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="work-order-art-select-probe") {
          if(parameters.size()!=5)return CR_WRONG_USAGE;
          int32_t values[4];
          for(size_t i=1;i<5;++i) {
            const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          df::manager_order* order=nullptr;
          if(df::global::world)for(auto* candidate:df::global::world->manager_orders.all)if(candidate && candidate->id==values[0]){order=candidate;break;}
          if(!order)return CR_FAILURE;
          const auto details=df3d_production::nativeWorkOrderDetails(*order);if(!details)return CR_FAILURE;
          uint64_t revision=0;
          if(values[2]!=0){const auto subjects=df3d_production::nativeWorkOrderArtSubjects(*order,values[2]);if(!subjects)return CR_FAILURE;revision=subjects->listRevision;}
          const auto edited=df3d_production::setWorkOrderArtSubject(*order,details->revision,values[1],values[2],values[3],revision);
          return edited.outcome==df3d_production::WorkshopOrdersOutcome::Applied?CR_OK:CR_FAILURE;
        }
        if(parameters[0]=="work-order-art-subjects-probe") {
          if(parameters.size()<3 || parameters.size()>4)return CR_WRONG_USAGE;
          int32_t id=-1,kind=-1;
          for(size_t i=1;i<3;++i) {
            auto& value=i==1?id:kind;const auto& raw=parameters[i];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || value<0)return CR_WRONG_USAGE;
          }
          df::manager_order* order=nullptr;
          if(df::global::world)for(auto* candidate:df::global::world->manager_orders.all)if(candidate && candidate->id==id){order=candidate;break;}
          if(!order)return CR_FAILURE;
          const auto observed=df3d_production::nativeWorkOrderArtSubjects(*order,kind,parameters.size()==4?UTF2DF(parameters[3]):std::string{});
          if(!observed)return CR_FAILURE;
          Json::Value result;result["order_revision"]=std::to_string(observed->orderRevision);result["list_revision"]=std::to_string(observed->listRevision);result["ids"]=Json::Value(Json::arrayValue);
          for(auto value:observed->ids)result["ids"].append(value);
          result["captions"]=Json::Value(Json::arrayValue);
          for(size_t i=0;i<std::min(size_t(8),observed->ids.size());++i) {
            const auto caption=df3d_production::nativeWorkOrderArtSubjectCaption(kind,observed->ids[i]);if(!caption)return CR_FAILURE;
            result["captions"].append(DF2UTF(*caption));
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="work-order-dye-probe") {
          if(parameters.size()<2 || parameters.size()>4)return CR_WRONG_USAGE;
          int32_t id=-1,target=-1;
          for(size_t i=1;i<std::min(parameters.size(),size_t(3));++i) {
            auto& value=i==1?id:target;const auto& raw=parameters[i];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || value<(i==1?0:-1))return CR_WRONG_USAGE;
          }
          df::manager_order* order=nullptr;
          if(df::global::world)for(auto* candidate:df::global::world->manager_orders.all)if(candidate && candidate->id==id){order=candidate;break;}
          if(!order)return CR_FAILURE;
          const auto observed=df3d_production::nativeWorkOrderDyeCatalog(*order,target,parameters.size()==4?parameters[3]:"");if(!observed)return CR_FAILURE;
          Json::Value result;result["kind"]=observed->kind;result["target"]=observed->target;result["rows"]=Json::Value(Json::arrayValue);
          for(const auto& row:observed->rows) {Json::Value v;v["color"]=row.color;v["first"]=row.first;v["second"]=row.second;v["available"]=row.available;v["tint"]=row.tint;result["rows"].append(v);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="work-order-details-probe") {
          if(parameters.size()<2 || parameters.size()>4)return CR_WRONG_USAGE;
          int32_t id=-1,selected=-1,choice=-1;
          for(size_t i=1;i<parameters.size();++i) {
            auto& value=i==1?id:i==2?selected:choice;const auto& raw=parameters[i];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || value<0)return CR_WRONG_USAGE;
          }
          df::manager_order* order=nullptr;
          if(df::global::world)for(auto* candidate:df::global::world->manager_orders.all)if(candidate && candidate->id==id){order=candidate;break;}
          if(!order)return CR_FAILURE;
          const auto observed=df3d_production::nativeWorkOrderDetails(*order,selected);if(!observed)return CR_FAILURE;
          if(choice>=0) {
            const auto applied=df3d_production::setWorkOrderDetailMaterial(*order,observed->revision,selected,observed->choicesRevision,choice);
            if(applied.outcome!=df3d_production::WorkshopOrdersOutcome::Applied)return CR_FAILURE;
          }
          Json::Value result;result["revision"]=std::to_string(observed->revision);result["choices_revision"]=std::to_string(observed->choicesRevision);result["caption"]=DF2UTF(observed->caption);result["options"]=Json::Value(Json::arrayValue);result["materials"]=Json::Value(Json::arrayValue);
          for(const auto& row:observed->options) {Json::Value value;value["kind"]=row.kind;value["index"]=row.index;value["caption"]=DF2UTF(row.caption);result["options"].append(value);}
          for(const auto& row:observed->materials) {Json::Value value;value["type"]=row.type;value["index"]=row.index;value["count"]=row.count;value["caption"]=DF2UTF(row.caption);result["materials"].append(value);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="work-orders-catalog-probe" || parameters[0]=="workshop-task-templates-probe") {
          if(parameters.size()>2)return CR_WRONG_USAGE;
          int32_t id=-1;
          if(parameters.size()==2) {
            const auto& raw=parameters[1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          }
          const auto catalog=id<0?df3d_production::nativeWorkOrderCatalog():df3d_production::nativeWorkshopOrderCatalog(df::building::find(id));
          if(!catalog)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["rows"]=Json::Value(Json::arrayValue);
          for(const auto& row:*catalog) {
            Json::Value value;value["job_type"]=int(row.job_type);value["reaction"]=row.reaction_name;
            value["item_type"]=int(row.item_type);value["item_subtype"]=row.item_subtype;
            value["mat_type"]=row.mat_type;value["mat_index"]=row.mat_index;
            value["caption"]=DF2UTF(row.name);value["compare"]=DF2UTF(row.compare_str);
            if(parameters[0]=="workshop-task-templates-probe") {
              value["material_category"]=row.material_category.whole;
              value["specflag"]=row.specflag.whole;value["specdata"]=row.specdata.hist_figure_id;
              value["art_type"]=int(row.art_specifier);value["art_id"]=row.art_specifier_id1;value["art_subid"]=row.art_specifier_id2;
            }
            result["rows"].append(value);
          }
          if(id<0) {
            const auto groups=df3d_production::nativeWorkOrderGroups(*catalog);if(!groups)return CR_FAILURE;
            result["groups"]=Json::Value(Json::arrayValue);
            for(const auto& group:*groups) {
              Json::Value value;value["type"]=group.type;value["subtype"]=group.subtype;value["custom"]=group.custom;
              value["name"]=DF2UTF(group.name);value["rows"]=Json::Value(Json::arrayValue);
              for(auto index:group.rows)value["rows"].append(result["rows"][Json::ArrayIndex(index)]);
              result["groups"].append(std::move(value));
            }
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="workshop-orders-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          const auto profile=df3d_production::workshopOrdersProfile(df::building::find(id));
          if(!profile)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["building_id"]=profile->buildingId;
          result["revision"]=std::to_string(profile->revision);
          result["manager_available"]=profile->managerAvailable;
          result["general_order_limit"]=profile->generalOrderLimit;
          result["order_ids"]=Json::Value(Json::arrayValue);
          for(const auto order:profile->orderIds)result["order_ids"].append(order);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="lever-target-probe" || parameters[0]=="lever-link-probe") {
          const bool editing=parameters[0]=="lever-link-probe";
          if(parameters.size()!=(editing?7:5))return CR_WRONG_USAGE;
          if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
          int32_t values[6]{};
          for(size_t i=1;i<parameters.size();++i) {
            const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<0 || (i>=2 && i<=4 && values[i-1]>32767))return CR_WRONG_USAGE;
          }
          auto* source=df::building::find(values[0]);const df::coord pos(values[1],values[2],values[3]);
          const auto target=df3d_production::leverLinkTargetAt(source,pos);if(!target)return CR_FAILURE;
          Json::Value result;result["building_id"]=values[0];result["target_id"]=*target;
          if(editing) {
            auto* job=df3d_production::linkLeverNative(source,pos,values[4],values[5]);if(!job)return CR_FAILURE;
            result["job_id"]=job->id;
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="lever-mechanisms-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          const auto selected=df3d_production::leverInitialMechanisms(df::building::find(id));
          if(!selected)return CR_FAILURE;
          Json::Value result;result["building_id"]=id;result["lever_mechanism"]=(*selected)[0];result["target_mechanism"]=(*selected)[1];
          result["available"]=(*selected)[0]>=0 && (*selected)[1]>=0;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="lever-pull-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          auto* job=df3d_production::pullLeverNative(df::building::find(id));
          if(!job)return CR_FAILURE;
          Json::Value result;result["building_id"]=id;result["job_id"]=job->id;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="building-links-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          const auto snapshot=df3d_production::buildingLinks(df::building::find(id));
          if(!snapshot)return CR_FAILURE;
          Json::Value result;result["building_id"]=snapshot->buildingId;result["revision"]=std::to_string(snapshot->revision);
          result["tabs"]=snapshot->tabs;result["rows"]=Json::Value(Json::arrayValue);
          for(const auto& row:snapshot->rows) {
            Json::Value value;value["item_id"]=row.itemId;value["reference_type"]=row.referenceType;
            value["id"]=row.id;value["type"]=row.type;value["name"]=DF2UTF(row.name);
            value["x"]=row.x;value["y"]=row.y;value["z"]=row.z;result["rows"].append(value);
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="funerary-body-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          const auto body=df3d_production::funeraryBody(df::building::find(id));
          if(!body)return CR_FAILURE;
          Json::Value result;result["building_id"]=body->buildingId;result["unit_id"]=body->unitId;
          result["historical_figure_id"]=body->historicalFigureId;
          result["introduction"]=DF2UTF(body->introduction);result["name"]=DF2UTF(body->name);
          result["room_id"]=body->roomId;result["room_type"]=body->roomType;
          result["room_introduction"]=DF2UTF(body->roomIntroduction);result["room_name"]=DF2UTF(body->roomName);
          result["deceased"]=DF2UTF(body->deceased);result["notices"]=Json::Value(Json::arrayValue);
          for(const auto& notice:body->notices)result["notices"].append(DF2UTF(notice));
          if(body->ownerAppearance) {
            const auto& recipe=*body->ownerAppearance;auto& art=result["owner_appearance"];
            art["pages"]=Json::Value(Json::arrayValue);art["palettes"]=Json::Value(Json::arrayValue);art["layers"]=Json::Value(Json::arrayValue);
            for(const auto& name:recipe.pages)art["pages"].append(name);
            for(const auto& name:recipe.palettes)art["palettes"].append(name);
            for(const auto& layer:recipe.layers){Json::Value values(Json::arrayValue);for(auto value:layer)values.append(value);art["layers"].append(values);}
          }
          result["zones"]=Json::Value(Json::arrayValue);for(const auto id:body->relevantZones)result["zones"].append(id);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="workshop-workers-probe") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          const auto candidates=df3d_production::workshopWorkerCandidates(df::building::find(id));
          if(!candidates)return CR_FAILURE;
          const auto skills=df3d_production::workshopWorkerSkills(df::building::find(id));
          const auto rows=df3d_area::observeNativeWorkshopWorkerRows(id);
          const auto profile=df3d_production::workshopWorkerProfile(df::building::find(id));
          if(!skills || !rows || !profile)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["ids"]=Json::Value(Json::arrayValue);
          result["revision"]=std::to_string(profile->revision);
          result["permitted_workers"]=Json::Value(Json::arrayValue);
          for(const auto worker:profile->permittedWorkers)result["permitted_workers"].append(worker);
          if(profile->assigned) {
            const auto& a=*profile->assigned;Json::Value value;
            value["id"]=a.id;value["caption"]=DF2UTF(a.caption);value["specialization_visible"]=a.specializationVisible;
            value["can_specialize"]=a.canSpecialize;value["specialized"]=a.specialized;result["assigned"]=value;
          }
          result["skills"]=Json::Value(Json::arrayValue);result["rows"]=Json::Value(Json::arrayValue);
          for(const auto unit:*candidates)result["ids"].append(unit);
          for(const auto& [skill,weight]:*skills){Json::Value value;value["skill"]=skill;value["weight"]=weight;result["skills"].append(value);}
          for(const auto& row:*rows){Json::Value value;value["id"]=row.unitId;value["name"]=row.name;value["score"]=row.score;
            value["assignments"]=Json::Value(Json::arrayValue);
            for(const auto& a:row.assignments){Json::Value entry;entry["kind"]=int(a.kind);entry["id"]=a.id;entry["type"]=a.type;
              entry["subtype"]=a.subtype;entry["custom"]=a.custom;entry["name"]=a.name;entry["custom_code"]=a.customCode;value["assignments"].append(entry);}
            result["rows"].append(value);}
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="workshop-forge-choices-probe") {
          if(parameters.size()!=3 && parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t values[3];
          for(size_t i=0;i<parameters.size()-1;++i) {
            const auto& raw=parameters[i+1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(values[1]==6 || parameters.size()==4) {
            if(values[1]==6 && parameters.size()!=3)return CR_WRONG_USAGE;
            const auto choices=values[1]==6?df3d_production::workshopForgeClothing(df::building::find(values[0])):
                df3d_production::workshopForgeTasks(df::building::find(values[0]),values[1],values[2]);
            if(!choices)return CR_FAILURE;
            Json::Value rows(Json::arrayValue);
            for(const auto& choice:*choices) {
              Json::Value row;row["job_type"]=int(choice.job_type);row["item_subtype"]=choice.item_subtype;
              row["mat_type"]=choice.mat_type;row["mat_index"]=choice.mat_index;
              row["material_category"]=choice.material_category.whole;row["specflag"]=choice.specflag.whole;
              row["specdata"]=choice.specdata.hist_figure_id;row["art_type"]=int(choice.art_specifier);
              row["art_id"]=choice.art_specifier_id1;row["art_subid"]=choice.art_specifier_id2;
              row["caption"]=DF2UTF(choice.name);rows.append(std::move(row));
            }
            out.print("{}",Json::FastWriter().write(rows));return CR_OK;
          }
          const auto choices=df3d_production::workshopForgeChoices(df::building::find(values[0]),values[1]);
          if(!choices)return CR_FAILURE;
          Json::Value rows(Json::arrayValue);
          for(const auto& choice:*choices) {
            Json::Value row(Json::objectValue);row["category"]=choice.category;
            row["material_index"]=choice.materialIndex;row["caption"]=DF2UTF(choice.caption);rows.append(std::move(row));
          }
          out.print("{}",Json::FastWriter().write(rows));return CR_OK;
        }
        if(parameters[0]=="workshop-dye-counts-probe") {
          if(parameters.size()!=1)return CR_WRONG_USAGE;
          if(!df::global::world || !df3d_production::workOrderDyeReady())return CR_FAILURE;
          auto colors=df::global::world->raws.descriptors.colors;
          if(colors.size()>1024)return CR_FAILURE;
          for(const auto* color:colors)if(!color)return CR_FAILURE;
          auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
          std::vector<int32_t> tint(colors.size()),mix(colors.size());
          for(int32_t a=0;size_t(a)<colors.size();++a)for(int32_t b=0;size_t(b)<colors.size();++b) {
            if(a==b)continue;
            std::array<int32_t,7> results;results.fill(-1);
            reinterpret_cast<void(*)(std::vector<df::descriptor_color*>*,int32_t,int32_t,int32_t*)>(base+0x7dc570)(&colors,a,b,results.data());
            std::set<int32_t> targets;
            for(auto color:results) {
              if(color==-1 || color==a || color==b)continue;
              if(color<0 || size_t(color)>=colors.size())return CR_FAILURE;
              targets.insert(color);
            }
            for(auto color:targets){++tint[color];if(a<b && colors[color]->id!="CLEAR")++mix[color];}
          }
          Json::Value rows(Json::arrayValue);
          for(size_t i=0;i<colors.size();++i) {
            Json::Value row(Json::objectValue);row["color"]=int(i);row["name"]=DF2UTF(colors[i]->name);
            row["tint"]=tint[i];row["mix"]=mix[i];rows.append(std::move(row));
          }
          out.print("{}",Json::FastWriter().write(rows));return CR_OK;
        }
        if(parameters[0]=="workshop-dye-targets-probe") {
          if(parameters.size()!=3 && parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t ids[3]={-1,-1,-1};
          for(size_t i=0;i+1<parameters.size();++i) {
            const auto& raw=parameters[i+1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),ids[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || ids[i]<0)return CR_WRONG_USAGE;
          }
          const auto choices=df3d_production::workshopDyeTargets(df::building::find(ids[0]),ids[1],ids[2]);
          if(!choices)return CR_FAILURE;
          Json::Value rows(Json::arrayValue);
          for(const auto& choice:*choices) {
            Json::Value row(Json::objectValue);row["color"]=choice.color;row["available"]=choice.available;
            row["alpha_order"]=choice.alphaOrder;row["tint"]=choice.tint;
            row["caption"]=DF2UTF(choice.caption);row["info"]=DF2UTF(choice.info);rows.append(std::move(row));
          }
          out.print("{}",Json::FastWriter().write(rows));return CR_OK;
        }
        if(parameters[0]=="workshop-reactions-probe" || parameters[0]=="workshop-reaction-categories-probe") {
          if(parameters.size()!=2 && parameters.size()!=3)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          auto* shop=df::building::find(id);if(!shop)return CR_FAILURE;
          const std::string category=parameters.size()==3?parameters[2]:"";
          if(parameters[0]=="workshop-reaction-categories-probe") {
            const auto choices=df3d_production::workshopReactionCategories(shop,category);if(!choices)return CR_FAILURE;
            Json::Value rows(Json::arrayValue);
            for(const auto& choice:*choices) {
              Json::Value row(Json::objectValue);row["code"]=DF2UTF(choice.code);
              row["caption"]=DF2UTF(choice.caption);row["hotkey"]=choice.hotkey;rows.append(std::move(row));
            }
            out.print("{}",Json::FastWriter().write(rows));return CR_OK;
          }
          const auto choices=df3d_production::workshopReactionRows(shop,category);if(!choices)return CR_FAILURE;
          Json::Value rows(Json::arrayValue);
          for(const auto& choice:*choices) {
            Json::Value row(Json::objectValue);row["raw_index"]=choice.rawIndex;row["code"]=DF2UTF(choice.code);
            row["caption"]=DF2UTF(choice.caption);row["objection"]=DF2UTF(choice.objection);row["available"]=choice.available;
            rows.append(std::move(row));
          }
          out.print("{}",Json::FastWriter().write(rows));return CR_OK;
        }
        if(parameters[0]=="workshop-requirements-probe") {
          if(parameters.size()!=3)return CR_WRONG_USAGE;
          int32_t ids[2];
          for(int i=0;i<2;++i) {
            const auto& raw=parameters[i+1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),ids[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || ids[i]<0)return CR_WRONG_USAGE;
          }
          auto* shop=df::building::find(ids[0]);if(!shop)return CR_FAILURE;
          df::job* source=nullptr;for(auto* job:shop->jobs)if(job && job->id==ids[1])source=job;
          if(!source)return CR_FAILURE;
          df::job owned;owned.id=-1;owned.list_link=nullptr;
          owned.job_type=source->job_type;owned.item_type=source->item_type;owned.item_subtype=source->item_subtype;
          owned.mat_type=source->mat_type;owned.mat_index=source->mat_index;owned.material_category=source->material_category;
          owned.specflag=source->specflag;owned.specdata=source->specdata;owned.art_spec=source->art_spec;
          owned.reaction_name=source->reaction_name;
          struct Cleanup {df::job& job;~Cleanup(){for(auto* item:job.job_items.elements)delete item;}} cleanup{owned};
          if(!df3d_production::workshopRequirements(owned,shop))return CR_FAILURE;
          const auto fields=[](const df::job_item& v) {
            return std::make_tuple(v.item_type,v.item_subtype,v.mat_type,v.mat_index,v.flags1.whole,v.quantity,
              v.vector_id,v.flags2.whole,v.flags3.whole,v.flags4,v.flags5,v.metal_ore,v.reaction_class,
              v.has_material_reaction_product,v.min_dimension,v.reagent_index,v.contains,v.reaction_id,
              v.has_tool_use,v.dye_color,v.job_details_flags.whole,v.job_details_mat_type,
              v.job_details_mat_index,v.job_details_item_flags2.whole);
          };
          bool equal=owned.job_items.elements.size()==source->job_items.elements.size();
          if(equal)for(size_t i=0;i<owned.job_items.elements.size();++i)
            if(fields(*owned.job_items.elements[i])!=fields(*source->job_items.elements[i]))equal=false;
          Json::Value result(Json::objectValue);result["equal"]=equal;
          result["requirements"]=Json::UInt(owned.job_items.elements.size());
          const auto caption=df3d_production::workshopJobCaption(owned);if(!caption)return CR_FAILURE;
          result["caption"]=DF2UTF(*caption);
          out.print("{}",Json::FastWriter().write(result));return equal?CR_OK:CR_FAILURE;
        }
        if(parameters[0]=="farm-contents-read") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{}||parsed.ptr!=raw.data()+raw.size()||id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          auto* farm=virtual_cast<df::building_farmplotst>(df::building::find(id));
          auto* tile=farm?Maps::getTileDesignation(farm->centerx,farm->centery,farm->z):nullptr;
          if(!tile||tile->bits.hidden)return CR_FAILURE;
          const auto snapshot=df3d_production::buildingContents(farm);if(!snapshot)return CR_FAILURE;
          Json::Value result(Json::objectValue),rows(Json::arrayValue);
          for(const auto& item:snapshot->rows) {
            Json::Value row(Json::objectValue);row["id"]=item.id;
            row["role_value"]=item.role;row["name"]=DF2UTF(item.caption);
            row["item_type"]=item.itemType;row["material_token"]=DF2UTF(item.materialToken);row["subtype_raw"]=DF2UTF(item.subtypeRaw);
            row["flags"]=Json::UInt(item.flags);row["countdown"]=int(item.countdown);row["delay"]=int(item.delay);
            row["can_dump"]=item.canDump;row["can_melt"]=item.canMelt;
            rows.append(std::move(row));
          }
          result["building_id"]=id;result["revision"]=std::to_string(snapshot->revision);
          result["rows"]=std::move(rows);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="farm-item-edit") {
          if(parameters.size()!=6)return CR_WRONG_USAGE;
          auto parse=[](const std::string& raw,auto& value) {
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);
            return parsed.ec==std::errc{}&&parsed.ptr==raw.data()+raw.size();
          };
          int32_t building=-1,itemId=-1,want=-1;uint64_t expected=0;
          if(!parse(parameters[1],building)||!parse(parameters[2],itemId)||
             !parse(parameters[4],want)||!parse(parameters[5],expected)||building<0||itemId<0||want<0||want>1)return CR_WRONG_USAGE;
          using A=df3d_production::BuildingItemAction;A action;
          if(parameters[3]=="forbid")action=A::Forbid;else if(parameters[3]=="dump")action=A::Dump;
          else if(parameters[3]=="melt")action=A::Melt;else if(parameters[3]=="hidden")action=A::Hidden;else return CR_WRONG_USAGE;
          if(!state.mapLoaded||df3d_session::saving())return CR_FAILURE;
          auto* farm=virtual_cast<df::building_farmplotst>(df::building::find(building));
          auto* tile=farm?Maps::getTileDesignation(farm->centerx,farm->centery,farm->z):nullptr;
          if(!tile||tile->bits.hidden||farm->getBuildStage()!=farm->getMaxBuildStage()||Buildings::markedForRemoval(farm))return CR_FAILURE;
          const auto observe=[&]()->std::optional<df3d_production::BuildingContentsSnapshot> {
            auto* current=virtual_cast<df::building_farmplotst>(df::building::find(building));
            auto* designation=current?Maps::getTileDesignation(current->centerx,current->centery,current->z):nullptr;
            if(!designation||designation->bits.hidden)return std::nullopt;
            return df3d_production::buildingContents(current);
          };
          const auto before=observe();if(!before)return CR_FAILURE;
          const auto edit=df3d_production::finishBuildingItemEdit(*before,expected,itemId,action,want!=0,[&] {
            auto* current=virtual_cast<df::building_farmplotst>(df::building::find(building));
            if(!current)return false;
            for(auto* held:current->contained_items)if(held&&held->item&&held->item->id==itemId)
              return df3d_production::setBuildingItemFlag(held->item,action,want!=0);
            return false;
          },observe);
          Json::Value result(Json::objectValue);result["item_id"]=itemId;
          using O=df3d_production::FarmEditOutcome;
          result["outcome"]=edit.outcome==O::Completed?"completed":edit.outcome==O::Stale?"stale":edit.outcome==O::Unknown?"unknown":"rejected";
          result["mutated"]=edit.mutated;
          if(edit.receipt) {
            result["revision"]=std::to_string(edit.receipt->revision);
            for(const auto& row:edit.receipt->rows)if(row.id==itemId)result["after_flags"]=Json::UInt(row.flags);
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="pending-building") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t id=-1;uint64_t revision=0;
          const auto parse=[](const std::string& raw,auto& value){const auto p=std::from_chars(raw.data(),raw.data()+raw.size(),value);return p.ec==std::errc{} && p.ptr==raw.data()+raw.size();};
          const auto& op=parameters[3];
          if(!parse(parameters[1],id) || !parse(parameters[2],revision) || (op!="read" && op!="resume" && op!="suspend" && op!="cancel" && op!="cancel-removal"))return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          df3d_production::PendingBuildingEdit edit;auto* target=df::building::find(id);
          if(op=="read") {
            if(revision)return CR_WRONG_USAGE;
            edit.receipt=df3d_production::observePendingBuilding(target);
            if(edit.receipt)edit.outcome=df3d_production::BuildingHeaderOutcome::Completed;
          } else {
            using Op=df3d_production::PendingBuildingOperation;
            edit=df3d_production::editPendingBuilding(target,revision,op=="resume"?Op::Resume:op=="suspend"?Op::Suspend:op=="cancel-removal"?Op::CancelRemoval:Op::Cancel);
          }
          Json::Value value(Json::objectValue);value["outcome"]=int(edit.outcome);value["mutated"]=edit.mutated;value["removed"]=edit.removed;value["removing"]=edit.removing;
          if(edit.receipt){const auto& r=*edit.receipt;value["id"]=r.id;value["stage"]=r.stage;value["max_stage"]=r.maxStage;value["job_id"]=r.jobId;value["flags"]=r.jobFlags;value["is_removing"]=r.removing;value["revision"]=std::to_string(r.revision);value["workers"]=Json::arrayValue;for(auto worker:r.workers)value["workers"].append(worker);}
          if(op=="read" && edit.receipt){const auto duration=df3d_production::pendingBuildDuration(target);
            if(duration)value["build_duration"]=*duration;}
          out.print("{}",Json::FastWriter().write(value));return CR_OK;
        }
        if(parameters[0]=="door-control") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t id=-1;uint64_t revision=0;
          const auto parse=[](const std::string& raw,auto& value){const auto p=std::from_chars(raw.data(),raw.data()+raw.size(),value);return p.ec==std::errc{} && p.ptr==raw.data()+raw.size();};
          if(!parse(parameters[1],id) || !parse(parameters[2],revision) ||
             (parameters[3]!="read" && parameters[3]!="forbid" && parameters[3]!="passable"))return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          auto* target=df::building::find(id);df3d_production::DoorEdit edit;
          if(parameters[3]=="read") {
            if(revision)return CR_WRONG_USAGE;
            edit.receipt=df3d_production::observeDoor(target);
            if(edit.receipt)edit.outcome=df3d_production::BuildingHeaderOutcome::Completed;
          } else edit=df3d_production::setDoorForbidden(target,revision,parameters[3]=="forbid");
          Json::Value value(Json::objectValue);value["outcome"]=int(edit.outcome);value["mutated"]=edit.mutated;
          if(edit.receipt){const auto& r=*edit.receipt;value["id"]=r.id;value["flags"]=r.flags;value["occupancy"]=r.occupancy;value["revision"]=std::to_string(r.revision);}
          out.print("{}",Json::FastWriter().write(value));return CR_OK;
        }
        if(parameters[0]=="building-header-action") {
          if(parameters.size()<4 || parameters.size()>5)return CR_WRONG_USAGE;
          int32_t id=-1;uint64_t revision=0;
          const auto parse=[](const std::string& raw,auto& value) {
            const auto result=std::from_chars(raw.data(),raw.data()+raw.size(),value);
            return result.ec==std::errc{} && result.ptr==raw.data()+raw.size();
          };
          if(!parse(parameters[1],id) || id<0 || !parse(parameters[2],revision))return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto target=[&]()->df::building* {
            auto* building=df::building::find(id);
            if(!building || building->getType()!=df::building_type::Box)return nullptr;
            auto* tile=Maps::getTileDesignation(building->centerx,building->centery,building->z);
            return tile && !tile->bits.hidden?building:nullptr;
          };
          const auto observe=[&]{return df3d_production::observeBuildingHeader(target());};
          const auto before=observe();if(!before)return CR_FAILURE;
          using Operation=df3d_production::BuildingHeaderOperation;
          using Outcome=df3d_production::BuildingHeaderOutcome;
          df3d_production::BuildingHeaderEdit edit;
          const auto& op=parameters[3];
          if(op=="read" && parameters.size()==4 && revision==0) {
            edit.outcome=Outcome::Completed;edit.receipt=before;
          } else {
            const bool rename=op=="rename";
            if((rename && parameters.size()!=5) || (!rename && parameters.size()!=4) ||
               (op!="rename" && op!="remove" && op!="cancel"))return CR_WRONG_USAGE;
            const auto operation=rename?Operation::Rename:op=="remove"?Operation::Remove:Operation::CancelRemoval;
            const auto name=rename?UTF2DF(parameters[4]):std::string{};
            if(rename && DF2UTF(name)!=parameters[4])return CR_FAILURE;
            edit=df3d_production::finishBuildingHeaderEdit(*before,revision,operation,name,[&]{
              auto* building=target();if(!building)return false;
              if(rename){building->name=name;return true;}
              if(operation==Operation::CancelRemoval)return df3d_production::cancelBuildingRemoval(building);
              building->queueDestroy();return true;
            },observe);
          }
          Json::Value result(Json::objectValue);
          result["outcome"]=edit.outcome==Outcome::Completed?"completed":edit.outcome==Outcome::Stale?"stale":edit.outcome==Outcome::Unknown?"unknown":"rejected";
          result["mutated"]=edit.mutated;
          if(edit.receipt) {
            const auto& value=*edit.receipt;Json::Value row(Json::objectValue);
            row["id"]=value.id;row["type"]=value.type;row["stage"]=value.stage;row["max_stage"]=value.maxStage;
            row["revision"]=std::to_string(value.revision);row["custom_name"]=DF2UTF(value.customName);
            row["native_name"]=DF2UTF(value.nativeName);row["header_name"]=DF2UTF(value.headerName);
            row["removing"]=value.removing;row["suspended"]=value.suspended;row["has_worker"]=value.hasWorker;
            result["snapshot"]=row;
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="farm-cancel-removal" || parameters[0]=="building-cancel-removal") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          auto* farm=df::building::find(id);
          if(parameters[0]=="farm-cancel-removal" && !virtual_cast<df::building_farmplotst>(farm))return CR_FAILURE;
          auto* tile=farm?Maps::getTileDesignation(farm->centerx,farm->centery,farm->z):nullptr;
          if(!tile || tile->bits.hidden || !df3d_production::cancelBuildingRemoval(farm))return CR_FAILURE;
          out.print("Native building removal cancelled");return CR_OK;
        }
        if(parameters[0]=="farm-header-read"||parameters[0]=="building-header-read") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          auto* farm=df::building::find(id);
          if(parameters[0]=="farm-header-read" && !virtual_cast<df::building_farmplotst>(farm))return CR_FAILURE;
          auto* tile=farm?Maps::getTileDesignation(farm->centerx,farm->centery,farm->z):nullptr;
          if(!tile || tile->bits.hidden)return CR_FAILURE;
          const auto header=df3d_production::buildingHeader(farm);if(!header)return CR_FAILURE;
          Json::Value result(Json::objectValue);result["building_id"]=id;
          result["custom_name"]=DF2UTF(header->customNameCp437);result["native_name"]=DF2UTF(header->nativeNameCp437);
          result["header_name"]=DF2UTF(header->headerNameCp437);
          result["removing"]=header->removing;result["suspended"]=header->suspended;result["has_worker"]=header->hasWorker;
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="farm-eligibility-read") {
          if(parameters.size()!=3)return CR_WRONG_USAGE;
          int32_t values[2]{};
          for(size_t i=0;i<2;++i) {
            const auto& raw=parameters[i+1];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(values[0]<0 || values[1]<0 || values[1]>32767)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          auto* farm=virtual_cast<df::building_farmplotst>(df::building::find(values[0]));
          if(!farm || !df::plant_raw::find(values[1]) || !df::global::plotinfo)return CR_FAILURE;
          const auto& native=df3d_production::farmFunctions();if(!native)return CR_FAILURE;
          std::array<uint8_t,4> seasons{};
          native.seasons(int16_t(values[1]),&seasons);
          Json::Value result(Json::objectValue),flags(Json::arrayValue);
          for(auto value:seasons)flags.append(value!=0);
          result["building_id"]=values[0];result["crop_id"]=values[1];
          result["seasons"]=std::move(flags);result["eligible"]=native.eligible(farm,values[1]);
          result["current_season_warning"]=native.plantingWarning(df::global::plotinfo,int16_t(values[1]));
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="stockpile-tile-types-read") {
          if(parameters.size()!=3)return CR_WRONG_USAGE;
          uint32_t values[2]{};
          for(size_t i=0;i<2;++i) {
            const auto& raw=parameters[i+1];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(values[0]>65535 || values[1]==0 || values[1]>1024 || values[1]>65536-values[0])return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          Json::Value result(Json::objectValue),rows(Json::arrayValue);
          for(uint32_t i=0;i<values[1];++i) {
            const auto allowed=df3d_area::nativeStockpileTileType(uint16_t(values[0]+i));
            if(!allowed)return CR_FAILURE;
            rows.append(*allowed);
          }
          result["first"]=values[0];result["allowed"]=std::move(rows);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="stockpile-summary-read") {
          if(parameters.size()<2 || parameters.size()>3)return CR_WRONG_USAGE;
          int32_t id{};const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          uint32_t categories=0x1ffff;
          if(parameters.size()==3) {
            const auto& mask=parameters[2];
            const auto value=std::from_chars(mask.data(),mask.data()+mask.size(),categories);
            if(value.ec!=std::errc{} || value.ptr!=mask.data()+mask.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          return df3d_management::printStockpileSummaries(out,id,categories)?CR_OK:CR_FAILURE;
        }
        if(parameters[0]=="stockpile-rows-read" || parameters[0]=="stockpile-rows-cold-read") {
          if(parameters.size()<3 || parameters.size()>4)return CR_WRONG_USAGE;
          int32_t values[2]{};
          for(size_t i=0;i<2;++i) {
            const auto& raw=parameters[i+1];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          return df3d_management::printStockpileRows(out,values[0],values[1],parameters.size()==4?parameters[3]:"",parameters[0]=="stockpile-rows-cold-read")?CR_OK:CR_FAILURE;
        }
        if(parameters[0]=="stockpile-wood-read") {
          if(parameters.size()<2 || parameters.size()>3)return CR_WRONG_USAGE;
          int32_t id{};const auto& raw=parameters[1];
          const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          return df3d_management::printStockpileWoodRows(out,id,parameters.size()==3?parameters[2]:"")?CR_OK:CR_FAILURE;
        }
        if(parameters[0]=="stockpile-preset-read" || parameters[0]=="stockpile-category-read" || parameters[0]=="stockpile-header-read") {
          const bool header=parameters[0]=="stockpile-header-read";
          if(parameters.size()!=(header?4:3))return CR_WRONG_USAGE;
          int32_t values[3]{};
          for(size_t i=0;i<(header?3u:2u);++i) {
            const auto& raw=parameters[i+1];
            const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
          }
          if(header && values[2]!=1 && values[2]!=2)return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const bool ok=header?df3d_management::printStockpileHeader(out,values[0],uint32_t(values[1]),values[2]==2):
              parameters[0]=="stockpile-category-read"?
              df3d_management::printStockpileCategory(out,values[0],uint32_t(values[1])):
              df3d_management::printStockpilePreset(out,values[0],values[1]);
          return ok?CR_OK:CR_FAILURE;
        }
        if(parameters[0]=="engraving-art-draft-probe") {
          const char* oracle=std::getenv("DF3D_TILE_SELECTION_ENGRAVING_DRAFT");
          if(!oracle || std::string_view(oracle)!="1")return CR_FAILURE;
          if(parameters.size()!=5)return CR_WRONG_USAGE;
          int32_t p[4]{};for(size_t i=0;i<4;++i){const auto& v=parameters[i+1];auto parsed=std::from_chars(v.data(),v.data()+v.size(),p[i]);if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;}
          if(!state.mapLoaded || df3d_session::saving() || p[3]<0 || p[3]>1)return CR_FAILURE;
          const auto read=[&](int16_t page,df3d_production::WorkOrderArtDraftValue value,uint8_t action,
              const std::optional<df3d_production::WorkOrderArtDraftElementValue>& element=std::nullopt,uint64_t list=0) {
            return df3d_selection::engravingArtDraftPage(p[0],p[1],p[2],page,std::move(value),action,element,std::nullopt,-1,{},0,list,98);
          };
          auto root=read(6,{},0),choices=read(7,{},0);
          if(!root || !choices || choices->page.rows.empty())return CR_FAILURE;
          const auto first=choices->page.rows.front();
          auto populated=read(7,{},1,df3d_production::WorkOrderArtDraftElementValue{7,first.id,first.secondary,1});
          if(!populated || !populated->page.draftDescription || !populated->page.draft)return CR_FAILURE;
          Json::Value result;result["caption"]=DF2UTF(root->page.caption);result["race"]=first.id;result["caste"]=first.secondary;result["total"]=choices->page.total;
          result["rows"]=Json::Value(Json::arrayValue);result["description"]=Json::Value(Json::arrayValue);
          for(const auto& row:root->page.rows)result["rows"].append(DF2UTF(row.caption));
          for(const auto& line:*populated->page.draftDescription)result["description"].append(DF2UTF(line));
          result["stale_list_rejected"]=!read(7,{},0,std::nullopt,choices->page.listRevision==1?2:1);
          if(p[3]) {
            auto name=df3d_production::WorkOrderArtDraft::create(df::image_creator_context_type::DESIGNATION_ENGRAVING);
            if(!name || !name->generateName())return CR_FAILURE;
            auto value=*populated->page.draft;value.name=name->image().name;
            auto before=df3d_selection::engravingArtSource(p[0],p[1],p[2]);if(!before)return CR_FAILURE;
            auto& resources=df::global::plotinfo->main.fortress_entity->resources;auto count=resources.art_image_ids.size();
            const auto apply=[&](uint64_t revision,const auto& v){return df3d_selection::commitEngravingArtDraft(p[0],p[1],p[2],revision,v);};
            using O=df3d_selection::EngravingArtDraftOutcome;
            result["stale_revision_rejected"]=apply(before->revision==1?2:1,value)==O::Stale;
            auto invalid=value;invalid.elements[0].id=INT32_MAX;
            result["invalid_element_rejected"]=apply(before->revision,invalid)==O::Rejected;
            auto unchanged=df3d_selection::engravingArtSource(p[0],p[1],p[2]);
            result["rejections_unchanged"]=unchanged && unchanged->revision==before->revision && resources.art_image_ids.size()==count;
            result["applied"]=apply(before->revision,value)==O::Applied;
            auto after=df3d_selection::engravingArtSource(p[0],p[1],p[2]);if(!after)return CR_FAILURE;
            result["type"]=int(after->detail.art_specifier);result["id"]=after->detail.art_spec_id1;result["subid"]=after->detail.art_spec_id2;
            result["one_registered"]=resources.art_image_ids.size()==count+1 && resources.art_image_ids.back()==after->detail.art_spec_id1 && resources.art_image_subids.back()==after->detail.art_spec_id2;
          }
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        if(parameters[0]=="engraving-art-page-probe" || parameters[0]=="engraving-art-apply-probe") {
          const char* oracle=std::getenv("DF3D_TILE_SELECTION_ENGRAVING_IMAGE");
          if(!oracle || std::string_view(oracle)!="1")return CR_FAILURE;
          const bool apply=parameters[0]=="engraving-art-apply-probe";
          if(parameters.size()!=(apply?9:6))return CR_WRONG_USAGE;
          int32_t p[5]{};uint64_t revision=0,listRevision=0;
          const auto parse=[](const std::string& v,auto& target){auto parsed=std::from_chars(v.data(),v.data()+v.size(),target);return parsed.ec==std::errc{} && parsed.ptr==v.data()+v.size();};
          for(size_t i=0;i<(apply?5:4);++i)if(!parse(parameters[i+1],p[i]))return CR_WRONG_USAGE;
          if(p[3]<-1 || p[3]>6)return CR_WRONG_USAGE;
          if(apply && (!parse(parameters[6],revision) || !parse(parameters[7],listRevision)))return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          Json::Value value(Json::objectValue);
          if(apply) {
            const auto outcome=df3d_selection::applyEngravingArtSubject(p[0],p[1],p[2],revision,p[3],p[4],listRevision,UTF2DF(parameters[8]));
            value["outcome"]=int(outcome);
          } else {
            const auto page=df3d_selection::engravingArtPage(p[0],p[1],p[2],int16_t(p[3]),UTF2DF(parameters[5]));
            value["valid"]=page.has_value();
            if(page){value["revision"]=std::to_string(page->revision);value["list_revision"]=std::to_string(page->page.listRevision);
              value["caption"]=DF2UTF(page->page.caption);value["total"]=page->page.total;
              value["rows"]=Json::Value(Json::arrayValue);
              for(const auto& row:page->page.rows){Json::Value r(Json::objectValue);r["id"]=row.id;r["caption"]=DF2UTF(row.caption);value["rows"].append(r);}}
          }
          out.print("{}",Json::FastWriter().write(value));return CR_OK;
        }
        if(parameters[0]=="engraving-art-subjects-probe") {
          const char* oracle=std::getenv("DF3D_TILE_SELECTION_ENGRAVING_IMAGE");
          if(!oracle || std::string_view(oracle)!="1")return CR_FAILURE;
          if(parameters.size()!=5)return CR_WRONG_USAGE;
          int32_t p[4]{};
          for(size_t i=0;i<4;++i){const auto& v=parameters[i+1];const auto parsed=std::from_chars(v.data(),v.data()+v.size(),p[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;}
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto subjects=df3d_selection::engravingArtSubjects(p[0],p[1],p[2],p[3]);
          Json::Value value(Json::objectValue);value["valid"]=subjects.has_value();
          if(subjects){value["ids"]=Json::Value(Json::arrayValue);for(auto id:subjects->ids)value["ids"].append(id);}
          out.print("{}",Json::FastWriter().write(value));return CR_OK;
        }
        if(parameters[0]=="engraving-description-probe") {
          const char* oracle=std::getenv("DF3D_TILE_SELECTION_ENGRAVING");
          if(!oracle || std::string_view(oracle)!="1")return CR_FAILURE;
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t p[3]{};
          for(size_t i=0;i<3;++i) {
              const auto& v=parameters[i+1];
              const auto parsed=std::from_chars(v.data(),v.data()+v.size(),p[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          std::string failure;
          const auto description=df3d_selection::engravingDescription(p[0],p[1],p[2],failure);
          Json::Value value(Json::objectValue);value["valid"]=description.has_value();
          if(description){value["title"]=description->title;value["description"]=description->description;}
          else value["failure"]=failure;
          out.print("{}",Json::FastWriter().write(value));return CR_OK;
        }
        if(parameters[0]=="vermin-description-read") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;const auto& arg=parameters[1];
          const auto parsed=std::from_chars(arg.data(),arg.data()+arg.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=arg.data()+arg.size())return CR_WRONG_USAGE;
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto text=df3d_selection::verminDescription(id);
          Json::Value value(Json::objectValue);value["valid"]=text.has_value();
          if(text){value["title"]=text->title;value["description"]=text->description;value["race"]=text->race;value["caste"]=text->caste;}
          out.print("{}",Json::FastWriter().write(value));return CR_OK;
        }
        if(parameters[0]=="tile-selection-read") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t p[3]{};
          for(size_t i=0;i<3;++i) {
              const auto& v=parameters[i+1];
              const auto parsed=std::from_chars(v.data(),v.data()+v.size(),p[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto selection=df3d_selection::collect(p[0],p[1],p[2]);
          Json::Value value(Json::objectValue);value["valid"]=selection.has_value();
          if(selection) {
              const auto ids=[](const auto& source){Json::Value rows(Json::arrayValue);for(auto id:source)rows.append(id);return rows;};
              value["units"]=ids(selection->units);value["items"]=ids(selection->items);value["vermin"]=ids(selection->vermin);
              value["building"]=selection->building;value["active_kind"]=int(selection->active.kind);value["active_id"]=selection->active.id;
              value["tabs"]=Json::Value(Json::arrayValue);
              for(const auto& target:selection->tabs){Json::Value row(Json::objectValue);row["kind"]=int(target.kind);row["id"]=target.id;value["tabs"].append(row);}
          }
          out.print("{}",Json::FastWriter().write(value));return CR_OK;
        }
        if(parameters[0]=="tile-description-read") {
          if(parameters.size()!=4)return CR_WRONG_USAGE;
          int32_t p[3]{};
          for(size_t i=0;i<3;++i) {
              const auto& v=parameters[i+1];
              const auto parsed=std::from_chars(v.data(),v.data()+v.size(),p[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          const auto description=df3d_hover::terrain(p[0],p[1],p[2]);
          Json::Value value(Json::objectValue);value["valid"]=description.has_value();
          if(description)value["text"]=*description;
          out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if(parameters[0]=="door-support-read" || parameters[0]=="site-support-read") {
          const bool typed=parameters[0]=="site-support-read";
          const bool rectangle=typed && parameters.size()==7 && parameters[1]=="BridgePerimeter";
          if(!rectangle && parameters.size()!=(typed?5:4))return CR_WRONG_USAGE;
          int32_t p[3]{};
          for(size_t i=0;i<3;++i){const auto& v=parameters[i+(typed?2:1)];
              const auto parsed=std::from_chars(v.data(),v.data()+v.size(),p[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          int32_t dimensions[2]={1,1};
          if(rectangle)for(size_t i=0;i<2;++i) {
              const auto& v=parameters[i+5];
              const auto parsed=std::from_chars(v.data(),v.data()+v.size(),dimensions[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          bool randomAdvanced=false;
          const auto support=df3d_construction::siteSupport(typed?parameters[1]:"Door",p[0],p[1],p[2],&randomAdvanced,dimensions[0],dimensions[1]);
          out.print("{{\"support\":{},\"random_advanced_before_restore\":{}}}\n",support,randomAdvanced);return CR_OK;
      }
      if (parameters[0] == "material-recipe-read" || parameters[0] == "material-candidates-read" || parameters[0] == "material-candidates-cold-read") {
          if(parameters.size()!=3 && parameters.size()!=4 && parameters.size()!=5 && parameters.size()!=6)return CR_WRONG_USAGE;
          int32_t values[5]{0,0,-1,0,-1};
          for(size_t i=0;i<parameters.size()-1;++i){const auto& v=parameters[i+1];const auto r=std::from_chars(v.data(),v.data()+v.size(),values[i]);
              if(r.ec!=std::errc{} || r.ptr!=v.data()+v.size())return CR_WRONG_USAGE;}
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          return df3d_management::printMaterialRecipe(out,values[0],values[1],parameters[0]!="material-recipe-read",parameters[0]=="material-candidates-cold-read",values[2],values[3],values[4])?CR_OK:CR_FAILURE;
      }
      if (parameters[0] == "material-distances-read" || parameters[0] == "track-material-candidates-read" || parameters[0] == "track-material-order-read") {
          if(parameters.size()!=8)return CR_WRONG_USAGE;
          std::array<int32_t,6> positions{};int32_t limit=0;
          for(size_t i=0;i<7;++i) {
              const auto& value=parameters[i+1];int32_t number=0;
              const auto parsed=std::from_chars(value.data(),value.data()+value.size(),number);
              if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
              if(i<6)positions[i]=number;else limit=number;
          }
          if(!state.mapLoaded || df3d_session::saving())return CR_FAILURE;
          if(parameters[0]=="track-material-order-read") {
              if(limit<=0)return CR_WRONG_USAGE;
              return df3d_management::printTrackMaterialCandidates(out,positions,65536,limit)?CR_OK:CR_FAILURE;
          }
          if(parameters[0]=="track-material-candidates-read")
              return df3d_management::printTrackMaterialCandidates(out,positions,limit)?CR_OK:CR_FAILURE;
          return df3d_management::printMaterialDistances(out,positions,limit)?CR_OK:CR_FAILURE;
      }
      if (parameters[0] == "room-create") {
          if(parameters.size()!=8)return CR_WRONG_USAGE;
          int32_t values[6]{};
          for(size_t i=0;i<6;++i) {
              const auto& value=parameters[i+1];
              const auto parsed=std::from_chars(value.data(),value.data()+value.size(),values[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
          }
          uint64_t epoch=0;const auto& value=parameters[7];
          const auto parsed=std::from_chars(value.data(),value.data()+value.size(),epoch);
          if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size() || values[0]<1 || values[0]>4)
              return CR_WRONG_USAGE;
          if(!state.mapLoaded || !epoch || epoch!=state.terrain.epoch() ||
             !df::global::pause_state || !*df::global::pause_state || df3d_session::saving()) {
              out.printerr("df3d: room-create requires the current fortress epoch, paused and not saving\n");
              return CR_FAILURE;
          }
          const auto result=df3d_area::createNativeRooms(static_cast<df3d_area::RoomFurniture>(values[0]),
              {values[1],values[2],values[4],values[5]},values[3]);
          out.print("{{\"status\":{},\"error\":{},\"in_use\":{},\"unenclosed\":{},\"created\":[",
              int(result.status),int(result.error),result.plan.rejectedInUse,result.plan.rejectedUnenclosed);
          for(size_t i=0;i<result.createdIds.size();++i) {
              out.print("{}{}",i?",":"",result.createdIds[i]);
              ent::hintBuilding(result.createdIds[i]);
          }
          out.print("]}}\n");
          return CR_OK;
      }
      if (parameters[0] == "room-plan") {
          if(parameters.size()!=7)return CR_WRONG_USAGE;
          int32_t values[6]{};
          for(size_t i=0;i<6;++i) {
              const auto& value=parameters[i+1];
              const auto parsed=std::from_chars(value.data(),value.data()+value.size(),values[i]);
              if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
          }
          if(values[0]<1 || values[0]>4)return CR_WRONG_USAGE;
          const auto plan=df3d_area::observeNativeRoomPlan(static_cast<df3d_area::RoomFurniture>(values[0]),
              {values[1],values[2],values[4],values[5]},values[3]);
          out.print("{{\"status\":{},\"in_use\":{},\"unenclosed\":{},\"rooms\":[",
              int(plan.status),plan.rejectedInUse,plan.rejectedUnenclosed);
          for(size_t i=0;i<plan.rooms.size();++i) {
              const auto& room=plan.rooms[i];const auto& f=room.footprint;
              out.print("{}{{\"seed\":{},\"dormitory\":{},\"x\":{},\"y\":{},\"z\":{},\"width\":{},\"height\":{},\"extents\":[",
                  i?",":"",room.seedId,room.dormitory,f.bounds.x,f.bounds.y,f.z,f.bounds.width,f.bounds.height);
              for(size_t j=0;j<f.extents.size();++j)out.print("{}{}",j?",":"",int(f.extents[j]));
              out.print("]}}");
          }
          out.print("]}}\n");
          return CR_OK;
      }
      if (parameters[0] == "room-seed") {
          if(parameters.size()!=2)return CR_WRONG_USAGE;
          int32_t id=-1;
          const auto& value=parameters[1];
          const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
          if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
          const auto seed=df3d_area::observeNativeRoomSeed(id);
          out.print("{{\"valid\":{},\"id\":{},\"x\":{},\"y\":{},\"z\":{},\"furniture\":{},\"in_use\":{}}}\n",
              seed.valid,seed.id,seed.x,seed.y,seed.z,int(seed.furniture),seed.inUse);
          return CR_OK;
      }
      if(parameters[0]=="location-specialization-read" || parameters[0]=="location-specialization-set" || parameters[0]=="location-staff-assignments-read") {
        const bool edit=parameters[0]=="location-specialization-set";
        if(parameters.size()!=(edit?9:7))return CR_WRONG_USAGE;
        int32_t ids[6]{};
        for(size_t i=0;i<6;++i) {
          const auto& text=parameters[i+1];const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        if(ids[2]<0 || ids[2]>1)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        const auto source=static_cast<df3d_area::LocationStaffSource>(ids[2]);
        Json::Value value(Json::objectValue);
        if(edit) {
          uint64_t revision=0;const auto& text=parameters[7];
          const auto parsed=std::from_chars(text.data(),text.data()+text.size(),revision);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size() ||
              (parameters[8]!="0" && parameters[8]!="1"))return CR_WRONG_USAGE;
          value["outcome"]=int(df3d_area::setNativeLocationStaffSpecialization(
              ids[0],ids[1],source,ids[3],ids[4],ids[5],revision,parameters[8]=="1"));
        } else if(parameters[0]=="location-staff-assignments-read") {
          const auto receipt=df3d_area::observeNativeLocationStaffAssignments(ids[0],ids[1],source,ids[3],ids[4],ids[5]);
          value["valid"]=receipt.has_value();
          if(receipt) {
            value["revision"]=std::to_string(receipt->revision);value["unit_id"]=receipt->unitId;value["histfig_id"]=receipt->histfigId;
            value["entries"]=Json::Value(Json::arrayValue);
            for(const auto& entry:receipt->entries) {
              Json::Value row(Json::objectValue);row["kind"]=int(entry.kind);row["id"]=entry.id;
              row["type"]=entry.type;row["subtype"]=entry.subtype;row["custom"]=entry.custom;row["name"]=entry.name;row["custom_code"]=entry.customCode;
              value["entries"].append(std::move(row));
            }
          }
        } else {
          const auto receipt=df3d_area::observeNativeLocationStaffSpecialization(ids[0],ids[1],source,ids[3],ids[4],ids[5]);
          value["valid"]=receipt.has_value();
          if(receipt) {
            value["revision"]=std::to_string(receipt->revision);value["eligible"]=receipt->eligible;
            value["specialized"]=receipt->specialized;value["unit_id"]=receipt->unitId;value["histfig_id"]=receipt->histfigId;
          }
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if(parameters[0]=="location-religious-assignment-receipt") {
        if(parameters.size()!=6)return CR_WRONG_USAGE;
        int32_t ids[5]{};
        for(size_t i=0;i<5;++i) {
          const auto& text=parameters[i+1];const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        const auto receipt=df3d_area::observeNativeReligiousAssignment(ids[0],ids[1],ids[2],ids[3],ids[4]);
        Json::Value value(Json::objectValue);value["valid"]=receipt.has_value();
        if(receipt) {
          value["revision"]=std::to_string(receipt->revision);value["eligible"]=receipt->eligible;
          value["holder_revision"]=std::to_string(receipt->target.revision);
          value["holder_id"]=receipt->target.holderId;value["histfig_id"]=receipt->histfigId;value["nemesis_id"]=receipt->nemesisId;
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if(parameters[0]=="location-religious-assign") {
        if(parameters.size()!=8)return CR_WRONG_USAGE;
        int32_t ids[6]{};uint64_t revision=0;
        for(size_t i=0;i<6;++i) {
          const auto& text=parameters[i+1];const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        const auto& text=parameters[7];const auto parsed=std::from_chars(text.data(),text.data()+text.size(),revision);
        if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        Json::Value value(Json::objectValue);
        value["outcome"]=int(df3d_area::assignNativeLocationReligiousStaff(ids[0],ids[1],ids[2],ids[3],ids[4],ids[5],revision));
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if(parameters[0]=="location-religious-remove" || parameters[0]=="location-religious-receipt" || parameters[0]=="location-religious-candidates" || parameters[0]=="location-religious-candidate-rows") {
        const bool candidateRows=parameters[0]=="location-religious-candidate-rows";
        const bool candidates=candidateRows || parameters[0]=="location-religious-candidates";
        const bool reading=candidates || parameters[0]=="location-religious-receipt";
        if(parameters.size()!=(reading?5:7))return CR_WRONG_USAGE;
        int32_t ids[5]{};
        for(size_t i=0;i<(reading?4:5);++i) {
          const auto& text=parameters[i+1];
          const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        Json::Value value(Json::objectValue);
        if(candidateRows) {
          const auto candidates=df3d_area::observeNativeReligiousCandidates(ids[0],ids[1],ids[2],ids[3]);
          value["valid"]=candidates.has_value();value["rows"]=Json::Value(Json::arrayValue);
          if(candidates)for(const auto& candidate:candidates->rows) {
            Json::Value row(Json::objectValue);row["unit_id"]=candidate.unitId;row["histfig_id"]=candidate.histfigId;
            row["name"]=candidate.name;row["base_name"]=candidate.baseName;row["profession_name"]=candidate.professionName;
            row["score"]=candidate.score;row["source_index"]=candidate.sourceIndex;
            row["profession_order"]=candidate.professionOrder;row["status_order"]=candidate.statusOrder;
            row["profession_color"]=candidate.professionColor;row["legendary"]=candidate.legendary;
            row["skills"]=Json::Value(Json::arrayValue);
            for(const auto& skill:candidate.skills) {
              Json::Value item(Json::objectValue);item["id"]=skill.id;item["rating"]=skill.rating;
              item["experience"]=skill.experience;item["weight"]=skill.weight;row["skills"].append(item);
            }
            value["rows"].append(row);
          }
        } else if(candidates) {
          const auto rows=df3d_area::observeNativeReligiousCandidateIds(ids[0],ids[1],ids[2],ids[3]);
          value["valid"]=rows.has_value();value["unit_ids"]=Json::Value(Json::arrayValue);
          if(rows)for(auto id:*rows)value["unit_ids"].append(id);
        } else if(reading) {
          const auto receipt=df3d_area::observeNativeLocationReligiousStaff(ids[0],ids[1],ids[2],ids[3]);
          value["valid"]=receipt.has_value();
          if(receipt) {
            value["revision"]=std::to_string(receipt->revision);value["removable"]=receipt->removable;
            value["position_id"]=receipt->positionId;value["holder_id"]=receipt->holderId;value["unit_id"]=receipt->unitId;
          }
        } else {
          uint64_t revision=0;const auto& text=parameters[6];
          const auto parsed=std::from_chars(text.data(),text.data()+text.size(),revision);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
          value["outcome"]=int(df3d_area::removeNativeLocationReligiousStaff(ids[0],ids[1],ids[2],ids[3],ids[4],revision));
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if(parameters[0]=="location-staff-candidates" || parameters[0]=="location-staff-set") {
        static df3d_area::LocationStaffCandidateSnapshot snapshot;
        const bool edit=parameters[0]=="location-staff-set";
        if(edit && parameters.size()!=6)return CR_WRONG_USAGE;
        if(parameters.size()!=4 && parameters.size()!=6)return CR_WRONG_USAGE;
        int32_t ids[3]{};
        for(size_t i=0;i<3;++i) {
          const auto& text=parameters[i+1];
          const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        auto observed=df3d_area::observeNativeLocationStaffCandidates(ids[0],ids[1],ids[2]);
        if(edit) {
          int32_t unitId=-1;uint64_t revision=0;
          const auto& u=parameters[4];const auto& r=parameters[5];
          const auto pu=std::from_chars(u.data(),u.data()+u.size(),unitId);
          const auto pr=std::from_chars(r.data(),r.data()+r.size(),revision);
          if(pu.ec!=std::errc{} || pu.ptr!=u.data()+u.size() || pr.ec!=std::errc{} || pr.ptr!=r.data()+r.size() || unitId< -1)return CR_WRONG_USAGE;
          if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
          const df3d_area::LocationStaffTarget target{ids[0],ids[1],ids[2]};
          const auto epoch=state.terrain.epoch();snapshot.observe(epoch,target,observed);
          auto outcome=df3d_area::LocationStaffEditOutcome::Rejected;
          if(revision && snapshot.page(epoch,target,0,revision).status==df3d_area::LocationPageStatus::Ready)
            outcome=df3d_area::editNativeLocationStaff(ids[0],ids[1],ids[2],unitId);
          if(outcome==df3d_area::LocationStaffEditOutcome::Applied || outcome==df3d_area::LocationStaffEditOutcome::Unknown)snapshot.invalidate();
          Json::Value result(Json::objectValue);result["outcome"]=int(outcome);
          out.print("{}",Json::FastWriter().write(result));return CR_OK;
        }
        Json::Value value(Json::objectValue);value["valid"]=observed.has_value();value["rows"]=Json::Value(Json::arrayValue);
        if(parameters.size()==6) {
          uint32_t cursor=0;uint64_t revision=0;
          const auto& c=parameters[4];const auto& v=parameters[5];
          const auto pc=std::from_chars(c.data(),c.data()+c.size(),cursor);
          const auto pr=std::from_chars(v.data(),v.data()+v.size(),revision);
          if(pc.ec!=std::errc{} || pc.ptr!=c.data()+c.size() || pr.ec!=std::errc{} || pr.ptr!=v.data()+v.size())return CR_WRONG_USAGE;
          const df3d_area::LocationStaffTarget target{ids[0],ids[1],ids[2]};
          const uint64_t epoch=state.mapLoaded?state.terrain.epoch():0;
          snapshot.observe(epoch,target,observed);
          const auto page=snapshot.page(epoch,target,cursor,revision);
          value["page_status"]=int(page.status);value["revision"]=Json::UInt64(page.revision);
          value["next_cursor"]=page.nextCursor;value["total"]=page.total;
          if(page.status==df3d_area::LocationPageStatus::Ready)observed->rows=page.rows;
          else observed.reset();
          value["valid"]=observed.has_value();
        }
        if(observed) {
          value["role"]=observed->role;
          for(const auto& candidate:observed->rows) {
            Json::Value row(Json::objectValue);row["unit_id"]=candidate.unitId;row["histfig_id"]=candidate.histfigId;
            row["name"]=candidate.name;row["score"]=candidate.score;
            row["base_name"]=candidate.baseName;row["profession_name"]=candidate.professionName;
            row["source_index"]=candidate.sourceIndex;row["profession_order"]=candidate.professionOrder;row["status_order"]=candidate.statusOrder;
            row["name_sort_key"]=Json::Value(Json::arrayValue);row["profession_sort_key"]=Json::Value(Json::arrayValue);
            for(auto byte:candidate.nameSortKey)row["name_sort_key"].append(int(byte));
            for(auto byte:candidate.professionSortKey)row["profession_sort_key"].append(int(byte));
            row["profession_color"]=candidate.professionColor;row["legendary"]=candidate.legendary;row["skills"]=Json::Value(Json::arrayValue);
            for(const auto& skill:candidate.skills) {
              Json::Value item(Json::objectValue);item["id"]=skill.id;item["rating"]=skill.rating;
              item["experience"]=skill.experience;item["weight"]=skill.weight;row["skills"].append(item);
            }
            value["rows"].append(row);
          }
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "location-staff-read" || parameters[0] == "location-staff-prepare") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        int32_t ids[2]{};
        for(size_t i=0;i<2;++i) {
          const auto& text=parameters[i+1];
          const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        Json::Value value(Json::objectValue);
        if(parameters[0]=="location-staff-prepare")value["prepared"]=df3d_area::prepareNativeLocationStaff(ids[0],ids[1]);
        const auto observed=df3d_area::observeNativeLocationStaff(ids[0],ids[1]);value["valid"]=observed.has_value();
        if(observed) {
          value["missing_roles"]=Json::Value(Json::arrayValue);for(auto role:observed->missingRoles)value["missing_roles"].append(role);
          value["rows"]=Json::Value(Json::arrayValue);
          for(const auto& r:observed->rows) {
            Json::Value row(Json::objectValue);row["entity"]=r.entityId;row["position"]=r.positionId;row["assignment"]=r.assignmentId;
            if(r.names) {
              Json::Value names(Json::objectValue);names["position_name"]=r.names->positionName;names["holder_name"]=r.names->holderName;
              names["holder_kind"]=r.names->holderKind;names["holder_id"]=r.names->holderId;row["names"]=names;
            }
            row["occupation"]=false;
            if(r.source==df3d_area::LocationStaffSource::Occupation) {
              Json::Value occupation(Json::objectValue);occupation["id"]=r.occupationId;occupation["type"]=r.role;
              occupation["histfig_id"]=r.histfigId;occupation["unit_id"]=r.unitId;
              occupation["location_id"]=r.locationId;occupation["site_id"]=r.siteId;occupation["group_id"]=r.groupId;
              row["occupation"]=occupation;
            }
            value["rows"].append(row);
          }
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "location-name-words" || parameters[0] == "location-name-pick") {
        if(parameters.size()<2 || parameters.size()>4 || (parameters[0]=="location-name-pick" && parameters.size()>3))return CR_WRONG_USAGE;
        int32_t component=-1;const auto& text=parameters[1];
        const auto parsed=std::from_chars(text.data(),text.data()+text.size(),component);
        if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size() || component<0 || component>6)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        const auto query=parameters.size()>=3?UTF2DF(parameters[2]):std::string{};
        int32_t language=-1;
        if(parameters.size()==4) {
          const auto& value=parameters[3];const auto parsedLanguage=std::from_chars(value.data(),value.data()+value.size(),language);
          if(parsedLanguage.ec!=std::errc{} || parsedLanguage.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        }
        if(parameters[0]=="location-name-pick") {
          const auto word=df3d_area::chooseNativeLocationNameWord(uint8_t(component),query);
          Json::Value value(Json::objectValue);value["valid"]=bool(word);
          if(word){value["word"]=word->word;value["part"]=word->partOfSpeech;value["english"]=word->english;}
          out.print("{}",Json::FastWriter().write(value));return CR_OK;
        }
        const auto words=df3d_area::observeNativeLocationNameWords(uint8_t(component),query,language);
        Json::Value value(Json::objectValue);value["valid"]=bool(words);value["words"]=Json::Value(Json::arrayValue);
        if(words)for(const auto& word:*words) {
          Json::Value pair(Json::arrayValue);pair.append(word.word);pair.append(word.partOfSpeech);pair.append(word.english);pair.append(word.translated);value["words"].append(pair);
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "location-name-generate" || parameters[0] == "location-name-read") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        int32_t ids[2]{};
        for(size_t i=0;i<2;++i) {
          const auto& text=parameters[i+1];const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        const auto snapshot=parameters[0]=="location-name-read" ? df3d_area::observeNativeLocationName(ids[0],ids[1]) : std::optional<df3d_area::LocationNameSnapshot>{};
        const auto name=parameters[0]=="location-name-read" ? (snapshot ? std::optional{snapshot->name} : std::optional<df3d_area::LocationNameValue>{}) : df3d_area::generateNativeLocationName(ids[0],ids[1]);
        Json::Value value(Json::objectValue);value["valid"]=bool(name);
        if(snapshot) {
          value["revision"]=std::to_string(df3d_area::locationNameRevision(*snapshot));
          value["namer_id"]=snapshot->namerId;value["namer_race"]=snapshot->namerRace;value["kind"]=snapshot->kind;
        }
        if(name) {
          if(snapshot) {
            const auto text=df3d_area::formatNativeLocationName(*name);
            value["header_valid"]=bool(text);
            if(text){value["native_header"]=text->native;value["english_header"]=text->english;}
          }
          auto& v=value["name"];v["first_name"]=DF2UTF(name->firstNameCp437);v["nickname"]=DF2UTF(name->nicknameCp437);
          v["language"]=name->language;v["type"]=name->type;v["has_name"]=name->hasName;
          v["words"]=Json::Value(Json::arrayValue);v["parts_of_speech"]=Json::Value(Json::arrayValue);
          for(size_t i=0;i<7;++i){v["words"].append(name->words[i]);v["parts_of_speech"].append(name->parts[i]);}
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "location-name-edit") {
        if(parameters.size()!=10)return CR_WRONG_USAGE;
        int32_t values[7]{};
        for(size_t i=0;i<7;++i) {
          const auto& text=parameters[i+1];const auto parsed=std::from_chars(text.data(),text.data()+text.size(),values[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        uint64_t receipt=0;const auto& text=parameters[8];
        const auto parsed=std::from_chars(text.data(),text.data()+text.size(),receipt);
        if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size() || values[2]<0 || values[2]>3)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        const auto outcome=df3d_area::editNativeLocationName(values[0],values[1],receipt,
            static_cast<df3d_area::LocationNameEdit>(values[2]),values[3],values[4],values[5],values[6],UTF2DF(parameters[9]));
        out.print("{{\"outcome\":{}}}\n",int(outcome));return CR_OK;
      }
      if (parameters[0] == "location-quantity-edit") {
        if(parameters.size()!=7)return CR_WRONG_USAGE;
        int32_t values[5]{};
        for(size_t i=0;i<5;++i) {
          const auto& text=parameters[i+1];const auto parsed=std::from_chars(text.data(),text.data()+text.size(),values[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        uint64_t receipt=0;const auto& text=parameters[6];
        const auto parsed=std::from_chars(text.data(),text.data()+text.size(),receipt);
        if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size() || values[2]<0 || values[2]>10 || values[3]<0 || values[3]>2)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        const auto outcome=df3d_area::editNativeLocationQuantity(values[0],values[1],receipt,
            uint8_t(values[2]),static_cast<df3d_area::LocationQuantityEdit>(values[3]),values[4]);
        out.print("{{\"outcome\":{}}}\n",int(outcome));return CR_OK;
      }
      if (parameters[0] == "location-access-set") {
        if(parameters.size()!=5)return CR_WRONG_USAGE;
        int32_t values[3]{};
        for(size_t i=0;i<3;++i) {
          const auto& value=parameters[i+1];
          const auto parsed=std::from_chars(value.data(),value.data()+value.size(),values[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        }
        uint64_t receipt=0;const auto& text=parameters[4];
        const auto parsed=std::from_chars(text.data(),text.data()+text.size(),receipt);
        if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size() || values[2]<0 || values[2]>3)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        const auto outcome=df3d_area::setNativeLocationAccess(values[0],values[1],receipt,
            static_cast<df3d_area::LocationAccess>(values[2]));
        out.print("{{\"outcome\":{}}}\n",int(outcome));return CR_OK;
      }
      if (parameters[0] == "location-details-refresh") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        int32_t ids[2]{};
        for(size_t i=0;i<2;++i) {
          const auto& value=parameters[i+1];
          const auto parsed=std::from_chars(value.data(),value.data()+value.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        }
        Json::Value value(Json::objectValue);
        value["refreshed"]=df3d_area::refreshNativeLocationDetailsCaches(ids[0],ids[1]);
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "location-details-read") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        int32_t ids[2]{};
        for(size_t i=0;i<2;++i) {
          const auto& value=parameters[i+1];
          const auto parsed=std::from_chars(value.data(),value.data()+value.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        }
        const auto result=df3d_area::observeNativeLocationDetailsCore(ids[0],ids[1]);
        Json::Value value(Json::objectValue);value["valid"]=result.has_value();
        if(result) {
          const auto& row=*result;
          value["site_id"]=row.siteId;value["id"]=row.id;value["kind"]=row.kind;value["name"]=row.name;
          // Preserve the exact 63-bit receipt through Lua/JSON number readers.
          value["revision"]=std::to_string(df3d_area::locationDetailsRevision(row));
          value["access"]=int(row.access);value["visitors"]=row.accessFlags.visitors;
          value["residents"]=row.accessFlags.residents;value["members"]=row.accessFlags.members;
          value["profession"]=row.profession;value["tier"]=row.tier;value["value"]=row.value;
          value["recognized"]=row.recognized;value["desired_copies"]=row.desiredCopies;value["appraisal"]=row.appraisal;value["written_objects"]=row.writtenObjects;value["dance_floor_x"]=row.danceFloorX;value["dance_floor_y"]=row.danceFloorY;
          const auto& f=row.facilities;
          value["facilities"]["chests"]=f.chests;value["facilities"]["beds"]=f.beds;value["facilities"]["tables"]=f.tables;value["facilities"]["traction_benches"]=f.tractionBenches;value["facilities"]["bookcases"]=f.bookcases;value["facilities"]["chairs"]=f.chairs;value["facilities"]["rooms"]=f.rooms;value["facilities"]["rented_rooms"]=f.rentedRooms;
          value["zones"]=Json::Value(Json::arrayValue);for(auto id:row.zoneIds)value["zones"].append(id);
          value["supplies"]=Json::Value(Json::arrayValue);
          for(size_t i=0;i<row.supplies.size();++i) {
            Json::Value supply(Json::objectValue);supply["kind"]=int(i);
            supply["stored"]=row.supplies[i].stored;supply["desired"]=row.supplies[i].desired;
            value["supplies"].append(supply);
          }
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "location-recognize" || parameters[0] == "location-recognition-receipt") {
        const bool reading=parameters[0]=="location-recognition-receipt";
        if(parameters.size()!=(reading?3:4))return CR_WRONG_USAGE;
        int32_t ids[2]{};
        for(size_t i=0;i<2;++i) {
          const auto& text=parameters[i+1];
          const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        Json::Value value(Json::objectValue);
        if(reading) {
          const auto receipt=df3d_area::observeNativeLocationRecognitionReceipt(ids[0],ids[1]);
          value["valid"]=receipt.has_value();
          if(receipt)value["revision"]=std::to_string(receipt->revision);
        } else {
          uint64_t revision=0;const auto& text=parameters[3];
          const auto parsed=std::from_chars(text.data(),text.data()+text.size(),revision);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
          value["outcome"]=int(df3d_area::recognizeNativeLocation(ids[0],ids[1],revision));
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "location-recognition-position") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        int32_t ids[2]{};
        for(size_t i=0;i<2;++i) {
          const auto& text=parameters[i+1];
          const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        const auto result=df3d_area::prepareNativeLocationRecognitionPosition(ids[0],ids[1]);
        Json::Value value(Json::objectValue);value["prepared"]=bool(result);
        if(result) {
          const auto& p=*result;auto& row=value["position"];
          row["code"]=p.code;row["name"]=DF2UTF(p.name[0]);
          row["land_name"]=DF2UTF(p.land_name);row["description"]=DF2UTF(p.description);
          row["id"]=int(p.id);
          row["squad_size"]=int(p.squad_size);
          row["land_holder"]=int(p.land_holder);
          row["requires_population"]=int(p.requires_population);
          row["execution_skill"]=int(p.execution_skill);
          row["precedence"]=int(p.precedence);
          row["replaced_by"]=int(p.replaced_by);
          row["number"]=int(p.number);
          row["required_boxes"]=int(p.required_boxes);
          row["required_cabinets"]=int(p.required_cabinets);
          row["required_racks"]=int(p.required_racks);
          row["required_stands"]=int(p.required_stands);
          row["required_office"]=int(p.required_office);
          row["required_bedroom"]=int(p.required_bedroom);
          row["required_dining"]=int(p.required_dining);
          row["required_tomb"]=int(p.required_tomb);
          row["mandate_max"]=int(p.mandate_max);
          row["demand_max"]=int(p.demand_max);
          row["best_appointment_precedence"]=int(p.best_appointment_precedence);
          row["allowed_creature"]=Json::Value(Json::arrayValue);for(auto v:p.allowed_creature)row["allowed_creature"].append(int(v));
          row["rejected_creature"]=Json::Value(Json::arrayValue);for(auto v:p.rejected_creature)row["rejected_creature"].append(int(v));
          row["commander_id"]=Json::Value(Json::arrayValue);for(auto v:p.commander_id)row["commander_id"].append(int(v));
          row["commander_civ"]=Json::Value(Json::arrayValue);for(auto v:p.commander_civ)row["commander_civ"].append(int(v));
          row["commander_types"]=Json::Value(Json::arrayValue);for(auto v:p.commander_types)row["commander_types"].append(int(v));
          row["appointed_by"]=Json::Value(Json::arrayValue);for(auto v:p.appointed_by)row["appointed_by"].append(int(v));
          row["appointed_by_civ"]=Json::Value(Json::arrayValue);for(auto v:p.appointed_by_civ)row["appointed_by_civ"].append(int(v));
          row["succession_by_position"]=Json::Value(Json::arrayValue);for(auto v:p.succession_by_position)row["succession_by_position"].append(int(v));
          row["color"]=Json::Value(Json::arrayValue);for(auto v:p.color)row["color"].append(int(v));
          row["name_forms"]=Json::Value(Json::arrayValue);for(const auto& v:p.name)row["name_forms"].append(DF2UTF(v));
          row["name_female_forms"]=Json::Value(Json::arrayValue);for(const auto& v:p.name_female)row["name_female_forms"].append(DF2UTF(v));
          row["name_male_forms"]=Json::Value(Json::arrayValue);for(const auto& v:p.name_male)row["name_male_forms"].append(DF2UTF(v));
          row["spouse_forms"]=Json::Value(Json::arrayValue);for(const auto& v:p.spouse)row["spouse_forms"].append(DF2UTF(v));
          row["spouse_female_forms"]=Json::Value(Json::arrayValue);for(const auto& v:p.spouse_female)row["spouse_female_forms"].append(DF2UTF(v));
          row["spouse_male_forms"]=Json::Value(Json::arrayValue);for(const auto& v:p.spouse_male)row["spouse_male_forms"].append(DF2UTF(v));
          row["squad_forms"]=Json::Value(Json::arrayValue);for(const auto& v:p.squad)row["squad_forms"].append(DF2UTF(v));
          row["allowed_class"]=Json::Value(Json::arrayValue);for(const auto* v:p.allowed_class)row["allowed_class"].append(DF2UTF(*v));
          row["rejected_class"]=Json::Value(Json::arrayValue);for(const auto* v:p.rejected_class)row["rejected_class"].append(DF2UTF(*v));
          row["flags"]=Json::Value(Json::arrayValue);
          for(int i=0;i<=31;++i)if(p.flags.is_set(static_cast<df::entity_position_flags>(i)))
            row["flags"].append(ENUM_KEY_STR(entity_position_flags,static_cast<df::entity_position_flags>(i)));
          row["responsibilities"]=Json::Value(Json::arrayValue);for(bool v:p.responsibilities)row["responsibilities"].append(v);
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "location-recognition-thoughts" || parameters[0] == "location-recognition-agreements") {
        // Staged semantic primitive for protected effect verification. This is
        // not exposed by the management wire as a complete recognition action.
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        int32_t ids[2]{};
        for(size_t i=0;i<2;++i) {
          const auto& text=parameters[i+1];
          const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        const bool thoughts=parameters[0]=="location-recognition-thoughts";
        const auto result=thoughts ? df3d_area::applyNativeLocationRecognitionThoughts(ids[0],ids[1]) :
          df3d_area::concludeNativeLocationRecognitionAgreements(ids[0],ids[1]);
        Json::Value value(Json::objectValue);value["applied"]=result.has_value();
        const char* field=thoughts?"unit_ids":"agreement_ids";
        value[field]=Json::Value(Json::arrayValue);
        if(result)for(auto id:*result)value[field].append(id);
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "continuing-agreements-read") {
        if(parameters.size()!=1)return CR_WRONG_USAGE;
        const auto rows=df3d_area::observeNativeContinuingAgreements();
        Json::Value value(Json::objectValue);value["valid"]=rows.has_value();value["rows"]=Json::Value(Json::arrayValue);
        if(rows)for(const auto& row:*rows) {
          Json::Value entry(Json::objectValue);
          entry["agreement_id"]=row.agreementId;entry["subject_id"]=row.subjectId;entry["entity_id"]=row.entityId;
          entry["entity_type"]=row.entityType;entry["tier"]=row.tier;entry["profession"]=row.profession;
          entry["year"]=row.year;entry["year_tick"]=row.yearTick;
          entry["heading"]=row.heading;entry["applicant"]=row.applicant;entry["date"]=row.date;
          value["rows"].append(entry);
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "continuing-agreement-details-read") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id=-1;const auto& text=parameters[1];
        const auto parsed=std::from_chars(text.data(),text.data()+text.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        const auto result=df3d_area::observeNativeContinuingAgreementDetails(id);
        Json::Value value(Json::objectValue);value["valid"]=result.has_value();
        if(result) {
          value["agreement_id"]=result->agreement.agreementId;value["entity_type"]=result->agreement.entityType;
          value["required_value"]=result->requiredValue;value["matching_locations"]=result->matchingLocations;
          value["location_id"]=result->locationId;value["location_value"]=result->locationValue;
          value["location_tier"]=result->locationTier;value["tier_met"]=result->tierMet;
          value["site_available"]=result->siteAvailable;value["location_name"]=result->locationName;
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "location-recognition-read") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        int32_t ids[2]{};
        for(size_t i=0;i<2;++i) {
          const auto& text=parameters[i+1];
          const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        const auto result=df3d_area::observeNativeLocationRecognition(ids[0],ids[1]);
        Json::Value value(Json::objectValue);value["valid"]=result.has_value();
        if(result) {
          value["site_id"]=result->siteId;value["location_id"]=result->locationId;value["religion_id"]=result->religionId;
          value["tier"]=result->tier;value["rank"]=result->rank;value["worshippers"]=result->worshippers;
          value["priest_threshold"]=result->priestThreshold;value["high_priest_threshold"]=result->highPriestThreshold;
          value["state"]=int(df3d_area::locationRecognitionState(*result));
          value["continuing_agreements"]=Json::Value(Json::arrayValue);
          for(auto id:result->continuingAgreements)value["continuing_agreements"].append(id);
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "location-affiliation-read") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        int32_t ids[2]{};
        for(size_t i=0;i<2;++i) {
          const auto& text=parameters[i+1];
          const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        const auto result=df3d_area::observeNativeLocationAffiliation(ids[0],ids[1]);
        Json::Value value(Json::objectValue);value["valid"]=result.has_value();
        if(result) {
          value["kind"]=result->kind;value["id"]=result->id;
          value["count"]=result->count;value["name"]=result->name;value["workers"]=result->workers;
        }
        out.print("{}",Json::FastWriter().write(value));return CR_OK;
      }
      if (parameters[0] == "location-religions-read") {
        if(parameters.size()!=1)return CR_WRONG_USAGE;
        const auto result=df3d_area::observeNativeLocationReligions();
        out.print("{{\"valid\":{},\"choices\":[",result.has_value());
        if(result)for(size_t i=0;i<result->size();++i) {
          const auto& row=(*result)[i];
          Json::Value value(Json::objectValue);
          value["kind"]=int(row.kind);value["id"]=row.id;value["worshippers"]=row.worshippers;
          value["has_temple"]=row.hasTemple;value["name"]=row.name;value["deities"]=Json::Value(Json::arrayValue);
          for(const auto& deity:row.deities) {
            Json::Value item(Json::objectValue);item["id"]=deity.id;item["name"]=deity.name;item["spheres"]=Json::Value(Json::arrayValue);
            for(auto sphere:deity.spheres)item["spheres"].append(sphere);
            value["deities"].append(item);
          }
          out.print("{}{}",i?",":"",Json::FastWriter().write(value));
        }
        out.print("]}}\n");return CR_OK;
      }
      if (parameters[0] == "location-guilds-read") {
        if(parameters.size()!=1)return CR_WRONG_USAGE;
        const auto result=df3d_area::observeNativeLocationGuilds();
        out.print("{{\"valid\":{},\"choices\":[",result.has_value());
        if(result)for(size_t i=0;i<result->size();++i) {
          const auto& row=(*result)[i];
          Json::Value value(Json::objectValue);
          value["profession"]=row.profession;value["workers"]=row.workers;value["has_meeting_place"]=row.hasMeetingPlace;
          value["guild_id"]=row.guildId;value["members"]=row.members;value["guild_name"]=row.guildName;
          out.print("{}{}",i?",":"",Json::FastWriter().write(value));
        }
        out.print("]}}\n");return CR_OK;
      }
      if (parameters[0] == "paint-water-read" || parameters[0] == "paint-base-read" || parameters[0] == "paint-material-read") {
        if(parameters.size()!=4)return CR_WRONG_USAGE;
        int32_t xyz[3]{};
        for(size_t i=0;i<3;++i) {
          const auto& value=parameters[i+1];
          const auto parsed=std::from_chars(value.data(),value.data()+value.size(),xyz[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        }
        if(parameters[0] == "paint-material-read") {
          const auto result=df3d_area::observeNativePaintMaterial(xyz[0],xyz[1],xyz[2]);
          out.print("{{\"sand\":{},\"clay\":{}}}\n",int(result.sand),int(result.clay));
          return CR_OK;
        }
        if(parameters[0] == "paint-base-read") {
          const auto result=df3d_area::observeNativePaintBase(xyz[0],xyz[1],xyz[2]);
          out.print("{{\"ordinary\":{},\"pond\":{}}}\n",int(result.ordinary),int(result.pond));
          return CR_OK;
        }
        const auto result=df3d_area::observeNativePaintWater(xyz[0],xyz[1],xyz[2]);
        out.print("{{\"water\":{},\"fishing\":{}}}\n",int(result.water),int(result.fishing));
        return CR_OK;
      }
      if(parameters[0]=="zone-owner-status-read") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        int32_t ids[2];
        for(int i=0;i<2;++i) {
          const auto& text=parameters[i+1];const auto parsed=std::from_chars(text.data(),text.data()+text.size(),ids[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        auto* zone=virtual_cast<df::building_civzonest>(df::building::find(ids[0]));auto* unit=df::unit::find(ids[1]);
        if(!zone || !unit)return CR_FAILURE;
        const auto result=df3d_area::nativeZoneOwnerRoomStatus(*zone,*unit);if(!result)return CR_FAILURE;
        Json::Value output(Json::arrayValue),bytes(Json::arrayValue);output.append(result->value);
        for(unsigned char byte:result->label)bytes.append(int(byte));output.append(bytes);
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-owner-name-color-read") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id=-1;const auto& text=parameters[1];const auto parsed=std::from_chars(text.data(),text.data()+text.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        auto* unit=df::unit::find(id);if(!unit)return CR_FAILURE;
        const auto color=df3d_area::nativeZoneOwnerNameColor(*unit);if(!color)return CR_FAILURE;
        Json::Value output;output["effect"]=int(color->effect);output["source"]=int(color->source);
        for(auto c:color->color)output["color"].append(int(c));for(auto c:color->alternate)output["alternate"].append(int(c));
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-owner-profession-color-read") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        int32_t values[2];
        for(int i=0;i<2;++i) {
          const auto& text=parameters[i+1];const auto parsed=std::from_chars(text.data(),text.data()+text.size(),values[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        }
        if(values[1]<INT16_MIN || values[1]>INT16_MAX)return CR_WRONG_USAGE;
        auto* unit=df::unit::find(values[0]);if(!unit)return CR_FAILURE;
        const auto color=df3d_area::nativeZoneOwnerProfessionColor(*unit,int16_t(values[1]));if(!color)return CR_FAILURE;
        Json::Value output(Json::arrayValue);for(auto component:*color)output.append(int(component));
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-owner-color-sources-read") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id=-1;const auto& value=parameters[1];
        const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        auto* unit=df::unit::find(id);if(!unit)return CR_FAILURE;
        const auto facts=df3d_area::nativeZoneOwnerColorSources(*unit);if(!facts)return CR_FAILURE;
        Json::Value output;
        output["identity_id"]=facts->identityId;output["identity_profession"]=facts->identityProfession;output["identity_impersonated_histfig"]=facts->identityImpersonatedHistfig;
        output["position_id"]=facts->positionId;output["entity_id"]=facts->entityId;output["assignment_id"]=facts->assignmentId;
        output["position_has_color"]=facts->positionHasColor;output["position_color"]=Json::Value(Json::arrayValue);
        for(auto color:facts->positionColor)output["position_color"].append(int(color));
        output["slave_strength"]=facts->slaveStrength;output["prisoner_strength"]=facts->prisonerStrength;output["imprisoner_strength"]=facts->imprisonerStrength;
        output["deity_histfig_id"]=facts->deityHistfigId;output["deity"]=facts->deity;
        output["ordinary_color"]=Json::Value(Json::arrayValue);for(auto color:facts->ordinaryColor)output["ordinary_color"].append(int(color));
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="depot-container-probe") {
        if(parameters.size()!=5 && parameters.size()!=6)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t values[4]={-1,-1,-1,-1};
        for(size_t i=1;i<5;++i){const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<0)return CR_WRONG_USAGE;}
        const auto goods=df3d_production::depotGoods(df::building::find(values[0]));if(!goods)return CR_FAILURE;
        if(std::none_of(goods->rows.begin(),goods->rows.end(),[&](const auto& row){return row.id==values[1];}))return CR_FAILURE;
        const auto revision=df3d_production::depotGoodsRevision(values[0],*goods);if(!revision)return CR_FAILURE;
        uint64_t expected=*revision;
        if(parameters.size()==6){const auto& raw=parameters[5];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),expected);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || !expected || expected>INT64_MAX)return CR_WRONG_USAGE;}
        auto* parent=df::item::find(values[1]);if(!parent)return CR_FAILURE;
        const auto read=df3d_production::readDepotGoods(df::building::find(values[0]),int16_t(parent->getType()),"",true,true,false,{},expected,{},{},values[1],values[2],values[3]);
        if(!read || !read->container || read->containerId!=values[1] || read->containerOffset!=values[2])return CR_FAILURE;
        if(df3d_production::readDepotGoods(df::building::find(values[0]),int16_t(parent->getType()),"",true,true,false,{},*revision==1?2:*revision-1,{},{},values[1],values[2],values[3]))return CR_FAILURE;
        if(df3d_production::readDepotGoods(df::building::find(values[0]),int16_t(parent->getType()),"",true,true,false,{},0,{},{},values[1],values[2],values[3]))return CR_FAILURE;
        const auto& page=read->container;
        bool countMatched=false;
        for(const auto& group:read->groups){if(group.ids.size()!=group.containerCounts.size())return CR_FAILURE;
          for(size_t i=0;i<group.ids.size();++i)if(group.ids[i]==values[1])countMatched=group.containerCounts[i]==page->total;}
        if(!countMatched)return CR_FAILURE;
        Json::Value output;output["total"]=page->total;output["appraisal"]=read->appraisal;output["revision"]=std::to_string(*revision);output["stale_rejected"]=true;output["items"]=Json::arrayValue;
        for(const auto& row:page->items){Json::Value item;item["id"]=row.id;item["type"]=row.type;item["contained_count"]=row.containedCount;item["value"]=row.value;item["prohibited"]=row.prohibited;item["caption"]=DF2UTF(row.caption);item["value_caption"]=DF2UTF(row.valueCaption);output["items"].append(item);}
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="depot-selection-probe") {
        if(parameters.size()!=7 && parameters.size()!=9)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t values[5]={-1,-1,-1,-1,-1};
        for(size_t i=1;i<6;++i){const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<0)return CR_WRONG_USAGE;}
        if(values[1]>=93 || values[2]>1 || values[3]>1 || values[4]>1)return CR_WRONG_USAGE;
        const auto facts=df3d_production::depotGoods(df::building::find(values[0]));if(!facts)return CR_FAILURE;
        std::vector<df3d_production::DepotGoodsChange> draft,sortDraft;
        const auto parseDraft=[](const std::string& raw,std::vector<df3d_production::DepotGoodsChange>& target){
          if(raw=="-")return true;
          size_t start=0;
          while(start<raw.size()){
            const auto end=raw.find(',',start),colon=raw.find(':',start);
            const auto stop=end==std::string::npos?raw.size():end;
            if(colon==std::string::npos || colon+2!=stop || (raw[colon+1]!='0' && raw[colon+1]!='1'))return false;
            int32_t id=-1;const auto parsed=std::from_chars(raw.data()+start,raw.data()+colon,id);
            if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+colon || id<0 || target.size()>=64)return false;
            target.push_back({id,raw[colon+1]=='1'});
            if(end==std::string::npos)return true;
            start=end+1;
          }
          return false;
        };
        if(parameters.size()==9 && (!parseDraft(parameters[7],draft) || !parseDraft(parameters[8],sortDraft)))return CR_WRONG_USAGE;
        const auto selected=df3d_production::depotSelection(*facts,int16_t(values[1]),parameters[6],values[2]!=0,values[3]!=0,values[4]!=0,draft,sortDraft);if(!selected)return CR_FAILURE;
        const auto categories=df3d_production::depotCategories(*facts,parameters[6],values[4]!=0);if(!categories)return CR_FAILURE;
        Json::Value output;output["ids"]=Json::arrayValue;output["groups"]=Json::arrayValue;
        output["categories"]=Json::arrayValue;for(auto type:*categories)output["categories"].append(type);
        output["category_captions"]=Json::arrayValue;
        for(auto type:*categories){const auto caption=df3d_production::depotGroupCaption(type);if(!caption)return CR_FAILURE;output["category_captions"].append(DF2UTF(*caption));}
        output["item_captions"]=Json::arrayValue;for(const auto& caption:selected->itemCaptions)output["item_captions"].append(DF2UTF(caption));
        output["row_cells"]=selected->rowCells;
        const auto appraisal=df3d_production::depotAppraisal();if(!appraisal)return CR_FAILURE;
        output["appraisal"]=*appraisal;output["value_captions"]=Json::arrayValue;
        for(auto id:selected->ids){const auto at=std::find_if(facts->rows.begin(),facts->rows.end(),[&](const auto& row){return row.id==id;});if(at==facts->rows.end())return CR_FAILURE;
          const auto caption=df3d_production::depotValueCaption(at->value,*appraisal);if(!caption)return CR_FAILURE;
          Json::Value bytes=Json::arrayValue;for(unsigned char ch:*caption)bytes.append(int(ch));output["value_captions"].append(bytes);}
        output["tags"]=Json::arrayValue;for(auto tag:selected->tags)output["tags"].append(int(tag));
        if(parameters.size()==9){
          const auto revision=df3d_production::depotGoodsRevision(values[0],*facts);if(!revision)return CR_FAILURE;
          std::vector<int32_t> ids(selected->ids.begin(),selected->ids.begin()+std::min<size_t>(64,selected->ids.size()));
          const auto read=df3d_production::readDepotGoods(df::building::find(values[0]),int16_t(values[1]),parameters[6],values[2]!=0,values[3]!=0,values[4]!=0,ids,*revision,draft,sortDraft);
          if(!read || read->revision!=*revision || read->items.size()!=ids.size())return CR_FAILURE;
          for(size_t i=0;i<ids.size();++i)if(read->items[i].facts.id!=ids[i] || read->items[i].facts.tag!=selected->tags[i])return CR_FAILURE;
          if(df3d_production::readDepotGoods(df::building::find(values[0]),int16_t(values[1]),parameters[6],values[2]!=0,values[3]!=0,values[4]!=0,ids,*revision==1?2:*revision-1,draft,sortDraft))return CR_FAILURE;
          output["revision"]=std::to_string(*revision);output["stale_rejected"]=true;
        }
        for(auto id:selected->ids)output["ids"].append(id);
        for(const auto& row:selected->groups){Json::Value g;g["subtype"]=row.group.subtype;g["subcat1"]=row.group.subcat1;g["subcat2"]=row.group.subcat2;g["amount"]=row.group.amount;g["expanded"]=row.group.expanded;g["matches"]=row.matches;g["flags"]=row.flags;g["caption"]=DF2UTF(row.caption);g["ids"]=Json::arrayValue;for(auto id:row.ids)g["ids"].append(id);g["container_counts"]=Json::arrayValue;for(auto count:row.containerCounts)g["container_counts"].append(count);output["groups"].append(g);}
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="depot-goods-probe") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t id=-1;const auto& raw=parameters[1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
        const auto before=df3d_production::depot_goods_detail::storageHash();
        const auto facts=df3d_production::depotGoods(df::building::find(id));
        if(!facts || before!=df3d_production::depot_goods_detail::storageHash())return CR_FAILURE;
        Json::Value output;output["rows"]=Json::arrayValue;output["groups"]=Json::arrayValue;
        for(const auto& row:facts->rows){Json::Value r;r["id"]=row.id;r["distance"]=row.distance;r["tag"]=row.tag;r["value"]=row.value;r["prohibited"]=row.prohibited;output["rows"].append(r);}
        for(const auto& group:facts->groups){Json::Value g;g["type"]=group.type;g["subtype"]=group.subtype;g["subcat1"]=group.subcat1;g["subcat2"]=group.subcat2;g["amount"]=group.amount;g["expanded"]=group.expanded;output["groups"].append(g);}
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="depot-commit-probe") {
        if(parameters.size()!=2 && (parameters.size()<5 || parameters.size()>68))return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t id=-1;const auto& raw=parameters[1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
        Json::Value output;
        if(parameters.size()==2){
          const auto value=df3d_production::readDepotGoods(df::building::find(id),-1,"",true,true,false,{});if(!value)return CR_FAILURE;
          output["revision"]=std::to_string(value->revision);
        }else{
          uint64_t revision=0;const auto& token=parameters[2];const auto parsedRevision=std::from_chars(token.data(),token.data()+token.size(),revision);
          if(parsedRevision.ec!=std::errc{} || parsedRevision.ptr!=token.data()+token.size() || parameters[3]!="0" && parameters[3]!="1")return CR_WRONG_USAGE;
          std::vector<df3d_production::DepotGoodsChange> changes;
          for(size_t i=4;i<parameters.size();++i){int32_t target=-1;const auto& text=parameters[i];const auto converted=std::from_chars(text.data(),text.data()+text.size(),target);if(converted.ec!=std::errc{} || converted.ptr!=text.data()+text.size() || target<0)return CR_WRONG_USAGE;changes.push_back({target,parameters[3]=="1"});}
          const auto value=df3d_production::commitDepotGoods(df::building::find(id),revision,changes);
          output["outcome"]=int(value.outcome);output["stale"]=value.stale;output["revision"]=std::to_string(value.observedRevision);
        }
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="depot-haul-batch-probe") {
        if(parameters.size()<5 || parameters.size()>68)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        std::vector<int32_t> values;
        for(size_t i=1;i<parameters.size();++i){int32_t value=-1;const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || value<0)return CR_WRONG_USAGE;values.push_back(value);}
        if(values[1]>1 || values[2]>3)return CR_WRONG_USAGE;
        std::vector<df3d_production::DepotHaulIntent> intents;
        for(size_t i=3;i<values.size();++i){auto* item=df::item::find(values[i]);if(!item)return CR_FAILURE;intents.push_back({item->id,item->flags.whole,values[1]!=0});}
        if(values[2]==1)intents.back().expectedFlags^=1;
        if(values[2]==2)intents.push_back(intents.front());
        if(values[2]==3)intents.back().id=INT32_MAX;
        Json::Value output;output["outcome"]=int(df3d_production::depotSetHaulBatch(df::building::find(values[0]),intents));
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="depot-haul-probe") {
        if(parameters.size()!=4)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t values[3]={-1,-1,-1};
        for(size_t i=1;i<parameters.size();++i){const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<0)return CR_WRONG_USAGE;}
        if(values[2]>1)return CR_WRONG_USAGE;
        auto* item=df::item::find(values[1]);if(!item)return CR_FAILURE;
        Json::Value output;output["outcome"]=int(df3d_production::depotSetHaul(df::building::find(values[0]),item,item->flags.whole,values[2]!=0));
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="depot-distance-probe") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t id=-1;const auto& raw=parameters[1];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || id<0)return CR_WRONG_USAGE;
        const auto before=df3d_production::depot_goods_detail::storageHash();
        const auto rows=df3d_production::depotItemDistances(df::building::find(id),df::global::world->items.other[df::items_other_id::IN_PLAY]);
        const auto after=df3d_production::depot_goods_detail::storageHash();
        if(!rows || before!=after)return CR_FAILURE;
        const auto available=df3d_production::depotUnassignedGoods(df::building::find(id));
        if(!available || before!=df3d_production::depot_goods_detail::storageHash())return CR_FAILURE;
        Json::Value output;output["restored"]=true;output["rows"]=Json::arrayValue;
        output["available"]=Json::arrayValue;
        for(const auto& row:*available)output["available"].append(row.id);
        for(const auto& row:*rows){Json::Value value;value["id"]=row.id;value["distance"]=row.distance;output["rows"].append(value);}
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="trade-owner-probe") {
        if(parameters.size()<3 || parameters.size()>4)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        uint64_t a=0,b=0;
        const auto number=[&](size_t i,uint64_t& value){const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);return parsed.ec==std::errc{} && parsed.ptr==raw.data()+raw.size();};
        if(!number(2,a) || (parameters.size()==4 && !number(3,b)))return CR_WRONG_USAGE;
        auto& owner=df3d_production::tradeDiagnosticOwner();Json::Value output;
        if(parameters[1]=="catalog" && parameters.size()==3 && a<=INT32_MAX){
          const auto value=owner.refresh(state.terrain.epoch(),df::building::find(int32_t(a)));output["available"]=bool(value);output["tokens"]=Json::arrayValue;
          if(value)for(const auto& row:value->choices)output["tokens"].append(Json::UInt64(row.token));
        }else if(parameters[1]=="open" && parameters.size()==4 && a<=INT32_MAX){
          const auto value=owner.open(state.terrain.epoch(),int32_t(a),b);
          output["status"]=int(value.status);output["available"]=value.status==df3d_production::TradeOpenStatus::Available;
          output["session"]=Json::UInt64(value.selection.session);output["revision"]=Json::UInt64(value.selection.revision);
          if(value.appraisal){output["recorded"]=Json::UInt64(value.appraisal->recorded);output["trained"]=Json::UInt64(value.appraisal->trained);}
          if(value.entry){output["entity"]=value.entry->entity;output["title"]=DF2UTF(value.entry->title);output["speaker"]=DF2UTF(value.entry->speaker);}
        }else if((parameters[1]=="read" || parameters[1]=="epoch") && parameters.size()==4){
          const auto value=owner.access(state.terrain.epoch()+(parameters[1]=="epoch"?1:0),a,b);
          output["status"]=int(value.status);output["session"]=Json::UInt64(value.session);output["revision"]=Json::UInt64(value.revision);
          output["available"]=value.status==df3d_production::TradeSessionStatus::Available;
        }else if(parameters[1]=="close" && parameters.size()==3){output["status"]=int(owner.close(a).status);}
        else return CR_WRONG_USAGE;
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="trade-catalog-probe") {
        if(parameters.size()!=3 && parameters.size()!=4)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t depot=-1;const auto& raw=parameters[2];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),depot);
        if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || depot<0)return CR_WRONG_USAGE;
        auto& catalog=df3d_production::tradeDiagnosticCatalog();Json::Value output;
        if(parameters[1]=="read" && parameters.size()==3) {
          const auto facts=catalog.refresh(state.terrain.epoch(),df::building::find(depot));output["available"]=bool(facts);output["choices"]=Json::arrayValue;
          if(facts){output["title"]=DF2UTF(facts->title);output["from"]=DF2UTF(facts->from);
            for(const auto& choice:facts->choices){Json::Value row;row["token"]=Json::UInt64(choice.token);row["entity"]=choice.entity;row["race"]=DF2UTF(choice.race);row["name"]=DF2UTF(choice.name);output["choices"].append(row);}}
        }else if((parameters[1]=="choose" || parameters[1]=="epoch") && parameters.size()==4) {
          uint64_t token=0;const auto& value=parameters[3];const auto number=std::from_chars(value.data(),value.data()+value.size(),token);
          if(number.ec!=std::errc{} || number.ptr!=value.data()+value.size() || !token)return CR_WRONG_USAGE;
          const auto index=catalog.take(state.terrain.epoch()+(parameters[1]=="epoch"?1:0),depot,token);output["available"]=bool(index);
          if(index){const auto entry=df3d_production::tradeEntryFacts(df::building::find(depot),*index);if(!entry)return CR_FAILURE;
            const auto session=df3d_production::tradeDiagnosticSession().open(state.terrain.epoch(),df::building::find(depot),*index);
            output["available"]=session.status==df3d_production::TradeSessionStatus::Available;
            output["entity"]=entry->entity;output["session"]=Json::UInt64(session.session);output["revision"]=Json::UInt64(session.revision);}
        }else return CR_WRONG_USAGE;
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="trade-session-probe") {
        if(parameters.size()<3)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        const auto number=[&](size_t i,uint64_t& value){if(i>=parameters.size())return false;const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),value);return parsed.ec==std::errc{} && parsed.ptr==raw.data()+raw.size();};
        uint64_t a=0,b=0,c=0,d=0;if(!number(2,a))return CR_WRONG_USAGE;
        const auto& action=parameters[1];auto& session=df3d_production::tradeDiagnosticSession();
        df3d_production::TradeSessionRead result;
        std::optional<df3d_production::TradeExchangeStatus> exchangeStatus;
        if(action=="open") {
          if(parameters.size()!=4 || !number(3,b) || a>INT32_MAX || b>INT32_MAX)return CR_WRONG_USAGE;
          result=session.open(state.terrain.epoch(),df::building::find(int32_t(a)),size_t(b));
        }else if(action=="close") {
          if(parameters.size()!=3)return CR_WRONG_USAGE;result=session.close(a);
        }else {
          if(!number(3,b))return CR_WRONG_USAGE;
          if(action=="exchange" || action=="gift"){
            if(parameters.size()!=4)return CR_WRONG_USAGE;
            const auto exchanged=action=="gift"?session.gift(state.terrain.epoch(),a,b):session.exchange(state.terrain.epoch(),a,b);exchangeStatus=exchanged.status;result=exchanged.selection;
          }else if(action=="okay") {
            if(parameters.size()!=4)return CR_WRONG_USAGE;
            result=session.dismissCounteroffer(state.terrain.epoch(),a,b);
          }else if(action=="read" || action=="epoch") {
            if(parameters.size()!=4)return CR_WRONG_USAGE;
            result=session.access(state.terrain.epoch()+(action=="epoch"?1:0),a,b);
          }else if(action=="item" || action=="filter") {
            if(parameters.size()!=6 || !number(4,c) || c>1)return CR_WRONG_USAGE;
            df3d_production::TradeSelectionIntent intent;intent.side=int32_t(c);
            if(action=="item"){if(!number(5,d) || d>INT32_MAX)return CR_WRONG_USAGE;intent.item=int32_t(d);}
            else {intent.action=df3d_production::TradeDraftAction::Filter;intent.query=UTF2DF(parameters[5]);}
            result=session.access(state.terrain.epoch(),a,b,&intent);
          }else return CR_WRONG_USAGE;
        }
        Json::Value output;output["status"]=int(result.status);output["session"]=Json::UInt64(result.session);output["revision"]=Json::UInt64(result.revision);
        if(exchangeStatus)output["exchange_status"]=int(*exchangeStatus);
        if(result.conversation){const auto& c=*result.conversation;output["dialogue"]=c.dialogue;output["counter_offer"]=c.counterOffer;
          output["requested_items"]=Json::arrayValue;output["announcement"]=Json::arrayValue;
          for(auto id:c.requestedItems)output["requested_items"].append(id);
          for(const auto& line:c.announcement)output["announcement"].append(DF2UTF(line));}
        if(action=="read" && result.status==df3d_production::TradeSessionStatus::Available){
          for(int32_t side=0;side<2;++side){const auto page=session.display(state.terrain.epoch(),a,b,side,0,64);if(!page || !result.draft || page->total*3!=size_t(result.draft->sides[side].height))return CR_FAILURE;}
          output["display_verified"]=true;
          if(result.conversation){
            const auto counter=session.counterPage(state.terrain.epoch(),a,b,0,64);if(!counter)return CR_FAILURE;
            output["counter_page"]["heading"]=Json::arrayValue;
            for(const auto& line:counter->heading)output["counter_page"]["heading"].append(DF2UTF(line));
            output["counter_page"]["dismiss"]=DF2UTF(counter->dismiss);
            output["counter_page"]["total"]=Json::UInt64(counter->page.total);
            output["counter_page"]["offset"]=Json::UInt64(counter->page.offset);
            output["counter_page"]["rows"]=Json::arrayValue;
            for(const auto& row:counter->page.rows){
              if(!row.valuation)return CR_FAILURE;Json::Value r;
              r["id"]=row.id;r["type"]=row.type;r["subtype"]=row.subtype;r["caption"]=DF2UTF(row.caption);
              r["disposition"]=int(row.disposition);r["contained_count"]=row.containedCount;r["contents_caption"]=DF2UTF(row.contentsCaption);
              r["appraisal"]=row.valuation->appraisal;r["value_caption"]=DF2UTF(row.valuation->valueCaption);r["weight_caption"]=DF2UTF(row.valuation->weightCaption);
              output["counter_page"]["rows"].append(r);
            }
            if(session.counterPage(state.terrain.epoch(),a,b-1,0,64) || session.counterPage(state.terrain.epoch(),a,b,counter->page.total+1,64))return CR_FAILURE;
          }
          const auto summary=session.summary(state.terrain.epoch(),a,b);
          if(summary.status!=result.status || summary.session!=a || summary.revision!=b ||
             !summary.entry || !summary.values || !summary.capacity || !summary.header || summary.columns!=102)return CR_FAILURE;
          if(summary.header->speaker!=summary.entry->merchantTrader || (summary.header->speaker>=0 && !summary.header->nameColor))return CR_FAILURE;
          if(session.summary(state.terrain.epoch(),a,b,0).status!=df3d_production::TradeSessionStatus::Rejected ||
             session.summary(state.terrain.epoch(),a,b,513).status!=df3d_production::TradeSessionStatus::Rejected ||
             session.summary(state.terrain.epoch(),a,b-1).status!=df3d_production::TradeSessionStatus::Rejected)return CR_FAILURE;
          const auto narrow=session.summary(state.terrain.epoch(),a,b,40);
          if(narrow.status!=result.status || narrow.session!=a || narrow.revision!=b || narrow.columns!=40 || !narrow.header || narrow.header->dialogue!=summary.header->dialogue)return CR_FAILURE;
          output["header_summary_verified"]=true;output["header_name"]=DF2UTF(summary.header->name);
          output["header_lines"]=Json::arrayValue;for(const auto& line:summary.dialogueLines)output["header_lines"].append(DF2UTF(line));
          output["summary_verified"]=true;
        }
        output["sides"]=Json::arrayValue;output["filters"]=Json::arrayValue;
        if(result.draft)for(size_t side=0;side<2;++side){const auto& value=result.draft->sides[side];Json::Value row;
          row["height"]=value.height;row["items"]=row["flags"]=row["amounts"]=row["groups"]=Json::arrayValue;
          for(auto id:value.items)row["items"].append(id);for(auto flag:value.flags)row["flags"].append(flag);for(auto amount:value.amounts)row["amounts"].append(amount);
          for(const auto& group:value.groups){Json::Value g;g["type"]=group.type;g["subtype"]=group.subtype;g["expanded"]=group.expanded;g["on"]=group.on;g["flags"]=group.flags;row["groups"].append(g);}
          output["sides"].append(row);output["filters"].append(DF2UTF(result.draft->filters[side]));}
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="trade-appraisal-probe") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t values[2]={};for(size_t i=1;i<3;++i){const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<0)return CR_WRONG_USAGE;}
        const auto effect=df3d_production::tradeAppraise(df::building::find(values[0]),size_t(values[1]));
        Json::Value output;output["available"]=bool(effect);
        if(effect){output["recorded"]=Json::UInt64(effect->recorded);output["trained"]=Json::UInt64(effect->trained);}
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="trade-row-values-probe") {
        if(parameters.size()!=6)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t values[5]={};for(size_t i=1;i<6;++i){const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<0)return CR_WRONG_USAGE;}
        const auto rows=df3d_production::tradeRowValues(df::building::find(values[0]),size_t(values[1]),values[2],size_t(values[3]),size_t(values[4]));
        Json::Value output;output["available"]=bool(rows);output["rows"]=Json::arrayValue;
        if(rows)for(const auto& row:*rows){Json::Value value;value["id"]=row.id;value["value"]=row.value;value["appraisal"]=row.appraisal;value["value_caption"]=DF2UTF(row.valueCaption);value["weight_caption"]=DF2UTF(row.weightCaption);output["rows"].append(value);}
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="trade-projection-probe" || parameters[0]=="trade-draft-probe" || parameters[0]=="trade-display-probe" || parameters[0]=="trade-negotiation-seed-probe" || parameters[0]=="trade-gift-probe" || parameters[0]=="trade-refusal-probe" || (parameters[0]=="trade-negotiate-probe" || parameters[0]=="trade-accept-probe")) {
        if(parameters.size()!=3 && parameters.size()!=5 && parameters.size()!=6)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t values[2]={-1,-1};
        for(size_t i=1;i<3;++i){const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<0)return CR_WRONG_USAGE;}
        std::array<std::string,2> filters{};if(parameters.size()>=5){filters[0]=UTF2DF(parameters[3]);filters[1]=UTF2DF(parameters[4]);}
        std::vector<df3d_production::TradeSelectionIntent> selections;
        if(parameters.size()==6){Json::Value intents;Json::Reader reader;if(parameters[5].size()>131072 || !reader.parse(parameters[5],intents) || !intents.isArray() || intents.size()>4096)return CR_WRONG_USAGE;
          for(const auto& intent:intents){if(!intent.isObject() || !intent["side"].isInt())return CR_WRONG_USAGE;
            df3d_production::TradeSelectionIntent draft;draft.side=intent["side"].asInt();
            if(intent.isMember("action") && !intent["action"].isString())return CR_WRONG_USAGE;
            const auto action=intent.get("action","item").asString();
            if(action=="item" || action=="expand_container"){if(!intent["item"].isInt())return CR_WRONG_USAGE;draft.item=intent["item"].asInt();if(action=="expand_container")draft.action=df3d_production::TradeDraftAction::ExpandContainer;}
            else if(action=="mark_all")draft.action=df3d_production::TradeDraftAction::MarkAll;
            else if(action=="unmark_all")draft.action=df3d_production::TradeDraftAction::UnmarkAll;
            else if(action=="filter"){if(!intent["query"].isString())return CR_WRONG_USAGE;draft.action=df3d_production::TradeDraftAction::Filter;draft.query=UTF2DF(intent["query"].asString());}
            else if(action=="group" || action=="expand_group") {
              if(!intent["type"].isInt() || !intent["subtype"].isInt())return CR_WRONG_USAGE;
              draft.action=action=="group"?df3d_production::TradeDraftAction::Group:df3d_production::TradeDraftAction::ExpandGroup;draft.type=intent["type"].asInt();draft.subtype=intent["subtype"].asInt();
            }else return CR_WRONG_USAGE;
            selections.push_back(draft);}}
        auto projection=df3d_production::tradeProjection(df::building::find(values[0]),size_t(values[1]),filters,selections);
        if(parameters[0]=="trade-draft-probe") {
          using Draft=df3d_production::TradeDraftNative;
          auto draft=std::make_unique<Draft>(df::building::find(values[0]),size_t(values[1]));
          const auto rebuild=[&] {
            const auto checkpoint=draft->checkpoint();if(!checkpoint)return false;
            auto next=std::make_unique<Draft>(df::building::find(values[0]),size_t(values[1]));
            if(!next->restore(*checkpoint))return false;
            draft=std::move(next);return true;
          };
          if(!*draft)return CR_FAILURE;
          for(int32_t side=0;side<2;++side)if(!draft->setFilter(side,filters[side]) || !rebuild())return CR_FAILURE;
          for(const auto& intent:selections)if(!draft->apply(intent) || !rebuild())return CR_FAILURE;
          projection=draft->snapshot();
        }
        Json::Value output;output["available"]=bool(projection);output["sides"]=Json::arrayValue;
        if(projection && (parameters[0]=="trade-negotiation-seed-probe" || parameters[0]=="trade-gift-probe" || parameters[0]=="trade-refusal-probe" || (parameters[0]=="trade-negotiate-probe" || parameters[0]=="trade-accept-probe"))) {
          df3d_production::TradeDraftCheckpoint selected{*projection,filters};
          df3d_production::TradeNegotiationNative context(df::building::find(values[0]),size_t(values[1]),selected);
          if(parameters[0]=="trade-gift-probe"){
            bool started=false;
            try{
              output["executed"]=context.offerGift(&started);
              const auto after=context.checkpoint();if(!after)throw std::runtime_error("Gift outcome unavailable");
              output["dialogue"]=after->conversation.dialogue;output["counter_offer"]=after->conversation.counterOffer;output["rebuild"]=context.goodsNeedRebuild();
              output["announcement"]=Json::arrayValue;for(const auto& line:after->conversation.announcement)output["announcement"].append(DF2UTF(line));
            }catch(...){output["unknown"]=started;}
            output["effects_started"]=started;out.print("{}",Json::FastWriter().write(output));return CR_OK;
          }
          if((parameters[0]=="trade-negotiate-probe" || parameters[0]=="trade-accept-probe")){
            bool started=false;
            try{output["executed"]=context.negotiate(&started);}
            catch(...){output["unknown"]=started;output["effects_started"]=started;out.print("{}",Json::FastWriter().write(output));return CR_OK;}
            output["effects_started"]=started;
          }
          if(parameters[0]=="trade-refusal-probe") {
            const auto check=context.checkOffer();output["disposition"]=int(check.disposition);output["reply_base"]=check.reply;output["ethical"]=check.ethical;output["replies"]=Json::arrayValue;
            // Ethical effects require their own destructive native reference.
            // This diagnostic currently exercises only the RNG/dialogue path.
            if(!check.ethical && check.disposition==df3d_production::TradeOfferDisposition::Refused)for(int i=0;i<2;++i){
              context.refuseOffer();const auto response=context.checkpoint();if(!response)return CR_FAILURE;output["replies"].append(response->conversation.dialogue);}
          }
          auto checkpoint=context.checkpoint();output["available"]=bool(checkpoint);
          if(checkpoint && (parameters[0]=="trade-negotiate-probe" || parameters[0]=="trade-accept-probe")){
            const auto equal=[](const auto& a,const auto& b){return a.dialogue==b.dialogue && a.counterOffer==b.counterOffer && a.requestedItems==b.requestedItems && a.announcement==b.announcement;};
            df3d_production::TradeNegotiationNative restored(df::building::find(values[0]),size_t(values[1]),checkpoint->draft);
            if(!restored.restore(*checkpoint))return CR_FAILURE;
            auto copy=restored.checkpoint();if(!copy || !equal(copy->conversation,checkpoint->conversation))return CR_FAILURE;
            if(parameters[0]=="trade-accept-probe"){
              // Disposable paused oracle: accept only the counteroffer produced
              // above, never client-supplied conversation or raw pointers.
              if(!checkpoint->conversation.counterOffer || checkpoint->conversation.requestedItems.empty())return CR_FAILURE;
              bool started=false;
              try{
                output["accepted_executed"]=restored.negotiate(&started);
                const auto accepted=restored.checkpoint();
                if(!accepted)throw std::runtime_error("Trade outcome unavailable");
                output["dialogue"]=accepted->conversation.dialogue;
                output["counter_offer"]=accepted->conversation.counterOffer;
                output["announcement"]=Json::arrayValue;
                for(const auto& line:accepted->conversation.announcement)output["announcement"].append(DF2UTF(line));
              }catch(...){output["unknown"]=started;}
              output["accept_effects_started"]=started;
              out.print("{}",Json::FastWriter().write(output));return CR_OK;
            }

            output["conversation_restored"]=true;checkpoint=std::move(copy);
            df3d_production::TradeNegotiationNative invalid(df::building::find(values[0]),size_t(values[1]),checkpoint->draft);
            const auto before=invalid.checkpoint();auto missing=*checkpoint;missing.conversation.requestedItems.push_back(INT32_MAX);
            if(!before || invalid.restore(missing))return CR_FAILURE;
            const auto after=invalid.checkpoint();if(!after || !equal(before->conversation,after->conversation))return CR_FAILURE;
            output["missing_counter_item_rejected"]=true;
            auto announcement=*checkpoint;announcement.conversation.dialogue=-1;announcement.conversation.announcement={"Synthetic owned announcement","Second line"};
            if(!invalid.restore(announcement))return CR_FAILURE;
            const auto text=invalid.checkpoint();if(!text || !equal(text->conversation,announcement.conversation))return CR_FAILURE;
            output["owned_text_roundtrip"]=true;
          }
          if(checkpoint){projection=checkpoint->draft.sides;const auto& c=checkpoint->conversation;
            output["dialogue"]=c.dialogue;output["counter_offer"]=c.counterOffer;output["requested_items"]=Json::arrayValue;output["announcement"]=Json::arrayValue;
            for(auto id:c.requestedItems)output["requested_items"].append(id);
            for(const auto& line:c.announcement)output["announcement"].append(DF2UTF(line));}
        }
        if(projection && parameters[0]=="trade-display-probe"){
          output["display"]=Json::arrayValue;
          for(int32_t side=0;side<2;++side){
            const auto page=df3d_production::tradeDisplayPage(df::building::find(values[0]),size_t(values[1]),(*projection)[side],0,64,side);if(!page)return CR_FAILURE;
            Json::Value result;result["total"]=Json::UInt64(page->total);result["rows"]=Json::arrayValue;
            for(const auto& row:page->rows){Json::Value value;value["group"]=row.group;value["expanded"]=row.expanded;value["id"]=row.id;value["parent"]=row.parent;value["type"]=row.type;value["subtype"]=row.subtype;value["flags"]=row.flags;value["amount"]=row.amount;value["caption"]=DF2UTF(row.caption);value["disposition"]=int(row.disposition);value["contained_count"]=row.containedCount;value["expandable"]=row.expandable;value["contents_caption"]=DF2UTF(row.contentsCaption);
              if(row.valuation){value["value_caption"]=DF2UTF(row.valuation->valueCaption);value["weight_caption"]=DF2UTF(row.valuation->weightCaption);value["value"]=row.valuation->value;value["appraisal"]=row.valuation->appraisal;}
              result["rows"].append(value);
            }
            const auto offset=std::min(size_t(3),page->total);const auto partial=df3d_production::tradeDisplayPage(df::building::find(values[0]),size_t(values[1]),(*projection)[side],offset,4,side);
            if(!partial || partial->offset!=offset || partial->total!=page->total || partial->rows.size()!=std::min(size_t(4),page->total-offset))return CR_FAILURE;
            for(size_t i=0;i<partial->rows.size();++i)if(partial->rows[i].id!=page->rows[offset+i].id || partial->rows[i].caption!=page->rows[offset+i].caption)return CR_FAILURE;
            if(df3d_production::tradeDisplayPage(df::building::find(values[0]),size_t(values[1]),(*projection)[side],page->total+1,4,side) || df3d_production::tradeDisplayPage(df::building::find(values[0]),size_t(values[1]),(*projection)[side],0,65,side))return CR_FAILURE;
            result["bounded_page_verified"]=true;output["display"].append(result);
          }
        }
        if(projection){const auto totals=df3d_production::tradeValueTotals(df::building::find(values[0]),size_t(values[1]),*projection);
          if(!totals)return CR_FAILURE;
          auto& value=output["value_totals"];value["broker_appraisal"]=totals->brokerAppraisal;value["actual"]=value["estimated"]=Json::arrayValue;
          for(auto number:totals->actual)value["actual"].append(number);for(auto number:totals->estimated)value["estimated"].append(number);
          value["actual_profit"]=totals->actualProfit;value["estimated_profit"]=totals->estimatedProfit;value["profit_color"]=totals->profitColor;
          const auto bytes=[](const std::string& text){Json::Value result(Json::arrayValue);for(unsigned char ch:text)result.append(ch);return result;};
          value["value_captions"]=Json::arrayValue;for(const auto& caption:totals->valueCaptions)value["value_captions"].append(bytes(caption));
          value["profit_caption"]=bytes(totals->profitCaption);
          const auto capacity=df3d_production::tradeCapacity(df::building::find(values[0]),size_t(values[1]),*projection);if(!capacity)return CR_FAILURE;
          auto& weight=output["capacity"];weight["whole"]=capacity->whole;weight["fraction"]=capacity->fraction;weight["excess"]=capacity->excess;weight["color"]=capacity->color;weight["caption"]=Json::arrayValue;
          for(unsigned char ch:capacity->caption)weight["caption"].append(ch);
        }
        if(projection)for(const auto& side:*projection){Json::Value row;row["height"]=side.height;row["items"]=row["flags"]=row["amounts"]=row["groups"]=Json::arrayValue;
          for(auto id:side.items)row["items"].append(id);for(auto flag:side.flags)row["flags"].append(flag);for(auto amount:side.amounts)row["amounts"].append(amount);
          for(const auto& group:side.groups){Json::Value g;g["type"]=group.type;g["subtype"]=group.subtype;g["expanded"]=group.expanded;g["on"]=group.on;g["flags"]=group.flags;row["groups"].append(g);}output["sides"].append(row);}
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="trade-goods-source-probe") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t values[2]={-1,-1};
        for(size_t i=1;i<parameters.size();++i){const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<0)return CR_WRONG_USAGE;}
        const auto source=df3d_production::tradeGoodsSources(df::building::find(values[0]),size_t(values[1]));
        Json::Value output;output["available"]=bool(source);output["sides"]=Json::arrayValue;
        if(source)for(const auto& side:*source){Json::Value ids=Json::arrayValue;for(auto id:side)ids.append(id);output["sides"].append(ids);}
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="trade-dialogue-probe" || parameters[0]=="trade-header-probe") {
        if(parameters.size()!=4 && !(parameters[0]=="trade-header-probe" && parameters.size()==5))return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t values[3]={};for(size_t i=1;i<4;++i){const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<0)return CR_WRONG_USAGE;}
        if(values[2]>28)return CR_WRONG_USAGE;
        if(parameters[0]=="trade-header-probe") {
          const auto header=df3d_production::tradeHeader(df::building::find(values[0]),size_t(values[1]),int16_t(values[2]));
          Json::Value output;output["available"]=bool(header);
          if(header){output["name"]=DF2UTF(header->name);output["speaker"]=header->speaker;output["dialogue"]=DF2UTF(header->dialogue);output["mood"]=DF2UTF(header->mood);output["mood_color"]=header->moodColor;output["status_color"]=header->statusColor;output["status"]=Json::arrayValue;for(const auto& line:header->status)output["status"].append(DF2UTF(line));
            if(parameters.size()==5){int32_t columns=0;const auto& raw=parameters[4];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),columns);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;
              const auto lines=df3d_production::tradeDialogueLines(header->dialogue,columns);if(!lines)return CR_FAILURE;output["lines"]=Json::arrayValue;for(const auto& line:*lines)output["lines"].append(DF2UTF(line));}
            if(header->nameColor){const auto& c=*header->nameColor;output["name_color"]=Json::arrayValue;for(auto v:c.color)output["name_color"].append(v);output["name_effect"]=c.effect;}}
          if(header && header->appearance){
              const auto& recipe=header->appearance;
              auto& art=output["appearance"];art["pages"]=art["palettes"]=art["layers"]=Json::arrayValue;
              for(const auto& page:recipe->pages)art["pages"].append(page);for(const auto& palette:recipe->palettes)art["palettes"].append(palette);
              for(const auto& layer:recipe->layers){Json::Value values(Json::arrayValue);for(auto v:layer)values.append(v);art["layers"].append(values);}}
          out.print("{}",Json::FastWriter().write(output));return CR_OK;
        }
        const auto entry=df3d_production::tradeEntryFacts(df::building::find(values[0]),size_t(values[1]));
        std::optional<std::string> dialogue;
        if(entry){auto* civ=df::historical_entity::find(entry->entity);auto* caravan=df::global::plotinfo->caravans[size_t(values[1])];
          if(civ && caravan)dialogue=df3d_production::tradeDialogue(*civ,*caravan,df::unit::find(entry->fortressTrader),int16_t(values[2]));}
        Json::Value output;output["available"]=bool(dialogue);if(dialogue)output["dialogue"]=DF2UTF(*dialogue);
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="trade-entry-probe") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t values[2]={-1,-1};
        for(size_t i=1;i<parameters.size();++i){const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<0)return CR_WRONG_USAGE;}
        const auto facts=df3d_production::tradeEntryFacts(df::building::find(values[0]),size_t(values[1]));
        Json::Value output;output["available"]=bool(facts);
        if(facts){output["entity"]=facts->entity;output["fortress_trader"]=facts->fortressTrader;output["merchant_trader"]=facts->merchantTrader;
          output["talkline"]=facts->dialogue;output["stillunloading"]=int(facts->unloading);output["havetalker"]=int(facts->hasSpeaker);
          output["title"]=DF2UTF(facts->title);output["talker"]=DF2UTF(facts->speaker);output["fortname"]=DF2UTF(facts->fortress);output["place"]=DF2UTF(facts->place);}
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="depot-settings-probe") {
        if(parameters.size()!=2 && parameters.size()!=4)return CR_WRONG_USAGE;
        if(!state.mapLoaded || !df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
        int32_t values[3]={-1,-1,-1};
        for(size_t i=1;i<parameters.size();++i) {
          const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-1]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size() || values[i-1]<0)return CR_WRONG_USAGE;
        }
        auto* target=df::building::find(values[0]);Json::Value output;
        if(parameters.size()==4)output["outcome"]=int(df3d_production::setDepotMode(target,uint32_t(values[1]),values[2]));
        const auto facts=df3d_production::depotFacts(target);if(!facts)return CR_FAILURE;
        output["flags"]=facts->flags;output["goods"]=facts->goods;output["trade"]=facts->trade;output["worker"]=facts->worker;
        const auto broker=df3d_production::depotBrokerFacts(target);if(!broker)return CR_FAILURE;
        output["broker_id"]=broker->id;output["broker_name"]=DF2UTF(broker->name);output["activity"]=DF2UTF(broker->activity);
        output["foreground"]=broker->foreground;output["background"]=broker->background;output["bright"]=broker->bright;output["accessible"]=broker->accessible;
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="well-status-probe") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id=-1;const auto& text=parameters[1];
        const auto parsed=std::from_chars(text.data(),text.data()+text.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        const auto value=df3d_production::wellStatus(df::building::find(id));if(!value)return CR_FAILURE;
        Json::Value output;output["status"]=int(*value);
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="machinery-body-probe") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id=-1;const auto& text=parameters[1];
        const auto parsed=std::from_chars(text.data(),text.data()+text.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=text.data()+text.size())return CR_WRONG_USAGE;
        const auto value=df3d_production::machineryBody(df::building::find(id));if(!value)return CR_FAILURE;
        Json::Value output;output["machine_id"]=value->machineId;output["produced"]=value->produced;output["required"]=value->required;
        output["status"]=int(value->status);output["stable_foundation"]=value->stableFoundation;output["disengaged"]=value->disengaged;
        output["pump_manual"]=int(value->pumpManual);output["pump_direction"]=int(value->pumpDirection);
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-animal-restraint-read") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id;const auto& value=parameters[1];const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        auto* item=df::item::find(id);if(!item)return CR_FAILURE;
        const auto facts=df3d_area::nativeZoneAnimalRestraint(*item);if(!facts)return CR_FAILURE;
        Json::Value output;output["rope"]=facts->rope;output["solid_color"]=facts->solidColor;output["color_id"]=facts->colorId;
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-animal-container-read") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id;const auto& value=parameters[1];const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        auto* item=df::item::find(id);if(!item)return CR_FAILURE;
        const auto facts=df3d_area::nativeZoneAnimalContainer(*item);if(!facts)return CR_FAILURE;
        Json::Value output;output["material_family"]=int(facts->materialFamily);output["solid_color"]=facts->solidColor;output["color_id"]=facts->colorId;
        output["occupant_entity"]=int(facts->occupantEntity);output["occupant_id"]=facts->occupantId;
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-animal-status-read") {
        if(parameters.size()!=4)return CR_WRONG_USAGE;
        int32_t values[3];
        for(int i=0;i<3;++i) {
          const auto& value=parameters[i+1];const auto parsed=std::from_chars(value.data(),value.data()+value.size(),values[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        }
        auto* zone=virtual_cast<df::building_civzonest>(df::building::find(values[0]));if(!zone)return CR_FAILURE;
        std::optional<df3d_area::ZoneAnimalStatus> status;
        if(values[1]==1) {
          auto* unit=df::unit::find(values[2]);if(!unit)return CR_FAILURE;
          status=df3d_area::nativeZoneAnimalStatus(*zone,*unit);
        } else if(values[1]==2) {
          if(!df::item::find(values[2]))return CR_FAILURE;
          status=df3d_area::nativeZoneAnimalItemStatus(*zone,
            std::find(zone->assigned_items.begin(),zone->assigned_items.end(),values[2])!=zone->assigned_items.end());
        } else return CR_WRONG_USAGE;
        if(!status)return CR_FAILURE;
        Json::Value output;output["kind"]=int(status->kind);output["containment"]=int(status->containment);output["item_id"]=status->itemId;
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-animal-unit-display-read") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        int32_t values[2];
        for(int i=0;i<2;++i) {
          const auto& value=parameters[i+1];const auto parsed=std::from_chars(value.data(),value.data()+value.size(),values[i]);
          if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        }
        auto* unit=df::unit::find(values[0]);if(!unit)return CR_FAILURE;
        const auto result=df3d_area::nativeZoneAnimalUnitDisplay(*unit,values[1]);if(!result)return CR_FAILURE;
        Json::Value output;output["grazer"]=result->grazer;
        output["text"]=Json::Value(Json::arrayValue);
        for(const auto* text:{&result->text.combined,&result->text.name,&result->text.profession,&result->text.firstLine,&result->text.secondLine}) {
          Json::Value bytes(Json::arrayValue);for(unsigned char byte:*text)bytes.append(int(byte));output["text"].append(bytes);
        }
        output["warning"]=Json::Value(Json::arrayValue);for(unsigned char byte:result->warning)output["warning"].append(int(byte));
        auto& color=output["name_color"];color["effect"]=int(result->nameColor.effect);color["source"]=int(result->nameColor.source);
        for(auto c:result->nameColor.color)color["color"].append(int(c));
        for(auto c:result->nameColor.alternate)color["alternate"].append(int(c));
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-selected-owners-read") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id=-1;const auto& value=parameters[1];
        const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        auto* zone=virtual_cast<df::building_civzonest>(df::building::find(id));if(!zone)return CR_FAILURE;
        const auto result=df3d_area::nativeZoneSelectedOwners(*zone);if(!result)return CR_FAILURE;
        Json::Value output(Json::arrayValue);
        for(const auto& row:*result) {
          Json::Value item(Json::objectValue),caption(Json::arrayValue),status(Json::arrayValue);
          item["id"]=row.id;
          for(unsigned char byte:row.caption)caption.append(int(byte));
          for(unsigned char byte:row.status)status.append(int(byte));
          item["caption"]=caption;item["status"]=status;output.append(item);
        }
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-owner-text-read") {
        if(parameters.size()!=3)return CR_WRONG_USAGE;
        int32_t id=-1;const auto& value=parameters[1];
        const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        auto* unit=df::unit::find(id);if(!unit)return CR_FAILURE;
        int32_t columns=0;const auto& width=parameters[2];
        const auto parsedWidth=std::from_chars(width.data(),width.data()+width.size(),columns);
        if(parsedWidth.ec!=std::errc{} || parsedWidth.ptr!=width.data()+width.size())return CR_WRONG_USAGE;
        const auto result=df3d_area::nativeZoneOwnerDisplayText(*unit,columns);if(!result)return CR_FAILURE;
        Json::Value output(Json::arrayValue);
        for(const auto* text:{&result->combined,&result->name,&result->profession,&result->firstLine,&result->secondLine}) {
          Json::Value bytes(Json::arrayValue);for(unsigned char byte:*text)bytes.append(int(byte));output.append(bytes);
        }
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-owner-query-read") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        auto key=df3d_area::nativeZoneOwnerQuery(parameters[1]);if(!key)return CR_FAILURE;
        Json::Value bytes(Json::arrayValue);for(unsigned char byte:*key)bytes.append(int(byte));
        out.print("{}",Json::FastWriter().write(bytes));return CR_OK;
      }
      if(parameters[0]=="zone-owner-order-read") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id=-1;const auto& value=parameters[1];
        const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        auto* zone=virtual_cast<df::building_civzonest>(df::building::find(id));
        if(!zone || !df::global::world)return CR_FAILURE;
        struct Row {int32_t id;df3d_area::ZoneOwnerOrderFacts facts;};
        std::vector<Row> rows;
        for(auto* unit:df::global::world->units.all) {
          if(!unit)continue;
          auto eligible=df3d_area::nativeZoneOwnerEligible(*zone,*unit);
          if(!eligible)return CR_FAILURE;
          if(!*eligible)continue;
          auto facts=df3d_area::nativeZoneOwnerOrderFacts(*zone,*unit);
          if(!facts)return CR_FAILURE;
          rows.push_back({unit->id,*facts});
        }
        Json::Value output(Json::arrayValue);
        for(const auto& r:rows) {
          Json::Value row(Json::arrayValue);
          row.append(r.id);row.append(r.facts.withoutRoom?1:0);row.append(r.facts.priority);
          row.append(r.facts.category);row.append(r.facts.categoryStatus);row.append(r.facts.stress);
          for(const auto* key:{&r.facts.nameKey,&r.facts.professionKey}) {
            Json::Value bytes(Json::arrayValue);for(unsigned char byte:*key)bytes.append(int(byte));row.append(bytes);
          }
          output.append(row);
        }
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-animal-item-text-read" || parameters[0]=="zone-animal-item-color-read") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id=-1;const auto& value=parameters[1];
        const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        auto* item=df::item::find(id);if(!item)return CR_FAILURE;
        if(parameters[0]=="zone-animal-item-color-read") {
          const auto color=df3d_area::nativeZoneAnimalItemColor(*item);if(!color)return CR_FAILURE;
          Json::Value values(Json::arrayValue);for(auto value:*color)values.append(int(value));
          out.print("{}",Json::FastWriter().write(values));return CR_OK;
        }
        const auto text=df3d_area::nativeZoneAnimalItemText(*item);if(!text)return CR_FAILURE;
        Json::Value bytes(Json::arrayValue);for(unsigned char byte:*text)bytes.append(int(byte));
        out.print("{}",Json::FastWriter().write(bytes));return CR_OK;
      }
      if(parameters[0]=="zone-squad-symbol-read") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id=-1;const auto& value=parameters[1];
        const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        auto* squad=df::squad::find(id);if(!squad)return CR_FAILURE;
        const auto symbol=df3d_area::nativeZoneSquadSymbol(*squad);if(!symbol)return CR_FAILURE;
        Json::Value output(Json::arrayValue);for(auto byte:*symbol)output.append(int(byte));
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-squad-swatches-read") {
        if(parameters.size()!=1)return CR_WRONG_USAGE;
        const auto swatches=df3d_area::nativeZoneSquadSwatches();if(!swatches)return CR_FAILURE;
        Json::Value output(Json::arrayValue);for(auto byte:*swatches)output.append(int(byte));
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-squad-name-read") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id=-1;const auto& value=parameters[1];
        const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        auto* squad=df::squad::find(id);if(!squad)return CR_FAILURE;
        const auto text=df3d_area::nativeZoneSquadName(*squad);if(!text)return CR_FAILURE;
        Json::Value output(Json::arrayValue);for(unsigned char byte:*text)output.append(int(byte));
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-squad-candidates-read") {
        if(parameters.size()!=1)return CR_WRONG_USAGE;
        const auto ids=df3d_area::nativeZoneSquadCandidates();
        if(!ids)return CR_FAILURE;
        Json::Value output(Json::arrayValue);for(auto id:*ids)output.append(id);
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-animal-candidates-read" || parameters[0]=="zone-animal-picker-read") {
        const bool picker=parameters[0]=="zone-animal-picker-read";
        if(parameters.size()!=(picker?5:2))return CR_WRONG_USAGE;
        int32_t id=-1;const auto& value=parameters[1];
        const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        auto* zone=virtual_cast<df::building_civzonest>(df::building::find(id));
        if(!zone)return CR_FAILURE;
        int32_t sort=0,descending=0;
        if(picker) {
          for(auto pair:{std::pair<size_t,int32_t*>(2,&sort),{3,&descending}}) {
            const auto& arg=parameters[pair.first];const auto parsed=std::from_chars(arg.data(),arg.data()+arg.size(),*pair.second);
            if(parsed.ec!=std::errc{} || parsed.ptr!=arg.data()+arg.size())return CR_WRONG_USAGE;
          }
          if(descending<0 || descending>1)return CR_WRONG_USAGE;
        }
        const auto candidates=picker?df3d_area::nativeZoneAnimalPickerCandidates(*zone,sort,descending!=0,parameters[4]):
          df3d_area::nativeZoneAnimalCandidates(*zone);
        if(!candidates)return CR_FAILURE;
        Json::Value output(Json::arrayValue);
        for(const auto& candidate:*candidates) {
          Json::Value row;row["id"]=candidate.id;row["kind"]=candidate.item?1:0;row["assigned"]=candidate.assigned;
          output.append(row);
        }
        out.print("{}",Json::FastWriter().write(output));return CR_OK;
      }
      if(parameters[0]=="zone-owner-candidates-read" || parameters[0]=="zone-new-owner-candidates-read") {
        if(parameters.size()!=2)return CR_WRONG_USAGE;
        int32_t id=-1;const auto& value=parameters[1];
        const auto parsed=std::from_chars(value.data(),value.data()+value.size(),id);
        if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        const bool unassigned=parameters[0]=="zone-new-owner-candidates-read";
        auto* zone=unassigned?nullptr:virtual_cast<df::building_civzonest>(df::building::find(id));
        if((!unassigned && !zone) || !df::global::world || !df3d_area::nativeZoneOwnerCandidatesReady())return CR_FAILURE;
        std::vector<int32_t> ids;
        for(auto* unit:df::global::world->units.all) {
          if(!unit)continue;
          auto eligible=unassigned?df3d_area::nativeZoneNewOwnerEligible(id,*unit):df3d_area::nativeZoneOwnerEligible(*zone,*unit);
          if(!eligible)return CR_FAILURE;
          if(*eligible)ids.push_back(unit->id);
        }
        out.print("[ ");
        for(size_t i=0;i<ids.size();++i)out.print("{}{}",i?",":"",ids[i]);
        out.print(" ]\n");return CR_OK;
      }
      if (parameters[0] == "room-read") {
        if(parameters.size()!=4)return CR_WRONG_USAGE;
        int32_t xyz[3]{};
        for(size_t i=0;i<3;++i) {
            const auto& value=parameters[i+1];
            const auto parsed=std::from_chars(value.data(),value.data()+value.size(),xyz[i]);
            if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size())return CR_WRONG_USAGE;
        }
        const auto room=df3d_area::observeNativeRoom(xyz[0],xyz[1],xyz[2]);
        out.print("{{\"status\":{},\"x\":{},\"y\":{},\"z\":{},\"width\":{},\"height\":{},\"extents\":[",
            int(room.traversal.status),room.x,room.y,room.z,room.width,room.height);
        for(size_t i=0;i<room.traversal.reached.size();++i)
            out.print("{}{}",i?",":"",int(room.traversal.reached[i]));
        out.print("]}}\n");
        return CR_OK;
    }
    if (parameters[0] == "record") {
        if (parameters.size() >= 2 && parameters[1] == "stop") {
            std::unique_lock<std::mutex> lock(state.recordMutex);
            const bool active = state.recordFile.is_open();
            lock.unlock();
            if (!active) {
                out.printerr("df3d: not recording\n");
                return CR_FAILURE;
            }
            stopRecording(out, true);
            return CR_OK;
        }
        if (parameters.size() >= 3 && parameters[1] == "start")
            return cmdRecordStart(out, parameters[2]);
        return CR_WRONG_USAGE;
    }
    if (parameters[0] == "scan") {
        if (parameters.size() < 2) return CR_WRONG_USAGE;
        const int n = std::atoi(parameters[1].c_str());
        if (n <= 0) return CR_WRONG_USAGE;
        const uint32_t clamped = df3d_scan_schedule::clampSlice(static_cast<uint32_t>(n));
        state.terrain.setSliceBlocks(clamped);
        if (clamped != static_cast<uint32_t>(n))
            out.print("df3d: rescan slice clamped to the {} block maximum per update\n", clamped);
        else
            out.print("df3d: rescan slice set to {} blocks per update\n", clamped);
        return CR_OK;
    }
    if (parameters[0] == "rescan") {
        state.terrain.requestRescan();
        out.print("df3d: full rescan scheduled: {} blocks, at most {} per update\n",
                  state.terrain.blockCount(), std::max(df3d_scan_schedule::kRescanSliceBlocks, state.terrain.sliceBlocks()));
        return CR_OK;
    }
    if (parameters[0] == "apprate") {
        if (parameters.size() < 3) return CR_WRONG_USAGE;
        const int a = std::atoi(parameters[1].c_str());
        const int b = std::atoi(parameters[2].c_str());
        if (a < 0 || b < 0) return CR_WRONG_USAGE;
        state.appearance.resolvePeriod = static_cast<uint32_t>(a);
        state.appearance.refreshPeriod = static_cast<uint32_t>(b);
        out.print("df3d: appearance resolve period {} frames, refresh period {} frames (0 = off)\n", a, b);
        return CR_OK;
    }
    if (parameters[0] == "entrate") {
        if (parameters.size() < 5) return CR_WRONG_USAGE;
        const int ip = std::atoi(parameters[1].c_str());
        const int bp = std::atoi(parameters[2].c_str());
        const int rp = std::atoi(parameters[3].c_str());
        const int rf = std::atoi(parameters[4].c_str());
        if (ip <= 0 || bp <= 0 || rp < 0 || rf < 0) return CR_WRONG_USAGE;
        ent::Config& c = ent::config();
        c.itemPass = static_cast<uint32_t>(ip);
        c.buildingPass = static_cast<uint32_t>(bp);
        c.repeat = static_cast<uint32_t>(rp);
        c.refresh = static_cast<uint32_t>(rf);
        out.print("df3d: item pass {} frames, building pass {} frames, repeat {} frames, refresh every {} frames\n",
                  ip, bp, rp, rf);
        return CR_OK;
    }
    if (parameters[0] == "corpse") {
        if (!state.mapLoaded) {
            out.printerr("df3d: no map loaded\n");
            return CR_FAILURE;
        }
        if (parameters.size() < 2) return CR_WRONG_USAGE;
        const string& what = parameters[1];
        if (what == "survey") {
            const int n = parameters.size() >= 3 ? std::atoi(parameters[2].c_str()) : 60;
            app::surveyCorpses(out, n > 0 ? n : 60);
            return CR_OK;
        }
        df::item* it = nullptr;
        if (what == "first") {
            // The first whole corpse in the main viewport at the current z
            // (the one DF has drawn, so the oracle exists), else the first
            // on the ground anywhere.
            df::item* anywhere = nullptr;
            for (df::item* cand : world->items.other.IN_PLAY) {
                if (!cand || !cand->flags.bits.on_ground || cand->getType() != df::item_type::CORPSE) continue;
                if (!anywhere) anywhere = cand;
                if (app::viewportIndexAt(cand->pos) >= 0) { it = cand; break; }
            }
            if (!it) it = anywhere;
        } else {
            it = df::item::find(std::atoi(what.c_str()));
        }
        if (!it) { out.printerr("df3d: corpse item not found\n"); return CR_FAILURE; }
        const bool verify = parameters.size() >= 3 && parameters[2] == "verify";
        app::dumpCorpse(out, it, verify, parameters.size() >= 4 ? parameters[3] : string());
        return CR_OK;
    }
    if (parameters[0] == "glyphs") {
        if (!state.mapLoaded) {
            out.printerr("df3d: no map loaded\n");
            return CR_FAILURE;
        }
        const int n = parameters.size() >= 2 ? std::atoi(parameters[1].c_str()) : 12;
        int shown = 0;
        out.print("creatures ({}): id tile fg:bg:br soldier_tile (creature raw); castes whose CASTE_TILE differs\n",
                  world->raws.creatures.all.size());
        int casteDiffers = 0;
        for (const df::creature_raw* raw : world->raws.creatures.all) {
            if (!raw) continue;
            int diff = 0;
            for (const df::caste_raw* c : raw->caste) {
                if (!c) continue;
                const bool tileSet = c->caste_tile != 1 && c->caste_tile != raw->creature_tile;
                const bool colorSet = (c->caste_color[0] || c->caste_color[1] || c->caste_color[2]) && c->caste_color != raw->color;
                if (tileSet || colorSet) ++diff;
            }
            if (diff) ++casteDiffers;
            if (shown++ < n)
                out.print("  {:<24} tile {:3} color {}:{}:{} soldier {:3} castes {} (differing {})\n", raw->creature_id.c_str(),
                          raw->creature_tile, raw->color[0], raw->color[1], raw->color[2], raw->creature_soldier_tile, raw->caste.size(), diff);
        }
        out.print("  creatures with a caste tile / colour override: {}\n", casteDiffers);
        out.print("materials ({} in the grid table): token tile item_symbol basic fg:br build fg:bg:br tile_color fg:bg:br\n",
                  state.terrain.materialTokenCount());
        shown = 0;
        for (size_t i = 0; i < state.terrain.materialTokenCount() && shown < n; ++i, ++shown) {
            MaterialInfo mi;
            const string tok(state.terrain.materialToken(i));
            if (!mi.find(tok) || !mi.material) { out.print("  {:<32} (does not resolve)\n", tok.c_str()); continue; }
            const df::material* m = mi.material;
            out.print("  {:<32} tile {:3} sym {:3} basic {}:{} build {}:{}:{} tile_color {}:{}:{}\n", tok.c_str(), m->tile, m->item_symbol,
                      m->basic_color[0], m->basic_color[1], m->build_color[0], m->build_color[1], m->build_color[2], m->tile_color[0],
                      m->tile_color[1], m->tile_color[2]);
        }
        out.print("tool itemdefs ({}): id tile\n", world->raws.itemdefs.tools.size());
        shown = 0;
        for (const df::itemdef_toolst* def : world->raws.itemdefs.tools) {
            if (!def || shown++ >= n) continue;
            out.print("  {:<32} tile {:3}\n", def->id.c_str(), def->tile);
        }
        return CR_OK;
    }
    if (parameters[0] == "appearance") {
        if (!state.mapLoaded) {
            out.printerr("df3d: no map loaded\n");
            return CR_FAILURE;
        }
        if (parameters.size() < 2) return CR_WRONG_USAGE;
        const string& what = parameters[1];
        if (what == "recipe") {
            if(parameters.size()!=5)return CR_WRONG_USAGE;
            if(!df::global::pause_state || !*df::global::pause_state || df3d_session::saving())return CR_FAILURE;
            int32_t values[2]={};for(size_t i=2;i<4;++i){const auto& raw=parameters[i];const auto parsed=std::from_chars(raw.data(),raw.data()+raw.size(),values[i-2]);if(parsed.ec!=std::errc{} || parsed.ptr!=raw.data()+raw.size())return CR_WRONG_USAGE;}
            return app::dumpUnitRecipe(out,df::unit::find(values[0]),values[1],parameters[4])?CR_OK:CR_FAILURE;
        }
        if (what == "texture") {
            if (parameters.size() != 4) return CR_WRONG_USAGE;
            if (!df::global::pause_state || !*df::global::pause_state || df3d_session::saving()) {
                out.printerr("df3d: texture diagnostic requires a paused loaded map, outside saving\n");
                return CR_FAILURE;
            }
            int32_t texpos = -1;
            const string& id = parameters[2];
            const auto parsed = std::from_chars(id.data(), id.data() + id.size(), texpos);
            if (parsed.ec != std::errc{} || parsed.ptr != id.data() + id.size() || texpos < 0)
                return CR_WRONG_USAGE;
            return app::dumpTexture(out, texpos, parameters[3]) ? CR_OK : CR_FAILURE;
        }
        if (what == "pages") {
            app::dumpPages(out);
            return CR_OK;
        }
        if (what == "survey") {
            const int n = parameters.size() >= 3 ? std::atoi(parameters[2].c_str()) : 40;
            app::survey(out, n > 0 ? n : 40);
            return CR_OK;
        }
        auto findUnit = [&](const string& sel) -> df::unit* {
            if (sel == "first") {
                for (df::unit* u : world->units.active)
                    if (Units::isActive(u) && !Units::isDead(u) && Units::isCitizen(u)) return u;
                return world->units.active.empty() ? nullptr : world->units.active[0];
            }
            return df::unit::find(std::atoi(sel.c_str()));
        };
        if (what == "layersets") {
            if (parameters.size() < 3) return CR_WRONG_USAGE;
            df::unit* u = findUnit(parameters[2]);
            if (!u) { out.printerr("df3d: unit not found\n"); return CR_FAILURE; }
            const int n = parameters.size() >= 4 ? std::atoi(parameters[3].c_str()) : 60;
            app::dumpLayerSet(out, u, n > 0 ? n : 60, parameters.size() >= 5 ? parameters[4] : string());
            return CR_OK;
        }
        df::unit* u = findUnit(what);
        if (!u) { out.printerr("df3d: unit not found\n"); return CR_FAILURE; }
        if (parameters.size() >= 4 && parameters[2] == "trace") {
            app::trace(out, u, parameters[3]);
            return CR_OK;
        }
        const bool verify = parameters.size() >= 3 && parameters[2] == "verify";
        app::dump(out, u, verify, parameters.size() >= 4 ? parameters[3] : string());
        return CR_OK;
    }
    return CR_WRONG_USAGE;
}

}  // namespace

// ---- plugin entry points ----

DFhackCExport command_result plugin_init(color_ostream& out,
                                         std::vector<PluginCommand>& commands) {
    df3d_contact::registerCommands(commands);
    commands.push_back(PluginCommand(
        "df3d",
        "DF3D mirror bridge: publish game state to shared memory.",
        df3d_command,
        false,  // not interactive
        false,  // run with core suspended
        "df3d [status]\n"
        "    Print bridge state (shm region, terrain grid, timings, counters).\n"
        "df3d paint-water-read <x> <y> <z> (0 unknown, 1 ineligible, 2 eligible)\n"
        "df3d paint-base-read <x> <y> <z> (ordinary/Pond eligibility; same codes)\n"
        "df3d paint-material-read <x> <y> <z> (sand/clay eligibility; same codes)\n"
        "df3d location-religions-read (ordered semantic temple identities; read-only)\n"
        "df3d location-staff-candidates <site id> <location id> <occupation id> [cursor revision] (semantic candidates; read-only)\n"
        "df3d location-staff-set <site id> <location id> <occupation id> <unit id|-1> <revision> (protected staff mutation)\n"
        "df3d location-staff-read <site id> <location id> (semantic staffing rows; read-only)\n"
        "df3d location-specialization-read <site> <location> <source> <entity|-1> <row> <unit> (semantic receipt)\n"
        "df3d location-staff-assignments-read <site> <location> <source> <entity|-1> <row> <unit> (ordered memberships)\n"
        "df3d location-specialization-set <site> <location> <source> <entity|-1> <row> <unit> <revision> <0|1> (protected mutation)\n"
        "df3d location-staff-prepare <site id> <location id> (create missing empty roles; protected acceptance)\n"
        "df3d location-access-set <site id> <location id> <mode 0..3> <revision> (protected access mutation)\n"
        "df3d location-name-words <component 0..6> [query] [language] (protected native word-selector observation)\n"
        "df3d location-name-pick <component 0..6> [query] (protected native selection; consumes RNG)\n"
        "df3d location-name-generate <site id> <location id> (protected owned name generation; consumes RNG)\n"
        "df3d location-name-read <site id> <location id> (protected structured name and revision observation)\n"
        "df3d location-name-edit <site> <id> <mode 0..3> <target> <displayed> <word> <part> <revision> <query> (protected name mutation)\n"
        "df3d location-quantity-edit <site id> <location id> <quantity 0..10> <mode 0..2> <value> <revision> (protected quantity mutation)\n"
        "df3d location-details-refresh <site id> <location id> (refresh semantic caches; protected acceptance)\n"
        "df3d location-details-read <site id> <location id> (partial semantic Details facts; read-only)\n"
        "df3d location-guilds-read (ordered native guild professions and workers; read-only)\n"
        "df3d site-support-read <family> <x> <y> <z> (read-only support, not full placement)\n"
        "df3d bars-connections-read <x> <y> <z> (read-only native vertical-bar adjacency)\n"
        "df3d stockpile-preset-read <building-id> <preset1..19> (read-only owned native settings)\n"
        "df3d stockpile-category-read <building-id> <category-bit> (read-only native activation)\n"
        "df3d stockpile-header-read <building-id> <category-bit-or-0-global> <1-none-or-2-all> (read-only native header action)\n"
        "df3d stockpile-wood-read <building-id> [filter] (read-only native Wood rows)\n"
        "df3d stockpile-summary-read <building-id> [category-mask] (read-only native summary indicators)\n"
        "df3d stockpile-link-target-read <pile-id> <x> <y> <z> <give0-or-1> (read-only native target lookup)\n"
        "df3d stockpile-tile-types-read <first-uint16> <count1..1024> (read-only native tile predicates)\n"
        "df3d stockpile-rows-cold-read <building-id> <native-mode> [filter] (private historical cache probe)\n"
        "df3d stockpile-rows-read <building-id> <native-mode> [filter] (read-only verified list modes)\n"
        "df3d door-support-read <x> <y> <z> (read-only wall support, not full placement)\n"
        "df3d bed-choices-read <item-id> <descriptor-color-count> (owned-state appearance diagnostic)\n"
        "df3d material-distances-read <sx> <sy> <sz> <tx> <ty> <tz> <tile-limit> (read-only)\n"
        "df3d track-material-order-read <sx> <sy> <sz> <tx> <ty> <tz> <tile-limit> (read-only)\n"
        "df3d track-material-candidates-read <sx> <sy> <sz> <tx> <ty> <tz> <candidate-limit> (read-only)\n"
        "df3d room-read <x> <y> <z>\n"
        "df3d zone-squad-name-read <squad id>\n"
        "df3d zone-squad-symbol-read <squad id>\n"
        "df3d zone-squad-swatches-read\n"
        "df3d zone-squad-candidates-read\n"
        "df3d zone-owner-candidates-read <zone id>\n"
        "df3d zone-new-owner-candidates-read <zone type>\n"
        "df3d zone-owner-order-read <zone id>\n"
        "df3d zone-owner-status-read <zone id> <unit id>\n"
        "df3d zone-owner-text-read <unit id> <columns>\n"
        "df3d zone-selected-owners-read <zone id>\n"
        "df3d zone-owner-color-sources-read <unit id>\n"
        "df3d zone-animal-restraint-read <item id>\n"
        "df3d zone-animal-container-read <item id>\n"
        "df3d zone-animal-status-read <zone id> <entity 1|2> <id>\n"
        "df3d zone-animal-unit-display-read <unit id> <columns>\n"
        "df3d zone-owner-name-color-read <unit id>\n"
        "df3d unit-knowledge-detail-probe <unit id> <kind> <entry id>\n"
        "df3d zone-owner-profession-color-read <unit id> <profession>\n"
        "df3d zone-owner-query-read <query>\n"
        "    Read-only diagnostic: semantic room observation and traversal mask as JSON.\n"
          "df3d room-seed <building id>\n"
          "    Read-only diagnostic: furniture identity and native room-use relations as JSON.\n"
          "df3d room-plan <furniture 1..4> <x> <y> <z> <width> <height>\n"
          "    Read-only diagnostic: native-order room grouping, extents and rejection counts.\n"
          "df3d room-create <furniture 1..4> <x> <y> <z> <width> <height> <epoch>\n"
          "    Mutating diagnostic: create native rooms while paused in the specified fortress epoch.\n"
        "df3d record start <path>\n"
        "    Start a DF3DFIX1 fixture: a Full terrain snapshot, then every\n"
        "    published snapshot.\n"
        "df3d record stop\n"
        "    Stop recording and report the snapshot count.\n"
        "df3d scan <n>\n"
        "    Rescan n blocks per update (amortized terrain change detection;\n"
        "    clamped to 4096).\n"
        "df3d rescan\n"
        "    Rescan every block, spread over the following updates.\n"
        "df3d apprate <resolve> <refresh>\n"
        "    Re-resolve every unit's appearance every <resolve> frames and\n"
        "    re-send it every <refresh> frames (0 = off).\n"
        "df3d appearance <unit id|first> [verify]\n"
        "    Print a unit's resolved layer stack (and compare it with DF's\n"
        "    own cached texture with verify).\n"
        "df3d appearance survey [n] | layersets <unit id|first> [n] | pages\n"
        "df3d appearance texture <texpos> <absolute-output-prefix> (paused diagnostic)\n"
        "    Fidelity survey over n units; raw layer-set dump; page tables.\n"
        "df3d entrate <itemPass> <buildingPass> <repeat> <refresh>\n"
        "    Buildings / items change detection: a complete pass over items\n"
        "    every <itemPass> frames and over buildings every <buildingPass>,\n"
        "    changes re-sent for <repeat> frames, every entity re-sent every\n"
        "    <refresh> frames (0 = off).\n"
        "df3d corpse <item id|first> [verify [dir]] | survey [n]\n"
        "    A corpse item's resolved CORPSE stack, DF's cached corpse texture\n"
        "    and (verify) the pixel diff; survey over n on-map corpse items.\n"
        "df3d glyphs [n]\n"
        "    Print n creature / material / tool-itemdef classic glyph rows.\n"
        "(commands from the shm ring — designations, item / building flags —\n"
        " are executed at every update; `df3d status` reports them)\n"));
    ent::AppearanceHooks hooks;
    hooks.palettePath = palettePathHook;
    hooks.encodeLayer = encodeLayerHook;
    ent::setAppearanceHooks(hooks);
    cmdx::Hooks chooks;
    chooks.hintBlock = [](int32_t bx, int32_t by, int32_t bz) {
        if (state.terrain.mapped()) state.terrain.hintBlock(bx, by, bz);
    };
    chooks.hintItem = ent::hintItem;
    chooks.hintBuilding = ent::hintBuilding;
    cmdx::setHooks(chooks);
    EventManager::registerListener(EventManager::EventType::UNIT_ATTACK, {plugin_self, combatAttack, 1});
    EventManager::registerListener(EventManager::EventType::UNIT_DEATH, {plugin_self, combatDeath, 1});
    EventManager::registerListener(EventManager::EventType::REPORT, {plugin_self, nativeReport, 1});
    return CR_OK;
}

DFhackCExport command_result plugin_shutdown(color_ostream& out) {
    df3d_contact::shutdown();
    EventManager::unregisterAll(plugin_self);
    df3d_session::stop();
    df3d_management::stop();
    stopRecording(out, true);
    is_enabled = false;
    state.mapLoaded = false;
    destroyRegion(out);
    return CR_OK;
}

// The session channel is exclusive per machine: a second DF with the bridge
// loaded cannot own it. That must not prevent this instance from mirroring.
void startSession(color_ostream& out) {
    state.sessionAvailable = df3d_session::start(out);
    if (!state.sessionAvailable && !state.warnedSessionUnavailable) {
        state.warnedSessionUnavailable = true;
        out.printerr("df3d: session channel unavailable; load/save requests are disabled, "
                     "the mirror keeps publishing (reported once per map load)\n");
    }
}

DFhackCExport command_result plugin_enable(color_ostream& out, bool enable) {
    if(enable && !is_enabled) df3d_events::resetReports(false);
    if (enable) startSession(out);
    if (!enable) {df3d_session::stop();df3d_management::stop();state.sessionAvailable=false;}
    // If region creation failed at map load (or the plugin was disabled and
    // torn down by hand), re-enabling with a loaded map retries it.
    if (enable && state.mapLoaded && !state.region && !createRegion(out))
        return CR_FAILURE;
    if (enable && state.mapLoaded && state.region && !state.terrain.mapped())
        state.terrain.create(out,state.region);
    is_enabled = enable;
    df3d_contact::setEnabled(enable && state.mapLoaded);
    return CR_OK;
}

DFhackCExport command_result plugin_onstatechange(color_ostream& out,
                                                  state_change_event event) {
    switch (event) {
    case SC_MAP_LOADED:
        df3d_contact::setEnabled(false);
        df3d_contact::reset();
        df3d_events::resetReports();
        combatEvents.clear(); nextCombatEventId = 1; resetProjectiles();
        state.warnedSessionUnavailable = false;
        startSession(out);  // non-fatal: see startSession
        if (!createRegion(out))
            return CR_FAILURE;
        state.mapLoaded = true;
        state.havePublished = false;
        state.lastUnitCount = 0;
        state.warnedCorruptCommand = false;
        state.warnedUnknownCommand = false;
        state.warnedOversizeSnapshot = false;
        state.warnedUnresolvedRace = false;
        state.updateUsEma = state.scanUsEma = state.publishUsEma = 0.0;
        state.updateUsMax = state.scanUsMax = state.publishUsMax = 0.0;
        state.updates = 0;
        resetAppearances();
        ent::reset();
        cmdx::reset();
        // Results queued while no map was loaded (a rectangle abandoned at
        // unload, commands rejected between maps) were never publishable:
        // they ride on this map's first snapshot; clients match by seq.
        state.commandPublicationPending = !state.results.empty();
        state.entityFullPending = true;
        state.entityFullServed = shm::atomicLoadAcquire(&state.region->entityFullRequest);
        state.terrain.create(out,state.region);  // failure leaves a units-only mirror (logged)
        is_enabled = true;
        df3d_contact::setEnabled(true);
        out.print("df3d: item contact source: {}\n",df3d_contact::status());
        out.print("df3d: map loaded; mirroring every simulated frame\n");
        break;
    case SC_MAP_UNLOADED:
        df3d_production::tradeDiagnosticCatalog().reset();
        df3d_production::tradeDiagnosticOwner().reset();
        df3d_production::tradeDiagnosticSession().reset();
        df3d_contact::setEnabled(false);
        df3d_contact::reset();
        df3d_events::resetReports();
        combatEvents.clear(); nextCombatEventId = 1; resetProjectiles();
        // A fixture must not span a map boundary (ticks restart, map size may
        // change), so recording ends here.
        stopRecording(out, true);
        state.mapLoaded = false;
        abandonPendingCommand();
        // Session channel remains enabled across map/world boundaries.
        destroyTerrain();
        resetAppearances();
        ent::reset();
        break;
    case SC_WORLD_UNLOADED:
        df3d_production::tradeDiagnosticCatalog().reset();
        df3d_production::tradeDiagnosticOwner().reset();
        df3d_production::tradeDiagnosticSession().reset();
        df3d_contact::setEnabled(false);
        stopRecording(out, true);
        state.mapLoaded = false;
        abandonPendingCommand();
        // Session channel remains enabled across map/world boundaries.
        destroyRegion(out);
        break;
    default:
        break;
    }
    return CR_OK;
}

// Runs on the DF simulation thread once per rendered/simulated frame, paused
// or not, whenever is_enabled is true — a safe point.
DFhackCExport command_result plugin_onupdate(color_ostream& out) {
    // Include semantic management dispatch in the bridge's tick-budget measurement.
    const auto t0 = Clock::now();
    df3d_session::update(state.mapLoaded,state.mapLoaded?state.terrain.epoch():0);
    df3d_management::update(out,state.terrain.epoch(),df3d_session::saving());
    if(df3d_management::takeMutation())state.entityFullPending=true;
    int32_t managementX,managementY,managementZ;
    while(df3d_management::takeTerrainHint(managementX,managementY,managementZ))state.terrain.hintBlock(managementX>>4,managementY>>4,managementZ);
    if (!state.region)
        return CR_OK;
    // Commands are drained every update, including while paused — SetPause
    // must work on a paused game.
    drainCommands(out);

    // An output may not yet have reached the amortized item scan when a player
    // pauses. Refresh once on the actual transition, including native DF pauses,
    // without advancing simulation time or rescanning on every paused update.
    if (state.pauseTransitions.observe(state.mapLoaded, state.mapLoaded && World::ReadPauseState()))
        state.entityFullPending = true;

    if (!state.mapLoaded)
        return CR_OK;

    const int32_t frame = world->frame_counter;
    // Native cancellation/placement changes the building sequence even while
    // paused. Detect that cheaply, then publish current entities and released
    // item reservations once. Pending subtype/stage changes also need refresh,
    // even when completed native building objects remain in the same list.
    if (World::ReadPauseState()) {
        const bool pendingChanged = ent::pendingConstructionChanged([](int32_t x,int32_t y,int32_t z) {
            state.terrain.hintBlock(x>>4,y>>4,z);
        });
        if (pendingChanged || ent::buildingSequenceChanged()) state.entityFullPending = true;
    }

    // Terrain maintenance runs every update (paused too) so the grid stays
    // current; the ring carries the resulting Deltas when the sim advances
    // or a command/entity refresh requests publication. gridTick is the
    // current frame: a client synthesizing from the grid then correctly skips
    // a Delta stamped with this same tick.
    {
        const auto ts = Clock::now();
        state.terrain.scan(static_cast<uint64_t>(frame), [](uint64_t tick) {
            for (const auto& event:combatEvents) if(event.tick<=tick && tick-event.tick<=2)
                state.terrain.hintBlock(event.pos.x()>>4,event.pos.y()>>4,event.pos.z());
        });
        track(usSince(ts), state.scanUsLast, state.scanUsEma, state.scanUsMax);
    }
    // Retire appearance entries of units the walk no longer sees (bounded
    // per update). Runs before the walk so no entry pointer collected by
    // buildUnits for this publication is erased underneath it.
    state.appearance.evicted += df3d_appearance_eviction::evict(state.appearance.evictionRing, state.appearance.units, frame);

    // A newly attached viewer must receive its requested entity Full even
    // while paused. Keep the actual DF tick: bootstrap is not a sim advance.
    const bool entityRefresh = state.entityFullPending ||
        shm::atomicLoadAcquire(&state.region->entityFullRequest) != state.entityFullServed;
    if (!state.havePublished || frame != state.lastFrame || entityRefresh || state.commandPublicationPending) {
        const auto tp = Clock::now();
        buildAndPublishSnapshot(out, frame);
        track(usSince(tp), state.publishUsLast, state.publishUsEma, state.publishUsMax);
    }
    ++state.updates;
    track(usSince(t0), state.updateUsLast, state.updateUsEma, state.updateUsMax);
    return CR_OK;
}
