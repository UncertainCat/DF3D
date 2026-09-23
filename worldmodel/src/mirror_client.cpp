#include "wm/mirror_client.h"

#ifdef _WIN32

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <vector>

#include "command_util.h"
#include "entity_sync.h"
#include "entity_util.h"
#include "shm_layout.h"
#include "publication_clock.h"
#include "client_mailbox.h"
#include "snapshot_convert.h"
#include "terrain_grid_sync.h"
#include "validate.h"

namespace wm {

namespace m = df3d::mirror;
namespace shm = df3d::shm;

struct MirrorClient::Impl {
  HANDLE mapping = nullptr;
  shm::CommandWriter writer;
  shm::RegionHeader* region = nullptr;
  std::vector<uint8_t> scratch;
  shm::SnapshotPublication publication;
  PublicationStats publicationStats;
  PublicationStats capturedStats;
  CaptureDiagnostics captureInfo;
  CapturedSnapshot latestCapture;
  bool captureEpochObserved = false;
  bool clockAligned = false;
  double sourceClockOffset = 0;
  uint64_t captureEpoch = 0;
  shm::SnapshotPublication capturedPublication;

  // Terrain grid.
  HANDLE terrainMapping = nullptr;
  shm::TerrainHeader* terrain = nullptr;
  uint64_t sessionEpoch = 0;
  bool epochObserved = false;
  uint64_t terrainEpoch = 0;     // epoch of the attached grid (0 = none)
  bool terrainSynced = false;    // a Full from this epoch has been ingested
  uint64_t terrainFloorTick = 0; // grid tick the Full was current to
  detail::GridScratch scratchGrid;  // outlives each poll's SnapshotData

  // Entity tables.
  detail::EntitySyncState entities;
  uint64_t entityRequests = 0;

  void requestEntityFull() {
    shm::requestEntityFull(region);
    ++entityRequests;
  }

  void detachTerrain() {
    if (terrain) UnmapViewOfFile(terrain);
    if (terrainMapping) CloseHandle(terrainMapping);
    terrain = nullptr;
    terrainMapping = nullptr;
    terrainEpoch = 0;
    terrainSynced = false;
    terrainFloorTick = 0;
  }

  // Maps the grid for `epoch`; nullptr on success, else a static message.
  const char* attachTerrain(uint64_t epoch) {
    detachTerrain();
    char name[64];
    shm::terrainRegionName(epoch, name, sizeof(name));
    terrainMapping = OpenFileMappingA(FILE_MAP_READ, FALSE, name);
    if (!terrainMapping) return "terrain grid mapping not found";
    void* view = MapViewOfFile(terrainMapping, FILE_MAP_READ, 0, 0, 0);
    if (!view) {
      CloseHandle(terrainMapping);
      terrainMapping = nullptr;
      return "MapViewOfFile(terrain) failed";
    }
    terrain = static_cast<shm::TerrainHeader*>(view);
    if (const char* err = shm::checkTerrain(terrain, static_cast<uint32_t>(m::SchemaVersion::Current))) {
      detachTerrain();
      return err;
    }
    if (terrain->epoch != epoch) {
      detachTerrain();
      return "terrain grid epoch mismatch";
    }
    terrainEpoch = epoch;
    return nullptr;
  }

