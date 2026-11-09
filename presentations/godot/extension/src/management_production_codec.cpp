#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include "management_codecs.h"
#include "management_dictionary.h"

namespace df3d_godot::management {
using namespace godot;
Dictionary contentsDictionary(const wm::ItemContainerContentsFacts& contents) {
  Dictionary result;result["container"]=contents.container;Array entries;
  for(const auto& e:contents.entries){Dictionary row;row["item_type"]=e.itemType;
    row["material_token"]=String::utf8(e.materialToken.c_str());row["color_token"]=String::utf8(e.colorToken.c_str());row["effective_armor_level"]=e.effectiveArmorLevel;
    row["metal"]=e.metal;row["coal"]=e.coal;row["contains_powder"]=e.containsPowder;row["rolls_sheets"]=e.rollsSheets;row["protects_folded_sheets"]=e.protectsFoldedSheets;row["contains_writing"]=e.containsWriting;entries.push_back(row);}
  result["entries"]=entries;return result;
}
namespace {
constexpr int actionValue(wm::ManagementAction a) {
  return static_cast<int>(a);
}
using Action = wm::ManagementAction;
int64_t draftNumber(const Dictionary& d,const char* key,int64_t fallback,int64_t low,int64_t high,bool& valid) {
  if(!d.has(key))return fallback;
  if(d[key].get_type()!=Variant::INT){valid=false;return fallback;}
  int64_t value=d[key];if(value<low || value>high)valid=false;return value;
}
std::vector<uint8_t> draftQueryBytes(const Dictionary& d,bool& valid) {
  if(!d.has("query_bytes") || d["query_bytes"].get_type()!=Variant::PACKED_BYTE_ARRAY){valid=false;return {};}
  PackedByteArray bytes=d["query_bytes"];if(bytes.size()>4096){valid=false;return {};}
  std::vector<uint8_t> result;for(int i=0;i<bytes.size();++i)result.push_back(bytes[i]);return result;
}
wm::WorkOrderArtDraftElement readDraftElement(const Dictionary& d,bool& valid) {
  return {int16_t(draftNumber(d,"kind",0,7,13,valid)),int32_t(draftNumber(d,"id",-1,0,INT32_MAX,valid)),
    int32_t(draftNumber(d,"secondary",-1,-1,32767,valid)),int32_t(draftNumber(d,"quantity",1,0,1000000000,valid))};
}
wm::WorkOrderArtDraftRelationship readDraftRelationship(const Dictionary& d,bool& valid) {
  bool transitive=false;
  if(d.has("transitive")){if(d["transitive"].get_type()!=Variant::BOOL)valid=false;else transitive=d["transitive"];}
  return {int32_t(draftNumber(d,"verb",-1,0,32767,valid)),transitive,
    int32_t(draftNumber(d,"actor",-1,-1,255,valid)),int32_t(draftNumber(d,"target",-1,-1,255,valid))};
}
wm::WorkOrderArtDraftValue readDraftValue(const Dictionary& d,bool& valid) {
  wm::WorkOrderArtDraftValue value;
  for(const char* key:{"elements","relationships"}) {
    if(!d.has(key) || d[key].get_type()!=Variant::ARRAY){valid=false;return value;}
    Array rows=d[key];if(rows.size()>256){valid=false;return value;}
    for(int i=0;i<rows.size();++i) {
      if(rows[i].get_type()!=Variant::DICTIONARY){valid=false;return value;}
      if(std::string(key)=="elements")value.elements.push_back(readDraftElement(Dictionary(rows[i]),valid));
      else value.relationships.push_back(readDraftRelationship(Dictionary(rows[i]),valid));
    }
  }
  if(d.has("name")) {
    if(d["name"].get_type()!=Variant::DICTIONARY){valid=false;return value;}
    Dictionary name=d["name"];value.name.emplace();auto& n=*value.name;
    const auto integers=[&](const char* key,auto& target,int64_t low,int64_t high,int count) {
      if(!name.has(key) || name[key].get_type()!=Variant::ARRAY){valid=false;return;}
      Array rows=name[key];if(rows.size()>4096 || (count>=0 && rows.size()!=count)){valid=false;return;}
      for(int i=0;i<rows.size();++i){if(rows[i].get_type()!=Variant::INT){valid=false;return;}int64_t number=rows[i];if(number<low || number>high){valid=false;return;}target.push_back(number);}
    };
    integers("first_name_bytes",n.firstNameBytes,0,255,-1);integers("nickname_bytes",n.nicknameBytes,0,255,-1);
    integers("words",n.words,-1,INT32_MAX,7);integers("parts",n.parts,0,8,7);
    n.language=int32_t(draftNumber(name,"language",-1,-1,INT32_MAX,valid));n.type=int16_t(draftNumber(name,"type",-1,-1,32767,valid));
    if(!name.has("has_name") || name["has_name"].get_type()!=Variant::BOOL)valid=false;else n.hasName=name["has_name"];
  }
  return value;
}
Dictionary writeDraftValue(const wm::WorkOrderArtDraftValue& value) {
  Dictionary result;Array elements,relationships;
  for(const auto& e:value.elements){Dictionary row;row["kind"]=e.kind;row["id"]=e.id;row["secondary"]=e.secondary;row["quantity"]=e.quantity;elements.push_back(row);}
  for(const auto& r:value.relationships){Dictionary row;row["verb"]=r.verb;row["transitive"]=r.transitive;row["actor"]=r.actor;row["target"]=r.target;relationships.push_back(row);}
  result["elements"]=elements;result["relationships"]=relationships;
  if(value.name){
    const auto& n=*value.name;Dictionary name;
    const auto integers=[](const auto& values){Array out;for(auto v:values)out.push_back(int64_t(v));return out;};
    name["first_name_bytes"]=integers(n.firstNameBytes);name["nickname_bytes"]=integers(n.nicknameBytes);
    name["words"]=integers(n.words);name["parts"]=integers(n.parts);name["language"]=n.language;name["type"]=n.type;name["has_name"]=n.hasName;result["name"]=name;
  }
  return result;
}

}  // namespace

void writeProduction(Dictionary& result, const wm::ProductionState& s) {
  Dictionary prod;
  const auto& p = s;
  auto reqs = [](const auto& values) {
    Array out;
    for (const auto& v : values) {
      Dictionary row;
      row["description"] = String::utf8(v.description.c_str());
      row["quantity"] = v.quantity;
      row["item_type"] = v.itemType;
      out.push_back(row);
    }
    return out;
  };
  Array buildings, recipes, jobs, crops, seasons;
  for (const auto& v : p.buildings) {
    Dictionary row;
    row["id"] = v.id;
    row["name"] = String::utf8(v.name.c_str());
    row["kind"] = String::utf8(v.kind.c_str());
    row["origin"] = Vector3i(v.x, v.y, v.z);
    row["build_stage"] = v.buildStage;
    row["max_stage"] = v.maxStage;
    row["queue_size"] = v.queueSize;
    buildings.push_back(row);
  }
  for (const auto& v : p.recipes) {
    Dictionary row;
    row["key"] = String::utf8(v.key.c_str());
    row["name"] = String::utf8(v.name.c_str());
    row["requirements"] = reqs(v.requirements);
    if(v.availability) {
      Dictionary availability;availability["available"]=v.availability->available;
      availability["objection"]=String::utf8(v.availability->objection.c_str());
      row["availability"]=availability;
    }
    recipes.push_back(row);
  }
  for (const auto& v : p.jobs) {
    Dictionary row;
    row["id"] = v.id;
    row["name"] = String::utf8(v.name.c_str());
    row["job_type"] = v.jobType;
    row["repeat"] = v.repeat;
    row["suspended"] = v.suspended;
    row["worker_id"] = v.workerId;
    row["worker_name"] = String::utf8(v.workerName.c_str());
    row["completion_timer"] = v.completionTimer;
    row["attached_items"] = v.attachedItems;
    row["editable"] = v.editable;
    row["status"] = String::utf8(v.status.c_str());
    row["requirements"] = reqs(v.requirements);
    jobs.push_back(row);
  }
  for (const auto& v : p.crops) {
    Dictionary row;
    row["id"] = v.id;
    row["name"] = String::utf8(v.name.c_str());
    row["seasons"] = v.seasons;
    row["seeds"] = int64_t(v.seeds);
    crops.push_back(row);
  }
  for (auto id : p.seasonalCrops)
    seasons.push_back(id);
  prod["buildings"] = buildings;
  prod["recipes"] = recipes;
  prod["jobs"] = jobs;
  prod["crops"] = crops;
  prod["seasonal_crops"] = seasons;
  prod["next_cursor"] = int64_t(p.nextCursor);
  prod["current_season"] = p.currentSeason;
  prod["selected_building"] = p.selectedBuilding;
  prod["created_job"] = p.createdJob;
  prod["detail"] = String::utf8(p.detail.c_str());
  if(p.workshopOrders) {
    const auto& c=*p.workshopOrders;Dictionary v;Array ids;
    v["building_id"]=c.buildingId;v["revision"]=int64_t(c.revision);
    v["manager_available"]=c.managerAvailable;v["general_order_limit"]=c.generalOrderLimit;
    v["outcome"]=int(c.outcome);v["delta"]=c.delta;v["value"]=c.value;
    for(const auto id:c.orderIds)ids.append(id);
    v["order_ids"]=ids;prod["workshop_orders"]=v;
  }
  if(p.workshopWorkers) {
    const auto& c=*p.workshopWorkers;Dictionary v;Array rows,permitted;
    v["building_id"]=c.buildingId;v["profile_revision"]=int64_t(c.profileRevision);
    v["revision"]=int64_t(c.revision);v["cursor"]=int64_t(c.cursor);v["next_cursor"]=int64_t(c.nextCursor);v["total"]=int64_t(c.total);
    v["outcome"]=int(c.outcome);v["unit_id"]=c.unitId;v["operation"]=int(c.operation);
    if(c.assigned){const auto& a=*c.assigned;Dictionary assigned;assigned["id"]=a.id;assigned["caption"]=String::utf8(a.caption.c_str());
      assigned["specialization_visible"]=a.specializationVisible;assigned["can_specialize"]=a.canSpecialize;assigned["specialized"]=a.specialized;v["assigned"]=assigned;}
    for(const auto id:c.permittedWorkers)permitted.push_back(id);
    v["permitted_workers"]=permitted;
    for(const auto& r:c.rows) {
      Dictionary row;Array skills;row["unit_id"]=r.unitId;row["histfig_id"]=r.histfigId;row["name"]=String::utf8(r.name.c_str());row["score"]=r.score;
      row["base_name"]=String::utf8(r.baseName.c_str());row["profession_name"]=String::utf8(r.professionName.c_str());row["profession_color"]=r.professionColor;row["legendary"]=r.legendary;
      row["source_index"]=r.sourceIndex;row["profession_order"]=r.professionOrder;row["status_order"]=r.statusOrder;
      PackedByteArray nameKey,professionKey;
      for(auto byte:r.nameSortKey)nameKey.push_back(byte);
      for(auto byte:r.professionSortKey)professionKey.push_back(byte);
      row["name_sort_key"]=nameKey;row["profession_sort_key"]=professionKey;
      for(const auto& s:r.skills) {Dictionary skill;skill["id"]=s.id;skill["rating"]=s.rating;skill["experience"]=s.experience;skill["weight"]=s.weight;skills.push_back(skill);}
      Array assignments;
      for(const auto& e:r.assignments) {Dictionary entry;entry["kind"]=int(e.kind);entry["id"]=e.id;entry["type"]=e.type;
        entry["subtype"]=e.subtype;entry["custom"]=e.custom;entry["name"]=String::utf8(e.name.c_str());entry["custom_code"]=String::utf8(e.customCode.c_str());assignments.push_back(entry);}
      row["assignments"]=assignments;
      row["skills"]=skills;rows.push_back(row);
    }
    v["rows"]=rows;prod["workshop_workers"]=v;
  }
  if(p.buildingHeader) {
    const auto& state=*p.buildingHeader;Dictionary headerState;headerState["outcome"]=int(state.outcome);headerState["operation"]=int(state.operation);
    if(state.snapshot) {
      const auto& f=*state.snapshot;Dictionary value;
      value["id"]=f.id;value["type"]=f.type;value["revision"]=int64_t(f.revision);value["stage"]=f.stage;value["max_stage"]=f.maxStage;
      value["custom_name"]=String::utf8(f.customName.c_str());value["native_name"]=String::utf8(f.nativeName.c_str());value["header_name"]=String::utf8(f.headerName.c_str());
      value["removing"]=f.removing;value["suspended"]=f.suspended;value["has_worker"]=f.hasWorker;headerState["snapshot"]=value;
    }
    prod["building_header"]=headerState;
  }
  if(p.independentItem) {
    const auto& state=*p.independentItem;Dictionary itemState;itemState["outcome"]=int(state.outcome);
    if(state.edit) {
      Dictionary edit;edit["item_id"]=state.edit->itemId;edit["farm_operation"]=int(state.edit->operation);edit["value"]=state.edit->value;itemState["edit"]=edit;
    }
    if(state.snapshot) {
      const auto& s=*state.snapshot;Dictionary value;
      if(s.ammunitionAssignment){const auto& a=*s.ammunitionAssignment;Dictionary row;row["kind"]=a.kind;row["squad_id"]=a.squadId;row["caption"]=String::utf8(a.caption.c_str());value["ammunition_assignment"]=row;}
      value["stockpile_categories"]=s.stockpileCategories;value["id"]=s.id;value["revision"]=int64_t(s.revision);value["item_type"]=s.itemType;
      value["name"]=String::utf8(s.name.c_str());value["material_token"]=String::utf8(s.materialToken.c_str());value["subtype_raw"]=String::utf8(s.subtypeRaw.c_str());
      value["weight"]=String::utf8(s.weight.c_str());value["description"]=String::utf8(s.description.c_str());
      value["forbid"]=s.forbid;value["dump"]=s.dump;value["melt"]=s.melt;value["hidden"]=s.hidden;
      value["can_dump"]=s.canDump;value["can_melt"]=s.canMelt;value["in_job"]=s.inJob;value["in_building"]=s.inBuilding;
      const auto link=[](const wm::ItemBuildingHolder& source){Dictionary v;v["id"]=source.id;v["type"]=source.type;v["name"]=String::utf8(source.name.c_str());return v;};
      if(s.appearance){const auto& a=*s.appearance;Dictionary look;look["material_token"]=String::utf8(a.materialToken.c_str());look["subtype_raw"]=String::utf8(a.subtypeRaw.c_str());look["color_token"]=String::utf8(a.colorToken.c_str());look["stack"]=a.stack;look["flags"]=a.flags;if(a.floodgateOpen>=0)look["floodgate_open"]=bool(a.floodgateOpen);if(a.doorOpen>=0){Dictionary door;door["open"]=bool(a.doorOpen);door["forbidden"]=bool(a.doorForbidden);door["wear"]=a.doorWear;look["door"]=door;}if(a.contents)look["contents"]=contentsDictionary(*a.contents);if(a.instrumentFamily>=0){Dictionary instrument;instrument["family"]=a.instrumentFamily;instrument["placed"]=a.instrumentPlaced;look["instrument"]=instrument;}value["appearance"]=look;}
      if(s.holder)value["holder"]=link(*s.holder);if(s.stockpile)value["stockpile"]=link(*s.stockpile);
      if(s.owner){Dictionary owner;owner["id"]=s.owner->id;owner["name"]=String::utf8(s.owner->name.c_str());value["owner"]=owner;}
      if(s.carrier){const auto& c=*s.carrier;Dictionary v;v["kind"]=c.kind;v["id"]=c.id;v["item_type"]=c.itemType;v["name"]=String::utf8(c.name.c_str());if(c.appearance){const auto& a=*c.appearance;Dictionary look;look["material_token"]=String::utf8(a.materialToken.c_str());look["subtype_raw"]=String::utf8(a.subtypeRaw.c_str());look["color_token"]=String::utf8(a.colorToken.c_str());look["stack"]=a.stack;look["flags"]=a.flags;if(a.floodgateOpen>=0)look["floodgate_open"]=bool(a.floodgateOpen);if(a.doorOpen>=0){Dictionary door;door["open"]=bool(a.doorOpen);door["forbidden"]=bool(a.doorForbidden);door["wear"]=a.doorWear;look["door"]=door;}if(a.contents)look["contents"]=contentsDictionary(*a.contents);if(a.instrumentFamily>=0){Dictionary instrument;instrument["family"]=a.instrumentFamily;instrument["placed"]=a.instrumentPlaced;look["instrument"]=instrument;}v["appearance"]=look;}value["carrier"]=v;}
      itemState["snapshot"]=value;
    }
    prod["independent_item"]=itemState;
  }
  if(p.itemPosition) {
    Dictionary value;value["id"]=p.itemPosition->id;value["position"]=Vector3i(p.itemPosition->x,p.itemPosition->y,p.itemPosition->z);
    prod["item_position"]=value;
  }
  if(p.contentsEdit) {
    Dictionary edit;edit["item_id"]=p.contentsEdit->itemId;edit["farm_operation"]=int(p.contentsEdit->operation);
    edit["value"]=p.contentsEdit->value;prod["contents_edit"]=edit;
  }
  if(p.contents) {
    const auto& page=*p.contents;Dictionary value;Array rows;
    value["building_id"]=page.buildingId;value["revision"]=int64_t(page.revision);
    value["cursor"]=page.cursor;value["next_cursor"]=page.nextCursor;value["total"]=page.total;
    value["completed"]=page.completed;value["removing"]=page.removing;
    for(const auto& item:page.rows) {
      Dictionary row;row["id"]=item.id;row["role"]=item.role;row["name"]=String::utf8(item.name.c_str());
      row["forbid"]=item.forbid;row["dump"]=item.dump;row["melt"]=item.melt;row["hidden"]=item.hidden;
      row["can_dump"]=item.canDump;row["can_melt"]=item.canMelt;row["in_job"]=item.inJob;row["in_building"]=item.inBuilding;
      row["item_type"]=item.itemType;row["material_token"]=String::utf8(item.materialToken.c_str());row["subtype_raw"]=String::utf8(item.subtypeRaw.c_str());
      if(item.appearance){const auto& a=*item.appearance;Dictionary look;look["material_token"]=String::utf8(a.materialToken.c_str());look["subtype_raw"]=String::utf8(a.subtypeRaw.c_str());look["color_token"]=String::utf8(a.colorToken.c_str());look["stack"]=a.stack;look["flags"]=a.flags;if(a.floodgateOpen>=0)look["floodgate_open"]=bool(a.floodgateOpen);if(a.doorOpen>=0){Dictionary door;door["open"]=bool(a.doorOpen);door["forbidden"]=bool(a.doorForbidden);door["wear"]=a.doorWear;look["door"]=door;}if(a.contents)look["contents"]=contentsDictionary(*a.contents);if(a.instrumentFamily>=0){Dictionary instrument;instrument["family"]=a.instrumentFamily;instrument["placed"]=a.instrumentPlaced;look["instrument"]=instrument;}row["appearance"]=look;}
      rows.push_back(row);
    }
    value["rows"]=rows;prod["contents"]=value;
  }
  if(p.item) {
    const auto& source=*p.item;const auto& row=source.item;Dictionary value;
    value["building_id"]=source.buildingId;value["revision"]=int64_t(source.revision);
    value["completed"]=source.completed;value["removing"]=source.removing;
    value["id"]=row.id;value["role"]=row.role;value["name"]=String::utf8(row.name.c_str());
    value["item_type"]=row.itemType;value["material_token"]=String::utf8(row.materialToken.c_str());value["subtype_raw"]=String::utf8(row.subtypeRaw.c_str());
    value["forbid"]=row.forbid;value["dump"]=row.dump;value["melt"]=row.melt;value["hidden"]=row.hidden;
    value["can_dump"]=row.canDump;value["can_melt"]=row.canMelt;value["in_job"]=row.inJob;value["in_building"]=row.inBuilding;
    if(row.appearance){const auto& a=*row.appearance;Dictionary look;look["material_token"]=String::utf8(a.materialToken.c_str());look["subtype_raw"]=String::utf8(a.subtypeRaw.c_str());look["color_token"]=String::utf8(a.colorToken.c_str());look["stack"]=a.stack;look["flags"]=a.flags;if(a.floodgateOpen>=0)look["floodgate_open"]=bool(a.floodgateOpen);if(a.doorOpen>=0){Dictionary door;door["open"]=bool(a.doorOpen);door["forbidden"]=bool(a.doorForbidden);door["wear"]=a.doorWear;look["door"]=door;}if(a.contents)look["contents"]=contentsDictionary(*a.contents);if(a.instrumentFamily>=0){Dictionary instrument;instrument["family"]=a.instrumentFamily;instrument["placed"]=a.instrumentPlaced;look["instrument"]=instrument;}value["appearance"]=look;}
    value["weight"]=String::utf8(source.weight.c_str());value["description"]=String::utf8(source.description.c_str());
    if(source.holder) {
      Dictionary holder;holder["id"]=source.holder->id;holder["type"]=source.holder->type;holder["name"]=String::utf8(source.holder->name.c_str());
      value["holder"]=holder;
    }
    prod["item"]=value;
  }
  prod["farm_edit_outcome"]=int(p.farmEditOutcome);
  if(p.farm) {
    const auto& f=*p.farm;Dictionary farm;Array choices,selected;
    farm["custom_name"]=String::utf8(f.customName.c_str());farm["header_name"]=String::utf8(f.headerName.c_str());
    farm["removing"]=f.removing;farm["removal_suspended"]=f.removalSuspended;farm["removal_has_worker"]=f.removalHasWorker;
    farm["building_id"]=f.buildingId;farm["revision"]=int64_t(f.revision);
    farm["selected_season"]=f.selectedSeason;farm["current_season"]=f.currentSeason;
    farm["current_fertilization"]=f.currentFertilization;farm["max_fertilization"]=f.maxFertilization;
    farm["pending_fertilization"]=f.pendingFertilization;farm["seasonal_fertilization"]=f.seasonalFertilization;
    for(auto crop:f.seasonalCrops)selected.push_back(crop);
    for(const auto& c:f.choices) {
      Dictionary row;row["id"]=c.id;row["name"]=String::utf8(c.name.c_str());
      row["raw_id"]=String::utf8(c.rawId.c_str());
      row["seeds_available"]=c.seedsAvailable;row["current_season_warning"]=c.currentSeasonWarning;
      choices.push_back(row);
    }
    farm["seasonal_crops"]=selected;farm["choices"]=choices;prod["farm"]=farm;
  }
  result["production"] = prod;
}

Dictionary writeArtState(const wm::WorkOrderArtState& a) {
Dictionary art;art["page"]=a.page;art["caption"]=String::utf8(a.caption.c_str());
  art["list_revision"]=int64_t(a.listRevision);art["total"]=int64_t(a.total);art["next_cursor"]=int64_t(a.nextCursor);
  art["hovered"]=a.hovered;
  if(a.preview){Array lines;for(const auto& line:*a.preview)lines.push_back(String::utf8(line.c_str()));art["preview"]=lines;}
  Array rows;for(const auto& r:a.rows){Dictionary row;row["id"]=r.id;row["secondary"]=r.secondary;row["caption"]=String::utf8(r.caption.c_str());if(r.badge)row["badge"]=String::utf8(r.badge->c_str());rows.push_back(row);}art["rows"]=rows;
  if(a.draft)art["draft"]=writeDraftValue(*a.draft);
  if(a.draftDescription){Array lines;for(const auto& line:*a.draftDescription)lines.push_back(String::utf8(line.c_str()));art["draft_description"]=lines;}
  if(a.name) {
    const auto& n=*a.name;Dictionary name;name["native_header"]=String::utf8(n.nativeHeader.c_str());name["english_header"]=String::utf8(n.englishHeader.c_str());
    name["component"]=n.component;PackedByteArray bytes;for(auto byte:n.queryBytes)bytes.push_back(byte);name["query_bytes"]=bytes;
    name["cursor"]=int64_t(n.cursor);name["total"]=int64_t(n.total);name["next_cursor"]=int64_t(n.nextCursor);
    Array choices;for(const auto& r:n.choices){Dictionary row;row["word"]=r.word;row["part"]=r.part;row["english"]=String::utf8(r.english.c_str());row["translated"]=String::utf8(r.translated.c_str());choices.push_back(row);}name["choices"]=choices;art["name"]=name;
  }
  return art;
}

void writeWorkOrder(Dictionary& result, const wm::WorkOrderState& s) {
  Dictionary work;
  const auto& ws = s;
  if(ws.nativeState) {
    Dictionary native;native["manager_available"]=ws.nativeState->managerAvailable;
    native["validation_required"]=ws.nativeState->validationRequired;work["native_state"]=native;
  }
  if(ws.details) {
    const auto& d=*ws.details;Dictionary details;
    details["id"]=d.id;details["revision"]=int64_t(d.revision);details["caption"]=String::utf8(d.caption.c_str());
    details["selected_option"]=d.selectedOption;details["choices_revision"]=int64_t(d.choicesRevision);
    details["total"]=int64_t(d.total);details["next_cursor"]=int64_t(d.nextCursor);
    if(d.currentValue)details["current_value"]=String::utf8(d.currentValue->c_str());
    if(d.settingHeading)details["setting_heading"]=String::utf8(d.settingHeading->c_str());
    details["dye_target"]=d.dyeTarget;
    if(d.art)details["art"]=writeArtState(*d.art);
    Array options;for(const auto& o:d.options){Dictionary option;option["kind"]=o.kind;option["index"]=o.index;option["caption"]=String::utf8(o.caption.c_str());options.push_back(option);}details["options"]=options;
    if(d.choices) {
      Array choices;for(const auto& c:*d.choices){Dictionary choice;choice["id"]=c.id;choice["caption"]=String::utf8(c.caption.c_str());if(c.countCaption)choice["count_caption"]=String::utf8(c.countCaption->c_str());choice["estimated"]=c.estimated;choice["dye_color"]=c.dyeColor;choice["opens_menu"]=c.opensMenu;if(c.swatch){Dictionary color;color["red"]=c.swatch->red;color["green"]=c.swatch->green;color["blue"]=c.swatch->blue;choice["swatch"]=color;}choices.push_back(choice);}details["choices"]=choices;
    }
    work["details"]=details;
  }
  Array orders, orderRecipes, orderChoices, managers;
  for (const auto& o : ws.orders) {
    Dictionary row;
    if(o.nativeState) {
      Dictionary native;native["phase"]=int(o.nativeState->phase);
      native["validation_required"]=o.nativeState->validationRequired;native["details_available"]=o.nativeState->detailsAvailable;
      if(o.nativeState->workshopName)native["workshop_name"]=String::utf8(o.nativeState->workshopName->c_str());
      row["native_state"]=native;
    }
    row["id"] = o.id;
    row["revision"] = int64_t(o.revision);
    row["name"] = String::utf8(o.name.c_str());
    row["total"] = o.total;
    row["remaining"] = o.remaining;
    row["frequency"] = o.frequency;
    row["validated"] = o.validated;
    row["active"] = o.active;
    row["finished_year"] = o.finishedYear;
    row["finished_tick"] = o.finishedTick;
    row["workshop_id"] = o.workshopId;
    row["max_workshops"] = o.maxWorkshops;
    row["editable"] = o.editable;
    row["reason"] = String::utf8(o.reason.c_str());
    row["position"]=o.position;row["detail_kind"]=o.detailKind;row["size_raw"]=o.sizeRaw;
    row["encrust_flags"]=o.encrustFlags;row["mat_type"]=o.matType;row["mat_index"]=o.matIndex;
    row["material_category"]=int64_t(o.materialCategory);
    Array inputRows;
    for(const auto& i:o.inputs) {
      Dictionary v;v["index"]=i.index;v["description"]=String::utf8(i.description.c_str());
      v["mat_type"]=i.matType;v["mat_index"]=i.matIndex;v["editable"]=i.editable;inputRows.push_back(v);
    }
    row["inputs"]=inputRows;
    Array ids, cs;
    for (auto id : o.generatedJobs)
      ids.push_back(id);
    const auto encodeConditions=[&](const auto& values) {
    Array converted;
    for (const auto& c : values) {
      Dictionary v;
      v["kind"] = c.kind;
      v["index"] = c.index;
      v["description"] = String::utf8(c.description.c_str());
      v["editable"] = c.editable;
      v["compare"] = c.compare;
      v["threshold"] = c.threshold;
      v["item_type"] = c.itemType;
      v["target_order"] = c.targetOrder;
      v["dependency"] = c.dependency;
      v["satisfied"] = c.satisfied;
      v["item_subtype"]=c.itemSubtype;v["mat_type"]=c.matType;v["mat_index"]=c.matIndex;
      v["satisfaction"]=c.satisfaction;v["estimated"]=c.estimated;v["estimate_count"]=c.estimateCount;
      Array traits;for(const auto& t:c.traits)traits.push_back(String::utf8(t.c_str()));v["traits"]=traits;
      if(c.itemCaption)v["item_caption"]=String::utf8(c.itemCaption->c_str());
      converted.push_back(v);
    }
    return converted;
    };
    cs=encodeConditions(o.conditions);
    if(o.suggestedConditions)row["suggested_conditions"]=encodeConditions(*o.suggestedConditions);
    row["generated_jobs"] = ids;
    row["conditions"] = cs;
    orders.push_back(row);
  }
  for (const auto& r : ws.recipes) {
    Dictionary v;
    v["key"] = String::utf8(r.key.c_str());
    v["name"] = String::utf8(r.name.c_str());
    orderRecipes.push_back(v);
  }
  for (const auto& c : ws.choices) {
    Dictionary v;
    v["id"] = c.id;
    v["name"] = String::utf8(c.name.c_str());
    orderChoices.push_back(v);
  }
  for (const auto& m : ws.managers) {
    Dictionary v;
    v["unit_id"] = m.unitId;
    v["name"] = String::utf8(m.name.c_str());
    v["position"] = String::utf8(m.position.c_str());
    v["job"] = String::utf8(m.job.c_str());
    Array ids;
    for (auto id : m.offices)
      ids.push_back(id);
    v["offices"] = ids;
    managers.push_back(v);
  }
  Array materials,traits,types,groups,tasks;
  for(const auto& r:ws.materials){Dictionary v;v["mat_type"]=r.matType;v["mat_index"]=r.matIndex;v["name"]=String::utf8(r.name.c_str());materials.push_back(v);}
  for(const auto& r:ws.traits){Dictionary v;v["key"]=String::utf8(r.key.c_str());v["name"]=String::utf8(r.name.c_str());traits.push_back(v);}
  for(const auto& r:ws.types){Dictionary v;v["item_type"]=r.itemType;v["item_subtype"]=r.itemSubtype;v["name"]=String::utf8(r.name.c_str());types.push_back(v);}
  for(const auto& r:ws.groups){Dictionary v;v["type"]=r.type;v["subtype"]=r.subtype;v["custom"]=r.custom;v["name"]=String::utf8(r.name.c_str());v["count"]=int64_t(r.count);if(r.customCode)v["custom_code"]=String::utf8(r.customCode->c_str());groups.push_back(v);}
  for(const auto& r:ws.tasks){Dictionary v;v["key"]=String::utf8(r.key.c_str());v["name"]=String::utf8(r.name.c_str());v["job_type"]=r.jobType;v["reaction"]=String::utf8(r.reaction.c_str());v["item_type"]=r.itemType;v["item_subtype"]=r.itemSubtype;v["mat_type"]=r.matType;v["mat_index"]=r.matIndex;tasks.push_back(v);}
  work["materials"]=materials;work["traits"]=traits;work["types"]=types;work["groups"]=groups;work["tasks"]=tasks;
  work["total"]=int64_t(ws.total);work["list_revision"]=ws.listRevision;work["build_phase"]=ws.buildPhase;
  work["build_done"]=int64_t(ws.buildDone);work["build_total"]=int64_t(ws.buildTotal);
  work["orders"] = orders;
  work["recipes"] = orderRecipes;
  work["choices"] = orderChoices;
  work["managers"] = managers;
  work["next_cursor"] = int64_t(ws.nextCursor);
  work["detail"] = String::utf8(ws.detail.c_str());
  result["work_order"] = work;
}

bool validateWorkOrderShape(const Dictionary& data, String& error) {
  if(data.has("details")) {
    if(data["details"].get_type()!=Variant::DICTIONARY){error="Details must be a Dictionary";return false;}
    Dictionary details=data["details"];
    for(const char* key:{"option","choice","expected_choices_revision","cursor","dye_target"})
      if(details.has(key) && details[key].get_type()!=Variant::INT){error=String("Wrong Details field type: ")+key;return false;}
    if(details.has("query") && details["query"].get_type()!=Variant::STRING){error="Details query must be a String";return false;}
    if(details.has("dye_filter_applied") && details["dye_filter_applied"].get_type()!=Variant::BOOL){error="Details dye filter flag must be a bool";return false;}
    if(details.has("art")) {
      if(details["art"].get_type()!=Variant::DICTIONARY){error="Artwork must be a Dictionary";return false;}
      Dictionary art=details["art"];
      for(const char* key:{"page","subject","expected_list_revision","cursor","hovered","preview_columns"})
        if(art.has(key) && art[key].get_type()!=Variant::INT){error=String("Wrong artwork field type: ")+key;return false;}
      if(art.has("query") && art["query"].get_type()!=Variant::STRING){error="Artwork query must be a String";return false;}
    }
  }
  if (!managementDictionaryTypes(
          data,
          {"id", "expected_revision", "cursor", "remaining", "frequency", "workshop_id",
           "max_workshops", "condition_kind", "condition_index", "compare", "threshold",
           "item_type", "target_order", "dependency", "candidate_kind", "move", "expected_neighbor",
           "expected_list_revision", "item_subtype", "mat_type", "mat_index", "input_index",
           "group_type", "group_subtype", "group_custom", "encrust_flags", "suggestion_index", "filter_choice"},
          error) ||
      !managementRequiredFields(data, error))
    return false;
  if(data.has("traits")) {
    if(data["traits"].get_type()!=Variant::ARRAY){error="Work-order traits must be an Array of String";return false;}
    Array traits=data["traits"];
    for(int i=0;i<traits.size();++i)if(traits[i].get_type()!=Variant::STRING){error="Work-order traits must be an Array of String";return false;}
  }
  return true;
}

// Work-order payloads (action is a required INT, 20..27):
// List(20): query, cursor. Inspect(21): required id.
// Create(22): required recipe, remaining; optional frequency, workshop_id, max_workshops.
// Update(23): required id, expected_revision; remaining, frequency, workshop_id, max_workshops.
// Delete(24): required id, expected_revision (retains removed native storage).
// Condition(25): required id, expected_revision; condition_kind, condition_index,
//   remove_condition, compare, threshold, item_type, target_order, dependency.
// Candidates(26): candidate_kind, query, cursor. Catalog(27): no additional keys.
// All numeric keys are INT: id -1..INT32_MAX (-1 none); expected_revision >0
// for edits, from Inspect/List revision (otherwise 0). The reader accepts 0;
// the model enforces >0 for actions 23..25 ("work order revision required").
// cursor 0..UINT32_MAX.
// recipe (Catalog key) and query are STRING, at most 128/64 UTF-8 bytes respectively.
// remaining -1..32767 (-1 unchanged, Create requires >=0; 0 indefinite);
// frequency -1..4 (-1 unchanged/OneTime; 0 OneTime, 1 Daily, 2 Monthly,
// 3 Seasonally, 4 Yearly); workshop_id -2..INT32_MAX (-2 unchanged, -1 any shop);
// max_workshops -1..32767 (-1 unchanged, 0 unlimited); condition_kind 0 item/1 order;
// condition_index -1..63 (-1 new); remove_condition BOOL (default false);
// compare -1..5 (-1 unset; AtLeast, AtMost, GreaterThan, LessThan, Exactly, Not);
// threshold -1..INT32_MAX (-1 unset); item_type int16 -1..32767 (-1 any item);
// target_order -1..INT32_MAX (-1 none); dependency -1..1 (-1 unset, 0 Activated,
// 1 Completed); candidate_kind 0 orders/1 workshops/2 base types/3 types/4 materials/5 traits.
bool readArtRequest(const Dictionary& art,wm::WorkOrderArtRequest& a) {
  bool valid=true;
  const auto artNumber=[&](const char* key,int64_t def,int64_t low,int64_t high){int64_t v=art.get(key,def);if(v<low || v>high)valid=false;return v;};
  a.page=int16_t(artNumber("page",-1,-1,18));a.subject=int32_t(artNumber("subject",-1,-1,INT32_MAX));
  a.expectedListRevision=uint64_t(artNumber("expected_list_revision",0,0,INT64_MAX));a.cursor=uint32_t(artNumber("cursor",0,0,262144));
  a.hovered=int32_t(artNumber("hovered",-1,-1,INT32_MAX));a.previewColumns=uint16_t(artNumber("preview_columns",0,0,256));
  String artQuery=art.get("query",String());a.query=artQuery.utf8().get_data();if(a.query.size()>128)valid=false;
  if(art.has("draft")) {
    if(art["draft"].get_type()!=Variant::DICTIONARY)valid=false;
    else {
      Dictionary draft=art["draft"];a.draft.emplace();auto& v=*a.draft;
      v.action=wm::WorkOrderArtDraftAction(draftNumber(draft,"action",0,0,6,valid));
      v.deleteIndex=int32_t(draftNumber(draft,"delete_index",-1,-1,511,valid));v.columns=uint16_t(draftNumber(draft,"columns",0,1,256,valid));
      if(!draft.has("value") || draft["value"].get_type()!=Variant::DICTIONARY)valid=false;
      else v.value=readDraftValue(Dictionary(draft["value"]),valid);
      if(draft.has("element")){if(draft["element"].get_type()!=Variant::DICTIONARY)valid=false;else v.element=readDraftElement(Dictionary(draft["element"]),valid);}
      if(draft.has("relationship")){if(draft["relationship"].get_type()!=Variant::DICTIONARY)valid=false;else v.relationship=readDraftRelationship(Dictionary(draft["relationship"]),valid);}
      if(draft.has("name_query")) {
        if(draft["name_query"].get_type()!=Variant::DICTIONARY)valid=false;
        else {Dictionary n=draft["name_query"];v.nameQuery.emplace();v.nameQuery->component=uint8_t(draftNumber(n,"component",0,0,6,valid));v.nameQuery->cursor=uint32_t(draftNumber(n,"cursor",0,0,262144,valid));v.nameQuery->queryBytes=draftQueryBytes(n,valid);}
      }
      if(draft.has("name_edit")) {
        if(draft["name_edit"].get_type()!=Variant::DICTIONARY)valid=false;
        else {Dictionary n=draft["name_edit"];v.nameEdit.emplace();auto& e=*v.nameEdit;
          e.mode=wm::LocationNameMode(draftNumber(n,"mode",0,0,3,valid));e.target=int8_t(draftNumber(n,"target",-1,-1,6,valid));e.displayed=int8_t(draftNumber(n,"displayed",-1,-1,6,valid));
          e.word=int32_t(draftNumber(n,"word",-1,-1,INT32_MAX,valid));e.part=int16_t(draftNumber(n,"part",-1,-1,8,valid));e.queryBytes=draftQueryBytes(n,valid);
        }
      }
    }
  }
  return valid;
}

bool readWorkOrder(const Dictionary& data, wm::ManagementRequest& r, String& error) {
  bool valid = true;
  auto n = [&](const char* key, int64_t def, int64_t low, int64_t high) {
    int64_t v = data.get(key, def);
    if (v < low || v > high)
      valid = false;
    return v;
  };
  r.action = wm::ManagementAction(n("action", actionValue(Action::WorkOrderList),
                                    actionValue(Action::WorkOrderList),
                                    actionValue(Action::WorkOrderCatalog)));
  auto& w = r.workOrder;
  w.id = int32_t(n("id", -1, -1, INT32_MAX));
  w.expectedRevision = uint64_t(n("expected_revision", 0, 0, INT64_MAX));
  w.cursor = uint32_t(n("cursor", 0, 0, UINT32_MAX));
  w.remaining = int32_t(n("remaining", r.action == wm::ManagementAction::WorkOrderCreate ? 10 : -1, -1, 32767));
  w.frequency = int8_t(n("frequency", -1, -1, 4));
  w.workshopId = int32_t(n("workshop_id", -2, -2, INT32_MAX));
  w.maxWorkshops = int32_t(n("max_workshops", -1, -1, 32767));
  w.conditionKind = uint8_t(n("condition_kind", 0, 0, 1));
  w.conditionIndex = int16_t(n("condition_index", -1, -1, 63));
  w.removeCondition = data.get("remove_condition", false);
  w.compare = int8_t(n("compare", -1, -1, 5));
  w.threshold = int32_t(n("threshold", -1, -1, INT32_MAX));
  w.itemType = int16_t(n("item_type", -1, -1, 32767));
  w.targetOrder = int32_t(n("target_order", -1, -1, INT32_MAX));
  w.dependency = int8_t(n("dependency", -1, -1, 1));
  w.candidateKind = uint8_t(n("candidate_kind", 0, 0, 5));
  w.move=int8_t(n("move",0,-1,1));w.expectedNeighbor=int32_t(n("expected_neighbor",-1,-1,INT32_MAX));
  w.expectedListRevision=n("expected_list_revision",0,0,INT64_MAX);
  w.itemSubtype=int16_t(n("item_subtype",-1,-1,INT16_MAX));w.matType=int16_t(n("mat_type",-1,-1,INT16_MAX));w.matIndex=int32_t(n("mat_index",-1,-1,INT32_MAX));
  w.inputIndex=int16_t(n("input_index",-1,-1,INT16_MAX));w.groupType=int16_t(n("group_type",-1,-1,INT16_MAX));w.groupSubtype=int16_t(n("group_subtype",-1,-1,INT16_MAX));
  w.groupCustom=int32_t(n("group_custom",-1,-1,INT32_MAX));w.encrustFlags=int32_t(n("encrust_flags",-1,-1,INT32_MAX));
  w.suggestionIndex=int16_t(n("suggestion_index",-1,-1,127));
  w.filterChoice=int32_t(n("filter_choice",-1,-1,32767));
  if(data.has("details")) {
    Dictionary details=data["details"];w.details.emplace();auto& d=*w.details;
    const auto number=[&](const char* key,int64_t def,int64_t low,int64_t high){int64_t v=details.get(key,def);if(v<low || v>high)valid=false;return v;};
    d.option=int16_t(number("option",-1,-1,64));d.choice=int32_t(number("choice",-1,-1,16383));
    d.expectedChoicesRevision=uint64_t(number("expected_choices_revision",0,0,INT64_MAX));d.cursor=uint32_t(number("cursor",0,0,16384));
    d.dyeTarget=int32_t(number("dye_target",-1,-1,1023));d.dyeFilterApplied=details.get("dye_filter_applied",false);
    String query=details.get("query",String());d.query=query.utf8().get_data();if(d.query.size()>128)valid=false;
    if(details.has("art")){d.art.emplace();if(!readArtRequest(Dictionary(details["art"]),*d.art))valid=false;}
  }
  w.traits.reset();
  if(data.has("traits")) {
    Array values=data["traits"];w.traits.emplace();
    if(values.size()>256)valid=false;
    else for(int i=0;i<values.size();++i) {
      String t=values[i];std::string value=t.utf8().get_data();
      if(value.size()>64)valid=false;
      w.traits->push_back(std::move(value));
    }
  }
  String recipe = data.get("recipe", String()), query = data.get("query", String());
  w.recipe = recipe.utf8().get_data();
  w.query = query.utf8().get_data();
  if (w.recipe.size() > 128 || w.query.size() > (r.action==wm::ManagementAction::WorkOrderCatalog && w.workshopId>=0?76:64)) valid = false;
  if (!valid) {
    error = "Invalid bounded work order request";
    return false;
  }
  return true;
}

bool validateProductionShape(const Dictionary& data, String& error) {
  if(data.has("workshop_orders") && data["workshop_orders"].get_type()!=Variant::BOOL){error="Wrong management field type: workshop_orders";return false;}
  if(!managementDictionaryTypes(data, {"general_order_delta", "general_order_value"}, error))return false;
  if(data.has("workshop_workers") && data["workshop_workers"].get_type()!=Variant::BOOL){error="Wrong management field type: workshop_workers";return false;}
  if(data.has("building_header") && data["building_header"].get_type()!=Variant::BOOL){error="Wrong management field type: building_header";return false;}
  if(data.has("independent_item") && data["independent_item"].get_type()!=Variant::BOOL){error="Wrong management field type: independent_item";return false;}
  if(data.has("locate_item") && data["locate_item"].get_type()!=Variant::BOOL){error="Wrong management field type: locate_item";return false;}
  if(!managementDictionaryTypes(data, {"building_id", "job_id", "crop_id", "cursor", "repeat", "suspend", "season", "expected_revision", "farm_operation", "seasonal_fertilization", "item_id", "item_value", "worker_id", "worker_list_revision", "worker_value"}, error))return false;
  if(data.has("farm_name") && data["farm_name"].get_type()!=Variant::STRING) {error="Wrong management field type: farm_name";return false;}
  if(int64_t(data.get("farm_operation",0))==3 && !data.has("farm_name")) {error="Missing management field: farm_name";return false;}
  return managementRequiredFields(data, error);
}

// production payload (actions 15 List, 16 Inspect, 17 Queue, 18 JobEdit, 19 FarmEdit):
// building_id: int, -1 none; required 16-19, ignored by 15.
// job_id: int, -1 none; required 18, from Inspect jobs[].id.
// recipe: String <=128 UTF-8 bytes; required 17, from Inspect recipes[].key.
// query: String <=128 UTF-8 bytes (15); cursor: int >=0 (15), resume at next_cursor building id.
// repeat: int -1..1; 17: 1 repeating, otherwise one-time; 18: -1 unchanged, 0 off, 1 on.
// suspend: int -1..1 (18), -1 unchanged, 0 resume, 1 suspend and release worker.
// cancel: bool (18), remove job; exclusive with repeat/suspend changes.
// expected_revision: positive int64 (19), from the displayed native farm snapshot.
// season: int 0..3 (Spring, Summer, Autumn, Winter), required 19.
// crop_id: int -1..32767 (19), plant raw id from farm.choices[].id, -1 fallow; required 19.
bool readProduction(const Dictionary& data, wm::ManagementRequest& r, String& error) {
  bool valid = true;
  auto n = [&](const char* key, int64_t def, int64_t low, int64_t high) {
    int64_t value = data.get(key, def);
    if (value < low || value > high) valid = false;
    return value;
  };
  r.action = wm::ManagementAction(n("action", 0, static_cast<int>(wm::ManagementAction::ProductionList),
      static_cast<int>(wm::ManagementAction::FarmEdit)));
  auto& value = r.production;
  value.buildingId = int32_t(n("building_id", -1, -1, INT32_MAX));
  value.jobId = int32_t(n("job_id", -1, -1, INT32_MAX));
  value.expectedRevision=uint64_t(n("expected_revision",0,0,INT64_MAX));
  if(data.has("contents") && data["contents"].get_type()!=Variant::BOOL){error="Wrong management field type: contents";return false;}
  value.contents=data.get("contents",false);
  if(data.has("locate_item") && data["locate_item"].get_type()!=Variant::BOOL){error="Wrong management field type: locate_item";return false;}
  value.locateItem=data.get("locate_item",false);
  if(data.has("independent_item") && data["independent_item"].get_type()!=Variant::BOOL){error="Wrong management field type: independent_item";return false;}
  value.independentItem=data.get("independent_item",false);
  if(data.has("workshop_workers") && data["workshop_workers"].get_type()!=Variant::BOOL){error="Wrong management field type: workshop_workers";return false;}
  if(data.has("building_header") && data["building_header"].get_type()!=Variant::BOOL){error="Wrong management field type: building_header";return false;}
  value.buildingHeader=data.get("building_header",false);
  if(data.has("workshop_orders") && data["workshop_orders"].get_type()!=Variant::BOOL){error="Wrong management field type: workshop_orders";return false;}
  value.workshopOrders=data.get("workshop_orders",false);
  value.generalOrderDelta=int8_t(n("general_order_delta",0,-1,1));
  value.generalOrderValue=int16_t(n("general_order_value",-1,-1,99));
  value.workshopWorkers=data.get("workshop_workers",false);
  value.workerId=int32_t(n("worker_id",-1,-1,INT32_MAX));value.workerListRevision=uint64_t(n("worker_list_revision",0,0,INT64_MAX));value.workerValue=int8_t(n("worker_value",-1,-1,1));
  value.farmOperation=wm::FarmOperation(n("farm_operation",0,0,12));
  value.itemId=int32_t(n("item_id",-1,-1,INT32_MAX));value.itemValue=int8_t(n("item_value",-1,-1,1));
  String farmName=data.get("farm_name",String());
  const auto nameBytes=farmName.utf8();value.farmName.assign(nameBytes.get_data(),nameBytes.length());
  if(value.farmName.size()>90)valid=false;
  if(data.has("farm_name") && value.farmOperation!=wm::FarmOperation::Rename) {error="unexpected farm name";return false;}
  value.seasonalFertilization=int8_t(n("seasonal_fertilization",-1,-1,1));
  value.cropId = int32_t(n("crop_id", -1, -1, 32767));
  value.cursor = uint32_t(n("cursor", 0, 0, UINT32_MAX));
  value.repeat = int8_t(n("repeat", -1, -1, 1));
  value.suspend = int8_t(n("suspend", -1, -1, 1));
  value.season = int8_t(n("season", -1, -1, 3));
  String recipe = data.get("recipe", String());
  value.recipe = recipe.utf8().get_data();
  if (value.recipe.size() > 128) valid = false;
  String query = data.get("query", String());
  value.query = query.utf8().get_data();
  if (value.query.size() > (r.action==Action::ProductionInspect?138:128)) valid = false;
  value.cancel = data.get("cancel", false);
  if (!valid) { error = "Invalid bounded production request"; return false; }
  return true;
}
}  // namespace df3d_godot::management
