// Interpolation evaluation: a pure function of
// (keyframe history, render tick). No clocks, no globals, no state.
#pragma once

#include <optional>

#include "wm/discontinuity.h"
#include "wm/keyframes.h"
#include "wm/types.h"

namespace wm {

enum class Presence : uint8_t {
  NotYetSeen,  // renderTick precedes the first keyframe
  Present,
  Departed,  // unit left the mirror at or before renderTick
};

// Motion timing between change-point keyframes. DF moves a unit one tile
// at a time after it sits on the previous tile for its movement cadence;
// smooth presentation spreads that step over the cadence instead of
// snapping at arrival.
struct MotionConfig {
  // Upper bound on how many ticks before arrival a step starts animating.
  // Bounds the "creep" of a unit that idled for a long time before moving:
  // it holds, then covers the tile in at most this many ticks. Walking
  // units whose cadence is shorter than this animate over their full
  // cadence (previous arrival-to-arrival span), i.e. constant speed.
  Tick maxMoveTicks = 12;
};

struct EvalResult {
  // Semantic motion interval selected by the evaluator. Consumers may evaluate
  // the same interval on another execution device without reconstructing the
  // discontinuity/cadence rules. Holds have identical endpoints/times.
  struct MotionSpan {
    Vec3 from{}, to{};
    Tick start = 0, end = 0;
  } motion;
  Presence presence = Presence::NotYetSeen;
  // Interpolated position in tile coordinates. For Departed, the last known
  // position. Undefined for NotYetSeen.
  Vec3 pos;
  // Motion segment active at renderTick; Hold when clamped outside history.
  SegmentKind segment = SegmentKind::Hold;
  JobKind job = JobKind::Idle;
  UnitAttack attack{};
};

// Evaluates a unit's presentation state at fractional `renderTick`.
// Semantics:
//  - Empty history or renderTick < first keyframe → NotYetSeen.
//  - departedAt set and renderTick >= *departedAt → Departed, last position.
//  - renderTick >= last keyframe → Present, hold last position.
//  - Otherwise the surrounding segment is classified; Teleport holds the
//    earlier frame's position until the later frame's tick (no smoothing).
//    Everything else lerps over a move window ending at the later frame's
//    tick: min(segment span, previous step's span, maxMoveTicks). Before
//    the window the unit holds (segment reported as Hold). Job changes take
//    effect at the earlier frame.
EvalResult evaluateUnit(const KeyframeHistory& history, double renderTick,
                        std::optional<Tick> departedAt = std::nullopt,
                        const ClassifierConfig& cfg = {},
                        const MotionConfig& motion = {});

}  // namespace wm
