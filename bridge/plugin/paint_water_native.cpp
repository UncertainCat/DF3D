#include "paint_water_native.h"
#include "TileTypes.h"
#include "modules/Maps.h"
#include "df/map_block.h"
#include "df/inorganic_raw.h"
#include "df/region_map_entry.h"
#include "df/world_geo_biome.h"
#include "df/world_geo_layer.h"
#include "df/civzone_type.h"

namespace df3d_area {
namespace {
enum class CountKind { Ordinary, Pond, Water, Fishing, Sand, Clay, Unsupported };
CountKind countKind(int32_t type) {
  switch(type) {
    case df::civzone_type::Pond:return CountKind::Pond;
    case df::civzone_type::WaterSource:return CountKind::Water;
    case df::civzone_type::FishingArea:return CountKind::Fishing;
    case df::civzone_type::SandCollection:return CountKind::Sand;
    case df::civzone_type::ClayCollection:return CountKind::Clay;
    case df::civzone_type::MeetingHall:case df::civzone_type::Bedroom:
    case df::civzone_type::DiningHall:case df::civzone_type::Pen:
    case df::civzone_type::Dungeon:case df::civzone_type::Office:
    case df::civzone_type::Dormitory:case df::civzone_type::Barracks:
    case df::civzone_type::ArcheryRange:case df::civzone_type::Dump:
    case df::civzone_type::AnimalTraining:case df::civzone_type::Tomb:
    case df::civzone_type::PlantGathering:return CountKind::Ordinary;
    default:return CountKind::Unsupported;
  }
}
PaintShape shapeOf(df::tiletype tile) {
  using namespace df::enums::tiletype_shape;
  switch(DFHack::tileShape(tile)) {
    case EMPTY:return PaintShape::Empty;
    case FLOOR:return PaintShape::Floor;
    case BOULDER:return PaintShape::Boulder;
    case PEBBLES:return PaintShape::Pebbles;
    case WALL:return PaintShape::Wall;
    case FORTIFICATION:return PaintShape::Fortification;
    case STAIR_UP:case STAIR_DOWN:case STAIR_UPDOWN:return PaintShape::Stair;
    case RAMP:return PaintShape::Ramp;
    case RAMP_TOP:return PaintShape::RampTop;
    case BROOK_TOP:return PaintShape::BrookTop;
    case BROOK_BED:return PaintShape::BrookBed;
    case BRANCH:return PaintShape::Branch;
    case TRUNK_BRANCH:return PaintShape::TrunkBranch;
    case TWIG:return PaintShape::Twig;
    case ENDLESS_PIT:return PaintShape::EndlessPit;
    case SHRUB:return PaintShape::Shrub;
    case SAPLING:return PaintShape::Sapling;
    default:return PaintShape::Unknown;
  }
}
const df::map_block* blockAt(int32_t x,int32_t y,int32_t z) {
  if(!DFHack::Maps::isValidTilePos(x,y,z))return nullptr;
  return DFHack::Maps::getTileBlock(x,y,z);
}
PaintTileObservation tileAt(const df::map_block* b,int32_t x,int32_t y) {
  if(!b)return {};
  const auto d=b->designation[x&15][y&15];
  return {shapeOf(b->tiletype[x&15][y&15]),
    uint8_t(b->occupancy[x&15][y&15].bits.building),uint8_t(d.bits.flow_size),
    d.bits.liquid_type==df::tile_liquid::Magma,bool(d.bits.hidden),true};
}
}
PaintCounts observeNativePaintCounts(int32_t zoneType,int32_t z,
    const std::vector<Span>& draft,const std::vector<Span>& preview) {
  const auto kind=countKind(zoneType);
  if(kind==CountKind::Unsupported || !DFHack::Maps::IsValid())return {};
  int32_t blocksX=0,blocksY=0,levels=0;
  DFHack::Maps::getSize(blocksX,blocksY,levels);
  if(z<0 || z>=levels || blocksX<=0 || blocksY<=0 ||
      blocksX>32768/16 || blocksY>32768/16)return {};
  return countPaint(draft,preview,blocksX*16,blocksY*16,[&](int32_t x,int32_t y) {
    switch(kind) {
      case CountKind::Ordinary:return observeNativePaintBase(x,y,z).ordinary;
      case CountKind::Pond:return observeNativePaintBase(x,y,z).pond;
      case CountKind::Water:return observeNativePaintWater(x,y,z).water;
      case CountKind::Fishing:return observeNativePaintWater(x,y,z).fishing;
      case CountKind::Sand:return observeNativePaintMaterial(x,y,z).sand;
      case CountKind::Clay:return observeNativePaintMaterial(x,y,z).clay;
      default:return PaintEligibility::Unknown;
    }
  });
}
PaintMaterialEligibility observeNativePaintMaterial(int32_t x,int32_t y,int32_t z) {
  const auto* block=blockAt(x,y,z);
  const auto bank=paintBank(tileAt(block,x,y));
  if(bank!=PaintEligibility::Eligible)return {bank,bank};
  const auto material=DFHack::tileMaterial(block->tiletype[x&15][y&15]);
  PaintMaterialFacts facts;
  if(material==df::tiletype_material::NONE)return {};
  facts.tileMaterialObserved=true;facts.soilTile=material==df::tiletype_material::SOIL;
  if(!facts.soilTile)return paintMaterialEligibility(bank,facts);
  const auto* region=DFHack::Maps::getRegionBiome(DFHack::Maps::getTileBiomeRgn(df::coord(x,y,z)));
  const auto* geo=region?df::world_geo_biome::find(region->geo_index):nullptr;
  const auto index=block->designation[x&15][y&15].bits.geolayer_index;
  if(!geo || index>=geo->layers.size() || !geo->layers[index])return {};
  const auto* raw=df::inorganic_raw::find(geo->layers[index]->mat_index);
  if(!raw)return {};
  // Match the existing terrain/DFHack soil resolver: the last soil layer is
  // the biome's default when the tile's designated layer is stone.
  if(!raw->flags.is_set(df::inorganic_flags::SOIL_ANY)) {
    const df::inorganic_raw* fallback=nullptr;
    for(const auto* layer:geo->layers) {
      if(!layer)return {};
      const auto* candidate=df::inorganic_raw::find(layer->mat_index);
      if(!candidate)return {};
      if(candidate->flags.is_set(df::inorganic_flags::SOIL_ANY))fallback=candidate;
    }
    if(fallback)raw=fallback;
  }
  facts.materialObserved=true;facts.soilMaterial=raw->flags.is_set(df::inorganic_flags::SOIL_ANY);
  facts.sand=raw->flags.is_set(df::inorganic_flags::SOIL_SAND);
  for(const auto* id:raw->material.reaction_product.id) {
    if(!id)return {};
    if(*id=="FIRED_MAT")facts.fired=true;
  }
  return paintMaterialEligibility(bank,facts);
}
PaintBaseEligibility observeNativePaintBase(int32_t x,int32_t y,int32_t z) {
  const auto tile=tileAt(blockAt(x,y,z),x,y);
  return {paintBank(tile),paintPond(tile)};
}
PaintWaterEligibility observeNativePaintWater(int32_t x,int32_t y,int32_t z) {
  const auto bank=paintBank(tileAt(blockAt(x,y,z),x,y));
  if(bank!=PaintEligibility::Eligible)return {bank,bank};
  std::array<PaintWaterColumn,8> columns{};
  size_t i=0;
  for(int32_t dy=-1;dy<=1;++dy)for(int32_t dx=-1;dx<=1;++dx) {
    if(!dx && !dy)continue;
    auto& c=columns[i++];
    c.opening=paintWaterOpening(tileAt(blockAt(x+dx,y+dy,z),x+dx,y+dy));
    if(c.opening!=PaintEligibility::Eligible)continue;
    if(const auto* b=blockAt(x+dx,y+dy,z-1)) {
      const auto d=b->designation[(x+dx)&15][(y+dy)&15];
      c.waterObserved=true;c.depth=uint8_t(d.bits.flow_size);
      c.magma=d.bits.liquid_type==df::tile_liquid::Magma;c.salt=d.bits.water_salt;
    }
  }
  return paintWaterEligibility(bank,columns);
}
}
