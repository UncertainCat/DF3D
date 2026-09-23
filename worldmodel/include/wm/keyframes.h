// Per-entity keyframe history: the input to interpolation evaluation.
#pragma once

#include <cstddef>
#include <deque>

#include "wm/types.h"

namespace wm {

// A change point in a unit's observed state: the unit arrived at `pos`
// with `job` at `tick` and was last observed unchanged at `heldUntil`
// (>= tick). Histories store change points, not every observation, so a
// segment between two keyframes spans the whole time the unit sat on the
// earlier tile - which is what constant-speed interpolation needs.
struct Keyframe {
  Tick tick = 0;
  TilePos pos;
  JobKind job = JobKind::Idle;
  Tick heldUntil = 0;  // normalized to >= tick on push
};

// Bounded history of a unit's change points, ordered by strictly increasing
// tick. Oldest frames are dropped past kMaxFrames.
class KeyframeHistory {
 public:
  static constexpr size_t kMaxFrames = 128;

  // Records an observation. A frame whose tick is <= the newest frame's tick
  // is ignored (snapshot replay/duplicate protection). A frame with the same
  // pos and job as the newest one extends that frame's heldUntil instead of
  // appending (change-point compression).
  void push(const Keyframe& kf);

  size_t size() const { return frames_.size(); }
  bool empty() const { return frames_.empty(); }
  const Keyframe& front() const { return frames_.front(); }
  const Keyframe& back() const { return frames_.back(); }
  const Keyframe& at(size_t i) const { return frames_[i]; }

 private:
  std::deque<Keyframe> frames_;
};

}  // namespace wm
