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
