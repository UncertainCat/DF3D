// Sim-clock estimation: the sim clock is estimated from tick
// numbers stamped on snapshots, never assumed constant. Pause, slowdown, and
// speedup are normal operating conditions. No hidden clocks — callers inject
// every timestamp.
#pragma once

#include <deque>
#include <utility>

#include "wm/types.h"

namespace wm {

struct SimClockConfig {
  // Observations kept for rate estimation.
  int window = 8;
  // Cap on extrapolation past the last observation, in ticks. Bounds drift
  // during pauses and snapshot gaps.
  double maxExtrapolationTicks = 2.0;
};

// Estimates fractional sim tick as a function of wall-clock time from
// (tick, arrival time) observations. Deterministic: same observations, same
// query time → same estimate.
class SimClockEstimator {
 public:
  explicit SimClockEstimator(SimClockConfig cfg = {}) : cfg_(cfg) {}

  // Records a snapshot arrival. Observations with non-increasing wall time
  // are ignored (clock misbehavior is the caller's bug, not a crash here).
  void observe(Tick tick, double wallSeconds);

  bool hasObservations() const { return !obs_.empty(); }

  // Estimated ticks per second over the observation window; 0 while paused
  // or with fewer than two observations.
  double ticksPerSecond() const;

  // Estimated fractional tick at `wallSeconds`. Clamped to the last observed
  // tick when queried in the past, and to last tick + maxExtrapolationTicks
  // when the bridge has gone quiet. Requires hasObservations().
  double estimate(double wallSeconds) const;

 private:
  SimClockConfig cfg_;
  std::deque<std::pair<double, Tick>> obs_;  // (wallSeconds, tick), increasing wall
};

}  // namespace wm
