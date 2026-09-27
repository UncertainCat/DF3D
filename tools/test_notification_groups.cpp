#include "doctest.h"
#include "../bridge/plugin/notification_groups.h"
#include <vector>
namespace {
struct NativeGroup {int type=0;std::vector<int32_t> announcement_id,report_unid,report_unit_announcement_category;};
}

TEST_CASE("notification groups are read completely or marked incomplete") {
  NativeGroup first{24,{0,12},{},{}},second{34,{}, {10,11},{0,2}};
  std::vector<NativeGroup*> native{&first,&second};
  auto data=df3d_session::readNotificationGroups(native);
  REQUIRE((data.complete && data.groups.size()==2 && data.groups[0].category==24 && data.groups[1].category==34));
  CHECK((data.groups[0].reports==std::vector<int32_t>({0,12})));
  CHECK((data.groups[1].units.size()==2 && data.groups[1].units[1].unitId==11 && data.groups[1].units[1].category==2));
  const auto before=data.key;native.erase(native.begin());
  CHECK(df3d_session::readNotificationGroups(native).key!=before);
  first.announcement_id.resize(300,17);native={&first};data=df3d_session::readNotificationGroups(native);
  CHECK((data.groups[0].reportCount==300 && data.groups[0].reports.size()==256 && !data.groups[0].complete));
  second.report_unit_announcement_category.resize(1);native={&second};data=df3d_session::readNotificationGroups(native);
  CHECK((data.groups[0].units.size()==1 && data.groups[0].unitCount==2 && !data.groups[0].complete));
  first.type=-1;native={&first};data=df3d_session::readNotificationGroups(native);
  CHECK((data.groups.empty() && !data.complete));
  native.clear();data=df3d_session::readNotificationGroups(native);CHECK((data.groups.empty() && data.complete));
}

TEST_CASE("notification category and reference boundaries preserve completeness") {
  for(int category:{-1,36,37}) {
    NativeGroup group{category,{0},{},{}};
    auto data=df3d_session::readNotificationGroups(std::vector<NativeGroup*>{&group});
    CHECK(data.complete==(category==36));CHECK(data.groups.size()==(category==36?1:0));
    if(category==36)CHECK(data.groups[0].category==36);
  }
  for(int count:{256,257}) {
    NativeGroup group{20,{},{},{}};
    for(int i=0;i<count;++i){group.announcement_id.push_back(i);group.report_unid.push_back(i);group.report_unit_announcement_category.push_back(2);}
    auto data=df3d_session::readNotificationGroups(std::vector<NativeGroup*>{&group});
    REQUIRE(data.groups.size()==1);const auto& g=data.groups[0];
    CHECK(data.complete);CHECK(g.complete==(count==256));CHECK(g.reports.size()==256);CHECK(g.units.size()==256);
    CHECK(g.reportCount==count);CHECK(g.unitCount==count);
  }
  for(int category:{-1,0,2,3}) {
    NativeGroup group{34,{0,-1},{0,17},{0,category}};
    auto data=df3d_session::readNotificationGroups(std::vector<NativeGroup*>{&group});
    REQUIRE(data.groups.size()==1);const auto& g=data.groups[0];
    CHECK_FALSE(g.complete);CHECK(g.reports==std::vector<int32_t>{0});
    CHECK(g.units.size()==(category>=0 && category<=2?2:1));
    CHECK(g.reportCount==2);CHECK(g.unitCount==2);
  }
  NativeGroup group{0,{},{},{}};
  for(int count:{64,65}) {
    auto data=df3d_session::readNotificationGroups(std::vector<NativeGroup*>(count,&group));
    CHECK(data.groups.size()==64);CHECK(data.complete==(count==64));
    CHECK(data.groups[0].complete);
  }
}
