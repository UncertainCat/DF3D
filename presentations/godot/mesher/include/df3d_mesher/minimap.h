#pragma once
// Presentation-owned native minimap color mapping from semantic terrain facts.
#include <algorithm>
#include <optional>
#include "wm/types.h"
namespace df3d::mesher {
// Fixed RGB from protected native133221..134815 captures. -1 is unknown/hidden.
// The below tile's hidden bit does not hide its liquid from an exposed opening
// in the captured native behavior; top-level hidden always wins.
inline int minimapColor(const std::optional<wm::TileState>& tile,
                        const std::optional<wm::TileState>& below = std::nullopt, bool mapBoundary = false) {
 if (!tile || (tile->flags & wm::kTileHidden) || tile->shape == wm::TileShape::Unknown) return -1;
 const auto& t=*tile;
 using S=wm::TileShape; using M=wm::MaterialKind;
 if(t.buildingOccupancy || t.materialKind==M::Constructed) return 0xc88c00;
 if(t.liquidLevel) return t.liquidKind==wm::LiquidKind::Magma ? 0x801800 : 0x0018c0;
 const bool open=t.shape==S::Empty || t.shape==S::RampTop;
 if((open || t.brookTop) && below && below->liquidLevel)
   return below->liquidKind==wm::LiquidKind::Magma ? 0x801800 : 0x0018c0;
 if(t.materialKind==M::Ice) return 0xe0ffff;
 if(open) return 0x64e0ff;
 if(t.shape==S::TreeTrunk) return t.root ? (mapBoundary ? 0xc0c0c0 : 0x404040) : 0x644600;
 if(t.shape==S::TreeBranch || (t.shape==S::Ramp && t.materialKind==M::Wood)) return 0x206000;
 if(t.shape==S::Wall || t.shape==S::Fortification) return mapBoundary ? 0xc0c0c0 : 0x404040;
 if(t.shape==S::Shrub) return 0x328000;
 if(t.shape==S::Sapling || t.materialKind==M::Grass) return 0x80c000;
 if(t.subterranean) return 0xc0c0c0;
 const bool ground=t.shape==S::Floor || t.shape==S::Boulder || t.shape==S::Pebbles;
 if(ground && t.materialKind==M::Soil) return 0x804000;
 if(ground && (t.materialKind==M::Stone || t.materialKind==M::Mineral || t.materialKind==M::Gem) &&
    !(t.flags & wm::kTileSmooth)) return 0x808080;
 return 0x80c000;
}
// Pixel centers, including the final source tile when source/output match.
inline int minimapSample(int pixel,int pixels,int tiles) {
 return std::clamp(static_cast<int>((static_cast<int64_t>(2*pixel+1)*tiles)/(2*pixels)),0,tiles-1);
}
}
