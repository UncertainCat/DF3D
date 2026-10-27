#include "doctest.h"
#include "location_name_util.h"
#include <vector>
namespace m=df3d::mirror;
namespace {
flatbuffers::Offset<m::LocationNameSnapshot> snapshot(flatbuffers::FlatBufferBuilder& b,
    int variant=-1) {
  std::vector<uint8_t> first{0x82,0xff},nick;
  std::vector<int32_t> words(7,-1);std::vector<int16_t> parts(7,8);
  if(variant==0)words.pop_back();if(variant==1)parts.push_back(0);
  if(variant==2)words[0]=-2;if(variant==3)parts[0]=9;
  if(variant==4)first.resize(m::kLocationNameBytes+1);
  auto v=m::CreateLocationNameValue(b,b.CreateVector(first),b.CreateVector(nick),
      b.CreateVector(words),b.CreateVector(parts),-1,-1,true);
  return m::CreateLocationNameSnapshot(b,651,1,1,245,0,variant==5?0:17,v);
}
}
TEST_CASE("Structured name contract preserves CP437 and independent native fields") {
  for(int variant=-1;variant<6;++variant) {
    flatbuffers::FlatBufferBuilder b;auto s=snapshot(b,variant);b.Finish(s);
    const auto* value=flatbuffers::GetRoot<m::LocationNameSnapshot>(b.GetBufferPointer());
    CHECK(bool(m::validateLocationNameSnapshot(*value))==(variant>=0));
    if(variant==-1) {
      CHECK(value->value()->first_name_bytes()->Get(0)==0x82);
      CHECK(value->value()->first_name_bytes()->Get(1)==0xff);
      CHECK(value->value()->parts()->Get(0)==8);
    }
  }
}
TEST_CASE("Name pages enforce exact progress and complete forms without losing native ordering") {
  for(int variant=0;variant<8;++variant) {
    flatbuffers::FlatBufferBuilder b;auto s=snapshot(b);
    std::vector<flatbuffers::Offset<m::LocationNameChoice>> rows;
    // Same word with two native grammatical forms must remain distinct/in order.
    for(int part=0;part<2;++part)rows.push_back(m::CreateLocationNameChoice(b,0,part,
        b.CreateString(part?"abbeys":"abbey"),b.CreateString("kulet")));
    if(variant==4)rows.clear();
    if(variant==5)rows.resize(129,rows[0]);
    if(variant==6)rows[0]=m::CreateLocationNameChoice(b,0,0,b.CreateString(std::string(65536,'x')),b.CreateString(""));
    auto page=m::CreateLocationNamePage(b,s,variant==7?7:0,b.CreateVector(std::vector<uint8_t>{}),
        0,variant==1?1:3,variant==2?1:2,variant!=3,b.CreateVector(rows));b.Finish(page);
    const auto* p=flatbuffers::GetRoot<m::LocationNamePage>(b.GetBufferPointer());
    CHECK(bool(m::validateLocationNamePage(*p))==(variant!=0));
    if(!variant){CHECK(p->choices()->Get(0)->part()==0);CHECK(p->choices()->Get(1)->part()==1);}
  }
  flatbuffers::FlatBufferBuilder b;auto s=snapshot(b);
  auto p=m::CreateLocationNamePage(b,s,0,b.CreateVector(std::vector<uint8_t>{}),0,0,0,false,
      b.CreateVector(std::vector<flatbuffers::Offset<m::LocationNameChoice>>{}));b.Finish(p);
  CHECK_FALSE(m::validateLocationNamePage(*flatbuffers::GetRoot<m::LocationNamePage>(b.GetBufferPointer())));
}
