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
  auto filters=[](const std::vector<wm::ConstructionFilter>& values){
    Array rows;for(const auto& v:values){Dictionary row;row["index"]=v.index;row["item_type"]=v.itemType;row["item_subtype"]=v.itemSubtype;row["caption"]=String::utf8(v.caption.c_str());row["requirement"]=String::utf8(v.requirement.c_str());row["quantity"]=v.quantity;rows.push_back(row);}return rows;
  };
  auto footprint=[](const wm::ConstructionFootprint& v){Dictionary row;row["direction"]=v.direction;row["width"]=v.width;row["height"]=v.height;row["center_x"]=v.centerX;row["center_y"]=v.centerY;return row;};
  const auto& c=s.construction;Dictionary construction;
  construction["building_key"]=String::utf8(c.buildingKey.c_str());construction["filter"]=c.filter;construction["filters"]=filters(c.filters);
  construction["total"]=int64_t(c.total);construction["list_revision"]=c.listRevision;construction["estimated"]=c.estimated;
  construction["build_phase"]=c.buildPhase;construction["build_done"]=int64_t(c.buildDone);construction["build_total"]=int64_t(c.buildTotal);
  construction["placed"]=int64_t(c.placed);construction["skipped"]=int64_t(c.skipped);construction["first_building"]=c.firstBuilding;
  PackedByteArray mask,pieces;for(auto v:c.validMask)mask.push_back(v);for(auto v:c.pieces)pieces.push_back(v);
  construction["valid_mask"]=mask;construction["pieces"]=pieces;construction["footprint"]=c.footprint ? footprint(*c.footprint) : Dictionary{};
  Array materials;for(const auto& v:c.materials){Dictionary row;row["item_type"]=v.itemType;row["item_subtype"]=v.itemSubtype;row["mat_type"]=v.matType;row["mat_index"]=v.matIndex;row["name"]=String::utf8(v.name.c_str());row["caption"]=String::utf8(v.caption.c_str());row["count"]=int64_t(v.count);materials.push_back(row);}
  construction["materials"]=materials;result["construction"]=construction;
  Array catalog, inputs;
  for (auto& d : s.catalog) {
    Dictionary row;
    row["key"] = String::utf8(d.key.c_str());
    row["name"] = String::utf8(d.name.c_str());
    row["width"] = d.width;
    row["height"] = d.height;
    row["supported"] = d.supported;
    row["reason"] = String::utf8(d.reason.c_str());
    row["family"]=String::utf8(d.family.c_str());row["subtype_key"]=String::utf8(d.subtypeKey.c_str());row["custom_code"]=String::utf8(d.customCode.c_str());row["native_name"]=String::utf8(d.nativeName.c_str());
    row["area_mode"]=d.areaMode;row["orientations"]=d.orientations;row["max_width"]=d.maxWidth;row["max_height"]=d.maxHeight;row["max_depth"]=d.maxDepth;row["filters"]=filters(d.filters);
    Array footprints;for(const auto& f:d.footprints)footprints.push_back(footprint(f));row["footprints"]=footprints;
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
  if (!managementDictionaryTypes(data, {"width", "height", "depth", "direction", "cursor", "building_id", "filter", "expected_list_revision"},
                                 error) ||
      !managementRequiredFields(data, error))
    return false;
  return true;
}

bool readConstruction(const Dictionary& data, wm::ManagementRequest& r, String& error) {
  int64_t a = data.get("action", actionValue(Action::Catalog)), w = data.get("width", 1),
          h = data.get("height", 1), d = data.get("direction", 0);
  int64_t cursor = data.get("cursor", 0), building = data.get("building_id", -1);
  if (a < actionValue(Action::Catalog) || (a > actionValue(Action::RemoveConstruction) && a != actionValue(Action::ConstructionMaterials)) || w < 1 ||
      w > 31 || h < 1 || h > 31 || d < 0 || d > 3 || cursor < 0 || cursor > UINT32_MAX ||
      building < -1 || building > INT32_MAX) {
    error = "Invalid management request";
    return false;
  }
  const int64_t depth=data.get("depth",1), filter=data.get("filter",-1), rev=data.get("expected_list_revision",0);
  if(depth<1 || depth>256 || w*h*depth>1024 || filter < -1 || filter>7 || rev<0) {error="Invalid bounded construction request";return false;}
  r.depth=uint16_t(depth);r.filter=int16_t(filter);r.expectedListRevision=rev;r.retracting=data.get("retracting",false);
  Array selections=data.get("selections",Array());
  if(selections.size()>16){error="Too many construction selections";return false;}
  for(int i=0;i<selections.size();++i) {
    Dictionary row=selections[i];bool valid=true;
    auto n=[&](const char* key,int64_t def,int64_t low,int64_t high){int64_t v=row.get(key,def);if(v<low || v>high)valid=false;return v;};
    wm::ConstructionSelection v;v.filter=int16_t(n("filter",-1,0,7));v.itemType=int16_t(n("item_type",-1,-1,INT16_MAX));v.itemSubtype=int16_t(n("item_subtype",-1,-1,INT16_MAX));v.matType=int16_t(n("mat_type",-1,-1,INT16_MAX));v.matIndex=int32_t(n("mat_index",-1,-1,INT32_MAX));v.count=uint32_t(n("count",0,1,UINT32_MAX));
    if(!valid){error="Invalid construction selection";return false;}r.selections.push_back(v);
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
