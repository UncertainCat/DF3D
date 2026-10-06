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

TEST_CASE("unit assignment filtered copies preserve other identities within the handler budget") {
  const std::vector<int32_t> source{7,9,7,4,7};
  CHECK(area::withoutValue(source,int32_t(7),1)==std::vector<int32_t>{9,4});
  CHECK(area::withoutValue(source,int32_t(8))==source);
  CHECK(source==std::vector<int32_t>{7,9,7,4,7});
  CHECK(area::withoutValue(std::vector<int32_t>{7,7},int32_t(7)).empty());
  const uint32_t scan=1+256+256+256; // base, references, cages, total cage entries
  const auto prepared=area::assignmentPreparationSteps(256,4096,4096,256,256);
  CHECK(prepared==297);
  // Both snapshots, handler checks and a 65536-location lookup still fit. This
  // catches accidental extra full-vector passes in the native preparation.
  CHECK(10+282+154+19+scan+prepared<=1536);
}

TEST_CASE("area links commit both sorted endpoints within caps and budget") {
  struct Node {int32_t id;};Node a{1},b{2},c{3},d{4};
  std::vector<Node*> first{&a,&c},second{&a,&d};
  const auto beforeFirst=first,beforeSecond=second;
  auto r=area::editLinks(first,second,&b,&c,false,30);
  CHECK(r.error==area::LinkError::Budget);CHECK(first==beforeFirst);CHECK(second==beforeSecond);
  r=area::editLinks(first,second,&b,&c,false,31);
  REQUIRE(r.error==area::LinkError::None);CHECK(r.steps==31);
  CHECK(first==std::vector<Node*>{&a,&b,&c});CHECK(second==std::vector<Node*>{&a,&c,&d});
  REQUIRE(area::editLinks(first,second,&b,&c,false,31).error==area::LinkError::None);
  CHECK(first.size()==3);CHECK(second.size()==3);
  REQUIRE(area::editLinks(first,second,&b,&c,true,31).error==area::LinkError::None);
  CHECK(first==beforeFirst);CHECK(second==beforeSecond);
  // Repair a missing reverse end and permit idempotent unlink.
  second.clear();REQUIRE(area::editLinks(first,second,&c,&a,false,31).error==area::LinkError::None);
  CHECK(first==beforeFirst);CHECK(second==std::vector<Node*>{&a});
  REQUIRE(area::editLinks(first,second,&b,&d,true,31).error==area::LinkError::None);
  std::vector<Node> nodes;nodes.reserve(1025);for(int i=0;i<1025;++i)nodes.push_back({i});
  first.clear();second.clear();for(int i=0;i<1024;++i)first.push_back(&nodes[i]);
  r=area::editLinks(first,second,&nodes[1024],&a,false,1536);
  CHECK(r.error==area::LinkError::Limit);CHECK(first.size()==1024);CHECK(second.empty());
  r=area::editLinks(second,first,&a,&nodes[1024],false,1536);
  CHECK(r.error==area::LinkError::Limit);CHECK(first.size()==1024);CHECK(second.empty());
  REQUIRE(area::editLinks(first,second,&nodes[1023],&a,false,1536).error==area::LinkError::None);
  CHECK(first.size()==1024);CHECK(second.size()==1);
  REQUIRE(area::editLinks(first,second,&nodes[1023],&a,true,1536).error==area::LinkError::None);
  REQUIRE(area::editLinks(first,second,&nodes[1024],&a,false,1536).error==area::LinkError::None);
  CHECK(first.size()==1024);CHECK(first.back()==&nodes[1024]);
  second={nullptr};const auto saved=first;
  CHECK(area::editLinks(first,second,&a,&b,false,1536).error==area::LinkError::Invalid);CHECK(first==saved);
  second={&b,&a};CHECK(area::editLinks(first,second,&a,&b,true,1536).error==area::LinkError::Invalid);CHECK(first==saved);
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

TEST_CASE("classified settings validate membership before bounded native fills") {
  const std::array<uint16_t,5> parts{{area::Gem,area::Metal,area::Stone,0,area::Gem}};
  size_t visits=0;
  const auto classify=[&](size_t i){++visits;return parts[i];};
  std::vector<char> values{0,1};const auto before=values;
  auto result=area::fillClassifiedSettings(values,5,area::Gem,-1,classify,true,2);
  CHECK(result.error==area::Error::Budget);CHECK(values==before);CHECK(visits==0);
  result=area::fillClassifiedSettings(values,5,area::Gem,-1,classify,true,3);
  REQUIRE(result.error==area::Error::None);CHECK(result.steps==3);CHECK(result.resized);
  CHECK(visits==5);CHECK(values==std::vector<char>{1,1,0,1,1});
  // Switching one partition does not change another; no shrink or rewriting
  // disallowed entries when already sized. A raw-index row must be a member.
  values={1,1,1,0,1,9};visits=0;
  result=area::fillClassifiedSettings(values,5,area::Metal|area::Stone,-1,classify,false,3);
  REQUIRE(result.error==area::Error::None);CHECK_FALSE(result.resized);
  CHECK(values==std::vector<char>{1,0,0,0,1,9});CHECK(visits==5);
  const auto saved=values;
  for(int32_t row:{-2,5}) {
    visits=0;result=area::fillClassifiedSettings(values,5,0,row,classify,true,3);
    CHECK(result.error==area::Error::InvalidMask);CHECK(values==saved);CHECK(visits==0);
  }
  for(int32_t row:{1,3}) {
    result=area::fillClassifiedSettings(values,5,area::Gem,row,classify,true,3);
    CHECK(result.error==area::Error::InvalidMask);CHECK(values==saved);CHECK(result.steps==2);
  }
  REQUIRE(area::fillClassifiedSettings(values,5,area::Gem,4,classify,false,3).error==area::Error::None);
  CHECK(values==std::vector<char>{1,0,0,0,0,9});
  visits=0;values.clear();
  const auto all=[&](size_t){++visits;return uint16_t(area::Any);};
  result=area::fillClassifiedSettings(values,65536,0,-1,all,true,512);
  CHECK(result.error==area::Error::Budget);CHECK(visits==0);CHECK(values.empty());
  result=area::fillClassifiedSettings(values,65536,0,-1,all,true,513);
  REQUIRE(result.error==area::Error::None);CHECK(result.steps==513);CHECK(visits==65536);
  CHECK(values.size()==65536);CHECK(values.front()==1);CHECK(values.back()==1);
  visits=0;result=area::fillClassifiedSettings(values,65537,0,-1,all,false,1536);
  CHECK(result.error==area::Error::TooManyRaws);CHECK(visits==0);CHECK(values.back()==1);
  result=area::fillClassifiedSettings(values,0,0,-1,all,false,1);
  CHECK(result.error==area::Error::None);CHECK(result.steps==1);CHECK(values.size()==65536);
  // ceil contributions for 77 raw vectors are <=256+76 at total65536.
  const uint32_t allFields=77+2*(256+76)+29*2;
  CHECK(allFields==799);CHECK(10+282+108+107+allFields+17+154==1477);
}

TEST_CASE("preset vector transactions restore original buffers or commit replacement filters") {
  std::vector<char> first{1,2,3},second(100000,7),unused{9};
  const auto* firstBuffer=first.data();const auto* secondBuffer=second.data();
  std::array<std::vector<char>*,3> fields{{&first,&second,nullptr}};
  {
    area::PresetVectors<std::vector<char>,3> guard(fields);
    CHECK(first.empty());CHECK(second.empty());CHECK(unused==std::vector<char>{9});
    first={4,5};second={6};
  }
  CHECK(first==std::vector<char>{1,2,3});CHECK(first.data()==firstBuffer);
  CHECK(second.size()==100000);CHECK(second.data()==secondBuffer);CHECK(second.back()==7);
  try {
    area::PresetVectors<std::vector<char>,3> guard(fields);
    first={8};throw 7;
  } catch(int value) {CHECK(value==7);}
  CHECK(first.data()==firstBuffer);CHECK(first==std::vector<char>{1,2,3});
  {
    area::PresetVectors<std::vector<char>,3> guard(fields);
    first={4,5};second={6};guard.commit();
  }
  CHECK(first==std::vector<char>{4,5});CHECK(second==std::vector<char>{6});
  // None commits cleared vectors, without traversing oversized stored tails.
  {area::PresetVectors<std::vector<char>,3> guard(fields);guard.commit();}
  CHECK(first.empty());CHECK(second.empty());CHECK(unused==std::vector<char>{9});
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

TEST_CASE("area settings fill respects shared members resize and budget") {
  std::vector<char> values{0,0,1,0};
  const std::vector<uint8_t> members{1,1,0,0},allowed{1,0,1,0};
  auto r=area::fillSettings(values,4,members,allowed,true,2);
  CHECK(r.error==area::Error::None);CHECK_FALSE(r.resized);CHECK(r.steps==2);
  CHECK(values==std::vector<char>{1,0,1,0}); // disallowed entries unchanged without resize
  values={1,0};r=area::fillSettings(values,4,members,allowed,false,2);
  CHECK(r.error==area::Error::None);CHECK(r.resized);CHECK(values==std::vector<char>{0,1,0,1});
  values={1,1,1,1,1};r=area::fillSettings(values,4,members,allowed,false,2);
  CHECK_FALSE(r.resized);CHECK(values==std::vector<char>{0,1,1,1,1}); // retained tail
  const auto before=values;
  CHECK(area::fillSettings(values,4,members,allowed,true,1).error==area::Error::Budget);CHECK(values==before);
  CHECK(area::fillSettings(values,3,members,allowed,true,20).error==area::Error::InvalidMask);CHECK(values==before);
  std::vector<uint8_t> large(65536,1);std::vector<char> native;
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

TEST_CASE("replacement paint plans additions and removals as one private edit") {
  const area::Bounds before{10,10,2,2};const std::vector<uint8_t> source(4,1);
  const std::vector<area::Span> desired{{11,10,2},{12,10,2}};
  int changes=0;
  auto plan=area::paint(before,source,desired,3,UINT32_MAX,
      [&](int32_t,int32_t,int64_t prior,int64_t after){changes+=prior!=after;return true;});
  REQUIRE(plan.error==area::Error::None);
  CHECK(plan.bounds.y==11);CHECK(plan.bounds.height==2);
  CHECK(plan.tiles==4);CHECK(plan.added==2);CHECK(plan.erased==2);CHECK(changes==4);
  auto fail=area::paint(before,source,desired,3,UINT32_MAX,
      [](int32_t,int32_t y,int64_t,int64_t){return y!=12;});
  CHECK(fail.error==area::Error::InvalidSite);CHECK(source==std::vector<uint8_t>(4,1));
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

TEST_CASE("native cage scan prepares all memberships without requiring a containing cage") {
  struct Cage {std::vector<int32_t> assigned_units;};
  Cage first{{7,9,7}},second{{4,7,5}},unrelated{{2,3}};
  std::vector<Cage*> cages{&first,&unrelated,&second};
  const auto originalFirst=first.assigned_units,originalSecond=second.assigned_units;
  auto scan=area::scanAssignedCages(cages,7,11);
  REQUIRE(scan.error==area::AssignmentScanError::None);CHECK(scan.steps==11);CHECK(scan.entries==8);
  CHECK(scan.affected==std::vector<Cage*>{&first,&second});
  const auto plans=area::prepareCageAssignments(scan.affected,7);
  REQUIRE(plans.size()==2);CHECK(plans[0].first==&first);CHECK(plans[0].second==std::vector<int32_t>{9});
  CHECK(plans[1].first==&second);CHECK(plans[1].second==std::vector<int32_t>{4,5});
  CHECK(first.assigned_units==originalFirst);CHECK(second.assigned_units==originalSecond);
  // No cage-item holder is an input: a loose-caged unit's assignments in any
  // built cage are found, while the containing-item reference remains native.
  auto absent=area::scanAssignedCages(cages,99,11);
  CHECK(absent.error==area::AssignmentScanError::None);CHECK(absent.affected.empty());
  CHECK(area::prepareCageAssignments(absent.affected,99).empty());
  auto low=area::scanAssignedCages(cages,7,10);CHECK(low.error==area::AssignmentScanError::Budget);CHECK(low.steps==10);
  CHECK(first.assigned_units==originalFirst);CHECK(second.assigned_units==originalSecond);
}

TEST_CASE("native cage scan enforces aggregate cage and membership bounds before changes") {
  struct Cage {std::vector<int32_t> assigned_units;};
  std::vector<Cage> storage(257);std::vector<Cage*> cages;
  for(int i=0;i<256;++i){storage[i].assigned_units={7};cages.push_back(&storage[i]);}
  auto scan=area::scanAssignedCages(cages,7,512);
  REQUIRE(scan.error==area::AssignmentScanError::None);CHECK(scan.steps==512);CHECK(scan.entries==256);CHECK(scan.affected.size()==256);
  auto plans=area::prepareCageAssignments(scan.affected,7);REQUIRE(plans.size()==256);
  for(const auto& plan:plans){CHECK(plan.second.empty());CHECK(plan.first->assigned_units==std::vector<int32_t>{7});}
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
