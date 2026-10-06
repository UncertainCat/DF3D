#pragma once
#include "paint_water.h"

namespace df3d_area {
struct PaintMaterialFacts {
  bool tileMaterialObserved=false, soilTile=false;
  bool materialObserved=false, soilMaterial=false, sand=false, fired=false;
};
struct PaintMaterialEligibility {
  PaintEligibility sand=PaintEligibility::Unknown;
  PaintEligibility clay=PaintEligibility::Unknown;
};
// Native material controls052006/055430: eligibility requires the ordinary
// bank predicate and a soil tile/material. Grass/plant, stone and mineral tiles
// do not inherit collection eligibility from a qualifying geological layer.
inline PaintMaterialEligibility paintMaterialEligibility(PaintEligibility bank,
    const PaintMaterialFacts& m) {
  using E=PaintEligibility;
  if(bank!=E::Eligible)return {bank,bank};
  if(!m.tileMaterialObserved)return {};
  if(!m.soilTile)return {E::Ineligible,E::Ineligible};
  if(!m.materialObserved)return {};
  if(!m.soilMaterial)return {E::Ineligible,E::Ineligible};
  return {m.sand?E::Eligible:E::Ineligible,m.fired?E::Eligible:E::Ineligible};
}
}
