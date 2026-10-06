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
Dictionary areaZoneDictionary(const wm::AreaZoneSettings& z) {
  Dictionary out;out["pond_mode"]=z.pondMode;out["facing"]=z.facing;
  out["tomb_citizens"]=z.tombCitizens;out["tomb_pets"]=z.tombPets;
  out["gather_trees"]=z.gatherTrees;out["gather_shrubs"]=z.gatherShrubs;
  return out;
}
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
  construction["outcome"]=int(c.outcome);construction["updated"]=int64_t(c.updated);construction["failed_index"]=c.failedIndex;
  construction["building_key"]=String::utf8(c.buildingKey.c_str());construction["filter"]=c.filter;construction["filters"]=filters(c.filters);
  construction["total"]=int64_t(c.total);construction["list_revision"]=c.listRevision;construction["estimated"]=c.estimated;
  construction["build_phase"]=c.buildPhase;construction["build_done"]=int64_t(c.buildDone);construction["build_total"]=int64_t(c.buildTotal);
  construction["placed"]=int64_t(c.placed);construction["skipped"]=int64_t(c.skipped);construction["first_building"]=c.firstBuilding;
  PackedByteArray mask,pieces;for(auto v:c.validMask)mask.push_back(v);for(auto v:c.pieces)pieces.push_back(v);
  construction["valid_mask"]=mask;construction["pieces"]=pieces;construction["footprint"]=c.footprint ? footprint(*c.footprint) : Dictionary{};
  Array pressureCreatures;
  for(const auto& v:c.pressureCreatures){Dictionary row;row["size"]=v.size;row["race_id"]=v.raceId;row["name"]=String::utf8(v.name.c_str());pressureCreatures.push_back(row);}
  construction["pressure_creatures"]=pressureCreatures;
  if (c.connectedTrack) {
    Dictionary track;
    Array path;
    track["status"] = int(c.connectedTrack->status);
    for (const auto& p : c.connectedTrack->path)
      path.push_back(Vector3i(p.x, p.y, p.z));
    track["path"] = path;
    construction["connected_track"] = track;
  }
  Array materials;for(const auto& v:c.materials){Dictionary row;row["item_type"]=v.itemType;row["item_subtype"]=v.itemSubtype;row["mat_type"]=v.matType;row["mat_index"]=v.matIndex;row["name"]=String::utf8(v.name.c_str());row["caption"]=String::utf8(v.caption.c_str());row["count"]=int64_t(v.count);row["individual_id"]=v.individualId;row["last_name"]=String::utf8(v.lastName.c_str());
    if(v.candidates) { Array candidates;for(const auto& item:*v.candidates) { Dictionary candidate;
      candidate["id"]=item.id;candidate["name"]=String::utf8(item.name.c_str());candidate["distance"]=int64_t(item.distance);
      if(item.appearance) { const auto& a=*item.appearance;Dictionary appearance;
        appearance["material_token"]=String::utf8(a.materialToken.c_str());appearance["subtype_raw"]=String::utf8(a.subtypeRaw.c_str());
        appearance["color_token"]=String::utf8(a.colorToken.c_str());appearance["stack"]=int64_t(a.stack);appearance["flags"]=a.flags;
        candidate["appearance"]=appearance; }
      candidates.push_back(candidate); }
      row["candidates"]=candidates; }
    materials.push_back(row);}
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
    row["owner_profession"]=String::utf8(a.ownerProfession.c_str());row["owner_sex"]=a.ownerSex;
    row["location_kind"]=a.locationKind;
    row["owner_allowed"] = a.ownerAllowed;
    row["revision"]=a.revision;row["zone_label"]=String::utf8(a.zoneLabel.c_str());
    row["location_id"]=a.locationId;row["location_site_id"]=a.locationSiteId;row["location_name"]=String::utf8(a.locationName.c_str());
    row["religion"]=String::utf8(a.religion.c_str());row["organic"]=a.organic;row["inorganic"]=a.inorganic;
    row["zone_settings"]=areaZoneDictionary(a.zoneSettings);row["tile_count"]=a.tileCount;row["assigned_count"]=a.assignedCount;
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
    row["label"] = String::utf8(c.label.c_str());
    choices.push_back(row);
  }
  result["areas"] = areas;
  result["area_choices"] = choices;
  result["area_next_cursor"] = int64_t(s.nextCursor);
  result["area_truncated"] = s.truncated;
  // Preserve legacy top-level rows while the area domain carries the complete
  // operation selector and incremental-list envelope, like other new domains.
  Dictionary area;area["areas"]=areas;area["choices"]=choices;area["next_cursor"]=int64_t(s.nextCursor);area["truncated"]=s.truncated;
  area["operation"]=int(s.operation);area["area_id"]=s.areaId;area["list_key"]=String::utf8(s.listKey.c_str());
  area["candidate_kind"]=s.candidateKind;area["sort"]=s.sort;area["sort_descending"]=s.sortDescending;
  area["interaction_id"]=s.interactionId;area["undo_token"]=s.undoToken;area["room_outcome"]=int(s.roomOutcome);
  area["rooms_created"]=s.roomsCreated;area["rooms_in_use"]=s.roomsInUse;
  area["rooms_unenclosed"]=s.roomsUnenclosed;area["rooms_removed"]=s.roomsRemoved;
  area["rooms_dormitories"]=s.roomsDormitories;
  area["count_generation"]=s.countGeneration;area["painted_count"]=s.paintedCount;area["preview_count"]=s.previewCount;
  area["location_entry_outcome"]=int64_t(s.locationEntryOutcome);
  area["location_edit_outcome"]=int64_t(s.locationEditOutcome);
  if(s.locationStaffCandidates) {
    const auto& c=*s.locationStaffCandidates;Dictionary v;Array rows;
    v["site_id"]=c.siteId;v["location_id"]=c.locationId;v["occupation_id"]=c.occupationId;v["role"]=c.role;
    v["revision"]=c.revision;v["cursor"]=int64_t(c.cursor);v["next_cursor"]=int64_t(c.nextCursor);v["total"]=int64_t(c.total);
    for(const auto& r:c.rows) {
      Dictionary row;Array skills;row["unit_id"]=r.unitId;row["histfig_id"]=r.histfigId;row["name"]=String::utf8(r.name.c_str());row["score"]=r.score;
      row["base_name"]=String::utf8(r.baseName.c_str());row["profession_name"]=String::utf8(r.professionName.c_str());row["profession_color"]=r.professionColor;row["legendary"]=r.legendary;
      row["source_index"]=r.sourceIndex;row["profession_order"]=r.professionOrder;row["status_order"]=r.statusOrder;
      PackedByteArray nameKey,professionKey;
      for(auto byte:r.nameSortKey)nameKey.push_back(byte);
      for(auto byte:r.professionSortKey)professionKey.push_back(byte);
      row["name_sort_key"]=nameKey;row["profession_sort_key"]=professionKey;
      for(const auto& s:r.skills) {Dictionary skill;skill["id"]=s.id;skill["rating"]=s.rating;skill["experience"]=s.experience;skill["weight"]=s.weight;skills.push_back(skill);}
      row["skills"]=skills;rows.push_back(row);
    }
    v["rows"]=rows;area["location_staff_candidates"]=v;
  }
  if(s.locationDetails) {
    const auto& d=*s.locationDetails;Dictionary v;Array supplies,zones;
    v["site_id"]=d.siteId;v["id"]=d.id;v["kind"]=d.kind;v["name"]=String::utf8(d.name.c_str());v["revision"]=d.revision;
    v["access"]=d.access;v["visitors"]=d.visitors;v["residents"]=d.residents;v["members"]=d.members;
    v["profession"]=d.profession;v["tier"]=d.tier;v["value"]=d.value;v["desired_copies"]=d.desiredCopies;v["recognized"]=d.recognized;v["appraisal"]=d.appraisal;v["written_objects"]=d.writtenObjects;v["dance_floor_x"]=d.danceFloorX;v["dance_floor_y"]=d.danceFloorY;
    for(const auto& supply:d.supplies){Dictionary row;row["kind"]=supply.kind;row["stored"]=supply.stored;row["desired"]=supply.desired;supplies.push_back(row);}
    for(auto id:d.zoneIds)zones.push_back(id);
    if(d.affiliation){const auto& a=*d.affiliation;Dictionary affiliation;
      affiliation["kind"]=a.kind;affiliation["id"]=a.id;affiliation["name"]=String::utf8(a.name.c_str());affiliation["count"]=a.count;affiliation["workers"]=a.workers;v["affiliation"]=affiliation;}
    if(d.facilities){const auto& f=*d.facilities;Dictionary facilities;
      facilities["chests"]=f.chests;facilities["beds"]=f.beds;facilities["tables"]=f.tables;facilities["traction_benches"]=f.tractionBenches;facilities["bookcases"]=f.bookcases;facilities["chairs"]=f.chairs;facilities["rooms"]=f.rooms;facilities["rented_rooms"]=f.rentedRooms;v["facilities"]=facilities;}
    if(d.staff) {
      Dictionary staff;Array rows,missing;
      for(const auto& r:d.staff->rows) {
        Dictionary row;row["source"]=r.source;row["occupation_id"]=r.occupationId;row["role"]=r.role;
        row["histfig_id"]=r.histfigId;row["unit_id"]=r.unitId;row["location_id"]=r.locationId;row["site_id"]=r.siteId;
        row["group_id"]=r.groupId;row["entity_id"]=r.entityId;row["position_id"]=r.positionId;row["assignment_id"]=r.assignmentId;
        if(r.names) { Dictionary names;names["position_name"]=String::utf8(r.names->positionName.c_str());names["holder_name"]=String::utf8(r.names->holderName.c_str());names["holder_kind"]=r.names->holderKind;names["holder_id"]=r.names->holderId;row["names"]=names; }
        rows.push_back(row);
      }
      for(auto role:d.staff->missingRoles)missing.push_back(role);
      staff["rows"]=rows;staff["missing_roles"]=missing;v["staff"]=staff;
    }
    v["supplies"]=supplies;v["zone_ids"]=zones;area["location_details"]=v;
  }
  area["query"]=String::utf8(s.query.c_str());area["list_revision"]=s.listRevision;area["build_phase"]=s.buildPhase;
  area["build_done"]=int64_t(s.buildDone);area["build_total"]=int64_t(s.buildTotal);area["omitted"]=int64_t(s.omitted);
  area["captured_tick"]=s.capturedTick;
  Array settings,locations,candidates,links;
  for(const auto& v:s.settings) {
    Dictionary row;row["key"]=String::utf8(v.key.c_str());row["index"]=v.index;row["label"]=String::utf8(v.label.c_str());
    row["kind"]=v.kind;row["state"]=v.state;row["estimated"]=v.estimated;settings.push_back(row);
  }
  for(const auto& v:s.locations) {
    Dictionary row;row["id"]=v.id;row["name"]=String::utf8(v.name.c_str());row["location_kind"]=v.locationKind;
    row["religion"]=String::utf8(v.religion.c_str());row["guild_profession"]=v.guildProfession;row["location_tier"]=v.locationTier;row["site_id"]=v.siteId;locations.push_back(row);
  }
  for(const auto& v:s.candidates) {
    Dictionary row;row["id"]=v.id;row["name"]=String::utf8(v.name.c_str());row["profession"]=String::utf8(v.profession.c_str());
    row["sex"]=v.sex;row["mood"]=v.mood;row["grazer"]=v.grazer;row["assigned"]=v.assigned;row["squad_use"]=v.squadUse;candidates.push_back(row);
  }
  for(const auto& v:s.links) {
    Dictionary row;row["id"]=v.id;row["kind"]=int(v.kind);row["direction"]=v.direction;row["name"]=String::utf8(v.name.c_str());links.push_back(row);
  }
  area["settings"]=settings;area["locations"]=locations;area["candidates"]=candidates;area["links"]=links;
  if(s.locationCatalog) {
    const auto& c=*s.locationCatalog;Dictionary catalog;Array religions,guilds;
    catalog["kind"]=c.kind;catalog["revision"]=c.revision;catalog["cursor"]=int64_t(c.cursor);
    catalog["total"]=int64_t(c.total);catalog["next_cursor"]=int64_t(c.nextCursor);
    for(const auto& r:c.religions) {
      Dictionary row;Array deities;row["kind"]=r.kind;row["id"]=r.id;row["name"]=String::utf8(r.name.c_str());
      row["worshippers"]=r.worshippers;row["has_temple"]=r.hasTemple;
      for(const auto& d:r.deities){Dictionary deity;Array spheres;deity["id"]=d.id;deity["name"]=String::utf8(d.name.c_str());for(auto id:d.spheres)spheres.push_back(id);deity["spheres"]=spheres;deities.push_back(deity);}
      row["deities"]=deities;religions.push_back(row);
    }
    for(const auto& g:c.guilds){Dictionary row;row["profession"]=g.profession;row["workers"]=g.workers;row["has_meeting_place"]=g.hasMeetingPlace;row["guild_id"]=g.guildId;row["guild_name"]=String::utf8(g.guildName.c_str());row["members"]=g.members;guilds.push_back(row);}
    catalog["religions"]=religions;catalog["guilds"]=guilds;area["location_catalog"]=catalog;
  }
  result["area"]=area;
}

