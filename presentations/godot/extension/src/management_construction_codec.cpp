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

void writeConstruction(Dictionary& result, const wm::ManagementState& s) {
  result["required"] = s.required;
  result["next_cursor"] = int64_t(s.nextCursor);
  result["placement_valid"] = s.placementValid;
  result["building_id"] = s.buildingId;
  result["build_stage"] = s.buildStage;
  result["max_stage"] = s.maxStage;
  result["removing"] = s.removing;
  result["jobs"] = s.jobs;
  result["terrain_construction"] = s.terrainConstruction;
  Array catalog, inputs;
  for (auto& d : s.catalog) {
    Dictionary row;
    row["key"] = String::utf8(d.key.c_str());
    row["name"] = String::utf8(d.name.c_str());
    row["width"] = d.width;
    row["height"] = d.height;
    row["supported"] = d.supported;
    row["reason"] = String::utf8(d.reason.c_str());
    catalog.push_back(row);
  }
  for (auto& i : s.inputs) {
    Dictionary row;
    row["id"] = i.id;
    row["description"] = String::utf8(i.description.c_str());
    row["quantity"] = int64_t(i.quantity);
    inputs.push_back(row);
  }
  result["catalog"] = catalog;
  result["inputs"] = inputs;
}

void writeArea(Dictionary& result, const wm::AreaState& s) {
  Array areas, choices;
  for (const auto& a : s.areas) {
    Dictionary row;
    row["id"] = a.id;
    row["kind"] = int(a.kind);
    row["name"] = String::utf8(a.name.c_str());
    row["origin"] = Vector3i(a.x, a.y, a.z);
    row["width"] = a.width;
    row["height"] = a.height;
    PackedByteArray extents;
    for (auto v : a.extents)
      extents.push_back(v);
    row["extents"] = extents;
    row["zone_type"] = a.zoneType;
    row["categories"] = int64_t(a.categories);
    row["barrels"] = a.barrels;
    row["bins"] = a.bins;
    row["wheelbarrows"] = a.wheelbarrows;
    row["links_only"] = a.linksOnly;
    row["active"] = a.active;
    row["owner_id"] = a.ownerId;
    row["owner_name"] = String::utf8(a.ownerName.c_str());
    row["owner_allowed"] = a.ownerAllowed;
    Array gives, takes;
    for (auto id : a.gives)
      gives.push_back(id);
    for (auto id : a.takes)
      takes.push_back(id);
    row["gives"] = gives;
    row["takes"] = takes;
    areas.push_back(row);
  }
  for (const auto& c : s.choices) {
    Dictionary row;
    row["id"] = c.id;
    row["name"] = String::utf8(c.name.c_str());
    choices.push_back(row);
  }
  result["areas"] = areas;
  result["area_choices"] = choices;
  result["area_next_cursor"] = int64_t(s.nextCursor);
  result["area_truncated"] = s.truncated;
}

bool validateConstructionShape(const Dictionary& data, String& error) {
  if (!managementDictionaryTypes(data, {"width", "height", "direction", "cursor", "building_id"},
                                 error) ||
      !managementRequiredFields(data, error))
    return false;
  return true;
}

bool readConstruction(const Dictionary& data, wm::ManagementRequest& r, String& error) {
  int64_t a = data.get("action", actionValue(Action::Catalog)), w = data.get("width", 1),
          h = data.get("height", 1), d = data.get("direction", 0);
  int64_t cursor = data.get("cursor", 0), building = data.get("building_id", -1);
  if (a < actionValue(Action::Catalog) || a > actionValue(Action::RemoveConstruction) || w < 1 ||
      w > 31 || h < 1 || h > 31 || d < 0 || d > 3 || cursor < 0 || cursor > UINT32_MAX ||
      building < -1 || building > INT32_MAX) {
    error = "Invalid construction request";
    return false;
  }
  r.action = wm::ManagementAction(a);
  String key = data.get("definition", String());
  r.definition = key.utf8().get_data();
  Vector3i p = data.get("origin", Vector3i());
  r.x = p.x;
  r.y = p.y;
  r.z = p.z;
  r.width = w;
  r.height = h;
  r.direction = d;
  r.cursor = uint32_t(cursor);
  r.buildingId = int32_t(building);
  Array ids = data.get("items", Array());
  if (ids.size() > 64) {
    error = "Too many construction inputs";
    return false;
  }
  for (int i = 0; i < ids.size(); ++i) {
    int64_t id = ids[i];
    if (id < 0 || id > INT32_MAX) {
      error = "Invalid construction input ID";
      return false;
    }
    r.items.push_back(int32_t(id));
  }
  return true;
}

bool validateAreaShape(const Dictionary& data, String& error) {
  if (!managementDictionaryTypes(data,
                                 {"kind", "id", "width", "height", "zone_type", "categories",
                                  "changed_categories", "barrels", "bins", "wheelbarrows", "active",
                                  "links_only", "owner_id", "link_id", "cursor"},
                                 error) ||
      !managementRequiredFields(data, error))
    return false;
  return true;
}

bool readArea(const Dictionary& data, wm::ManagementRequest& r, String& error) {
  bool valid = true;
  auto n = [&](const char* key, int64_t def, int64_t low, int64_t high) {
    int64_t v = data.get(key, def);
    if (v < low || v > high)
      valid = false;
    return v;
  };
  r.action = wm::ManagementAction(n("action", actionValue(Action::AreaCatalog),
                                    actionValue(Action::AreaCatalog),
                                    actionValue(Action::AreaCandidates)));
  auto& a = r.area;
  a.kind = wm::AreaKind(n("kind", 0, 0, 1));
  a.id = int32_t(n("id", -1, -1, INT32_MAX));
  Vector3i p = data.get("origin", Vector3i());
  a.x = p.x;
  a.y = p.y;
  a.z = p.z;
  a.width = uint16_t(n("width", 1, 1, 31));
  a.height = uint16_t(n("height", 1, 1, 31));
  a.zoneType = int16_t(n("zone_type", -1, -1, 255));
  a.categories = uint32_t(n("categories", 0, 0, 0x1ffff));
  a.changedCategories = uint32_t(n("changed_categories", 0, 0, 0x1ffff));
  a.barrels = int16_t(n("barrels", -1, -1, 32767));
  a.bins = int16_t(n("bins", -1, -1, 32767));
  a.wheelbarrows = int16_t(n("wheelbarrows", -1, -1, 32767));
  a.active = int8_t(n("active", -1, -1, 1));
  a.linksOnly = int8_t(n("links_only", -1, -1, 1));
  a.ownerId = int32_t(n("owner_id", -2, -2, INT32_MAX));
  a.linkId = int32_t(n("link_id", -1, -1, INT32_MAX));
  a.give = data.get("give", true);
  a.unlink = data.get("unlink", false);
  a.cursor = uint32_t(n("cursor", 0, 0, UINT32_MAX));
  String q = data.get("query", String());
  a.query = q.utf8().get_data();
  if (!valid) {
    error = "Invalid bounded area request";
    return false;
  }
  return true;
}
}  // namespace df3d_godot::management
