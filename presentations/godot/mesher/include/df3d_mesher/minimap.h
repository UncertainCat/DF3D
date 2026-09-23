#pragma once
// Layer-4 selected-level overview. Palette indices refer to the installed
// classic colour configuration; this is not DF's surface/biome map algorithm.
#include <algorithm>
#include <optional>
#include "wm/types.h"
namespace df3d::mesher {
inline int minimapPalette(const std::optional<wm::TileState>& tile) {
 if (!tile || (tile->flags & wm::kTileHidden) || tile->shape == wm::TileShape::Unknown) return -1;
 const auto& t=*tile;
 if(t.liquidLevel) return t.liquidKind==wm::LiquidKind::Magma ? 12 : 11;
 if(t.shape==wm::TileShape::Empty || t.shape==wm::TileShape::RampTop) return -1;
 if(t.shape==wm::TileShape::TreeTrunk || t.shape==wm::TileShape::TreeBranch || t.shape==wm::TileShape::Shrub || t.shape==wm::TileShape::Sapling) return 2;
 switch(t.materialKind) {
 case wm::MaterialKind::Grass: case wm::MaterialKind::Plant: return 10;
 case wm::MaterialKind::Wood: case wm::MaterialKind::Soil: return 6;
 case wm::MaterialKind::Ice: return 15;
 default: return t.shape==wm::TileShape::Wall || t.shape==wm::TileShape::Fortification ? 7 : 8;
 }
}
// Pixel centers, including the final source tile when source/output match.
inline int minimapSample(int pixel,int pixels,int tiles) {
 return std::clamp(static_cast<int>((static_cast<int64_t>(2*pixel+1)*tiles)/(2*pixels)),0,tiles-1);
}
}
