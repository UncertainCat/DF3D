#include "management_codecs.h"

namespace wm::detail::management {
namespace m = df3d::mirror;

void decodeConstruction(const m::ManagementState* s, ManagementState& next) {
  auto text=[](const flatbuffers::String* v){return v ? v->str() : std::string{};};
  auto filters=[&](const auto* values){
    std::vector<ConstructionFilter> rows;
    if(values)for(const auto* v:*values)rows.push_back({v->index(),v->item_type(),v->item_subtype(),text(v->caption()),text(v->requirement()),v->quantity()});
    return rows;
  };
  auto footprint=[](const m::ConstructionFootprint* v){return ConstructionFootprint{v->direction(),v->width(),v->height(),v->center_x(),v->center_y()};};
  if(s->catalog())for(const auto* d:*s->catalog()) {
    BuildingDefinition v;
    v.key=text(d->key());v.name=text(d->name());v.width=d->width();v.height=d->height();v.supported=d->supported();v.reason=text(d->reason());
    v.family=text(d->family());v.subtypeKey=text(d->subtype_key());v.customCode=text(d->custom_code());v.nativeName=text(d->native_name());
    v.areaMode=d->area_mode();v.orientations=d->orientations();v.maxWidth=d->max_width();v.maxHeight=d->max_height();v.maxDepth=d->max_depth();
    v.filters=filters(d->filters());if(d->footprints())for(const auto* f:*d->footprints())v.footprints.push_back(footprint(f));
    next.catalog.push_back(std::move(v));
  }
  if(const auto* c=s->construction()) {
    auto& v=next.construction;
    v.outcome=ConstructionOutcome(c->outcome());v.updated=c->updated();v.failedIndex=c->failed_index();
    v.connectedTrack.reset();
    if(const auto* track=c->connected_track()) {
      v.connectedTrack.emplace();v.connectedTrack->status=ConnectedTrackStatus(track->status());
      if(track->path())for(const auto* p:*track->path())v.connectedTrack->path.push_back({p->x(),p->y(),p->z()});
    }
    v.buildingKey=text(c->building_key());v.filter=c->filter();v.filters=filters(c->filters());
    if(c->materials())for(const auto* f:*c->materials()) {
      ConstructionMaterial row{f->item_type(),f->item_subtype(),f->mat_type(),f->mat_index(),text(f->name()),text(f->caption()),f->count()};
      row.individualId=f->individual_id();
      row.lastName=f->last_name()?f->last_name()->str():std::string{};
      if(f->candidates()) { row.candidates.emplace();for(const auto* item:*f->candidates()) {
        ConstructionMaterialCandidate candidate{item->id(),text(item->name()),item->distance()};
        if(const auto* a=item->appearance())candidate.appearance=ConstructionItemAppearance{
          text(a->material_token()),text(a->subtype_raw()),text(a->color_token()),a->stack(),a->flags()};
        row.candidates->push_back(std::move(candidate)); } }
      v.materials.push_back(std::move(row));
    }
    v.total=c->total();v.listRevision=int64_t(c->list_revision());v.estimated=c->estimated();v.buildPhase=c->build_phase();v.buildDone=c->build_done();v.buildTotal=c->build_total();
    v.placed=c->placed();v.skipped=c->skipped();v.firstBuilding=c->first_building();
    if(c->valid_mask())v.validMask.assign(c->valid_mask()->begin(),c->valid_mask()->end());
    if(c->pieces())v.pieces.assign(c->pieces()->begin(),c->pieces()->end());
    if(c->footprint())v.footprint=footprint(c->footprint());
    if(c->pressure_creatures())for(const auto* row:*c->pressure_creatures())
      v.pressureCreatures.push_back({row->size(),row->race_id(),text(row->name())});
  }
  if (s->inputs())
    for (auto* a : *s->inputs())
      next.inputs.push_back(
          {a->id(), a->description() ? a->description()->str() : "", a->quantity()});
  next.required = s->required();
  next.nextCursor = s->next_cursor();
  next.placementValid = s->placement_valid();
  next.buildingId = s->building_id();
  next.buildStage = s->build_stage();
  next.maxStage = s->max_stage();
  next.removing = s->removing();
  next.jobs = s->jobs();
  next.terrainConstruction = s->terrain_construction();
}

AreaState decodeArea(const m::AreaState* a) {
  AreaState out;
  if (!a)
    return out;
  const auto text=[](const flatbuffers::String* v){return v ? v->str() : std::string{};};
  const auto settings=[](const m::AreaZoneSettings* z) {
    return z ? AreaZoneSettings{z->pond_mode(),z->facing(),z->tomb_citizens(),z->tomb_pets(),z->gather_trees(),z->gather_shrubs()} : AreaZoneSettings{};
  };
  out.nextCursor = a->next_cursor();
  out.truncated = a->truncated();
  out.operation=AreaOperation(a->operation());out.areaId=a->area_id();out.listKey=text(a->list_key());
  out.candidateKind=a->candidate_kind();out.sort=a->sort();out.sortDescending=a->sort_descending();out.query=text(a->query());
  out.interactionId=a->interaction_id();out.undoToken=a->undo_token();out.roomOutcome=AreaRoomOutcome(a->room_outcome());
  out.roomsCreated=a->rooms_created();out.roomsInUse=a->rooms_in_use();
  out.roomsUnenclosed=a->rooms_unenclosed();out.roomsRemoved=a->rooms_removed();
  out.locationEntryOutcome=static_cast<LocationEntryOutcome>(a->location_entry_outcome());
  out.locationEditOutcome=static_cast<LocationEditOutcome>(a->location_edit_outcome());
  out.roomsDormitories=a->rooms_dormitories();
  out.countGeneration=a->count_generation();out.paintedCount=a->painted_count();out.previewCount=a->preview_count();
  if(const auto* c=a->location_staff_candidates()) {
    LocationStaffCandidates v;v.siteId=c->site_id();v.locationId=c->location_id();v.occupationId=c->occupation_id();v.role=c->role();
    v.revision=int64_t(c->revision());v.cursor=c->cursor();v.nextCursor=c->next_cursor();v.total=c->total();
    if(c->rows())for(const auto* r:*c->rows()) {
      LocationStaffCandidate row;row.unitId=r->unit_id();row.histfigId=r->histfig_id();row.name=text(r->name());row.score=r->score();
      row.baseName=text(r->base_name());row.professionName=text(r->profession_name());row.professionColor=r->profession_color();row.legendary=r->legendary();
      row.sourceIndex=r->source_index();row.professionOrder=r->profession_order();row.statusOrder=r->status_order();
      if(r->name_sort_key())row.nameSortKey.assign(r->name_sort_key()->begin(),r->name_sort_key()->end());
      if(r->profession_sort_key())row.professionSortKey.assign(r->profession_sort_key()->begin(),r->profession_sort_key()->end());
      if(r->skills())for(const auto* skill:*r->skills())row.skills.push_back({skill->id(),skill->rating(),skill->experience(),skill->weight()});
      v.rows.push_back(std::move(row));
    }
    out.locationStaffCandidates=std::move(v);
  }
  if(const auto* d=a->location_details()) {
    LocationDetails v;v.siteId=d->site_id();v.id=d->id();v.kind=d->kind();v.name=text(d->name());v.revision=int64_t(d->revision());
    v.access=d->access();v.visitors=d->visitors();v.residents=d->residents();v.members=d->members();
    v.profession=d->profession();v.tier=d->tier();v.value=d->value();v.desiredCopies=d->desired_copies();v.recognized=d->recognized();v.appraisal=d->appraisal();v.writtenObjects=d->written_objects();v.danceFloorX=d->dance_floor_x();v.danceFloorY=d->dance_floor_y();
    if(d->supplies())for(const auto* row:*d->supplies())v.supplies.push_back({row->kind(),row->stored(),row->desired()});
    if(d->zone_ids())v.zoneIds.assign(d->zone_ids()->begin(),d->zone_ids()->end());
    if(const auto* a=d->affiliation())v.affiliation=LocationAffiliation{a->kind(),a->id(),text(a->name()),a->count(),a->workers()};
    if(const auto* f=d->facilities())v.facilities=LocationFacilities{f->chests(),f->beds(),f->tables(),f->traction_benches(),f->bookcases(),f->chairs(),f->rooms(),f->rented_rooms()};
    if(const auto* staff=d->staff()) {
      v.staff.emplace();
      if(staff->rows())for(const auto* r:*staff->rows()) {
        LocationStaffRow row{r->source(),r->occupation_id(),r->role(),r->histfig_id(),r->unit_id(),r->location_id(),r->site_id(),r->group_id(),r->entity_id(),r->position_id(),r->assignment_id(),std::nullopt};
        if(const auto* n=r->names())row.names=LocationStaffNames{text(n->position_name()),text(n->holder_name()),n->holder_kind(),n->holder_id()};
        v.staff->rows.push_back(std::move(row));
      }
      if(staff->missing_roles())v.staff->missingRoles.assign(staff->missing_roles()->begin(),staff->missing_roles()->end());
    }
    out.locationDetails=std::move(v);
  }
  if(const auto* c=a->location_catalog()) {
    LocationCatalog catalog;catalog.kind=c->kind();catalog.revision=int64_t(c->revision());catalog.cursor=c->cursor();
    catalog.total=c->total();catalog.nextCursor=c->next_cursor();
    if(c->religions())for(const auto* row:*c->religions()) {
      LocationReligion r;r.kind=row->kind();r.id=row->id();r.name=text(row->name());r.worshippers=row->worshippers();r.hasTemple=row->has_temple();
      if(row->deities())for(const auto* d:*row->deities()) {
        LocationDeity deity;deity.id=d->id();deity.name=text(d->name());
        if(d->spheres())deity.spheres.assign(d->spheres()->begin(),d->spheres()->end());
        r.deities.push_back(std::move(deity));
      }
      catalog.religions.push_back(std::move(r));
    }
    if(c->guilds())for(const auto* g:*c->guilds())catalog.guilds.push_back({g->profession(),g->workers(),g->has_meeting_place(),g->guild_id(),text(g->guild_name()),g->members()});
    out.locationCatalog=std::move(catalog);
  }
  out.listRevision=int64_t(a->list_revision());out.buildPhase=a->build_phase();out.buildDone=a->build_done();
  out.buildTotal=a->build_total();out.omitted=a->omitted();out.capturedTick=a->captured_tick();
  if(a->settings())for(const auto* v:*a->settings())out.settings.push_back({text(v->key()),v->index(),text(v->label()),v->kind(),v->state(),v->estimated()});
  if(a->locations())for(const auto* v:*a->locations())out.locations.push_back({v->id(),text(v->name()),v->location_kind(),text(v->religion()),v->guild_profession(),v->location_tier(),v->site_id()});
  if(a->candidates())for(const auto* v:*a->candidates())out.candidates.push_back({v->id(),text(v->name()),text(v->profession()),v->sex(),v->mood(),v->grazer(),v->assigned(),v->squad_use()});
  if(a->links())for(const auto* v:*a->links())out.links.push_back({v->id(),AreaKind(v->kind()),v->direction(),text(v->name())});
  if (a->choices())
    for (const auto* c : *a->choices())
      out.choices.push_back({c->id(), text(c->name()),text(c->label())});
  if (a->areas())
    for (const auto* v : *a->areas()) {
      AreaInfo n;
      n.id = v->id();
      n.kind = AreaKind(v->kind());
      n.name = v->name() ? v->name()->str() : "";
      n.x = v->origin()->x();
      n.y = v->origin()->y();
      n.z = v->origin()->z();
      n.width = v->width();
      n.height = v->height();
      n.extents.assign(v->extents()->begin(), v->extents()->end());
      n.zoneType = v->zone_type();
      n.categories = v->categories();
      n.barrels = v->barrels();
      n.bins = v->bins();
      n.wheelbarrows = v->wheelbarrows();
      n.linksOnly = v->links_only();
      n.active = v->active();
      n.ownerId = v->owner_id();
      n.ownerAllowed = v->owner_allowed();
      n.ownerName = v->owner_name() ? v->owner_name()->str() : "";
      n.ownerProfession=text(v->owner_profession());n.ownerSex=v->owner_sex();n.locationKind=v->location_kind();
      n.revision=int64_t(v->revision());n.zoneLabel=text(v->zone_label());n.locationId=v->location_id();n.locationSiteId=v->location_site_id();
      n.locationName=text(v->location_name());n.religion=text(v->religion());
      n.organic=v->organic();n.inorganic=v->inorganic();n.zoneSettings=settings(v->zone_settings());
      n.tileCount=v->tile_count();n.assignedCount=v->assigned_count();
      if (v->gives())
        n.gives.assign(v->gives()->begin(), v->gives()->end());
      if (v->takes())
        n.takes.assign(v->takes()->begin(), v->takes()->end());
      out.areas.push_back(std::move(n));
    }

  return out;
}

flatbuffers::Offset<m::AreaRequest> encodeArea(flatbuffers::FlatBufferBuilder& b,
                                               const AreaRequest& value) {
  const auto& a = value;
  m::TilePos ap(a.x, a.y, a.z);
  const auto query=b.CreateString(a.query),listKey=b.CreateString(a.listKey),rowKey=b.CreateString(a.rowKey),name=b.CreateString(a.name);
  std::vector<m::AreaSpan> spans;spans.reserve(a.spans.size());
  for(const auto& s:a.spans)spans.emplace_back(s.y,s.x,s.length);
  const auto spanRows=b.CreateVectorOfStructs(spans);
  const auto& z=a.zoneSettings;
  const auto zone=m::CreateAreaZoneSettings(b,z.pondMode,z.facing,z.tombCitizens,z.tombPets,z.gatherTrees,z.gatherShrubs);
  flatbuffers::Offset<m::AreaPaintPreview> preview;
  if(a.paintPreview) {
    const auto& p=*a.paintPreview;
    preview=m::CreateAreaPaintPreview(b,p.x,p.y,p.width,p.height);
  }
  m::AreaRequestBuilder r(b);
  r.add_kind(m::AreaKind(a.kind));r.add_id(a.id);
  if(a.operation==AreaOperation::None || a.operation==AreaOperation::MultiCreate)r.add_origin(&ap);
  r.add_width(a.width);r.add_height(a.height);r.add_zone_type(a.zoneType);
  r.add_categories(a.categories);r.add_changed_categories(a.changedCategories);
  r.add_barrels(a.barrels);r.add_bins(a.bins);r.add_wheelbarrows(a.wheelbarrows);
  r.add_links_only(a.linksOnly);r.add_active(a.active);r.add_owner_id(a.ownerId);r.add_link_id(a.linkId);
  r.add_give(a.give);r.add_unlink(a.unlink);r.add_query(query);r.add_cursor(a.cursor);
  r.add_operation(m::AreaOperation(a.operation));r.add_expected_revision(uint64_t(a.expectedRevision));
  r.add_expected_list_revision(uint64_t(a.expectedListRevision));r.add_list_key(listKey);r.add_row_key(rowKey);
  r.add_scope(a.scope);r.add_value(a.value);r.add_preset(a.preset);r.add_name(name);r.add_spans(spanRows);
  r.add_paint_mode(a.paintMode);r.add_paint_z(a.paintZ);r.add_location_id(a.locationId);r.add_location_kind(a.locationKind);
  r.add_profession(a.profession);r.add_deity_kind(a.deityKind);r.add_deity_id(a.deityId);r.add_zone_settings(zone);
  r.add_unit_id(a.unitId);r.add_assign(a.assign);r.add_squad_id(a.squadId);r.add_squad_use(a.squadUse);
  r.add_organic(a.organic);r.add_inorganic(a.inorganic);r.add_candidate_kind(a.candidateKind);
  r.add_sort(a.sort);r.add_sort_descending(a.sortDescending);
  r.add_room_furniture(a.roomFurniture);r.add_interaction_id(uint64_t(a.interactionId));r.add_undo_token(uint64_t(a.undoToken));
  r.add_count_generation(uint64_t(a.countGeneration));r.add_paint_preview(preview);
  r.add_location_site_id(a.locationSiteId);r.add_occupation_id(a.occupationId);
  return r.Finish();
}
}  // namespace wm::detail::management
