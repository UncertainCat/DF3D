// Tier 0: interpolation evaluation — a pure function of (history, render
// tick). Edge cases: teleports, tick-rate swings
// mid-interpolation, pause, entity death mid-lerp.
#include <doctest.h>
#include <algorithm>

#include "wm/evaluate.h"

using namespace wm;

namespace {
KeyframeHistory walkEastFrom(int32_t x0, Tick t0, int steps) {
  KeyframeHistory h;
  for (int i = 0; i <= steps; ++i) {
    h.push(Keyframe{t0 + static_cast<Tick>(i), TilePos{x0 + i, 4, 2}, JobKind::HaulItem});
  }
  return h;
}
}  // namespace

TEST_CASE("empty history is NotYetSeen") {
  CHECK(evaluateUnit(KeyframeHistory{}, 100.0).presence == Presence::NotYetSeen);
}

TEST_CASE("motion intervals reproduce CPU evaluation including holds and vertical travel") {
  KeyframeHistory h;
  const Tick base = 123456789;
  h.push({base, {1, 2, 3}, JobKind::Idle, base + 19});
  h.push({base + 20, {2, 2, 4}, JobKind::Idle, base + 22});
  h.push({base + 23, {2, 2, 1}, JobKind::Idle, base + 23});
  h.push({base + 24, {50, 50, 50}, JobKind::Idle, base + 24});
  for (double tick = double(base); tick < double(base + 27); tick += .125) {
    const auto evaluated = evaluateUnit(h, tick);
    const auto& span = evaluated.motion;
    const auto fraction = span.end > span.start
      ? std::clamp((tick - double(span.start)) / double(span.end - span.start), 0.0, 1.0) : 0.0;
    CHECK(span.from.x + (span.to.x - span.from.x) * fraction == doctest::Approx(evaluated.pos.x));
    CHECK(span.from.y + (span.to.y - span.from.y) * fraction == doctest::Approx(evaluated.pos.y));
    CHECK(span.from.z + (span.to.z - span.from.z) * fraction == doctest::Approx(evaluated.pos.z));
    // Shader representation retains fractional ticks even on old forts.
    const double elapsed = (double(uint64_t(tick) / 4096) - double(span.start / 4096)) * 4096
      + (tick - double(uint64_t(tick) / 4096) * 4096) - double(span.start % 4096);
    CHECK(elapsed == doctest::Approx(tick - double(span.start)));
  }
}

TEST_CASE("before the first keyframe is NotYetSeen") {
  auto h = walkEastFrom(10, 100, 3);
  CHECK(evaluateUnit(h, 99.9).presence == Presence::NotYetSeen);
  CHECK(evaluateUnit(h, 100.0).presence == Presence::Present);
}

TEST_CASE("midpoint of a continuous segment lerps") {
  auto h = walkEastFrom(10, 100, 3);
  auto r = evaluateUnit(h, 101.5);
  CHECK(r.presence == Presence::Present);
  CHECK(r.segment == SegmentKind::Continuous);
  CHECK(r.pos.x == doctest::Approx(11.5f));
  CHECK(r.pos.y == doctest::Approx(4.0f));
  CHECK(r.job == JobKind::HaulItem);
}

TEST_CASE("at and beyond the last keyframe the position holds") {
  auto h = walkEastFrom(10, 100, 3);
  for (double t : {103.0, 103.7, 500.0}) {
    auto r = evaluateUnit(h, t);
    CHECK(r.presence == Presence::Present);
    CHECK(r.segment == SegmentKind::Hold);
    CHECK(r.pos.x == doctest::Approx(13.0f));
  }
}

TEST_CASE("teleport holds the departure tile until arrival — no smoothing") {
  KeyframeHistory h;
  h.push(Keyframe{100, TilePos{5, 5, 0}, JobKind::Idle});
  h.push(Keyframe{101, TilePos{40, 40, 0}, JobKind::Idle});
  auto r = evaluateUnit(h, 100.9);
  CHECK(r.segment == SegmentKind::Teleport);
  CHECK(r.pos.x == doctest::Approx(5.0f));
  CHECK(r.pos.y == doctest::Approx(5.0f));
  // From the arrival tick on, the unit is at the destination.
  CHECK(evaluateUnit(h, 101.0).pos.x == doctest::Approx(40.0f));
}

