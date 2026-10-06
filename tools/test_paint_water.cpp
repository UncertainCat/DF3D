#include "doctest.h"
#include "../bridge/plugin/paint_water.h"
namespace area=df3d_area;
namespace {
using E=area::PaintEligibility;
using S=area::PaintShape;
area::PaintTileObservation tile(S shape,uint8_t occupancy=0) {
  return {shape,occupancy,0,false,false,true};
}
std::array<area::PaintWaterColumn,8> closedColumns() {
  std::array<area::PaintWaterColumn,8> c{};
  for(auto& v:c)v.opening=E::Ineligible;
  return c;
}
}
TEST_CASE("Paint bank and edge occupancy match independent native boundary counts") {
  // DF53.16 paint-water-controls-052938/water-boundaries.json. Bit n is the
  // native count at occupancy n. These expected masks are captured results,
  // not computed with the implementation under test.
  struct Sample {S shape;uint8_t bankMask,edgeMask;};
  const Sample rows[]={{S::Floor,0xa7,0},{S::Wall,0x20,0},
    {S::Fortification,0x20,0},{S::Empty,0x20,0x97},
    {S::Stair,0xa7,0},{S::Ramp,0xa7,0},{S::BrookTop,0xa7,0x97},
    // Native055430 bank-shapes/edge-shapes.json extends the same independent
    // occupancy masks to every non-sentinel native shape group.
    {S::Boulder,0xa7,0},{S::Pebbles,0xa7,0},{S::BrookBed,0x20,0},
    {S::Branch,0xa7,0},{S::TrunkBranch,0x20,0},{S::Twig,0x20,0},
    {S::EndlessPit,0x20,0x97},{S::RampTop,0x20,0x97},
    {S::Shrub,0xa7,0},{S::Sapling,0xa7,0}};
  for(const auto& r:rows)for(uint8_t occ=0;occ<8;++occ) {
    INFO("shape=",int(r.shape)," occupancy=",int(occ));
    CHECK(area::paintBank(tile(r.shape,occ))==((r.bankMask&(1<<occ))?E::Eligible:E::Ineligible));
    CHECK(area::paintWaterOpening(tile(r.shape,occ))==((r.edgeMask&(1<<occ))?E::Eligible:E::Ineligible));
  }
  // water-depth-shapes.json: RampTop opening counts1; both extra stair shapes0.
  CHECK(area::paintWaterOpening(tile(S::RampTop))==E::Eligible);
}
TEST_CASE("Paint water native directional depth and salt controls") {
  // water-directions.json: every offset counts0 at depth0/1 and1 at2/7.
  // water-open-edge.json supplies depths3..6. water-boundaries.json supplies
  // the salt-water difference: WaterSource0, Fishing1.
  for(size_t direction=0;direction<8;++direction)for(uint8_t depth=0;depth<=7;++depth) {
    auto columns=closedColumns();
    columns[direction]={E::Eligible,true,false,false,depth};
    const auto actual=area::paintWaterEligibility(E::Eligible,columns);
    const auto expected=depth>=2?E::Eligible:E::Ineligible;
    CHECK(actual.water==expected);CHECK(actual.fishing==expected);
    columns[direction].salt=true;
    const auto salt=area::paintWaterEligibility(E::Eligible,columns);
    CHECK(salt.water==E::Ineligible);CHECK(salt.fishing==expected);
  }
  auto columns=closedColumns();columns[0]={E::Eligible,true,true,false,1};
  const auto magma=area::paintWaterEligibility(E::Eligible,columns);
  CHECK(magma.water==E::Ineligible);CHECK(magma.fishing==E::Ineligible);
}
TEST_CASE("Paint water bank and opening have different liquid and visibility rules") {
  // water-boundaries.json: hidden bank has no draft; hidden edge still counts.
  auto bank=tile(S::Floor);auto edge=tile(S::Empty);
  bank.hidden=true;edge.hidden=true;
  CHECK(area::paintBank(bank)==E::Ineligible);
  CHECK(area::paintWaterOpening(edge)==E::Eligible);
  bank.hidden=false;
  for(uint8_t depth=1;depth<=7;++depth) {
    bank.depth=depth;edge.depth=depth;
    CHECK(area::paintBank(bank)==(depth==7?E::Ineligible:E::Eligible));
    CHECK(area::paintWaterOpening(edge)==E::Eligible);
  }
  bank.depth=1;bank.magma=true;edge.depth=1;edge.magma=true;
  CHECK(area::paintBank(bank)==E::Ineligible);
  CHECK(area::paintWaterOpening(edge)==E::Eligible);
}
TEST_CASE("Paint eligibility never converts missing observations to zero") {
  auto columns=closedColumns();columns[0].opening=E::Unknown;
  CHECK(area::paintWaterEligibility(E::Eligible,columns).water==E::Unknown);
  columns[0].opening=E::Eligible; // lower tile still missing
  CHECK(area::paintWaterEligibility(E::Eligible,columns).fishing==E::Unknown);
  // A known qualifying column proves the OR even with another missing column.
  columns[1]={E::Eligible,true,false,true,7};
  auto actual=area::paintWaterEligibility(E::Eligible,columns);
  CHECK(actual.water==E::Unknown);CHECK(actual.fishing==E::Eligible);
  columns[1].salt=false;
  actual=area::paintWaterEligibility(E::Eligible,columns);
  CHECK(actual.water==E::Eligible);CHECK(actual.fishing==E::Eligible);
  CHECK(area::paintWaterEligibility(E::Unknown,columns).water==E::Unknown);
  CHECK(area::paintWaterEligibility(E::Ineligible,columns).water==E::Ineligible);
  CHECK(area::paintBank({})==E::Unknown);
  CHECK(area::paintBank(tile(S::Unknown))==E::Unknown);
  CHECK(area::paintBank(tile(S::RampTop))==E::Ineligible);
  auto invalid=tile(S::Floor);invalid.depth=8;
  CHECK(area::paintBank(invalid)==E::Unknown);
  invalid=tile(S::Floor,8);CHECK(area::paintBank(invalid)==E::Unknown);
}
TEST_CASE("Pond counts native open shapes independently of ordinary occupancy and liquid guards") {
  // Native055430 bank-shapes.json: three shapes have mask0xff; all others0.
  for(const auto shape:{S::Empty,S::Floor,S::Boulder,S::Pebbles,S::Wall,
      S::Fortification,S::Stair,S::Ramp,S::RampTop,S::BrookBed,S::BrookTop,
      S::Branch,S::TrunkBranch,S::Twig,S::Sapling,S::Shrub,S::EndlessPit}) {
    const auto expected=shape==S::Empty || shape==S::RampTop || shape==S::EndlessPit?
      E::Eligible:E::Ineligible;
    for(uint8_t occ=0;occ<8;++occ)CHECK(area::paintPond(tile(shape,occ))==expected);
  }
  // pond-liquids.json / pond-chasm.json: these shapes at occupancy0 were
  // independently tested under water/magma0..7 and hidden selection.
  for(const auto shape:{S::Empty,S::RampTop,S::EndlessPit,S::Twig,S::BrookTop,S::Floor}) {
    const auto expected=shape==S::Empty || shape==S::RampTop || shape==S::EndlessPit?
      E::Eligible:E::Ineligible;
    auto t=tile(shape);
    for(bool magma:{false,true})for(uint8_t depth=0;depth<=7;++depth) {
      t.magma=magma;t.depth=depth;CHECK(area::paintPond(t)==expected);
    }
    t.hidden=true;CHECK(area::paintPond(t)==E::Ineligible);
  }
  CHECK(area::paintPond({})==E::Unknown);
  CHECK(area::paintPond(tile(S::Unknown))==E::Unknown);
  CHECK(area::paintPond(tile(static_cast<S>(255)))==E::Unknown);
}
