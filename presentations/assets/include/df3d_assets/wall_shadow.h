#pragma once

#include "df3d_assets/wall_top.h"

namespace df3d::assets {

struct WallShadowLayer {
  std::string name;
  int clockwise = 0;
};

// Native DF 53.16: each cardinal uses its two diagonals to choose a straight,
// open-ended or isolated-wall shadow. A diagonal casts a corner only when
// neither adjacent cardinal is occupied. See the 256-case native oracle.
inline std::vector<WallShadowLayer> wallShadowLayers(uint8_t walls) {
  std::vector<WallShadowLayer> result;
  struct Side { uint8_t bit, left, right; const char *name, *leftName, *rightName; int turn; };
  const Side sides[] = {
    {kWallN,kWallNW,kWallNE,"N","NW","NE",1},
    {kWallS,kWallSW,kWallSE,"S","SW","SE",3},
    {kWallW,kWallNW,kWallSW,"W","NW","SW",0},
    {kWallE,kWallNE,kWallSE,"E","NE","SE",2}};
  for (const auto& side : sides) if (walls & side.bit) {
    const bool left = (walls & side.left) != 0, right = (walls & side.right) != 0;
    if (left && right) result.push_back({std::string("WALL_SHADOW_STRAIGHT_") + side.name});
    else if (left || right) result.push_back({std::string("WALL_SHADOW_NEAR_") + side.name +
        "_OPEN_" + (left ? side.rightName : side.leftName)});
    else result.push_back({"WALL_SHADOW_END_OF_WALL_W", side.turn});
  }
  struct Corner { uint8_t bit, adjacent; const char* name; };
  const Corner corners[] = {{kWallNW,kWallN|kWallW,"NW"},{kWallNE,kWallN|kWallE,"NE"},
      {kWallSW,kWallS|kWallW,"SW"},{kWallSE,kWallS|kWallE,"SE"}};
  for (const auto& corner : corners)
    if ((walls & corner.bit) && !(walls & corner.adjacent))
      result.push_back({std::string("WALL_SHADOW_AT_CORNER_") + corner.name});
  return result;
}

// The floor is already palette-resolved. Shadows keep their own source color;
// their alpha is artwork, not an invented material/light-dependent AO curve.
inline bool applyWallShadows(RgbaImage& floor, const AssetIndex& index, uint8_t walls,
                             const ImageLoader& load) {
  if (floor.empty() || floor.width != floor.height || !load) return false;
  for (const auto& layer : wallShadowLayers(walls)) {
    const auto* sprite = index.tile(layer.name);
    const auto* page = sprite ? index.page(sprite->page) : nullptr;
    const auto* image = page ? load(page->absPath) : nullptr;
    if (!image) return false;
    const auto rect = index.pixels(*sprite);
    if (rect.pw != floor.width || rect.ph != floor.height ||
        !image->contains(rect.px,rect.py) || !image->contains(rect.px+rect.pw-1,rect.py+rect.ph-1)) return false;
    for (int y=0; y<floor.height; ++y) for (int x=0; x<floor.width; ++x) {
      int sx=x, sy=y;
      for (int turn=0; turn<layer.clockwise; ++turn) {
        const int previous=sx; sx=sy; sy=rect.pw-1-previous;
      }
      floor.set(x,y,blendWallOverOpaque(floor.get(x,y),image->get(rect.px+sx,rect.py+sy)));
    }
  }
  return true;
}

} // namespace df3d::assets
