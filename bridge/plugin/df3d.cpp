// Keep <windows.h> (needed for CreateFileMapping) from polluting everything.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "PluginManager.h"
#include "contact_capture.h"

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
        // Active + alive only: corpses and off-map units are not part of the
        // mirrored world yet.
        if (!Units::isActive(u) || Units::isDead(u))
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
            if (!target || !Units::isActive(target) || Units::isDead(target)) continue;
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
            attackVec,df3d_contact::attacksDropped(),df3d_contact::available(),projectileCombatVec,df3d_contact::projectilesDropped(),df3d_contact::available());
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
                                    attackVec,df3d_contact::attacksDropped(),df3d_contact::available(),projectileCombatVec,df3d_contact::projectilesDropped(),df3d_contact::available());
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
