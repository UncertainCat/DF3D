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
    reportRows.push_back(row);
  }
  report["reports"] = reportRows;
  report["next_before_id"] = s.nextBeforeId;
  report["announcements_only"] = s.announcementsOnly;
  report["detail"] = String::utf8(s.detail.c_str());
  result["report"] = report;
}

bool validateReportShape(const Dictionary& data, String& error) {
  if (!managementDictionaryTypes(data, {"id", "before_id"}, error) ||
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
// (Vector3i, -1s when hidden), position_visible, position2_visible}, next_before_id,
// announcements_only, detail (blank when absent). No native viewscreen inputs.
bool readReport(const Dictionary& data, wm::ManagementRequest& r, String& error) {
  const int64_t action = data.get("action", actionValue(Action::ReportList)),
                id = data.get("id", -1), before = data.get("before_id", -1);
  String query = data.get("query", String());
  if (action < actionValue(Action::ReportList) || action > actionValue(Action::ReportInspect) ||
      id < -1 || id > INT32_MAX || before < -1 || before > INT32_MAX ||
      query.utf8().length() > 128 ||
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
  return true;
}
}  // namespace df3d_godot::management
