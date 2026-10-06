#pragma once
#include <tuple>
#include <optional>
#include "session_util.h"
#include "location_catalog_util.h"
#include "location_details_util.h"
#include "location_staff_candidates_util.h"
namespace df3d::mirror {
inline constexpr uint32_t kManagementVersion = 53;
inline constexpr const char* kManagementRegionName = "Local\\df3d_management_v53";
inline constexpr uint32_t kManagementCapacity = 512 * 1024;
// 192 KiB maximum path payload leaves room for the rest of the reply envelope.
inline constexpr uint32_t kConnectedTrackMaxTiles = 16384;
// v39: Track may select one distinct material group per tile (16,384 total).
// The maximum encoded request is tested against this bound; older peers use a separate region.
inline constexpr uint32_t kManagementCommandCapacity = 2 * 1024 * 1024;
inline bool areaZoneSettingsPresent(const AreaZoneSettings* z) {
  return z && (z->pond_mode() || z->facing() || z->tomb_citizens()!=-1 ||
      z->tomb_pets()!=-1 || z->gather_trees()!=-1 || z->gather_shrubs()!=-1);
}
inline bool validAreaZoneSettings(const AreaZoneSettings* z) {
  if(!z) return true;
  return z->pond_mode()<=2 && z->facing()<=4 &&
      z->tomb_citizens()>=-1 && z->tomb_citizens()<=1 &&
      z->tomb_pets()>=-1 && z->tomb_pets()<=1 &&
      z->gather_trees()>=-1 && z->gather_trees()<=1 &&
      z->gather_shrubs()>=-1 && z->gather_shrubs()<=1;
}
// Keep this order in the Lua dispatcher too: selector, matrix, kind, legacy
// ownership, new-field ownership/requirements, identities, then bounded sizes.
inline std::optional<std::string> validateAreaOperation(ManagementAction action, const AreaRequest& a) {
  const auto op=static_cast<uint8_t>(a.operation());
  if(op>25) return "Unsupported area operation";
  const bool multi=op>=16 && op<=18;
  const bool counts=op==19;
  const bool locationChoices=op==20;
  const bool staffCandidates=op==24;
  const bool staffEdit=op==25;
  const bool locationOpen=op==22;
  const bool locationAccess=op==23;
  const bool locationDetails=op==21 || locationOpen || locationAccess || staffEdit;
  const bool inspect=action==ManagementAction::AreaInspect;
  const bool create=action==ManagementAction::AreaCreate;
  const bool update=action==ManagementAction::AreaUpdate;
  bool allowed=op==0;
  switch(a.operation()) {
    case AreaOperation::SettingsPage: case AreaOperation::LocationList: case AreaOperation::Links: case AreaOperation::PaintCounts: case AreaOperation::LocationChoices: case AreaOperation::LocationDetails: case AreaOperation::LocationStaffCandidates:
      allowed=inspect; break;
    case AreaOperation::SettingsSet: case AreaOperation::Preset: case AreaOperation::Rename:
    case AreaOperation::LocationSet: case AreaOperation::LocationCreate: case AreaOperation::ZoneSettings:
    case AreaOperation::AssignUnits: case AreaOperation::SquadUse: case AreaOperation::Toggles: case AreaOperation::LocationOpen: case AreaOperation::LocationAccess: case AreaOperation::LocationStaffEdit:
      allowed=update; break;
    case AreaOperation::Paint: allowed=create || update; break;
    case AreaOperation::CandidateList: allowed=action==ManagementAction::AreaCandidates; break;
    case AreaOperation::WorkshopLink: allowed=action==ManagementAction::AreaLink; break;
    case AreaOperation::MultiCreate: allowed=create; break;
    case AreaOperation::MultiUndo: case AreaOperation::MultiFinish: allowed=update; break;
    default: break;
  }
  if(!allowed) return "Area operation is not valid for this action";
  if(a.kind()>AreaKind::Workshop || (a.kind()==AreaKind::Workshop)!=(op==15))
    return "Workshop kind is only valid for workshop links";
  const bool stock=op==1 || op==2 || op==3 || op==10 || op==13;
  const bool zone=(op>=6 && op<=9) || op==11 || op==12 || op==14 || multi || counts || locationChoices || locationDetails || staffCandidates;
  if((stock && a.kind()!=AreaKind::Stockpile) || (zone && a.kind()!=AreaKind::Zone))
    return "Area kind is not valid for this operation";
  if(op && ((op!=16 && (a.origin() || a.width()!=1 || a.height()!=1)) ||
      (a.zone_type()!=-1 && !(op==5 && create) && !counts) || a.categories() || a.changed_categories() ||
      a.barrels()!=-1 || a.bins()!=-1 || a.wheelbarrows()!=-1 || a.links_only()!=-1 ||
      a.active()!=-1 || a.owner_id()!=-2 ||
      (op!=15 && (a.link_id()!=-1 || !a.give() || a.unlink()))))
    return "Legacy area fields cannot be combined with an operation";
  if(!op) {
    if(!a.origin()) return "invalid area request";
    if(a.origin()->x()<0 || a.origin()->y()<0 || a.origin()->z()<0 ||
        a.width()<1 || a.height()<1 || a.width()>31 || a.height()>31) return "invalid area rectangle";
    if((a.categories() | a.changed_categories()) & ~0x1ffffu) return "invalid stockpile categories";
    if(a.barrels()<-1 || a.bins()<-1 || a.wheelbarrows()<-1 ||
        a.links_only()<-1 || a.links_only()>1 || a.active()<-1 || a.active()>1 ||
        a.owner_id()<-2 || a.zone_type()<-1 || a.zone_type()>255 ||
        a.id()<-1 || a.link_id()<-1 || (a.query() && a.query()->size()>128)) return "invalid area edit";
    if((inspect || update || action==ManagementAction::AreaDelete || action==ManagementAction::AreaLink) && a.id()<0)
      return "area id required";
    if(action==ManagementAction::AreaLink && (a.link_id()<0 || a.id()==a.link_id())) return "invalid area link";
  }
  const auto present=[](const auto* p){return p && p->size()!=0;};
  // Ordered like the appended schema fields, so malformed requests have stable errors.
  const std::pair<bool,const char*> foreign[]{
    {a.expected_list_revision()!=0 && !(op==1 || op==6 || op==10 || op==14 || locationChoices || staffCandidates || staffEdit), "expected_list_revision"},
    {present(a.list_key()) && op!=1 && op!=2, "list_key"},
    {present(a.row_key()) && op!=2, "row_key"},
    {a.scope()!=0 && op!=2, "scope"}, {a.value()!=0 && op!=2 && !locationAccess, "value"},
    {a.preset()!=0 && op!=3, "preset"}, {present(a.name()) && op!=4, "name"},
    {present(a.spans()) && op!=5 && !counts, "spans"}, {a.paint_mode()!=0 && op!=5, "paint_mode"},
    {a.paint_z()!=-1 && op!=5 && !counts, "paint_z"}, {a.location_id()!=-2 && op!=7 && !locationDetails && !staffCandidates, "location_id"},
    {a.location_kind()!=0 && op!=8 && !locationChoices, "location_kind"}, {a.profession()!=-1 && op!=8, "profession"},
    {a.deity_kind()!=-1 && op!=8, "deity_kind"}, {a.deity_id()!=-1 && op!=8, "deity_id"},
    {areaZoneSettingsPresent(a.zone_settings()) && op!=9, "zone_settings"},
    {a.unit_id()!=-1 && op!=11 && !staffEdit, "unit_id"}, {a.assign()!=-1 && op!=11, "assign"},
    {a.squad_id()!=-1 && op!=12, "squad_id"}, {a.squad_use()!=-1 && op!=12, "squad_use"},
    {a.organic()!=-1 && op!=13, "organic"}, {a.inorganic()!=-1 && op!=13, "inorganic"},
    {a.candidate_kind()!=0 && op!=14, "candidate_kind"}, {a.sort()!=0 && op!=14, "sort"},
    {a.sort_descending() && op!=14, "sort_descending"},
    {a.room_furniture()!=0 && op!=16, "room_furniture"},
    {a.interaction_id()!=0 && !multi, "interaction_id"},
    {a.undo_token()!=0 && op!=17, "undo_token"},
    {a.count_generation()!=0 && !counts, "count_generation"},
    {a.paint_preview()!=nullptr && !counts, "paint_preview"},
    {a.occupation_id()!=-1 && !staffCandidates && !staffEdit, "occupation_id"},
    {a.location_site_id()!=-1 && !locationDetails && !staffCandidates, "location_site_id"},
  };
  for(const auto& field:foreign) if(field.first)
    return std::string("Field ")+field.second+" does not belong to this operation";
  if(op==2 && (a.scope()<1 || a.scope()>4 || a.value()<1 || a.value()>2 ||
      present(a.row_key())!=(a.scope()==1))) return "invalid area settings edit";
  if(op==3 && (a.preset()<1 || a.preset()>19)) return "invalid area preset";
  if(locationAccess && a.value()>3)return "invalid location access mode";
  if(op==5 && (a.paint_mode()<1 || a.paint_mode()>3 || (create && a.paint_mode()!=1) ||
      !present(a.spans()))) return "invalid area paint";
  if(op==7 && a.location_id()<-1) return "area location required";
  if(op==8 && (a.location_kind()<1 || a.location_kind()>5 ||
      (a.location_kind()==4 ? a.profession()<0 : a.profession()!=-1) ||
      (a.location_kind()==2 ? (a.deity_kind()<1 || a.deity_kind()>3) : a.deity_kind()!=-1) ||
      (a.deity_kind()==2 || a.deity_kind()==3 ? a.deity_id()<0 : a.deity_id()!=-1)))
    return "invalid area location creation";
  if(op==9 && (!areaZoneSettingsPresent(a.zone_settings()) || !validAreaZoneSettings(a.zone_settings())))
    return "invalid area zone settings";
  if(op==11 && (a.unit_id()<0 || a.assign()<0 || a.assign()>1)) return "invalid area unit assignment";
  if(op==12 && (a.squad_id()<0 || a.squad_use()<0 || a.squad_use()>15)) return "invalid area squad use";
  if(op==13 && ((a.organic()==-1 && a.inorganic()==-1) || a.organic()<-1 || a.organic()>1 ||
      a.inorganic()<-1 || a.inorganic()>1)) return "invalid area toggles";
  if(op==14 && (a.candidate_kind()<1 || a.candidate_kind()>3 || a.sort()>3))
    return "invalid area candidate selector";
  if(multi) {
    if(!a.interaction_id() || a.interaction_id()>INT64_MAX || a.undo_token()>INT64_MAX ||
        (op==17 && !a.undo_token()))return "invalid room interaction identity";
    if(a.id()!=-1 || a.expected_revision() || present(a.query()) || a.cursor())
      return "unrelated area fields in room operation";
    if(op==16 && (!a.origin() || a.origin()->x()<0 || a.origin()->y()<0 || a.origin()->z()<0 ||
        a.origin()->x()>32767 || a.origin()->y()>32767 || a.origin()->z()>32767 ||
        !a.width() || !a.height() || uint64_t(a.origin()->x())+a.width()>32768 ||
        uint64_t(a.origin()->y())+a.height()>32768 || a.room_furniture()<1 || a.room_furniture()>4))
      return "invalid room selection";
  }
  if(a.id()<-1 || a.unit_id()<-1 || a.squad_id()<-1 || a.deity_id()<-1 ||
      a.location_id()<-2 || a.paint_z()<-1) return "invalid area identity";
  if(counts) {
    if(!a.count_generation() || a.count_generation()>INT64_MAX || a.paint_z()<0 ||
        a.zone_type()<0 || a.zone_type()>255 || a.id()!=-1 || a.expected_revision() ||
        present(a.query()) || a.cursor())return "invalid paint count identity";
    if(const auto* p=a.paint_preview()) {
      if(p->x()<0 || p->y()<0 || !p->width() || !p->height() || p->width()>256 || p->height()>256 ||
          uint32_t(p->width())*p->height()>32768 || uint32_t(p->x())+p->width()>32768 ||
          uint32_t(p->y())+p->height()>32768)return "invalid paint preview";
    }
  }
  if(locationChoices && ((a.location_kind()!=2 && a.location_kind()!=4) || a.id()!=-1 || a.expected_revision() ||
      present(a.query()) || a.cursor()%128 || (a.cursor() && !a.expected_list_revision())))return "invalid location catalog request";
  if(staffCandidates && (a.location_site_id()<0 || a.location_id()<0 || a.occupation_id()<0 ||
      a.id()!=-1 || a.expected_revision() || present(a.query()) || a.cursor()%128 ||
      (a.cursor() && !a.expected_list_revision())))return "invalid staff candidates request";
  if(staffEdit && (a.occupation_id()<0 || !a.expected_list_revision()))return "invalid staff edit request";
  if(locationDetails && (a.location_site_id()<0 || a.location_id()<0 || a.id()!=-1 || ((locationOpen || locationAccess || staffEdit)?!a.expected_revision():a.expected_revision()!=0) ||
      present(a.query()) || a.cursor()))return "invalid location details request";
  if(op && !multi && !counts && !locationChoices && !locationDetails && !staffCandidates && !(op==5 && create) && a.id()<0) return "area id required";
  if(op==5 && create && a.paint_z()<0) return "area paint z required";
  if(op==15 && (a.link_id()<0 || a.link_id()==a.id())) return "invalid area link";
  if(op==5 && create && (a.zone_type()<-1 || a.zone_type()>255)) return "invalid area edit";
  if((a.list_key() && a.list_key()->size()>64) || (a.row_key() && a.row_key()->size()>64))
    return "area key too long";
  if(a.name() && a.name()->size()>512) return "area name too long";
  if(a.query() && a.query()->size()>128) return "invalid area edit";
  if(a.expected_revision()>INT64_MAX || a.expected_list_revision()>INT64_MAX) return "invalid area revision";
  if(present(a.spans())) {
    if(a.spans()->size()>32768) return "too many area spans";
    uint32_t total=0;
    for(const auto* span:*a.spans()) {
      if(span->x()<0 || span->y()<0 || !span->length() ||
          uint32_t(span->x())+span->length()-1>32767) return "invalid area span";
      total+=span->length();
    }
    if(total>32768) return "too many painted area tiles";
    if(counts) {
      int32_t lastY=-1,lastEnd=-1,left=32768,top=32768,right=-1,bottom=-1;
      for(const auto* s:*a.spans()) {
        if(s->y()<lastY || (s->y()==lastY && s->x()<lastEnd))return "noncanonical paint count spans";
        lastY=s->y();lastEnd=int32_t(s->x())+s->length();
        left=std::min(left,int32_t(s->x()));top=std::min(top,int32_t(s->y()));
        right=std::max(right,lastEnd-1);bottom=std::max(bottom,lastY);
      }
      if(right-left+1>256 || bottom-top+1>256 || int64_t(right-left+1)*(bottom-top+1)>32768)
        return "paint count footprint too large";
    }
  }
  if(!multi && (update || action==ManagementAction::AreaDelete || action==ManagementAction::AreaLink) && !a.expected_revision())
    return "area revision required";
  return std::nullopt;
}
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
  return action >= ManagementAction::Catalog && action <= ManagementAction::DismissAlert &&
      action != ManagementAction::Alert && action != ManagementAction::Selection &&
      !(action >= ManagementAction::TradeExchangeOpen && action <= ManagementAction::TradeExchangeClose) &&
      !(action >= ManagementAction::StocksOpen && action <= ManagementAction::StocksClose) &&
      !(action >= ManagementAction::AppointmentsOpen && action <= ManagementAction::AppointmentsBack) &&
      !(action >= ManagementAction::KitchenOpen && action <= ManagementAction::KitchenClose);
}
inline std::optional<std::string> validateConstructionRequest(const ConstructionRequest& r) {
  if (r.schema_version() != kManagementVersion) return "management version mismatch";
  if (r.cancel_removal() && r.action()!=ManagementAction::Remove) return "cancellation requires building removal intent";
  const bool connectedTrack=(r.action()==ManagementAction::Preview || r.action()==ManagementAction::Place ||
      r.action()==ManagementAction::ConstructionMaterials) && r.definition() && r.definition()->str()=="Construction:Track";
  if (const auto* track=r.connected_track()) {
    const auto* end=track->destination();
    if (!connectedTrack || !r.origin() || !end || end->x()<0 || end->y()<0 || end->z()<0 ||
        r.width()!=1 || r.height()!=1 || r.depth()!=1 || r.direction()!=0 || r.retracting())
      return "invalid connected track intent";
  } else if (connectedTrack) return "connected track destination required";
  const bool terrainMaterials=(r.action()==ManagementAction::Preview || r.action()==ManagementAction::Place ||
      r.action()==ManagementAction::ConstructionMaterials) && r.definition() &&
      (r.definition()->str()=="Construction:Wall" || r.definition()->str()=="Construction:Floor" ||
       r.definition()->str()=="Construction:Ramp" || r.definition()->str()=="Construction:Fortification" ||
       r.definition()->str()=="Construction:Stairs" || r.definition()->str()=="Construction:ReinforcedWall");
  if (const auto* anchor=r.material_anchor()) {
    const auto* origin=r.origin();
    const auto corner=[](int32_t v,int32_t low,uint16_t extent) {
      return v>=0 && (int64_t(v)==low || int64_t(v)==int64_t(low)+extent-1);
    };
    if (!terrainMaterials || !origin || !corner(anchor->x(),origin->x(),r.width()) ||
        !corner(anchor->y(),origin->y(),r.height()) || !corner(anchor->z(),origin->z(),r.depth()))
      return "invalid construction material anchor";
  }
  const bool trackPlacement=(r.action()==ManagementAction::Preview || r.action()==ManagementAction::Place) &&
      r.definition() && r.definition()->str()=="Trap:TrackStop";
  if (const auto* t=r.track_stop()) {
    if (!trackPlacement || t->dump_direction()>4 ||
        (t->friction()!=10 && t->friction()!=50 && t->friction()!=500 && t->friction()!=10000 && t->friction()!=50000))
      return "invalid track stop intent";
  } else if (trackPlacement) return "track stop options required";
  const bool pressurePlacement=(r.action()==ManagementAction::Preview || r.action()==ManagementAction::Place) &&
      r.definition() && r.definition()->str()=="Trap:PressurePlate";
  if (const auto* p=r.pressure_plate()) {
    const auto weight=[](int32_t v){return v==1 || (v>=50 && v<=2000 && v%50==0);};
    if (!pressurePlacement || p->unit_min()<1000 || p->unit_min()>200000 || p->unit_min()%1000 ||
        p->unit_max()<p->unit_min() || p->unit_max()>200999 ||
        (p->unit_max()!=200000 && p->unit_max()%1000!=999) ||
        p->water_min()<0 || p->water_max()>7 || p->water_min()>p->water_max() ||
        p->magma_min()<0 || p->magma_max()>7 || p->magma_min()>p->magma_max() ||
        !weight(p->track_min()) || !weight(p->track_max()) || p->track_min()>p->track_max())
      return "invalid pressure plate intent";
  } else if (pressurePlacement) return "pressure plate options required";
  if (r.roller_speed() &&
      ((r.action()!=ManagementAction::Preview && r.action()!=ManagementAction::Place) ||
       !r.definition() || r.definition()->str()!="Rollers" ||
       r.roller_speed()>50000 || r.roller_speed()%10000)) return "invalid roller speed intent";
  if (!r.client_id() || !r.seq()) return "client and sequence required";
  if (r.action() < ManagementAction::Catalog || r.action() > ManagementAction::DismissAlert)
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
    if (!a) return "invalid area request";
    if(auto error=validateAreaOperation(r.action(),*a)) return error;
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
  if((r.action()>=ManagementAction::CitizenList && r.action()<=ManagementAction::WorkDetailMode) ||
     (r.action()>=ManagementAction::WorkDetailCreate && r.action()<=ManagementAction::CitizenWorkScope)) {
    const auto* c=r.citizen();
    if(!c || c->unit_id() < -1 || c->detail_index() < -1 || c->detail_index()>127 || c->expected_revision()>INT64_MAX ||
       c->member() < -1 || c->member()>1 || c->mode() < -1 || c->mode()>3 || (c->query() && c->query()->size()>128)) return "invalid citizen request";
    if((r.action()==ManagementAction::CitizenInspect || r.action()==ManagementAction::WorkDetailMembership) && c->unit_id()<0) return "citizen id required";
    if(((r.action()>=ManagementAction::WorkDetailInspect && r.action()<=ManagementAction::WorkDetailMode) ||
        r.action()==ManagementAction::WorkDetailDelete || r.action()==ManagementAction::WorkDetailEdit) && c->detail_index()<0) return "work detail index required";
    if(r.action()>=ManagementAction::WorkDetailMembership && !c->expected_revision()) return "citizen receipt required";
    if(r.action()>=ManagementAction::WorkDetailCreate && (c->cursor() || (c->query() && c->query()->size()))) return "unexpected citizen search";
    if(r.action()==ManagementAction::WorkDetailMembership && (c->member()<0 || c->mode()!=-1)) return "membership edit requires only member field";
    if(r.action()==ManagementAction::WorkDetailMode && (c->mode()<0 || c->member()!=-1)) return "mode edit requires only mode field";
    if(r.action()!=ManagementAction::WorkDetailMembership && r.action()!=ManagementAction::WorkDetailMode &&
       (c->member()!=-1 || c->mode()!=-1)) return "unexpected citizen edit fields";
    const bool hasName=c->name() && c->name()->size();
    const bool hasLabors=c->labors() && c->labors()->size();
    if(c->edit() && r.action()!=ManagementAction::WorkDetailEdit) return "unexpected work detail edit";
    if(r.action()==ManagementAction::WorkDetailCreate && (c->detail_index()!=-1 || c->unit_id()!=-1))
      return "unexpected new work detail identity";
    if(r.action()==ManagementAction::WorkDetailEdit && (c->edit()<1 || c->edit()>3))
      return "invalid work detail edit";
    if(hasName && (r.action()!=ManagementAction::WorkDetailEdit || c->edit()!=1))
      return "unexpected work detail name";
    if(c->name() && c->name()->size()>160) return "work detail name too long";
    if(hasLabors && (r.action()!=ManagementAction::WorkDetailEdit || c->edit()!=2))
      return "unexpected work detail labors";
    if(c->labors()) {
      if(c->labors()->size()>94) return "too many work detail labors";
      std::set<int16_t> labors;
      for(auto labor:*c->labors()) if(labor<0 || labor>93 || !labors.insert(labor).second)
        return "invalid work detail labor";
    }
    if(r.action()==ManagementAction::CitizenWorkScope) {
      if(c->unit_id()<0 || c->detail_index()!=-1 || c->only_assigned()<0 || c->only_assigned()>1)
        return "invalid citizen work scope";
    } else if(c->only_assigned()!=-1) return "unexpected citizen work scope";
    if(r.action()==ManagementAction::WorkDetailList && c->cursor()>0 && !c->expected_list_revision())
      return "work detail list revision required";
    if(c->expected_list_revision()>INT64_MAX) return "invalid work detail list revision";
    if(c->expected_list_revision() && r.action()!=ManagementAction::WorkDetailList)
      return "unexpected work detail list revision";
  } else if(r.citizen()) return "unexpected citizen payload";
  if(r.action()==ManagementAction::PrepareAlertDismissal || r.action()==ManagementAction::DismissAlert) {
    const auto* p=r.report();
    if(!p || p->view()!=ReportView::Flat || p->id()!=-1 || p->before_id()!=-1 || p->after_id()!=-1 ||
       p->tab()!=ReportTab::Unknown || p->unit_id()!=-1 || p->unit_category()!=-1 || p->cursor() ||
       p->from_end() || p->refresh() || !p->announcements_only() || p->notification_category()!=-1 || p->alert_button() ||
       (p->query() && p->query()->size()) || (p->ids() && p->ids()->size()) || (p->units() && p->units()->size()) ||
       p->expected_list_revision()>INT64_MAX ||
       (r.action()==ManagementAction::PrepareAlertDismissal ? p->expected_list_revision()!=0 : p->expected_list_revision()==0))
      return "invalid red alert dismissal request";
  } else if(r.action()>=ManagementAction::ReportList && r.action()<=ManagementAction::ReportInspect) {
    const auto* p=r.report();
    if(!p || p->id() < -1 || p->before_id() < -1 || p->after_id() < -1 || (p->query() && p->query()->size()>128))return "invalid report request";
    if(p->view()>ReportView::Group)return "Unsupported report view";
    const bool groupOwner=p->notification_category()>=0 || p->alert_button();
    if(p->notification_category()< -1 || p->notification_category()>36 || (p->alert_button() && p->notification_category()!=-1) ||
       (groupOwner && p->view()!=ReportView::Group && p->view()!=ReportView::Text))return "invalid alert group selector";
    if(p->refresh() && (p->view()!=ReportView::UnitLog || !p->expected_list_revision() || p->before_id()!=-1 || p->from_end()))return "invalid unit log refresh";
    if(p->unit_id()< -1 || p->unit_category()< -1 || p->unit_category()>2 || p->expected_list_revision()>INT64_MAX)return "invalid report unit request";
    if(p->view()<ReportView::UnitList && (p->unit_id()!=-1 || p->unit_category()!=-1 || p->cursor() || (p->view()==ReportView::Flat && p->expected_list_revision())))return "unexpected report unit fields";
    const size_t entryIds=p->ids()?p->ids()->size():0,entryUnits=p->units()?p->units()->size():0;
    if(entryIds>64 || entryUnits>64)return "Too many report entries";
    if(p->view()!=ReportView::Entries && (entryIds || entryUnits))return "unexpected report entries";
    if(p->ids())for(auto id:*p->ids())if(id<0)return "invalid report entry identity";
    if(p->units())for(const auto* u:*p->units())if(!u || u->unit_id()<0 || u->category()>UnitReportCategory::Hunting)return "invalid unit report reference";
    if(p->view()==ReportView::Flat) {
      if(p->tab()!=ReportTab::Unknown || p->after_id()!=-1 || p->from_end())return "unexpected report tab fields";
      if(r.action()==ManagementAction::ReportInspect && (p->id()<0 || p->before_id()!=-1 || (p->query() && p->query()->size())))return "invalid report inspection";
      if(r.action()==ManagementAction::ReportList && p->id()!=-1)return "unexpected report identity";
    } else if(p->view()==ReportView::Group) {
      if(r.action()!=ManagementAction::ReportList || !groupOwner || p->id()!=-1 || p->before_id()!=-1 || p->after_id()!=-1 ||
         p->from_end() || p->tab()!=ReportTab::Unknown || p->unit_id()!=-1 || p->unit_category()!=-1 ||
         p->cursor()>65536 || (p->cursor() && !p->expected_list_revision()) ||
         (p->query() && p->query()->size()) || !p->announcements_only())return "invalid alert group request";
    } else if(p->view()==ReportView::Text) {
      if(groupOwner && (p->tab()!=ReportTab::Unknown || p->unit_id()!=-1 || p->unit_category()!=-1 || !p->expected_list_revision()))return "invalid alert text selector";
      if(r.action()!=ManagementAction::ReportInspect || p->id()<0 || p->before_id()!=-1 || p->after_id()!=-1 ||
         p->from_end() || p->tab()>ReportTab::Curses || (p->tab()!=ReportTab::Unknown && !p->expected_list_revision()) ||
         (p->unit_id()<0 ? p->unit_category()!=-1 : (p->unit_category()<0 || p->tab()!=ReportTab::Unknown || !p->expected_list_revision())) ||
         p->cursor()>33554432 || (p->cursor() && !p->expected_list_revision()) ||
         (p->query() && p->query()->size()) || !p->announcements_only())return "invalid report text request";
    } else if(p->view()==ReportView::Entries) {
      if(r.action()!=ManagementAction::ReportInspect)return "Report view is not valid for this action";
      if(!entryIds && !entryUnits)return "No report entries requested";
      if(p->id()!=-1 || p->before_id()!=-1 || p->after_id()!=-1 || p->from_end() || p->tab()!=ReportTab::Unknown ||
         p->unit_id()!=-1 || p->unit_category()!=-1 || p->cursor() || p->expected_list_revision() ||
         (p->query() && p->query()->size()) || !p->announcements_only())return "unexpected report entries fields";
    } else {
      if(r.action()!=ManagementAction::ReportList)return "Report view is not valid for this action";
      if(p->id()!=-1 || (p->query() && p->query()->size()) || !p->announcements_only())return "unexpected flat report fields";
      if(p->view()==ReportView::Tab) {
        if(p->tab()<ReportTab::All || p->tab()>ReportTab::Curses)return "Unsupported report tab";
      } else {
        if(p->tab()!=ReportTab::Unknown || p->unit_category()<0)return "invalid report unit selector";
        if(p->view()==ReportView::UnitList && (p->after_id()!=-1 || p->before_id()!=-1 || p->from_end()))return "unexpected unit list cursor";
        if(p->view()==ReportView::UnitLog && (p->unit_id()<0 || p->cursor()))return "invalid unit log request";
      }
      if(int(p->after_id()>=0)+int(p->before_id()>=0)+int(p->from_end())>1)return "Only one report cursor may be set";
    }
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
  if (r.width() < 1 || r.width() > 31 || r.height() < 1 || r.height() > 31 || r.direction() > 7)
    return "invalid dimensions or orientation";
  if (r.action() == ManagementAction::Preview || r.action() == ManagementAction::Place) {
    if (!r.definition() || !r.definition()->size() || !r.origin())
      return "definition and origin required";
  }
  if ((r.action() == ManagementAction::Preview || r.action() == ManagementAction::Place) &&
      r.definition() && r.definition()->str() == "Construction:Stairs" && r.depth() == 1)
    return "Must span multiple elevations";
  if (r.depth() < 1 || r.depth() > 256 ||
      uint64_t(r.width()) * r.height() * r.depth() > 1024)
    return "invalid construction depth or volume";
  if (r.expected_list_revision() > INT64_MAX) return "invalid construction list revision";
  if (r.retracting() && r.direction() != 0) return "invalid retracting orientation";
  if (r.action() != ManagementAction::Preview && r.action() != ManagementAction::Place &&
      ((r.depth() != 1 && !(terrainMaterials && r.action()==ManagementAction::ConstructionMaterials &&
         r.definition()->str()=="Construction:Stairs")) || r.retracting())) return "unexpected construction placement fields";
  if (r.filter() < -1 || r.filter() > 7) return "invalid construction filter";
  if (r.filter() >= 0 && r.action() != ManagementAction::ConstructionMaterials)
    return "unexpected construction filter";
  if (r.action() == ManagementAction::ConstructionMaterials &&
      (!r.definition() || !r.definition()->size() || r.filter() < 0 || !r.origin()))
    return "definition, filter and origin required";
  if (r.expected_list_revision() && r.action() != ManagementAction::Catalog &&
      r.action() != ManagementAction::Place && r.action() != ManagementAction::ConstructionMaterials)
    return "unexpected construction list revision";
  if (r.selections() && r.selections()->size()) {
    if (r.selections()->size() > (connectedTrack ? kConnectedTrackMaxTiles : 16)) return "too many construction selections";
    if (r.action() != ManagementAction::Place) return "unexpected construction selections";
    std::set<std::tuple<int16_t,int16_t,int16_t,int16_t,int32_t,int32_t>> keys;
    std::set<int32_t> selectedIds;
    size_t selectedCount=0;
    for (const auto* v : *r.selections()) {
      if (v && v->expected_list_revision() < -1) return "invalid construction selection list revision";
      if (!v || v->filter() < 0 || v->filter() > 7 || !v->count() ||
          v->item_type() < -1 || v->item_subtype() < -1 || v->mat_type() < -1 || v->mat_index() < -1 ||
          !keys.emplace(v->filter(),v->item_type(),v->item_subtype(),v->mat_type(),v->mat_index(),v->individual_id()).second)
        return "invalid or duplicate construction selection";
      if (v->individual_id() < -1 || (v->individual_id() >= 0 &&
          (v->count()!=1 || !v->item_ids() || v->item_ids()->size()!=1 || v->item_ids()->Get(0)!=v->individual_id())))
        return "invalid individual construction selection";
      if (const auto* ids=v->item_ids()) {
        if (v->expected_list_revision()<=0) return "exact construction selection requires snapshot revision";
        if (ids->size()!=v->count()) return "exact construction selection count mismatch";
        selectedCount+=ids->size();
        if (selectedCount>16384) return "too many exact construction items";
        for (int32_t id:*ids)
          if(id<0 || !selectedIds.insert(id).second) return "invalid or duplicate exact construction item";
      }
    }
  }
  if(r.action()==ManagementAction::Place && r.definition() &&
      (r.definition()->str()=="Weapon" || r.definition()->str()=="Trap:WeaponTrap")) {
    uint64_t count=0;
    if(r.selections())for(const auto* v:*r.selections())
      if(v->filter()==(r.definition()->str()=="Weapon" ? 0 : 1))count+=v->count();
    if(count<1 || count>10)return "Weapon count must be between 1 and 10";
  }
  if (r.origin() && (r.origin()->x() < 0 || r.origin()->y() < 0 || r.origin()->z() < 0))
    return "negative origin";
  if (r.action() == ManagementAction::Place && r.items() && r.items()->size())
    return "selected inputs are retired; use selections";
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
  if (s.action() < ManagementAction::Catalog || s.action() > ManagementAction::DismissAlert ||
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
  // At most 1024 tiles, eight inputs, each with an int32 quantity. The
  // legacy uint16 wire total is an additional, tighter representability cap.
  constexpr uint64_t constructionRequiredCap = uint64_t(1024) * 8 * INT32_MAX;
  if ((s.required() > (s.construction() ? constructionRequiredCap : 64)) || s.jobs() > 1024 || s.build_stage() < -1 || s.max_stage() < -1)
    return "invalid construction state";
  if (s.max_stage() >= 0 && s.build_stage() > s.max_stage()) return "invalid build stage";
  auto constructionTextOk = [](const flatbuffers::String* v, size_t cap) {
    return !v || v->size() <= cap;
  };
  auto constructionTokenOk = [](const flatbuffers::String* v,size_t cap) {
    if(!v)return true;
    if(v->size()>cap)return false;
    for(size_t i=0;i<v->size();) {
      const uint8_t lead=uint8_t(v->Get(i++));
      if(lead<128) { if(lead<32 || lead==127)return false;continue; }
      const unsigned count=lead>=0xc2 && lead<=0xdf?1:lead>=0xe0 && lead<=0xef?2:lead>=0xf0 && lead<=0xf4?3:0;
      if(!count || i+count>v->size())return false;
      uint32_t point=lead & (count==1?0x1f:count==2?0x0f:0x07);
      for(unsigned j=0;j<count;++j) {
        const uint8_t next=uint8_t(v->Get(i++));if((next&0xc0)!=0x80)return false;
        point=(point<<6)|(next&0x3f);
      }
      if(point<(count==1?0x80u:count==2?0x800u:0x10000u) || point>0x10ffff || (point>=0xd800 && point<=0xdfff))return false;
    }
    return true;
  };
  auto constructionFiltersOk = [&](const auto* values) {
    if (!values) return true;
    if (values->size() > 8) return false;
    std::set<int16_t> indices;
    for (const auto* v : *values)
      if (!v || v->index() < 0 || v->index() > 7 || !indices.insert(v->index()).second ||
          v->item_type() < -1 || v->item_subtype() < -1 || v->quantity() < -1 ||
          !constructionTextOk(v->caption(),64) || !constructionTextOk(v->requirement(),64)) return false;
    return true;
  };
  auto constructionFootprintOk = [](const ConstructionFootprint* v) {
    return !v || (v->direction() <= 7 && v->width() >= 1 && v->width() <= 31 && v->height() >= 1 && v->height() <= 31 &&
        v->center_x() >= -1 && v->center_x() < v->width() && v->center_y() >= -1 && v->center_y() < v->height());
  };
  if (const auto* c = s.construction()) {
    if(c->outcome()>ConstructionOutcome::Unknown || c->updated()>16384 || c->failed_index() < -1 ||
       c->failed_index()==0 || c->failed_index()>16384) return "invalid construction outcome";
    if(c->outcome()==ConstructionOutcome::None) {
      if(c->updated() || c->failed_index()!=-1)return "unexpected construction outcome details";
    } else {
      if(s.action()!=ManagementAction::Place)return "unexpected construction outcome";
      if(c->outcome()==ConstructionOutcome::Complete) {
        if(s.status()!=ManagementStatus::Ok || c->failed_index()!=-1)return "invalid completed construction outcome";
      } else if(s.status()!=ManagementStatus::Rejected)return "invalid unsuccessful construction outcome";
      if(c->outcome()==ConstructionOutcome::Rejected && (c->placed() || c->updated()))return "rejected construction has confirmed effects";
      if(c->outcome()==ConstructionOutcome::Partial && !(c->placed() || c->updated()))return "partial construction has no confirmed effects";
    }
    if(const auto* track=c->connected_track()) {
      if(s.action()!=ManagementAction::Preview || !c->building_key() || c->building_key()->str()!="Construction:Track" ||
         track->status()>ConnectedTrackStatus::PayloadLimit) return "invalid connected track preview";
      const auto count=track->path()?track->path()->size():0;
      if(count>kConnectedTrackMaxTiles || (track->status()==ConnectedTrackStatus::Found ? count<2 : count!=0))
        return "invalid connected track path size";
      std::set<std::tuple<int32_t,int32_t,int32_t>> seen;
      const TilePos* prior=nullptr;
      if(track->path())for(const auto* p:*track->path()) {
        if(p->x()<0 || p->y()<0 || p->z()<0 || !seen.emplace(p->x(),p->y(),p->z()).second) return "invalid connected track tile";
        if(prior) {
          const auto dx=int64_t(p->x())-prior->x(),dy=int64_t(p->y())-prior->y(),dz=int64_t(p->z())-prior->z();
          if(std::abs(dx)+std::abs(dy)!=1 || std::abs(dz)>1) return "invalid connected track step";
        }
        prior=p;
      }
    }
    if (const auto* rows=c->pressure_creatures(); rows && rows->size()) {
      if(s.action()!=ManagementAction::Catalog || rows->size()!=200) return "invalid pressure creature examples";
      int32_t expected=1000;
      for(const auto* row:*rows) {
        if(!row || row->size()!=expected || row->race_id() < -1 || !constructionTextOk(row->name(),128) ||
           (row->race_id()==-1 && row->name() && row->name()->size())) return "invalid pressure creature examples";
        expected+=1000;
      }
    }
    if (c->filter() < -1 || c->filter() > 7 || c->first_building() < -1 || c->build_phase() > 3 ||
        c->build_done() > c->build_total() || c->list_revision() > INT64_MAX ||
        uint64_t(c->placed()) + c->skipped() > 1024 ||
        !constructionTextOk(c->building_key(),64) || !constructionFiltersOk(c->filters()) ||
        !constructionFootprintOk(c->footprint())) return "invalid construction result";
    if (c->valid_mask()) {
      if (c->valid_mask()->size() > 1024) return "construction mask too large";
      for (auto v : *c->valid_mask()) if (v > 1) return "invalid construction mask";
    }
    if (c->pieces()) {
      if (c->pieces()->size() > 1024) return "construction pieces too large";
      for (auto v : *c->pieces()) if (v > 3) return "invalid construction piece";
    }
    if (c->materials()) {
      if (c->materials()->size() > 128) return "construction materials page too large";
      std::set<std::tuple<int16_t,int16_t,int16_t,int32_t,int32_t>> materialKeys;
      size_t candidateCount=0;std::set<int32_t> candidateIds;
      for (const auto* v : *c->materials()) {
        if (!v || v->item_type() < -1 || v->item_subtype() < -1 || v->mat_type() < -1 ||
            v->mat_index() < -1 || !v->count() || !constructionTextOk(v->name(),128) ||
            !constructionTextOk(v->caption(),64) || !constructionTextOk(v->last_name(),128) ||
            !materialKeys.emplace(v->item_type(),v->item_subtype(),v->mat_type(),v->mat_index(),v->individual_id()).second) return "invalid construction material";
        if (v->individual_id() < -1 || (v->individual_id() >= 0 &&
            (v->count()!=1 || !v->candidates() || v->candidates()->size()!=1 || !v->candidates()->Get(0) || v->candidates()->Get(0)->id()!=v->individual_id())))
          return "invalid individual construction material";
        if (v->candidates()) {
          candidateCount+=v->candidates()->size();
          if(candidateCount>16384 || v->candidates()->size()!=v->count()) return "incomplete or excessive construction candidates";
          std::optional<std::pair<uint32_t,int32_t>> previous;
          for(const auto* item:*v->candidates()) {
            if(!item || item->id()<0 || !item->name() || !item->name()->size() ||
                !constructionTextOk(item->name(),128) || !candidateIds.insert(item->id()).second)
              return "invalid construction candidate";
            if(const auto* a=item->appearance()) {
              if(!a->material_token() || !a->material_token()->size() ||
                 !constructionTokenOk(a->material_token(),256) || !constructionTokenOk(a->subtype_raw(),128) ||
                 !constructionTokenOk(a->color_token(),128) || !a->stack() || a->stack()>INT32_MAX ||
                 (a->flags() & ~uint8_t(96)) || v->item_type()<0)
                return "invalid construction item appearance";
            }
            const auto key=std::pair{item->distance(),item->id()};
            if(previous && key<=*previous)return "unordered construction candidates";
            previous=key;
          }
        }
      }
    }
  }
  if (s.catalog()) {
    if (s.catalog()->size() > 128) return "catalog too large";
    std::set<std::string> keys;
    for (auto* d : *s.catalog()) {
      if (!d || !d->key() || !d->key()->size() || d->key()->size() > 64 ||
          !keys.insert(d->key()->str()).second || d->width() < 1 || d->width() > 31 ||
          d->height() < 1 || d->height() > 31 || !constructionTextOk(d->name(),128) ||
          !constructionTextOk(d->reason(),128) || !constructionTextOk(d->native_name(),128) ||
          !constructionTextOk(d->family(),64) || !constructionTextOk(d->subtype_key(),64) ||
          !constructionTextOk(d->custom_code(),64) || d->area_mode() > 4 ||
          d->max_width() > 31 || d->max_height() > 31 || d->max_depth() > 256 ||
          !constructionFiltersOk(d->filters())) return "invalid definition";
      if (d->footprints()) {
        if (d->footprints()->size() > 8) return "too many construction footprints";
        std::set<uint8_t> directions;
        for (const auto* v : *d->footprints())
          if (!v || !constructionFootprintOk(v) || !directions.insert(v->direction()).second)
            return "invalid or duplicate construction footprint";
      }
    }
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
    const auto count=[](const auto* v)->size_t{return v ? v->size() : 0;};
    const auto textSize=[](const flatbuffers::String* v)->size_t{return v ? v->size() : 0;};
    if(a->operation()>AreaOperation::LocationStaffEdit || a->area_id()<-1 ||
        textSize(a->list_key())>64 || textSize(a->query())>128 ||
        a->candidate_kind()>3 || a->sort()>3 || a->list_revision()>INT64_MAX ||
        a->build_phase()>3 || a->build_done()>a->build_total() || a->captured_tick()<-1)
      return "invalid area response header";
    const bool multi=a->operation()>=AreaOperation::MultiCreate && a->operation()<=AreaOperation::MultiFinish;
    const bool counts=a->operation()==AreaOperation::PaintCounts;
    const bool locationChoices=a->operation()==AreaOperation::LocationChoices;
    const bool staffCandidates=a->operation()==AreaOperation::LocationStaffCandidates;
    const bool locationOpen=a->operation()==AreaOperation::LocationOpen;
    const bool locationAccess=a->operation()==AreaOperation::LocationAccess;
    const bool staffEdit=a->operation()==AreaOperation::LocationStaffEdit;
    const bool locationEdit=locationAccess || staffEdit;
    const bool locationDetails=a->operation()==AreaOperation::LocationDetails || locationOpen || locationEdit;
    if(a->location_staff_candidates() && !staffCandidates)return "staff candidates without operation";
    if(staffCandidates) {
      if(s.action()!=ManagementAction::AreaInspect)return "staff candidates action mismatch";
      if(a->area_id()!=-1 || a->next_cursor() || a->truncated() || count(a->areas()) || count(a->choices()) ||
          count(a->settings()) || count(a->locations()) || count(a->candidates()) || count(a->links()) ||
          textSize(a->list_key()) || textSize(a->query()) || a->candidate_kind() || a->sort() ||
          a->sort_descending() || a->list_revision() || a->build_phase() || a->build_done() || a->build_total() || a->omitted())
        return "mixed staff candidates reply";
      if((s.status()==ManagementStatus::Ok)!=(a->location_staff_candidates()!=nullptr))return "invalid staff candidates presence";
      if(a->location_staff_candidates())if(auto error=validateLocationStaffCandidates(*a->location_staff_candidates()))return error;
    }
    if(!locationOpen && a->location_entry_outcome()!=LocationEntryOutcome::None)return "entry outcome without entry operation";
    if(!locationEdit && a->location_edit_outcome()!=LocationEditOutcome::None)return "edit outcome without edit operation";
    if(a->location_details() && !locationDetails)return "location details without operation";
    if(locationDetails) {
      if(s.action()!=((locationOpen || locationEdit)?ManagementAction::AreaUpdate:ManagementAction::AreaInspect))return "location details action mismatch";
      if(locationEdit && (a->location_edit_outcome()==LocationEditOutcome::None || a->location_edit_outcome()>LocationEditOutcome::Unknown ||
          ((a->location_edit_outcome()==LocationEditOutcome::Completed)!=(s.status()==ManagementStatus::Ok))))return "invalid location edit outcome";
      if(locationOpen && (a->location_entry_outcome()==LocationEntryOutcome::None || a->location_entry_outcome()>LocationEntryOutcome::Unknown ||
          ((a->location_entry_outcome()==LocationEntryOutcome::Completed)!=(s.status()==ManagementStatus::Ok))))return "invalid location entry outcome";
      if(a->area_id()!=-1 || a->next_cursor() || a->truncated() || count(a->areas()) || count(a->choices()) ||
          count(a->settings()) || count(a->locations()) || count(a->candidates()) || count(a->links()) ||
          textSize(a->list_key()) || textSize(a->query()) || a->candidate_kind() || a->sort() ||
          a->sort_descending() || a->list_revision() || a->build_phase() || a->build_done() || a->build_total() || a->omitted())
        return "mixed location details reply";
      if((s.status()==ManagementStatus::Ok)!=(a->location_details()!=nullptr))return "invalid location details presence";
      if(a->location_details())if(auto error=validateLocationDetails(*a->location_details()))return error;
    }
    if(a->location_catalog() && !locationChoices)return "location catalog without operation";
    if(locationChoices) {
      if(a->area_id()!=-1 || a->next_cursor() || a->truncated() || count(a->areas()) || count(a->choices()) ||
          count(a->settings()) || count(a->locations()) || count(a->candidates()) || count(a->links()) ||
          textSize(a->list_key()) || textSize(a->query()) || a->candidate_kind() || a->sort() ||
          a->sort_descending() || a->list_revision() || a->build_phase() || a->build_done() || a->build_total() || a->omitted())
        return "mixed location catalog reply";
      if(s.status()==ManagementStatus::Ok && !a->location_catalog())return "missing location catalog";
      if(s.status()!=ManagementStatus::Ok && a->location_catalog())return "catalog on failed read";
      if(a->location_catalog())if(auto error=validateLocationCatalog(*a->location_catalog()))return error;
    }
    if(!counts && (a->count_generation() || a->painted_count()!=-1 || a->preview_count()!=-1))
      return "paint counts without count operation";
    if(counts && (!a->count_generation() || a->count_generation()>INT64_MAX ||
        a->painted_count()<-1 || a->painted_count()>32768 || a->preview_count()<-1 || a->preview_count()>32768 ||
        a->area_id()!=-1 || a->next_cursor() || a->truncated() || count(a->areas()) || count(a->choices()) ||
        count(a->settings()) || count(a->locations()) || count(a->candidates()) || count(a->links()) ||
        textSize(a->list_key()) || textSize(a->query()) || a->candidate_kind() || a->sort() ||
        a->sort_descending() || a->list_revision() || a->build_phase() || a->build_done() ||
        a->build_total() || a->omitted()))return "invalid paint count response";
    const bool roomFields=a->interaction_id() || a->undo_token() || a->room_outcome()!=AreaRoomOutcome::None ||
        a->rooms_created() || a->rooms_in_use() || a->rooms_unenclosed() || a->rooms_removed() || a->rooms_dormitories();
    if(!multi && roomFields)return "room result without room operation";
    if(multi) {
      if(!a->interaction_id() || a->interaction_id()>INT64_MAX || a->undo_token()>INT64_MAX ||
          a->room_outcome()==AreaRoomOutcome::None || a->room_outcome()>AreaRoomOutcome::Unknown ||
          a->area_id()!=-1 || a->next_cursor() || a->truncated() || count(a->areas()) || count(a->choices()) ||
          count(a->settings()) || count(a->locations()) || count(a->candidates()) || count(a->links()) ||
          textSize(a->list_key()) || textSize(a->query()) || a->candidate_kind() || a->sort() ||
          a->sort_descending() || a->list_revision() || a->build_phase() || a->build_done() ||
          a->build_total() || a->omitted())return "invalid room response";
      if(a->rooms_dormitories()>a->rooms_created())return "invalid room type counts";
      if(a->operation()==AreaOperation::MultiCreate) {
        if(a->rooms_removed() ||
            (a->room_outcome()==AreaRoomOutcome::Completed ?
              (bool(a->rooms_created())!=bool(a->undo_token())) : (a->undo_token()!=0)))
          return "invalid room creation result";
      } else if(a->rooms_created() || a->rooms_in_use() || a->rooms_unenclosed() || a->undo_token())
        return "invalid room undo result";
      if(a->operation()==AreaOperation::MultiFinish && (a->rooms_removed() || a->room_outcome()!=AreaRoomOutcome::Completed))
        return "invalid room finish result";
      if(a->operation()==AreaOperation::MultiUndo &&
          (a->room_outcome()==AreaRoomOutcome::Rejected || a->room_outcome()==AreaRoomOutcome::Stale) && a->rooms_removed())
        return "invalid room undo result";
    }
    if(count(a->settings())>128 || count(a->locations())>128 ||
        count(a->candidates())>128 || count(a->links())>128) return "area response too large";
    const unsigned families=(count(a->settings())!=0)+(count(a->locations())!=0)+
        (count(a->candidates())!=0)+(count(a->links())!=0);
    if(families>1 || (count(a->choices()) && (count(a->areas()) || families)) ||
        (families && count(a->areas())>1)) return "area response mixes list families";
    // Sum variable payloads across the entire reply, not just each page's
    // per-row bounds. Scalar/table overhead still fits the 512 KiB channel.
    size_t payload=textSize(a->list_key())+textSize(a->query());
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
          (v->gives() && v->gives()->size()>1024) || (v->takes() && v->takes()->size()>1024) ||
          v->revision()>INT64_MAX || textSize(v->zone_label())>512 ||
          textSize(v->location_name())>512 || textSize(v->religion())>512 ||
          v->location_id()<-1 || v->location_site_id()<-1 || v->organic()<-1 || v->organic()>1 ||
          v->inorganic()<-1 || v->inorganic()>1 || !validAreaZoneSettings(v->zone_settings()) ||
          v->tile_count()<-1 || v->assigned_count()<-1 || v->location_kind()>5 ||
          v->owner_sex()<-1 || v->owner_sex()>1 || textSize(v->owner_profession())>512) return "invalid area state";
      payload+=4+textSize(v->name())+textSize(v->owner_name())+textSize(v->zone_label())+
          textSize(v->location_name())+textSize(v->religion())+textSize(v->owner_profession());
      for (auto extent:*v->extents()) if(extent>1) return "invalid area extent";
      extentTotal+=v->extents()->size();
      for(auto* links:{v->gives(),v->takes()}) if(links){
        std::set<int32_t> ids;
        for(auto id:*links) if(id<0 || id==v->id() || !ids.insert(id).second) return "invalid area link";
        linkTotal+=links->size();
      }
    }
    if(extentTotal>32768 || linkTotal>8192) return "area response exceeds bounded payload";
    payload+=extentTotal+linkTotal*sizeof(int32_t);
    if (a->choices()) for(const auto* c:*a->choices()) {
      if(!c || c->id()<0 || !choiceIds.insert(c->id()).second || !c->name() ||
          c->name()->size()>512 || textSize(c->label())>512) return "invalid area choice";
      payload+=sizeof(int32_t)+textSize(c->name())+textSize(c->label());
    }
    std::set<std::pair<std::string,int32_t>> settingKeys;
    if(a->settings()) for(const auto* row:*a->settings()) {
      if(!row || textSize(row->key())>64 || textSize(row->label())>512 ||
          row->index()<-1 || row->kind()>4 || row->state()>3 ||
          !settingKeys.emplace(row->key() ? row->key()->str() : "",row->index()).second)
        return "invalid area setting row";
      payload+=7+textSize(row->key())+textSize(row->label());
    }
    if(a->locations()) for(const auto* row:*a->locations()) {
      if(!row || row->id()<-1 || row->location_kind()>5 || row->guild_profession()<-1 || row->guild_profession()>511 || row->location_tier()<-1 || row->site_id()<-1 ||
          textSize(row->name())>512 || textSize(row->religion())>512) return "invalid area location row";
      payload+=15+textSize(row->name())+textSize(row->religion());
    }
    if(a->candidates()) for(const auto* row:*a->candidates()) {
      if(!row || row->id()<-1 || textSize(row->name())>512 || textSize(row->profession())>512 ||
          row->sex()<-1 || row->sex()>1 || row->mood()>7 || row->squad_use()<-1 || row->squad_use()>15)
        return "invalid area candidate row";
      payload+=9+textSize(row->name())+textSize(row->profession());
    }
    if(a->links()) for(const auto* row:*a->links()) {
      if(!row || row->id()<0 || (row->kind()!=AreaKind::Stockpile && row->kind()!=AreaKind::Workshop) ||
          row->direction()<1 || row->direction()>2 || textSize(row->name())>512) return "invalid area link row";
      payload+=6+textSize(row->name());
    }
    if(payload>224*1024) return "area response exceeds bounded payload";
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
    ids.clear();if(w->choices())for(const auto* c:*w->choices())if(!c || c->id()<0 || !ids.insert(c->id()).second || (!textOk(c->name(),512) || (c->label() && c->label()->size())))return "invalid work order choice";
    ids.clear();if(w->managers())for(const auto* m:*w->managers()){
      if(!m || m->unit_id()<0 || !ids.insert(m->unit_id()).second || !textOk(m->name(),512) || !textOk(m->position(),512) || !textOk(m->job(),512) || (m->offices() && m->offices()->size()>64))return "invalid manager role";
      std::set<int32_t> offices;if(m->offices())for(auto id:*m->offices())if(id<0 || !offices.insert(id).second)return "invalid manager office";
    }
    std::set<std::string> keys;if(w->recipes())for(const auto* r:*w->recipes())if(!r || !r->key() || !r->key()->size() || !textOk(r->key(),128) || !keys.insert(r->key()->str()).second || !textOk(r->name(),512) || (r->requirements() && r->requirements()->size()))return "invalid manager recipe";
  }
  if(const auto* c=s.citizen()) {
    if((c->citizens() && c->citizens()->size()>32) || (c->details() && c->details()->size()>16) || c->selected_unit() < -1 || c->selected_detail() < -1 || c->selected_detail()>127 || (c->detail() && c->detail()->size()>2048)) return "invalid citizen state";
    if(c->recalc_done()>c->recalc_total() || c->detail_list_revision()>INT64_MAX ||
       (c->recalc_error() && c->recalc_error()->size()>256)) return "invalid citizen recalculation state";
    auto nonempty=[](const auto* values){return values && values->size();};
    const auto citizenCount=c->citizens()?c->citizens()->size():0;
    const auto detailCount=c->details()?c->details()->size():0;
    if(s.action()==ManagementAction::CitizenList) {
      if(detailCount) return "invalid citizen roster page";
    } else if(s.action()==ManagementAction::WorkDetailList) {
      if(citizenCount) return "invalid work detail list page";
    } else if(s.action()==ManagementAction::CitizenInspect ||
              (s.action()>=ManagementAction::WorkDetailInspect && s.action()<=ManagementAction::WorkDetailMode) ||
              (s.action()>=ManagementAction::WorkDetailCreate && s.action()<=ManagementAction::CitizenWorkScope)) {
      if(citizenCount>1 || detailCount>1) return "invalid citizen inspection page";
    } else if(citizenCount || detailCount) return "unexpected citizen state";
    auto textOk=[](const flatbuffers::String* v,size_t cap){return v && v->size()<=cap;};
    auto namesOk=[](const auto* names,const auto* ids){if(!names||!ids||names->size()!=ids->size())return false;for(const auto* name:*names)if(!name||name->size()>128)return false;return true;};
    auto laborsOk=[](const auto* values){if(!values || values->size()>94)return false;int prior=-1;for(auto v:*values){if(v<0 || v>93 || v<=prior)return false;prior=v;}return true;};
    std::set<int32_t> ids;
    if(c->citizens())for(const auto* v:*c->citizens()) {
      if(!v || v->id()<0 || !ids.insert(v->id()).second || v->age() < -1 || v->age()>1000000 || !v->origin() || v->origin()->x()<0 || v->origin()->y()<0 || v->origin()->z()<0 || !textOk(v->name(),512) || !textOk(v->profession(),512) || !textOk(v->job(),512) || !textOk(v->reason(),512) || !laborsOk(v->labors()) || !namesOk(v->labor_names(),v->labors()) || (v->roles() && v->roles()->size()>32) || (v->offices() && v->offices()->size()>64))return "invalid citizen row";
      // detail_skill is int16 on the wire, so its upper bound is already INT16_MAX.
      if(v->revision()>INT64_MAX || v->detail_member()< -1 || v->detail_member()>1 ||
         v->detail_skill()< -1 || v->detail_skill_rating()< -1 || v->detail_skill_rating()>20 ||
         v->portrait_state()>3 || (v->detail_skill_name() && v->detail_skill_name()->size()>128) ||
         (v->row_error() && v->row_error()->size()>256)) return "invalid citizen detail fields";
      if(s.action()==ManagementAction::CitizenList && (nonempty(v->labors()) || nonempty(v->labor_names()) ||
         nonempty(v->roles()) || nonempty(v->offices()))) return "unexpected citizen roster detail fields";
      if(v->assigned_details()) {
        if(v->assigned_details()->size()>128)return "too many citizen work details";
        int prior=-1;
        for(const auto* d:*v->assigned_details()) {
          if(!d || d->index()<=prior || d->index()>127 || d->icon()< -1 || d->icon()>18 || !textOk(d->name(),512))return "invalid citizen work detail";
          if(s.action()==ManagementAction::CitizenList && d->name()->size())return "unexpected citizen roster detail names";
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
    ids.clear();
    if(c->details())for(const auto* d:*c->details()) {
      if(!d || d->index()<0 || d->index()>127 || !ids.insert(d->index()).second || !d->revision() || d->revision()>INT64_MAX || d->mode()>3 || !textOk(d->name(),512) || !textOk(d->reason(),512) || !laborsOk(d->labors()) || !namesOk(d->labor_names(),d->labors()) || !d->assigned_units() || d->assigned_units()->size()>1024)return "invalid work detail";
      if(d->icon()< -2 || d->icon()>18 || (d->row_error() && d->row_error()->size()>256))
        return "invalid work detail fields";
      int32_t prior=-1;for(auto id:*d->assigned_units()){if(id<0 || id<=prior)return "invalid work detail membership";prior=id;}
    }
  }
  if((s.action()==ManagementAction::PrepareAlertDismissal || s.action()==ManagementAction::DismissAlert) && s.status()==ManagementStatus::Ok) {
    const auto* r=s.report();
    if(!r || !r->list_revision() || r->list_revision()>INT64_MAX || r->total()>65536 ||
       r->view()!=ReportView::Flat || r->tab()!=ReportTab::Unknown || r->notification_category()!=-1 || r->alert_button() ||
       r->cursor() || r->next_cursor() || r->unit_id()!=-1 || r->unit_category()!=-1 ||
       (r->reports() && r->reports()->size()) || (r->units() && r->units()->size()))
      return "invalid alert dismissal state";
  }
  if(const auto* r=s.report()) {
    if(r->view()>ReportView::Group || r->tab()>ReportTab::Hunting || r->after_id() < -1 || r->next_after_id() < -1 || r->trimmed_through() < -1 ||
       r->next_before_id() < -1 || (r->detail() && r->detail()->size()>2048) ||
       (r->reports() && r->reports()->size()>(r->view()==ReportView::Flat?16u:64u)) ||
       (r->tab_counts() && r->tab_counts()->size()!=0 && r->tab_counts()->size()!=25))return "invalid report state";
    const bool groupOwner=r->notification_category()>=0 || r->alert_button();
    if(r->notification_category()< -1 || r->notification_category()>36 || (r->alert_button() && r->notification_category()!=-1) ||
       (groupOwner && r->view()!=ReportView::Group && r->view()!=ReportView::Text))return "invalid alert group state selector";
    if(groupOwner && (r->tab()!=ReportTab::Unknown || r->unit_id()!=-1 || r->unit_category()!=-1))return "mixed report state owners";
    if(r->view()==ReportView::Group) {
      const size_t count=(r->reports()?r->reports()->size():0)+(r->units()?r->units()->size():0);
      if(!groupOwner || !r->list_revision() || r->total()>65536 || r->cursor()>r->total() || count>64 ||
         count>r->total()-r->cursor() || (r->total() && !count) ||
         r->next_cursor()!=(r->cursor()+count<r->total()?r->cursor()+count:0) ||
         r->after_id()!=-1 || r->next_after_id()!=-1 || r->next_before_id()!=-1 || r->from_end() ||
         r->trimmed_through()!=-1 || r->gap() || (r->tab_counts() && r->tab_counts()->size()))return "invalid alert group state";
    }
    if(r->view()==ReportView::Tab && (!r->list_revision() || r->tab()<ReportTab::All || r->tab()>ReportTab::Curses || !r->tab_counts() ||
       r->tab_counts()->size()!=25 || r->total()!=r->tab_counts()->Get(uint8_t(r->tab())-1) ||
       (r->reports() && r->reports()->size()>r->total())))return "invalid report tab state";
    if(r->unit_id()< -1 || r->unit_category()< -1 || r->unit_category()>2 || r->list_revision()>INT64_MAX ||
       (r->units() && r->units()->size()>64))return "invalid report unit state";
    if(r->view()==ReportView::UnitList && (r->unit_category()<0 || !r->list_revision() || r->cursor()>r->total() ||
       r->next_cursor()>r->total() || (r->next_cursor() && r->next_cursor()<=r->cursor()) ||
       (r->reports() && r->reports()->size())))return "invalid unit list state";
    if(r->view()==ReportView::UnitLog && (r->unit_id()<0 || r->unit_category()<0 || !r->list_revision()))return "invalid unit log state";
    if(r->view()!=ReportView::UnitList && r->view()!=ReportView::Entries && r->view()!=ReportView::Group && r->units() && r->units()->size())return "unexpected report unit rows";
    if(r->view()==ReportView::UnitList && r->units() && r->units()->size()>r->total()-r->cursor())return "unit page exceeds remaining rows";
    std::set<std::pair<int32_t,int8_t>> unitIds;
    if(r->units())for(const auto* u:*r->units()) {
      if(!u || u->unit_id()<0 || u->category()<0 || u->category()>2 || (r->view()!=ReportView::Entries && r->view()!=ReportView::Group && !unitIds.insert({u->unit_id(),u->category()}).second) ||
         !u->name() || u->name()->size()>512 || !u->profession() || u->profession()->size()>512 || !u->error() || u->error()->size()>256 ||
         (r->view()==ReportView::UnitList && u->category()!=r->unit_category()))return "invalid report unit row";
    }
    if(r->missing_ids()) {
      if(r->missing_ids()->size()>64 || (r->view()!=ReportView::Entries && r->missing_ids()->size()))return "invalid missing report identities";
      for(auto id:*r->missing_ids())if(id<0)return "invalid missing report identity";
    }
    size_t bytes=0;std::set<int32_t> ids;
    if(r->reports())for(const auto* v:*r->reports()) {
      if(!v || v->id()<0 || (r->view()!=ReportView::Entries && r->view()!=ReportView::Group && !ids.insert(v->id()).second) || v->year()<0 || v->year_tick()<0 || v->year_tick()>=403200 || v->repeat_count()<0 || !v->text() || v->text()->size()>16384 || !v->category() || v->category()->size()>128)return "invalid report row";
      // Native report coordinates are signed 16-bit. Negative/off-map targets
      // are valid; presence is independent of reveal state and wire -1 defaults.
      auto pos=[](bool present,int x,int y,int z){
        return present ? (x>=INT16_MIN&&x<=INT16_MAX&&x!=-30000&&
                          y>=INT16_MIN&&y<=INT16_MAX&&z>=INT16_MIN&&z<=INT16_MAX)
                       : (x==-1&&y==-1&&z==-1);
      };
      if(!pos(v->position_visible(),v->x(),v->y(),v->z()) || !pos(v->position2_visible(),v->x2(),v->y2(),v->z2()))return "invalid report location";
      if(v->tab()>ReportTab::Hunting || v->color() < -1 || v->color()>15 || v->zoom_type()>ReportZoom::Unit ||
         v->zoom_type2()>ReportZoom::Unit || v->speaker_id() < -1 ||
         (v->position_hidden()&&!v->position_visible()) || (v->position2_hidden()&&!v->position2_visible()))return "invalid report metadata";
      bytes+=v->text()->size();
    }
    if(bytes>131072)return "report text budget exceeded";
    if(r->view()==ReportView::Text) {
      if(!r->list_revision() || r->total()>33554432 || r->cursor()>r->total() ||
         !r->reports() || r->reports()->size()!=1 || bytes>r->total()-r->cursor() ||
         (r->total() && !bytes) || r->next_cursor()!=(r->cursor()+bytes<r->total()?r->cursor()+bytes:0) ||
         r->reports()->Get(0)->text_complete()!=(r->cursor()==0 && bytes==r->total()) ||
         r->tab()>ReportTab::Curses || (r->unit_id()<0 ? r->unit_category()!=-1 : (r->unit_category()<0 || r->tab()!=ReportTab::Unknown)) ||
         r->after_id()!=-1 || r->next_after_id()!=-1 || r->next_before_id()!=-1 || r->from_end() ||
         r->trimmed_through()!=-1 || r->gap() || (r->tab_counts() && r->tab_counts()->size()))return "invalid report text state";
    }
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
