// Resolves, for one live unit (or one corpse item: the creature's
// CORPSE-role layer set or simple CORPSE sprite, evaluated against the
// state the corpse item carries), the ordered stack of creature-graphics
// layers DF draws it with, from DF's own parsed graphics raws
// (creature_raw_graphics / creature_graphics_layer_setst /
// creature_graphics_layerst, loaded by DF at startup) and the unit's state
// (caste, profession, worn items, syndromes, tissue colours, ...). Every
// layer resolves a texpos back through df::global::texture's tile pages
// to (page token, tile x, tile y) and a palette page + row, which is what
// the mirror publishes (schema v3). Nothing here reads or writes pixels
// except the diagnostic `verify`, which composites the stack in-process
// and compares it with the texture DF itself cached for the unit.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "ColorText.h"

namespace df {
struct unit;
struct item;
struct tile_pagest;
struct palette_pagest;
struct coord;
}  // namespace df

namespace df3d_appearance {

struct Layer {
    const df::tile_pagest* page = nullptr;
    uint16_t tileX = 0, tileY = 0;
    uint8_t cellsX = 1, cellsY = 1;
    const df::palette_pagest* palette = nullptr;  // null = drawn as-is
    int16_t row = -1, keyRow = -1;
    int8_t offX = 0, offY = 0;
    const std::string* token = nullptr;  // LAYER name (DF memory), diagnostics only

    bool sameReference(const Layer& o) const {
        return page == o.page && tileX == o.tileX && tileY == o.tileY && cellsX == o.cellsX &&
               cellsY == o.cellsY && palette == o.palette && row == o.row && keyRow == o.keyRow &&
               offX == o.offX && offY == o.offY;
    }
};

struct Result {
    std::vector<Layer> layers;  // bottom first
    bool layered = false;       // a LAYER_SET was used (else a simple sprite or nothing)
    int32_t role = -1;          // creature_graphics_role chosen
    int32_t prof = -1;          // layer set profession key chosen
};

// Drops every cache (texpos map, palette surfaces). Call on map load and
// on unload.
void reset();

// Resolves the unit's appearance. Returns false (and leaves `out.layers`
// empty) when DF has no graphics for it. Never touches pixels.
bool resolve(df::unit* u, Result& out);
// Native PORTRAIT layer sets; never substitute the map sprite.
bool resolvePortrait(df::unit* u, Result& out);

// Cheap per-frame change hint: a hash of the unit fields the layer
// conditions read that can change between frames (profession, inventory
// ids/modes, syndromes, ghost flag, caste, body size bucket, missing parts). Slow-moving
// inputs (tissue growth) are not covered; the bridge re-resolves every
// unit periodically for those.
uint32_t fingerprint(const df::unit* u);

// Corpse items. `resolveCorpse` resolves a Corpse item's stack
// through the creature's CORPSE role (layer set with the item's caste,
// tissue colours / lengths / styles, body part presence and the dead
// unit's child status as the conditions; else the simple CORPSE sprite,
// CHILD variant for children). CorpsePiece items and non-corpse items
// leave `out.layers` empty and return false (DF draws body parts from
// hardcoded BODYPART_* tiles that df-structures does not expose; layer 4
// picks them from `MapItem.corpse_flags`). `corpseFingerprint` hashes the
// state the corpse conditions read (race, caste, corpse flags, rot,
// tissue styles, size bucket).
bool resolveCorpse(df::item* it, Result& out);
uint32_t corpseFingerprint(const df::item* it);

// The page's TILE_PAGE token, and the palette file's path relative to the
// DF install root with forward slashes (what the mirror publishes).
const std::string& pageToken(const df::tile_pagest* page);
std::string paletteInstallPath(const df::palette_pagest* palette);

// Diagnostics (console command `df3d appearance ...`).
// dump: prints role / layer set / every chosen layer with its resolution,
//   DF's own cached unit texpos and what it is, and, with verify, composites
//   the stack and compares it pixel-wise with DF's cached texture.
void dump(DFHack::color_ostream& out, df::unit* u, bool verify, const std::string& imageDir = {});
// trace: re-resolves the unit printing every failing condition of the
//   layers whose token contains `token` ("*" = all layers; "*tissue" also
//   prints the tissue values every tissue condition reads).
void trace(DFHack::color_ostream& out, df::unit* u, const std::string& token);
// layersets: prints the chosen layer set's raw layer table (every layer,
//   conditions and defaults) — for calibrating the evaluator.
void dumpLayerSet(DFHack::color_ostream& out, df::unit* u, int maxLayers,
                  const std::string& tokenFilter = {});
// survey: for up to n units of the unit's race, prints a one-line summary
//   (layers, DF texpos kind, verify mismatch %) and the random-part
//   calibration table.
void survey(DFHack::color_ostream& out, int maxUnits);
// pages: prints the texpos map summary (page count, texpos range, unmapped
//   texposes).
void dumpPages(DFHack::color_ostream& out);
// Read-only runtime texture diagnostic. Writes bounded RGBA, JSON dimensions
// and a magenta-backed PPM to an absolute prefix in an existing directory.
bool dumpTexture(DFHack::color_ostream& out, int32_t texpos, const std::string& prefix);
// Corpse diagnostics (`df3d corpse ...`). dumpCorpse prints the
//   item's creature / caste / corpse flags, the resolved stack, DF's own
//   cached corpse texpos (item_corpsest::texpos) and the viewport's item
//   cell, and with `verify` composites the stack and diffs it against
//   whichever of the two DF has drawn. surveyCorpses runs that over up to
//   n on-map corpse items at the current view z (on-screen ones verify).
void dumpCorpse(DFHack::color_ostream& out, df::item* it, bool verify, const std::string& imageDir = {});
void surveyCorpses(DFHack::color_ostream& out, int maxItems);
// The item cell index of a map position in the main viewport at the
// current view z ((x - window_x) * dim_y + (y - window_y)), or -1.
int viewportIndexAt(const df::coord& pos);

}  // namespace df3d_appearance
