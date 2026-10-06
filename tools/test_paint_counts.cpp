#include "doctest.h"
#include "../bridge/plugin/paint_counts.h"
#include <set>
namespace area=df3d_area;
using E=area::PaintEligibility;
using Spans=std::vector<area::Span>;

TEST_CASE("Paint counts reproduce captured add and actual-button erase previews") {
  // Native062137 draft-preview-mixed.json/.lua. Geometry is reconstructed from
  // recorded extents and the capture's input coordinates, not product output.
  const Spans nine{{57,170,3},{58,170,3},{59,170,3}};
  const Spans twelve{{57,170,4},{58,170,4},{59,170,4}};
  const Spans eight{{57,172,2},{58,172,2},{59,170,4}};
  const Spans six{{57,173,1},{58,173,1},{59,170,4}};
  const auto check=[](const Spans& draft,const Spans& preview,int32_t painted,int32_t added) {
    std::set<std::pair<int32_t,int32_t>> read;
    const auto result=area::countPaint(draft,preview,192,192,[&](int32_t x,int32_t y) {
      CHECK(read.emplace(x,y).second);return E::Eligible;
    });
    CHECK(result.valid);CHECK(result.painted==painted);CHECK(result.preview==added);
  };
  check(nine,{{59,172,1}},9,0);
  check(nine,{{57,171,3},{58,171,3},{59,171,3}},9,3);
  check(twelve,{{59,173,1}},12,0);
  check(twelve,{{57,170,2},{58,170,2}},12,0);
  check(eight,{{58,171,1}},8,1);
  check(eight,{{57,170,3},{58,170,3}},8,4);
  check(six,{{58,172,1}},6,1);
  check(six,{{59,173,1}},6,0);
}
TEST_CASE("unknown count terms cannot become partial totals or poison the other term") {
  const Spans draft{{1,1,2}},preview{{1,1,3}};
  const auto result=area::countPaint(draft,preview,10,10,[](int32_t x,int32_t) {
    return x==1?E::Unknown:E::Eligible;
  });
  CHECK(result.valid);CHECK(result.painted==-1);CHECK(result.preview==1);
  const auto other=area::countPaint(draft,preview,10,10,[](int32_t x,int32_t) {
    return x==3?E::Unknown:E::Ineligible;
  });
  CHECK(other.valid);CHECK(other.painted==0);CHECK(other.preview==-1);
  const auto malformed=area::countPaint({},{{1,1,1}},10,10,[](int32_t,int32_t) {return E(255);});
  CHECK(malformed.valid);CHECK(malformed.painted==0);CHECK(malformed.preview==-1);
}
TEST_CASE("invalid selection geometry never invokes native observations") {
  const std::vector<Spans> invalid={{{0,-1,1}},{{-1,0,1}},{{0,0,0}},{{0,0,-1}},
    {{0,9,2}},{{10,0,1}},{{1,2,2},{1,3,1}},{{2,0,1},{1,0,1}},
    {{0,INT32_MAX,INT32_MAX}}};
  for(const auto& spans:invalid)for(bool draft:{false,true}) {
    int reads=0;
    const auto result=area::countPaint(draft?spans:Spans{},draft?Spans{}:spans,10,10,
      [&](int32_t,int32_t) {++reads;return E::Eligible;});
    CHECK_FALSE(result.valid);CHECK(result.painted==-1);CHECK(result.preview==-1);CHECK(reads==0);
  }
}
TEST_CASE("count query limits bound each geometry independently of hover distance") {
  const auto observe=[](int32_t,int32_t){return E::Eligible;};
  CHECK(area::countPaint({{0,0,1}},{{511,511,1}},512,512,observe).preview==1);
  CHECK_FALSE(area::countPaint({{0,0,257}},{},512,512,observe).valid);
  CHECK_FALSE(area::countPaint({{0,0,1},{256,0,1}},{},512,512,observe).valid);
  CHECK_FALSE(area::countPaint({{0,0,256},{128,0,256}},{},512,512,observe).valid);
  Spans full;
  for(int32_t y=0;y<128;++y)full.push_back({y,0,256});
  const auto maximum=area::countPaint(full,full,512,512,observe);
  CHECK(maximum.valid);CHECK(maximum.painted==32768);CHECK(maximum.preview==0);
  full.push_back({128,0,1});
  CHECK_FALSE(area::countPaint(full,{},512,512,observe).valid);
  const auto empty=area::countPaint({},{},512,512,observe);
  CHECK(empty.valid);CHECK(empty.painted==0);CHECK(empty.preview==0);
}
