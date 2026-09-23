#pragma once
#include "wm/types.h"
#include <optional>
#include <string>
#include <string_view>

namespace df3d_godot {
// Only inputs read while resolving art. Motion, job, attack, camera and stack
// placement are intentionally absent. Glyph rows matter only for fallback art.
struct UnitArtKey {
    uint64_t resources=0;
    uint32_t appearance=0, volume=0;
    bool hasLayers=false, glyphDependent=false, glyphsKnown=false;
    std::string species;
    std::optional<wm::CreatureGlyph> glyph;
    bool matches(uint64_t generation,uint32_t version,bool layers,uint32_t bodyVolume,
        std::string_view token,bool known,const std::optional<wm::CreatureGlyph>& creature) const {
        return resources==generation && appearance==version && hasLayers==layers &&
            volume==bodyVolume && species==token &&
            (!glyphDependent || (glyphsKnown==known && glyph==creature));
    }
};
}