TEST_CASE("death mid-lerp: Departed from the departure tick, last pos kept") {
  auto h = walkEastFrom(10, 100, 2);  // frames at 100,101,102
  const Tick departedAt = 102;
  auto before = evaluateUnit(h, 101.5, departedAt);
  CHECK(before.presence == Presence::Present);
  CHECK(before.pos.x == doctest::Approx(11.5f));
  auto after = evaluateUnit(h, 102.0, departedAt);
  CHECK(after.presence == Presence::Departed);
  CHECK(after.pos.x == doctest::Approx(12.0f));
  CHECK(evaluateUnit(h, 400.0, departedAt).presence == Presence::Departed);
}

TEST_CASE("pause: a frozen render tick returns an identical result") {
  auto h = walkEastFrom(10, 100, 3);
  auto a = evaluateUnit(h, 101.25);
  auto b = evaluateUnit(h, 101.25);
  CHECK(a.pos == b.pos);
  CHECK(a.segment == b.segment);
  CHECK(a.presence == b.presence);
}

TEST_CASE("tick-rate swings mid-interpolation: evaluation depends only on history") {
  // The same history evaluated at monotonically increasing render ticks
  // yields monotonic x — regardless of how wall-clock maps to those ticks.
  auto h = walkEastFrom(10, 100, 5);
  float prev = -1.0f;
  for (double t = 100.0; t <= 105.0; t += 0.173) {
    auto r = evaluateUnit(h, t);
    CHECK(r.pos.x >= prev);
    prev = r.pos.x;
  }
}

TEST_CASE("z transition lerps vertically and is flagged") {
  KeyframeHistory h;
  h.push(Keyframe{100, TilePos{5, 5, 3}, JobKind::Idle});
  h.push(Keyframe{101, TilePos{5, 6, 4}, JobKind::Idle});
  auto r = evaluateUnit(h, 100.5);
  CHECK(r.segment == SegmentKind::ZTransition);
  CHECK(r.pos.z == doctest::Approx(3.5f));
  CHECK(r.pos.y == doctest::Approx(5.5f));
}

TEST_CASE("fall lerps downward and is flagged") {
  KeyframeHistory h;
  h.push(Keyframe{100, TilePos{5, 5, 9}, JobKind::Idle});
  h.push(Keyframe{101, TilePos{5, 5, 4}, JobKind::Idle});
  auto r = evaluateUnit(h, 100.5);
  CHECK(r.segment == SegmentKind::Fall);
  CHECK(r.pos.z == doctest::Approx(6.5f));
}

TEST_CASE("job changes take effect at the segment's earlier frame") {
  KeyframeHistory h;
  h.push(Keyframe{100, TilePos{5, 5, 0}, JobKind::Mine});
  h.push(Keyframe{101, TilePos{6, 5, 0}, JobKind::Sleep});
  CHECK(evaluateUnit(h, 100.5).job == JobKind::Mine);
  CHECK(evaluateUnit(h, 101.0).job == JobKind::Sleep);
}

TEST_CASE("single keyframe: present and held from that tick onward") {
  KeyframeHistory h;
  h.push(Keyframe{100, TilePos{5, 5, 0}, JobKind::Idle});
  CHECK(evaluateUnit(h, 99.0).presence == Presence::NotYetSeen);
  auto r = evaluateUnit(h, 100.0);
  CHECK(r.presence == Presence::Present);
  CHECK(r.pos.x == doctest::Approx(5.0f));
}

TEST_CASE("history ignores non-increasing ticks and stays bounded") {
  KeyframeHistory h;
  h.push(Keyframe{100, TilePos{1, 1, 0}, JobKind::Idle});
  h.push(Keyframe{100, TilePos{9, 9, 0}, JobKind::Idle});  // dropped
  h.push(Keyframe{99, TilePos{9, 9, 0}, JobKind::Idle});   // dropped
  CHECK(h.size() == 1);
  // Distinct positions so every push is a change point.
  for (Tick t = 101; t < 101 + 500; ++t) {
    h.push(Keyframe{t, TilePos{static_cast<int32_t>(t % 7), 1, 0}, JobKind::Idle});
  }
  CHECK(h.size() == KeyframeHistory::kMaxFrames);
}

