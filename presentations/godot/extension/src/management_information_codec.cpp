#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include "management_codecs.h"
#include "management_dictionary.h"

namespace df3d_godot::management {
using namespace godot;
namespace {
constexpr int actionValue(wm::ManagementAction a) {
  return static_cast<int>(a);
}
using Action = wm::ManagementAction;
}  // namespace

void writeReport(Dictionary& result, const wm::ReportState& s) {
  Dictionary report;
  Array reportRows;
  for (const auto& r : s.reports) {
    Dictionary row;
    row["id"] = r.id;
    row["category"] = String::utf8(r.category.c_str());
    row["text"] = String::utf8(r.text.c_str());
    row["year"] = r.year;
    row["year_tick"] = r.yearTick;
    row["repeat_count"] = r.repeatCount;
    row["continuation"] = r.continuation;
    row["text_complete"] = r.textComplete;
    row["position"] = Vector3i(r.x, r.y, r.z);
    row["position2"] = Vector3i(r.x2, r.y2, r.z2);
    row["position_visible"] = r.positionVisible;
    row["position2_visible"] = r.position2Visible;
    row["tab"]=int(r.tab);row["color"]=r.color;row["bright"]=r.bright;
    row["zoom_type"]=int(r.zoomType);row["zoom_type2"]=int(r.zoomType2);
    row["position_hidden"]=r.positionHidden;row["position2_hidden"]=r.position2Hidden;row["speaker_id"]=r.speakerId;
    reportRows.push_back(row);
  }
  report["reports"] = reportRows;
  report["next_before_id"] = s.nextBeforeId;
  report["announcements_only"] = s.announcementsOnly;
  report["detail"] = String::utf8(s.detail.c_str());
  report["view"]=int(s.view);report["tab"]=int(s.tab);report["after_id"]=s.afterId;report["from_end"]=s.fromEnd;
  Array counts;for(auto count:s.tabCounts)counts.push_back(int64_t(count));report["tab_counts"]=counts;
  report["total"]=int64_t(s.total);report["next_after_id"]=s.nextAfterId;report["trimmed_through"]=s.trimmedThrough;report["gap"]=s.gap;
  report["notification_category"]=s.notificationCategory;report["alert_button"]=s.alertButton;report["unit_id"]=s.unitId;report["unit_category"]=s.unitCategory;report["cursor"]=int64_t(s.cursor);report["next_cursor"]=int64_t(s.nextCursor);report["list_revision"]=int64_t(s.listRevision);
  Array units;for(const auto& u:s.units){Dictionary row;row["unit_id"]=u.unitId;row["category"]=u.category;row["name"]=String::utf8(u.name.c_str());row["profession"]=String::utf8(u.profession.c_str());row["dead"]=u.dead;row["log_count"]=int64_t(u.logCount);row["error"]=String::utf8(u.error.c_str());units.push_back(row);}report["units"]=units;
  Array missing;for(auto id:s.missingIds)missing.push_back(id);report["missing_ids"]=missing;
  result["report"] = report;
}

bool validateReportShape(const Dictionary& data, String& error) {
  if (!managementDictionaryTypes(data, {"id", "before_id", "view", "tab", "after_id", "unit_id", "unit_category", "cursor", "expected_list_revision", "notification_category"}, error) ||
      !managementRequiredFields(data, error))
    return false;
  return true;
}

// Reports payload: id int -1..INT32_MAX (-1 absent; required for 35, native
// reports[].id or active_notifications[].report_ids[]; 34 permits only -1).
// before_id int -1..INT32_MAX: 34 exclusive previous next_before_id; -1 newest.
// query String <=128 UTF-8 bytes: 34 case-insensitive substring or exact decimal id.
// announcements_only bool defaults true: world.status.announcements; false reads
// world.status.reports including combat/sparring/hunting lines; echoed in reply.
// Reply report: reports[]{id, category (announcement_type key or "Unknown"), text,
// year, year_tick, repeat_count, continuation, text_complete, position, position2
// (Vector3i, -1s when absent), position_visible, position2_visible}, next_before_id,
// Position flags mean stored recenter targets, including hidden and off-map tiles.
// announcements_only, detail (blank when absent). No native viewscreen inputs.
bool readReport(const Dictionary& data, wm::ManagementRequest& r, String& error) {
  const int64_t action = data.get("action", actionValue(Action::ReportList)),
                id = data.get("id", -1), before = data.get("before_id", -1),
                view=data.get("view",0), tab=data.get("tab",0), after=data.get("after_id",-1), unit=data.get("unit_id",-1), category=data.get("unit_category",-1), cursor=data.get("cursor",0), revision=data.get("expected_list_revision",0), group=data.get("notification_category",-1);
  if(action==actionValue(Action::PrepareAlertDismissal) || action==actionValue(Action::DismissAlert)) {
    for(const Variant& key:data.keys())if(key!=String("action") && key!=String("expected_list_revision")) {
      error="Unexpected alert dismissal field";return false;
    }
    if((data.has("expected_list_revision") && data["expected_list_revision"].get_type()!=Variant::INT) ||
       revision<0 || (action==actionValue(Action::PrepareAlertDismissal) ? revision!=0 : revision==0)) {
      error="Invalid alert dismissal receipt";return false;
    }
    r.action=wm::ManagementAction(action);r.report.expectedListRevision=uint64_t(revision);return true;
  }
  const auto invalidEntries=[&](){error="Invalid bounded report entries";return false;};
  for(const char* key:{"ids","units"})if(data.has(key) && data[key].get_type()!=Variant::ARRAY)return invalidEntries();
  Array ids=data.get("ids",Array()),units=data.get("units",Array());
  if(ids.size()>64 || units.size()>64 || (view!=4 && (!ids.is_empty() || !units.is_empty())))return invalidEntries();
  for(int i=0;i<ids.size();++i){if(ids[i].get_type()!=Variant::INT)return invalidEntries();const int64_t value=ids[i];if(value<0 || value>INT32_MAX)return invalidEntries();r.report.ids.push_back(int32_t(value));}
  for(int i=0;i<units.size();++i){
    if(units[i].get_type()!=Variant::DICTIONARY)return invalidEntries();Dictionary ref=units[i];
    if(!ref.has("unit_id") || !ref.has("category") || ref["unit_id"].get_type()!=Variant::INT || ref["category"].get_type()!=Variant::INT)return invalidEntries();
    const int64_t uid=ref["unit_id"],cat=ref["category"];if(uid<0 || uid>INT32_MAX || cat<0 || cat>2)return invalidEntries();
    r.report.units.push_back({int32_t(uid),uint8_t(cat)});
  }
  String query = data.get("query", String());
  const bool fromEnd=data.get("from_end",false), only=data.get("announcements_only",true), refresh=data.get("refresh",false), button=data.get("alert_button",false);
  const bool groupOwner=group>=0 || button;
  if (action < actionValue(Action::ReportList) || action > actionValue(Action::ReportInspect) ||
      id < -1 || id > INT32_MAX || before < -1 || before > INT32_MAX ||
      query.utf8().length() > 128 || view<0 || view>6 || tab<0 || tab>25 || after < -1 || after>INT32_MAX ||
      unit< -1 || unit>INT32_MAX || category< -1 || category>2 || cursor<0 || cursor>UINT32_MAX || revision<0 ||
      (group< -1 || group>36 || (button && group!=-1) || (groupOwner && view!=5 && view!=6)) ||
      (view==6 && (action!=34 || !groupOwner || id!=-1 || tab!=0 || unit!=-1 || category!=-1 || before!=-1 || after!=-1 || fromEnd || !query.is_empty() || !only || cursor>65536 || (cursor && !revision))) ||
      (view==5 && groupOwner && (tab!=0 || unit!=-1 || category!=-1 || !revision)) ||
      (view==5 && (action!=35 || id<0 || before!=-1 || after!=-1 || fromEnd || tab>22 || (tab!=0 && !revision) || (unit<0 ? category!=-1 : (category<0 || tab!=0 || !revision)) || cursor>33554432 || (cursor && !revision) || !query.is_empty() || !only)) ||
      (view==4 && (action!=35 || id!=-1 || before!=-1 || after!=-1 || fromEnd || tab!=0 || unit!=-1 || category!=-1 || cursor || revision || !query.is_empty() || !only || (ids.is_empty() && units.is_empty()))) ||
      (view<2 && (unit!=-1 || category!=-1 || cursor || (view==0 && revision))) ||
      (view>=2 && view<=3 && (action!=34 || tab!=0 || category<0 || !query.is_empty() || !only)) ||
      (view==2 && (after!=-1 || before!=-1 || fromEnd)) ||
      (refresh && (view!=3 || !revision || before!=-1 || fromEnd)) ||
      (view==3 && (unit<0 || cursor || int(after>=0)+int(before>=0)+int(fromEnd)>1)) ||
      (view==0 && (tab!=0 || after!=-1 || fromEnd)) ||
      (view==1 && (action!=34 || tab<1 || tab>22 || !query.is_empty() || !only ||
                  int(after>=0)+int(before>=0)+int(fromEnd)>1)) ||
      (action == actionValue(Action::ReportList) && id != -1) ||
      (action == actionValue(Action::ReportInspect) && (before != -1 || !query.is_empty()))) {
    error = "Invalid bounded report request";
    return false;
  }
  r.action = wm::ManagementAction(action);
  r.report.id = int32_t(id);
  r.report.beforeId = int32_t(before);
  r.report.announcementsOnly = data.get("announcements_only", true);
  r.report.query = query.utf8().get_data();
  r.report.unitId=int32_t(unit);r.report.unitCategory=int8_t(category);r.report.cursor=uint32_t(cursor);r.report.expectedListRevision=uint64_t(revision);
  r.report.view=wm::ReportView(view);r.report.tab=wm::ReportTab(tab);r.report.afterId=int32_t(after);r.report.fromEnd=fromEnd;r.report.refresh=refresh;r.report.notificationCategory=int16_t(group);r.report.alertButton=button;
  return true;
}
}  // namespace df3d_godot::management
