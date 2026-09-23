// Tier 0: sim-clock estimation. Pause, slowdown, and speedup are normal
// operating conditions, not edge cases.
#include <doctest.h>

#include "wm/sim_clock.h"

using namespace wm;

TEST_CASE("constant rate: estimate advances linearly between snapshots") {
  SimClockEstimator c;
  c.observe(0, 0.0);
  c.observe(10, 1.0);
  c.observe(20, 2.0);
  CHECK(c.ticksPerSecond() == doctest::Approx(10.0));
  CHECK(c.estimate(2.0) == doctest::Approx(20.0));
  CHECK(c.estimate(2.1) == doctest::Approx(21.0));
}

TEST_CASE("extrapolation is clamped when the bridge goes quiet") {
  SimClockEstimator c({.window = 8, .maxExtrapolationTicks = 2.0});
  c.observe(0, 0.0);
  c.observe(10, 1.0);
  // 10 ticks/sec; 5 wall seconds of silence would naively extrapolate +50.
  CHECK(c.estimate(6.0) == doctest::Approx(12.0));
}

TEST_CASE("pause: repeated ticks drive the rate to zero") {
  SimClockEstimator c({.window = 4, .maxExtrapolationTicks = 2.0});
  c.observe(100, 0.0);
  c.observe(110, 1.0);
  // Paused: same tick keeps arriving.
  c.observe(110, 2.0);
  c.observe(110, 3.0);
  c.observe(110, 4.0);  // window now spans only the flat region
  CHECK(c.ticksPerSecond() == doctest::Approx(0.0));
  CHECK(c.estimate(10.0) == doctest::Approx(110.0));
}

TEST_CASE("speedup: rate estimate converges to the new rate") {
  SimClockEstimator c({.window = 4, .maxExtrapolationTicks = 100.0});
  c.observe(0, 0.0);
  c.observe(10, 1.0);
  c.observe(20, 2.0);
  // Rate doubles to 20 ticks/sec.
  c.observe(40, 3.0);
  c.observe(60, 4.0);
  c.observe(80, 5.0);
  c.observe(100, 6.0);  // window covers only the fast region now
  CHECK(c.ticksPerSecond() == doctest::Approx(20.0));
}

TEST_CASE("slowdown: rate follows the sim down") {
  SimClockEstimator c({.window = 3, .maxExtrapolationTicks = 100.0});
  c.observe(0, 0.0);
  c.observe(100, 1.0);
  c.observe(105, 2.0);
  c.observe(110, 3.0);
  c.observe(115, 4.0);
  CHECK(c.ticksPerSecond() == doctest::Approx(5.0));
}

TEST_CASE("estimate in the past clamps to the last observed tick") {
  SimClockEstimator c;
  c.observe(0, 0.0);
  c.observe(10, 1.0);
  CHECK(c.estimate(0.5) == doctest::Approx(10.0));
}

TEST_CASE("non-increasing wall times are ignored, no division by zero") {
  SimClockEstimator c;
  c.observe(0, 1.0);
  c.observe(10, 1.0);  // same wall second: dropped
  c.observe(10, 0.5);  // going backwards: dropped
  CHECK(c.ticksPerSecond() == doctest::Approx(0.0));
  CHECK(c.estimate(2.0) == doctest::Approx(0.0));
}

TEST_CASE("single observation: estimate holds that tick") {
  SimClockEstimator c;
  c.observe(42, 1.0);
  CHECK(c.hasObservations());
  CHECK(c.estimate(100.0) == doctest::Approx(42.0));
}
