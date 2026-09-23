#pragma once

#include <algorithm>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "wm/world_model.h"

namespace wm {
// Lifetime counters; each attach/map epoch establishes a new baseline.
// Missed means a publication absent from accepted ingestion, not a missing DF tick.
struct PublicationStats {
    uint64_t lastIndex=0, accepted=0, missed=0, gapEvents=0, largestGap=0;
    uint64_t readFailures=0, rejected=0;
    void resetBaseline() { lastIndex=0; }
    void accept(uint64_t index) {
        if (!index || index==lastIndex) return;
        if (lastIndex && index>lastIndex+1) {
            const auto gap=index-lastIndex-1;
            missed+=gap; ++gapEvents; largestGap=std::max(largestGap,gap);
        }
        lastIndex=index; ++accepted;
    }
};

class MirrorClient {
 public:
  // Attaches to the bridge's region (created by the bridge on map load).
  // Returns nullptr and sets `error` if the region doesn't exist or fails
  // validation (bad magic / layout / schema version). The terrain grid is
  // attached lazily by poll() (it appears once the bridge finished its
  // initial scan).
  // Empty regionName uses the bridge default; custom names isolate test publishers.
  enum class OpenMode { Ingest, Capture, Commands };
  static std::unique_ptr<MirrorClient> open(std::string& error, const std::string& regionName = {},
                                          OpenMode mode = OpenMode::Ingest);

  ~MirrorClient();
  MirrorClient(const MirrorClient&) = delete;
  MirrorClient& operator=(const MirrorClient&) = delete;

  bool poll(WorldModel& model, double wallSeconds);

  // Owned transport envelope. No views into shared memory survive capture.
  struct CapturedSnapshot {
    uint64_t epoch = 0, tick = 0, index = 0, sequence = 0;
    unsigned slot = 2;
    double wallSeconds = 0; // collector receipt time
    double sourceWallSeconds = 0; // original publication time on the injected clock
    bool timestamped = false;
    std::vector<uint8_t> bytes;
  };
  // Each client has one thread owner. Use separate clients for these stages.
  // capture returns only a new publication or an epoch transition (empty bytes).
  bool capture(CapturedSnapshot& out, double wallSeconds);
  bool ingestCaptured(WorldModel& model, const CapturedSnapshot& snapshot);
  PublicationStats captureStats() const;
  struct CaptureDiagnostics {
    uint64_t pendingPublications = 0, retainedPublications = 0;
    double sourceAgeMilliseconds = 0;
  };
  CaptureDiagnostics captureDiagnostics() const;
  // A local queue overrun requires authoritative terrain/entity recovery.
  void requestRecovery();

  void setCommandEpoch(uint64_t epoch) { commandEpoch_ = epoch; }
  uint64_t sendSetPause(bool paused);
  uint64_t sendDesignateDig(const TileRect& rect, DigKind kind,
                            uint8_t priority = kDefaultDigPriority, bool marker = false, uint8_t mining_mode = 0, int32_t max_z = -1);
  uint64_t sendDesignateSmooth(const TileRect& rect, SmoothKind kind, uint8_t priority = kDefaultDigPriority, bool marker = false, bool from_east = false, bool from_south = false, int32_t max_z = -1, int32_t track_end_z = -1);
  uint64_t sendDesignateChop(const TileRect& rect, bool enable, uint8_t priority = kDefaultDigPriority, bool marker = false, int32_t max_z = -1);
  uint64_t sendDesignateGather(const TileRect& rect, bool enable, uint8_t priority = kDefaultDigPriority, bool marker = false, int32_t max_z = -1);
  uint64_t sendSetItemFlags(ItemId item, OptionalBool forbidden, OptionalBool dump,
                            OptionalBool melt);
  uint64_t sendSetBuildingFlags(BuildingId building, OptionalBool forbidden);
  // Seq of the last command sent (0 before the first).
  uint64_t lastCommandSeq() const { return commandSeq_; }

  // Last sim tick the bridge has published (heartbeat), 0 before first.
  uint64_t bridgeTick() const;
  PublicationStats publicationStats() const;

  // Terrain grid diagnostics: the epoch the bridge currently advertises
  // (0 = no grid), whether a Full from it has been ingested, and the grid
  // tick that Full was current to.
  uint64_t terrainEpoch() const;
  bool terrainSynced() const;
  uint64_t terrainGridTick() const;
  // Entity tables: whether a Full of each has been ingested from
  // the bridge since attach / the last map change.
  bool buildingsSynced() const;
  bool itemsSynced() const;
  // Number of Full requests sent to the bridge so far (diagnostics).
  uint64_t entityFullRequests() const;

  const std::string& lastError() const { return lastError_; }

 private:
  MirrorClient();
  struct Impl;
  void syncTerrain(SnapshotData& data);
  void syncEntities(SnapshotData& data);
  uint64_t sendBytes(const std::vector<uint8_t>& bytes);
  std::unique_ptr<Impl> impl_;
  std::string lastError_;
  uint64_t lastIngestedTick_ = 0;
  uint64_t commandSeq_ = 0;
  uint64_t commandEpoch_ = 0;
};

}  // namespace wm
