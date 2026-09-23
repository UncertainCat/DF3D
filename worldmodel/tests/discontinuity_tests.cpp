// Tier 0: discontinuity classification — classified, not smoothed away.
#include <doctest.h>

#include "wm/discontinuity.h"

using namespace wm;

namespace {
Keyframe kf(Tick tick, int32_t x, int32_t y, int32_t z) {
  return Keyframe{tick, TilePos{x, y, z}, JobKind::Idle};
}
}  // namespace

TEST_CASE("same position is Hold") {
  CHECK(classifySegment(kf(10, 5, 5, 0), kf(11, 5, 5, 0)) == SegmentKind::Hold);
}

TEST_CASE("single-tile steps are Continuous, including diagonals") {
  CHECK(classifySegment(kf(10, 5, 5, 0), kf(11, 6, 5, 0)) == SegmentKind::Continuous);
  CHECK(classifySegment(kf(10, 5, 5, 0), kf(11, 4, 4, 0)) == SegmentKind::Continuous);
  CHECK(classifySegment(kf(10, 5, 5, 0), kf(11, 6, 6, 0)) == SegmentKind::Continuous);
}

TEST_CASE("multi-tile walk across a small snapshot gap is Continuous") {
  // 3 tiles in 3 ticks: ordinary walking observed sparsely.
  CHECK(classifySegment(kf(10, 5, 5, 0), kf(13, 8, 5, 0)) == SegmentKind::Continuous);
}

TEST_CASE("moving faster than one tile per tick is Teleport") {
  CHECK(classifySegment(kf(10, 5, 5, 0), kf(11, 7, 5, 0)) == SegmentKind::Teleport);
  CHECK(classifySegment(kf(10, 5, 5, 0), kf(12, 20, 20, 0)) == SegmentKind::Teleport);
}

TEST_CASE("one z-level step is ZTransition (stairs/ramps)") {
  CHECK(classifySegment(kf(10, 5, 5, 3), kf(11, 5, 6, 4)) == SegmentKind::ZTransition);
  CHECK(classifySegment(kf(10, 5, 5, 3), kf(11, 5, 5, 2)) == SegmentKind::ZTransition);
}

TEST_CASE("multi-z descent in place is Fall") {
  CHECK(classifySegment(kf(10, 5, 5, 8), kf(11, 5, 5, 3)) == SegmentKind::Fall);
  CHECK(classifySegment(kf(10, 5, 5, 8), kf(11, 6, 5, 6)) == SegmentKind::Fall);
}

TEST_CASE("multi-z ascent is Teleport, not a fall upward") {
  CHECK(classifySegment(kf(10, 5, 5, 3), kf(11, 5, 5, 8)) == SegmentKind::Teleport);
}

TEST_CASE("gap beyond maxContinuousGap is Teleport even for adjacent tiles") {
  ClassifierConfig cfg{.maxContinuousGap = 4};
  CHECK(classifySegment(kf(10, 5, 5, 0), kf(15, 6, 5, 0), cfg) == SegmentKind::Teleport);
  CHECK(classifySegment(kf(10, 5, 5, 0), kf(14, 6, 5, 0), cfg) == SegmentKind::Continuous);
}

TEST_CASE("malformed zero/negative tick gap is Teleport") {
  CHECK(classifySegment(kf(10, 5, 5, 0), kf(10, 6, 5, 0)) == SegmentKind::Teleport);
  CHECK(classifySegment(kf(10, 5, 5, 0), kf(9, 6, 5, 0)) == SegmentKind::Teleport);
}

TEST_CASE("diagonal move with z-step within gap budget is ZTransition") {
  CHECK(classifySegment(kf(10, 5, 5, 3), kf(12, 7, 6, 4)) == SegmentKind::ZTransition);
}
