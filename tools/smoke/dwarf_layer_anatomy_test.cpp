#include "doctest.h"
#include "../../bridge/plugin/dwarf_layer_anatomy.h"
#include <vector>
using namespace df3d_appearance::anatomy;
TEST_CASE("missing ancestors suppress the correct connected map regions") {
    std::vector<Part> p={{"UB",-1,false},{"LUA",0,false},{"LLA",1,false},{"LH",2,false},
                        {"RUA",0,false},{"RH",4,false},{"LUL",0,false},{"LLL",6,false},{"LF",7,false}};
    auto mask=[&]{return missingRegions(p.size(),[&](size_t i){return p[i];});};
    CHECK(mask()==0);
    p[1].missing=true;
    CHECK(mask()==(bit(Region::LeftArm)|bit(Region::LeftHand)));
    p[1].missing=false;p[2].missing=true;
    CHECK(mask()==bit(Region::LeftHand)); // shoulder remains after lower-arm loss
    p[2].missing=false;p[8].missing=true;
    CHECK(mask()==bit(Region::LeftFoot));
    p[8].missing=false;p[7].missing=true;
    CHECK(mask()==(bit(Region::LeftLeg)|bit(Region::LeftFoot)));
    p[7].missing=false;
    CHECK(mask()==0); // restored anatomy recovers the original stack
    p[0].parent=3;
    CHECK(mask()==0); // cycle is bounded
    p[0].parent=999;
    CHECK(mask()==0); // invalid parent is bounded
}
TEST_CASE("named dwarf art and equipment share regions without eating unrelated layers") {
    CHECK(region("DWARF_BODY","LIGHT_LEFT_HAND")==Region::LeftHand);
    CHECK(region("DWARF_BODY","Z_RIGHT_SHOULDER_M")==Region::RightArm);
    CHECK(region("DWARF_WEARABLES","CLOTHING_LA_PLATE_STANDARD")==Region::LeftArm);
    CHECK(region("WIELDABLES","CLOTHING_RH_SWORD_SHORT")==Region::RightHand);
    CHECK(region("DWARF_WEARABLES","CLOTHING_LF_HIGH_STANDARD")==Region::LeftFoot);
    CHECK(region("DWARF_WEARABLES","CLOTHING_CAPE_DEFAULT")==Region::None);
    CHECK(region("DWARF_WEARABLES","CLOTHING_WAIST_ROBE_DEFAULT")==Region::None);
    CHECK(region("DWARF_WEARABLES","CLOTHING_CAP_DEFAULT")==Region::Head);
    CHECK(region("DWARF_BODY","LIGHT_FACE_M2")==Region::Head);
    CHECK(region("DWARF_HAIR","BEARD_MID_COMBED_BLOND")==Region::Head);
    CHECK(region("DWARF_HAIR","LONG_PONY_TAIL_BLOND")==Region::Head);
    CHECK(region("DWARF_HAIR","STUBBLE_BLACK")==Region::Head);
    CHECK(region("PORTRAIT_DWARF_BODY","LIGHT_LEFT_HAND")==Region::None);
    CHECK(region("OTHER_BODY","LIGHT_LEFT_HAND")==Region::None);
    CHECK(region("DWARF_BODY","LIGHT_LEFT_HANDMADE")==Region::None);
    CHECK(region("DWARF_BODY","LIGHT_BABY")==Region::None);
    CHECK(hideNamedLayer(bit(Region::LeftHand),"DWARF_BODY","LIGHT_LEFT_HAND",false));
    CHECK_FALSE(hideNamedLayer(bit(Region::LeftHand),"DWARF_BODY","LIGHT_LEFT_HAND",true));
    CHECK_FALSE(hideNamedLayer(bit(Region::LeftHand),"DWARF_BODY","LIGHT_RIGHT_HAND",false));
    CHECK_FALSE(hideNamedLayer(0,"DWARF_BODY","LIGHT_LEFT_HAND",false));
}
TEST_CASE("appearance invalidation detects missing part identity and restoration") {
    struct Status {struct {bool missing=false;} bits;};
    std::vector<Status> p(5);
    auto hash=[&]{uint32_t h=2166136261u;fingerprintMissing(p,[&](uint32_t v){h=(h^v)*16777619u;});return h;};
    const auto intact=hash();p[1].bits.missing=true;const auto left=hash();
    CHECK(left!=intact);p[1].bits.missing=false;p[2].bits.missing=true;
    CHECK(hash()!=left);p[2].bits.missing=false;CHECK(hash()==intact);
}
