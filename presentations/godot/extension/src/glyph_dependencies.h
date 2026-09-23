#pragma once
#include "wm/world_model.h"
#include "df3d_assets/asset_index.h"
#include <optional>

namespace df3d_godot {
// Snapshot only the semantic rows read by glyph fallback. Missing rows are
// dependencies too: late arrival must repair previously unresolved artwork.
struct GlyphInputs {
    bool known = false;
    std::optional<wm::MaterialGlyph> material;
    std::optional<wm::CreatureGlyph> creature;
    std::optional<uint8_t> itemDefTile;
    friend bool operator==(const GlyphInputs&, const GlyphInputs&) = default;
};
struct ItemGlyphDependency {
    wm::MaterialId material = wm::kNoMaterial;
    wm::ItemKind kind = wm::ItemKind::Unknown;
    std::string subtype;
    GlyphInputs observed;
    GlyphInputs read(const wm::WorldModel& model) const {
        GlyphInputs result;
        result.known = model.glyphsKnown();
        if (const auto* row = model.materialGlyph(material)) result.material = *row;
        const auto token = model.materialName(material);
        if (token.starts_with("CREATURE:"))
            if (const auto* row = model.creatureGlyph(df3d::assets::AssetIndex::materialRawId(token))) result.creature = *row;
        if (!subtype.empty())
            if (const auto* row = model.itemDefGlyph(kind, subtype)) result.itemDefTile = row->tile;
        return result;
    }
};
}