bool validateConstructionShape(const Dictionary& data, String& error) {
  if (!managementDictionaryTypes(data, {"width", "height", "depth", "direction", "cursor", "building_id", "filter", "expected_list_revision"},
                                 error) ||
      !managementRequiredFields(data, error))
    return false;
  return true;
}

bool readConstruction(const Dictionary& data, wm::ManagementRequest& r, String& error) {
  if(data.has("cancel_removal") && data["cancel_removal"].get_type()!=Variant::BOOL) {error="Invalid removal cancellation type";return false;}
  r.cancelRemoval=data.get("cancel_removal",false);
  if(r.cancelRemoval && int64_t(data.get("action",-1))!=actionValue(Action::Remove)) {error="Cancellation requires building removal intent";return false;}
  int64_t a = data.get("action", actionValue(Action::Catalog)), w = data.get("width", 1),
          h = data.get("height", 1), d = data.get("direction", 0);
  int64_t cursor = data.get("cursor", 0), building = data.get("building_id", -1);
  if (a < actionValue(Action::Catalog) || (a > actionValue(Action::RemoveConstruction) && a != actionValue(Action::ConstructionMaterials)) || w < 1 ||
      w > 31 || h < 1 || h > 31 || d < 0 || d > 7 || cursor < 0 || cursor > UINT32_MAX ||
      building < -1 || building > INT32_MAX) {
    error = "Invalid management request";
    return false;
  }
  const int64_t depth=data.get("depth",1), filter=data.get("filter",-1), rev=data.get("expected_list_revision",0);
  if(depth<1 || depth>256 || w*h*depth>1024 || filter < -1 || filter>7 || rev<0) {error="Invalid bounded construction request";return false;}
  r.depth=uint16_t(depth);r.filter=int16_t(filter);r.expectedListRevision=rev;r.retracting=data.get("retracting",false);
  if(data.has("roller_speed") && data["roller_speed"].get_type()!=Variant::INT) {error="Invalid roller speed type";return false;}
  const int64_t rollerSpeed=data.get("roller_speed",0);
  if(rollerSpeed<0 || rollerSpeed>50000 || rollerSpeed%10000) {error="Invalid roller speed";return false;}
  r.rollerSpeed=uint32_t(rollerSpeed);
  if (data.has("material_anchor")) {
    if (data["material_anchor"].get_type()!=Variant::VECTOR3I) {error="Invalid material anchor type";return false;}
    const Vector3i anchor=data["material_anchor"];
    r.materialAnchor=wm::TilePos{anchor.x,anchor.y,anchor.z};
  }
  if (data.has("connected_track_destination")) {
    if (data["connected_track_destination"].get_type() != Variant::VECTOR3I) {
      error = "Invalid connected track destination type";
      return false;
    }
    const Vector3i destination = data["connected_track_destination"];
    r.connectedTrackDestination = wm::TilePos{destination.x, destination.y, destination.z};
  }
  if(data.has("track_stop")) {
    if(data["track_stop"].get_type()!=Variant::DICTIONARY){error="Invalid track stop options";return false;}
    Dictionary t=data["track_stop"];
    if(!t.has("friction") || !t.has("dump_direction") || t["friction"].get_type()!=Variant::INT || t["dump_direction"].get_type()!=Variant::INT) {error="Invalid track stop option types";return false;}
    const int64_t friction=t["friction"],dump=t["dump_direction"];
    if(dump<0 || dump>4 || (friction!=10 && friction!=50 && friction!=500 && friction!=10000 && friction!=50000)){error="Invalid track stop options";return false;}
    r.trackStop=wm::ManagementRequest::TrackStopOptions{uint32_t(friction),uint8_t(dump)};
  }
  if(data.has("pressure_plate")) {
    if(data["pressure_plate"].get_type()!=Variant::DICTIONARY){error="Invalid pressure plate options";return false;}
    Dictionary p=data["pressure_plate"];
    for(const char* key:{"units","water","magma","citizens","resets","track"})
      if(!p.has(key) || p[key].get_type()!=Variant::BOOL){error="Invalid pressure plate flag type";return false;}
    for(const char* key:{"unit_min","unit_max","water_min","water_max","magma_min","magma_max","track_min","track_max"})
      if(!p.has(key) || p[key].get_type()!=Variant::INT){error="Invalid pressure plate range type";return false;}
    const int64_t umin=p["unit_min"],umax=p["unit_max"],wmin=p["water_min"],wmax=p["water_max"],
        mmin=p["magma_min"],mmax=p["magma_max"],tmin=p["track_min"],tmax=p["track_max"];
    const auto weight=[](int64_t v){return v==1 || (v>=50 && v<=2000 && v%50==0);};
    if(umin<1000 || umin>200000 || umin%1000 || umax<umin || umax>200999 || (umax!=200000 && umax%1000!=999) ||
       wmin<0 || wmax>7 || wmin>wmax || mmin<0 || mmax>7 || mmin>mmax || !weight(tmin) || !weight(tmax) || tmin>tmax) {
      error="Invalid pressure plate ranges";return false;
    }
    wm::ManagementRequest::PressurePlateOptions v;
    v.units=p["units"];v.water=p["water"];v.magma=p["magma"];v.citizens=p["citizens"];v.resets=p["resets"];v.track=p["track"];
    v.unitMin=int32_t(umin);v.unitMax=int32_t(umax);v.waterMin=int8_t(wmin);v.waterMax=int8_t(wmax);
    v.magmaMin=int8_t(mmin);v.magmaMax=int8_t(mmax);v.trackMin=int32_t(tmin);v.trackMax=int32_t(tmax);r.pressurePlate=v;
  }
  String key = data.get("definition", String());
  r.definition = key.utf8().get_data();
  Array selections=data.get("selections",Array());
  if(selections.size()>(r.definition=="Construction:Track" ? 16384 : 16)){error="Too many construction selections";return false;}
  size_t exactCount=0;
  for(int i=0;i<selections.size();++i) {
    if(selections[i].get_type()!=Variant::DICTIONARY){error="Invalid construction selection";return false;}
    Dictionary row=selections[i];bool valid=true;
    auto n=[&](const char* key,int64_t def,int64_t low,int64_t high){int64_t v=row.get(key,def);if(v<low || v>high)valid=false;return v;};
    wm::ConstructionSelection v;v.filter=int16_t(n("filter",-1,0,7));v.itemType=int16_t(n("item_type",-1,-1,INT16_MAX));v.itemSubtype=int16_t(n("item_subtype",-1,-1,INT16_MAX));v.matType=int16_t(n("mat_type",-1,-1,INT16_MAX));v.matIndex=int32_t(n("mat_index",-1,-1,INT32_MAX));v.count=uint32_t(n("count",1,1,UINT32_MAX));v.expectedListRevision=n("expected_list_revision",-1,-1,INT64_MAX);v.individualId=int32_t(n("individual_id",-1,-1,INT32_MAX));
    if(row.has("item_ids")) {
      if(row["item_ids"].get_type()!=Variant::ARRAY){error="Invalid exact construction items";return false;}
      Array ids=row["item_ids"];exactCount+=ids.size();
      if(exactCount>16384){error="Too many exact construction items";return false;}
      v.itemIds.emplace();v.itemIds->reserve(ids.size());
      for(int j=0;j<ids.size();++j) {
        if(ids[j].get_type()!=Variant::INT){error="Invalid exact construction item type";return false;}
        const int64_t id=ids[j];
        if(id<0 || id>INT32_MAX){error="Invalid exact construction item";return false;}
        v.itemIds->push_back(int32_t(id));
      }
    }
    if(!valid){error="Invalid construction selection";return false;}r.selections.push_back(v);
  }
  r.action = wm::ManagementAction(a);
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
                                  "links_only", "owner_id", "link_id", "cursor", "operation", "expected_revision",
                                  "expected_list_revision", "scope", "value", "preset", "paint_mode", "paint_z",
                                  "location_id", "location_kind", "profession", "deity_kind", "deity_id",
                                  "unit_id", "assign", "squad_id", "squad_use", "organic", "inorganic", "candidate_kind", "sort",
                                  "room_furniture", "interaction_id", "undo_token", "count_generation", "location_site_id", "occupation_id"},
                                 error) ||
      !managementRequiredFields(data, error))
    return false;
  const auto typed=[&](const Dictionary& row,const char* key,Variant::Type type,bool required=false) {
    if(!row.has(key)) {
      if(!required)return true;
      error=String("Missing area field: ")+key;return false;
    }
    if(row[key].get_type()==type)return true;
    error=String("Wrong area field type: ")+key;return false;
  };
  if(!typed(data,"list_key",Variant::STRING) || !typed(data,"row_key",Variant::STRING) ||
      !typed(data,"sort_descending",Variant::BOOL) || !typed(data,"spans",Variant::ARRAY) ||
      !typed(data,"zone_settings",Variant::DICTIONARY) || !typed(data,"paint_preview",Variant::DICTIONARY))return false;
  if(data.has("paint_preview")) {
    const Dictionary preview=data["paint_preview"];
    for(const char* key:{"x","y","width","height"})if(!typed(preview,key,Variant::INT,true))return false;
  }
  if(data.has("spans")) {
    const Array spans=data["spans"];
    if(spans.size()>32768){error="Too many area spans";return false;}
    for(int i=0;i<spans.size();++i) {
      if(spans[i].get_type()!=Variant::DICTIONARY){error="Area span must be a dictionary";return false;}
      const Dictionary row=spans[i];
      for(const char* key:{"y","x","length"})if(!typed(row,key,Variant::INT,true))return false;
    }
  }
  if(data.has("zone_settings")) {
    const Dictionary row=data["zone_settings"];
    for(const char* key:{"pond_mode","facing","tomb_citizens","tomb_pets","gather_trees","gather_shrubs"})
      if(!typed(row,key,Variant::INT))return false;
  }
  const auto operation=int64_t(data.get("operation",0));
  if(operation!=0 && operation!=int64_t(wm::AreaOperation::MultiCreate) && data.has("origin")) {
    error="Legacy area fields cannot be combined with an operation";return false;
  }
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
  a.kind = wm::AreaKind(n("kind", 0, 0, 2));
  a.id = int32_t(n("id", -1, -1, INT32_MAX));
  Vector3i p = data.get("origin", Vector3i());
  a.x = p.x;
  a.y = p.y;
  a.z = p.z;
  const bool multi=int64_t(data.get("operation",0))==int64_t(wm::AreaOperation::MultiCreate);
  a.width = uint16_t(n("width", 1, 1, multi?32768:31));
  a.height = uint16_t(n("height", 1, 1, multi?32768:31));
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
  a.operation=wm::AreaOperation(n("operation",0,0,int64_t(wm::AreaOperation::LocationStaffEdit)));
  a.countGeneration=n("count_generation",0,0,INT64_MAX);
  a.locationSiteId=int32_t(n("location_site_id",-1,-1,INT32_MAX));
  a.occupationId=int32_t(n("occupation_id",-1,-1,INT32_MAX));
  if(data.has("paint_preview")) {
    const Dictionary preview=data["paint_preview"];
    const int64_t x=preview["x"],y=preview["y"],width=preview["width"],height=preview["height"];
    if(x<0 || x>INT16_MAX || y<0 || y>INT16_MAX || width<1 || width>256 || height<1 || height>256 ||
        width*height>32768 || x+width>32768 || y+height>32768) {
      error="Invalid paint preview";return false;
    }
    a.paintPreview=wm::AreaPaintPreview{int16_t(x),int16_t(y),uint16_t(width),uint16_t(height)};
  }
  a.roomFurniture=uint8_t(n("room_furniture",0,0,4));
  a.interactionId=n("interaction_id",0,0,INT64_MAX);a.undoToken=n("undo_token",0,0,INT64_MAX);
  a.expectedRevision=n("expected_revision",0,0,INT64_MAX);a.expectedListRevision=n("expected_list_revision",0,0,INT64_MAX);
  const auto text=[&](const char* key,size_t limit) {
    const String value=data.get(key,String());const auto utf=value.utf8();
    if(size_t(utf.length())>limit)valid=false;
    return std::string(utf.get_data(),size_t(utf.length()));
  };
  a.query=text("query",128);a.listKey=text("list_key",64);a.rowKey=text("row_key",64);a.name=text("name",512);
  a.scope=uint8_t(n("scope",0,0,4));a.value=uint8_t(n("value",0,0,a.operation==wm::AreaOperation::LocationAccess?3:2));a.preset=uint8_t(n("preset",0,0,19));
  a.paintMode=uint8_t(n("paint_mode",0,0,3));a.paintZ=int16_t(n("paint_z",-1,-1,INT16_MAX));
  a.locationId=int32_t(n("location_id",-2,-2,INT32_MAX));a.locationKind=uint8_t(n("location_kind",0,0,5));
  a.profession=int16_t(n("profession",-1,-1,INT16_MAX));a.deityKind=int8_t(n("deity_kind",-1,-1,3));
  a.deityId=int32_t(n("deity_id",-1,-1,INT32_MAX));a.unitId=int32_t(n("unit_id",-1,-1,INT32_MAX));
  a.assign=int8_t(n("assign",-1,-1,1));a.squadId=int32_t(n("squad_id",-1,-1,INT32_MAX));
  a.squadUse=int8_t(n("squad_use",-1,-1,15));a.organic=int8_t(n("organic",-1,-1,1));a.inorganic=int8_t(n("inorganic",-1,-1,1));
  a.candidateKind=uint8_t(n("candidate_kind",0,0,3));a.sort=uint8_t(n("sort",0,0,3));a.sortDescending=data.get("sort_descending",false);
  const Array spans=data.get("spans",Array());
  if(spans.size()>32768){error="Too many area spans";return false;}
  uint32_t tiles=0;
  for(int i=0;i<spans.size();++i) {
    const Dictionary row=spans[i];const int64_t x=row["x"],y=row["y"],length=row["length"];
    if(x<0 || x>INT16_MAX || y<0 || y>INT16_MAX || length<1 || length>32768 || x+length-1>INT16_MAX) {
      error="Invalid area span";return false;
    }
    tiles+=uint32_t(length);a.spans.push_back({int16_t(y),int16_t(x),uint16_t(length)});
  }
  if(tiles>32768){error="Too many painted area tiles";return false;}
  const Dictionary zone=data.get("zone_settings",Dictionary());
  const auto zn=[&](const char* key,int64_t def,int64_t low,int64_t high){
    const int64_t v=zone.get(key,def);if(v<low || v>high)valid=false;return v;
  };
  a.zoneSettings={uint8_t(zn("pond_mode",0,0,2)),uint8_t(zn("facing",0,0,4)),
      int8_t(zn("tomb_citizens",-1,-1,1)),int8_t(zn("tomb_pets",-1,-1,1)),
      int8_t(zn("gather_trees",-1,-1,1)),int8_t(zn("gather_shrubs",-1,-1,1))};
  if (!valid) {
    error = "Invalid bounded area request";
    return false;
  }
  return true;
}
}  // namespace df3d_godot::management
