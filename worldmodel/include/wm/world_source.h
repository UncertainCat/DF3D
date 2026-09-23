#pragma once
#include "wm/buffered_world_client.h"

namespace wm {

// Owns source replacement, frame adoption and retirement. No engine resources.
// Callers supply time in the same clock domain as BufferedWorldConfig::clock.
class WorldSource {
 public:
  explicit WorldSource(WorldModelConfig config = {});
  ~WorldSource();
  WorldSource(const WorldSource&) = delete;
  WorldSource& operator=(const WorldSource&) = delete;

  bool attach(BufferedWorldConfig config, const std::string& regionName = {});
  void detachLive();
  bool loadFixture(const std::string& path, double now);
  struct Update { bool available = false; bool changed = false; double renderTick = 0; };
  Update poll(double now);
  bool setFixedTick(double tick);
  void setReplaySpeed(double speed) { replaySpeed_ = speed; }
  void setReplayElapsed(double seconds) { replayElapsed_ = seconds; }

  WorldModel& model() { return model_; }
  const WorldModel& model() const { return model_; }
  bool attached() const { return client_ || replay_; }
  bool live() const { return bool(client_); }
  BufferedWorldStats liveStats() const { return client_ ? client_->stats() : BufferedWorldStats{}; }
  uint64_t sendSetPause(bool paused);
  uint64_t sendDesignateDig(const TileRect&, DigKind, uint8_t priority = kDefaultDigPriority, bool marker = false, uint8_t mining_mode = 0, int32_t max_z = -1);
  uint64_t sendDesignateSmooth(const TileRect&, SmoothKind, uint8_t priority = kDefaultDigPriority, bool marker = false, bool from_east = false, bool from_south = false, int32_t max_z = -1, int32_t track_end_z = -1);
  uint64_t sendDesignateChop(const TileRect&, bool enable, uint8_t priority = kDefaultDigPriority, bool marker = false, int32_t max_z = -1);
  uint64_t sendDesignateGather(const TileRect&, bool enable, uint8_t priority = kDefaultDigPriority, bool marker = false, int32_t max_z = -1);
  uint64_t sendSetItemFlags(ItemId, OptionalBool forbidden, OptionalBool dump, OptionalBool melt);
  uint64_t sendSetBuildingFlags(BuildingId, OptionalBool forbidden);
  const std::string& error() const { return error_; }
  const std::string& name() const { return name_; }
  size_t fixtureSnapshots() const { return replay_ ? replay_->snapshotCount() : 0; }
  double delaySeconds() const { return delay_; }
  double displayedCapturedAt() const { return displayedCapturedAt_; }

 private:
  void fail(const std::string& error);
  // The worker is joined before the adopted model is destroyed.
  WorldModel model_;
  std::unique_ptr<BufferedWorldClient> client_;
  std::unique_ptr<FixtureReplay> replay_;
  double delay_ = .100, displayedCapturedAt_ = 0;
  double replayStart_ = 0, replaySpeed_ = 1, replayElapsed_ = -1, fixedTick_ = -1;
  std::string error_, name_;
};
} // namespace wm
