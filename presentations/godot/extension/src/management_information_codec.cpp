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

bool readReport(const Dictionary& data, wm::ManagementRequest& r, String& error) {
  const int64_t action = data.get("action", actionValue(Action::ReportList)),
                id = data.get("id", -1), before = data.get("before_id", -1);
  if (action < actionValue(Action::ReportList) || action > actionValue(Action::ReportInspect) ||
      id < -1 || id > INT32_MAX || before < -1 || before > INT32_MAX) {
    error = "Invalid bounded report request";
    return false;
  }
  r.action = wm::ManagementAction(action);
  r.report.id = int32_t(id);
  r.report.beforeId = int32_t(before);
  r.report.announcementsOnly = data.get("announcements_only", true);
  String query = data.get("query", String());
  r.report.query = query.utf8().get_data();
  return true;
}
}  // namespace df3d_godot::management
