#include "management_codecs.h"

namespace wm::detail::management {
namespace m = df3d::mirror;

void decodeConstruction(const m::ManagementState* s, ManagementState& next) {
  if (s->catalog())
    for (auto* d : *s->catalog())
      next.catalog.push_back({d->key()->str(), d->name() ? d->name()->str() : "", d->width(),
                              d->height(), d->supported(), d->reason() ? d->reason()->str() : ""});
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
