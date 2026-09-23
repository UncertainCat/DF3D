#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>
#include "../src/effect_material.h"
using namespace df3d::assets;
using df3d_godot::effectMaterial;
TEST_CASE("effect material uses source raw flags without assuming unknown means flesh or stone") {
    AssetIndex index;
    index.inorganics["STEEL"].flags=kMatMetal;
    index.inorganics["GRANITE"].flags=kMatStone;
    CHECK(std::string(effectMaterial(&index,"INORGANIC:STEEL"))=="metal");
    CHECK(std::string(effectMaterial(&index,"INORGANIC:GRANITE"))=="stone");
    CHECK(std::string(effectMaterial(&index,"INORGANIC:UNKNOWN"))=="");
    CHECK(std::string(effectMaterial(nullptr,"INORGANIC:STEEL"))=="");
    CHECK(std::string(effectMaterial(nullptr,"PLANT:OAK:WOOD"))=="wood");
    CHECK(std::string(effectMaterial(nullptr,"CREATURE:DWARF:BONE"))=="bone");
    CHECK(std::string(effectMaterial(nullptr,"CREATURE:DWARF:MUSCLE"))=="flesh");
    CHECK(std::string(effectMaterial(nullptr,"CREATURE:DWARF:BLOOD"))=="");
    CHECK(std::string(effectMaterial(nullptr,""))=="");
}
