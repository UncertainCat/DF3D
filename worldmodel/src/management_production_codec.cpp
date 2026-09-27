#include "management_codecs.h"

namespace wm::detail::management {
namespace m = df3d::mirror;

ProductionState decodeProduction(const m::ProductionState* p) {
  ProductionState out;
  if (!p)
    return out;
  auto& n = out;
  auto str = [](const flatbuffers::String* v) { return v ? v->str() : std::string(); };
  auto reqs = [&](const auto* vs) {
    std::vector<ProductionRequirement> out;
    if (vs)
      for (const auto* v : *vs)
        out.push_back({str(v->description()), v->quantity(), v->item_type()});
    return out;
  };
  n.nextCursor = p->next_cursor();
  n.currentSeason = p->current_season();
  n.selectedBuilding = p->selected_building();
  n.createdJob = p->created_job();
  n.detail = str(p->detail());
  if (p->buildings())
    for (const auto* v : *p->buildings())
      n.buildings.push_back({v->id(), v->origin()->x(), v->origin()->y(), v->origin()->z(),
                             str(v->name()), str(v->kind()), v->build_stage(), v->max_stage(),
                             v->queue_size()});
  if (p->recipes())
    for (const auto* v : *p->recipes())
      n.recipes.push_back({str(v->key()), str(v->name()), reqs(v->requirements())});
  if (p->jobs())
    for (const auto* v : *p->jobs()) {
      ProductionJob j;
      j.id = v->id();
      j.workerId = v->worker_id();
      j.completionTimer = v->completion_timer();
      j.jobType = v->job_type();
      j.name = str(v->name());
      j.workerName = str(v->worker_name());
      j.status = str(v->status());
      j.repeat = v->repeat();
      j.suspended = v->suspended();
      j.editable = v->editable();
      j.attachedItems = v->attached_items();
      j.requirements = reqs(v->requirements());
      n.jobs.push_back(std::move(j));
    }
  if (p->crops())
    for (const auto* v : *p->crops())
      n.crops.push_back({v->id(), str(v->name()), v->seasons(), v->seeds()});
  if (p->seasonal_crops())
    n.seasonalCrops.assign(p->seasonal_crops()->begin(), p->seasonal_crops()->end());

  return out;
}

WorkOrderState decodeWorkOrder(const m::WorkOrderState* w) {
  WorkOrderState out;
  if (!w)
    return out;
  auto& n = out;
  auto str = [](const flatbuffers::String* s) { return s ? s->str() : std::string(); };
  n.nextCursor = w->next_cursor();
  n.detail = str(w->detail());
  n.total=w->total();n.listRevision=int64_t(w->list_revision());n.buildPhase=w->build_phase();
  n.buildDone=w->build_done();n.buildTotal=w->build_total();
  if(w->materials())for(const auto* v:*w->materials())n.materials.push_back({v->mat_type(),v->mat_index(),str(v->name())});
  if(w->traits())for(const auto* v:*w->traits())n.traits.push_back({str(v->key()),str(v->name())});
  if(w->types())for(const auto* v:*w->types())n.types.push_back({v->item_type(),v->item_subtype(),str(v->name())});
  if(w->groups())for(const auto* v:*w->groups())n.groups.push_back({v->type(),v->subtype(),v->custom(),str(v->name()),v->count()});
  if(w->tasks())for(const auto* v:*w->tasks())n.tasks.push_back({str(v->key()),str(v->name()),v->job_type(),str(v->reaction()),v->item_type(),v->item_subtype(),v->mat_type(),v->mat_index()});
  if (w->orders())
    for (const auto* v : *w->orders()) {
      WorkOrderInfo o;
      o.id = v->id();
      o.revision = v->revision();
      o.name = str(v->name());
      o.reason = str(v->reason());
      o.total = v->total();
      o.remaining = v->remaining();
      o.frequency = v->frequency();
      o.validated = v->validated();
      o.active = v->active();
      o.finishedYear = v->finished_year();
      o.finishedTick = v->finished_tick();
      o.workshopId = v->workshop_id();
      o.maxWorkshops = v->max_workshops();
      o.editable = v->editable();
      o.position=v->position();o.detailKind=v->detail_kind();o.sizeRaw=v->size_raw();o.encrustFlags=v->encrust_flags();
      o.matType=v->mat_type();o.matIndex=v->mat_index();o.materialCategory=v->material_category();
      if(v->inputs())for(const auto* i:*v->inputs())o.inputs.push_back({i->index(),str(i->description()),i->mat_type(),i->mat_index(),i->editable()});
      if (v->generated_jobs())
        o.generatedJobs.assign(v->generated_jobs()->begin(), v->generated_jobs()->end());
      if (v->conditions())
        for (const auto* c : *v->conditions()) {
          o.conditions.emplace_back();
          auto& row=o.conditions.back();row.kind=c->kind();row.index=c->index();row.description=str(c->description());
          row.editable=c->editable();row.satisfied=c->satisfied();row.compare=c->compare();row.dependency=c->dependency();
          row.itemType=c->item_type();row.threshold=c->threshold();row.targetOrder=c->target_order();row.itemSubtype=c->item_subtype();row.matType=c->mat_type();row.matIndex=c->mat_index();
          row.satisfaction=c->satisfaction();row.estimated=c->estimated();row.estimateCount=c->estimate_count();
          if(c->traits())for(const auto* t:*c->traits())row.traits.push_back(str(t));
        }
      n.orders.push_back(std::move(o));
    }
  if (w->recipes())
    for (const auto* v : *w->recipes())
      n.recipes.push_back({str(v->key()), str(v->name()), {}});
  if (w->choices())
    for (const auto* v : *w->choices())
      n.choices.push_back({v->id(), str(v->name())});
  if (w->managers())
    for (const auto* v : *w->managers()) {
      ManagerRole r;
      r.unitId = v->unit_id();
      r.name = str(v->name());
      r.position = str(v->position());
      r.job = str(v->job());
      if (v->offices())
        r.offices.assign(v->offices()->begin(), v->offices()->end());
      n.managers.push_back(std::move(r));
    }

  return out;
}

KitchenState decodeKitchen(const m::KitchenState* k) {
  KitchenState out;
  if (!k)
    return out;
  auto& n = out;
  n.open = k->open();
  n.receipt = k->receipt();
  n.nextCursor = k->next_cursor();
  n.total = k->total();
  n.detail = k->detail()->str();
  for (const auto* v : *k->ingredients()) {
    KitchenIngredient i;
    i.itemType = v->item_type();
    i.itemSubtype = v->item_subtype();
    i.matType = v->mat_type();
    i.matIndex = v->mat_index();
    i.name = v->name()->str();
    i.count = v->count();
    i.canCook = v->can_cook();
    i.canBrew = v->can_brew();
    i.cookAllowed = v->cook_allowed();
    i.brewAllowed = v->brew_allowed();
    n.ingredients.push_back(std::move(i));
  }

  return out;
}

flatbuffers::Offset<m::ProductionRequest> encodeProduction(flatbuffers::FlatBufferBuilder& b,
                                                           const ProductionRequest& value) {
  const auto& p = value;
  return m::CreateProductionRequest(b, p.buildingId, p.jobId, b.CreateString(p.recipe),
                                    b.CreateString(p.query), p.cursor, p.repeat, p.suspend,
                                    p.cancel, p.season, p.cropId);
}

flatbuffers::Offset<m::WorkOrderRequest> encodeWorkOrder(flatbuffers::FlatBufferBuilder& b,
                                                         const WorkOrderRequest& value) {
  const auto& w = value;
  return m::CreateWorkOrderRequest(b, w.id, w.expectedRevision, b.CreateString(w.recipe),
                                   b.CreateString(w.query), w.cursor, w.remaining, w.frequency,
                                   w.workshopId, w.maxWorkshops, w.conditionKind, w.conditionIndex,
                                   w.removeCondition, w.compare, w.threshold, w.itemType,
                                   w.targetOrder, w.dependency, w.candidateKind, w.move, w.expectedNeighbor,
                                   uint64_t(w.expectedListRevision), w.itemSubtype, w.matType, w.matIndex,
                                   w.traits && (!w.traits->empty() || (!w.move && w.inputIndex < 0))
                                       ? b.CreateVectorOfStrings(*w.traits) : 0,
                                   w.inputIndex, w.groupType, w.groupSubtype, w.groupCustom, w.encrustFlags);
}

flatbuffers::Offset<m::KitchenRequest> encodeKitchen(flatbuffers::FlatBufferBuilder& b,
                                                     const KitchenRequest& value) {
  const auto& k = value;
  return m::CreateKitchenRequest(b, k.itemType, k.itemSubtype, k.matType, k.matIndex, k.permission,
                                 k.allowed, k.receipt, k.cursor, b.CreateString(k.query));
}
}  // namespace wm::detail::management
