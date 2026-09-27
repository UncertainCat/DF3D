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
    v.buildingKey=text(c->building_key());v.filter=c->filter();v.filters=filters(c->filters());
    if(c->materials())for(const auto* f:*c->materials())v.materials.push_back({f->item_type(),f->item_subtype(),f->mat_type(),f->mat_index(),text(f->name()),text(f->caption()),f->count()});
    v.total=c->total();v.listRevision=int64_t(c->list_revision());v.estimated=c->estimated();v.buildPhase=c->build_phase();v.buildDone=c->build_done();v.buildTotal=c->build_total();
    v.placed=c->placed();v.skipped=c->skipped();v.firstBuilding=c->first_building();
    if(c->valid_mask())v.validMask.assign(c->valid_mask()->begin(),c->valid_mask()->end());
    if(c->pieces())v.pieces.assign(c->pieces()->begin(),c->pieces()->end());
    if(c->footprint())v.footprint=footprint(c->footprint());
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
  out.nextCursor = a->next_cursor();
  out.truncated = a->truncated();
  if (a->choices())
    for (const auto* c : *a->choices())
      out.choices.push_back({c->id(), c->name()->str()});
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
  return m::CreateAreaRequest(b, m::AreaKind(a.kind), a.id, &ap, a.width, a.height, a.zoneType,
                              a.categories, a.changedCategories, a.barrels, a.bins, a.wheelbarrows,
                              a.linksOnly, a.active, a.ownerId, a.linkId, a.give, a.unlink,
                              b.CreateString(a.query), a.cursor);
}
}  // namespace wm::detail::management
