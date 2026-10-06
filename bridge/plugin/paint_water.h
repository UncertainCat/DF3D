#pragma once
#include <array>
#include <cstdint>

namespace df3d_area {
enum class PaintEligibility : uint8_t { Unknown, Ineligible, Eligible };
// Semantic shape groups established by native Paint probes055430. Native NONE
// and unrecognized values remain Unknown; these are not renderer/wire values.
enum class PaintShape : uint8_t {
  Unknown, Empty, Floor, Wall, Fortification, Stair, Ramp, RampTop,
  BrookTop, Shrub, Sapling, Boulder, Pebbles, BrookBed, Branch, TrunkBranch,
  Twig, EndlessPit
};
struct PaintTileObservation {
  PaintShape shape=PaintShape::Unknown;
  uint8_t occupancy=0; // native None..Dynamic, 0..7
  uint8_t depth=0;
  bool magma=false, hidden=false, observed=false;
};
inline PaintEligibility paintBank(const PaintTileObservation& t) {
  using E=PaintEligibility;
  if(!t.observed || t.occupancy>7 || t.depth>7 || t.shape>PaintShape::EndlessPit)return E::Unknown;
  if(t.hidden || t.occupancy==3 || t.occupancy==4 || t.occupancy==6 ||
     t.depth==7 || (t.depth && t.magma))return E::Ineligible;
  if(t.shape==PaintShape::Unknown)return E::Unknown;
  if(t.occupancy==5)return E::Eligible;
  switch(t.shape) {
    case PaintShape::Floor:case PaintShape::Stair:case PaintShape::Ramp:
    case PaintShape::BrookTop:case PaintShape::Shrub:case PaintShape::Sapling:
    case PaintShape::Boulder:case PaintShape::Pebbles:case PaintShape::Branch:
      return E::Eligible;
    default:return E::Ineligible;
  }
}
inline PaintEligibility paintWaterOpening(const PaintTileObservation& t) {
  using E=PaintEligibility;
  if(!t.observed || t.occupancy>7 || t.shape>PaintShape::EndlessPit)return E::Unknown;
  if(t.occupancy==3 || t.occupancy==5 || t.occupancy==6)return E::Ineligible;
  switch(t.shape) {
    case PaintShape::Empty:case PaintShape::RampTop:case PaintShape::BrookTop:
    case PaintShape::EndlessPit:
      return E::Eligible;
    case PaintShape::Floor:case PaintShape::Wall:case PaintShape::Fortification:
    case PaintShape::Stair:case PaintShape::Ramp:case PaintShape::Boulder:
    case PaintShape::Pebbles:case PaintShape::BrookBed:case PaintShape::Branch:
    case PaintShape::TrunkBranch:case PaintShape::Twig:case PaintShape::Shrub:
    case PaintShape::Sapling:return E::Ineligible;
    default:return E::Unknown;
  }
}
// Native055430: Pond counts these three shapes independently of building
// occupancy and liquid depth/type. It must not use the ordinary bank predicate.
inline PaintEligibility paintPond(const PaintTileObservation& t) {
  using E=PaintEligibility;
  if(!t.observed || t.occupancy>7 || t.depth>7 || t.shape>PaintShape::EndlessPit)return E::Unknown;
  if(t.hidden)return E::Ineligible;
  if(t.shape==PaintShape::Unknown)return E::Unknown;
  return t.shape==PaintShape::Empty || t.shape==PaintShape::RampTop ||
    t.shape==PaintShape::EndlessPit?E::Eligible:E::Ineligible;
}
struct PaintBaseEligibility {
  PaintEligibility ordinary=PaintEligibility::Unknown;
  PaintEligibility pond=PaintEligibility::Unknown;
};
struct PaintWaterColumn {
  PaintEligibility opening=PaintEligibility::Unknown;
  bool waterObserved=false, magma=false, salt=false;
  uint8_t depth=0;
};
struct PaintWaterEligibility {
  PaintEligibility water=PaintEligibility::Unknown;
  PaintEligibility fishing=PaintEligibility::Unknown;
};
inline PaintEligibility paintAnyWater(PaintEligibility bank,
    const std::array<PaintWaterColumn,8>& columns,bool allowSalt) {
  using E=PaintEligibility;
  if(bank!=E::Eligible)return bank;
  bool unknown=false;
  for(const auto& c:columns) {
    if(c.opening==E::Ineligible)continue;
    if(c.opening==E::Unknown || !c.waterObserved || c.depth>7) {
      unknown=true;continue;
    }
    if(c.depth>=2 && !c.magma && (allowSalt || !c.salt))return E::Eligible;
  }
  return unknown?E::Unknown:E::Ineligible;
}
// Native DF53.16 captures paint-water-controls-052938: all eight adjacent
// openings use only the immediately lower tile. Salt excludes drinking, not
// fishing. Hidden neighboring tiles can qualify an observed bank; callers must
// return only this eligibility, never disclose their raw hidden terrain.
inline PaintWaterEligibility paintWaterEligibility(PaintEligibility bank,
    const std::array<PaintWaterColumn,8>& columns) {
  return {paintAnyWater(bank,columns,false),paintAnyWater(bank,columns,true)};
}
}
