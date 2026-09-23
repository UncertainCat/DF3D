// Internal (worldmodel/src only): mirror buffer → neutral SnapshotData.
// Not installed with public headers; presentations never see mirror types.
#pragma once

#include "mirror_generated.h"
#include "wm/world_model.h"

namespace wm::detail {

// With withTerrain == false the terrain payload is skipped entirely (the
// snapshot reads as terrain_scope None), for units-only models.
SnapshotData toSnapshotData(const df3d::mirror::Snapshot& s, bool withTerrain = true);

}  // namespace wm::detail
