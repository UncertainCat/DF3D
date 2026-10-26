#include "../bridge/plugin/area_links.h"
#include "doctest.h"
#include "../bridge/plugin/area_geometry.h"
#include <array>
namespace area=df3d_area;

TEST_CASE("location membership prepares sorted relationships before either endpoint changes") {
  std::vector<int32_t> previous{9,6,4,6},next{10,2,6,6};
  const auto beforePrevious=previous,beforeNext=next;
  auto plan=area::prepareLocationMembership(&previous,&next,6);
  CHECK(plan.removePrevious);CHECK(plan.assignNext);
  CHECK(plan.previous==std::vector<int32_t>{4,9});CHECK(plan.next==std::vector<int32_t>{2,6,10});
  CHECK(previous==beforePrevious);CHECK(next==beforeNext);
  plan=area::prepareLocationMembership(&next,&next,6);
  CHECK_FALSE(plan.removePrevious);CHECK(plan.assignNext);
  CHECK(plan.next==std::vector<int32_t>{2,6,10});CHECK(next==beforeNext);
  plan=area::prepareLocationMembership(&previous,nullptr,6);
  CHECK(plan.removePrevious);CHECK_FALSE(plan.assignNext);CHECK(plan.previous==std::vector<int32_t>{4,9});
  plan=area::prepareLocationMembership(nullptr,&next,7);
  CHECK_FALSE(plan.removePrevious);CHECK(plan.next==std::vector<int32_t>{2,6,6,7,10});
  plan=area::prepareLocationMembership(nullptr,nullptr,6);
  CHECK_FALSE(plan.removePrevious);CHECK_FALSE(plan.assignNext);
  previous.assign(5000,6);next.clear();
  plan=area::prepareLocationMembership(&previous,&next,6);
  CHECK(plan.previous.empty());CHECK(plan.next==std::vector<int32_t>{6});CHECK(previous.size()==5000);
}

TEST_CASE("filtered location membership copies preserve other identities") {
  const std::vector<int32_t> source{7,9,7,4,7};
  CHECK(area::withoutValue(source,int32_t(7),1)==std::vector<int32_t>{9,4});
  CHECK(area::withoutValue(source,int32_t(8))==source);
  CHECK(source==std::vector<int32_t>{7,9,7,4,7});
  CHECK(area::withoutValue(std::vector<int32_t>{7,7},int32_t(7)).empty());
}

TEST_CASE("area revision hashing keeps integer bits and a nonzero signed range") {
  area::Revision empty;
  CHECK(empty.finish()==0x4bf29ce484222325ULL);
  area::Revision a,b;a.add(int64_t(-1));b.add(UINT64_MAX);CHECK(a.bits==b.bits);
  a.add(uint64_t(9007199254740993ULL));b.add(uint64_t(9007199254740992ULL));CHECK(a.finish()!=b.finish());
  CHECK(area::Revision::normalize(0)==1);CHECK(area::Revision::normalize(1ULL<<63)==1);
  CHECK(area::Revision::normalize(UINT64_MAX)==INT64_MAX);
  area::Revision one;one.add(uint64_t(1));CHECK(one.bits==0x89cd31291d2aefa4ULL);
  CHECK(one.finish()==0x09cd31291d2aefa4ULL);
}

TEST_CASE("area raw cap counts the complete backing inventory without overflow") {
  std::array<size_t,78> counts{};
  counts[0]=32768;counts[77]=32768;
  auto total=area::settingsRawTotal(counts);
  CHECK(total.valid);CHECK(total.count==65536);
  counts[39]=1;CHECK_FALSE(area::settingsRawTotal(counts).valid);
  counts={};counts[77]=65537;CHECK_FALSE(area::settingsRawTotal(counts).valid);
  counts[77]=SIZE_MAX;CHECK_FALSE(area::settingsRawTotal(counts).valid);
  counts={};total=area::settingsRawTotal(counts);CHECK(total.valid);CHECK(total.count==0);
}


