#pragma once

#include "wm/types.h"
#include <functional>
#include <optional>
#include <span>

namespace wm {

enum class TrackTileEligibility { Eligible, Ineligible, Unverified };
enum class TrackSiteOccupancy { None, PendingTrack, BlockingBuilding, Unknown };
struct TrackSiteFacts {
  // Native shape classification for eligibility, not an unchecked copy of a
  // normalized display tile (e.g. brook bed/top are displayed as Wall/Floor).
  // Known brook/tree classes use equivalent eligibility shapes; support/open
  // facts remain separate so this cannot invent ramp support from a brook bed.
  // Native shapes without established rules must remain Unknown.
  TileShape shape = TileShape::Unknown;
  TrackSiteOccupancy occupancy = TrackSiteOccupancy::Unknown;
  bool loaded = false;
  bool hidden = false;
  uint8_t liquidDepth = 0;
  bool magma = false;
  bool endpointOnly = false; // Ordinary/dead twigs; burning twigs differ.
};
// Preview eligibility from semantic terrain facts. Hidden endpoints differ from
// hidden intermediate tiles. PendingTrack must identify an actual compatible
// construction job, not merely an occupancy bit. BlockingBuilding requires an
// established blocking family/state; unclassified buildings remain Unknown.
// Unverified facts must not be
// silently presented as a native refusal or used to authorize placement.
// Does not validate directed movement, materials, job stage or current targets.
TrackTileEligibility trackSiteEligibility(const TrackSiteFacts& facts, bool endpoint);

struct TrackMovementFacts {
  TileShape shape = TileShape::Unknown;
  bool loaded = false;
  bool clearanceBlocked = true;
  // Native movement facts, independent of display-shape normalization (e.g.
  // a brook bed is displayed as Wall but is not a native wall support).
  bool support = false;
  bool open = false;
  bool movementRamp = false; // Native ramp predicate, not nominal shape.
};
using TrackMovementLookup = std::function<TrackMovementFacts(TilePos)>;
// Forward movement edge, separate from tile/site eligibility. Callers must
// establish complete terrain and dynamic-clearance facts before routing.
// Missing facts cannot establish a connection. Pure vertical/diagonal xy moves
// are never valid track steps. Ascent accepts open space above the ramp;
// descent requires RampTop, matching the directed native rule.
bool trackMovementConnected(TilePos from, TilePos to, const TrackMovementLookup& lookup);
// Native search's linked ramp/top marking, not a movement edge or site approval.
std::optional<TilePos> trackLinkedTile(TilePos position, const TrackMovementLookup& lookup);

enum class TrackPathStatus { Found, NoPath, InvalidInput, FrontierLimit, UnverifiedTerrain };
struct TrackPathResult {
  TrackPathStatus status = TrackPathStatus::NoPath;
  std::vector<TilePos> tiles;
};

struct TrackRouteRules {
  std::function<bool(TilePos)> eligible;
  // Direction is in route order, even though the search is destination-seeded.
  std::function<bool(TilePos, TilePos)> connected;
  // Ramp/top partner to mark visited; absent callback means no linked tile.
  std::function<std::optional<TilePos>(TilePos)> linked;
};
// Native search bookkeeping with caller-supplied semantic terrain/edge rules and
// inclusive loaded bounds. No native UI inputs; not a complete site validator.
TrackPathResult routeTrackPath(TilePos start, TilePos goal,
    TilePos minimum, TilePos maximum, const TrackRouteRules& rules);

struct TrackRoutingTile {
  TrackSiteFacts site;
  // Needed above a ramp for an elevation transition. Absent means unknown,
  // rather than an assumed absence of a hatch/grate or other dynamic barrier.
  std::optional<bool> clearanceBlocked;
  std::optional<bool> support;
  std::optional<bool> open;
  std::optional<bool> movementRamp;
  // Native nonzero walkability, checked at non-start sources of elevation edges.
  // Group equality is not required; same-level edges ignore this fact.
  std::optional<bool> walkable;
};
// Compose the native construction rules over a stable semantic snapshot. Bounds
// describe the actual map, not a cropped resident window. Missing facts within
// those bounds produce UnverifiedTerrain and no route, even if a path was found
// through other explored tiles. Each coordinate is sampled at most once.
TrackPathResult routeTrackConstruction(TilePos start, TilePos goal,
    TilePos minimum, TilePos maximum,
    const std::function<TrackRoutingTile(TilePos)>& lookup);

// Flat-only convenience using the same search. Unequal elevations reject.
TrackPathResult routeFlatTrackPath(TilePos start, TilePos goal,
    TilePos minimum, TilePos maximum,
    const std::function<bool(TilePos)>& eligible);

enum TrackConnection : uint8_t { TrackNorth = 1, TrackSouth = 2, TrackEast = 4, TrackWest = 8 };
struct TrackPathPiece {
  TilePos position;
  uint8_t connections = 0;
  bool ramp = false;
};
// Converts an already validated route into semantic piece connections. Ramp
// shape comes from terrain facts, not an inferred elevation icon. Does not merge
// existing track or validate site/material eligibility. Single-tile routes have
// no established native placement behavior and are rejected.
std::optional<std::vector<TrackPathPiece>> trackPathPieces(
    std::span<const TilePos> path, const std::function<bool(TilePos)>& isRamp);

struct PendingTrack {
  TilePos position;
  int32_t buildingId = -1;
  uint8_t connections = 0;
  bool ramp = false;
};
enum class TrackTerrainKind { None, Carved, Constructed };
struct TrackTerrain {
  TilePos position;
  uint8_t connections = 0;
  TrackTerrainKind kind = TrackTerrainKind::Constructed;
  bool ramp = false;
};
enum class TrackPlanAction { Create, Update, Unchanged };
struct TrackPlanPiece {
  TilePos position;
  TrackPlanAction action = TrackPlanAction::Create;
  int32_t buildingId = -1;
  uint8_t expectedConnections = 0;
  uint8_t connections = 0;
  uint8_t expectedTerrainConnections = 0;
  TrackTerrainKind expectedTerrainKind = TrackTerrainKind::None;
  bool ramp = false;
  bool expectedJobRamp = false;
  bool expectedTerrainRamp = false;
};
struct TrackConstructionPlan {
  std::vector<TrackPlanPiece> pieces;
  size_t newPieceCount = 0;
};
// Pure plan for a validated route, pending jobs and existing track terrain.
// The caller must establish terrain/occupancy eligibility, then revalidate IDs,
// stages and expected connections before committing. No mutation or material
// reservation occurs here. Terrain gets a new job even when unchanged unless a
// pending job already exists. Job and terrain expectations remain separate.
// Shape comes from independent terrain facts. Conflicting shapes and pending
// jobs omitting existing terrain connections reject pending native evidence.
std::optional<TrackConstructionPlan> planTrackConstruction(
    std::span<const TilePos> path, std::span<const PendingTrack> existing,
    std::span<const TrackTerrain> terrain, const std::function<bool(TilePos)>& isRamp);

} // namespace wm
