#include "wm/evaluate.h"

#include <algorithm>

namespace wm {

namespace {

Vec3 toVec3(const TilePos& p) {
  return Vec3{static_cast<float>(p.x), static_cast<float>(p.y), static_cast<float>(p.z)};
}

Vec3 lerp(const TilePos& a, const TilePos& b, double t) {
  const auto ft = static_cast<float>(t);
  return Vec3{
      static_cast<float>(a.x) + (static_cast<float>(b.x) - static_cast<float>(a.x)) * ft,
      static_cast<float>(a.y) + (static_cast<float>(b.y) - static_cast<float>(a.y)) * ft,
      static_cast<float>(a.z) + (static_cast<float>(b.z) - static_cast<float>(a.z)) * ft,
  };
}

}  // namespace

// Ticks over which the step a -> b (b = history[bi]) animates: the span of
// this step, bounded by the previous step's span (walking cadence) and the
// configured maximum. Job-only keyframes (same pos) are skipped when looking
// for the previous step.
Tick moveWindow(const KeyframeHistory& history, size_t bi, const MotionConfig& motion) {
  const Keyframe& a = history.at(bi - 1);
  const Keyframe& b = history.at(bi);
  Tick window = b.tick - a.tick;
  for (size_t k = bi - 1; k > 0; --k) {
    const Keyframe& p = history.at(k - 1);
    if (p.pos != a.pos) {
      window = std::min(window, a.tick - p.tick);
      break;
    }
    if (bi - k >= 4) break;  // bounded look-back
  }
  window = std::min(window, motion.maxMoveTicks);
  return window == 0 ? 1 : window;
}

EvalResult evaluateUnit(const KeyframeHistory& history, double renderTick,
                        std::optional<Tick> departedAt, const ClassifierConfig& cfg,
                        const MotionConfig& motion) {
  EvalResult out;
  if (history.empty()) return out;  // NotYetSeen

  if (departedAt && renderTick >= static_cast<double>(*departedAt)) {
    out.presence = Presence::Departed;
    out.pos = toVec3(history.back().pos);
    out.segment = SegmentKind::Hold;
    out.job = history.back().job;
    out.motion = {out.pos, out.pos, history.back().tick, history.back().tick};
    return out;
  }

  const Keyframe& first = history.front();
  if (renderTick < static_cast<double>(first.tick)) return out;  // NotYetSeen

  const Keyframe& last = history.back();
  if (renderTick >= static_cast<double>(last.tick)) {
    out.presence = Presence::Present;
    out.pos = toVec3(last.pos);
    out.segment = SegmentKind::Hold;
    out.job = last.job;
    out.motion = {out.pos, out.pos, last.tick, last.tick};
    return out;
  }

  // Binary search for the segment [i, i+1] with a.tick <= renderTick < b.tick.
  size_t lo = 0, hi = history.size() - 1;
  while (hi - lo > 1) {
    const size_t mid = lo + (hi - lo) / 2;
    if (static_cast<double>(history.at(mid).tick) <= renderTick) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  const Keyframe& a = history.at(lo);
  const Keyframe& b = history.at(lo + 1);

  out.presence = Presence::Present;
  out.segment = classifySegment(a, b, cfg);
  out.job = a.job;
  if (out.segment == SegmentKind::Teleport || out.segment == SegmentKind::Hold) {
    out.pos = toVec3(a.pos);  // teleport: hold until arrival; never smooth
    out.motion = {out.pos, out.pos, a.tick, a.tick};
    return out;
  }
  const Tick window = moveWindow(history, lo + 1, motion);
  const double moveStart = static_cast<double>(b.tick) - static_cast<double>(window);
  out.motion = {toVec3(a.pos), toVec3(b.pos), b.tick - window, b.tick};
  if (renderTick < moveStart) {
    out.pos = toVec3(a.pos);  // still sitting on the earlier tile
    out.segment = SegmentKind::Hold;
    return out;
  }
  const double t = (renderTick - moveStart) / static_cast<double>(window);
  out.pos = lerp(a.pos, b.pos, t);
  return out;
}

}  // namespace wm
