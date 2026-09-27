#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include "management_codecs.h"
#include "management_dictionary.h"

namespace df3d_godot::management {
using namespace godot;
void writeCitizen(Dictionary& result, const wm::CitizenState& s) {
  Dictionary citizen;
  const auto& c = s;
  Array people, details;
  auto ids = [](const auto& source) {
    Array out;
    for (auto v : source)
      out.push_back(v);
    return out;
  };
  auto names = [](const auto& source) {
    Array out;
    for (const auto& v : source)
      out.push_back(String::utf8(v.c_str()));
    return out;
  };
  for (const auto& u : c.citizens) {
    Dictionary row;
    row["id"] = u.id;
    row["name"] = String::utf8(u.name.c_str());
    row["profession"] = String::utf8(u.profession.c_str());
    row["job"] = String::utf8(u.job.c_str());
    row["reason"] = String::utf8(u.reason.c_str());
    row["age"] = u.age;
    row["stress"] = u.stress;
    row["has_stress"] = u.hasStress;
    row["origin"] = Vector3i(u.x, u.y, u.z);
    row["can_focus"] = u.canFocus;
    row["eligible"] = u.eligible;
    row["only_assigned_jobs"] = u.onlyAssignedJobs;
    row["profession_color"] = u.professionColor;
    row["profession_id"] = u.professionId;
    row["job_type"] = u.jobType;
    row["social_activity"] = u.socialActivity;
    Array assignments;
    for (const auto& d : u.assignedDetails) {
      Dictionary assignment;
      assignment["index"] = d.index;
      assignment["icon"] = d.icon;
      assignment["name"] = String::utf8(d.name.c_str());
      assignments.push_back(assignment);
    }
    row["assigned_details"] = assignments;
    row["labors"] = ids(u.labors);
    row["labor_names"] = names(u.laborNames);
    row["offices"] = ids(u.offices);
    Array roles;
    for (const auto& r : u.roles) {
      Dictionary role;
      role["name"] = String::utf8(r.name.c_str());
      role["required_office"] = r.requiredOffice;
      roles.push_back(role);
    }
    row["roles"] = roles;
    people.push_back(row);
  }
  for (const auto& d : c.details) {
    Dictionary row;
    row["index"] = d.index;
    row["revision"] = int64_t(d.revision);
    row["name"] = String::utf8(d.name.c_str());
    row["reason"] = String::utf8(d.reason.c_str());
    row["mode"] = d.mode;
    row["no_modify"] = d.noModify;
    row["cannot_be_everybody"] = d.cannotBeEverybody;
    row["editable"] = d.editable;
    row["mode_editable"] = d.modeEditable;
    row["labors"] = ids(d.labors);
    row["labor_names"] = names(d.laborNames);
    row["assigned_units"] = ids(d.assignedUnits);
    details.push_back(row);
  }
  citizen["citizens"] = people;
  citizen["details"] = details;
  citizen["selected_unit"] = c.selectedUnit;
  citizen["selected_detail"] = c.selectedDetail;
  citizen["next_cursor"] = int64_t(c.nextCursor);
  citizen["external_controller"] = c.externalController;
  citizen["detail"] = String::utf8(c.detail.c_str());
  result["citizen"] = citizen;
}


bool validateCitizenShape(const Dictionary& data, String& error) {
  return managementDictionaryTypes(data, {"unit_id", "detail_index", "expected_revision", "cursor", "member", "mode"}, error) &&
      managementRequiredFields(data, error);
}

// Citizen payload keys (actions 28..33):
// unit_id: int, -1 none; required for 29/32, optional for 31 to include that citizen.
// detail_index: int 0..127, native vector index; required for 31..33.
// expected_revision: int >0 from 30/31 revision; required for 32/33.
// query: String <=128 UTF-8 bytes; cursor: int (28 unit id, 30 detail index).
// member: 0/1, action 32 only. mode: 1 Everybody / 2 Nobody / 3 Only selected,
// action 33 only. Omitted member/mode retain the wire sentinel -1.
bool readCitizen(const Dictionary& data, wm::ManagementRequest& r, String& error) {
  bool valid = true;
  auto n = [&](const char* key, int64_t def, int64_t low, int64_t high) {
    int64_t value = data.get(key, def);
    if (value < low || value > high) valid = false;
    return value;
  };
  r.action = wm::ManagementAction(n("action", 0, static_cast<int>(wm::ManagementAction::CitizenList),
      static_cast<int>(wm::ManagementAction::WorkDetailMode)));
  auto& value = r.citizen;
  value.unitId = int32_t(n("unit_id", -1, -1, INT32_MAX));
  value.detailIndex = int32_t(n("detail_index", -1, -1, 127));
  value.expectedRevision = uint64_t(n("expected_revision", 0, 0, INT64_MAX));
  value.cursor = uint32_t(n("cursor", 0, 0, UINT32_MAX));
  value.member = int8_t(n("member", -1, -1, 1));
  value.mode = int8_t(n("mode", -1, -1, 3));
  if (r.action == wm::ManagementAction::WorkDetailMode && value.mode < 1) valid = false;
  String query = data.get("query", String());
  value.query = query.utf8().get_data();
  if (value.query.size() > 128) valid = false;
  if (!valid) { error = "Invalid bounded citizen request"; return false; }
  return true;
}
}  // namespace df3d_godot::management
