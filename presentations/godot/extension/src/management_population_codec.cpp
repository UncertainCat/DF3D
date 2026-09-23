#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include "management_codecs.h"

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

}  // namespace df3d_godot::management
