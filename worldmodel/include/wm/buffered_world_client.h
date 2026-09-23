#pragma once

#include <functional>
#include <memory>
#include <string>
#include "wm/mirror_client.h"

namespace wm {

struct BufferedWorldConfig {
  WorldModelConfig model;
  // Seed a replacement worker above the last identity exposed by its owner.
  uint64_t initialGeneration = 0;
  double delaySeconds = 0.100;
  double pollIntervalSeconds = 0.004;
  double publishIntervalSeconds = 1.0 / 60.0;
  size_t maxFrames = 16;
  // Allow capture bursts and brief parser stalls; the 64 MiB byte bound still applies.
  size_t maxPendingSnapshots = 512;
  size_t maxPendingBytes = 64 * 1024 * 1024;
  // Diagnostic timings are opt-in; simulation/publication clocks still run.
  bool collectTimings = false;
  // Optional diagnostic observer: stage, steady-clock start/duration in us.
  // Called on the ingestion worker only when collectTimings is enabled.
  std::function<void(const char*, double, double)> timingObserver;
  // Thread-safe clock, shared by capture/processing workers and takeReady caller.
  std::function<double()> clock;
};

struct BufferedWorldStats {
  PublicationStats sourcePublications; // successfully ingested publications
  MirrorClient::CaptureDiagnostics captureDiagnostics;
  PublicationStats capturedPublications; // transport receipts, before model work
  size_t pendingSnapshots = 0, pendingBytes = 0;
  size_t peakPendingSnapshots = 0, peakPendingBytes = 0;
  uint64_t captureQueueDrops = 0;
  double captureMilliseconds = 0;
  // Lifetime maxima; intervals use the injected clock and include scheduling.
  double capturePollIntervalMaxMs = 0, captureMissPollIntervalMaxMs = 0;
  uint64_t publicationBackpressure = 0;
  double retirementMilliseconds = 0;
  uint64_t published = 0;
  uint64_t coalesced = 0;
  uint64_t generation = 0;
  uint64_t bridgeTick = 0;
  uint64_t terrainEpoch = 0;
  uint64_t terrainGridTick = 0;
  uint64_t entityFullRequests = 0;
  bool terrainSynced = false;
  bool buildingsSynced = false;
  bool itemsSynced = false;
  size_t queuedFrames = 0;
  // Cumulative worker timings, suitable for interval deltas.
  double pollMilliseconds = 0;
  double publicationMilliseconds = 0;
  std::string error;
};

struct BufferedWorldFrame {
  uint64_t sequence = 0;
  uint64_t sourceEpoch = 0;
  uint64_t generation = 0;
  double capturedAt = 0;
  double sourceAt = 0;
  double releaseAt = 0;
  std::unique_ptr<WorldModel> model;
};

// Dedicated transport collector, ordered model worker and model reclamation.
// Bounded input, presentation and retired-model queues. Commands bypass the delay and never wait for ingestion/publication.
class BufferedWorldClient {
 public:
  static std::unique_ptr<BufferedWorldClient> open(BufferedWorldConfig config,
      std::string& error, const std::string& regionName = {});
  ~BufferedWorldClient();
  BufferedWorldClient(const BufferedWorldClient&) = delete;
  BufferedWorldClient& operator=(const BufferedWorldClient&) = delete;
  void stop();
  // Newest completed eligible state. Skipped notifications are preserved in
  // the returned model's existing drain APIs. Epoch resets bypass the delay.
  std::unique_ptr<BufferedWorldFrame> takeReady(double wallSeconds);
  BufferedWorldStats stats() const;
  // Return a superseded presentation model for destruction by the worker.
  // Call before stop(); ownership transfer itself does not destroy the model.
  void retire(std::unique_ptr<WorldModel> model);
  uint64_t sendSetPause(bool paused);
  uint64_t sendDesignateDig(const TileRect&, DigKind, uint8_t priority = kDefaultDigPriority, bool marker = false, uint8_t mining_mode = 0, int32_t max_z = -1);
  uint64_t sendDesignateSmooth(const TileRect&, SmoothKind, uint8_t priority = kDefaultDigPriority, bool marker = false, bool from_east = false, bool from_south = false, int32_t max_z = -1, int32_t track_end_z = -1);
  uint64_t sendDesignateChop(const TileRect&, bool enable, uint8_t priority = kDefaultDigPriority, bool marker = false, int32_t max_z = -1);
  uint64_t sendDesignateGather(const TileRect&, bool enable, uint8_t priority = kDefaultDigPriority, bool marker = false, int32_t max_z = -1);
  uint64_t sendSetItemFlags(ItemId, OptionalBool forbidden, OptionalBool dump, OptionalBool melt);
  uint64_t sendSetBuildingFlags(BuildingId, OptionalBool forbidden);
  uint64_t lastCommandSeq() const;
  std::string commandError() const;
 private:
  BufferedWorldClient();
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
} // namespace wm