TEST_CASE("fixed area settings write only selected qualities and switches") {
  std::array<bool,7> quality{{false,true,false,true,false,true,false}};
  const std::array<uint8_t,7> members{{1,1,0,0,0,0,1}},allowed{{1,0,1,1,1,1,1}};
  auto result=area::fillFixedSettings(quality.data(),quality.size(),members,allowed,true,2);
  REQUIRE(result.error==area::Error::None);CHECK(result.steps==2);CHECK_FALSE(result.resized);
  CHECK(quality==std::array<bool,7>{{true,true,false,true,false,true,true}});
  result=area::fillFixedSettings(quality.data(),quality.size(),members,allowed,false,2);
  REQUIRE(result.error==area::Error::None);
  CHECK(quality==std::array<bool,7>{{false,true,false,true,false,true,false}});
  const auto before=quality;
  CHECK(area::fillFixedSettings(quality.data(),7,members,allowed,true,1).error==area::Error::Budget);
  CHECK(quality==before);
  for(size_t size:{size_t(0),size_t(6),size_t(8)}) {
    const std::vector<uint8_t> malformed(size,1);
    CHECK(area::fillFixedSettings(quality.data(),7,malformed,allowed,true,2).error==area::Error::InvalidMask);
    CHECK(area::fillFixedSettings(quality.data(),7,members,malformed,true,2).error==area::Error::InvalidMask);
    CHECK(quality==before);
  }
  CHECK(area::fillFixedSettings(static_cast<bool*>(nullptr),7,members,allowed,true,2).error==area::Error::InvalidMask);
  // Guards beside a scalar catch an accidental vector-style resize or overrun.
  std::array<bool,3> switches{{true,false,true}};
  const std::array<uint8_t,1> yes{{1}},no{{0}};
  REQUIRE(area::fillFixedSettings(&switches[1],1,yes,yes,true,2).error==area::Error::None);
  CHECK(switches==std::array<bool,3>{{true,true,true}});
  REQUIRE(area::fillFixedSettings(&switches[1],1,no,yes,false,2).error==area::Error::None);
  CHECK(switches[1]);
  REQUIRE(area::fillFixedSettings(&switches[1],1,yes,no,false,2).error==area::Error::None);
  CHECK(switches[1]);
  REQUIRE(area::fillFixedSettings(&switches[1],1,yes,yes,false,2).error==area::Error::None);
  CHECK(switches==std::array<bool,3>{{true,false,true}});
}

TEST_CASE("area settings fill preserves native storage and respects masks and budget") {
  std::vector<char> values{0,0,1,0};
  const std::vector<uint8_t> members{1,1,0,0},allowed{1,0,1,0};
  auto r=area::fillSettings(values,4,members,allowed,true,2);
  CHECK(r.error==area::Error::None);CHECK_FALSE(r.resized);CHECK(r.steps==2);
  CHECK(values==std::vector<char>{1,0,1,0}); // disallowed entries unchanged without resize
  values={1,0};r=area::fillSettings(values,4,members,allowed,false,2);
  CHECK(r.error==area::Error::InvalidMask);CHECK_FALSE(r.resized);CHECK(values==std::vector<char>{1,0});
  values={1,1,1,1,1};r=area::fillSettings(values,4,members,allowed,false,2);
  CHECK(r.error==area::Error::InvalidMask);CHECK_FALSE(r.resized);CHECK(values==std::vector<char>{1,1,1,1,1});
  values.resize(4);
  const auto before=values;
  CHECK(area::fillSettings(values,4,members,allowed,true,1).error==area::Error::Budget);CHECK(values==before);
  CHECK(area::fillSettings(values,3,members,allowed,true,20).error==area::Error::InvalidMask);CHECK(values==before);
  std::vector<uint8_t> large(65536,1);std::vector<char> native(65536,0);
  r=area::fillSettings(native,65536,large,large,true,257);
  CHECK(r.error==area::Error::None);CHECK(r.steps==257);CHECK(native.size()==65536);CHECK(native.back()==1);
  CHECK(area::fillSettings(native,65537,large,large,false,1536).error==area::Error::TooManyRaws);
  CHECK(native.front()==1);CHECK(native.back()==1);
}

