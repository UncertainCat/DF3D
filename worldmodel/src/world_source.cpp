#include "wm/world_source.h"
#include <filesystem>
#include <stdexcept>
#include <utility>

namespace wm {
WorldSource::WorldSource(WorldModelConfig config) : model_(config) {}
WorldSource::~WorldSource() { client_.reset(); }

bool WorldSource::attach(BufferedWorldConfig config, const std::string& regionName) {
  if (client_) return true;
  if (replay_) { error_ = "a fixture is loaded; attach() is unavailable"; return false; }
  config.model = model_.config();
  config.initialGeneration = model_.sessionGeneration() + 1;
  delay_ = config.delaySeconds;
  client_ = BufferedWorldClient::open(std::move(config), error_, regionName);
  if (!client_) return false;
  model_.resetSession();
  displayedCapturedAt_ = 0;
  error_.clear(); name_ = "live mirror";
  return true;
}

void WorldSource::detachLive() {
  if (!client_) return;
  client_.reset();
  model_.resetSession();
  displayedCapturedAt_ = 0;
  name_ = "waiting for fortress";
}

bool WorldSource::loadFixture(const std::string& path, double now) {
  if (client_) { error_ = "already attached to the live mirror"; return false; }
  // A failed open leaves the previous valid source and model together.
  auto next = FixtureReplay::open(path, error_);
  if (!next) return false;
  replay_ = std::move(next);
  model_.resetSession();
  replayStart_ = now; replayElapsed_ = -1;
  name_ = "fixture " + std::filesystem::path(path).filename().string();
  error_.clear();
  return setFixedTick(fixedTick_);
}

void WorldSource::fail(const std::string& error) {
  error_ = error;
  if (client_) client_->stop();
  replay_.reset();
}

bool WorldSource::setFixedTick(double tick) {
  fixedTick_ = tick;
  try {
    if (replay_ && fixedTick_ >= 0) replay_->stepAll(model_);
    return true;
  } catch (const std::length_error& error) { fail(error.what()); return false; }
}

WorldSource::Update WorldSource::poll(double now) {
  Update update;
  double clock = now;
  try {
    if (client_) {
      if (auto frame = client_->takeReady(now)) {
        update.changed = true;
        if (frame->generation == model_.sessionGeneration()) {
          auto pending = model_.drainAllEvents();
          pending.append(frame->model->drainAllEvents());
          frame->model->restoreEvents(std::move(pending));
        }
        std::swap(model_, *frame->model);
        client_->retire(std::move(frame->model));
        displayedCapturedAt_ = frame->capturedAt;
      }
      const auto state = client_->stats();
      if (!state.error.empty()) error_ = state.error;
      if (state.generation != model_.sessionGeneration() && model_.hasData()) model_.resetSession();
      clock = now - delay_;
    } else if (replay_) {
      clock = replay_->firstArrivalSeconds() + (replayElapsed_ >= 0 ? replayElapsed_ : (now - replayStart_) * replaySpeed_);
      update.changed = replay_->stepTo(model_, clock) != 0;
    } else return update;
  } catch (const std::length_error& error) { fail(error.what()); return update; }
  update.available = true;
  update.renderTick = fixedTick_ >= 0 ? fixedTick_ : model_.renderTickAt(clock);
  return update;
}
uint64_t WorldSource::sendSetPause(bool paused) {
  if (!client_) { error_ = "not attached to the live mirror"; return 0; }
  const auto seq = client_->sendSetPause(paused);
  if (!seq) error_ = client_->commandError();
  return seq;
}

uint64_t WorldSource::sendDesignateDig(const TileRect& rect, DigKind kind, uint8_t priority, bool marker, uint8_t mining_mode, int32_t max_z) {
  if (!client_) { error_ = "not attached to the live mirror"; return 0; }
  const auto seq = client_->sendDesignateDig(rect, kind, priority, marker, mining_mode, max_z);
  if (!seq) error_ = client_->commandError();
  return seq;
}

uint64_t WorldSource::sendDesignateSmooth(const TileRect& rect, SmoothKind kind, uint8_t priority, bool marker, bool from_east, bool from_south, int32_t max_z, int32_t track_end_z) {
  if (!client_) { error_ = "not attached to the live mirror"; return 0; }
  const auto seq = client_->sendDesignateSmooth(rect, kind, priority, marker, from_east, from_south, max_z, track_end_z);
  if (!seq) error_ = client_->commandError();
  return seq;
}

uint64_t WorldSource::sendDesignateChop(const TileRect& rect, bool enable, uint8_t priority, bool marker, int32_t max_z) {
  if (!client_) { error_ = "not attached to the live mirror"; return 0; }
  const auto seq = client_->sendDesignateChop(rect, enable, priority, marker, max_z);
  if (!seq) error_ = client_->commandError();
  return seq;
}

uint64_t WorldSource::sendDesignateGather(const TileRect& rect, bool enable, uint8_t priority, bool marker, int32_t max_z) {
  if (!client_) { error_ = "not attached to the live mirror"; return 0; }
  const auto seq = client_->sendDesignateGather(rect, enable, priority, marker, max_z);
  if (!seq) error_ = client_->commandError();
  return seq;
}

uint64_t WorldSource::sendSetItemFlags(ItemId id, OptionalBool forbidden, OptionalBool dump, OptionalBool melt) {
  if (!client_) { error_ = "not attached to the live mirror"; return 0; }
  const auto seq = client_->sendSetItemFlags(id, forbidden, dump, melt);
  if (!seq) error_ = client_->commandError();
  return seq;
}

uint64_t WorldSource::sendSetBuildingFlags(BuildingId id, OptionalBool forbidden) {
  if (!client_) { error_ = "not attached to the live mirror"; return 0; }
  const auto seq = client_->sendSetBuildingFlags(id, forbidden);
  if (!seq) error_ = client_->commandError();
  return seq;
}

} // namespace wm
