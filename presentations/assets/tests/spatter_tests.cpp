#include <doctest.h>
#include "df3d_assets/asset_index.h"
#include "df3d_assets/ground_spatter.h"
#include "df3d_assets/raw_tokens.h"
using namespace df3d::assets;
TEST_CASE("ground deposits accumulate before resolving a single stable pile") {
  SpatterPiles split,combined;
  split.add("blood",60);split.add("blood",60);split.add("slime",100);
  combined.add("blood",120);combined.add("slime",100);
  CHECK(split.dominant().family=="blood");
  CHECK(split.dominant().amount==combined.dominant().amount);
  CHECK(spatterFull(split.dominant().density()));
  split.add("",255);split.add("unknown",0);
  CHECK(split.dominant().family=="blood");
  SpatterPiles reversed,tie;
  reversed.add("slime",100);reversed.add("blood",100);
  tie.add("blood",100);tie.add("slime",100);
  CHECK(reversed.dominant().family==tie.dominant().family);
  SpatterPiles saturated;
  for(int i=0;i<400;++i) saturated.add("blood",255);
  for(int i=0;i<401;++i) saturated.add("slime",255);
  CHECK(saturated.dominant().family=="slime");
  CHECK(saturated.dominant().amount==102255);
  CHECK(saturated.dominant().density()==255);
  CHECK(SpatterPiles{}.dominant().family.empty());
}
TEST_CASE("spatter art selection is stable connected and material specific") {
  CHECK(spatterFamily("CREATURE:DWARF:BLOOD")=="SPATTER_BLOOD_RED");
  CHECK(spatterFamily("CREATURE:SPIDER:ICHOR")=="SPATTER_BLOOD_ICHOR");
  CHECK(spatterFamily("INORGANIC:GRANITE").empty());
  CHECK(spatterVariant(100,0,0,0)=="FULL_ISOLATED");
  CHECK(spatterVariant(100,3,0,0)=="FULL_NS");
  CHECK(spatterVariant(100,12,0,0)=="FULL_WE");
  CHECK(spatterVariant(255,15,0,0)=="FULL_NSWE_A");
  CHECK(spatterVariant(1,0,0,0)=="PARTIAL_1A");
  CHECK(spatterVariant(99,0,0,0)=="PARTIAL_4A");
  CHECK(spatterVariant(50,0,31,42)==spatterVariant(50,15,31,42));
}
TEST_CASE("native symbolic spatter variants survive parsing and index cache") {
  AssetIndex index;
  index.buildId="test";
  ingestRawText(index,"[OBJECT:GRAPHICS]\n[TILE_PAGE:BLOOD]\n[FILE:blood.png]\n[TILE_DIM:32:32]\n[PAGE_DIM_PIXELS:256:160]\n[TILE_GRAPHICS:BLOOD:1:0:SPATTER_BLOOD_RED:FULL_ISOLATED]\n[TILE_GRAPHICS:BLOOD:4:3:SPATTER_BLOOD_RED:PARTIAL_1A]","test","spatters",nullptr);
  finalizeIndex(index);
  const auto* isolated=index.tile("SPATTER_BLOOD_RED:FULL_ISOLATED");
  REQUIRE(isolated); CHECK(isolated->x==1);CHECK(isolated->y==0);
  const auto* partial=index.tile("SPATTER_BLOOD_RED:PARTIAL_1A");
  REQUIRE(partial);CHECK(partial->x==4);CHECK(partial->y==3);
  AssetIndex cached;std::string error;
  REQUIRE(deserializeIndex(serializeIndex(index),cached,error));
  REQUIRE(cached.tile("SPATTER_BLOOD_RED:PARTIAL_1A"));
  CHECK(*cached.tile("SPATTER_BLOOD_RED:PARTIAL_1A")==*partial);
}
TEST_CASE("creature liquid materials choose blood family from installed descriptors") {
  AssetIndex index;index.buildId="test";
  ingestRawText(index,"[OBJECT:MATERIAL_TEMPLATE][MATERIAL_TEMPLATE:BLOOD_TEMPLATE][BLOOD_MAP_DESCRIPTOR][STATE_COLOR:ALL:RED][MATERIAL_TEMPLATE:ICHOR_TEMPLATE][ICHOR_MAP_DESCRIPTOR][STATE_COLOR:ALL:WHITE]","","templates",nullptr);
  ingestRawText(index,"[OBJECT:CREATURE][CREATURE:MONSTER][USE_MATERIAL_TEMPLATE:BLOOD:BLOOD_TEMPLATE][SELECT_MATERIAL:BLOOD][STATE_COLOR:LIQUID:CYAN][CREATURE:CHILD][COPY_TAGS_FROM:MONSTER][CREATURE:BUG][USE_MATERIAL_TEMPLATE:BLOOD:ICHOR_TEMPLATE][CREATURE:PINK][USE_MATERIAL_TEMPLATE:BLOOD:BLOOD_TEMPLATE][STATE_COLOR:LIQUID:MAGENTA]","","creatures",nullptr);
  index.colors["RED"]={150,0,24};index.colors["CYAN"]={0,255,255};index.colors["MAGENTA"]={255,0,255};
  CHECK(index.materialSpatterFamily("CREATURE:MONSTER:BLOOD")=="SPATTER_BLOOD_CYAN");
  CHECK(index.materialSpatterFamily("CREATURE:MONSTER:BLOOD",false)=="SPATTER_BLOOD_RED");
  CHECK(index.materialSpatterFamily("CREATURE:CHILD:BLOOD")=="SPATTER_BLOOD_CYAN");
  CHECK(index.materialSpatterFamily("CREATURE:BUG:BLOOD")=="SPATTER_BLOOD_ICHOR");
  CHECK(index.materialSpatterFamily("CREATURE:PINK:BLOOD")=="SPATTER_BLOOD_MAGENTA");
  AssetIndex cached;std::string error;REQUIRE_MESSAGE(deserializeIndex(serializeIndex(index),cached,error),error);
  CHECK(cached.materialSpatterFamily("CREATURE:CHILD:BLOOD")=="SPATTER_BLOOD_CYAN");
}