  ~Impl() {
    detachTerrain();
    if (region) UnmapViewOfFile(region);
    if (mapping) CloseHandle(mapping);
  }
};

namespace {

void stripTerrain(SnapshotData& data) {
  data.terrainScope = TerrainScope::None;
  data.blocks.clear();
  data.tileStorage.clear();
}

}  // namespace

MirrorClient::MirrorClient() : impl_(new Impl) {}
MirrorClient::~MirrorClient() = default;

std::unique_ptr<MirrorClient> MirrorClient::open(std::string& error, const std::string& regionName, OpenMode mode) {
  std::unique_ptr<MirrorClient> c(new MirrorClient());
  c->impl_->mapping =
      OpenFileMappingA(FILE_MAP_ALL_ACCESS, FALSE, regionName.empty() ? shm::kDefaultRegionName : regionName.c_str());
  if (!c->impl_->mapping) {
    error = "mirror region not found (is DF running with the df3d bridge and a map loaded?)";
    return nullptr;
  }
  void* view = MapViewOfFile(c->impl_->mapping, FILE_MAP_ALL_ACCESS, 0, 0, 0);
  if (!view) {
    error = "MapViewOfFile failed, error " + std::to_string(GetLastError());
    return nullptr;
  }
  c->impl_->region = static_cast<shm::RegionHeader*>(view);
  if (const char* err = shm::checkRegion(
          c->impl_->region, static_cast<uint32_t>(m::SchemaVersion::Current))) {
    error = err;
    return nullptr;
  }
  if(mode != OpenMode::Capture && !c->impl_->writer.open(regionName.empty()?shm::kDefaultRegionName:regionName)){error="Cannot open mirror command writer";return nullptr;}
  // Ask for the buildings / items base state right away; poll() keeps
  // asking until both Fulls have been seen.
  if (mode == OpenMode::Ingest) c->impl_->requestEntityFull();
  return c;
}

// Applies the stream rule to the entity tables of a ring snapshot
// and re-requests a Full whenever the filter says the model is not (or no
// longer) in sync with the bridge.
void MirrorClient::syncEntities(SnapshotData& data) {
  Impl& im = *impl_;
  if (detail::filterEntities(data, im.entities, m::kEntityRepeatFrames)) im.requestEntityFull();
}

// Replaces `data`'s terrain payload according to the grid state: a Full
// synthesized from the grid on the first poll of an epoch, nothing while
// the grid is unavailable or the ring snapshot predates the grid, the ring
// Delta as-is otherwise.
void MirrorClient::syncTerrain(SnapshotData& data) {
  Impl& im = *impl_;
  const uint64_t epoch = shm::atomicLoadAcquire(&im.region->terrainEpoch);
  if (epoch == 0) {  // bridge has no grid (yet)
    im.detachTerrain();
    stripTerrain(data);
    return;
  }
  if (epoch != im.terrainEpoch) {
    if (const char* err = im.attachTerrain(epoch)) {
      lastError_ = std::string("terrain grid unavailable: ") + err;
      stripTerrain(data);
      return;
    }
  }
  if (im.terrainSynced) {
    // Deltas not newer than the grid state are already folded into the
    // Full we ingested; re-applying one could roll a block back.
    if (data.terrainScope != TerrainScope::None && data.tick <= im.terrainFloorTick)
      stripTerrain(data);
    return;
  }

  // Synthesize the Full. The ring snapshot's own terrain (if any) is at
  // most as new as the grid (the bridge updates the grid before publishing
  // the ring), so it is dropped in favour of the grid.
  stripTerrain(data);
  uint64_t gridTick = 0;
  std::string err;
  if (!detail::synthesizeFullFromGrid(im.terrain, im.scratchGrid, data, gridTick, err)) {
    if (!err.empty()) lastError_ = err;
    stripTerrain(data);  // torn or mismatched; the next poll retries
    return;
  }
  im.terrainSynced = true;
  im.terrainFloorTick = gridTick;
}

bool MirrorClient::capture(CapturedSnapshot& out, double wallSeconds) {
  auto* region = impl_->region;
  if (!impl_->clockAligned) {
    impl_->sourceClockOffset = wallSeconds - double(shm::publicationClockMicros()) / 1e6;
    impl_->clockAligned = true;
  }
  const uint64_t epoch = shm::atomicLoadAcquire(&region->terrainEpoch);
  const bool epochChanged = !impl_->captureEpochObserved || epoch != impl_->captureEpoch;
  if (epochChanged) {
    impl_->captureEpochObserved = true;
    impl_->captureEpoch = epoch;
    impl_->capturedPublication = {};
    impl_->capturedStats.resetBaseline();
    impl_->captureInfo = {};
    // Publish the lifecycle change even if the new map has no snapshot yet.
    out = {};
    out.epoch = epoch;
    out.wallSeconds = wallSeconds;
  }
  if (!epoch) return epochChanged;
  const uint64_t latestIndex = shm::atomicLoadAcquire(&region->publicationIndex);
  if (latestIndex && latestIndex == impl_->capturedPublication.index) return false;
  shm::SnapshotPublication publication;
  if (impl_->scratch.empty()) impl_->scratch.resize(region->snapshotCapacity);
  const size_t len = shm::readNextSnapshot(region, impl_->capturedPublication.index,
      impl_->scratch.data(), impl_->scratch.size(), 16, &publication);
  if (publication.latestIndex) {
    impl_->captureInfo.retainedPublications = publication.latestIndex >= publication.oldestRetainedIndex
        ? publication.latestIndex - publication.oldestRetainedIndex + 1 : 0;
    const auto received = len ? publication.index : impl_->capturedPublication.index;
    impl_->captureInfo.pendingPublications = publication.latestIndex > received ? publication.latestIndex - received : 0;
  }
  if (!len) {
    impl_->captureInfo.pendingPublications = latestIndex > impl_->capturedPublication.index
        ? latestIndex - impl_->capturedPublication.index : 0;
    if (latestIndex > impl_->capturedPublication.index) ++impl_->capturedStats.readFailures;
    return epochChanged;
  }
  if (shm::atomicLoadAcquire(&region->terrainEpoch) != epoch) return false;
  // Only transport verification runs here; semantic conversion belongs to ingestion.
  flatbuffers::Verifier v(impl_->scratch.data(), len);
  if (!m::VerifySizePrefixedSnapshotBuffer(v)) {
    ++impl_->capturedStats.rejected;
    lastError_ = "live snapshot failed FlatBuffers verification";
    return epochChanged;
  }
  const uint64_t tick = m::GetSizePrefixedSnapshot(impl_->scratch.data())->tick();
  // Journal entries own their tick. The live heartbeat may already describe
  // a later publication by the time this coherent copy finishes verification.
  if (tick != publication.tick || (!region->journalCapacity && !impl_->capturedPublication.index &&
      tick != shm::atomicLoadAcquire(&region->bridgeTick))) {
    ++impl_->capturedStats.rejected; return epochChanged;
  }
  out.epoch = epoch;
  out.tick = m::GetSizePrefixedSnapshot(impl_->scratch.data())->tick();
  out.index = publication.index;
  out.slot = publication.slot;
  out.sequence = publication.sequence;
  out.wallSeconds = wallSeconds;
  out.timestamped = publication.timestampMicros != 0;
  out.sourceWallSeconds = out.timestamped
      ? double(publication.timestampMicros) / 1e6 + impl_->sourceClockOffset : wallSeconds;
  impl_->captureInfo.sourceAgeMilliseconds = std::max(0.0, (wallSeconds - out.sourceWallSeconds) * 1000);
  out.bytes.assign(impl_->scratch.begin(), impl_->scratch.begin() + len);
  impl_->capturedPublication = publication;
  impl_->capturedStats.accept(publication.index);
  lastError_.clear();
  return true;
}

PublicationStats MirrorClient::captureStats() const { return impl_->capturedStats; }
MirrorClient::CaptureDiagnostics MirrorClient::captureDiagnostics() const { return impl_->captureInfo; }

void MirrorClient::requestRecovery() {
  impl_->terrainSynced = false;
  impl_->entities.buildingsNeedFull = true;
  impl_->entities.itemsNeedFull = true;
  impl_->requestEntityFull();
}

bool MirrorClient::poll(WorldModel& model, double wallSeconds) {
  capture(impl_->latestCapture, wallSeconds);
  return ingestCaptured(model, impl_->latestCapture);
}

bool MirrorClient::ingestCaptured(WorldModel& model, const CapturedSnapshot& captured) {
  shm::RegionHeader* region = impl_->region;
  const uint64_t epoch = captured.epoch;
  if (shm::atomicLoadAcquire(&region->terrainEpoch) != epoch) return false;
  const uint64_t tick = captured.tick;
  const double wallSeconds = captured.timestamped ? captured.sourceWallSeconds : captured.wallSeconds;
  bool reset = false;
  if (!impl_->epochObserved || epoch != impl_->sessionEpoch) {
    reset = impl_->epochObserved || model.hasData();
    impl_->epochObserved = true;
    impl_->sessionEpoch = epoch;
    impl_->detachTerrain();
    impl_->entities.reset();
    impl_->publication = {};
    impl_->publicationStats.resetBaseline();
    lastIngestedTick_ = 0;
    if (reset) model.resetSession();
  }
  // Epoch zero explicitly means unloaded/initializing. Do not re-ingest
  // the previous map's snapshot, which remains in the double buffer.
  // Tick zero is valid for a freshly loaded paused fort. Empty publication
  // slots distinguish no snapshot from that first frame.
  if (epoch == 0) return reset;
  const bool retryTerrain = model.config().ingestTerrain && !impl_->terrainSynced;
  const bool retryEntities = !impl_->entities.buildingsSynced || !impl_->entities.itemsSynced ||
      impl_->entities.buildingsNeedFull || impl_->entities.itemsNeedFull;
  if (captured.bytes.empty()) return reset;
  const shm::SnapshotPublication publication{captured.slot, captured.sequence, captured.index};
  if (tick == lastIngestedTick_ && publication.index == impl_->publication.index && !retryTerrain && !retryEntities)
    return reset;
  flatbuffers::Verifier v(captured.bytes.data(), captured.bytes.size());
  if (!m::VerifySizePrefixedSnapshotBuffer(v)) {
    ++impl_->publicationStats.rejected;
    lastError_ = "captured snapshot failed FlatBuffers verification";
    return reset;
  }
  const m::Snapshot* snap = m::GetSizePrefixedSnapshot(captured.bytes.data());
  if (auto verr = m::validateSnapshot(*snap)) {
    ++impl_->publicationStats.rejected;
    lastError_ = "live snapshot failed validation: " + *verr;
    return reset;
  }
  if (lastIngestedTick_ && snap->tick() < lastIngestedTick_) {
    model.resetSession();
    impl_->entities.reset();
    impl_->terrainSynced = false;
  } else if (lastIngestedTick_ && snap->tick() > lastIngestedTick_ &&
             snap->tick() - lastIngestedTick_ > m::kEntityRepeatFrames) {
    impl_->terrainSynced = false;
  }
  if (impl_->publication.index && publication.index > impl_->publication.index + 1)
    requestRecovery();
  lastError_.clear();
  SnapshotData data = detail::toSnapshotData(*snap, model.config().ingestTerrain);
  // Paused edits share the last ingested tick even when the initial grid Full
  // came from an earlier running frame. Refresh all authoritative grid blocks:
  // the command's bounded Delta can omit spill blocks with no later sim frame
  // to deliver them. Older queued running Deltas are already covered by the
  // grid Full and stay stripped by syncTerrain without rebuilding that Full.
  const bool newPublication = publication.index != impl_->publication.index;
  if (newPublication && impl_->publication.sequence && impl_->terrainSynced &&
      data.terrainScope != TerrainScope::None && !data.blocks.empty() &&
      data.tick == lastIngestedTick_)
    impl_->terrainSynced = false;
  if (model.config().ingestTerrain) syncTerrain(data);
  if (shm::atomicLoadAcquire(&region->terrainEpoch) != epoch) return reset;
  syncEntities(data);
  model.ingest(data, wallSeconds);
  commandEpoch_ = epoch;
  lastIngestedTick_ = snap->tick();
  impl_->publication = publication;
  impl_->publicationStats.accept(publication.index);
  return true;
}

// --- commands ---

namespace {
m::TileRect toRect(const TileRect& r) { return m::TileRect(r.x1, r.y1, r.x2, r.y2, r.z); }
}  // namespace

// Validates the command with the schema validator (no map size: the
// bridge checks the live map), then pushes it. Returns the seq or 0.
uint64_t MirrorClient::sendBytes(const std::vector<uint8_t>& bytes) {
  if (!commandEpoch_ || shm::atomicLoadAcquire(&impl_->region->terrainEpoch) != commandEpoch_) {
    lastError_ = "displayed world is unavailable or changed; command was not sent";
    return 0;
  }
  const m::Command* cmd = m::parseCommand(bytes.data(), bytes.size());
  if (!cmd) {
    lastError_ = "command failed to build";
    return 0;
  }
  if (auto err = m::validateCommand(*cmd, nullptr)) {
    lastError_ = "command rejected before send: " + *err;
    return 0;
  }
  if (!impl_->writer.push(impl_->region, bytes.data(), static_cast<uint32_t>(bytes.size()))) {
    lastError_ = "command ring full";
    return 0;
  }
  return cmd->seq();
}

uint64_t MirrorClient::sendSetPause(bool paused) {
  const uint64_t seq = shm::nextCommandSequence(impl_->region);
  const uint64_t sent = sendBytes(m::buildSetPauseCommand(seq, paused, commandEpoch_));
  if (sent) commandSeq_ = seq;
  return sent;
}

uint64_t MirrorClient::sendDesignateDig(const TileRect& rect, DigKind kind, uint8_t priority, bool marker, uint8_t mining_mode, int32_t max_z) {
  const uint64_t seq = shm::nextCommandSequence(impl_->region);
  const uint64_t sent = sendBytes(m::buildDesignateDigCommand(
      seq, toRect(rect), static_cast<m::DigKind>(static_cast<uint8_t>(kind)), priority, marker, mining_mode, max_z, commandEpoch_));
  if (sent) commandSeq_ = seq;
  return sent;
}

uint64_t MirrorClient::sendDesignateSmooth(const TileRect& rect, SmoothKind kind, uint8_t priority, bool marker, bool from_east, bool from_south, int32_t max_z, int32_t track_end_z) {
  const uint64_t seq = shm::nextCommandSequence(impl_->region);
  const uint64_t sent = sendBytes(m::buildDesignateSmoothCommand(
      seq, toRect(rect), static_cast<m::SmoothKind>(static_cast<uint8_t>(kind)), priority, marker, from_east, from_south, max_z, track_end_z, commandEpoch_));
  if (sent) commandSeq_ = seq;
  return sent;
}

uint64_t MirrorClient::sendDesignateChop(const TileRect& rect, bool enable, uint8_t priority, bool marker, int32_t max_z) {
  const uint64_t seq = shm::nextCommandSequence(impl_->region);
  const uint64_t sent = sendBytes(m::buildDesignateChopCommand(seq, toRect(rect), enable, priority, marker, max_z, commandEpoch_));
  if (sent) commandSeq_ = seq;
  return sent;
}

uint64_t MirrorClient::sendDesignateGather(const TileRect& rect, bool enable, uint8_t priority, bool marker, int32_t max_z) {
  const uint64_t seq = shm::nextCommandSequence(impl_->region);
  const uint64_t sent = sendBytes(m::buildDesignateGatherCommand(seq, toRect(rect), enable, priority, marker, max_z, commandEpoch_));
  if (sent) commandSeq_ = seq;
  return sent;
}

uint64_t MirrorClient::sendSetItemFlags(ItemId item, OptionalBool forbidden, OptionalBool dump,
                                        OptionalBool melt) {
  const uint64_t seq = shm::nextCommandSequence(impl_->region);
  const auto ob = [](OptionalBool v) { return static_cast<m::OptionalBool>(static_cast<uint8_t>(v)); };
  const uint64_t sent =
      sendBytes(m::buildSetItemFlagsCommand(seq, item, ob(forbidden), ob(dump), ob(melt), commandEpoch_));
  if (sent) commandSeq_ = seq;
  return sent;
}

uint64_t MirrorClient::sendSetBuildingFlags(BuildingId building, OptionalBool forbidden) {
  const uint64_t seq = shm::nextCommandSequence(impl_->region);
  const uint64_t sent = sendBytes(m::buildSetBuildingFlagsCommand(
      seq, building, static_cast<m::OptionalBool>(static_cast<uint8_t>(forbidden)), commandEpoch_));
  if (sent) commandSeq_ = seq;
  return sent;
}

PublicationStats MirrorClient::publicationStats() const {
  auto result = impl_->publicationStats;
  // A synchronous poll client owns both stages. A dedicated ingest client
  // never captures, so these additions are zero in the buffered pipeline.
  result.readFailures += impl_->capturedStats.readFailures;
  result.rejected += impl_->capturedStats.rejected;
  return result;
}

uint64_t MirrorClient::bridgeTick() const {
  return shm::atomicLoadAcquire(&impl_->region->bridgeTick);
}

uint64_t MirrorClient::terrainEpoch() const {
  return shm::atomicLoadAcquire(&impl_->region->terrainEpoch);
}

bool MirrorClient::terrainSynced() const { return impl_->terrainSynced; }

uint64_t MirrorClient::terrainGridTick() const { return impl_->terrainFloorTick; }

bool MirrorClient::buildingsSynced() const { return impl_->entities.buildingsSynced; }
bool MirrorClient::itemsSynced() const { return impl_->entities.itemsSynced; }
uint64_t MirrorClient::entityFullRequests() const { return impl_->entityRequests; }

}  // namespace wm

#else
#error "MirrorClient is Windows-only for now (bridge host platform)"
#endif
