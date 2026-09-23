#pragma once

#include <optional>
#include <string>

#include "wm/world_model.h"

namespace inspector {

struct ReportOptions {
  // Also list every building and item on the rendered z level, one line
  // each (`--list`).
  bool listEntities = false;
};

// Human-readable report of the world at `renderTick`: map header, terrain,
// building and item summaries, one line per unit ever seen (id, species,
// presence, position, job, motion), optionally the buildings and items of
// the rendered level, then an ASCII rendering of one z level (`z`, or the
// level holding the most present units).
std::string report(const wm::WorldModel& model, double renderTick,
                   std::optional<int> z = std::nullopt, ReportOptions options = {});

// Pieces of the report, exposed for tests and the live client.
std::string terrainSummary(const wm::WorldModel& model);
// "buildings: <n> known | version <v>" with counts by kind and by stage;
// "buildings: none (no Full snapshot yet)" before one arrives. Likewise
// "items: <n> on map | version <v>" with counts by kind.
std::string buildingSummary(const wm::WorldModel& model);
// "items: <n> on map | version <v>" with counts by kind, then a line with
// the web count and the corpse items that carry an appearance stack.
std::string itemSummary(const wm::WorldModel& model);
// "glyphs: known|no Full yet | species N, materials M, itemdefs K".
std::string glyphSummary(const wm::WorldModel& model);
// One line per building / item on z, sorted by id: kind, subtype, custom
// raw id, rectangle / position, material, stage, stack, flags.
std::string listBuildingsAt(const wm::WorldModel& model, int z);
std::string listItemsAt(const wm::WorldModel& model, int z);
// Overlay glyphs (see glyphLegend()): buildings by kind, 'x' while not
// Complete; items by kind family.
char buildingGlyph(const wm::Building& b);
char itemGlyph(const wm::MapItem& it);
// Compact appearance summary for one unit: "appearance v<hash>:
// <n> layers [PAGE, PAGE, ...] palettes <m>" listing the distinct tile
// pages in draw order; "appearance: none yet" before one arrives, and
// "appearance v<hash>: no graphics" for an empty stack.
std::string appearanceSummary(const wm::WorldModel& model, wm::UnitId id);
// One z level as text: dims.y rows of dims.x glyphs (see glyphLegend()),
// with the level's buildings (footprints, extents honoured), then items,
// then present units ('@') overlaid in that precedence. Hidden and
// never-observed tiles both show as '?'.
std::string renderZ(const wm::WorldModel& model, int z, double renderTick);
// The z level with the most present units at renderTick (0 if none).
int defaultZ(const wm::WorldModel& model, double renderTick);
char tileGlyph(const wm::TileState& t);
const char* glyphLegend();

}  // namespace inspector
