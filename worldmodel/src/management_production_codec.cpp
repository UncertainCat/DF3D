#include "management_codecs.h"

namespace wm::detail::management {
namespace m = df3d::mirror;

static flatbuffers::Offset<m::WorkOrderArtDraftElement> encodeArtElement(flatbuffers::FlatBufferBuilder& b,const WorkOrderArtDraftElement& e) {
  return m::CreateWorkOrderArtDraftElement(b,e.kind,e.id,e.secondary,e.quantity);
}
static flatbuffers::Offset<m::WorkOrderArtDraftRelationship> encodeArtRelationship(flatbuffers::FlatBufferBuilder& b,const WorkOrderArtDraftRelationship& r) {
  return m::CreateWorkOrderArtDraftRelationship(b,r.verb,r.transitive,r.actor,r.target);
}
static flatbuffers::Offset<m::WorkOrderArtDraftValue> encodeArtDraft(flatbuffers::FlatBufferBuilder& b,const WorkOrderArtDraftValue& v) {
  std::vector<flatbuffers::Offset<m::WorkOrderArtDraftElement>> elements;
  for(const auto& e:v.elements)elements.push_back(encodeArtElement(b,e));
  std::vector<flatbuffers::Offset<m::WorkOrderArtDraftRelationship>> relationships;
  for(const auto& r:v.relationships)relationships.push_back(encodeArtRelationship(b,r));
  flatbuffers::Offset<m::LocationNameValue> name;
  if(v.name){const auto& n=*v.name;name=m::CreateLocationNameValue(b,b.CreateVector(n.firstNameBytes),b.CreateVector(n.nicknameBytes),b.CreateVector(n.words),b.CreateVector(n.parts),n.language,n.type,n.hasName);}
  return m::CreateWorkOrderArtDraftValue(b,b.CreateVector(elements),b.CreateVector(relationships),name);
}
static WorkOrderArtDraftValue decodeArtDraft(const m::WorkOrderArtDraftValue& v) {
  WorkOrderArtDraftValue result;
  for(const auto* e:*v.elements())result.elements.push_back({e->kind(),e->id(),e->secondary(),e->quantity()});
  for(const auto* r:*v.relationships())result.relationships.push_back({r->verb(),r->transitive(),r->actor(),r->target()});
  if(const auto* n=v.name()) {
    result.name.emplace();auto& name=*result.name;
    name.firstNameBytes.assign(n->first_name_bytes()->begin(),n->first_name_bytes()->end());
    name.nicknameBytes.assign(n->nickname_bytes()->begin(),n->nickname_bytes()->end());
    name.words.assign(n->words()->begin(),n->words()->end());name.parts.assign(n->parts()->begin(),n->parts()->end());
    name.language=n->language();name.type=n->type();name.hasName=n->has_name();
  }
  return result;
}

ProductionState decodeProduction(const m::ProductionState* p) {
  ProductionState out;
  if (!p)
    return out;
  auto& n = out;
  auto str = [](const flatbuffers::String* v) { return v ? v->str() : std::string(); };
  const auto decodeAppearance=[&](const m::ItemInspectionAppearance* a)->std::optional<ItemInspectionAppearance> {
    if(!a)return std::nullopt;return decodeInspectionAppearance(a);
  };
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
  if(const auto* c=p->workshop_orders()) {
    auto& v=n.workshopOrders.emplace();v.buildingId=c->building_id();v.revision=c->revision();
    v.managerAvailable=c->manager_available();v.generalOrderLimit=c->general_order_limit();
    v.outcome=static_cast<FarmEditOutcome>(c->outcome());v.delta=c->delta();v.value=c->value();
    if(c->order_ids())v.orderIds.assign(c->order_ids()->begin(),c->order_ids()->end());
  }
  if(const auto* c=p->workshop_workers()) {
    auto& v=n.workshopWorkers.emplace();v.operation=static_cast<FarmOperation>(c->operation());
    if(const auto* a=c->assigned())v.assigned=WorkshopAssignedWorker{a->id(),str(a->caption()),a->specialization_visible(),a->can_specialize(),a->specialized()};
    v.buildingId=c->building_id();v.profileRevision=c->profile_revision();
    v.revision=c->revision();v.cursor=c->cursor();v.nextCursor=c->next_cursor();v.total=c->total();
    v.outcome=static_cast<FarmEditOutcome>(c->outcome());v.unitId=c->unit_id();
    if(c->permitted_workers())v.permittedWorkers.assign(c->permitted_workers()->begin(),c->permitted_workers()->end());
    if(c->rows())for(const auto* r:*c->rows()) {
      LocationStaffCandidate row;row.unitId=r->unit_id();row.histfigId=r->histfig_id();row.name=str(r->name());row.score=r->score();
      row.baseName=str(r->base_name());row.professionName=str(r->profession_name());row.professionColor=r->profession_color();row.legendary=r->legendary();
      row.sourceIndex=r->source_index();row.professionOrder=r->profession_order();row.statusOrder=r->status_order();
      if(r->name_sort_key())row.nameSortKey.assign(r->name_sort_key()->begin(),r->name_sort_key()->end());
      if(r->profession_sort_key())row.professionSortKey.assign(r->profession_sort_key()->begin(),r->profession_sort_key()->end());
      if(r->skills())for(const auto* skill:*r->skills())row.skills.push_back({skill->id(),skill->rating(),skill->experience(),skill->weight()});
      if(r->assignments())for(const auto* e:*r->assignments())row.assignments.push_back({static_cast<LocationStaffAssignmentKind>(e->kind()),e->id(),e->type(),e->subtype(),e->custom(),str(e->name()),str(e->custom_code())});
      v.rows.push_back(std::move(row));
    }
  }
  if(const auto* s=p->lever()) {
    auto& v=n.lever.emplace();v.buildingId=s->building_id();v.revision=s->revision();v.operation=s->operation();v.outcome=s->outcome();
    v.sourceMechanism=s->source_mechanism();v.targetMechanism=s->target_mechanism();v.targetId=s->target_id();v.jobId=s->job_id();
    v.sourceName=s->source_name()->str();v.targetName=s->target_name()->str();
  }
  if(const auto* page=p->building_links()) {
    auto& v=n.buildingLinks.emplace();v.buildingId=page->building_id();v.revision=page->revision();v.tabs=page->tabs();
    v.cursor=page->cursor();v.nextCursor=page->next_cursor();v.total=page->total();
    for(const auto* row:*page->rows()) {
      BuildingLinkRow value;value.itemId=row->item_id();value.referenceType=row->reference_type();value.id=row->id();value.type=row->type();value.name=str(row->name());
      value.x=row->position()->x();value.y=row->position()->y();value.z=row->position()->z();
      if(row->appearance())value.appearance=decodeItemRecipe(row->appearance());
      v.rows.push_back(std::move(value));
    }
  }
  if(const auto* source=p->pending_building()) {
    auto& state=n.pendingBuilding.emplace();state.outcome=static_cast<FarmEditOutcome>(source->outcome());state.removed=source->removed();state.removing=source->removing();
    if(const auto* f=source->snapshot())state.snapshot=PendingBuildingSnapshot{f->id(),f->type(),f->revision(),f->stage(),f->max_stage(),f->job_id(),f->suspended(),f->has_worker(),f->header_name()->str(),f->removing(),f->forbidden(),f->appearance()?std::optional<SelectionAppearance>(decodeItemRecipe(f->appearance())):std::nullopt,f->progress(),f->trigger_kind(),f->trigger_links()};
  }
  if(const auto* source=p->door_controls()) {
    auto& state=n.doorControls.emplace();state.outcome=static_cast<FarmEditOutcome>(source->outcome());
    if(const auto* f=source->snapshot())state.snapshot=DoorControlsSnapshot{f->id(),f->revision(),f->forbidden(),f->closed(),f->taken_by_invaders(),f->used_by_intruder(),f->operated_by_mechanisms()};
  }
  if(const auto* source=p->building_header()) {
    auto& state=n.buildingHeader.emplace();state.outcome=static_cast<FarmEditOutcome>(source->outcome());
    state.missingBuildingId=source->missing_building_id();
    state.operation=static_cast<FarmOperation>(source->operation());
    if(const auto* f=source->snapshot())state.snapshot=BuildingHeaderSnapshot{f->id(),f->type(),f->stage(),f->max_stage(),f->revision(),
      str(f->custom_name()),str(f->native_name()),str(f->header_name()),f->removing(),f->suspended(),f->has_worker(),f->forbidden(),f->appearance()?std::optional<SelectionAppearance>(decodeItemRecipe(f->appearance())):std::nullopt};
    if(source->snapshot() && source->snapshot()->funerary()) {
      const auto* f=source->snapshot()->funerary();auto& v=state.snapshot->funerary.emplace();
      v.unitId=f->unit_id();v.historicalFigureId=f->historical_figure_id();v.roomId=f->room_id();v.roomType=f->room_type();
      v.introduction=str(f->introduction());v.name=str(f->name());v.roomIntroduction=str(f->room_introduction());
      v.roomName=str(f->room_name());v.deceased=str(f->deceased());
      if(f->notices())for(const auto* text:*f->notices())v.notices.push_back(str(text));
      if(f->owner_appearance())v.ownerAppearance=decodeItemRecipe(f->owner_appearance());
    }
  }
  if(const auto* source=p->independent_item()) {
    auto& state=n.independentItem.emplace();state.outcome=static_cast<FarmEditOutcome>(source->outcome());
    if(const auto* edit=source->edit())state.edit=BuildingItemReceipt{edit->item_id(),static_cast<FarmOperation>(edit->operation()),edit->value()};
    if(const auto* item=source->snapshot()) {
      auto& value=state.snapshot.emplace();
      if(const auto* a=item->ammunition_assignment())value.ammunitionAssignment=ItemAmmunitionAssignment{a->kind(),a->squad_id(),a->caption()->str()};
      if(const auto* rows=item->uses()){value.uses.emplace();for(const auto* row:*rows)value.uses->push_back({str(row->caption()),row->reaction()});}
      if(const auto* rows=item->contents()){value.contents.emplace();for(const auto* row:*rows){
        ItemSheetContent copy;copy.kind=row->kind();copy.id=row->id();copy.caption=str(row->caption());copy.itemType=row->item_type();copy.flags=row->flags();copy.canDump=row->can_dump();copy.canMelt=row->can_melt();
        if(row->appearance())copy.appearance=decodeInspectionAppearance(row->appearance());
        value.contents->push_back(std::move(copy));
      }}
      value.id=item->id();value.revision=item->revision();value.itemType=item->item_type();value.stockpileCategories=item->stockpile_categories();
      value.name=str(item->name());value.materialToken=str(item->material_token());value.subtypeRaw=str(item->subtype_raw());
      if(const auto* owner=item->owner())value.owner=ItemOwner{owner->id(),str(owner->name())};
      value.weight=str(item->weight());value.description=str(item->description());
      value.forbid=item->forbid();value.dump=item->dump();value.melt=item->melt();value.hidden=item->hidden();
      value.canDump=item->can_dump();value.canMelt=item->can_melt();value.inJob=item->in_job();value.inBuilding=item->in_building();
      if(const auto* a=item->appearance())value.appearance=decodeInspectionAppearance(a);
      if(const auto* link=item->holder())value.holder=ItemBuildingHolder{link->id(),link->type(),str(link->name()),link->appearance()?std::optional<SelectionAppearance>(decodeItemRecipe(link->appearance())):std::nullopt};
      if(const auto* link=item->stockpile())value.stockpile=ItemBuildingHolder{link->id(),link->type(),str(link->name()),link->appearance()?std::optional<SelectionAppearance>(decodeItemRecipe(link->appearance())):std::nullopt};
      if(const auto* c=item->carrier()){value.carrier=ItemCarrier{c->kind(),c->id(),c->item_type(),str(c->name())};
        if(const auto* a=c->appearance())value.carrier->appearance=decodeInspectionAppearance(a);}
    }
  }
  if(const auto* value=p->item_position())n.itemPosition=ItemPosition{value->id(),value->position()->x(),value->position()->y(),value->position()->z()};
  if(const auto* edit=p->contents_edit())n.contentsEdit=BuildingItemReceipt{edit->item_id(),static_cast<FarmOperation>(edit->operation()),edit->value()};
  if(const auto* page=p->contents()) {
    auto& value=n.contents.emplace();value.buildingId=page->building_id();value.revision=page->revision();
    value.cursor=page->cursor();value.nextCursor=page->next_cursor();value.total=page->total();
    value.completed=page->completed();value.removing=page->removing();
    if(page->rows())for(const auto* row:*page->rows())value.rows.push_back({row->id(),row->role(),str(row->name()),
      row->forbid(),row->dump(),row->melt(),row->hidden(),row->can_dump(),row->can_melt(),row->in_job(),row->in_building(),row->item_type(),str(row->material_token()),str(row->subtype_raw()),decodeAppearance(row->appearance())});
  }
  if(const auto* source=p->item()) {
    auto& value=n.item.emplace();value.buildingId=source->building_id();value.revision=source->revision();
    value.completed=source->completed();value.removing=source->removing();
    value.weight=str(source->weight());value.description=str(source->description());
    const auto* row=source->item();value.item={row->id(),row->role(),str(row->name()),
      row->forbid(),row->dump(),row->melt(),row->hidden(),row->can_dump(),row->can_melt(),row->in_job(),row->in_building(),row->item_type(),str(row->material_token()),str(row->subtype_raw()),decodeAppearance(row->appearance())};
    if(const auto* holder=source->holder())value.holder=ItemBuildingHolder{holder->id(),holder->type(),str(holder->name()),holder->appearance()?std::optional<SelectionAppearance>(decodeItemRecipe(holder->appearance())):std::nullopt};
  }
  n.farmEditOutcome=static_cast<FarmEditOutcome>(p->farm_edit_outcome());
  if(const auto* f=p->farm()) {
    auto& farm=n.farm.emplace();farm.buildingId=f->building_id();farm.revision=f->revision();
    farm.selectedSeason=f->selected_season();farm.currentSeason=f->current_season();
    farm.customName=str(f->custom_name());farm.headerName=str(f->header_name());
    farm.removing=f->removing();farm.removalSuspended=f->removal_suspended();farm.removalHasWorker=f->removal_has_worker();
    farm.currentFertilization=f->current_fertilization();farm.maxFertilization=f->max_fertilization();
    farm.pendingFertilization=f->pending_fertilization();farm.seasonalFertilization=f->seasonal_fertilization();
    if(f->seasonal_crops())farm.seasonalCrops.assign(f->seasonal_crops()->begin(),f->seasonal_crops()->end());
    if(f->choices())for(const auto* c:*f->choices())
      farm.choices.push_back({c->id(),str(c->name()),c->seeds_available(),c->current_season_warning(),str(c->raw_id())});
  }
  if (p->buildings())
    for (const auto* v : *p->buildings())
      n.buildings.push_back({v->id(), v->origin()->x(), v->origin()->y(), v->origin()->z(),
                             str(v->name()), str(v->kind()), v->build_stage(), v->max_stage(),
                             v->queue_size()});
  if(p->task_category())n.taskCategory=p->task_category()->str();
  if(p->task_parent())n.taskParent=p->task_parent()->str();
  const auto dyeStatus=[&](const auto* d){return ProductionDyeStatus{str(d->text()),d->color_id(),d->red(),d->green(),d->blue()};};
  if(p->task_categories())for(const auto* v:*p->task_categories()) {
    ProductionTaskCategory row{str(v->key()),str(v->name())};
    if(const auto* d=v->dye())row.dye=dyeStatus(d);
    n.taskCategories.push_back(std::move(row));
  }
  if (p->recipes())
    for (const auto* v : *p->recipes()) {
      ProductionRecipe row{str(v->key()), str(v->name()), reqs(v->requirements())};
      if(const auto* a=v->availability())row.availability=ProductionAvailability{a->available(),str(a->objection())};
      if(const auto* m=v->memorial())row.memorial=ProductionMemorialStatus{str(m->text()),m->priority()};
      if(const auto* d=v->dye())row.dye=dyeStatus(d);
      n.recipes.push_back(std::move(row));
    }
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
      j.priority = v->priority();
      j.canMoveUp = v->can_move_up();
      j.active = v->active();
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

WorkOrderArtState decodeArtState(const m::WorkOrderArtState& source) {
  const auto* a=&source;WorkOrderArtState art;
  const auto str=[](const flatbuffers::String* s){return s?s->str():std::string{};};
  art.page=a->page();art.caption=str(a->caption());art.listRevision=a->list_revision();art.total=a->total();art.nextCursor=a->next_cursor();
  art.hovered=a->hovered();
  if(a->preview()){art.preview.emplace();for(const auto* line:*a->preview())art.preview->push_back(str(line));}
  if(a->rows())for(const auto* row:*a->rows())art.rows.push_back({row->id(),str(row->caption()),row->badge()?std::optional<std::string>(str(row->badge())):std::nullopt,row->secondary()});
  if(a->draft())art.draft=decodeArtDraft(*a->draft());
  if(a->draft_description()){art.draftDescription.emplace();for(const auto* line:*a->draft_description())art.draftDescription->push_back(str(line));}
  if(const auto* n=a->name()) {
    art.name.emplace();auto& v=*art.name;v.nativeHeader=str(n->native_header());v.englishHeader=str(n->english_header());
    v.component=n->component();v.queryBytes.assign(n->query_bytes()->begin(),n->query_bytes()->end());
    v.cursor=n->cursor();v.total=n->total();v.nextCursor=n->next_cursor();
    for(const auto* row:*n->choices())v.choices.push_back({row->word(),row->part(),str(row->english()),str(row->translated())});
  }
  return art;
}

WorkOrderState decodeWorkOrder(const m::WorkOrderState* w) {
  WorkOrderState out;
  if (!w)
    return out;
  auto& n = out;
  auto str = [](const flatbuffers::String* s) { return s ? s->str() : std::string(); };
  if(const auto* native=w->native_state())n.nativeState=WorkOrderListNativeState{native->manager_available(),native->validation_required()};
  if(const auto* d=w->details()) {
    n.details.emplace();auto& details=*n.details;
    details.id=d->id();details.revision=d->revision();details.caption=str(d->caption());details.selectedOption=d->selected_option();
    details.choicesRevision=d->choices_revision();details.total=d->total();details.nextCursor=d->next_cursor();
    if(d->current_value())details.currentValue=str(d->current_value());
    if(d->setting_heading())details.settingHeading=str(d->setting_heading());
    details.dyeTarget=d->dye_target();
    if(d->art())details.art=decodeArtState(*d->art());
    if(d->options())for(const auto* option:*d->options())details.options.push_back({option->kind(),option->index(),str(option->caption())});
    if(d->choices()) {
      details.choices.emplace();for(const auto* choice:*d->choices()) {
        WorkOrderDetailsChoice row{choice->id(),str(choice->caption()),choice->count_caption()?std::optional<std::string>(str(choice->count_caption())):std::nullopt,choice->estimated(),choice->dye_color(),choice->opens_menu()};
        if(const auto* color=choice->swatch())row.swatch=WorkOrderDyeColor{color->red(),color->green(),color->blue()};
        details.choices->push_back(std::move(row));
      }
    }
  }
  n.nextCursor = w->next_cursor();
  n.detail = str(w->detail());
  n.total=w->total();n.listRevision=int64_t(w->list_revision());n.buildPhase=w->build_phase();
  n.buildDone=w->build_done();n.buildTotal=w->build_total();
  if(w->materials())for(const auto* v:*w->materials())n.materials.push_back({v->mat_type(),v->mat_index(),str(v->name())});
  if(w->traits())for(const auto* v:*w->traits())n.traits.push_back({str(v->key()),str(v->name())});
  if(w->types())for(const auto* v:*w->types())n.types.push_back({v->item_type(),v->item_subtype(),str(v->name())});
  if(w->groups())for(const auto* v:*w->groups())n.groups.push_back({v->type(),v->subtype(),v->custom(),str(v->name()),v->count(),v->custom_code()?std::optional<std::string>(str(v->custom_code())):std::nullopt});
  if(w->tasks())for(const auto* v:*w->tasks())n.tasks.push_back({str(v->key()),str(v->name()),v->job_type(),str(v->reaction()),v->item_type(),v->item_subtype(),v->mat_type(),v->mat_index()});
  if (w->orders())
    for (const auto* v : *w->orders()) {
      WorkOrderInfo o;
      if(const auto* n=v->native_state())o.nativeState=WorkOrderNativeState{static_cast<WorkOrderPhase>(n->phase()),n->validation_required(),n->details_available(),n->workshop_name()?std::optional<std::string>(str(n->workshop_name())):std::nullopt};
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
      const auto decodeConditions=[&](const auto* values,auto& destination) {
        if(!values)return;
        for (const auto* c : *values) {
          destination.emplace_back();
          auto& row=destination.back();row.kind=c->kind();row.index=c->index();row.description=str(c->description());
          row.editable=c->editable();row.satisfied=c->satisfied();row.compare=c->compare();row.dependency=c->dependency();
          row.itemType=c->item_type();row.threshold=c->threshold();row.targetOrder=c->target_order();row.itemSubtype=c->item_subtype();row.matType=c->mat_type();row.matIndex=c->mat_index();
          row.satisfaction=c->satisfaction();row.estimated=c->estimated();row.estimateCount=c->estimate_count();
          if(c->item_caption())row.itemCaption=str(c->item_caption());
          if(c->traits())for(const auto* t:*c->traits())row.traits.push_back(str(t));
        }
      };
      decodeConditions(v->conditions(),o.conditions);
      if(v->suggested_conditions()){o.suggestedConditions.emplace();decodeConditions(v->suggested_conditions(),*o.suggestedConditions);}
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
  flatbuffers::Offset<m::LeverRequest> lever;
  if(p.lever) {
    const auto& v=*p.lever;const m::TilePos pos(v.position?(*v.position)[0]:0,v.position?(*v.position)[1]:0,v.position?(*v.position)[2]:0);
    lever=m::CreateLeverRequest(b,v.operation,v.position?&pos:nullptr,v.targetId,v.sourceMechanism,v.targetMechanism);
  }
  return m::CreateProductionRequest(b, p.buildingId, p.jobId, b.CreateString(p.recipe),
                                    b.CreateString(p.query), p.cursor, p.repeat, p.suspend,
                                    p.cancel, p.season, p.cropId, p.expectedRevision,static_cast<m::FarmOperation>(p.farmOperation),p.seasonalFertilization,
                                    p.farmOperation==wm::FarmOperation::Rename || !p.farmName.empty()?b.CreateString(p.farmName):0,p.contents,p.itemId,p.itemValue,p.locateItem,p.independentItem,p.buildingHeader,p.workshopWorkers,p.workerId,p.workerListRevision,p.workerValue,p.workshopOrders,p.generalOrderDelta,p.generalOrderValue,p.contentsItemId,p.priority,p.expectedPriority,b.CreateString(p.taskCategory),p.expectedPreviousJobId,p.doorControls,p.doorForbidden,p.pendingBuilding,p.pendingOperation,p.buildingLinks,lever);
}

flatbuffers::Offset<m::WorkOrderArtRequest> encodeArtRequest(flatbuffers::FlatBufferBuilder& b,const WorkOrderArtRequest& a) {
flatbuffers::Offset<m::WorkOrderArtDraftRequest> draft;
  if(a.draft){
    const auto& v=*a.draft;
    const auto element=v.element?encodeArtElement(b,*v.element):flatbuffers::Offset<m::WorkOrderArtDraftElement>{};
    const auto relationship=v.relationship?encodeArtRelationship(b,*v.relationship):flatbuffers::Offset<m::WorkOrderArtDraftRelationship>{};
    flatbuffers::Offset<m::LocationNameQuery> nameQuery;flatbuffers::Offset<m::LocationNameEdit> nameEdit;
    if(v.nameQuery){const auto& n=*v.nameQuery;nameQuery=m::CreateLocationNameQuery(b,n.component,b.CreateVector(n.queryBytes),n.cursor);}
    if(v.nameEdit){const auto& n=*v.nameEdit;nameEdit=m::CreateLocationNameEdit(b,m::LocationNameMode(n.mode),n.target,n.displayed,n.word,n.part,b.CreateVector(n.queryBytes));}
    draft=m::CreateWorkOrderArtDraftRequest(b,encodeArtDraft(b,v.value),m::WorkOrderArtDraftAction(v.action),element,relationship,v.deleteIndex,v.columns,nameQuery,nameEdit);
  }
  return m::CreateWorkOrderArtRequest(b,a.page,a.subject,a.expectedListRevision,b.CreateString(a.query),a.cursor,a.hovered,a.previewColumns,draft);
}

flatbuffers::Offset<m::WorkOrderRequest> encodeWorkOrder(flatbuffers::FlatBufferBuilder& b,
                                                         const WorkOrderRequest& value) {
  const auto& w = value;
  flatbuffers::Offset<m::WorkOrderDetailsRequest> details;
  if(w.details){const auto& d=*w.details;
    flatbuffers::Offset<m::WorkOrderArtRequest> art;
    if(d.art)art=encodeArtRequest(b,*d.art);
    details=m::CreateWorkOrderDetailsRequest(b,d.option,d.choice,d.expectedChoicesRevision,b.CreateString(d.query),d.cursor,art,d.dyeTarget,d.dyeFilterApplied);
  }
  return m::CreateWorkOrderRequest(b, w.id, w.expectedRevision, b.CreateString(w.recipe),
                                   b.CreateString(w.query), w.cursor, w.remaining, w.frequency,
                                   w.workshopId, w.maxWorkshops, w.conditionKind, w.conditionIndex,
                                   w.removeCondition, w.compare, w.threshold, w.itemType,
                                   w.targetOrder, w.dependency, w.candidateKind, w.move, w.expectedNeighbor,
                                   uint64_t(w.expectedListRevision), w.itemSubtype, w.matType, w.matIndex,
                                   w.traits && (!w.traits->empty() || (!w.move && w.inputIndex < 0))
                                       ? b.CreateVectorOfStrings(*w.traits) : 0,
                                   w.inputIndex, w.groupType, w.groupSubtype, w.groupCustom, w.encrustFlags, w.suggestionIndex, w.filterChoice,details);
}

flatbuffers::Offset<m::KitchenRequest> encodeKitchen(flatbuffers::FlatBufferBuilder& b,
                                                     const KitchenRequest& value) {
  const auto& k = value;
  return m::CreateKitchenRequest(b, k.itemType, k.itemSubtype, k.matType, k.matIndex, k.permission,
                                 k.allowed, k.receipt, k.cursor, b.CreateString(k.query));
}
}  // namespace wm::detail::management
