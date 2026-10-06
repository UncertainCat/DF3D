#include "doctest.h"
#include "../bridge/plugin/paint_material.h"
namespace area=df3d_area;
using E=area::PaintEligibility;

TEST_CASE("collection eligibility uses native material classes and flags, not names") {
  // Native055430 sources-*.json: all five sand raws and five clay soils count
  // on SoilFloor1. Six negative raws include clay-named loams and kaolinite.
  struct Sample {const char* raw;bool soil,sand,fired;E expectedSand,expectedClay;};
  const Sample rows[]={
    {"SAND_TAN",true,true,false,E::Eligible,E::Ineligible},
    {"SAND_YELLOW",true,true,false,E::Eligible,E::Ineligible},
    {"SAND_WHITE",true,true,false,E::Eligible,E::Ineligible},
    {"SAND_BLACK",true,true,false,E::Eligible,E::Ineligible},
    {"SAND_RED",true,true,false,E::Eligible,E::Ineligible},
    {"CLAY",true,false,true,E::Ineligible,E::Eligible},
    {"SILTY_CLAY",true,false,true,E::Ineligible,E::Eligible},
    {"SANDY_CLAY",true,false,true,E::Ineligible,E::Eligible},
    {"CLAY_LOAM",true,false,true,E::Ineligible,E::Eligible},
    {"FIRE_CLAY",true,false,true,E::Ineligible,E::Eligible},
    {"KAOLINITE",false,false,true,E::Ineligible,E::Ineligible},
    {"CLAYSTONE",false,false,false,E::Ineligible,E::Ineligible},
    {"DOLOMITE",false,false,false,E::Ineligible,E::Ineligible},
    {"LOAM",true,false,false,E::Ineligible,E::Ineligible},
    {"SANDY_CLAY_LOAM",true,false,false,E::Ineligible,E::Ineligible},
    {"SILTY_CLAY_LOAM",true,false,false,E::Ineligible,E::Ineligible}};
  for(const auto& r:rows) {
    INFO(r.raw);
    area::PaintMaterialFacts m{true,true,true,r.soil,r.sand,r.fired};
    auto result=area::paintMaterialEligibility(E::Eligible,m);
    CHECK(result.sand==r.expectedSand);CHECK(result.clay==r.expectedClay);
    // The tested stone/mineral/grass/shrub/sapling classes never qualify from
    // the same underlying layer. The native adapter supplies this distinction.
    m.soilTile=false;result=area::paintMaterialEligibility(E::Eligible,m);
    CHECK(result.sand==E::Ineligible);CHECK(result.clay==E::Ineligible);
  }
}
TEST_CASE("material eligibility preserves unknowns and ordinary bank exclusions") {
  area::PaintMaterialFacts m{true,true,true,true,true,true};
  auto result=area::paintMaterialEligibility(E::Ineligible,m);
  CHECK(result.sand==E::Ineligible);CHECK(result.clay==E::Ineligible);
  result=area::paintMaterialEligibility(E::Unknown,m);
  CHECK(result.sand==E::Unknown);CHECK(result.clay==E::Unknown);
  m.materialObserved=false;result=area::paintMaterialEligibility(E::Eligible,m);
  CHECK(result.sand==E::Unknown);CHECK(result.clay==E::Unknown);
  m.soilTile=false;result=area::paintMaterialEligibility(E::Eligible,m);
  CHECK(result.sand==E::Ineligible);CHECK(result.clay==E::Ineligible);
  m.tileMaterialObserved=false;result=area::paintMaterialEligibility(E::Eligible,m);
  CHECK(result.sand==E::Unknown);CHECK(result.clay==E::Unknown);
}
