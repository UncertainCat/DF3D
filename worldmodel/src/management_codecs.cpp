#include "management_codecs.h"
namespace wm::detail::management {
namespace m = df3d::mirror;

ManagementState decodeState(const m::ManagementState* s) {
  ManagementState next;
  next.revision = s->revision();
  next.worldEpoch = s->world_epoch();
  next.requestSeq = s->request_seq();
  next.action = ManagementAction(s->action());
  next.status = ManagementStatus(s->status());

  if (s->message())
    next.message = s->message()->str();
  decodeConstruction(s, next);
  next.area = decodeArea(s->area());
  next.creature = decodeCreature(s->creature());
  if(const auto* e=s->creature_expel()) {
    CreatureExpelState state;state.outcome=CreatureExpelOutcome(e->outcome());
    if(const auto* p=e->preview()) {
      state.preview.emplace();auto& out=*state.preview;
      out.unitId=p->unit_id();out.eligible=p->eligible();out.reason=p->reason();
      for(const auto* v:*p->units()) {
        CreatureExpelUnit row;row.id=v->id();row.name=v->name()->str();const auto* c=v->name_color();
        row.nameColor={{c->foreground(),c->background(),c->bright()},
          {c->alternate_foreground(),c->alternate_background(),c->alternate_bright()},c->effect()};
        const auto* icon=v->sheet_icon();
        for(const auto* t:*icon->tile_pages())row.sheetIcon.tilePages.push_back(t->str());
        for(const auto* t:*icon->palettes())row.sheetIcon.palettes.push_back(t->str());
        for(const auto* l:*icon->layers())row.sheetIcon.layers.push_back({l->page(),l->tile_x(),l->tile_y(),l->cells_x(),l->cells_y(),
          l->palette(),l->palette_row(),l->palette_key_row(),l->offset_x(),l->offset_y()});
        out.units.push_back(std::move(row));
      }
      for(const auto* v:*p->destinations())out.destinations.push_back({v->id(),v->name()->str()});
    }
    next.creatureExpel=std::move(state);
  }
  if(const auto* w=s->creature_workshop())next.creatureWorkshop=CreatureWorkshopState{w->unit_id(),w->building_id(),CreatureWorkshopOutcome(w->outcome())};
  if(const auto* w=s->creature_location())next.creatureLocation=CreatureLocationState{w->unit_id(),w->occupation_id(),CreatureLocationOutcome(w->outcome())};
  if(const auto* w=s->creature_animal())next.creatureAnimal=CreatureAnimalState{w->unit_id(),w->animal_id(),CreatureAnimalOutcome(w->outcome()),w->assigned()};
  if(const auto* k=s->creature_knowledge())next.creatureKnowledge=CreatureKnowledgeState{k->unit_id(),k->kind(),k->id(),CreatureKnowledgeOutcome(k->outcome()),k->text()->str()};
  if(const auto* p=s->creature_position())next.creaturePosition=CreaturePosition{p->unit_id(),{p->position()->x(),p->position()->y(),p->position()->z()}};
  if(const auto* h=s->creature_header()) {
    CreatureHeaderState header;header.outcome=CreatureHeaderOutcome(h->outcome());header.mutated=h->mutated();
    if(const auto* v=h->snapshot())header.snapshot=CreatureHeaderSnapshot{v->unit_id(),v->historical_figure_id(),v->has_figure(),v->revision(),v->nickname()->str(),v->profession()->str(),v->figure_nickname()->str()};
    next.creatureHeader=std::move(header);
  }
  if(const auto* r=s->residents())next.residents=ResidentsState{{r->unit_ids()->begin(),r->unit_ids()->end()}};
  if(const auto* r=s->residents_rows()) {
    next.residentsRows.emplace();
    for(const auto* v:*r->rows()) {
      ResidentRow row;
      if(const auto* t=v->job_target())row.jobTarget=ResidentJobTarget{t->job_id(),t->building_id()};
      if(const auto* t=v->activity_target())row.activityTarget=ResidentActivityTarget{t->activity_id(),t->event_id()};
      if(const auto* p=v->position())row.position=TilePos{p->x(),p->y(),p->z()};
      if(const auto* state=v->specialization())row.specialization=ResidentSpecialization{state->only_assigned(),state->revision()};
      if(const auto* entries=v->assignments()) {
        row.assignments.emplace();
        for(const auto* e:*entries)row.assignments->push_back({LocationStaffAssignmentKind(e->kind()),e->id(),e->type(),e->subtype(),e->custom(),e->name()->str(),e->custom_code()->str()});
      }
      row.id=v->id();row.happiness=v->happiness();row.combined=v->combined()->str();row.name=v->name()->str();
      row.profession=v->profession()->str();row.firstLine=v->first_line()->str();row.secondLine=v->second_line()->str();
      const auto* c=v->name_color();
      row.nameColor={{c->foreground(),c->background(),c->bright()},
                     {c->alternate_foreground(),c->alternate_background(),c->alternate_bright()},c->effect()};
      row.activity=v->activity()->str();row.activityForeground=v->activity_foreground();
      row.activityBackground=v->activity_background();row.activityBright=v->activity_bright();
      if(const auto* icon=v->sheet_icon()) {
        row.sheetIcon.emplace();
        for(const auto* t:*icon->tile_pages())row.sheetIcon->tilePages.push_back(t->str());
        for(const auto* t:*icon->palettes())row.sheetIcon->palettes.push_back(t->str());
        for(const auto* l:*icon->layers())row.sheetIcon->layers.push_back({l->page(),l->tile_x(),l->tile_y(),l->cells_x(),l->cells_y(),
          l->palette(),l->palette_row(),l->palette_key_row(),l->offset_x(),l->offset_y()});
      }
      next.residentsRows->rows.push_back(std::move(row));
    }
  }
  if(const auto* v=s->residents_specialization())
    next.residentsSpecialization=ResidentsSpecializationState{v->unit_id(),ResidentsSpecializationOutcome(v->outcome()),v->only_assigned()};
  if(const auto* v=s->job_settings_edit())next.jobSettingsEdit=JobSettingsEditState{v->job_id(),v->building_id(),v->unit_id(),JobSettingsEditOutcome(v->outcome())};
  if(const auto* v=s->job_settings()) {
    JobSettingsState value;value.jobId=v->job_id();value.buildingId=v->building_id();value.unitId=v->unit_id();value.revision=v->revision();value.caption=v->caption()->str();
    value.selectedOption=v->selected_option();value.choicesRevision=v->choices_revision();value.total=v->total();value.cursor=v->cursor();value.nextCursor=v->next_cursor();
    for(const auto* o:*v->options())value.options.push_back({o->kind(),o->index(),o->caption()->str()});
    for(const auto* c:*v->choices())value.choices.push_back({c->id(),c->caption()->str(),c->count_caption()?std::optional<std::string>(c->count_caption()->str()):std::nullopt,c->estimated()});
    if(v->current_value())value.currentValue=v->current_value()->str();
    if(v->setting_heading())value.settingHeading=v->setting_heading()->str();
    if(v->art())value.art=decodeArtState(*v->art());
    next.jobSettings=std::move(value);
  }
  if(const auto* v=s->residents_activity()) {
    ResidentsActivityState value;value.unitId=v->unit_id();value.activityId=v->activity_id();value.eventId=v->event_id();value.columns=v->columns();value.maxY=v->max_y();
    for(const auto* w:*v->words())value.words.push_back({w->text()->str(),w->red(),w->green(),w->blue(),w->link(),w->flags(),w->x(),w->y()});
    for(const auto* l:*v->links())value.links.push_back({l->type(),l->id(),l->subid()});
    next.residentsActivity=std::move(value);
  }
  next.citizen = decodeCitizen(s->citizen());
  next.appointments = decodeAppointments(s->appointments());
  next.production = decodeProduction(s->production());
  next.workOrder = decodeWorkOrder(s->work_order());
  next.kitchen = decodeKitchen(s->kitchen());
  next.stocks = decodeStocks(s->stocks());
  next.trade = decodeTrade(s->trade());
  next.agreement = decodeAgreement(s->agreement());
  next.selection = decodeSelection(s->selection());
  next.alert = decodeAlert(s->alert());
  next.report = decodeReport(s->report());
  if (const auto* t=s->world_hover()) {
    WorldHover hover;hover.x=t->tile()->x();hover.y=t->tile()->y();hover.z=t->tile()->z();
    for(const auto* e:*t->entries()) hover.entries.push_back({e->text()->str(),e->foreground(),e->background(),e->bright(),e->kind(),e->object_id()});
    next.worldHover=std::move(hover);
  }
  return next;
}

void encodeRequest(flatbuffers::FlatBufferBuilder& b, const ManagementRequest& r, uint64_t clientId,
                   uint64_t sequence, uint64_t worldEpoch) {
  m::TilePos p(r.x, r.y, r.z);
  flatbuffers::Offset<m::AreaRequest> area;
  if (r.action >= ManagementAction::AreaCatalog && r.action <= ManagementAction::AreaCandidates) {
    area = encodeArea(b, r.area);
  }
  flatbuffers::Offset<m::ProductionRequest> production;
  if (r.action >= ManagementAction::ProductionList && r.action <= ManagementAction::FarmEdit) {
    production = encodeProduction(b, r.production);
  }
  flatbuffers::Offset<m::WorkOrderRequest> workOrder;
  if (r.action >= ManagementAction::WorkOrderList &&
      r.action <= ManagementAction::WorkOrderCatalog) {
    workOrder = encodeWorkOrder(b, r.workOrder);
  }
  flatbuffers::Offset<m::CitizenRequest> citizen;
  if ((r.action >= ManagementAction::CitizenList && r.action <= ManagementAction::WorkDetailMode) ||
      (r.action >= ManagementAction::WorkDetailCreate && r.action <= ManagementAction::CitizenWorkScope)) {
    citizen = encodeCitizen(b, r.citizen);
  }
  flatbuffers::Offset<m::SelectionRequest> selection;
  if (r.action == ManagementAction::Selection) {
    selection = encodeSelection(b, r.selection);
  }
  flatbuffers::Offset<m::AlertRequest> alert;
  if (r.action == ManagementAction::Alert) {
    alert = encodeAlert(b, r.alert);
  }
  flatbuffers::Offset<m::KitchenRequest> kitchen;
  if (r.action >= ManagementAction::KitchenOpen && r.action <= ManagementAction::KitchenClose) {
    kitchen = encodeKitchen(b, r.kitchen);
  }
  flatbuffers::Offset<m::AppointmentsRequest> appointments;
  if (r.action >= ManagementAction::AppointmentsOpen &&
      r.action <= ManagementAction::AppointmentsBack) {
    appointments = encodeAppointments(b, r.appointments);
  }
  flatbuffers::Offset<m::StocksRequest> stocks;
  if (r.action >= ManagementAction::StocksOpen && r.action <= ManagementAction::StocksClose) {
    stocks = encodeStocks(b, r.stocks);
  }
  flatbuffers::Offset<m::TradeRequest> trade;
  if (r.action >= ManagementAction::TradeList && r.action <= ManagementAction::TradeExchangeClose) {
    trade = encodeTrade(b, r.trade);
  }
  flatbuffers::Offset<m::AgreementRequest> agreement;
  if (r.action >= ManagementAction::AgreementList &&
      r.action <= ManagementAction::AgreementInspect) {
    agreement = encodeAgreement(b, r.agreement);
  }
  flatbuffers::Offset<m::ReportRequest> report;
  if ((r.action >= ManagementAction::ReportList && r.action <= ManagementAction::ReportInspect) || r.action==ManagementAction::PrepareAlertDismissal || r.action==ManagementAction::DismissAlert) {
    report = encodeReport(b, r.report);
  }
  std::vector<flatbuffers::Offset<m::ConstructionSelection>> selections;
  for(const auto& v:r.selections) {
    const auto ids=v.itemIds ? b.CreateVector(*v.itemIds) : flatbuffers::Offset<flatbuffers::Vector<int32_t>>{};
    selections.push_back(m::CreateConstructionSelection(b,v.filter,v.itemType,v.itemSubtype,v.matType,v.matIndex,v.count,v.expectedListRevision,ids,v.individualId));
  }
  flatbuffers::Offset<m::ConnectedTrackOptions> connectedTrack;
  if (r.connectedTrackDestination) {
    const auto& end=*r.connectedTrackDestination;
    const m::TilePos destination(end.x,end.y,end.z);
    connectedTrack=m::CreateConnectedTrackOptions(b,&destination);
  }
  const auto anchor=r.materialAnchor.value_or(TilePos{r.x,r.y,r.z});
  const m::TilePos materialAnchor(anchor.x,anchor.y,anchor.z);
  auto request = m::CreateConstructionRequest(
      b, m::kManagementVersion, clientId, sequence, worldEpoch, m::ManagementAction(r.action),
      b.CreateString(r.definition), &p, r.width, r.height, r.direction, b.CreateVector(r.items),
      r.cursor, r.buildingId, area, production, workOrder, citizen, report, agreement, trade,
      stocks, appointments, kitchen, alert, selection,
      (r.action == ManagementAction::CreatureInspect || r.action == ManagementAction::CreatureLocate || r.action == ManagementAction::CreatureSheetLocate) ? m::CreateCreatureRequest(b, r.creatureUnitId)
                                                    : flatbuffers::Offset<m::CreatureRequest>{},
      r.depth,r.retracting,r.filter,b.CreateVector(selections),uint64_t(r.expectedListRevision),r.rollerSpeed,
      r.trackStop?m::CreateTrackStopOptions(b,r.trackStop->friction,r.trackStop->dumpDirection):flatbuffers::Offset<m::TrackStopOptions>{},
      r.pressurePlate?m::CreatePressurePlateOptions(b,r.pressurePlate->units,r.pressurePlate->water,r.pressurePlate->magma,
          r.pressurePlate->citizens,r.pressurePlate->resets,r.pressurePlate->track,r.pressurePlate->unitMin,r.pressurePlate->unitMax,
          r.pressurePlate->waterMin,r.pressurePlate->waterMax,r.pressurePlate->magmaMin,r.pressurePlate->magmaMax,
          r.pressurePlate->trackMin,r.pressurePlate->trackMax):flatbuffers::Offset<m::PressurePlateOptions>{},connectedTrack,r.materialAnchor ? &materialAnchor : nullptr,r.cancelRemoval,
      (r.action==ManagementAction::CreatureHeaderRead || r.action==ManagementAction::CreatureHeaderEdit)?
          m::CreateCreatureHeaderRequest(b,r.creatureHeader.unitId,r.creatureHeader.profession,r.creatureHeader.expectedRevision,b.CreateString(r.creatureHeader.name)):
          flatbuffers::Offset<m::CreatureHeaderRequest>{},
      (r.action==ManagementAction::CreatureExpelRead || r.action==ManagementAction::CreatureExpelApply)?
          m::CreateCreatureExpelRequest(b,r.creatureExpel.unitId,r.creatureExpel.destinationId,b.CreateVector(r.creatureExpel.expectedUnitIds)):
          flatbuffers::Offset<m::CreatureExpelRequest>{},
      r.action==ManagementAction::CreatureKnowledgeRead?
          m::CreateCreatureKnowledgeRequest(b,r.creatureKnowledge.unitId,r.creatureKnowledge.kind,r.creatureKnowledge.id):
          flatbuffers::Offset<m::CreatureKnowledgeRequest>{},
      r.action==ManagementAction::CreatureWorkshopRemove?
          m::CreateCreatureWorkshopRequest(b,r.creatureWorkshop.unitId,r.creatureWorkshop.buildingId,r.creatureWorkshop.expectedRevision):
          flatbuffers::Offset<m::CreatureWorkshopRequest>{},
      r.action==ManagementAction::CreatureLocationRemove?
          m::CreateCreatureLocationRequest(b,r.creatureLocation.unitId,r.creatureLocation.occupationId,r.creatureLocation.expectedRevision):
          flatbuffers::Offset<m::CreatureLocationRequest>{},
      r.action==ManagementAction::CreatureAnimalEdit?
          m::CreateCreatureAnimalRequest(b,r.creatureAnimal.unitId,r.creatureAnimal.animalId,r.creatureAnimal.expectedRevision,r.creatureAnimal.assigned):
          flatbuffers::Offset<m::CreatureAnimalRequest>{},
      r.action==ManagementAction::ResidentsQuery?
          m::CreateResidentsRequest(b,m::ResidentsSort(r.residents.sort),r.residents.descending,b.CreateVector(r.residents.queryBytes)):
          flatbuffers::Offset<m::ResidentsRequest>{},
      r.action==ManagementAction::ResidentsRowsRead?
          m::CreateResidentsRowsRequest(b,b.CreateVector(r.residentsRows.unitIds),r.residentsRows.columns,r.residentsRows.showGender):
          flatbuffers::Offset<m::ResidentsRowsRequest>{},
      r.action==ManagementAction::ResidentsSpecialize?
          m::CreateResidentsSpecializationRequest(b,r.residentsSpecialization.unitId,r.residentsSpecialization.expectedRevision,r.residentsSpecialization.onlyAssigned):
          flatbuffers::Offset<m::ResidentsSpecializationRequest>{},
      r.action==ManagementAction::ResidentsActivityRead?
          m::CreateResidentsActivityRequest(b,r.residentsActivity.unitId,r.residentsActivity.activityId,r.residentsActivity.eventId,r.residentsActivity.columns):
          flatbuffers::Offset<m::ResidentsActivityRequest>{},
      r.action==ManagementAction::JobSettingsRead?
          m::CreateJobSettingsRequest(b,r.jobSettings.jobId,r.jobSettings.buildingId,r.jobSettings.unitId,r.jobSettings.option,b.CreateString(r.jobSettings.query),r.jobSettings.cursor,r.jobSettings.artPage,r.jobSettings.expectedListRevision,r.jobSettings.hovered,r.jobSettings.previewColumns):
          flatbuffers::Offset<m::JobSettingsRequest>{},
      r.action==ManagementAction::JobSettingsApply?
          m::CreateJobSettingsEditRequest(b,r.jobSettingsEdit.jobId,r.jobSettingsEdit.buildingId,r.jobSettingsEdit.unitId,r.jobSettingsEdit.option,r.jobSettingsEdit.expectedRevision,r.jobSettingsEdit.expectedChoicesRevision,r.jobSettingsEdit.choice,r.jobSettingsEdit.artPage,b.CreateString(r.jobSettingsEdit.query)):
          flatbuffers::Offset<m::JobSettingsEditRequest>{});
  b.Finish(request);
}
}  // namespace wm::detail::management