TEST_CASE("area paint preserves holes and counts overlapping span effects once") {
  const area::Bounds before{10,20,2,2};const std::vector<uint8_t> existing{1,0,0,1};
  auto p=area::paint(before,existing,std::vector<area::Span>{{20,11,2},{20,11,2}},1);
  REQUIRE(p.error==area::Error::None);CHECK(p.bounds.x==10);CHECK(p.bounds.y==20);
  CHECK(p.bounds.width==3);CHECK(p.bounds.height==2);CHECK(p.extents==std::vector<uint8_t>{1,1,1,0,1,0});
  CHECK(p.tiles==4);CHECK(p.added==2);CHECK(p.erased==0);CHECK(p.requested==4);CHECK(p.steps==8);
  auto erase=area::paint(p.bounds,p.extents,std::vector<area::Span>{{20,11,2},{20,11,2},{30,30,1}},2);
  REQUIRE(erase.error==area::Error::None);CHECK(erase.bounds.width==3);CHECK(erase.tiles==2);CHECK(erase.erased==2);
  CHECK(erase.extents==std::vector<uint8_t>{1,0,0,0,1,0});CHECK(existing==std::vector<uint8_t>{1,0,0,1});
  auto empty=area::paint(before,existing,std::vector<area::Span>{{20,10,2},{21,10,2}},2);
  CHECK(empty.error==area::Error::Empty);CHECK(empty.tiles==0);CHECK(empty.erased==2);
  CHECK(existing==std::vector<uint8_t>{1,0,0,1});
}

TEST_CASE("area paint bounds inputs before allocation or native mutation") {
  const std::vector<uint8_t> none;const area::Bounds empty;
  CHECK(area::paint(empty,none,std::vector<area::Span>{{0,0,384}},1).error==area::Error::TooLarge);
  auto p=area::paint(empty,none,std::vector<area::Span>{{0,0,256},{1,0,128}},1);
  CHECK(p.error==area::Error::None);CHECK(p.requested==384);CHECK(p.tiles==384);CHECK(p.bounds.width==256);
  CHECK(area::paint(empty,none,std::vector<area::Span>{{0,0,256},{1,0,129}},1).error==area::Error::None);
  CHECK(area::paint(empty,none,std::vector<area::Span>(area::kMaxSpans+1,{0,0,1}),1).error==area::Error::TooManySpans);
  CHECK(area::paint(empty,none,std::vector<area::Span>(128,{0,0,1}),1).error==area::Error::None);
  for(const auto span:std::vector<area::Span>{{-1,0,1},{0,-1,1},{32768,0,1},{0,32767,2},{0,0,0}})
    CHECK(area::paint(empty,none,std::vector<area::Span>{span},1).error==area::Error::InvalidSpan);
  CHECK(area::paint(empty,none,std::vector<area::Span>{{32767,32767,1}},1).error==area::Error::None);
  CHECK(area::paint(empty,none,std::vector<area::Span>{{0,0,1},{127,255,1}},1).error==area::Error::None);
  CHECK(area::paint(empty,none,std::vector<area::Span>{{0,0,1},{128,255,1}},1).error==area::Error::TooLarge);
  CHECK(area::paint(empty,none,std::vector<area::Span>{{0,0,1},{0,256,1}},1).error==area::Error::TooLarge);
  const area::Bounds full{0,0,256,128};const std::vector<uint8_t> filled(32768,1);
  std::vector<area::Span> spans;for(int y=0;y<128;++y)spans.push_back({y,0,3});
  p=area::paint(full,filled,spans,2);CHECK(p.error==area::Error::None);CHECK(p.steps==641);CHECK(p.erased==384);
  CHECK(p.tiles==32768-384);CHECK(area::paint(full,filled,spans,2,640).error==area::Error::Budget);
  CHECK(area::paint(full,filled,spans,2,0).steps==0);CHECK(filled.front()==1);
  CHECK(area::paint({0,0,1,1},std::vector<uint8_t>{2},std::vector<area::Span>{{0,0,1}},1).error==area::Error::InvalidExtent);
  CHECK(area::paint({0,0,-1,1},none,std::vector<area::Span>{{0,0,1}},1).error==area::Error::InvalidExtent);
}

TEST_CASE("one paint plans a full supported footprint and refuses before mutation") {
  const area::Bounds empty{};const std::vector<uint8_t> none;
  std::vector<area::Span> rectangle;
  for(int y=0;y<128;++y)rectangle.push_back({y,0,256});
  auto full=area::paint(empty,none,rectangle,1);
  REQUIRE(full.error==area::Error::None);CHECK(full.tiles==32768);
  CHECK(full.extents.size()==32768);CHECK(full.requested==32768);
  rectangle.push_back({128,0,1});
  CHECK(area::paint(empty,none,rectangle,1).error==area::Error::TooManyTiles);
  std::vector<area::Span> sparse;
  for(int y=0;y<128;++y)for(int x=0;x<256;x+=2)sparse.push_back({y,x,1});
  auto holes=area::paint(empty,none,sparse,1);
  REQUIRE(holes.error==area::Error::None);CHECK(holes.tiles==16384);
  const auto source=full.extents;
  int visited=0;
  auto rejected=area::paint(full.bounds,source,sparse,2,UINT32_MAX,
      [&](int32_t,int32_t,int64_t,int64_t){return ++visited<16384;});
  CHECK(rejected.error==area::Error::InvalidSite);CHECK(visited==16384);
  CHECK(source==full.extents);CHECK(source.front()==1);CHECK(source.back()==1);
  auto erased=area::paint(full.bounds,source,sparse,2);
  REQUIRE(erased.error==area::Error::None);CHECK(erased.erased==16384);CHECK(erased.tiles==16384);
}

