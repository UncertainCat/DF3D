#include "wm/discontinuity.h"

#include <algorithm>
#include <cstdlib>

namespace wm {

const char* segmentKindName(SegmentKind kind) {
  switch (kind) {
    case SegmentKind::Hold: return "Hold";
    case SegmentKind::Continuous: return "Continuous";
    case SegmentKind::ZTransition: return "ZTransition";
    case SegmentKind::Fall: return "Fall";
    case SegmentKind::Teleport: return "Teleport";
  }
  return "?";
}

SegmentKind classifySegment(const Keyframe& a, const Keyframe& b,
                            const ClassifierConfig& cfg) {
  const Tick from = std::max(a.heldUntil, a.tick);
  const Tick g = b.tick > from ? b.tick - from : 0;
  if (g == 0 || g > cfg.maxContinuousGap) return SegmentKind::Teleport;
  if (a.pos == b.pos) return SegmentKind::Hold;

  const int64_t dx = std::abs(int64_t{b.pos.x} - a.pos.x);
  const int64_t dy = std::abs(int64_t{b.pos.y} - a.pos.y);
  const int64_t dz = int64_t{b.pos.z} - a.pos.z;
  const int64_t dxy = std::max(dx, dy);
  const auto gap = static_cast<int64_t>(g);

  if (dz <= -2 && dxy <= 1) return SegmentKind::Fall;
  if (dxy <= gap && dz != 0 && std::abs(dz) <= gap) return SegmentKind::ZTransition;
  if (dxy <= gap && dz == 0) return SegmentKind::Continuous;
  return SegmentKind::Teleport;
}

}  // namespace wm
