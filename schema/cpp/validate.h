// Schema validators: referential integrity, bounds, enum
// validity. Every fixture and every live capture must pass these in CI.
// When a field is added to the schema, its validation is added here in the
// same change.
#pragma once

#include <optional>
#include <string>

#include "fixture_io.h"
#include "mirror_generated.h"

namespace df3d::mirror {

// Returns an error message, or nullopt if the snapshot is valid.
std::optional<std::string> validateSnapshot(const Snapshot& snap);

// Validates one Command (v6): a known payload; rectangles well
// formed (x1 <= x2, y1 <= y2, non-negative) and, when `mapSize` is given
// (the bridge validates against the live map; the schema tests and
// clients may pass nullptr), inside it; enums valid; dig priority 1..7;
// item / building ids non-zero. Returns an error message, or nullopt.
std::optional<std::string> validateCommand(const Command& cmd, const TilePos* mapSize);

// Stream-level terrain invariant: a Delta may not precede the first Full.
// Feed snapshots in stream order (validateStream does this for fixtures;
// the live client does it for shared-memory polls).
class TerrainStreamState {
 public:
  // Returns an error if `snap` is a Delta before any Full; records Fulls.
  std::optional<std::string> check(const Snapshot& snap);
  bool seenFull() const { return seenFull_; }

 private:
  bool seenFull_ = false;
};

// Same rule for the v4 entity tables: building_scope / item_scope Delta
// may not precede that table's first Full.
class EntityStreamState {
 public:
  std::optional<std::string> check(const Snapshot& snap);
  bool seenFullBuildings() const { return seenFullBuildings_; }
  bool seenFullItems() const { return seenFullItems_; }

 private:
  bool seenFullBuildings_ = false;
  bool seenFullItems_ = false;
};

// Validates every snapshot plus stream-level invariants: non-decreasing
// ticks, non-decreasing emitted_at_ms, stable map_size, no Delta before the
// first Full (terrain, buildings, items).
std::optional<std::string> validateStream(const FixtureStream& stream);

}  // namespace df3d::mirror