TEST_CASE("native073705 zone erase retains an empty mask for repaint") {
  const area::Bounds bounds{170,57,3,3};
  const std::vector<uint8_t> source(9,1);
  const std::vector<area::Span> spans{{57,170,3},{58,170,3},{59,170,3}};
  const auto denied=area::paint(bounds,source,spans,2);
  CHECK(denied.error==area::Error::Empty);
  auto erased=area::paint(bounds,source,spans,2,UINT32_MAX,area::AllowPaintTile{},true);
  REQUIRE(erased.error==area::Error::None);
  CHECK(erased.tiles==0);CHECK(erased.erased==9);
  CHECK(erased.bounds.x==170);CHECK(erased.bounds.y==57);
  CHECK(erased.bounds.width==3);CHECK(erased.bounds.height==3);
  CHECK(erased.extents==std::vector<uint8_t>(9,0));CHECK(source==std::vector<uint8_t>(9,1));
  auto added=area::paint(erased.bounds,erased.extents,std::vector<area::Span>{{57,170,1}},1,UINT32_MAX,area::AllowPaintTile{},true);
  REQUIRE(added.error==area::Error::None);
  CHECK(added.tiles==1);CHECK(added.added==1);
  CHECK(added.extents==std::vector<uint8_t>{1,0,0,0,0,0,0,0,0});
  const auto rejected=area::paint(bounds,source,spans,2,UINT32_MAX,
      [](int32_t,int32_t y,int64_t,int64_t){return y!=58;},true);
  CHECK(rejected.error==area::Error::InvalidSite);CHECK(source==std::vector<uint8_t>(9,1));
}

TEST_CASE("retired replacement paint refuses before visiting or changing cells") {
  const area::Bounds before{10,10,2,2};const std::vector<uint8_t> source(4,1);
  const std::vector<area::Span> desired{{11,10,2},{12,10,2}};
  int visits=0;
  auto plan=area::paint(before,source,desired,3,UINT32_MAX,
      [&](int32_t,int32_t,int64_t,int64_t){++visits;return true;});
  CHECK(plan.error==area::Error::InvalidMode);CHECK(visits==0);
  CHECK(source==std::vector<uint8_t>(4,1));
}

TEST_CASE("native paint transfers its original allocation and preserves raw extents") {
  enum class Extent:int8_t { None=0,Stockpile=1,Wall=2,Interior=3,Boundary=4 };
  using Buffer=area::NativeExtents<Extent>;
  const std::vector<Extent> before{Extent::Wall,Extent::Interior,Extent::Boundary,Extent::None};
  auto plan=area::paint<Buffer>({10,20,2,2},before,std::vector<area::Span>{{21,11,2}},1);
  REQUIRE(plan.error==area::Error::None);
  CHECK(plan.bounds.width==3);CHECK(plan.tiles==5);CHECK(plan.added==2);
  CHECK(plan.extents[0]==Extent::Wall);CHECK(plan.extents[1]==Extent::Interior);
  CHECK(plan.extents[3]==Extent::Boundary);CHECK(plan.extents[4]==Extent::Stockpile);
  CHECK(plan.extents[5]==Extent::Stockpile);CHECK(before[3]==Extent::None);
  auto* allocation=plan.extents.data();
  auto moved=std::move(plan);
  CHECK(moved.extents.data()==allocation);
  CHECK(plan.extents.data()==nullptr);CHECK(plan.extents.size()==0);
  std::unique_ptr<Extent[]> committed(moved.extents.release());
  CHECK(committed.get()==allocation);CHECK(moved.extents.data()==nullptr);CHECK(moved.extents.size()==0);
  auto erased=area::paint<Buffer>({0,0,2,2},before,std::vector<area::Span>{{0,0,1}},2);
  REQUIRE(erased.error==area::Error::None);CHECK(erased.erased==1);CHECK(erased.tiles==2);
  CHECK(erased.extents[0]==Extent::None);CHECK(erased.extents[1]==Extent::Interior);
  for(auto invalid:{static_cast<Extent>(-1),static_cast<Extent>(5)})
    CHECK(area::paint<Buffer>({0,0,1,1},std::vector<Extent>{invalid},std::vector<area::Span>{{0,0,1}},1).error==area::Error::InvalidExtent);
  const std::vector<Extent> full(32768,Extent::Interior);
  std::vector<area::Span> spans;for(int y=0;y<128;++y)spans.push_back({y,0,3});
  auto maximum=area::paint<Buffer>({0,0,256,128},full,spans,2);
  REQUIRE(maximum.error==area::Error::None);CHECK(maximum.steps==641);CHECK(maximum.erased==384);
  CHECK(area::paint<Buffer>({0,0,256,128},full,spans,2,640).error==area::Error::Budget);
}

