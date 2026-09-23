#pragma once
#include "session_util.h"
#include <algorithm>
#include <string>
#include <vector>

namespace df3d_session {
// Bounded copies only; no native pointers survive the update that reads them.
struct UnitNotificationRef { int32_t unitId; uint8_t category; };
struct NotificationGroup {
  uint8_t category=0;
  std::vector<int32_t> reports;
  std::vector<UnitNotificationRef> units;
  uint32_t reportCount=0,unitCount=0;
  bool complete=true;
};
struct NotificationGroups {
  std::vector<NotificationGroup> groups;
  bool complete=true;
  std::string key;
};
template<class NativeGroups>
inline NotificationGroups readNotificationGroups(const NativeGroups& source) {
  namespace m=df3d::mirror;
  NotificationGroups result;
  result.complete=source.size()<=m::kMaxNotificationGroups;
  for(size_t i=0;i<std::min<size_t>(source.size(),m::kMaxNotificationGroups);++i) {
    const auto* native=source[i];
    if(!native || int(native->type)<0 || int(native->type)>int(m::NotificationCategory::Hunting)) {result.complete=false;continue;}
    NotificationGroup group;group.category=uint8_t(native->type);
    group.reportCount=uint32_t(std::min<size_t>(native->announcement_id.size(),UINT32_MAX));
    group.unitCount=uint32_t(std::min<size_t>(native->report_unid.size(),UINT32_MAX));
    for(size_t j=0;j<std::min<size_t>(native->announcement_id.size(),m::kMaxNotificationReferences);++j)
      if(native->announcement_id[j]>=0)group.reports.push_back(native->announcement_id[j]);
    const auto pairs=std::min(native->report_unid.size(),native->report_unit_announcement_category.size());
    for(size_t j=0;j<std::min<size_t>(pairs,m::kMaxNotificationReferences);++j) {
      const auto category=int(native->report_unit_announcement_category[j]);
      if(native->report_unid[j]>=0 && category>=0 && category<=2)group.units.push_back({native->report_unid[j],uint8_t(category)});
    }
    group.complete=group.reports.size()==native->announcement_id.size() && group.units.size()==native->report_unid.size() && native->report_unid.size()==native->report_unit_announcement_category.size();
    result.key+="g"+std::to_string(group.category)+":"+std::to_string(group.reportCount)+":"+std::to_string(group.unitCount)+":"+std::to_string(group.complete);
    for(auto id:group.reports)result.key+="r"+std::to_string(id);
    for(auto ref:group.units)result.key+="u"+std::to_string(ref.unitId)+":"+std::to_string(ref.category);
    result.groups.push_back(std::move(group));
  }
  result.key+=result.complete?"complete":"partial";
  return result;
}
inline auto serializeNotificationGroups(flatbuffers::FlatBufferBuilder& b,const NotificationGroups& source) {
  namespace m=df3d::mirror;
  std::vector<flatbuffers::Offset<m::ActiveNotificationGroup>> groups;
  for(const auto& group:source.groups) {
    std::vector<flatbuffers::Offset<m::UnitReportReference>> units;
    for(auto ref:group.units)units.push_back(m::CreateUnitReportReference(b,ref.unitId,m::UnitReportCategory(ref.category)));
    groups.push_back(m::CreateActiveNotificationGroup(b,m::NotificationCategory(group.category),b.CreateVector(group.reports),group.reportCount,b.CreateVector(units),group.unitCount,group.complete));
  }
  return b.CreateVector(groups);
}
}
