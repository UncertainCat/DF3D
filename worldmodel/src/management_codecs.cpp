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
  if(const auto* r=s->nobles()) {
    auto& out=next.nobles.emplace();out.outcome=NoblesOutcome(r->outcome());out.listRevision=r->list_revision();out.total=r->total();out.offset=r->offset();
    for(const auto* row:*r->rows()){
      NoblesRow v;v.entityId=row->entity_id();v.positionId=row->position_id();v.assignmentId=row->assignment_id();
      v.unitId=row->unit_id();v.nemesisId=row->nemesis_id();v.priority=row->priority();
      v.title=row->title()->str();v.squadCaption=row->squad_caption()->str();v.holderCaption=row->holder_caption()->str();
      v.canAppoint=row->can_appoint();v.hasRoomAssessment=row->has_room_assessment();v.demandStatus=row->demand_status();v.mandateStatus=row->mandate_status();
      for(size_t i=0;i<4;++i){v.requiredRooms[i]=row->required_rooms()->Get(i);v.actualRooms[i]=row->actual_rooms()->Get(i);
        v.requiredFurniture[i]=row->required_furniture()->Get(i);v.actualFurniture[i]=row->actual_furniture()->Get(i);}
      out.rows.push_back(std::move(v));
    }
  }
  if(const auto* r=s->places()) {
    auto& out=next.places.emplace();out.outcome=PlacesOutcome(r->outcome());out.tab=r->tab();
    out.listRevision=r->list_revision();out.total=r->total();out.offset=r->offset();
    out.buildingId=r->building_id();out.siegeAction=r->siege_action();
    for(const auto* row:*r->rows()) {
      PlacesRow v;v.buildingId=row->building_id();v.subtitleLocationId=row->subtitle_location_id();
      if(const auto* p=row->position())v.position=TilePos{p->x(),p->y(),p->z()};
      v.name=row->name()->str();v.subtitle=row->subtitle()->str();v.jobCaption=row->job_caption()->str();
      v.statusCaption=row->status_caption()->str();v.secondaryStatus=row->secondary_status()->str();
      v.statusOverlay=row->status_overlay()->str();v.operatorCaption=row->operator_caption()->str();
      v.additionalJobs=row->additional_jobs();v.siegeAction=row->siege_action();
      if(row->appearance())v.appearance=decodeItemRecipe(row->appearance());
      out.rows.push_back(std::move(v));
    }
  }
  if(const auto* r=s->tasks()) {
    auto& out=next.tasks.emplace();out.outcome=TasksOutcome(r->outcome());out.listRevision=r->list_revision();
    out.total=r->total();out.offset=r->offset();out.jobId=r->job_id();
    for(const auto* row:*r->rows()) {
      TasksRow v;v.jobId=row->job_id();v.workerId=row->worker_id();v.buildingId=row->building_id();v.revision=row->revision();
      v.caption=row->caption()->str();v.workerName=row->worker_name()->str();v.buildingCaption=row->building_caption()->str();
      if(const auto* p=row->worker_position())v.workerPosition=TilePos{p->x(),p->y(),p->z()};
      if(const auto* p=row->building_position())v.buildingPosition=TilePos{p->x(),p->y(),p->z()};
      if(const auto* c=row->worker_color())v.workerColor=AreaNameColor{{c->foreground(),c->background(),c->bright()},
        {c->alternate_foreground(),c->alternate_background(),c->alternate_bright()},c->effect()};
      v.canViewJob=row->can_view_job();v.canRepeat=row->can_repeat();v.canRemoveWorker=row->can_remove_worker();
      v.canSuspend=row->can_suspend();v.canCancel=row->can_cancel();v.repeating=row->repeating();v.suspended=row->suspended();
      if(row->worker_appearance())v.workerAppearance=decodeItemRecipe(row->worker_appearance());
      if(row->building_appearance())v.buildingAppearance=decodeItemRecipe(row->building_appearance());
      out.rows.push_back(std::move(v));
    }
  }
  if(const auto* r=s->stocks_menu()) {
    next.stocksMenu.emplace();auto& out=*next.stocksMenu;out.outcome=StocksMenuOutcome(r->outcome());out.category=r->category();
    for(const auto* row:*r->categories())out.categories.push_back({row->type(),row->caption()->str(),row->stored()->str(),row->unavailable()->str(),row->matches()});
    for(const auto* row:*r->groups()){const auto* k=row->key();StocksGroupRow group;group.key={k->type(),k->subtype(),k->subcat1(),k->subcat2()};group.amount=row->amount();group.caption=row->caption()->str();group.matches=row->matches();group.expanded=row->expanded();group.flags=row->flags();group.revision=row->revision();group.itemIds.assign(row->item_ids()->begin(),row->item_ids()->end());out.groups.push_back(std::move(group));}
    for(const auto* row:*r->items()){
      StocksItemRow item{row->id(),row->type(),row->caption()->str(),row->flags(),row->can_dump(),row->can_melt(),row->material_token()->str(),row->subtype_raw()->str()};
      if(const auto* a=row->appearance())item.appearance=decodeInspectionAppearance(a);
      out.items.push_back(std::move(item));
    }
  }
  if(const auto* r=s->stone_use()) {
    next.stoneUse.emplace();auto& out=*next.stoneUse;out.outcome=StoneUseOutcome(r->outcome());
    for(const auto* row:*r->rows())out.rows.push_back({row->category(),row->index(),row->restricted(),row->name()->str(),row->uses()->str(),row->magma_safe(),row->material_token()->str()});
    out.restrictions.assign(r->restrictions()->begin(),r->restrictions()->end());
  }
  if(const auto* r=s->kitchen_menu()) {
    next.kitchenMenu.emplace();auto& out=*next.kitchenMenu;out.outcome=KitchenMenuOutcome(r->outcome());
    const auto key=[](const m::KitchenFoodKey* k){return KitchenFoodKey{k->item_type(),k->item_subtype(),k->mat_type(),k->mat_index()};};
    for(const auto* row:*r->rows()){const auto* v=row->receipt();out.rows.push_back({{key(v->key()),v->count(),v->capabilities()},row->name()->str(),row->count_caption()->str(),row->estimated(),row->excluded(),row->material_token()->str()});}
    for(const auto* row:*r->exclusions())out.exclusions.push_back({key(row->key()),row->flags()});
  }
  if(const auto* r=s->chores()) {
    next.chores.emplace();auto& out=*next.chores;out.outcome=ChoresOutcome(r->outcome());
    if(const auto* v=r->snapshot()) {out.snapshot.emplace();auto& snap=*out.snapshot;
      snap.enabled=v->enabled();snap.children.assign(v->children()->begin(),v->children()->end());snap.exempted.assign(v->exempted()->begin(),v->exempted()->end());
      for(const auto* row:*v->labors())snap.labors.push_back({row->id(),row->enabled()});}
    for(const auto* row:*r->children())out.children.push_back({row->id(),row->caption()->str()});
    for(const auto* row:*r->labors())out.labors.push_back({row->id(),row->caption()->str()});
  }
  if(const auto* r=s->hunter_ammunition()) {
    next.hunterAmmunition.emplace();auto& out=*next.hunterAmmunition;
    out.outcome=HunterAmmunitionOutcome(r->outcome());out.itemType=r->item_type();out.itemSubtype=r->item_subtype();
    for(const auto* v:*r->specs())out.specs.push_back({v->item_type(),v->item_subtype(),v->material_class(),v->mattype(),v->matindex(),v->amount(),v->flags(),{v->assigned()->begin(),v->assigned()->end()}});
    for(const auto* v:*r->rules()){
      HunterAmmunitionRule row{v->caption()->str(),v->quantity(),{}};
      for(const auto* item:*v->items()){
        const auto* a=item->appearance();
        row.items.push_back({item->id(),item->caption()->str(),item->quantity(),{a->material_token()->str(),a->subtype_raw()->str(),a->color_token()->str(),a->stack(),a->flags()}});
      }
      out.rules.push_back(std::move(row));
    }
    for(const auto* v:*r->types())out.types.push_back({v->item_type(),v->item_subtype(),v->foreign(),v->caption()->str()});
    for(const auto* v:*r->materials())out.materials.push_back({v->material_class(),v->mattype(),v->matindex(),v->caption()->str()});
  }
  if(const auto* r=s->standing_orders()) {
    next.standingOrders.emplace();auto& out=*next.standingOrders;
    out.category=r->category();out.outcome=StandingOrdersOutcome(r->outcome());
    for(const auto* row:*r->settings())out.settings.push_back({row->id(),row->value(),row->visible(),row->editable()});
  }
  if(const auto* r=s->work_detail_settings()) {
    next.workDetailSettings.emplace();auto& out=*next.workDetailSettings;
    out.detailIndex=r->detail_index();out.revision=r->revision();out.editable=r->editable();out.noModify=r->no_modify();
    out.labors.assign(r->labors()->begin(),r->labors()->end());
    for(const auto* entry:*r->catalog())out.catalog.push_back({entry->id(),entry->caption()->str()});
  }
  if(const auto* r=s->residents_rows()) {
    next.residentsRows.emplace();
    for(const auto* v:*r->rows()) {
      ResidentRow row;row.detailMember=v->detail_member();
      if(const auto* skills=v->work_detail_skills()) {
        row.workDetailSkills.emplace();
        for(const auto* skill:*skills)row.workDetailSkills->push_back({skill->skill(),skill->rating(),skill->caption()->str()});
      }
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
  flatbuffers::Offset<m::NoblesRequest> nobles;
  if(r.action==ManagementAction::NoblesRead)nobles=m::CreateNoblesRequest(b,r.nobles.offset,r.nobles.limit,r.nobles.expectedListRevision);
  flatbuffers::Offset<m::PlacesRequest> places;
  if(r.action==ManagementAction::PlacesRead || r.action==ManagementAction::PlacesApply){const auto& q=r.places;
    places=m::CreatePlacesRequest(b,q.tab,q.offset,q.limit,q.expectedListRevision,q.buildingId,q.siegeAction);}
  flatbuffers::Offset<m::TasksRequest> tasks;
  if(r.action==ManagementAction::TasksRead || r.action==ManagementAction::TasksApply){
    const auto& q=r.tasks;
    tasks=m::CreateTasksRequest(b,q.offset,q.limit,q.expectedListRevision,q.jobId,q.workerId,q.buildingId,
      q.expectedRevision,m::TasksOperation(q.operation),q.expectedState);
  }
  flatbuffers::Offset<m::StocksMenuRequest> stocksMenu;
  if(r.action==ManagementAction::StocksMenuRead || r.action==ManagementAction::StocksGroupApply || r.action==ManagementAction::StocksItemApply){
    const auto& q=r.stocksMenu;flatbuffers::Offset<m::StocksGroupKey> target;
    if(q.target){const auto& k=*q.target;target=m::CreateStocksGroupKey(b,k.type,k.subtype,k.subcat1,k.subcat2);}
    stocksMenu=m::CreateStocksMenuRequest(b,q.category,b.CreateString(q.query),b.CreateVector(q.itemIds),target,q.expectedRevision,m::StocksFlagAction(q.operation),q.value,q.itemId,q.pageRequest,q.pageOffset);
  }
  flatbuffers::Offset<m::StoneUseRequest> stoneUse;
  if(r.action==ManagementAction::StoneUseRead || r.action==ManagementAction::StoneUseApply){
    const auto& q=r.stoneUse;flatbuffers::Offset<flatbuffers::Vector<uint8_t>> expected;
    if(q.expected)expected=b.CreateVector(*q.expected);
    stoneUse=m::CreateStoneUseRequest(b,q.category,q.index,expected);
  }
  flatbuffers::Offset<m::KitchenMenuRequest> kitchenMenu;
  if(r.action==ManagementAction::KitchenRead || r.action==ManagementAction::KitchenApply){
    const auto& q=r.kitchenMenu;
    const auto key=[&](const KitchenFoodKey& k){return m::CreateKitchenFoodKey(b,k.itemType,k.itemSubtype,k.matType,k.matIndex);};
    flatbuffers::Offset<m::KitchenMenuQuery> query;flatbuffers::Offset<m::KitchenFoodReceipt> target;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<m::KitchenExclusion>>> expected;
    if(q.query){const auto& v=*q.query;std::vector<flatbuffers::Offset<m::KitchenSort>> sorts;
      for(const auto& s:v.sorts)sorts.push_back(m::CreateKitchenSort(b,m::KitchenSortColumn(s.column),s.reverse));
      query=m::CreateKitchenMenuQuery(b,v.typeFilter,v.capabilityFilter,b.CreateString(v.query),b.CreateVector(sorts));}
    if(q.target){const auto& v=*q.target;target=m::CreateKitchenFoodReceipt(b,key(v.key),v.count,v.capabilities);}
    if(q.expected){std::vector<flatbuffers::Offset<m::KitchenExclusion>> rows;for(const auto& v:*q.expected)rows.push_back(m::CreateKitchenExclusion(b,key(v.key),v.flags));expected=b.CreateVector(rows);}
    kitchenMenu=m::CreateKitchenMenuRequest(b,query,target,q.permission,expected);
  }
  flatbuffers::Offset<m::ChoresRequest> chores;
  if(r.action==ManagementAction::ChoresRead || r.action==ManagementAction::ChoresApply){
    const auto& q=r.chores;flatbuffers::Offset<m::ChoresSnapshot> expected;
    if(q.expected){const auto& v=*q.expected;std::vector<flatbuffers::Offset<m::ChoreLabor>> labors;
      for(const auto& row:v.labors)labors.push_back(m::CreateChoreLabor(b,row.id,row.enabled));
      expected=m::CreateChoresSnapshot(b,v.enabled,b.CreateVector(v.children),b.CreateVector(v.exempted),b.CreateVector(labors));}
    chores=m::CreateChoresRequest(b,m::ChoresOperation(q.operation),q.id,q.value,expected);
  }
  flatbuffers::Offset<m::WorkDetailWorkersRequest> detailWorkers;
  if(r.action==ManagementAction::WorkDetailWorkersQuery) {
    const auto& q=r.workDetailWorkers;std::vector<flatbuffers::Offset<m::WorkDetailSort>> sorts;
    for(const auto& sort:q.sorts)sorts.push_back(m::CreateWorkDetailSort(b,m::WorkDetailWorkerSort(sort.column),sort.descending));
    detailWorkers=m::CreateWorkDetailWorkersRequest(b,q.detailIndex,q.expectedRevision,b.CreateVector(sorts),b.CreateVector(q.queryBytes));
  }
  flatbuffers::Offset<m::HunterAmmunitionRequest> hunter;
  if(r.action>=ManagementAction::HunterAmmunitionRead && r.action<=ManagementAction::HunterAmmunitionApply){
    const auto& q=r.hunterAmmunition;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<m::HunterAmmunitionSpec>>> expected;
    if(r.action==ManagementAction::HunterAmmunitionApply){
      std::vector<flatbuffers::Offset<m::HunterAmmunitionSpec>> specs;
      for(const auto& v:q.expected)specs.push_back(m::CreateHunterAmmunitionSpec(b,v.itemType,v.itemSubtype,v.materialClass,v.matType,v.matIndex,v.amount,v.flags,b.CreateVector(v.assigned)));
      expected=b.CreateVector(specs);
    }
    hunter=m::CreateHunterAmmunitionRequest(b,m::HunterAmmunitionOperation(q.operation),q.index,q.itemId,q.amount,q.itemType,q.itemSubtype,q.materialClass,q.matType,q.matIndex,expected);
  }
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
      (r.action==ManagementAction::ResidentsRowsRead || r.action==ManagementAction::WorkDetailRowsRead)?
          m::CreateResidentsRowsRequest(b,b.CreateVector(r.residentsRows.unitIds),r.residentsRows.columns,r.residentsRows.showGender,r.residentsRows.detailIndex,r.residentsRows.expectedRevision):
          flatbuffers::Offset<m::ResidentsRowsRequest>{},
      r.action==ManagementAction::ResidentsSpecialize?
          m::CreateResidentsSpecializationRequest(b,r.residentsSpecialization.unitId,r.residentsSpecialization.expectedRevision,r.residentsSpecialization.onlyAssigned):
          flatbuffers::Offset<m::ResidentsSpecializationRequest>{},
      r.action==ManagementAction::ResidentsActivityRead?
          m::CreateResidentsActivityRequest(b,r.residentsActivity.unitId,r.residentsActivity.activityId,r.residentsActivity.eventId,r.residentsActivity.columns):
          flatbuffers::Offset<m::ResidentsActivityRequest>{},
      r.action==ManagementAction::JobSettingsRead?
          m::CreateJobSettingsRequest(b,r.jobSettings.jobId,r.jobSettings.buildingId,r.jobSettings.unitId,r.jobSettings.option,b.CreateString(r.jobSettings.query),r.jobSettings.cursor,r.jobSettings.artPage,r.jobSettings.expectedListRevision,r.jobSettings.hovered,r.jobSettings.previewColumns,r.jobSettings.expectedRevision,r.jobSettings.art?encodeArtRequest(b,*r.jobSettings.art):0):
          flatbuffers::Offset<m::JobSettingsRequest>{},
      r.action==ManagementAction::JobSettingsApply?
          m::CreateJobSettingsEditRequest(b,r.jobSettingsEdit.jobId,r.jobSettingsEdit.buildingId,r.jobSettingsEdit.unitId,r.jobSettingsEdit.option,r.jobSettingsEdit.expectedRevision,r.jobSettingsEdit.expectedChoicesRevision,r.jobSettingsEdit.choice,r.jobSettingsEdit.artPage,b.CreateString(r.jobSettingsEdit.query),r.jobSettingsEdit.art?encodeArtRequest(b,*r.jobSettingsEdit.art):0):
          flatbuffers::Offset<m::JobSettingsEditRequest>{},
      detailWorkers,
      (r.action==ManagementAction::WorkDetailSettingsRead || r.action==ManagementAction::WorkDetailSettingsToggle)?
          m::CreateWorkDetailSettingsRequest(b,r.workDetailSettings.detailIndex,r.workDetailSettings.expectedRevision,r.workDetailSettings.settingId):
          flatbuffers::Offset<m::WorkDetailSettingsRequest>{},
      (r.action==ManagementAction::StandingOrdersRead || r.action==ManagementAction::StandingOrdersSet)?
          m::CreateStandingOrdersRequest(b,r.standingOrders.category,r.standingOrders.settingId,r.standingOrders.expectedValue,r.standingOrders.value):
          flatbuffers::Offset<m::StandingOrdersRequest>{},hunter,chores,kitchenMenu,stoneUse,stocksMenu,tasks,places,nobles);
  b.Finish(request);
}
}  // namespace wm::detail::management