TEST_CASE("paint site preflight is counted and never changes the source on refusal") {
  const std::vector<uint8_t> source{1,0,0,1};
  std::vector<std::array<int64_t,4>> checked;
  const auto site=[&](int32_t x,int32_t y,int64_t before,int64_t after) {
    checked.push_back({x,y,before,after});return x!=2;
  };
  auto rejected=area::paint({0,0,2,2},source,std::vector<area::Span>{{0,0,3}},1,1536,site);
  CHECK(rejected.error==area::Error::InvalidSite);CHECK(rejected.steps==6);
  CHECK(checked==std::vector<std::array<int64_t,4>>{{0,0,1,1},{1,0,0,1},{2,0,0,1}});
  CHECK(source==std::vector<uint8_t>{1,0,0,1});
  checked.clear();
  auto refusedBudget=area::paint({0,0,2,2},source,std::vector<area::Span>{{0,0,3}},1,5,site);
  CHECK(refusedBudget.error==area::Error::Budget);CHECK(checked.empty());
  // Erase requests outside the current rectangle still receive visibility/site
  // checks, and repeated tiles only produce one change in the commit list.
  checked.clear();
  auto erase=area::paint({0,0,2,2},source,std::vector<area::Span>{{0,0,1},{0,0,1},{2,0,1}},2,1536,site);
  REQUIRE(erase.error==area::Error::None);CHECK(erase.erased==1);
  CHECK(checked==std::vector<std::array<int64_t,4>>{{0,0,1,0},{0,0,0,0},{0,2,0,0}});
  const std::vector<uint8_t> full(32768,1);
  std::vector<area::Span> spans;for(int y=0;y<128;++y)spans.push_back({y,0,3});
  size_t calls=0;
  const auto maximum=area::paint({0,0,256,128},full,spans,2,641,
      [&](int32_t,int32_t,int64_t,int64_t){++calls;return true;});
  CHECK(maximum.error==area::Error::None);CHECK(maximum.steps==641);CHECK(calls==384);
}


TEST_CASE("native assignment reference scan checks every reference and preserves unrelated pointers") {
  struct Ref {bool zone=false;};Ref other,oldZone{true},secondZone{true};
  std::vector<Ref*> refs(256,&other);refs[137]=&oldZone;const auto original=refs;
  auto isZone=[](const Ref* ref){return ref->zone;};
  auto scan=area::scanZoneReferences(refs,isZone,256);
  CHECK(scan.error==area::AssignmentScanError::None);CHECK(scan.steps==256);CHECK(scan.previous==&oldZone);CHECK(refs==original);
  auto limited=area::scanZoneReferences(refs,isZone,255);
  CHECK(limited.error==area::AssignmentScanError::Budget);CHECK(limited.steps==255);CHECK(refs==original);
  refs.push_back(&other);scan=area::scanZoneReferences(refs,isZone,1000);
  CHECK(scan.error==area::AssignmentScanError::Limit);CHECK(scan.steps==0);
  refs=original;refs[138]=&secondZone;scan=area::scanZoneReferences(refs,isZone,256);
  CHECK(scan.error==area::AssignmentScanError::Multiple);CHECK(scan.steps==139);
  refs=original;refs[0]=nullptr;scan=area::scanZoneReferences(refs,isZone,256);
  CHECK(scan.error==area::AssignmentScanError::Invalid);CHECK(scan.steps==1);
  refs.clear();scan=area::scanZoneReferences(refs,isZone,0);
  CHECK(scan.error==area::AssignmentScanError::None);CHECK(scan.previous==nullptr);CHECK(scan.steps==0);
}

