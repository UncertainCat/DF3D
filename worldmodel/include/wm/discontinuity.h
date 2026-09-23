#pragma once

#include "wm/keyframes.h"
#include "wm/types.h"

namespace wm {

enum class SegmentKind : uint8_t {
  Hold,         // no movement between the frames
  Continuous,   // ordinary walking; interpolate
  ZTransition,  // deliberate z traversal (stairs/ramps); interpolate, flagged
  Fall,         // rapid downward multi-z movement; interpolate, flagged
  Teleport,     // non-physical jump or data gap; hold, then snap — never lerp
};

const char* segmentKindName(SegmentKind kind);

struct ClassifierConfig {
  // Unobserved gaps longer than this many ticks are classified Teleport:
  // too much unobserved time to claim the motion was continuous. The gap is
  // measured from the earlier keyframe's heldUntil (last observation at
  // that position) to the later keyframe's tick, so a long hold on one
  // tile followed by an observed one-tile step is still Continuous.
  Tick maxContinuousGap = 4;
};

// Classifies the motion between two consecutive keyframes (a.tick < b.tick).
// Rules, applied in order (dxy = Chebyshev distance in x/y;
// g = b.tick - max(a.heldUntil, a.tick), the unobserved gap):
//   1. g == 0 (malformed) or g > maxContinuousGap  → Teleport
//   2. same position                               → Hold
//   3. b.z < a.z by ≥2, dxy ≤ 1                    → Fall
//   4. dxy ≤ g and |dz| ≤ g, dz ≠ 0                → ZTransition
//   5. dxy ≤ g and dz == 0                         → Continuous
//   6. anything else                               → Teleport
SegmentKind classifySegment(const Keyframe& a, const Keyframe& b,
                            const ClassifierConfig& cfg = {});

}  // namespace wm
