#pragma once
#include <tuple>
#include "session_util.h"
namespace df3d::mirror {
inline constexpr uint32_t kManagementVersion = 17;
inline constexpr const char* kManagementRegionName = "Local\\df3d_management_v17";
inline constexpr uint32_t kManagementCapacity = 512 * 1024;
inline constexpr uint32_t kManagementCommandCapacity = 4096;
// Catalog discovers the current epoch, so it does not require a matching
// request epoch. It still requires a loaded world outside a save operation.
inline bool managementRequestAdmitted(ManagementAction action, uint64_t requested,
                                      uint64_t current, bool saving) {
  return current != 0 && !saving &&
      (action == ManagementAction::Catalog || requestEpochMatches(requested,current));
}
// Retired wire values remain valid protocol vocabulary for explicit rejection.
// This runtime policy must not be folded into structural buffer validation.
inline constexpr bool runtimeManagementAction(ManagementAction action) {
  return action >= ManagementAction::Catalog && action <= ManagementAction::CreatureInspect &&
      action != ManagementAction::Alert && action != ManagementAction::Selection &&
      !(action >= ManagementAction::TradeExchangeOpen && action <= ManagementAction::TradeExchangeClose) &&
      !(action >= ManagementAction::StocksOpen && action <= ManagementAction::StocksClose) &&
      !(action >= ManagementAction::AppointmentsOpen && action <= ManagementAction::AppointmentsBack) &&
      !(action >= ManagementAction::KitchenOpen && action <= ManagementAction::KitchenClose);
}
inline std::optional<std::string> validateConstructionRequest(const ConstructionRequest& r) {
  if (r.schema_version() != kManagementVersion) return "management version mismatch";
  if (!r.client_id() || !r.seq()) return "client and sequence required";
  if (r.action() < ManagementAction::Catalog || r.action() > ManagementAction::CreatureInspect)
    return "invalid management action";
  if (r.action() != ManagementAction::Catalog && !r.world_epoch()) return "world epoch required";
  if(r.action()==ManagementAction::CreatureInspect) {
    if(!r.creature() || r.creature()->unit_id()<0) return "creature identity required";
  } else if(r.creature()) return "unexpected creature payload";
  if(r.action()==ManagementAction::Selection) {
    const auto* a=r.selection();
    if(!a || a->operation()>SelectionOperation::Back || a->index() < -1 || a->index()>255) return "invalid selection request";
    if(a->operation()==SelectionOperation::OpenTile) {if(!a->tile() || a->tile()->x()<0 || a->tile()->y()<0 || a->tile()->z()<0) return "invalid selection tile";}
    else if(!a->receipt()) return "selection receipt required";
    if((a->operation()==SelectionOperation::SelectAlternative || a->operation()==SelectionOperation::InspectItem) && a->index()<0) return "selection index required";
  } else if(r.selection()) return "unexpected selection payload";
  if(r.action()==ManagementAction::Alert) {
    const auto* a=r.alert();
    if(!a || a->operation()>AlertOperation::Scroll || a->category() < -1 || a->category()>36 ||
       a->entry() < -1 || a->entry()>511 || a->tab() < -1 || a->tab()>63 || a->delta() < -32 || a->delta()>32)
      return "invalid alert request";
    if((a->operation()==AlertOperation::OpenCategory || a->operation()==AlertOperation::Dismiss) && a->category()<0) return "alert category required";
    if(a->operation()!=AlertOperation::OpenCategory && a->operation()!=AlertOperation::OpenHistory && a->operation()!=AlertOperation::Dismiss && !a->receipt()) return "alert receipt required";
    if((a->operation()==AlertOperation::OpenUnit || a->operation()==AlertOperation::Recenter) && a->entry()<0) return "alert entry required";
    if(a->operation()==AlertOperation::SelectTab && a->tab()<0) return "alert tab required";
  } else if(r.alert()) return "unexpected alert request";

  if (r.action() >= ManagementAction::AreaCatalog && r.action() <= ManagementAction::AreaCandidates) {
    const auto* a = r.area();
    if (!a || a->kind() > AreaKind::Zone || !a->origin()) return "invalid area request";
    if (a->origin()->x()<0 || a->origin()->y()<0 || a->origin()->z()<0 ||
        a->width()<1 || a->height()<1 || a->width()>31 || a->height()>31) return "invalid area rectangle";
    if ((a->categories() | a->changed_categories()) & ~0x1ffffu) return "invalid stockpile categories";
    if (a->barrels() < -1 || a->bins() < -1 || a->wheelbarrows() < -1 ||
        a->links_only() < -1 || a->links_only()>1 || a->active() < -1 || a->active()>1 ||
        a->owner_id() < -2 || a->zone_type() < -1 || a->zone_type()>255 ||
        a->id() < -1 || a->link_id() < -1 || (a->query() && a->query()->size()>128)) return "invalid area edit";
    if ((r.action()==ManagementAction::AreaInspect || r.action()==ManagementAction::AreaUpdate ||
         r.action()==ManagementAction::AreaDelete || r.action()==ManagementAction::AreaLink) && a->id()<0)
      return "area id required";
    if (r.action()==ManagementAction::AreaLink && (a->link_id()<0 || a->id()==a->link_id())) return "invalid area link";
  } else if (r.area()) return "unexpected area payload";
  if (r.action() >= ManagementAction::ProductionList && r.action() <= ManagementAction::FarmSetCrop) {
    const auto* p=r.production();
    if (!p || p->building_id() < -1 || p->job_id() < -1 || p->crop_id() < -1 || p->crop_id()>32767 ||
        p->repeat() < -1 || p->repeat()>1 || p->suspend() < -1 || p->suspend()>1 ||
        p->season() < -1 || p->season()>3 || (p->query() && p->query()->size()>128) ||
        (p->recipe() && p->recipe()->size()>128)) return "invalid production request";
    if (r.action()!=ManagementAction::ProductionList && p->building_id()<0) return "production building required";
    if (r.action()==ManagementAction::ProductionQueue && (!p->recipe() || !p->recipe()->size())) return "recipe required";
    if (r.action()==ManagementAction::ProductionJobEdit && (p->job_id()<0 ||
        (p->cancel() && (p->repeat()!=-1 || p->suspend()!=-1)) ||
        (!p->cancel() && p->repeat()==-1 && p->suspend()==-1))) return "invalid job edit";
    if (r.action()==ManagementAction::FarmSetCrop && p->season()<0) return "season required";
  } else if(r.production()) return "unexpected production payload";
  if(r.action()>=ManagementAction::WorkOrderList && r.action()<=ManagementAction::WorkOrderCatalog) {
    const auto* w=r.work_order();
    if(!w || w->expected_revision()>INT64_MAX || w->id() < -1 || w->remaining() < -1 || w->remaining()>32767 || w->frequency() < -1 || w->frequency()>4 ||
       w->workshop_id() < -2 || w->max_workshops() < -1 || w->max_workshops()>32767 || w->condition_kind()>1 ||
       w->condition_index() < -1 || w->condition_index()>63 || w->compare() < -1 || w->compare()>5 ||
       w->threshold() < -1 || w->item_type() < -1 || w->target_order() < -1 || w->dependency() < -1 || w->dependency()>1 ||
       w->candidate_kind()>5 || (w->recipe() && w->recipe()->size()>128) || (w->query() && w->query()->size()>64)) return "invalid work order request";
    if(w->move() < -1 || w->move()>1 || w->expected_list_revision()>INT64_MAX ||
       w->expected_neighbor() < -1 || w->input_index() < -1 || w->item_subtype() < -1 ||
       w->mat_type() < -1 || w->mat_index() < -1 || w->group_type() < -1 ||
       w->group_subtype() < -1 || w->group_custom() < -1 || w->encrust_flags() < -1)
      return "invalid work order edit";
    if(w->traits()) {
      if(w->traits()->size()>256) return "too many work order traits";
      for(const auto* t:*w->traits()) if(!t || t->size()>64) return "invalid work order trait";
    }
    // Move and input edits are separate intents; input edits carry only material/decoration.
    const bool otherUpdate = w->remaining()!=-1 || w->frequency()!=-1 ||
        w->workshop_id()!=-2 || w->max_workshops()!=-1 || (w->recipe() && w->recipe()->size()) ||
        (w->query() && w->query()->size()) ||
        w->cursor() || w->condition_kind() || w->condition_index()!=-1 || w->remove_condition() ||
        w->compare()!=-1 || w->threshold()!=-1 || w->item_type()!=-1 ||
        w->target_order()!=-1 || w->dependency()!=-1 || w->candidate_kind() ||
        w->item_subtype()!=-1 || w->traits() || w->group_type()!=-1 ||
        w->group_subtype()!=-1 || w->group_custom()!=-1;
    const bool inputValue = w->mat_type()!=-1 || w->mat_index()!=-1 || w->encrust_flags()!=-1;
    if(r.action()==ManagementAction::WorkOrderUpdate && w->input_index()<0 && inputValue)
      return "work order input index required";
    if(w->move() && (r.action()!=ManagementAction::WorkOrderUpdate || w->id()<0 ||
       !w->expected_revision() || w->expected_neighbor()<0 || !w->expected_list_revision() ||
       otherUpdate || w->input_index()!=-1 || w->mat_type()!=-1 || w->mat_index()!=-1 ||
       w->encrust_flags()!=-1)) return "invalid exclusive work order move";
    if(w->input_index()>=0 && (r.action()!=ManagementAction::WorkOrderUpdate || w->id()<0 ||
       !w->expected_revision() || w->move() || w->expected_neighbor()!=-1 ||
       w->expected_list_revision() || otherUpdate || !inputValue)) return "invalid exclusive work order input edit";
    if((r.action()==ManagementAction::WorkOrderInspect || r.action()==ManagementAction::WorkOrderUpdate || r.action()==ManagementAction::WorkOrderDelete || r.action()==ManagementAction::WorkOrderCondition) && w->id()<0) return "work order id required";
    if((r.action()==ManagementAction::WorkOrderUpdate || r.action()==ManagementAction::WorkOrderDelete || r.action()==ManagementAction::WorkOrderCondition) && !w->expected_revision()) return "work order revision required";
    if(r.action()==ManagementAction::WorkOrderCreate && (!w->recipe() || !w->recipe()->size() || w->remaining()<0)) return "new work order recipe and quantity required";
    if(r.action()==ManagementAction::WorkOrderCondition) {
      if(w->remove_condition() && w->condition_index()<0) return "condition identity required";
      if(!w->remove_condition() && ((w->condition_kind()==0 && (w->compare()<0 || w->threshold()<0)) ||
        (w->condition_kind()==1 && (w->target_order()<0 || w->target_order()==w->id() || w->dependency()<0)))) return "invalid work order condition";
    }
  } else if(r.work_order()) return "unexpected work order payload";
  if(r.action()>=ManagementAction::CitizenList && r.action()<=ManagementAction::WorkDetailMode) {
    const auto* c=r.citizen();
    if(!c || c->unit_id() < -1 || c->detail_index() < -1 || c->detail_index()>127 || c->expected_revision()>INT64_MAX ||
       c->member() < -1 || c->member()>1 || c->mode() < -1 || c->mode()>3 || (c->query() && c->query()->size()>128)) return "invalid citizen request";
    if((r.action()==ManagementAction::CitizenInspect || r.action()==ManagementAction::WorkDetailMembership) && c->unit_id()<0) return "citizen id required";
    if(r.action()>=ManagementAction::WorkDetailInspect && c->detail_index()<0) return "work detail index required";
    if(r.action()>=ManagementAction::WorkDetailMembership && !c->expected_revision()) return "work detail receipt required";
    if(r.action()==ManagementAction::WorkDetailMembership && (c->member()<0 || c->mode()!=-1)) return "membership edit requires only member field";
    if(r.action()==ManagementAction::WorkDetailMode && (c->mode()<0 || c->member()!=-1)) return "mode edit requires only mode field";
    if(r.action()<ManagementAction::WorkDetailMembership && (c->member()!=-1 || c->mode()!=-1)) return "unexpected citizen edit fields";
  } else if(r.citizen()) return "unexpected citizen payload";
  if(r.action()>=ManagementAction::ReportList && r.action()<=ManagementAction::ReportInspect) {
    const auto* p=r.report();
    if(!p || p->id() < -1 || p->before_id() < -1 || (p->query() && p->query()->size()>128))return "invalid report request";
    if(r.action()==ManagementAction::ReportInspect && (p->id()<0 || p->before_id()!=-1 || (p->query() && p->query()->size())))return "invalid report inspection";
    if(r.action()==ManagementAction::ReportList && p->id()!=-1)return "unexpected report identity";
  } else if(r.report())return "unexpected report payload";
  if(r.action()>=ManagementAction::AgreementList && r.action()<=ManagementAction::AgreementInspect) {
    const auto* a=r.agreement();
    if(!a || a->id() < -1 || a->before_id() < -1 || (a->query() && a->query()->size()>128))return "invalid agreement request";
    if(r.action()==ManagementAction::AgreementInspect && (a->id()<0 || a->before_id()!=-1 || (a->query() && a->query()->size()) || a->pending_only()))return "invalid agreement inspection";
    if(r.action()==ManagementAction::AgreementList && a->id()!=-1)return "unexpected agreement identity";
  } else if(r.agreement())return "unexpected agreement payload";
  if ((r.action() == ManagementAction::Inspect || r.action() == ManagementAction::Remove) &&
      r.building_id() < 0)
    return "building id required";
  if(r.action()>=ManagementAction::KitchenOpen && r.action()<=ManagementAction::KitchenClose) {
    const auto* k=r.kitchen();
    if(!k || k->item_type()< -1 || k->item_type()>255 || k->item_subtype()< -1 || k->mat_type()< -1 || k->mat_index()< -1 || k->receipt()>INT64_MAX || k->cursor()>4096 || (k->query() && k->query()->size()>128)) return "invalid Kitchen request";
    const bool edit=r.action()==ManagementAction::KitchenSetPermission;
    if(edit ? (k->item_type()<0 || (k->permission()!=1 && k->permission()!=2) || k->allowed()<0 || k->allowed()>1) : (k->item_type()!=-1 || k->item_subtype()!=-1 || k->mat_type()!=-1 || k->mat_index()!=-1 || k->permission()!=0 || k->allowed()!=-1)) return "invalid Kitchen permission identity";
    if((edit || r.action()==ManagementAction::KitchenList) && !k->receipt()) return "Kitchen receipt required";
    if((r.action()==ManagementAction::KitchenOpen || r.action()==ManagementAction::KitchenClose) && (k->cursor() || (k->query() && k->query()->size()))) return "unexpected Kitchen search";
  } else if(r.kitchen()) return "unexpected Kitchen payload";
  if(r.action()>=ManagementAction::AppointmentsOpen && r.action()<=ManagementAction::AppointmentsBack) {
    const auto* a=r.appointments();
    if(!a || a->entity_id()< -1 || a->position_id()< -1 || a->assignment_id()< -1 || a->unit_id()< -1 || a->receipt()>INT64_MAX) return "invalid appointment request";
    if((r.action()==ManagementAction::AppointmentsCandidates || r.action()==ManagementAction::AppointmentsAssign) && (!a->receipt() || a->entity_id()<0 || a->position_id()<0)) return "appointment identity and receipt required";
  } else if(r.appointments()) return "unexpected appointment payload";
  if(r.action()>=ManagementAction::StocksOpen && r.action()<=ManagementAction::StocksClose) {
    const auto* a=r.stocks();
    if(!a || a->category() < -1 || a->category()>255 || a->item_id() < -1 || a->receipt()>INT64_MAX || (a->query() && a->query()->size()>128)) return "invalid Stocks request";
    if(r.action()==ManagementAction::StocksInspect && a->item_id()<0) return "Stocks item required";
    if((r.action()==ManagementAction::StocksList || r.action()==ManagementAction::StocksInspect) && !a->receipt()) return "Stocks receipt required";
  } else if(r.stocks()) return "unexpected Stocks payload";
  if(r.action()>=ManagementAction::TradeList && r.action()<=ManagementAction::TradeExchangeClose) {
    const auto* t=r.trade();
    if(!t || t->receipt()>INT64_MAX || t->side()>1 || t->selected() < -1 || t->selected()>1 || t->depot_id() < -1 || t->item_id() < -1 || t->expected_revision()>INT64_MAX || t->requested() < -1 || t->requested()>1 || t->anyone() < -1 || t->anyone()>1 || (t->query() && t->query()->size()>128)) return "invalid trade request";
    if(r.action()!=ManagementAction::TradeList && t->depot_id()<0) return "trade depot required";
    if(r.action()==ManagementAction::TradeUpdate) {
      if(!t->expected_revision() || (t->requested()==-1 && t->anyone()==-1)) return "trade revision and edit required";
    } else if(t->requested()!=-1 || t->anyone()!=-1 || t->expected_revision()) return "unexpected trade edit";
    if(r.action()<ManagementAction::TradeExchangeOpen && (t->receipt() || t->side() || t->selected()!=-1))return "unexpected exchange fields";
    if((r.action()==ManagementAction::TradeExchangeSelect || r.action()==ManagementAction::TradeExchangeSubmit) && !t->receipt())return "exchange receipt required";
    if(r.action()==ManagementAction::TradeExchangeSelect ? t->selected()<0 : t->selected()!=-1)return "invalid exchange selection";
    if((r.action()==ManagementAction::TradeBring || r.action()==ManagementAction::TradeExchangeSelect)!=(t->item_id()>=0)) return "trade item identity required only for hauling";
    if(r.action()!=ManagementAction::TradeGoods && r.action()!=ManagementAction::TradeExchangeInspect && r.action()!=ManagementAction::TradeExchangeSelect && (t->cursor() || (t->query() && t->query()->size()))) return "unexpected trade search";
  } else if(r.trade()) return "unexpected trade payload";
  if ((r.action() == ManagementAction::InspectAtTile ||
       r.action() == ManagementAction::RemoveConstruction) &&
      !r.origin())
    return "inspection tile required";
  if (r.definition() && r.definition()->size() > 128) return "definition too long";
  if (r.width() < 1 || r.width() > 31 || r.height() < 1 || r.height() > 31 || r.direction() > 3)
    return "invalid dimensions or orientation";
  if (r.action() == ManagementAction::Preview || r.action() == ManagementAction::Place) {
    if (!r.definition() || !r.definition()->size() || !r.origin())
      return "definition and origin required";
  }
  if (r.origin() && (r.origin()->x() < 0 || r.origin()->y() < 0 || r.origin()->z() < 0))
    return "negative origin";
  if (r.items()) {
    if (r.items()->size() > 64) return "too many inputs";
    std::set<int32_t> ids;
    for (auto id : *r.items())
      if (id < 0 || !ids.insert(id).second) return "invalid or duplicate input";
  }
  if (r.action() != ManagementAction::Place && r.items() && r.items()->size())
    return "unexpected selected inputs";
  return {};
}
inline std::optional<std::string> validateManagementState(const ManagementState& s) {
  if (s.schema_version() != kManagementVersion || !s.revision())
    return "invalid management version/revision";
  if (s.action() < ManagementAction::Catalog || s.action() > ManagementAction::CreatureInspect ||
      s.status() < ManagementStatus::Idle || s.status() > ManagementStatus::Rejected)
    return "invalid management enum";
  if (s.message() && s.message()->size() > 8192) return "message too long";
  if(s.action()==ManagementAction::CreatureInspect && s.status()==ManagementStatus::Ok && !s.creature()) return "creature result required";
  if(s.creature() && s.action()!=ManagementAction::CreatureInspect) return "unexpected creature result";
  if(const auto* c=s.creature()) {
    size_t bytes=0,records=0,facts=0;
    auto text=[&](const flatbuffers::String* t,size_t limit){if(!t)return true;bytes+=t->size();return t->size()<=limit && bytes<=131072;};
    if(c->unit_id()<0 || c->age()< -1 || c->sex()< -1 || c->sex()>2 || !c->origin() ||
       c->origin()->x()<0 || c->origin()->y()<0 || c->origin()->z()<0 ||
       !text(c->name(),512) || !text(c->species(),512) || !text(c->profession(),512) || !text(c->job(),512) ||
       !c->sections() || c->sections()->size()!=25) return "invalid creature header";
    if(const auto* p=c->portrait()) {
      if(!p->tile_pages() || p->tile_pages()->size()>256 || !p->palettes() || p->palettes()->size()>256 || !p->layers() || p->layers()->size()>256) return "invalid creature portrait references";
      for(const auto* t:*p->tile_pages())if(!text(t,256))return "invalid creature portrait page";
      for(const auto* t:*p->palettes())if(!text(t,512))return "invalid creature portrait palette";
      for(const auto* l:*p->layers())if(l->page()>=p->tile_pages()->size() || !l->cells_x() || !l->cells_y() || (l->palette()!=65535 && l->palette()>=p->palettes()->size()))return "invalid creature portrait layer";
    }
    std::set<uint8_t> sections;
    for(const auto* section:*c->sections()) {
      if(!section || section->kind()>CreatureSectionKind::WorkAnimals || !sections.insert(uint8_t(section->kind())).second ||
         !text(section->reason(),1024) || (section->records() && section->records()->size()>256) ||
         (c->complete() && (!section->available() || section->truncated()))) return "invalid creature section";
      if(section->records())for(const auto* row:*section->records()) {
        if(!row || ++records>2048 || !text(row->name(),512) || (row->facts() && row->facts()->size()>12)) return "invalid creature record";
        if(row->facts())for(const auto* fact:*row->facts())
          // Matches the bounded selected-creature collector in creature.lua.
          if(!fact || ++facts>8192 || !fact->key() || !fact->key()->size() || !text(fact->key(),64) || !text(fact->text(),1024)) return "invalid creature fact";
      }
    }
  }
  if (s.required() > 64 || s.jobs() > 1024 || s.build_stage() < -1 || s.max_stage() < -1)
    return "invalid construction state";
  if (s.max_stage() >= 0 && s.build_stage() > s.max_stage()) return "invalid build stage";
  if (s.catalog()) {
    if (s.catalog()->size() > 256) return "catalog too large";
    std::set<std::string> keys;
    for (auto* d : *s.catalog())
      if (!d || !d->key() || !d->key()->size() || d->key()->size() > 128 ||
          !keys.insert(d->key()->str()).second || d->width() < 1 || d->width() > 31 ||
          d->height() < 1 || d->height() > 31 || (d->name() && d->name()->size() > 256) ||
          (d->reason() && d->reason()->size() > 1024))
        return "invalid definition";
  }
  if (s.inputs()) {
    if (s.inputs()->size() > 128) return "input page too large";
    std::set<int32_t> ids;
    for (auto* i : *s.inputs())
      if (!i || i->id() < 0 || !ids.insert(i->id()).second || !i->quantity() ||
          (i->description() && i->description()->size() > 1024))
        return "invalid input";
  }
  if (const auto* a=s.area()) {
    if ((a->areas() && a->areas()->size()>64) || (a->choices() && a->choices()->size()>128)) return "area response too large";
    size_t extentTotal=0,linkTotal=0;
    std::set<int32_t> areaIds,choiceIds;
    if (a->areas()) for (const auto* v:*a->areas()) {
      if (!v || v->id()<0 || v->kind()>AreaKind::Zone || !v->origin() ||
          !areaIds.insert(v->id()).second || v->origin()->x()<0 || v->origin()->y()<0 || v->origin()->z()<0 ||
          v->barrels()<0 || v->bins()<0 || v->wheelbarrows()<0 || v->owner_id() < -1 || v->zone_type() < -1 || v->zone_type()>255 ||
          v->width()<1 || v->height()<1 || v->width()>256 || v->height()>256 ||
          !v->extents() || v->extents()->size()!=uint32_t(v->width())*v->height() ||
          v->extents()->size()>65536 || (v->categories() & ~0x1ffffu) ||
          (v->name() && v->name()->size()>512) || (v->owner_name() && v->owner_name()->size()>512) ||
          (v->gives() && v->gives()->size()>1024) || (v->takes() && v->takes()->size()>1024)) return "invalid area state";
      for (auto extent:*v->extents()) if(extent>1) return "invalid area extent";
      extentTotal+=v->extents()->size();
      for(auto* links:{v->gives(),v->takes()}) if(links){
        std::set<int32_t> ids;
        for(auto id:*links) if(id<0 || id==v->id() || !ids.insert(id).second) return "invalid area link";
        linkTotal+=links->size();
      }
    }
    if(extentTotal>32768 || linkTotal>8192) return "area response exceeds bounded payload";
    if (a->choices()) for(const auto* c:*a->choices())
      if(!c || c->id()<0 || !choiceIds.insert(c->id()).second || !c->name() || c->name()->size()>512) return "invalid area choice";
  }
  if (const auto* p=s.production()) {
    if ((p->buildings() && p->buildings()->size()>64) || (p->recipes() && p->recipes()->size()>128) ||
        (p->jobs() && p->jobs()->size()>64) || (p->crops() && p->crops()->size()>256) ||
        (p->seasonal_crops() && p->seasonal_crops()->size()!=0 && p->seasonal_crops()->size()!=4) ||
        p->current_season() < -1 || p->current_season()>3 || p->selected_building() < -1 || p->created_job() < -1 ||
        (p->detail() && p->detail()->size()>2048)) return "invalid production state";
    auto textOk=[](const flatbuffers::String* t,size_t limit){return t && t->size()<=limit;};
    auto requirementsOk=[&](const auto* values){
      if(!values || values->size()>16) return false;
      for(const auto* v:*values) if(!v || !textOk(v->description(),512) || v->quantity()<0 || v->quantity()>1000000 || v->item_type() < -1) return false;
      return true;
    };
    std::set<int32_t> ids;
    if(p->buildings()) for(const auto* v:*p->buildings()) {
      if(!v || v->id()<0 || !ids.insert(v->id()).second || !textOk(v->name(),512) || !textOk(v->kind(),128) || !v->origin() ||
         v->origin()->x()<0 || v->origin()->y()<0 || v->origin()->z()<0 || v->build_stage()<0 || v->max_stage()<v->build_stage() || v->queue_size()>1024) return "invalid production building";
    }
    std::set<std::string> keys;
    if(p->recipes()) for(const auto* v:*p->recipes()) if(!v || !textOk(v->key(),128) || !v->key()->size() || !keys.insert(v->key()->str()).second || !textOk(v->name(),512) || !requirementsOk(v->requirements())) return "invalid production recipe";
    ids.clear();
    if(p->jobs()) for(const auto* v:*p->jobs()) if(!v || v->id()<0 || !ids.insert(v->id()).second || v->worker_id() < -1 || v->job_type()<0 || v->completion_timer() < -1 || !textOk(v->name(),512) || !textOk(v->worker_name(),512) || !textOk(v->status(),512) || !requirementsOk(v->requirements())) return "invalid production job";
    ids.clear();
    if(p->crops()) for(const auto* v:*p->crops()) if(!v || v->id()<0 || v->id()>32767 || !ids.insert(v->id()).second || !textOk(v->name(),512) || !v->seasons() || v->seasons()>15) return "invalid farm crop";
    if(p->seasonal_crops()) for(auto id:*p->seasonal_crops()) if(id < -1 || id>32767) return "invalid seasonal crop";
  }

  if(const auto* a=s.selection()) {
    auto text=[](const flatbuffers::String* v,size_t max){return v && v->size()<=max;};
    if(a->kind()>SelectionKind::Vermin || a->id() < -1 || (a->open() && (!a->receipt() || a->kind()==SelectionKind::None || a->id()<0)) ||
       !text(a->title(),512) || !text(a->subtitle(),512) || !text(a->job(),512) || !text(a->description(),16384) ||
       !a->alternatives() || a->alternatives()->size()>256 || !a->items() || a->items()->size()>256 || !a->overview() || a->overview()->size()>32 || a->weight() < -1 || a->value() < -1) return "invalid selection state";
    if(a->tile() && (a->tile()->x()<0 || a->tile()->y()<0 || a->tile()->z()<0)) return "invalid selected tile";
    auto identity=[&](const SelectionIdentity* e){return e && e->kind()>SelectionKind::None && e->kind()<=SelectionKind::Vermin && e->id()>=0 && text(e->name(),512);};
    for(const auto* e:*a->alternatives()) if(!identity(e)) return "invalid selection identity";
    if(a->container() && !identity(a->container())) return "invalid selected container";
    for(const auto* e:*a->items()) if(!e || e->id()<0 || !text(e->name(),512)) return "invalid selected item";
    size_t bytes=0;for(const auto* e:*a->overview()) {if(!e || e->section()>SelectionSection::UnmetNeeds || !text(e->text(),16384)) return "invalid unit overview";bytes+=e->text()->size();}if(bytes>65536)return "unit overview too large";
    if(const auto* p=a->portrait()) {
      if(!p->tile_pages() || p->tile_pages()->size()>256 || !p->palettes() || p->palettes()->size()>256 || !p->layers() || p->layers()->size()>256) return "invalid portrait references";
      for(const auto* t:*p->tile_pages())if(!text(t,256))return "invalid portrait page";
      for(const auto* t:*p->palettes())if(!text(t,512))return "invalid portrait palette";
      for(const auto* l:*p->layers())if(l->page()>=p->tile_pages()->size() || !l->cells_x() || !l->cells_y() || (l->palette()!=65535 && l->palette()>=p->palettes()->size()))return "invalid portrait layer";
    }
  }
  if(const auto* a=s.alert()) {
    if(a->view()>AlertView::History || a->category() < -1 || a->category()>36 || a->unit_id() < -1 ||
       a->unit_category() < -1 || a->unit_category()>2 || !a->entries() || a->entries()->size()>512 ||
       !a->tabs() || a->tabs()->size()>64 || a->selected_tab() < -1 || a->selected_tab()>=int(a->tabs()->size()) || a->scroll()<0 || a->total()>65536 ||
       (a->view()!=AlertView::Closed && !a->receipt())) return "invalid alert state";
    if(a->focus() && (a->focus()->x()<0 || a->focus()->y()<0 || a->focus()->z()<0)) return "invalid alert focus";
    size_t bytes=0;
    for(const auto* e:*a->entries()) {
      if(!e || !e->text() || e->text()->size()>8192 || e->report_id() < -1 || e->unit_id() < -1 || e->unit_category() < -1 || e->unit_category()>2) return "invalid alert entry";
      bytes+=e->text()->size();
    }
    if(bytes>131072) return "alert text limit";
    for(const auto* t:*a->tabs()) if(!t || t->size()>128) return "invalid alert tab";
  }
  if(const auto* w=s.work_order()) {
    auto textOk=[](const flatbuffers::String* v,size_t max){return !v || v->size()<=max;};
    if((w->orders() && w->orders()->size()>16) || (w->recipes() && w->recipes()->size()>128) ||
       (w->choices() && w->choices()->size()>128) || (w->managers() && w->managers()->size()>32) || !textOk(w->detail(),2048)) return "work order response too large";
    if(w->build_phase()>3 || w->build_done()>w->build_total() || w->list_revision()>INT64_MAX)
      return "invalid work order build state";
    auto rowsOk=[](const auto* rows){return !rows || rows->size()<=128;};
    if(!rowsOk(w->materials()) || !rowsOk(w->traits()) || !rowsOk(w->types()) ||
       !rowsOk(w->groups()) || !rowsOk(w->tasks())) return "work order catalog too large";
    if(w->materials())for(const auto* row:*w->materials())
      if(!row || row->mat_type() < -1 || row->mat_index() < -1 ||
         !textOk(row->name(),128))return "invalid work order material";
    if(w->traits())for(const auto* row:*w->traits())
      if(!row || !textOk(row->key(),64) || !textOk(row->name(),128))return "invalid work order trait row";
    if(w->types())for(const auto* row:*w->types())
      if(!row || row->item_type() < -1 || row->item_subtype() < -1 ||
         !textOk(row->name(),128))return "invalid work order type";
    if(w->groups())for(const auto* row:*w->groups())
      if(!row || row->type() < -1 || row->subtype() < -1 || row->custom() < -1 ||
         !textOk(row->name(),128))return "invalid work order group";
    if(w->tasks())for(const auto* row:*w->tasks())
      if(!row || row->job_type() < -1 || row->item_type() < -1 || row->item_subtype() < -1 ||
         row->mat_type() < -1 || row->mat_index() < -1 || !textOk(row->reaction(),64) ||
         !textOk(row->key(),64) || !textOk(row->name(),128))return "invalid work order task";
    std::set<int32_t> ids;size_t conditionCount=0,jobCount=0,traitCount=0,inputCount=0;
    if(w->orders()) for(const auto* o:*w->orders()) {
      if(!o || o->id()<0 || !ids.insert(o->id()).second || !o->revision() || o->revision()>INT64_MAX || !textOk(o->name(),512) || !textOk(o->reason(),1024) ||
         o->position() < -1 || o->size_raw() < -1 || o->mat_type() < -1 || o->mat_index() < -1 ||
         o->detail_kind()>6 || o->total()<0 || o->remaining()<0 || o->remaining()>o->total() || o->frequency() < -1 || o->frequency()>4 ||
         o->finished_year() < -1 || o->finished_tick() < -1 || o->workshop_id() < -1 || o->max_workshops()<0 ||
         (o->inputs() && o->inputs()->size()>64) || (o->conditions() && o->conditions()->size()>64) || (o->generated_jobs() && o->generated_jobs()->size()>1024)) return "invalid work order";
      if(o->inputs())for(const auto* input:*o->inputs()) {
        if(!input || input->mat_type() < -1 || input->mat_index() < -1 ||
           !textOk(input->description(),1024))return "invalid work order input";
        ++inputCount;
      }
      std::set<int32_t> jobs; if(o->generated_jobs()) for(auto id:*o->generated_jobs()) {if(id<0 || !jobs.insert(id).second)return "invalid generated job";++jobCount;}
      std::set<uint32_t> conditions;
      if(o->conditions()) for(const auto* c:*o->conditions()) {
        if(!c || c->estimate_count() < -1 || c->item_subtype() < -1 || c->mat_type() < -1 || c->mat_index() < -1 ||
           c->satisfaction()>2 || c->kind()>1 || c->index()>63 || !conditions.insert(uint32_t(c->kind())*64+c->index()).second ||
           !textOk(c->description(),1024) || c->compare() < -1 || c->compare()>5 || c->threshold() < -1 || c->item_type() < -1 ||
           c->target_order() < -1 || c->dependency() < -1 || c->dependency()>1) return "invalid work order condition";
        if(c->editable() && ((c->kind()==0 && (c->compare()<0 || c->threshold()<0)) ||
          (c->kind()==1 && (c->target_order()<0 || c->dependency()<0 || c->target_order()==o->id())))) return "invalid editable condition";
        if(c->traits()) {
          if(c->traits()->size()>256)return "too many condition traits";
          traitCount+=c->traits()->size();
          for(const auto* t:*c->traits())if(!t || !textOk(t,64))return "invalid condition trait";
        }
        ++conditionCount;
      }
    }
    if(conditionCount>128 || jobCount>2048 || traitCount>2048 || inputCount>128)return "work order aggregate limit exceeded";
    ids.clear();if(w->choices())for(const auto* c:*w->choices())if(!c || c->id()<0 || !ids.insert(c->id()).second || !textOk(c->name(),512))return "invalid work order choice";
    ids.clear();if(w->managers())for(const auto* m:*w->managers()){
      if(!m || m->unit_id()<0 || !ids.insert(m->unit_id()).second || !textOk(m->name(),512) || !textOk(m->position(),512) || !textOk(m->job(),512) || (m->offices() && m->offices()->size()>64))return "invalid manager role";
      std::set<int32_t> offices;if(m->offices())for(auto id:*m->offices())if(id<0 || !offices.insert(id).second)return "invalid manager office";
    }
    std::set<std::string> keys;if(w->recipes())for(const auto* r:*w->recipes())if(!r || !r->key() || !r->key()->size() || !textOk(r->key(),128) || !keys.insert(r->key()->str()).second || !textOk(r->name(),512) || (r->requirements() && r->requirements()->size()))return "invalid manager recipe";
  }
  if(const auto* c=s.citizen()) {
    if((c->citizens() && c->citizens()->size()>32) || (c->details() && c->details()->size()>16) || c->selected_unit() < -1 || c->selected_detail() < -1 || c->selected_detail()>127 || (c->detail() && c->detail()->size()>2048)) return "invalid citizen state";
    auto textOk=[](const flatbuffers::String* v,size_t cap){return v && v->size()<=cap;};
    auto namesOk=[](const auto* names,const auto* ids){if(!names||!ids||names->size()!=ids->size())return false;for(const auto* name:*names)if(!name||name->size()>128)return false;return true;};
    auto laborsOk=[](const auto* values){if(!values || values->size()>94)return false;int prior=-1;for(auto v:*values){if(v<0 || v>93 || v<=prior)return false;prior=v;}return true;};
    std::set<int32_t> ids;
    if(c->citizens())for(const auto* v:*c->citizens()) {
      if(!v || v->id()<0 || !ids.insert(v->id()).second || v->age() < -1 || v->age()>1000000 || !v->origin() || v->origin()->x()<0 || v->origin()->y()<0 || v->origin()->z()<0 || !textOk(v->name(),512) || !textOk(v->profession(),512) || !textOk(v->job(),512) || !textOk(v->reason(),512) || !laborsOk(v->labors()) || !namesOk(v->labor_names(),v->labors()) || (v->roles() && v->roles()->size()>32) || (v->offices() && v->offices()->size()>64))return "invalid citizen row";
      if(v->assigned_details()) {
        if(v->assigned_details()->size()>128)return "too many citizen work details";
        int prior=-1;
        for(const auto* d:*v->assigned_details()) {
          if(!d || d->index()<=prior || d->index()>127 || d->icon()<0 || !textOk(d->name(),512))return "invalid citizen work detail";
          prior=d->index();
        }
      }
      if(const auto* p=v->sheet_icon()) {
        if(!p->tile_pages() || p->tile_pages()->size()>256 || !p->palettes() || p->palettes()->size()>256 || !p->layers() || p->layers()->size()>256)return "invalid citizen sheet icon references";
        for(const auto* t:*p->tile_pages())if(!textOk(t,256))return "invalid citizen sheet icon page";
        for(const auto* t:*p->palettes())if(!textOk(t,512))return "invalid citizen sheet icon palette";
        for(const auto* l:*p->layers())if(l->page()>=p->tile_pages()->size() || !l->cells_x() || !l->cells_y() || (l->palette()!=65535 && l->palette()>=p->palettes()->size()))return "invalid citizen sheet icon layer";
      }
      if(v->roles())for(const auto* role:*v->roles())if(!role || !textOk(role->name(),512) || role->required_office()<0)return "invalid citizen role";
      std::set<int32_t> offices;if(v->offices())for(auto id:*v->offices())if(id<0 || !offices.insert(id).second)return "invalid citizen office";
    }
    ids.clear();size_t members=0;
    if(c->details())for(const auto* d:*c->details()) {
      if(!d || d->index()<0 || d->index()>127 || !ids.insert(d->index()).second || !d->revision() || d->revision()>INT64_MAX || d->mode()>3 || !textOk(d->name(),512) || !textOk(d->reason(),512) || !laborsOk(d->labors()) || !namesOk(d->labor_names(),d->labors()) || !d->assigned_units() || d->assigned_units()->size()>1024)return "invalid work detail";
      int32_t prior=-1;for(auto id:*d->assigned_units()){if(id<0 || id<=prior)return "invalid work detail membership";prior=id;}
      members+=d->assigned_units()->size();
    }
    if(members>8192)return "work detail response too large";
  }
  if(const auto* r=s.report()) {
    if(r->next_before_id() < -1 || (r->detail() && r->detail()->size()>2048) || (r->reports() && r->reports()->size()>16))return "invalid report state";
    size_t bytes=0;std::set<int32_t> ids;
    if(r->reports())for(const auto* v:*r->reports()) {
      if(!v || v->id()<0 || !ids.insert(v->id()).second || v->year()<0 || v->year_tick()<0 || v->year_tick()>=403200 || v->repeat_count()<0 || !v->text() || v->text()->size()>16384 || !v->category() || v->category()->size()>128)return "invalid report row";
      auto pos=[](bool visible,int x,int y,int z){return visible?(x>=0&&y>=0&&z>=0):(x==-1&&y==-1&&z==-1);};
      if(!pos(v->position_visible(),v->x(),v->y(),v->z()) || !pos(v->position2_visible(),v->x2(),v->y2(),v->z2()))return "invalid report location";
      bytes+=v->text()->size();
    }
    if(bytes>131072)return "report text budget exceeded";
  }
  if(const auto* a=s.agreement()) {
    if(a->next_before_id() < -1 || (a->detail() && a->detail()->size()>2048) || (a->agreements() && a->agreements()->size()>16))return "invalid agreement state";
    size_t bytes=0;std::set<int32_t> ids;
    auto text=[&](const flatbuffers::String* t){if(!t || t->size()>2048)return false;bytes+=t->size();return true;};
    if(a->agreements())for(const auto* v:*a->agreements()) {
      if(!v || v->id()<0 || !ids.insert(v->id()).second || v->status()>AgreementStatus::Concluded || !text(v->summary()) || !text(v->reason()) || !v->details() || v->details()->size()>8 || !v->parties() || v->parties()->size()>8)return "invalid agreement row";
      if((v->status()==AgreementStatus::Accepted && (v->not_approved() || v->concluded())) || (v->status()==AgreementStatus::Unapproved && (!v->not_approved() || v->concluded())) || (v->status()==AgreementStatus::Concluded && !v->concluded()))return "inconsistent agreement status";
      std::set<int32_t> parties,details;
      for(const auto* p:*v->parties()) {
        if(!p || p->id()<0 || !parties.insert(p->id()).second || !text(p->name()))return "invalid agreement party";
        for(const auto* vec:{p->entity_ids(),p->histfig_ids()}) {
          if(!vec || vec->size()>32)return "invalid agreement members";
          std::set<int32_t> members;for(auto id:*vec)if(id<0 || !members.insert(id).second)return "invalid agreement member";
        }
      }
      for(const auto* d:*v->details()) {
        if(!d || d->id()<0 || !details.insert(d->id()).second || d->kind() < -1 || d->site_id() < -1 || d->year() < -1 || d->year_tick() < -1 || d->year_tick()>=403200 || d->applicant_party() < -1 || d->government_party() < -1 || d->location_type() < -1 || d->tier() < -1 || d->profession() < -1 || d->deity_type() < -1 || d->deity_id() < -1 || !text(d->description()))return "invalid agreement detail";
        if(v->complete() && ((d->applicant_party()>=0 && !parties.count(d->applicant_party())) || (d->government_party()>=0 && !parties.count(d->government_party()))))return "missing agreement party";
      }
    }
    if(bytes>131072)return "agreement text budget exceeded";
  }
  if(const auto* k=s.kitchen()) {
    if(k->receipt()>INT64_MAX || (k->open() != (k->receipt()>0)) || !k->ingredients() || k->ingredients()->size()>16 || k->total()>4096 || k->next_cursor()>k->total() || !k->detail() || k->detail()->size()>2048 || (!k->open() && (k->ingredients()->size() || k->total() || k->next_cursor()))) return "invalid Kitchen state";
    std::set<std::tuple<int32_t,int16_t,int16_t,int32_t>> keys;
    for(const auto* row:*k->ingredients()) if(!row || row->item_type()<0 || row->item_type()>255 || row->item_subtype()< -1 || row->mat_type()< -1 || row->mat_index()< -1 || !row->name() || row->name()->size()>512 || row->count()>INT32_MAX || (!row->can_cook() && row->cook_allowed()) || (!row->can_brew() && row->brew_allowed()) || !keys.emplace(row->item_type(),row->item_subtype(),row->mat_type(),row->mat_index()).second) return "invalid Kitchen ingredient";
    if(k->ingredients()->size()>k->total()) return "invalid Kitchen total";
  }
  if(const auto* t=s.appointments()) {
    auto text=[](const flatbuffers::String* v,size_t cap){return v && v->size()<=cap;};
    if(t->receipt()>INT64_MAX || (t->open()&&!t->receipt()) || (t->choosing()&&!t->open()) || !text(t->detail(),2048) || !t->roles() || t->roles()->size()>64 || !t->candidates() || t->candidates()->size()>256) return "invalid appointments state";
    std::set<int32_t> ids;
    for(const auto* r:*t->roles()) if(!r || r->entity_id()<0 || r->position_id()<0 || r->assignment_id()< -1 || r->unit_id()< -1 || !text(r->name(),128) || !text(r->holder(),256) || !text(r->reason(),256) || r->office()<0 || r->bedroom()<0 || r->dining()<0 || r->tomb()<0 || r->boxes()<0 || r->cabinets()<0 || r->racks()<0 || r->stands()<0) return "invalid appointment role";
    for(const auto* c:*t->candidates()) if(!c || c->unit_id()< -1 || !ids.insert(c->unit_id()).second || !text(c->name(),256) || !text(c->skill(),256) || !text(c->reason(),256)) return "invalid appointment candidate";
  }
  if(const auto* t=s.stocks()) {
    auto text=[](const flatbuffers::String* v,size_t n){return v && v->size()<=n;};
    if(t->receipt()>INT64_MAX || (t->open() && !t->receipt()) || t->category() < -1 || t->category()>255 || !text(t->detail(),2048) || !t->categories() || t->categories()->size()>256 || !t->items() || t->items()->size()>16) return "invalid Stocks state";
    auto count=[](const StockCount* c){return c && c->accuracy()<=StockAccuracy::Approximate && (c->accuracy()!=StockAccuracy::Unavailable || !c->amount());};
    std::set<int32_t> ids;
    for(const auto* c:*t->categories()) if(!c || c->id()<0 || c->id()>255 || !ids.insert(c->id()).second || !text(c->name(),128) || !count(c->available()) || !count(c->unavailable())) return "invalid Stocks category";
    ids.clear();
    for(const auto* i:*t->items()) {
      if(!i || i->id()<0 || !ids.insert(i->id()).second || i->category()<0 || i->category()>255 || !text(i->description(),512) || !i->quantity()) return "invalid Stocks item";
      if(i->can_focus() ? (i->x()<0 || i->y()<0 || i->z()<0) : (i->x()!=-1 || i->y()!=-1 || i->z()!=-1)) return "invalid Stocks location";
    }
  }
  if(const auto* t=s.trade()) {
    auto text=[](const flatbuffers::String* v,size_t n){return v && v->size()<=n;};
    if(t->selected_depot() < -1 || !text(t->detail(),2048) || !t->depots() || t->depots()->size()>64 || !t->caravans() || t->caravans()->size()>64 || !t->goods() || t->goods()->size()>64) return "invalid trade state";
    if(const auto* e=t->exchange()) {
      if(e->receipt()>INT64_MAX || e->side()>1 || e->outcome()>3 || e->entity_id() < -1 || e->merchant_id() < -1 || e->broker_id() < -1 || e->merchant_count()>8192 || e->fort_count()>8192 || e->merchant_selected()>e->merchant_count() || e->fort_selected()>e->fort_count() || !text(e->reply(),2048) || !text(e->reason(),2048))return "invalid trade exchange";
      if(e->can_submit() && (!e->open() || !e->receipt() || !e->merchant_selected() || !e->fort_selected()))return "inconsistent exchange readiness";
    }
    std::set<int32_t> ids;
    for(const auto* d:*t->depots()) if(!d || d->id()<0 || !ids.insert(d->id()).second || !d->origin() || d->origin()->x()<0 || d->origin()->y()<0 || d->origin()->z()<0 || !d->revision() || d->revision()>INT64_MAX || !text(d->broker(),512)) return "invalid trade depot";
    ids.clear();
    for(const auto* c:*t->caravans()) if(!c || c->id()<0 || !ids.insert(c->id()).second || !text(c->name(),512) || !text(c->state(),128) || c->days_remaining()<0) return "invalid trade caravan";
    ids.clear();
    for(const auto* g:*t->goods()) if(!g || g->id()<0 || !ids.insert(g->id()).second || !text(g->description(),512) || !g->quantity() || (g->reason() && !text(g->reason(),512))) return "invalid trade good";
  }
  return {};
}
}  // namespace df3d::mirror