TEST_CASE("native cage scan finds all memberships without requiring a containing cage") {
  struct Cage {std::vector<int32_t> assigned_units;};
  Cage first{{7,9,7}},second{{4,7,5}},unrelated{{2,3}};
  std::vector<Cage*> cages{&first,&unrelated,&second};
  const auto originalFirst=first.assigned_units,originalSecond=second.assigned_units;
  auto scan=area::scanAssignedCages(cages,7,11);
  REQUIRE(scan.error==area::AssignmentScanError::None);CHECK(scan.steps==11);CHECK(scan.entries==8);
  CHECK(scan.affected==std::vector<Cage*>{&first,&second});
  CHECK(first.assigned_units==originalFirst);CHECK(second.assigned_units==originalSecond);
  // No cage-item holder is an input: a loose-caged unit's assignments in any
  // built cage are found, while the containing-item reference remains native.
  auto absent=area::scanAssignedCages(cages,99,11);
  CHECK(absent.error==area::AssignmentScanError::None);CHECK(absent.affected.empty());
  auto low=area::scanAssignedCages(cages,7,10);CHECK(low.error==area::AssignmentScanError::Budget);CHECK(low.steps==10);
  CHECK(first.assigned_units==originalFirst);CHECK(second.assigned_units==originalSecond);
}

TEST_CASE("native cage scan enforces aggregate cage and membership bounds before changes") {
  struct Cage {std::vector<int32_t> assigned_units;};
  std::vector<Cage> storage(257);std::vector<Cage*> cages;
  for(int i=0;i<256;++i){storage[i].assigned_units={7};cages.push_back(&storage[i]);}
  auto scan=area::scanAssignedCages(cages,7,512);
  REQUIRE(scan.error==area::AssignmentScanError::None);CHECK(scan.steps==512);CHECK(scan.entries==256);CHECK(scan.affected.size()==256);
  for(const auto* cage:scan.affected)CHECK(cage->assigned_units==std::vector<int32_t>{7});
  CHECK(area::scanAssignedCages(cages,7,511).error==area::AssignmentScanError::Budget);
  cages.push_back(&storage[256]);scan=area::scanAssignedCages(cages,7,1000);
  CHECK(scan.error==area::AssignmentScanError::Limit);CHECK(scan.steps==0);
  cages.pop_back();storage.back().assigned_units={7};storage[255].assigned_units.push_back(8);
  scan=area::scanAssignedCages(cages,7,1000);CHECK(scan.error==area::AssignmentScanError::Limit);
  CHECK(storage[255].assigned_units==std::vector<int32_t>{7,8});
  // A single vector at the aggregate boundary has the same rule.
  storage[0].assigned_units.assign(256,7);cages={&storage[0]};
  CHECK(area::scanAssignedCages(cages,7,257).error==area::AssignmentScanError::None);
  storage[0].assigned_units.push_back(7);CHECK(area::scanAssignedCages(cages,7,1000).error==area::AssignmentScanError::Limit);
  cages={nullptr};CHECK(area::scanAssignedCages(cages,7,1).error==area::AssignmentScanError::Invalid);
  cages.clear();scan=area::scanAssignedCages(cages,7,0);
  CHECK(scan.error==area::AssignmentScanError::None);CHECK(scan.steps==0);CHECK(scan.entries==0);
}

TEST_CASE("stockpile link snapshots and native edits share endpoint validation") {
  struct Endpoint {int32_t id;};
  Endpoint first{1},second{2},negative{-1};
  CHECK(area::validStockpileLinkVector(std::vector<Endpoint*>{&first,&second},3));
  for(auto rows:{std::vector<Endpoint*>{nullptr},std::vector<Endpoint*>{&negative},
      std::vector<Endpoint*>{&first,&first},std::vector<Endpoint*>{&second,&first}})
    CHECK_FALSE(area::validStockpileLinkVector(rows,3));
  CHECK_FALSE(area::validStockpileLinkVector(std::vector<Endpoint*>{&first,&second},2));
  std::vector<Endpoint> storage(1025);std::vector<Endpoint*> rows;
  for(int i=0;i<1025;++i){storage[i].id=i;rows.push_back(&storage[i]);}
  CHECK_FALSE(area::validStockpileLinkVector(rows,2000));
  rows.pop_back();CHECK(area::validStockpileLinkVector(rows,2000));
}