TEST_CASE("history compresses unchanged observations into heldUntil") {
  KeyframeHistory h;
  for (Tick t = 100; t <= 150; ++t) h.push(Keyframe{t, TilePos{5, 5, 0}, JobKind::Idle});
  CHECK(h.size() == 1);
  CHECK(h.back().tick == 100);
  CHECK(h.back().heldUntil == 150);
  h.push(Keyframe{151, TilePos{6, 5, 0}, JobKind::Idle});
  CHECK(h.size() == 2);
  CHECK(h.back().heldUntil == 151);
  // A job change at the same position is a change point too.
  h.push(Keyframe{152, TilePos{6, 5, 0}, JobKind::Mine});
  CHECK(h.size() == 3);
}

TEST_CASE("a long hold followed by an observed step is Continuous, not Teleport") {
  KeyframeHistory h;
  for (Tick t = 100; t <= 200; ++t) h.push(Keyframe{t, TilePos{5, 5, 0}, JobKind::Idle});
  h.push(Keyframe{201, TilePos{6, 5, 0}, JobKind::Idle});
  CHECK(classifySegment(h.at(0), h.at(1)) == SegmentKind::Continuous);
}

TEST_CASE("idle-then-step: no creep, the step animates only inside the move window") {
  MotionConfig motion{.maxMoveTicks = 12};
  KeyframeHistory h;
  for (Tick t = 100; t <= 200; ++t) h.push(Keyframe{t, TilePos{5, 5, 0}, JobKind::Idle});
  h.push(Keyframe{201, TilePos{6, 5, 0}, JobKind::Idle});
  // Sitting still for most of the segment.
  for (double t : {100.0, 150.0, 188.9}) {
    auto r = evaluateUnit(h, t, std::nullopt, {}, motion);
    CHECK(r.pos.x == doctest::Approx(5.0f));
    CHECK(r.segment == SegmentKind::Hold);
  }
  // Window is [189, 201): halfway through it the unit is halfway across.
  auto mid = evaluateUnit(h, 195.0, std::nullopt, {}, motion);
  CHECK(mid.segment == SegmentKind::Continuous);
  CHECK(mid.pos.x == doctest::Approx(5.5f));
  CHECK(evaluateUnit(h, 201.0, std::nullopt, {}, motion).pos.x == doctest::Approx(6.0f));
}

TEST_CASE("walking cadence: constant speed across the whole step") {
  // One tile every 10 ticks, observed every tick (compressed on push).
  KeyframeHistory h;
  for (int step = 0; step < 4; ++step) {
    for (Tick k = 0; k < 10; ++k) {
      h.push(Keyframe{100 + static_cast<Tick>(step * 10 + k), TilePos{10 + step, 4, 0}, JobKind::HaulItem});
    }
  }
  // Steps 1..3 have a previous step span of 10 → full-span lerp.
  CHECK(evaluateUnit(h, 115.0).pos.x == doctest::Approx(11.5f));
  CHECK(evaluateUnit(h, 122.5).pos.x == doctest::Approx(12.25f));
  // Sampling densely, no jump exceeds the constant speed of 0.1 tile/tick.
  float prev = evaluateUnit(h, 110.0).pos.x;
  for (double t = 110.25; t <= 130.0; t += 0.25) {
    float x = evaluateUnit(h, t).pos.x;
    CHECK(x - prev <= 0.1f * 0.25f + 1e-4f);
    CHECK(x >= prev);
    prev = x;
  }
}

TEST_CASE("move window is capped by maxMoveTicks even for a slow walker") {
  MotionConfig motion{.maxMoveTicks = 4};
  KeyframeHistory h;
  for (Tick t = 100; t < 120; ++t) h.push(Keyframe{t, TilePos{1, 1, 0}, JobKind::Idle});
  for (Tick t = 120; t < 140; ++t) h.push(Keyframe{t, TilePos{2, 1, 0}, JobKind::Idle});
  h.push(Keyframe{140, TilePos{3, 1, 0}, JobKind::Idle});
  // Step to x=3 arrives at 140; window [136, 140).
  CHECK(evaluateUnit(h, 135.0, std::nullopt, {}, motion).pos.x == doctest::Approx(2.0f));
  CHECK(evaluateUnit(h, 138.0, std::nullopt, {}, motion).pos.x == doctest::Approx(2.5f));
}
