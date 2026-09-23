#include "wm/sim_clock.h"

#include <algorithm>
#include <cassert>

namespace wm {

void SimClockEstimator::observe(Tick tick, double wallSeconds) {
  if (!obs_.empty() && wallSeconds <= obs_.back().first) return;
  obs_.emplace_back(wallSeconds, tick);
  while (obs_.size() > static_cast<size_t>(std::max(2, cfg_.window))) obs_.pop_front();
}

double SimClockEstimator::ticksPerSecond() const {
  if (obs_.size() < 2) return 0.0;
  const auto& [w0, t0] = obs_.front();
  const auto& [w1, t1] = obs_.back();
  const double dw = w1 - w0;
  if (dw <= 0.0 || t1 <= t0) return 0.0;
  return static_cast<double>(t1 - t0) / dw;
}

double SimClockEstimator::estimate(double wallSeconds) const {
  assert(hasObservations());
  const auto& [lastWall, lastTick] = obs_.back();
  const double dt = std::max(0.0, wallSeconds - lastWall);
  const double advance = std::min(dt * ticksPerSecond(), cfg_.maxExtrapolationTicks);
  return static_cast<double>(lastTick) + advance;
}

}  // namespace wm
