#pragma once
#include <tuple>
#include <set>
#include "stocks_reply_pages.h"
#include <unordered_set>
#include <optional>
#include "session_util.h"
#include "location_catalog_util.h"
#include "location_details_util.h"
#include "location_staff_candidates_util.h"
#include "location_name_util.h"
#include "location_recognition_util.h"
namespace df3d::mirror {
inline bool validNoblesOffice(const NoblesOffice* key,uint32_t lastSlot) {
  return key && key->entity_id()>=0 && key->position_id()>=0 && key->assignment_id()>=-1 &&
    key->draft_slot()<=lastSlot && (key->assignment_id()==-1 || key->draft_slot()==0);
}
inline std::optional<std::string> validateNoblesHelp(const NoblesHelp& help,bool present,size_t& bytes) {
  bytes+=64;
  const auto text=[&](const flatbuffers::String* value){if(!value || value->size()>16384)return false;bytes+=4+value->size();return true;};
  if(!text(help.description()))return "invalid nobles help description";
  for(const auto* group:{help.rooms(),help.furniture()}){
    if(!group || group->size()!=4)return "invalid nobles help assessments";
    for(const auto* part:*group){
      if(!part || !text(part->actual()) || !text(part->required()) ||
         (part->color()!=11 && part->color()!=12 && part->color()!=14 && part->color()!=15))return "invalid nobles help assessment";
      bytes+=16;
      if(!present && (part->actual()->size() || part->required()->size() || part->color()!=15))return "unexpected nobles holder help";
    }
  }
  for(const auto* group:{help.demands(),help.mandates()}){
    if(!group || group->size()>65536 || (!present && group->size()))return "invalid nobles help obligations";
    for(const auto* item:*group){
      if(!item || !text(item->text()) || (item->color()!=6 && item->color()!=12 && item->color()!=14 && item->color()!=15))return "invalid nobles help obligation";
      bytes+=16;
    }
  }
  if(const auto* a=help.accounting()){
    if(!present || a->setting()>4 || a->level()>4 || !text(a->title()) || !text(a->examples()) || !text(a->attained()) || !text(a->progress()))return "invalid nobles accounting help";
    bytes+=16;
  }
  if(bytes>384*1024)return "nobles help payload exceeded";
  return std::nullopt;
}
inline bool validArtDraftElement(const WorkOrderArtDraftElement* e) {
  return e && e->kind()>=7 && e->kind()<=13 && e->id()>=0 && e->secondary()>=-1 &&
    e->quantity()>=0 && e->quantity()<=1000000000 &&
    ((e->kind()==8 || e->kind()==9 || e->kind()==10 || e->kind()==13)?e->secondary()==-1:e->secondary()<=32767);
}
inline bool validArtDraftRelationship(const WorkOrderArtDraftRelationship* r,size_t elements) {
  return r && r->verb()>=0 && r->verb()<=32767 && r->actor()>=0 && size_t(r->actor())<elements &&
    (r->transitive()?(r->target()>=0 && size_t(r->target())<elements && r->target()!=r->actor()):r->target()==-1);
}
inline bool validArtDraftValue(const WorkOrderArtDraftValue* v) {
  if(!v || !v->elements() || !v->relationships() || v->elements()->size()>256 || v->relationships()->size()>256)return false;
  for(const auto* e:*v->elements())if(!validArtDraftElement(e))return false;
  for(const auto* r:*v->relationships())if(!validArtDraftRelationship(r,v->elements()->size()))return false;
  if(const auto* n=v->name()) {
    if(!n->first_name_bytes() || !n->nickname_bytes() || n->first_name_bytes()->size()>kLocationNameBytes ||
       n->nickname_bytes()->size()>kLocationNameBytes || !n->words() || n->words()->size()!=7 ||
       !n->parts() || n->parts()->size()!=7 || n->language()<-1 || n->type()<-1)return false;
    for(auto word:*n->words())if(word<-1)return false;
    for(auto part:*n->parts())if(part<0 || part>8)return false;
  }
  return true;
}
// Shared artwork draft semantics; callers separately validate their source IDs,
// revision, exclusive envelope fields and outer artwork bounds.
inline std::optional<std::string> validateArtDraftRequest(const WorkOrderArtRequest& art,bool writing) {
  const auto* a=&art;const auto* draft=a->draft();
  if(!draft)return "artwork draft required";
  const auto op=draft->action();
  const bool changesWorld=op==WorkOrderArtDraftAction::GenerateName || op==WorkOrderArtDraftAction::Commit ||
    (op==WorkOrderArtDraftAction::EditName && draft->name_edit() && draft->name_edit()->mode()>=LocationNameMode::RandomComponent);
  if((a->page()<6 && a->page()!=-1) || a->subject()!=-1 || a->hovered()!=-1 || a->preview_columns() ||
     !validArtDraftValue(draft->value()) || op>WorkOrderArtDraftAction::EditName ||
     writing!=changesWorld || !draft->columns() || draft->columns()>256 ||
     (op!=WorkOrderArtDraftAction::Inspect && (a->cursor() || (a->query() && a->query()->size()))))return "invalid artwork draft intent";
  if(op==WorkOrderArtDraftAction::AddElement ? !validArtDraftElement(draft->element()) : draft->element()!=nullptr)return "invalid artwork draft element intent";
  if(op==WorkOrderArtDraftAction::AddRelationship) {
    if(!validArtDraftRelationship(draft->relationship(),draft->value()->elements()->size()))return "invalid artwork draft relationship intent";
  } else if(draft->relationship()) {
    const auto* r=draft->relationship();
    if(op!=WorkOrderArtDraftAction::Inspect || (a->page()!=15 && a->page()!=16) || r->verb()<0 || r->verb()>32767 ||
       r->target()!=-1 || (a->page()==15?r->actor()!=-1:(!r->transitive() || r->actor()<0 || size_t(r->actor())>=draft->value()->elements()->size())))return "invalid artwork relationship selection";
  }
  if(op==WorkOrderArtDraftAction::Delete ? (draft->delete_index()<0 || size_t(draft->delete_index())>=draft->value()->elements()->size()+draft->value()->relationships()->size()) : draft->delete_index()!=-1)return "invalid artwork draft delete intent";
  if(op==WorkOrderArtDraftAction::Commit && (draft->value()->elements()->size()==0 || !draft->value()->name()))return "invalid artwork draft commit";
  if(a->page()==-1 && (op!=WorkOrderArtDraftAction::Inspect || a->cursor() || a->expected_list_revision() || (a->query() && a->query()->size())))return "invalid artwork root draft";
  if(a->page()==18) {
    if(!draft->value()->name() || !draft->name_query() || validateLocationNameQuery(*draft->name_query()) || draft->name_query()->cursor()>262144 ||
       (op!=WorkOrderArtDraftAction::Inspect && op!=WorkOrderArtDraftAction::EditName) || a->cursor() || a->expected_list_revision() || (a->query() && a->query()->size()))return "invalid artwork name query";
  } else if(draft->name_query() || op==WorkOrderArtDraftAction::EditName)return "unexpected artwork name query";
  if(op==WorkOrderArtDraftAction::EditName ? (!draft->name_edit() || validateLocationNameEdit(*draft->name_edit()).has_value() || draft->name_query()->cursor()!=0) : draft->name_edit()!=nullptr)return "invalid artwork name edit";
  return std::nullopt;
}
inline std::optional<std::string> validateArtDraftState(const WorkOrderArtState& art) {
  const auto* a=&art;const auto textOk=[](const flatbuffers::String* v,size_t max){return !v || v->size()<=max;};
  if(a->page()>=6 || (a->page()==-1 && a->draft())) {
    if(!validArtDraftValue(a->draft()) || !a->draft_description() || a->draft_description()->size()>128 || a->hovered()!=-1)return "invalid artwork draft observation";
    for(const auto* line:*a->draft_description())if(!line || line->size()>2048)return "invalid artwork draft description";
  } else if(a->draft() || a->draft_description())return "unexpected artwork draft observation";
  if(a->page()==18) {
    const auto* n=a->name();
    if(!n || !a->draft()->name() || !n->native_header() || !n->english_header() || !textOk(n->native_header(),16384) || !textOk(n->english_header(),16384) ||
       n->component()>6 || !n->query_bytes() || n->query_bytes()->size()>4096 || !n->choices() || n->choices()->size()>128 || n->total()>262144 ||
       uint64_t(n->cursor())+n->choices()->size()>n->total())return "invalid artwork name state";
    const uint64_t end=uint64_t(n->cursor())+n->choices()->size();
    if(n->next_cursor()!=(end<n->total()?end:0) || (end<n->total() && !n->choices()->size()))return "invalid artwork name pagination";
    size_t bytes=n->native_header()->size()+n->english_header()->size()+n->query_bytes()->size();
    for(const auto* row:*n->choices()) {
      if(!row || row->word()<0 || row->part()<0 || row->part()>8 || !row->english() || !row->translated())return "invalid artwork name word";
      bytes+=64+row->english()->size()+row->translated()->size();if(bytes>65536)return "artwork name page too large";
    }
  } else if(a->name())return "unexpected artwork name state";
  return std::nullopt;
}
// Shared by wire validation and the private Lua builder's owned recipe blobs.
inline const char* validateOwnerAppearance(const SelectionAppearance& image,size_t& payload) {
  const auto* p=&image;
  if(!p->tile_pages() || p->tile_pages()->size()>256 || !p->palettes() || p->palettes()->size()>256 ||
     !p->layers() || p->layers()->size()>256)return "invalid owner sheet icon references";
  payload+=12+p->layers()->size()*sizeof(AppearanceLayer);
  for(const auto* t:*p->tile_pages()) {if(!t || t->size()>256)return "invalid owner sheet icon page";payload+=4+t->size();}
  for(const auto* t:*p->palettes()) {if(!t || t->size()>512)return "invalid owner sheet icon palette";payload+=4+t->size();}
  for(const auto* l:*p->layers())if(l->page()>=p->tile_pages()->size() || !l->cells_x() || !l->cells_y() ||
     (l->palette()!=65535 && l->palette()>=p->palettes()->size()))return "invalid owner sheet icon layer";
  return nullptr;
}
inline bool validInspectionInstrument(const ItemInspectionAppearance& a,int32_t type) {
  if(a.slab_engraving() < -2 || a.slab_engraving()>26 || (a.slab_engraving()!=-2 && type!=87))return false;
  size_t recipeBytes=0;
  if(const auto* portrait=a.portrait()) {
    if((type!=51 && type!=52) || validateOwnerAppearance(*portrait,recipeBytes) || portrait->layers()->size()==0)return false;
  }
  if(const auto* occupant=a.cage_occupant()) {
    if(type!=16 || a.cage_material_family()<0 || a.cage_occupant_entity()<1 || a.cage_occupant_id()<0 ||
       validateOwnerAppearance(*occupant,recipeBytes) || occupant->layers()->size()==0)return false;
  }
  if(const auto* corpse=a.corpse_selector()) {
    if((type!=23 && type!=46) || validateOwnerAppearance(*corpse,recipeBytes) || corpse->layers()->size()==0)return false;
  }
  if(const auto* legwear=a.legwear_selector()) {
    if(type!=60 || validateOwnerAppearance(*legwear,recipeBytes) || legwear->layers()->size()==0)return false;
  }
  if(a.coffin_unused() < -1 || a.coffin_unused()>1 || (type!=21 && a.coffin_unused()!=-1))return false;
  if(a.artifact_mood() < -1 || a.artifact_mood()>1 || (type!=24 && a.artifact_mood()!=-1))return false;
  if(a.craft_soft_material() < -1 || a.craft_soft_material()>1 ||
     (a.craft_soft_material()!=-1 && (type<36 || type>43 || type==39)))return false;
  if(const auto* gem=a.craft_gem_color()) {
    if(type<36 || type>43 || type==39 || gem->size()>128)return false;
  }
  if(recipeBytes>131072)return false;

    const auto* liquidColor=a.bucket_liquid_color();
    if(a.bucket_liquid() < -1 || a.bucket_liquid()>1 || (type!=18 && a.bucket_liquid()!=-1) ||
       (liquidColor && (liquidColor->size()>128 || (a.bucket_liquid()!=1 && liquidColor->size()))))return false;
    const bool doorUnknown=a.door_open()==-1 && a.door_forbidden()==-1 && a.door_wear()==-1;
    if(!doorUnknown && (type!=6 || a.door_open()<0 || a.door_open()>1 || a.door_forbidden()<0 || a.door_forbidden()>1 || a.door_wear()<0 || a.door_wear()>3))return false;
  if(a.restraint_rope() < -1 || a.restraint_rope()>1 || (a.restraint_rope()!=-1 && type!=10) || (a.restraint_solid_color() && (a.restraint_solid_color()->size()>128 || (a.restraint_rope()==-1 && a.restraint_solid_color()->size()))))return false;
  if(a.cage_material_family() < -1 || a.cage_material_family()>2 || a.cage_occupant_entity() < -1 || a.cage_occupant_entity()>2 || a.cage_occupant_id() < -1 || (a.cage_solid_color() && a.cage_solid_color()->size()>128))return false;
  if(a.cage_material_family()==-1) {if(a.cage_occupant_entity()!=-1 || a.cage_occupant_id()!=-1 || (a.cage_solid_color() && a.cage_solid_color()->size()))return false;}
  else if(type!=16 || a.cage_occupant_entity()<0 || (a.cage_occupant_entity()==0 ? a.cage_occupant_id()!=-1 : a.cage_occupant_id()<0))return false;
  if(a.floodgate_open() < -1 || a.floodgate_open()>1 || (type!=7 && a.floodgate_open()!=-1))return false;
  if(const auto* c=a.contents()) {
    if(c->material_inorganic() < -1 || c->material_inorganic()>1 || (type==17 ? c->material_inorganic()==-1 : c->material_inorganic()!=-1) || (c->solid_color() && (c->solid_color()->size()>128 || (type!=17 && c->solid_color()->size()))))return false;
    if((type!=17 && type!=31 && type!=32) || !c->entries() || c->entries()->size()>(type==32?4096u:1u) || (type!=31 && !c->container() && c->entries()->size()))return false;
    for(const auto* e:*c->entries())if(!e || e->item_type() < -1 || e->item_type()>92 ||
      !e->material_token() || e->material_token()->size()>256 || !e->color_token() || e->color_token()->size()>128)return false;
  }
  return type==13 ? a.instrument_family()>=0&&a.instrument_family()<=3&&a.instrument_placed()>=0&&a.instrument_placed()<=1 : a.instrument_family()==-1&&a.instrument_placed()==-1;
}
inline bool validContentsAppearance(const BuildingContentsItem& row) {
  const auto* a=row.appearance();
  if(!a)return row.item_type()!=13&&row.item_type()!=30;
  return validInspectionInstrument(*a,row.item_type())&&a->material_token()&&a->material_token()->size()>0&&a->material_token()->size()<=256&&
    a->subtype_raw()&&a->subtype_raw()->size()<=128&&a->color_token()&&a->color_token()->size()<=128&&a->stack()>0&&!(a->flags()&~96)&&
    row.material_token()&&row.subtype_raw()&&a->material_token()->str()==row.material_token()->str()&&a->subtype_raw()->str()==row.subtype_raw()->str();
}
inline constexpr int standingCategoryCount(int category) {
  switch(category){case 0:return 11;case 1:case 4:return 6;case 2:case 3:return 10;case 6:return 7;default:return 0;}
}
inline constexpr int standingValueMax(int category,int id) {
  return category==3 || category==4 || (category==0 && id==0)?2:category==6 && id==0?3:1;
}
inline constexpr uint32_t kManagementVersion = 193;
inline constexpr const char* kManagementRegionName = "Local\\df3d_management_v193";
inline constexpr uint32_t kResidentsQueryBytes = 128;
inline constexpr uint32_t kResidentsQueryUnits = 65536;
inline constexpr uint32_t kResidentsRowsLimit = 64;
inline constexpr uint32_t kManagementCapacity = 512 * 1024;
// 192 KiB maximum path payload leaves room for the rest of the reply envelope.
inline constexpr uint32_t kConnectedTrackMaxTiles = 16384;
// v39: Track may select one distinct material group per tile (16,384 total).
// The maximum encoded request is tested against this bound; older peers use a separate region.
inline constexpr uint32_t kManagementCommandCapacity = 2 * 1024 * 1024;
inline const char* validateFarmSnapshot(const FarmSnapshot& f) {
  if(f.building_id()<0 || !f.revision() || f.revision()>INT64_MAX ||
     f.selected_season()<0 || f.selected_season()>3 || f.current_season()<0 || f.current_season()>3 ||
     !f.seasonal_crops() || f.seasonal_crops()->size()!=4 || !f.choices() || f.choices()->size()>256)
    return "invalid native farm snapshot";
  if(!f.custom_name() || f.custom_name()->size()>1536 || !f.header_name() || !f.header_name()->size() || f.header_name()->size()>1536 ||
     (!f.removing() && (f.removal_suspended() || f.removal_has_worker())))return "invalid farm header";
  if(f.current_fertilization()<0 || f.max_fertilization()<0 || f.pending_fertilization()<0)return "invalid farm fertilization";
  for(auto id:*f.seasonal_crops())if(id < -1 || id>32767)return "invalid native farm selection";
  std::set<int32_t> ids;
  for(const auto* c:*f.choices())if(!c || c->id()<0 || c->id()>32767 || !ids.insert(c->id()).second ||
      !c->name() || !c->name()->size() || c->name()->size()>512 ||
      !c->raw_id() || !c->raw_id()->size() || c->raw_id()->size()>128)return "invalid native farm choice";
  return nullptr;
}
inline bool areaZoneSettingsPresent(const AreaZoneSettings* z) {
  return z && (z->pond_mode() || z->facing() || z->tomb_citizens()!=-1 ||
      z->tomb_pets()!=-1 || z->gather_trees()!=-1 || z->gather_shrubs()!=-1 || z->gather_fallen()!=-1);
}
inline bool validAreaZoneSettings(const AreaZoneSettings* z) {
  if(!z) return true;
  return z->pond_mode()<=2 && z->facing()<=4 &&
      z->tomb_citizens()>=-1 && z->tomb_citizens()<=1 &&
      z->tomb_pets()>=-1 && z->tomb_pets()<=1 &&
      z->gather_trees()>=-1 && z->gather_trees()<=1 &&
      z->gather_shrubs()>=-1 && z->gather_shrubs()<=1 &&
      z->gather_fallen()>=-1 && z->gather_fallen()<=1;
}
// Keep this order in the Lua dispatcher too: selector, matrix, kind, legacy
// ownership, new-field ownership/requirements, identities, then bounded sizes.
inline std::optional<std::string> validateAreaOperation(ManagementAction action, const AreaRequest& a) {
  if(a.candidate_limit() && (a.candidate_limit()>128 || action!=ManagementAction::AreaCandidates ||
      a.operation()!=AreaOperation::CandidateList || a.kind()!=AreaKind::Zone || a.id()<0 || (a.candidate_kind()!=1 && a.candidate_kind()!=2)))
    return "invalid selector candidate limit";
  if(const auto* bytes=a.query_bytes()) {
    if(action!=ManagementAction::AreaCandidates || a.operation()!=AreaOperation::CandidateList ||
       a.kind()!=AreaKind::Zone || a.id()<0 || (a.candidate_kind()!=1 && a.candidate_kind()!=2) || bytes->size()>33 ||
       (a.query() && a.query()->size()))return "invalid owner query bytes";
  }
  const auto op=static_cast<uint8_t>(a.operation());
  if(op>40) return "Unsupported area operation";
  const bool nameRead=op==28,nameChoices=op==29,nameEdit=op==30;
  const bool recognitionRead=op==31,recognize=op==32;
  const bool recognition=recognitionRead || recognize;
  const bool religiousRead=op==33,religiousRemove=op==34;
  const bool religiousCandidates=op==35,religiousAssignmentRead=op==36,religiousAssign=op==37;
  const bool specializationRead=op==38 || op==40,specializationSet=op==39;
  const bool specialization=specializationRead || specializationSet;
  const bool religiousSelection=religiousAssignmentRead || religiousAssign;
  const bool religious=religiousRead || religiousRemove || religiousCandidates || religiousSelection;
  const bool naming=nameRead || nameChoices || nameEdit;
  const bool linkTarget=op==26;
  const bool multi=op>=16 && op<=18;
  const bool counts=op==19;
  const bool locationChoices=op==20;
  const bool staffCandidates=op==24;
  const bool staffEdit=op==25;
  const bool locationOpen=op==22;
  const bool locationAccess=op==23;
  const bool quantityEdit=op==27;
  const bool locationDetails=op==21 || locationOpen || locationAccess || staffEdit || quantityEdit;
  const bool inspect=action==ManagementAction::AreaInspect;
  const bool create=action==ManagementAction::AreaCreate;
  const bool update=action==ManagementAction::AreaUpdate;
  bool allowed=op==0;
  switch(a.operation()) {
    case AreaOperation::LocationStaffAssignmentsRead: case AreaOperation::LocationSpecializationRead: case AreaOperation::LocationReligiousCandidates: case AreaOperation::LocationReligiousAssignmentRead: case AreaOperation::LocationReligiousStaffRead: case AreaOperation::LocationRecognitionRead: case AreaOperation::LocationNameRead: case AreaOperation::LocationNameChoices: allowed=inspect;break;
    case AreaOperation::LocationSpecializationSet: case AreaOperation::LocationReligiousAssign: case AreaOperation::LocationReligiousStaffRemove: case AreaOperation::LocationRecognize: case AreaOperation::LocationNameEdit: allowed=update;break;
    case AreaOperation::LinkTarget: case AreaOperation::SettingsPage: case AreaOperation::LocationList: case AreaOperation::Links: case AreaOperation::PaintCounts: case AreaOperation::LocationChoices: case AreaOperation::LocationDetails: case AreaOperation::LocationStaffCandidates:
      allowed=inspect; break;
    case AreaOperation::SettingsSet: case AreaOperation::Preset: case AreaOperation::Rename:
    case AreaOperation::LocationSet: case AreaOperation::LocationCreate: case AreaOperation::ZoneSettings:
    case AreaOperation::AssignUnits: case AreaOperation::SquadUse: case AreaOperation::Toggles: case AreaOperation::LocationOpen: case AreaOperation::LocationAccess: case AreaOperation::LocationStaffEdit: case AreaOperation::LocationQuantity:
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
  const bool stock=op==1 || op==2 || op==3 || op==10 || op==13 || linkTarget;
  const bool zone=(op>=6 && op<=9) || op==11 || op==12 || op==14 || multi || counts || locationChoices || locationDetails || staffCandidates || naming || recognition || religious || specialization;
  if((stock && a.kind()!=AreaKind::Stockpile) || (zone && a.kind()!=AreaKind::Zone))
    return "Area kind is not valid for this operation";
  if(op && ((op!=16 && ((!linkTarget && a.origin()) || a.width()!=1 || a.height()!=1)) ||
      (a.zone_type()!=-1 && !(op==5 && create) && !counts) || a.categories() || a.changed_categories() ||
      a.barrels()!=-1 || a.bins()!=-1 || a.wheelbarrows()!=-1 || a.links_only()!=-1 ||
      a.active()!=-1 || a.owner_id()!=-2 ||
      (op!=15 && (a.link_id()!=-1 || (!linkTarget && !a.give()) || a.unlink()))))
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
  if(linkTarget && (!a.origin() || a.origin()->x()<0 || a.origin()->y()<0 || a.origin()->z()<0 ||
      a.origin()->x()>32767 || a.origin()->y()>32767 || a.origin()->z()>32767 ||
      !a.expected_revision() || a.cursor() || present(a.query()))) return "invalid stockpile link target request";
  // Ordered like the appended schema fields, so malformed requests have stable errors.
  const std::pair<bool,const char*> foreign[]{
    {a.expected_list_revision()!=0 && !(op==1 || op==6 || op==10 || op==14 || locationChoices || staffCandidates || staffEdit || religiousCandidates || religiousSelection), "expected_list_revision"},
    {present(a.list_key()) && op!=1 && op!=2, "list_key"},
    {present(a.row_key()) && op!=2, "row_key"},
    {a.scope()!=0 && op!=2, "scope"}, {a.value()!=0 && op!=2 && !locationAccess && !specializationSet, "value"},
    {a.preset()!=0 && op!=3, "preset"}, {present(a.name()) && op!=4, "name"},
    {present(a.spans()) && op!=5 && !counts, "spans"}, {a.paint_mode()!=0 && op!=5, "paint_mode"},
    {a.paint_z()!=-1 && op!=5 && !counts, "paint_z"}, {a.location_id()!=-2 && op!=7 && !locationDetails && !staffCandidates && !naming && !recognition && !religious && !specialization, "location_id"},
    {a.location_kind()!=0 && op!=8 && !locationChoices, "location_kind"}, {a.profession()!=-1 && op!=8, "profession"},
    {a.deity_kind()!=-1 && op!=8, "deity_kind"}, {a.deity_id()!=-1 && op!=8, "deity_id"},
    {areaZoneSettingsPresent(a.zone_settings()) && op!=9, "zone_settings"},
    {a.item_id()!=-1 && op!=11, "item_id"}, {a.unit_id()!=-1 && op!=11 && !staffEdit && !religiousSelection && !specialization, "unit_id"}, {a.assign()!=-1 && op!=11, "assign"},
    {a.squad_id()!=-1 && op!=12, "squad_id"}, {a.squad_use()!=-1 && op!=12, "squad_use"},
    {a.organic()!=-1 && op!=13, "organic"}, {a.inorganic()!=-1 && op!=13, "inorganic"},
    {a.candidate_kind()!=0 && op!=14, "candidate_kind"}, {a.sort()!=0 && op!=14, "sort"},
    {a.sort_descending() && op!=14, "sort_descending"},
    {a.room_furniture()!=0 && op!=16, "room_furniture"},
    {a.interaction_id()!=0 && !multi, "interaction_id"},
    {a.undo_token()!=0 && op!=17, "undo_token"},
    {a.count_generation()!=0 && !counts, "count_generation"},
    {a.paint_preview()!=nullptr && !counts, "paint_preview"},
    {a.occupation_id()!=-1 && !staffCandidates && !staffEdit && !specialization, "occupation_id"},
    {a.location_site_id()!=-1 && !locationDetails && !staffCandidates && !naming && !recognition && !religious && !specialization, "location_site_id"},
    {a.religious_entity_id()!=-1 && !religious && !specialization, "religious_entity_id"},
    {a.religious_assignment_id()!=-1 && !religious && !specialization, "religious_assignment_id"},
    {a.religious_holder_id()!=-1 && !religiousRemove && !religiousSelection, "religious_holder_id"},
    {a.name_query()!=nullptr && !nameChoices, "name_query"},
    {a.name_edit()!=nullptr && !nameEdit, "name_edit"},
    {a.category_opening() && op!=1, "category_opening"},
    {a.quantity_id()!=-1 && !quantityEdit, "quantity_id"},
    {a.quantity_mode()!=LocationQuantityMode::Set && !quantityEdit, "quantity_mode"},
    {a.quantity_value()!=0 && !quantityEdit, "quantity_value"},
  };
  for(const auto& field:foreign) if(field.first)
    return std::string("Field ")+field.second+" does not belong to this operation";
  if(a.category_opening()) {
    const auto key=a.list_key()?a.list_key()->str():std::string{};
    bool known=false;
    for(const char* initial:{"food/meat","furniture/type","refuse/type","stone/metal_ores","ammo/type","bars_blocks/bars_metal","gems/rough_gem","finished_goods/type","leather/type","cloth/thread_silk","weapons/weapons","armor/body","sheet/paper"})
      known|=key==initial;
    if(!known)return "invalid settings opening context";
  }
  if(op==2 && (a.scope()<1 || a.scope()>4 || a.value()<1 || a.value()>2 ||
      present(a.row_key())!=(a.scope()==1))) return "invalid area settings edit";
  if(op==3 && (a.preset()<1 || a.preset()>19)) return "invalid area preset";
  if(quantityEdit && (a.quantity_id()<0 || a.quantity_id()>10 || a.quantity_mode()>LocationQuantityMode::Decrease ||
      (a.quantity_mode()==LocationQuantityMode::Set ? a.quantity_value()<0 || a.quantity_value()>999 : a.quantity_value()!=0)))
    return "invalid location quantity edit";
  if(locationAccess && a.value()>3)return "invalid location access mode";
  if(op==5 && (a.paint_mode()<1 || a.paint_mode()>2 || (create && a.paint_mode()!=1) ||
      !present(a.spans()))) return "invalid area paint";
  if(op==7 && a.location_id()<-1) return "area location required";
  if(op==8 && (a.location_kind()<1 || a.location_kind()>5 ||
      (a.location_kind()==4 ? a.profession()<0 : a.profession()!=-1) ||
      (a.location_kind()==2 ? (a.deity_kind()<1 || a.deity_kind()>3) : a.deity_kind()!=-1) ||
      (a.deity_kind()==2 || a.deity_kind()==3 ? a.deity_id()<0 : a.deity_id()!=-1)))
    return "invalid area location creation";
  if(op==9 && (!areaZoneSettingsPresent(a.zone_settings()) || !validAreaZoneSettings(a.zone_settings())))
    return "invalid area zone settings";
  if(op==11 && ((a.unit_id()>=0)==(a.item_id()>=0) || a.assign()<0 || a.assign()>1)) return "invalid area unit assignment";
  if(op==12 && (a.squad_id()<0 || a.squad_use()<0 || a.squad_use()>15)) return "invalid area squad use";
  if(op==13 && ((a.organic()==-1 && a.inorganic()==-1) || a.organic()<-1 || a.organic()>1 ||
      a.inorganic()<-1 || a.inorganic()>1)) return "invalid area toggles";
  if(op==14 && (a.candidate_kind()<1 || a.candidate_kind()>3 || a.sort()>(a.candidate_kind()==1?4:3)))
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
  if(a.id()<-1 || a.item_id()<-1 || a.unit_id()<-1 || a.squad_id()<-1 || a.deity_id()<-1 ||
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
  if(locationDetails && (a.location_site_id()<0 || a.location_id()<0 || a.id()!=-1 || ((locationOpen || locationAccess || staffEdit || quantityEdit)?!a.expected_revision():a.expected_revision()!=0) ||
      present(a.query()) || a.cursor()))return "invalid location details request";
  if(recognition && (a.location_site_id()<0 || a.location_id()<0 || a.id()!=-1 || present(a.query()) || a.cursor() ||
      (recognitionRead?a.expected_revision()!=0:!a.expected_revision()) || a.expected_revision()>INT64_MAX))return "invalid recognition request";
  if(religious) {
    if(a.location_site_id()<0 || a.location_id()<0 || a.id()!=-1 || present(a.query()) ||
        a.religious_entity_id()<0 || a.religious_assignment_id()<0 ||
        a.expected_revision()>INT64_MAX || a.expected_list_revision()>INT64_MAX)
      return "invalid religious staff request";
    if(religiousCandidates) {
      if(a.expected_revision() || a.cursor()%128 || (a.cursor() && !a.expected_list_revision()))
        return "invalid religious candidates request";
    } else if(a.cursor() || (religiousRemove && a.religious_holder_id()<0) ||
        ((religiousRead || religiousAssignmentRead)?a.expected_revision()!=0:!a.expected_revision()))
      return "invalid religious staff request";
    if(religiousSelection && (a.unit_id()<0 || a.religious_holder_id()<-1 || !a.expected_list_revision()))
      return "invalid religious assignment request";
  }
  if(specialization) {
    const bool occupation=a.occupation_id()>=0;
    if(a.location_site_id()<0 || a.location_id()<0 || a.unit_id()<0 || a.id()!=-1 || present(a.query()) || a.cursor() ||
        a.occupation_id()<-1 || (occupation?(a.religious_entity_id()!=-1 || a.religious_assignment_id()!=-1):
          (a.religious_entity_id()<0 || a.religious_assignment_id()<0)) ||
        (specializationRead?a.expected_revision()!=0:!a.expected_revision()) || a.value()>1)
      return "invalid location specialization request";
  }
  if(naming) {
    if(a.location_site_id()<0 || a.location_id()<0 || a.id()!=-1 || present(a.query()) || a.cursor() ||
        (nameRead?a.expected_revision()!=0:!a.expected_revision()))return "invalid location naming identity";
    if(nameChoices) {
      if(!a.name_query())return "missing location name query";
      if(auto error=validateLocationNameQuery(*a.name_query()))return error;
    }
    if(nameEdit) {
      if(!a.name_edit())return "missing location name edit";
      if(auto error=validateLocationNameEdit(*a.name_edit()))return error;
    }
  }
  if(op && !multi && !counts && !locationChoices && !locationDetails && !staffCandidates && !naming && !recognition && !religious && !specialization && !(op==5 && create) && a.id()<0) return "area id required";
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
  return action >= ManagementAction::Catalog && action <= ManagementAction::JusticeCaseRead &&
      action != ManagementAction::Alert && action != ManagementAction::Selection &&
      !(action >= ManagementAction::TradeExchangeOpen && action <= ManagementAction::TradeExchangeClose) &&
      !(action >= ManagementAction::StocksOpen && action <= ManagementAction::StocksClose) &&
      !(action >= ManagementAction::AppointmentsOpen && action <= ManagementAction::AppointmentsBack) &&
      !(action >= ManagementAction::KitchenOpen && action <= ManagementAction::KitchenClose);
}
inline bool validStocksKey(const StocksGroupKey* key) {return key && key->type()>=0 && key->type()<93 && key->subtype()>=-1 && key->subcat1()>=-1 && key->subcat2()>=-1;}
inline bool validStoneRestrictions(const flatbuffers::Vector<uint8_t>* flags) {
  if(!flags || flags->size()>65536)return false;
  for(auto value:*flags)if(value>1)return false;
  return true;
}
inline bool validKitchenKey(const KitchenFoodKey* k) {
  return k && k->item_type()>=0 && k->item_subtype()>=-1 && k->mat_type()>=-1 && k->mat_index()>=-1;
}
inline bool validKitchenReceipt(const KitchenFoodReceipt* r) {
  return r && validKitchenKey(r->key()) && r->count()>=0 && r->capabilities()>=1 && r->capabilities()<=3;
}
inline bool validKitchenExclusions(const flatbuffers::Vector<flatbuffers::Offset<KitchenExclusion>>* rows) {
  if(!rows || rows->size()>65536)return false;
  for(const auto* row:*rows)if(!row || !validKitchenKey(row->key()) || row->flags()>3)return false;
  return true;
}
inline bool validChoresSnapshot(const ChoresSnapshot* s) {
  if(!s || !s->children() || !s->exempted() || !s->labors() ||
     s->children()->size()>65536 || s->exempted()->size()>65536 || s->labors()->size()!=14)return false;
  std::unordered_set<int32_t> ids;
  for(int32_t id:*s->children())if(id<0 || !ids.insert(id).second)return false;
  int32_t prior=-1;for(int32_t id:*s->exempted()){if(id<=prior)return false;prior=id;}
  constexpr int32_t catalog[]={23,37,1,2,6,3,4,5,7,8,74,77,9,75};
  size_t index=0;for(const auto* row:*s->labors())if(!row || row->id()!=catalog[index++])return false;
  return true;
}
inline bool validHunterSpec(const HunterAmmunitionSpec* v) {
  if(!v || v->item_type()!=39 || v->item_subtype()<0 || v->material_class()<-1 || v->mattype()<-1 ||
     v->matindex()<-1 || v->amount()<0 || v->flags()>3 || !v->assigned())return false;
  int32_t prior=-1;for(auto id:*v->assigned()){if(id<=prior)return false;prior=id;}
  return true;
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
  if (r.action() < ManagementAction::Catalog || r.action() > ManagementAction::JusticeCaseRead)
    return "invalid management action";
  if (r.action() != ManagementAction::Catalog && !r.world_epoch()) return "world epoch required";
  if (r.action()==ManagementAction::WorldHover &&
      (!r.origin() || r.origin()->x()<0 || r.origin()->y()<0 || r.origin()->z()<0 ||
       r.origin()->x()>32767 || r.origin()->y()>32767 || r.origin()->z()>32767))
    return "invalid terrain description tile";
  if(r.action()==ManagementAction::CreatureInspect || r.action()==ManagementAction::CreatureLocate || r.action()==ManagementAction::CreatureSheetLocate) {
    if(!r.creature() || r.creature()->unit_id()<0) return "creature identity required";
  } else if(r.creature()) return "unexpected creature payload";
  if(r.action()==ManagementAction::CreatureHeaderRead || r.action()==ManagementAction::CreatureHeaderEdit) {
    const auto* h=r.creature_header();
    if(!h || h->unit_id()<0 || !h->name() || h->name()->size()>90 ||
       h->name()->str().find('\0')!=std::string::npos)return "invalid creature header request";
    if(r.action()==ManagementAction::CreatureHeaderRead) {
      if(h->profession() || h->expected_revision() || h->name()->size())return "unexpected creature header read intent";
    } else if(!h->expected_revision() || h->expected_revision()>INT64_MAX)return "creature header revision required";
  } else if(r.creature_header())return "unexpected creature header request";
  if(r.action()==ManagementAction::CreatureExpelRead || r.action()==ManagementAction::CreatureExpelApply) {
    const auto* e=r.creature_expel();
    if(!e || e->unit_id()<0 || e->destination_id() < -1 || !e->expected_unit_ids() ||
       e->expected_unit_ids()->size()>4096)return "invalid creature expel request";
    if(r.action()==ManagementAction::CreatureExpelRead) {
      if(e->destination_id()!=-1 || e->expected_unit_ids()->size())return "unexpected creature expel read intent";
    } else {
      int32_t previous=-1;bool selected=false;
      for(auto id:*e->expected_unit_ids()) {
        if(id<=previous)return "invalid creature expel group";
        previous=id;selected|=id==e->unit_id();
      }
      if(!selected)return "creature expel group must contain selected unit";
    }
  } else if(r.creature_expel())return "unexpected creature expel request";
  if(r.action()==ManagementAction::CreatureWorkshopRemove) {
    const auto* w=r.creature_workshop();
    if(!w || w->unit_id()<0 || w->building_id()<0 || !w->expected_revision() || w->expected_revision()>INT64_MAX)
      return "invalid creature workshop request";
  } else if(r.creature_workshop())return "unexpected creature workshop request";
  if(r.action()==ManagementAction::CreatureLocationRemove) {
    const auto* w=r.creature_location();
    if(!w || w->unit_id()<0 || w->occupation_id()<0 || !w->expected_revision() || w->expected_revision()>INT64_MAX)
      return "invalid creature location request";
  } else if(r.creature_location())return "unexpected creature location request";
  if(r.action()==ManagementAction::JobSettingsApply) {
    const auto* q=r.job_settings_edit();
    if(!q || q->job_id()<0 || q->building_id()<0 || q->unit_id() < -1 || q->option()<0 || q->option()>64 ||
       !q->expected_revision() || q->expected_revision()>INT64_MAX || q->expected_choices_revision()>INT64_MAX ||
       (q->query() && (q->query()->size()>128 || q->query()->str().find('\0')!=std::string::npos)))return "invalid job settings edit request";
    const auto page=q->art_page();const bool query=q->query() && q->query()->size();
    if(q->art()) {
      if(page!=-2 || q->choice()!=-1 || q->expected_choices_revision() || query)return "mixed job draft edit fields";
      const auto* a=q->art();
      if(a->page() < -1 || a->page()>18 || a->expected_list_revision()>INT64_MAX || a->cursor()>262144 ||
         (a->cursor() && !a->expected_list_revision()) || (a->query() && (a->query()->size()>128 || a->query()->str().find('\0')!=std::string::npos)))return "invalid job draft bounds";
      if(auto error=validateArtDraftRequest(*a,true))return error;
    } else if(page==-2) {
      if(!q->expected_choices_revision() || q->choice()<0 || q->choice()>=16384 || query)return "invalid ordinary job edit";
    } else if(page==-1 || page==0) {
      if(q->choice()!=-1 || query || (page==-1 ? !q->expected_choices_revision() : q->expected_choices_revision()!=0))return "invalid artwork entry or artist choice";
    } else if(page==1 || page==2 || page==3 || page==5) {
      if(!q->expected_choices_revision() || q->choice()<0 || (page==5 && q->choice()>=262144))return "invalid artwork subject choice";
    } else return "invalid artwork edit page";
  } else if(r.job_settings_edit())return "unexpected job settings edit request";
  if(r.action()==ManagementAction::JobSettingsRead) {
    const auto* q=r.job_settings();
    if(!q || q->job_id()<0 || q->building_id()<0 || q->unit_id() < -1 || q->option() < -1 || q->option()>64 ||
       q->cursor()>(q->art_page()==-2?16384u:262144u) || !q->query() || q->query()->size()>128 || q->query()->str().find('\0')!=std::string::npos)
      return "invalid job settings request";
    if(q->art()) {
      if(q->option()<0 || q->art_page()!=-2 || q->cursor() || q->query()->size() || q->expected_list_revision() || q->hovered()!=-1 || q->preview_columns() ||
         !q->expected_revision() || q->expected_revision()>INT64_MAX)return "mixed job draft read fields";
      const auto* a=q->art();
      if(a->page() < -1 || a->page()>18 || a->expected_list_revision()>INT64_MAX || a->cursor()>262144 ||
         (a->cursor() && !a->expected_list_revision()) || (a->query() && (a->query()->size()>128 || a->query()->str().find('\0')!=std::string::npos)))return "invalid job draft bounds";
      if(auto error=validateArtDraftRequest(*a,false))return error;
    } else if(q->expected_revision())return "unexpected job source revision";
    else if(q->art_page()==-2) {
      if(q->expected_list_revision() || q->hovered()!=-1 || q->preview_columns())return "unexpected job artwork fields";
    } else {
      if(q->option()<0 || (q->art_page()!=-1 && q->art_page()!=1 && q->art_page()!=2 && q->art_page()!=3 && q->art_page()!=5) ||
         q->expected_list_revision()>INT64_MAX || q->hovered() < -1 || q->preview_columns()>1024 ||
         (q->hovered()>=0 ? (!q->expected_list_revision() || !q->preview_columns()) : q->preview_columns()!=0))return "invalid job artwork request";
      if(q->art_page()==-1 && (q->cursor() || q->query()->size() || q->expected_list_revision() || q->hovered()!=-1))return "invalid job artwork root";
    }
  } else if(r.job_settings())return "unexpected job settings request";
  if(r.action()==ManagementAction::ResidentsActivityRead) {
    const auto* q=r.residents_activity();
    if(!q || q->unit_id()<0 || q->activity_id()<0 || q->event_id()<0 || q->columns()<1 || q->columns()>1024)
      return "invalid residents activity request";
  } else if(r.residents_activity())return "unexpected residents activity request";
  if(r.action()==ManagementAction::ResidentsSpecialize) {
    const auto* q=r.residents_specialization();
    if(!q || q->unit_id()<0 || !q->expected_revision() || q->expected_revision()>INT64_MAX)return "invalid residents specialization request";
  } else if(r.residents_specialization())return "unexpected residents specialization request";
  if(r.action()>=ManagementAction::NoblesRead && r.action()<=ManagementAction::NoblesSymbolsRetire){
    const auto* q=r.nobles();
    if(!q || q->expected_list_revision()>INT64_MAX || q->expected_candidate_revision()>INT64_MAX)return "invalid nobles request";
    const auto count=q->choices()?q->choices()->size():0;
    // 4096 operations bound replay storage and keep the draft below the shared
    // request payload budget. Slot references can only point backward.
    if(count>4096 || (count && !q->expected_list_revision()))return "invalid nobles draft";
    for(uint32_t i=0;i<count;++i){const auto* choice=q->choices()->Get(i);
      if(!choice || !validNoblesOffice(choice->target(),i) || choice->expected_unit_id()<-1 || choice->unit_id()<-1)return "invalid nobles choice";
    }
    const bool symbols=r.action()==ManagementAction::NoblesSymbolsRead;
    const bool applySymbols=r.action()==ManagementAction::NoblesSymbolsApply;
    const bool nameRead=r.action()==ManagementAction::NoblesSymbolNameRead;
    const bool nameEdit=r.action()==ManagementAction::NoblesSymbolNameEdit;
    const bool continuation=r.action()==ManagementAction::NoblesSymbolsContinue;
    const bool retire=r.action()==ManagementAction::NoblesSymbolsRetire;
    const bool step=nameRead || nameEdit || continuation;
    const auto symbolCount=q->symbol_choices()?q->symbol_choices()->size():0;
    if(!applySymbols && symbolCount)return "unexpected nobles symbol choices";
    if(!step && (q->step_token() || q->expected_name_revision() || q->name_query() || q->name_edit()))return "unexpected nobles naming fields";
    const bool accounting=r.action()==ManagementAction::NoblesAccounting;
    if(!accounting && (q->expected_setting()!=-1 || q->setting()!=-1))return "unexpected nobles accounting setting";
    if(retire){
      // FIFO cleanup of this client's bridge-owned tail, never simulation undo.
      if(count || q->target() || q->expected_list_revision() || q->expected_candidate_revision() || q->offset() || q->limit()!=32)return "invalid nobles symbol retirement";
    }else if(step){
      // The token binds the session, office, appointment draft and pending tail.
      // Clients cannot replace any of those inputs while naming is in progress.
      if(!q->step_token() || q->step_token()>INT64_MAX || q->expected_name_revision()>INT64_MAX ||
         count || q->target() || q->expected_list_revision() || q->expected_candidate_revision() ||
         q->offset() || q->limit()!=32)return "invalid nobles symbol step";
      if(nameRead){
        if(!q->name_query() || q->name_edit() || (q->name_query()->cursor() && !q->expected_name_revision()))return "invalid nobles symbol name read";
        if(auto error=validateLocationNameQuery(*q->name_query()))return error;
      }else if(nameEdit){
        if(!q->expected_name_revision() || !q->name_edit() || q->name_query())return "invalid nobles symbol name edit";
        if(auto error=validateLocationNameEdit(*q->name_edit()))return error;
      }else if(q->expected_name_revision() || q->name_query() || q->name_edit())return "unexpected nobles continuation fields";
    }else if(applySymbols){
      if(!q->expected_list_revision() || !q->expected_candidate_revision() || !validNoblesOffice(q->target(),0) ||
         q->target()->assignment_id()<0 || q->offset() || q->limit()!=32 || !symbolCount || symbolCount>4096)return "invalid nobles symbol apply";
      std::set<int32_t> items;
      for(const auto* choice:*q->symbol_choices())if(!choice || choice->item_id()<0 || !items.insert(choice->item_id()).second)return "invalid nobles symbol choice";
    }else if(accounting){
      if(!q->expected_list_revision() || !validNoblesOffice(q->target(),count) || q->offset() || q->limit()!=32 || q->expected_candidate_revision() ||
         q->expected_setting()<0 || q->expected_setting()>4 || q->setting()<0 || q->setting()>4)return "invalid nobles accounting request";
    }else if(r.action()==ManagementAction::NoblesCommit){
      if(!count || !q->expected_list_revision() || q->offset() || q->limit()!=32 || q->target() || q->expected_candidate_revision())return "invalid nobles commit";
    }else{
      const bool candidates=r.action()==ManagementAction::NoblesCandidates || symbols;
      if(!q->limit() || q->limit()>64 || q->offset()>(candidates?1048576u:65536u) ||
         (q->offset() && !q->expected_list_revision()))return "invalid nobles page request";
      if(candidates){
        if(!q->expected_list_revision() || !validNoblesOffice(q->target(),count) || (q->offset() && !q->expected_candidate_revision()))return "invalid nobles candidate request";
        if(symbols && (q->target()->assignment_id()<0 || q->target()->draft_slot()))return "invalid nobles symbol office";
      }else if(q->target() || q->expected_candidate_revision())return "unexpected nobles candidate target";
    }
  }else if(r.nobles())return "unexpected nobles request";
  if(r.action()==ManagementAction::JusticeRead || r.action()==ManagementAction::JusticeCaseRead){
    const auto* q=r.justice();
    if(!q || q->tab()>2 || !q->limit() || q->limit()>64 || q->offset()>1048576 ||
      q->expected_list_revision()>INT64_MAX || q->expected_case_revision()>INT64_MAX)return "invalid justice request";
    if(r.action()==ManagementAction::JusticeRead){
      if(q->crime_id()!=-1 || q->expected_case_revision() || (q->offset() && !q->expected_list_revision()))return "invalid justice list request";
    }else if(q->crime_id()<0 || !q->expected_list_revision() || (q->offset() && !q->expected_case_revision()))return "invalid justice case request";
  }else if(r.justice())return "unexpected justice request";
  if(r.action()==ManagementAction::ObjectsRead || r.action()==ManagementAction::ObjectsLocate){
    const auto* q=r.objects();if(!q || q->tab()>3 || q->expected_list_revision()>INT64_MAX)return "invalid objects request";
    if(r.action()==ManagementAction::ObjectsRead){
      if(!q->limit() || q->limit()>64 || q->offset()>1048576 ||
        (q->offset() && !q->expected_list_revision()) || q->artifact_id()!=-1)return "invalid objects page request";
    }else if(q->offset() || q->limit()!=32 || !q->expected_list_revision() || q->artifact_id()<0)return "invalid objects destination request";
  }else if(r.objects())return "unexpected objects request";
  if(r.action()==ManagementAction::PlacesRead || r.action()==ManagementAction::PlacesApply){
    const auto* q=r.places();if(!q || q->tab()>5 || q->expected_list_revision()>INT64_MAX)return "invalid places request";
    if(r.action()==ManagementAction::PlacesRead){
      if(!q->limit() || q->limit()>64 || q->offset()>1048576 ||
        (q->offset() && !q->expected_list_revision()) || q->building_id()!=-1 || q->siege_action()!=-1)return "invalid places page request";
    }else if(q->tab()!=5 || q->offset() || q->limit()!=32 || !q->expected_list_revision() ||
      q->building_id()<-1 || q->siege_action()<0 || q->siege_action()>4)return "invalid places siege request";
  }else if(r.places())return "unexpected places request";
  if(r.action()==ManagementAction::TasksRead || r.action()==ManagementAction::TasksApply) {
    const auto* q=r.tasks();if(!q || q->operation()>TasksOperation::Cancel)return "invalid tasks request";
    if(r.action()==ManagementAction::TasksRead){
      if(!q->limit() || q->limit()>64 || q->offset()>1048576 || q->expected_list_revision()>INT64_MAX ||
         (q->offset() && !q->expected_list_revision()) || q->job_id()!=-1 || q->worker_id()!=-1 || q->building_id()!=-1 ||
         q->expected_revision() || q->operation()!=TasksOperation::Repeat || q->expected_state()!=-1)return "invalid tasks page request";
    }else if(q->offset() || q->limit()!=32 || q->expected_list_revision() || q->job_id()<0 || q->worker_id()<-1 ||
      q->building_id()<0 || !q->expected_revision() || q->expected_revision()>INT64_MAX ||
      ((q->operation()==TasksOperation::Repeat || q->operation()==TasksOperation::Suspend)?
        (q->expected_state()<0 || q->expected_state()>1):q->expected_state()!=-1) ||
      (q->operation()==TasksOperation::RemoveWorker && q->worker_id()<0))return "invalid tasks edit";
  }else if(r.tasks())return "unexpected tasks request";
  if(r.action()==ManagementAction::StocksMenuRead || r.action()==ManagementAction::StocksGroupApply || r.action()==ManagementAction::StocksItemApply) {
    const auto* q=r.stocks_menu();if(!q || q->category()<-1 || q->category()>=93 || !q->query() || q->query()->size()>4096 || q->operation()>StocksFlagAction::Hidden)return "invalid stocks request";
    if(q->page_request()) {
      if(r.action()!=ManagementAction::StocksMenuRead || q->page_request()>=r.seq() || q->category()!=-1 || q->query()->size() ||
         (q->item_ids() && q->item_ids()->size()) || !q->page_offset() || q->page_offset()>=df3d::stocks_pages::retainedBytes ||
         q->page_offset()%df3d::stocks_pages::pageBytes)return "invalid stocks continuation";
    }else if(q->page_offset())return "unexpected stocks page offset";
    if((r.action()==ManagementAction::StocksItemApply && q->item_id()<0) || (r.action()!=ManagementAction::StocksItemApply && q->item_id()!=-1))return "invalid stocks item target";
    std::unordered_set<int32_t> ids;
    if(q->item_ids()){if(q->item_ids()->size()>64)return "too many stocks rows";for(auto id:*q->item_ids())if(id<0 || !ids.insert(id).second)return "invalid stocks row identity";}
    if(r.action()==ManagementAction::StocksMenuRead){
      if(q->target() || q->expected_revision() || q->value()!=-1 || q->operation()!=StocksFlagAction::Forbid)return "unexpected stocks edit fields";
    }else if(!validStocksKey(q->target()) || q->category()!=q->target()->type() || q->query()->size() || !ids.empty() ||
      !q->expected_revision() || q->expected_revision()>INT64_MAX || q->value()<0 || q->value()>1)return "invalid stocks edit";
  }else if(r.stocks_menu())return "unexpected stocks request";
  if(r.action()==ManagementAction::StoneUseRead || r.action()==ManagementAction::StoneUseApply) {
    const auto* q=r.stone_use();if(!q)return "missing stone use request";
    if(r.action()==ManagementAction::StoneUseRead){
      if(q->category()!=-1 || q->index()!=-1 || q->expected())return "invalid stone use read";
    }else if(q->category()<0 || q->category()>1 || q->index()<0 || !validStoneRestrictions(q->expected()) ||
      uint32_t(q->index())>=q->expected()->size())return "invalid stone use edit";
  }else if(r.stone_use())return "unexpected stone use request";
  if(r.action()==ManagementAction::KitchenRead || r.action()==ManagementAction::KitchenApply) {
    const auto* q=r.kitchen_menu();if(!q)return "missing kitchen request";
    if(r.action()==ManagementAction::KitchenRead){
      const auto* v=q->query();
      if(!v || v->type_filter()<-1 || v->type_filter()>3 || v->capability_filter()>3 || !v->query() || v->query()->size()>4096 ||
         !v->sorts() || !v->sorts()->size() || v->sorts()->size()>65536 || q->target() || q->permission() || q->expected())return "invalid kitchen query";
      unsigned seen=0,reversed=0;for(const auto* sort:*v->sorts()){
        if(!sort || sort->column()<KitchenSortColumn::Type || sort->column()>KitchenSortColumn::Brew)return "invalid kitchen sort";
        const unsigned bit=1u<<unsigned(sort->column());if((seen&bit) && bool(reversed&bit)!=sort->reverse())return "inconsistent kitchen sort direction";
        seen|=bit;if(sort->reverse())reversed|=bit;
      }
    }else if(q->query() || !validKitchenReceipt(q->target()) || !validKitchenExclusions(q->expected()) ||
      (q->permission()!=1 && q->permission()!=2) || !(q->target()->capabilities()&q->permission()))return "invalid kitchen edit";
  }else if(r.kitchen_menu())return "unexpected kitchen request";
  if(r.action()==ManagementAction::ChoresRead || r.action()==ManagementAction::ChoresApply) {
    const auto* q=r.chores();if(!q)return "missing chores request";
    if(r.action()==ManagementAction::ChoresRead) {
      if(q->operation()!=ChoresOperation::None || q->id()!=-1 || q->value() || q->expected())return "unexpected chores edit";
    }else{
      if(!validChoresSnapshot(q->expected()) || q->operation()<ChoresOperation::Enabled || q->operation()>ChoresOperation::Exempt)return "invalid chores edit";
      if(q->operation()==ChoresOperation::Enabled){if(q->id()!=-1)return "unexpected chores target";}
      else if(q->operation()==ChoresOperation::Labor){bool found=false;for(const auto* row:*q->expected()->labors())found|=row->id()==q->id();if(!found)return "invalid chore labor";}
      else if(std::find(q->expected()->children()->begin(),q->expected()->children()->end(),q->id())==q->expected()->children()->end())return "invalid chore child";
    }
  }else if(r.chores())return "unexpected chores request";
  if(r.action()>=ManagementAction::HunterAmmunitionRead && r.action()<=ManagementAction::HunterAmmunitionApply) {
    const auto* q=r.hunter_ammunition();if(!q)return "missing hunter ammunition request";
    using O=HunterAmmunitionOperation;
    const bool apply=r.action()==ManagementAction::HunterAmmunitionApply;
    const bool choices=r.action()==ManagementAction::HunterAmmunitionCandidates;
    if(q->operation()<O::None || q->operation()>O::Remove)return "invalid ammunition operation";
    if(!apply){
      if(q->operation()!=O::None || q->index()!=-1 || q->item_id()!=-1 || q->amount()!=-1 || q->material_class()!=-1 ||
         q->mattype()!=-1 || q->matindex()!=-1 || q->expected())return "unexpected ammunition edit fields";
      if(choices?(q->item_type()!=39 || q->item_subtype()<0):(q->item_type()!=-1 || q->item_subtype()!=-1))return "invalid ammunition candidate target";
    }else{
      if(q->operation()==O::None || !q->expected())return "missing ammunition edit receipt";
      for(const auto* spec:*q->expected())if(!validHunterSpec(spec))return "invalid ammunition receipt";
      if(q->operation()==O::Add ? q->index()!=-1 : (q->index()<0 || size_t(q->index())>=q->expected()->size()))return "invalid ammunition rule target";
      if(q->operation()==O::Amount ? (q->amount()<0 || q->amount()>5000) : q->amount()!=-1)return "invalid ammunition amount";
      if(q->operation()==O::Remove ? q->item_id()<0 : q->item_id()!=-1)return "invalid ammunition item target";
      if(q->operation()==O::Add ? (q->item_type()!=39 || q->item_subtype()<0) : (q->item_type()!=-1 || q->item_subtype()!=-1))return "invalid ammunition type";
      if(q->operation()==O::Material ? (q->material_class()<-1 || q->mattype()<-1 || q->matindex()<-1) :
         (q->material_class()!=-1 || q->mattype()!=-1 || q->matindex()!=-1))return "invalid ammunition material";
    }
  }else if(r.hunter_ammunition())return "unexpected ammunition request";
  if(r.action()==ManagementAction::StandingOrdersRead || r.action()==ManagementAction::StandingOrdersSet) {
    const auto* q=r.standing_orders();
    if(!q || !standingCategoryCount(q->category()))return "invalid standing orders category";
    if(r.action()==ManagementAction::StandingOrdersRead) {
      if(q->setting_id()!=-1 || q->expected_value()!=-1 || q->value()!=-1)return "unexpected standing orders write";
    } else if(q->setting_id()<0 || q->setting_id()>=standingCategoryCount(q->category()) || q->expected_value()<0 || q->value()<0 ||
              q->expected_value()>standingValueMax(q->category(),q->setting_id()) || q->value()>standingValueMax(q->category(),q->setting_id()))return "invalid standing orders edit";
  } else if(r.standing_orders())return "unexpected standing orders request";
  if(r.action()==ManagementAction::WorkDetailSettingsRead || r.action()==ManagementAction::WorkDetailSettingsToggle) {
    const auto* q=r.work_detail_settings();
    if(!q || q->detail_index()<0 || q->detail_index()>=128 || !q->expected_revision() || q->expected_revision()>INT64_MAX)
      return "invalid work-detail settings authority";
    if(r.action()==ManagementAction::WorkDetailSettingsRead ? q->setting_id()!=-1 :
       !((q->setting_id()>=-13 && q->setting_id()<=-2) || (q->setting_id()>=1 && q->setting_id()<=93)))
      return "invalid work-detail setting target";
  } else if(r.work_detail_settings())return "unexpected work-detail settings request";
  if(r.action()==ManagementAction::WorkDetailWorkersQuery) {
    const auto* q=r.work_detail_workers();
    if(!q || q->detail_index()<0 || q->detail_index()>=128 || !q->expected_revision() || q->expected_revision()>INT64_MAX ||
       !q->sorts() || !q->sorts()->size() || q->sorts()->size()>65536 || !q->query_bytes() || q->query_bytes()->size()>kResidentsQueryBytes ||
       std::find(q->query_bytes()->begin(),q->query_bytes()->end(),uint8_t(0))!=q->query_bytes()->end())
      return "invalid work-detail worker query";
    std::array<int8_t,4> directions{{-1,-1,-1,-1}};
    for(const auto* sort:*q->sorts()) {
      if(!sort || sort->column()>WorkDetailWorkerSort::Skills)return "invalid work-detail sort";
      auto& direction=directions[size_t(sort->column())];
      if(direction!=-1 && direction!=int8_t(sort->descending()))return "conflicting work-detail sort direction";
      direction=int8_t(sort->descending());
    }
  } else if(r.work_detail_workers())return "unexpected work-detail worker query";
  if(r.action()==ManagementAction::ResidentsQuery) {
    const auto* q=r.residents();
    if(!q || q->sort()>ResidentsSort::Activity || !q->query_bytes() ||
       q->query_bytes()->size()>kResidentsQueryBytes ||
       std::find(q->query_bytes()->begin(),q->query_bytes()->end(),uint8_t(0))!=q->query_bytes()->end())
      return "invalid residents query";
  } else if(r.residents())return "unexpected residents query";
  if(r.action()==ManagementAction::ResidentsRowsRead || r.action()==ManagementAction::WorkDetailRowsRead) {
    const auto* q=r.residents_rows();
    if(!q || !q->unit_ids() || q->unit_ids()->size()==0 || q->unit_ids()->size()>kResidentsRowsLimit ||
       q->columns()<3 || q->columns()>30)return "invalid residents rows request";
    if(r.action()==ManagementAction::WorkDetailRowsRead) {
      if(q->detail_index()<0 || q->detail_index()>=128 || !q->expected_revision() || q->expected_revision()>INT64_MAX)return "invalid work detail row authority";
    } else if(q->detail_index()!=-1 || q->expected_revision())return "unexpected work detail row authority";
    std::unordered_set<int32_t> ids;
    for(auto id:*q->unit_ids())if(id<0 || !ids.insert(id).second)return "invalid residents row identity";
  } else if(r.residents_rows())return "unexpected residents rows request";
  if(r.action()==ManagementAction::CreatureAnimalEdit) {
    const auto* w=r.creature_animal();
    if(!w || w->unit_id()<0 || w->animal_id()<0 || !w->expected_revision() || w->expected_revision()>INT64_MAX)
      return "invalid creature animal request";
  } else if(r.creature_animal())return "unexpected creature animal request";
  if(r.action()==ManagementAction::CreatureKnowledgeRead) {
    const auto* k=r.creature_knowledge();
    if(!k || k->unit_id()<0 || k->kind()<14 || k->kind()>17 || k->id()<0)
      return "invalid creature knowledge request";
  } else if(r.creature_knowledge())return "unexpected creature knowledge request";
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
  if (r.action() >= ManagementAction::ProductionList && r.action() <= ManagementAction::FarmEdit) {
    const auto* p=r.production();
    if (!p || p->building_id() < -1 || p->job_id() < -1 || p->crop_id() < -1 || p->crop_id()>32767 ||
        p->repeat() < -1 || p->repeat()>1 || p->suspend() < -1 || p->suspend()>1 ||
        p->season() < -1 || p->season()>3 || (p->query() && p->query()->size()>(r.action()==ManagementAction::ProductionInspect?138:128)) ||
        (p->recipe() && p->recipe()->size()>128)) return "invalid production request";
    if(!p->workshop_orders() && (p->general_order_delta() || p->general_order_value()!=-1))return "unexpected workshop order step";
    if(p->workshop_orders()) {
      const bool edit=r.action()==ManagementAction::FarmEdit;
      if((!edit && r.action()!=ManagementAction::ProductionInspect) || p->building_id()<0 ||
         p->workshop_workers() || p->building_header() || p->independent_item() || p->locate_item() || p->contents() ||
         p->worker_id()!=-1 || p->worker_value()!=-1 || p->worker_list_revision() ||
         p->item_id()!=-1 || p->item_value()!=-1 || p->season()!=-1 || p->crop_id()!=-1 || p->seasonal_fertilization()!=-1 ||
         p->job_id()!=-1 || p->repeat()!=-1 || p->suspend()!=-1 || p->cancel() || p->farm_name() || p->cursor() ||
         p->farm_operation()!=FarmOperation::Crop || (p->recipe() && p->recipe()->size()) || (p->query() && p->query()->size()) ||
         p->expected_revision()>INT64_MAX || p->general_order_value()<-1 || p->general_order_value()>99 ||
         (edit ? (!p->expected_revision() || (p->general_order_value()>=0 ? p->general_order_delta()!=0 : (p->general_order_delta()!=-1 && p->general_order_delta()!=1)))
               : (p->expected_revision() || p->general_order_delta() || p->general_order_value()!=-1)))return "invalid workshop orders intent";
    } else if(p->workshop_workers()) {
      const bool edit=r.action()==ManagementAction::FarmEdit;
      if((!edit && r.action()!=ManagementAction::ProductionInspect) || p->building_id()<0 ||
         p->building_header() || p->independent_item() || p->locate_item() || p->contents() ||
         p->item_id()!=-1 || p->item_value()!=-1 || p->season()!=-1 || p->crop_id()!=-1 || p->seasonal_fertilization()!=-1 ||
         p->job_id()!=-1 || p->repeat()!=-1 || p->suspend()!=-1 || p->cancel() || p->farm_name() ||
         (p->recipe() && p->recipe()->size()) || (p->query() && p->query()->size()) ||
         p->expected_revision()>INT64_MAX || p->worker_list_revision()>INT64_MAX ||
         (edit ? (p->worker_id()<0 || !p->expected_revision() || p->cursor() || p->farm_operation()<FarmOperation::WorkerSelect || p->farm_operation()>FarmOperation::WorkerSpecialize || (p->farm_operation()==FarmOperation::WorkerSelect?!p->worker_list_revision():p->worker_list_revision()!=0) || (p->farm_operation()==FarmOperation::WorkerSpecialize?(p->worker_value()<0 || p->worker_value()>1):p->worker_value()!=-1))
               : (p->worker_id()!=-1 || p->worker_value()!=-1 || p->expected_revision() || p->farm_operation()!=FarmOperation::Crop || p->cursor()%128 || (p->cursor() && !p->worker_list_revision()))))return "invalid workshop worker intent";
    } else {
    if(p->worker_id()!=-1 || p->worker_value()!=-1 || p->worker_list_revision() || p->farm_operation()>=FarmOperation::WorkerSelect)return "unexpected workshop worker intent";
    if(p->building_header() && (p->building_id()<0 || p->independent_item() || p->locate_item() || p->contents() ||
       p->item_id()!=-1 || p->item_value()!=-1 || p->season()!=-1 || p->crop_id()!=-1 || p->seasonal_fertilization()!=-1 ||
       p->job_id()!=-1 || p->cursor() || p->repeat()!=-1 || p->suspend()!=-1 || p->cancel() ||
       (p->recipe() && p->recipe()->size()) || (p->query() && p->query()->size()) ||
       (r.action()!=ManagementAction::ProductionInspect && r.action()!=ManagementAction::FarmEdit) ||
       (r.action()==ManagementAction::FarmEdit && (p->farm_operation()<FarmOperation::Rename || p->farm_operation()>FarmOperation::CancelRemoval))))return "invalid building header intent";
    if(p->contents_item_id()<-1 || (p->contents_item_id()>=0 && (!p->independent_item() || r.action()!=ManagementAction::FarmEdit || p->contents_item_id()==p->item_id())))return "invalid item contents intent";
    if(p->independent_item() && (p->building_id()!=-1 || p->item_id()<0 || p->locate_item() ||
       (r.action()!=ManagementAction::ProductionInspect && r.action()!=ManagementAction::FarmEdit) ||
       (r.action()==ManagementAction::FarmEdit && (p->farm_operation()<FarmOperation::ItemForbid || p->farm_operation()>FarmOperation::ItemHidden))))return "invalid independent item intent";
    if(p->locate_item() && (r.action()!=ManagementAction::ProductionInspect || p->building_id()!=-1 || p->item_id()<0))return "invalid item position intent";
    if (r.action()!=ManagementAction::ProductionList && !p->locate_item() && !p->independent_item() && p->building_id()<0) return "production building required";
    if (r.action()==ManagementAction::ProductionQueue && (!p->recipe() || !p->recipe()->size())) return "recipe required";
    if (r.action()==ManagementAction::ProductionJobEdit && (p->job_id()<0 ||
        (p->cancel() && (p->repeat()!=-1 || p->suspend()!=-1)) ||
        (!p->cancel() && p->repeat()==-1 && p->suspend()==-1))) return "invalid job edit";
    if(static_cast<uint8_t>(p->farm_operation())>9 || p->seasonal_fertilization() < -1 || p->seasonal_fertilization()>1)return "invalid farm operation";
    if(p->farm_operation()==FarmOperation::Rename) {
      if(!p->farm_name() || p->farm_name()->size()>90 || p->farm_name()->str().find('\0')!=std::string::npos)return "invalid farm name";
    } else if(p->farm_name())return "unexpected farm name";
    if(r.action()!=ManagementAction::FarmEdit && (p->farm_operation()!=FarmOperation::Crop || p->seasonal_fertilization()!=-1))return "unexpected farm operation";
    const bool itemEdit=p->farm_operation()>=FarmOperation::ItemForbid && p->farm_operation()<=FarmOperation::ItemHidden;
    const bool itemInspect=r.action()==ManagementAction::ProductionInspect && p->item_id()>=0;
    if(itemInspect && (p->item_value()!=-1 || p->contents() || p->season()!=-1 || p->cursor() ||
        p->job_id()!=-1 || p->crop_id()!=-1 || p->repeat()!=-1 || p->suspend()!=-1 || p->cancel() ||
        (p->recipe() && p->recipe()->size()) || (p->query() && p->query()->size())))return "invalid item inspection";
    if(itemEdit) {
      if(r.action()!=ManagementAction::FarmEdit || p->item_id()<0 || p->item_value()<0 || p->item_value()>1 ||
         p->season()!=-1 || p->contents())return "invalid contained item intent";
    } else if(!itemInspect && (p->item_id()!=-1 || p->item_value()!=-1))return "unexpected contained item intent";
    if(r.action()==ManagementAction::FarmEdit) {
      if(!itemEdit && !p->building_header() && p->season()<0)return "season required";
      if(p->farm_operation()!=FarmOperation::Crop && p->crop_id()!=-1)return "unexpected farm crop";
      if(p->farm_operation()==FarmOperation::SeasonalFertilization ? p->seasonal_fertilization()<0 : p->seasonal_fertilization()!=-1)return "invalid seasonal fertilization intent";
    }
    if(p->contents() && (r.action()!=ManagementAction::ProductionInspect || p->season()!=-1 ||
        p->job_id()!=-1 || p->crop_id()!=-1 || p->repeat()!=-1 || p->suspend()!=-1 || p->cancel() ||
        (p->recipe() && p->recipe()->size()) || (p->query() && p->query()->size()) ||
        (p->cursor()>0 && !p->expected_revision())))return "invalid contents read";
    if(p->expected_revision()>INT64_MAX || (!p->contents() && (r.action()==ManagementAction::FarmEdit?!p->expected_revision():p->expected_revision()!=0)))return "invalid farm edit revision";
    if(r.action()==ManagementAction::FarmEdit && (p->job_id()!=-1 || p->cursor() || p->repeat()!=-1 || p->suspend()!=-1 || p->cancel() ||
        (p->recipe() && p->recipe()->size()) || (p->query() && p->query()->size())))return "unexpected farm edit fields";
    }
  } else if(r.production()) return "unexpected production payload";
  if(r.action()>=ManagementAction::WorkOrderList && r.action()<=ManagementAction::WorkOrderCatalog) {
    const auto* w=r.work_order();
    if(w && w->details()) {
      const auto* d=w->details();
      const bool writing=r.action()==ManagementAction::WorkOrderUpdate;
      if(d->dye_target() < -1 || d->dye_target()>1023 ||
         ((d->option()<0 || d->art()) && (d->dye_target()!=-1 || d->dye_filter_applied())) ||
         (writing && d->dye_filter_applied()))return "invalid dye Details navigation";
      if((r.action()!=ManagementAction::WorkOrderInspect && !writing) || w->id()<0 ||
         (w->workshop_id()<0 && w->workshop_id()!=-2) || d->option() < -1 || d->option()>64 ||
         d->choice() < -1 || d->choice()>16383 || d->expected_choices_revision()>INT64_MAX ||
         d->cursor()>16384 || (d->query() && d->query()->size()>128) ||
         (d->option()==-1 && (d->choice()!=-1 || d->cursor() || d->expected_choices_revision() || (d->query() && d->query()->size()))) ||
         (writing && !d->art() && (d->choice()<0 || !w->expected_revision() || !d->expected_choices_revision() || d->cursor() || (d->query() && d->query()->size()))) ||
         (!writing && d->choice()!=-1) || (d->cursor() && (!w->expected_revision() || !d->expected_choices_revision())) ||
         w->remaining()!=-1 || w->frequency()!=-1 || w->max_workshops()!=-1 ||
         (w->recipe() && w->recipe()->size()) || (w->query() && w->query()->size()) ||
         w->cursor() || w->expected_list_revision() || w->condition_kind() || w->condition_index()!=-1 || w->remove_condition() ||
         w->compare()!=-1 || w->threshold()!=-1 || w->item_type()!=-1 || w->item_subtype()!=-1 || w->mat_type()!=-1 || w->mat_index()!=-1 ||
         w->target_order()!=-1 || w->dependency()!=-1 || w->candidate_kind() || w->move() || w->expected_neighbor()!=-1 || w->traits() ||
         w->input_index()!=-1 || w->group_type()!=-1 || w->group_subtype()!=-1 || w->group_custom()!=-1 || w->encrust_flags()!=-1 ||
         w->filter_choice()!=-1 || w->suggestion_index()!=-1)return "invalid exclusive native Details intent";
      if(const auto* a=d->art()) {
        if(d->option()<0 || d->choice()!=-1 || d->expected_choices_revision() || d->cursor() || (d->query() && d->query()->size()) ||
           a->page() < -1 || a->page()>18 || a->subject() < -1 || a->expected_list_revision()>INT64_MAX ||
           a->cursor()>262144 || (a->query() && a->query()->size()>128) || !w->expected_revision() ||
           (a->cursor() && !a->expected_list_revision()))return "invalid exclusive artwork intent";
        if(const auto* draft=a->draft()) {
          if(auto error=validateArtDraftRequest(*a,writing))return error;
        } else {
          if(a->page()>5 || (!writing && (a->subject()!=-1 || a->page()==0)) ||
             (a->page()<=0 && (a->subject()!=-1 || a->expected_list_revision() || a->cursor() || (a->query() && a->query()->size()))) ||
             (writing && (a->cursor() || (a->page()>0 && (a->subject()<0 || !a->expected_list_revision())))))return "invalid exclusive artwork intent";
          if(a->hovered() < -1 || a->preview_columns()>256 ||
             (a->hovered()==-1 ? a->preview_columns()!=0 :
              (writing || a->page()<1 || !a->preview_columns() || !a->expected_list_revision())))return "invalid artwork preview intent";
        }
      }
    }
    if(w && (w->filter_choice() < -1 || w->filter_choice()>32767))return "invalid native filter choice";
    if(w && w->filter_choice()>=0 &&
       (r.action()!=ManagementAction::WorkOrderCondition || w->id()<0 || (w->workshop_id()<0 && w->workshop_id()!=-2) || !w->expected_revision() || !w->expected_list_revision() ||
        w->candidate_kind()<3 || w->candidate_kind()>5 || w->condition_kind() || w->condition_index()<0 ||
        w->suggestion_index()!=-1 || w->remove_condition() || w->remaining()!=-1 || w->frequency()!=-1 || w->max_workshops()!=-1 ||
        (w->recipe() && w->recipe()->size()) || (w->query() && w->query()->size()) || w->cursor() ||
        w->compare()!=-1 || w->threshold()!=-1 || w->item_type()!=-1 || w->item_subtype()!=-1 || w->mat_type()!=-1 || w->mat_index()!=-1 ||
        w->target_order()!=-1 || w->dependency()!=-1 || w->move() || w->expected_neighbor()!=-1 || w->traits() ||
        w->input_index()!=-1 || w->group_type()!=-1 || w->group_subtype()!=-1 || w->group_custom()!=-1 || w->encrust_flags()!=-1))
      return "native filter choice must be an exclusive condition edit";
    if(w && (w->suggestion_index() < -1 || w->suggestion_index()>127))return "invalid native suggestion index";
    if(w && w->suggestion_index()>=0 &&
       (r.action()!=ManagementAction::WorkOrderCondition || w->id()<0 || (w->workshop_id()<0 && w->workshop_id()!=-2) || !w->expected_revision() ||
        w->remaining()!=-1 || w->frequency()!=-1 || w->max_workshops()!=-1 ||
        (w->recipe() && w->recipe()->size()) || (w->query() && w->query()->size()) ||
        w->cursor() || w->expected_list_revision() || w->condition_kind() || w->condition_index()!=-1 || w->remove_condition() ||
        w->compare()!=-1 || w->threshold()!=-1 || w->item_type()!=-1 || w->item_subtype()!=-1 ||
        w->mat_type()!=-1 || w->mat_index()!=-1 || w->target_order()!=-1 || w->dependency()!=-1 ||
        w->candidate_kind() || w->move() || w->expected_neighbor()!=-1 || w->traits() ||
        w->input_index()!=-1 || w->group_type()!=-1 || w->group_subtype()!=-1 || w->group_custom()!=-1 || w->encrust_flags()!=-1 || w->filter_choice()!=-1))
      return "native suggestion must be an exclusive condition add";
    if(!w || w->expected_revision()>INT64_MAX || w->id() < -1 || w->remaining() < -1 || w->remaining()>32767 || w->frequency() < -1 || w->frequency()>4 ||
       w->workshop_id() < -2 || w->max_workshops() < -1 || w->max_workshops()>32767 || w->condition_kind()>1 ||
       w->condition_index() < -1 || w->condition_index()>63 || w->compare() < -1 || w->compare()>5 ||
       w->threshold() < -1 || w->item_type() < -1 || w->target_order() < -1 || w->dependency() < -1 || w->dependency()>1 ||
       w->candidate_kind()>5 || (w->recipe() && w->recipe()->size()>128) || (w->query() && w->query()->size()>(r.action()==ManagementAction::WorkOrderCatalog && w->workshop_id()>=0?76:64))) return "invalid work order request";
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
    if(r.action()==ManagementAction::WorkOrderCondition && w->suggestion_index()<0 && w->filter_choice()<0) {
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
    if(a->tracker() && (a->before_id()!=-1 || a->pending_only() || (a->query() && a->query()->size())))return "invalid tracker request";
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
  if (s.action() < ManagementAction::Catalog || s.action() > ManagementAction::JusticeCaseRead ||
      s.status() < ManagementStatus::Idle || s.status() > ManagementStatus::Rejected)
    return "invalid management enum";
  if (s.message() && s.message()->size() > 8192) return "message too long";
  if(const auto* p=s.stocks_page()) {
    if((s.action()!=ManagementAction::StocksMenuRead && s.action()!=ManagementAction::StocksGroupApply && s.action()!=ManagementAction::StocksItemApply) ||
       s.status()!=ManagementStatus::Pending || !s.world_epoch() || !s.client_id() || !p->request_seq() || p->request_seq()>s.request_seq() ||
       !p->total() || p->total()>df3d::stocks_pages::retainedBytes || p->offset()>=p->total() || p->offset()%df3d::stocks_pages::pageBytes ||
       !p->bytes() || p->bytes()->size()!=std::min(df3d::stocks_pages::pageBytes,p->total()-p->offset()) || s.stocks_menu())return "invalid stocks reply page";
    return std::nullopt;
  }
  if (const auto* t=s.world_hover()) {
    if(s.action()!=ManagementAction::WorldHover || !t->tile() ||
       t->tile()->x()<0 || t->tile()->y()<0 || t->tile()->z()<0 ||
       t->tile()->x()>32767 || t->tile()->y()>32767 || t->tile()->z()>32767 ||
       !t->entries() || t->entries()->size()>4096) return "invalid world hover";
    size_t bytes=0;
    for(const auto* e:*t->entries()) {
      if(!e || !e->text() || e->text()->size()>4096 || e->foreground()>7 ||
         e->background()>7 || e->kind()>15 || e->object_id()<-1) return "invalid hover entry";
      bytes+=e->text()->size();
    }
    if(bytes>320*1024) return "hover text too large";
  }
  if(s.action()==ManagementAction::CreatureInspect && s.status()==ManagementStatus::Ok && !s.creature()) return "creature result required";
  if(const auto* e=s.creature_expel()) {
    const bool read=s.action()==ManagementAction::CreatureExpelRead,apply=s.action()==ManagementAction::CreatureExpelApply;
    const auto outcome=e->outcome();
    if((!read && !apply) || outcome>CreatureExpelOutcome::Unknown ||
       (outcome==CreatureExpelOutcome::Ready && !read) ||
       ((outcome==CreatureExpelOutcome::Applied || outcome==CreatureExpelOutcome::Unknown) && !apply) ||
       ((outcome==CreatureExpelOutcome::Ready || outcome==CreatureExpelOutcome::Applied)!=(s.status()==ManagementStatus::Ok)) ||
       (outcome==CreatureExpelOutcome::Ready)!=(e->preview()!=nullptr))return "invalid creature expel outcome";
    if(const auto* p=e->preview()) {
      if(p->unit_id()<0 || p->reason() < -1 || p->reason()>10 || !p->units() || !p->destinations() ||
         p->units()->size()>4096 || p->destinations()->size()>4096 ||
         (!p->eligible() && (p->reason()!=-1 || p->units()->size() || p->destinations()->size())) ||
         (p->reason()!=-1 && p->destinations()->size()))return "invalid creature expel preview";
      size_t bytes=128;int32_t previous=-1;bool selected=false;
      for(const auto* row:*p->units()) {
        if(!row || row->id()<=previous || !row->name() || row->name()->size()>1536 ||
           row->name()->str().find('\0')!=std::string::npos || !row->name_color() || !row->sheet_icon())return "invalid creature expel unit";
        previous=row->id();selected|=row->id()==p->unit_id();bytes+=128+row->name()->size();
        const auto* c=row->name_color();
        if(c->foreground()>7 || c->background()>7 || c->bright()>1 || c->alternate_foreground()>7 ||
           c->alternate_background()>7 || c->alternate_bright()>1 || c->effect()>3)return "invalid creature expel color";
        if(auto error=validateOwnerAppearance(*row->sheet_icon(),bytes))return error;
      }
      if(p->eligible() && p->reason()==-1 && !selected)return "creature expel selected unit missing";
      previous=-2;
      for(const auto* row:*p->destinations()) {
        if(!row || row->id() < -1 || row->id()<=previous || !row->name() || row->name()->size()>1536 ||
           row->name()->str().find('\0')!=std::string::npos || (row->id()==-1 && row->name()->size()))return "invalid creature expel destination";
        previous=row->id();bytes+=64+row->name()->size();
      }
      if(p->destinations()->size() && (p->destinations()->size()<2 || p->destinations()->Get(0)->id()!=-1))return "invalid creature expel destination choices";
      if(bytes>320*1024)return "creature expel preview too large";
    }
  } else if((s.action()==ManagementAction::CreatureExpelRead || s.action()==ManagementAction::CreatureExpelApply) &&
            s.status()==ManagementStatus::Ok)return "creature expel result required";
  if(const auto* w=s.creature_workshop()) {
    if(s.action()!=ManagementAction::CreatureWorkshopRemove || w->unit_id()<0 || w->building_id()<0 ||
       w->outcome()>CreatureWorkshopOutcome::Unavailable)return "invalid creature workshop result";
    const bool applied=w->outcome()==CreatureWorkshopOutcome::Applied;
    if((applied && s.status()!=ManagementStatus::Ok) || (!applied && s.status()!=ManagementStatus::Rejected))
      return "invalid creature workshop outcome";
  } else if(s.action()==ManagementAction::CreatureWorkshopRemove && s.status()==ManagementStatus::Ok)
    return "creature workshop result required";
  if(const auto* w=s.creature_location()) {
    if(s.action()!=ManagementAction::CreatureLocationRemove || w->unit_id()<0 || w->occupation_id()<0 ||
       w->outcome()>CreatureLocationOutcome::Unknown)return "invalid creature location result";
    const bool applied=w->outcome()==CreatureLocationOutcome::Applied;
    if((applied && s.status()!=ManagementStatus::Ok) || (!applied && s.status()!=ManagementStatus::Rejected))
      return "invalid creature location outcome";
  } else if(s.action()==ManagementAction::CreatureLocationRemove && s.status()==ManagementStatus::Ok)
    return "creature location result required";
  if(const auto* r=s.residents()) {
    if((s.action()!=ManagementAction::ResidentsQuery && s.action()!=ManagementAction::WorkDetailWorkersQuery) || s.status()!=ManagementStatus::Ok ||
       !r->unit_ids() || r->unit_ids()->size()>kResidentsQueryUnits)return "invalid residents result";
    std::unordered_set<int32_t> ids;
    for(auto id:*r->unit_ids())if(id<0 || !ids.insert(id).second)return "invalid residents identity";
  } else if((s.action()==ManagementAction::ResidentsQuery || s.action()==ManagementAction::WorkDetailWorkersQuery) && s.status()==ManagementStatus::Ok)
    return "residents result required";
  if(const auto* r=s.nobles()) {
    const bool read=s.action()==ManagementAction::NoblesRead,candidates=s.action()==ManagementAction::NoblesCandidates;
    const bool symbols=s.action()==ManagementAction::NoblesSymbolsRead,name=s.action()==ManagementAction::NoblesSymbolNameRead;
    const bool symbolStep=s.action()==ManagementAction::NoblesSymbolsApply || s.action()==ManagementAction::NoblesSymbolsContinue;
    const bool commit=s.action()==ManagementAction::NoblesCommit || s.action()==ManagementAction::NoblesAccounting || symbolStep || s.action()==ManagementAction::NoblesSymbolNameEdit || s.action()==ManagementAction::NoblesSymbolsRetire;
    if((!read && !candidates && !symbols && !name && !commit) || !r->rows() || r->rows()->size()>64 || r->outcome()>NoblesOutcome::Unknown)return "invalid nobles result";
    const auto candidateCount=r->candidates()?r->candidates()->size():0;
    const auto symbolCount=r->symbols()?r->symbols()->size():0;
    if(symbols && s.status()==ManagementStatus::Ok){if(!r->symbol_target_caption() || r->symbol_target_caption()->size()>16384)return "invalid nobles symbol target caption";}
    else if(r->symbol_target_caption())return "unexpected nobles symbol target caption";
    if((!symbols && symbolCount) || (!name && r->name()) || ((!name && !symbolStep) && r->step()) ||
       (s.status()!=ManagementStatus::Ok && (symbolCount || r->step() || r->name())))return "unexpected nobles symbol payload";
    if(const auto* step=r->step())if(!step->token() || step->token()>INT64_MAX || step->naming_artifact_id()<0 || step->remaining()>4096)return "invalid nobles symbol step";
    if(name && s.status()==ManagementStatus::Ok){
      if(r->outcome()!=NoblesOutcome::None || !r->name() || !r->step() || r->list_revision() || r->total() || r->offset() || r->rows()->size() || r->target() || r->candidate_revision() || candidateCount)return "invalid nobles name payload";
      const auto& n=*r->name();
      if(n.artifact_id()!=r->step()->naming_artifact_id() || n.item_id()<0 || !n.revision() || n.revision()>INT64_MAX || !n.value() ||
         !n.native_header() || !n.english_header() || n.native_header()->size()>kLocationNameHeaderBytes || n.english_header()->size()>kLocationNameHeaderBytes)return "invalid nobles name identity";
      if(auto error=validateLocationNameValue(*n.value()))return error;
      if(n.component()>6 || !n.query_bytes() || n.query_bytes()->size()>kLocationNameBytes || !n.choices() || n.choices()->size()>kLocationNamePageRows || n.cursor()>n.total())return "invalid nobles name page";
      const uint64_t end=uint64_t(n.cursor())+n.choices()->size();
      if(end>n.total() || n.next_cursor()!=(end<n.total()?end:0) || (end<n.total() && !n.choices()->size()))return "invalid nobles name pagination";
      size_t bytes=512+n.query_bytes()->size()+n.value()->first_name_bytes()->size()+n.value()->nickname_bytes()->size()+n.native_header()->size()+n.english_header()->size();
      for(const auto* c:*n.choices()){
        if(!c || c->word()<0 || c->part()<0 || c->part()>8 || !c->english() || !c->translated())return "invalid nobles name choice";
        bytes+=64+uint64_t(c->english()->size())+c->translated()->size();
      }
      if(bytes>kLocationNamePageBytes)return "nobles name page too large";
    }else if(s.status()==ManagementStatus::Ok && !commit){
      const auto count=symbols?symbolCount:candidates?candidateCount:r->rows()->size();
      if(r->outcome()!=NoblesOutcome::None || !r->list_revision() || r->list_revision()>INT64_MAX || r->total()>((candidates || symbols)?1048576u:65536u) ||
         r->offset()>r->total() || count>r->total()-r->offset() || (r->offset()<r->total() && !count))return "invalid nobles page";
      if(candidates || symbols){
        if(!validNoblesOffice(r->target(),4096) || !r->candidate_revision() || r->candidate_revision()>INT64_MAX || (symbols?!r->symbols():!r->candidates()) || r->rows()->size())return "invalid nobles candidate page";
        if(symbols && (candidateCount || r->target()->assignment_id()<0 || r->target()->draft_slot()))return "invalid nobles symbol page";
      }else if(r->target() || r->candidate_revision() || candidateCount)return "unexpected nobles candidates";
    }else{
      if(r->list_revision() || r->total() || r->offset() || r->rows()->size() || r->target() || r->candidate_revision() || candidateCount)return "unexpected nobles terminal payload";
      if(commit){
        if(!((s.status()==ManagementStatus::Ok && r->outcome()==NoblesOutcome::Applied) ||
             (s.status()==ManagementStatus::Rejected && (r->outcome()==NoblesOutcome::Rejected || r->outcome()==NoblesOutcome::Stale || r->outcome()==NoblesOutcome::Unknown))))return "invalid nobles commit outcome";
      }else if(s.status()!=ManagementStatus::Rejected || (r->outcome()!=NoblesOutcome::Rejected && r->outcome()!=NoblesOutcome::Stale))return "invalid nobles refusal";
    }
    size_t bytes=r->symbol_target_caption()?r->symbol_target_caption()->size():0;std::set<std::tuple<int32_t,int32_t,int32_t,uint32_t>> ids;
    for(const auto* row:*r->rows()){
      if(!row || row->entity_id()<0 || row->position_id()<0 || row->assignment_id()<-1 || row->unit_id()<-1 || row->nemesis_id()<-1 ||
         !ids.emplace(row->entity_id(),row->position_id(),row->assignment_id(),row->draft_slot()).second || row->draft_slot()>4096 ||
         (row->assignment_id()>=0 && row->draft_slot()) || row->demand_status()<-1 || row->demand_status()>3 ||
         row->mandate_status()<-1 || row->mandate_status()>3 || row->has_room_assessment()!=(row->unit_id()>=0))return "invalid nobles identity or status";
      bytes+=192;
      for(const auto* text:{row->title(),row->squad_caption(),row->holder_caption()}){
        if(!text || text->size()>16384)return "invalid nobles caption";bytes+=text->size();}
      for(const auto* values:{row->required_rooms(),row->actual_rooms(),row->required_furniture(),row->actual_furniture()}){
        if(!values || values->size()!=4)return "invalid nobles assessment";
        if(!row->has_room_assessment())for(auto value:*values)if(value)return "unexpected nobles assessment";
      }
      if(!row->has_room_assessment() && (row->demand_status()!=-1 || row->mandate_status()!=-1))return "unexpected nobles obligation";
      if(const auto* a=row->appearance()){
        size_t recipe=0;if(auto error=validateOwnerAppearance(*a,recipe))return error;
        if(row->unit_id()<0 || a->layers()->size()==0 || recipe>131072)return "invalid nobles appearance";
        bytes+=recipe;
      }
      if(row->help())if(auto error=validateNoblesHelp(*row->help(),row->unit_id()>=0,bytes))return error;
      if(bytes>384*1024)return "nobles page payload exceeded";
    }
    if(candidateCount>64)return "too many nobles candidates";
    if(symbolCount>64)return "too many nobles symbols";
    std::set<int32_t> symbolIds;
    if(r->symbols())for(const auto* row:*r->symbols()){
      if(!row || row->item_id()<0 || row->item_type()<0 || row->item_type()>92 || (row->artifact_mood() && row->item_type()!=24) || !symbolIds.insert(row->item_id()).second ||
         (row->current_office() && !validNoblesOffice(row->current_office(),4096)) ||
         (row->selected_office() && !validNoblesOffice(row->selected_office(),4096)))return "invalid nobles symbol";
      bytes+=128;
      for(const auto* text:{row->caption(),row->office_caption(),row->value_caption()}){if(!text || text->size()>16384)return "invalid nobles symbol text";bytes+=text->size();}
      if(const auto* a=row->appearance()){
        if(!validInspectionInstrument(*a,row->item_type()) || !a->material_token() || !a->material_token()->size() || a->material_token()->size()>256 ||
           !a->subtype_raw() || a->subtype_raw()->size()>128 || !a->color_token() || a->color_token()->size()>128 || a->stack()<1 || (a->flags()&~96))return "invalid nobles symbol appearance";
        bytes+=256+a->material_token()->size()+a->subtype_raw()->size()+a->color_token()->size();
        size_t recipe=0;
        for(const auto* p:{a->portrait(),a->corpse_selector(),a->cage_occupant(),a->legwear_selector()})if(p)if(auto error=validateOwnerAppearance(*p,recipe))return error;
        bytes+=recipe;
        for(const auto* text:{a->restraint_solid_color(),a->cage_solid_color(),a->bucket_liquid_color(),a->craft_gem_color()})if(text)bytes+=text->size();
        if(const auto* c=a->contents()){
          bytes+=64;if(c->solid_color())bytes+=c->solid_color()->size();
          for(const auto* e:*c->entries())bytes+=64+e->material_token()->size()+e->color_token()->size();
        }
      }
      if(bytes>384*1024)return "nobles page payload exceeded";
    }
    std::set<int32_t> candidateIds;
    if(r->candidates())for(const auto* row:*r->candidates()){
      if(!row || row->unit_id()<-1 || !candidateIds.emplace(row->unit_id()).second || !row->caption() || !row->no_skills() || !row->skills() || row->skills()->size()>4096)return "invalid nobles candidate";
      bytes+=64;
      for(const auto* text:{row->caption(),row->no_skills()}){if(text->size()>16384)return "invalid nobles candidate text";bytes+=text->size();}
      if(row->unit_id()<0 && (row->skills()->size() || row->no_skills()->size() || row->appearance()))return "invalid vacant candidate";
      if(row->unit_id()>=0 && (row->skills()->size()==0)!=(row->no_skills()->size()!=0))return "invalid nobles skill fallback";
      std::set<int16_t> skills;
      for(const auto* skill:*row->skills()){
        if(!skill || skill->id()<0 || skill->rating()<=0 || !skills.emplace(skill->id()).second || !skill->caption() || skill->caption()->size()>16384)return "invalid nobles candidate skill";
        bytes+=16+skill->caption()->size();
      }
      if(const auto* a=row->appearance()){
        size_t recipe=0;if(auto error=validateOwnerAppearance(*a,recipe))return error;
        if(a->layers()->size()==0 || recipe>131072)return "invalid nobles candidate appearance";
        bytes+=recipe;
      }
      if(bytes>384*1024)return "nobles page payload exceeded";
    }
  }else if(s.status()==ManagementStatus::Ok && s.action()>=ManagementAction::NoblesRead && s.action()<=ManagementAction::NoblesSymbolsRetire)return "missing nobles result";
  if(const auto* r=s.justice()) {
    const bool read=s.action()==ManagementAction::JusticeRead,detail=s.action()==ManagementAction::JusticeCaseRead;
    if((!read && !detail) || r->tab()>2 || r->outcome()>JusticeOutcome::Stale || !r->rows() || r->rows()->size()>64)return "invalid justice result";
    const auto page=[](uint32_t total,uint32_t offset,size_t count){return total<=1048576 && offset<=total && count<=64 && count<=total-offset && (offset==total || count!=0);};
    size_t bytes=0;
    const auto text=[&](const flatbuffers::String* value){if(!value || value->size()>16384)return false;bytes+=value->size();return bytes<=384*1024;};
    if(s.status()==ManagementStatus::Ok){
      if(r->outcome()!=JusticeOutcome::None || !r->list_revision() || r->list_revision()>INT64_MAX)return "invalid justice revision";
      if(read){
        if(r->detail() || !page(r->total(),r->offset(),r->rows()->size()))return "invalid justice page";
      }else{
        const auto* d=r->detail();
        if(r->total() || r->offset() || r->rows()->size() || !d || d->crime_id()<0 || !d->revision() || d->revision()>INT64_MAX ||
          d->resolution()==JusticeCaseResolution::None || d->resolution()>JusticeCaseResolution::UnknownConvict || !d->witnesses() || !page(d->total(),d->offset(),d->witnesses()->size()) || !text(d->caption()) || !text(d->status()) ||
          (d->injured_party() && !text(d->injured_party())))return "invalid justice case";
        for(const auto* w:*d->witnesses()){
          bytes+=64;
          if(!w || !text(w->witness()) || !text(w->description()) || !text(w->date()) || !text(w->reported()))return "invalid justice witness";
        }
      }
    }else if(s.status()!=ManagementStatus::Rejected || r->outcome()==JusticeOutcome::None || r->list_revision() || r->total() || r->offset() || r->rows()->size() || r->detail())return "invalid justice refusal";
    std::unordered_set<int32_t> ids;
    for(const auto* row:*r->rows()){
      bytes+=32;
      if(!row || row->crime_id()<0 || !ids.insert(row->crime_id()).second || !text(row->caption()))return "invalid justice row";
    }
  }else if(s.status()==ManagementStatus::Ok && (s.action()==ManagementAction::JusticeRead || s.action()==ManagementAction::JusticeCaseRead))return "missing justice result";
  if(const auto* r=s.objects()) {
    const bool read=s.action()==ManagementAction::ObjectsRead,locate=s.action()==ManagementAction::ObjectsLocate;
    if((!read && !locate) || r->tab()>3 || !r->rows() || r->rows()->size()>64 ||
      r->outcome()>ObjectsOutcome::Stale)return "invalid objects result";
    const auto validPosition=[](const TilePos* p){return !p || (p->x()>=0 && p->y()>=0 && p->z()>=0 && p->x()<=32767 && p->y()<=32767 && p->z()<=32767);};
    if(s.status()==ManagementStatus::Ok){
      if(r->outcome()!=ObjectsOutcome::None || !r->list_revision() || r->list_revision()>INT64_MAX)return "invalid objects revision";
      if(read){
        if(r->destination() || r->total()>1048576 || r->offset()>r->total() || r->rows()->size()>r->total()-r->offset() ||
          (r->offset()<r->total() && !r->rows()->size()))return "invalid objects page";
      }else{
        const auto* d=r->destination();
        if(r->total() || r->offset() || r->rows()->size() || !d || d->artifact_id()<0 || d->item_id()<0 || !validPosition(d->position()))return "invalid objects destination";
      }
    }else if(s.status()!=ManagementStatus::Rejected || r->outcome()==ObjectsOutcome::None ||
      r->list_revision() || r->total() || r->offset() || r->rows()->size() || r->destination())return "invalid objects refusal";
    size_t bytes=0;std::unordered_set<int32_t> ids;
    for(const auto* row:*r->rows()){
      if(!row || row->artifact_id()<0 || row->item_id()<0 || row->item_type()<-1 || row->item_type()>92 || !ids.insert(row->artifact_id()).second || !validPosition(row->position()))return "invalid objects row";
      bytes+=128;
      for(const auto* text:{row->native_name(),row->translated_name(),row->ownership()}){
        if(!text || text->size()>16384)return "invalid objects caption";bytes+=text->size();}
      if(const auto* a=row->appearance()){
        if(row->item_type()<0 || !validInspectionInstrument(*a,row->item_type()) || !a->material_token() || !a->material_token()->size() || a->material_token()->size()>256 ||
           !a->subtype_raw() || a->subtype_raw()->size()>128 || !a->color_token() || a->color_token()->size()>128 || a->stack()<1 || (a->flags()&~96))return "invalid objects appearance";
        bytes+=256+a->material_token()->size()+a->subtype_raw()->size()+a->color_token()->size();
        size_t recipe=0;
        for(const auto* p:{a->portrait(),a->corpse_selector(),a->cage_occupant(),a->legwear_selector()})if(p)if(auto error=validateOwnerAppearance(*p,recipe))return error;
        bytes+=recipe;
        for(const auto* text:{a->restraint_solid_color(),a->cage_solid_color(),a->bucket_liquid_color(),a->craft_gem_color()})if(text)bytes+=text->size();
        if(const auto* c=a->contents()){
          bytes+=64;if(c->solid_color())bytes+=c->solid_color()->size();
          for(const auto* e:*c->entries())bytes+=64+e->material_token()->size()+e->color_token()->size();
        }
      }
      if(bytes>384*1024)return "objects page payload exceeded";
    }
  }else if(s.status()==ManagementStatus::Ok && (s.action()==ManagementAction::ObjectsRead || s.action()==ManagementAction::ObjectsLocate))return "missing objects result";
  if(const auto* r=s.places()) {
    const bool read=s.action()==ManagementAction::PlacesRead,apply=s.action()==ManagementAction::PlacesApply;
    if((!read && !apply) || r->tab()>5 || !r->rows() ||
      r->rows()->size()>64 || r->outcome()>PlacesOutcome::Unknown)return "invalid places result";
    if(apply){
      if(r->tab()!=5 || r->building_id()<-1 || r->siege_action()<0 || r->siege_action()>4 ||
        r->list_revision() || r->total() || r->offset() || r->rows()->size() ||
        (s.status()==ManagementStatus::Ok ? r->outcome()!=PlacesOutcome::Applied :
          s.status()!=ManagementStatus::Rejected || (r->outcome()!=PlacesOutcome::Rejected && r->outcome()!=PlacesOutcome::Stale && r->outcome()!=PlacesOutcome::Unknown)))return "invalid places receipt";
    }else if(r->building_id()!=-1 || r->siege_action()!=-1 || r->outcome()>PlacesOutcome::Stale)return "invalid places read result";
    else if(s.status()==ManagementStatus::Ok){
      if(r->outcome()!=PlacesOutcome::None || !r->list_revision() || r->list_revision()>INT64_MAX ||
        r->total()>1048576 || r->offset()>r->total() || r->rows()->size()>r->total()-r->offset() ||
        (r->offset()<r->total() && !r->rows()->size()))return "invalid places page";
    }else if(s.status()!=ManagementStatus::Rejected || r->outcome()==PlacesOutcome::None ||
      r->list_revision() || r->total() || r->offset() || r->rows()->size())return "invalid places refusal";
    size_t bytes=0;std::unordered_set<int32_t> ids;
    for(const auto* row:*r->rows()){
      if(!row || row->building_id()<0 || !ids.insert(row->building_id()).second ||
        row->subtitle_location_id()<-1 || (r->tab()!=0 && row->subtitle_location_id()!=-1) ||
        row->additional_jobs()<0 || row->additional_jobs()>1048576 ||
        (r->tab()==5 ? row->siege_action()<0 || row->siege_action()>4 : row->siege_action()!=-1))return "invalid places row";
      bytes+=128;
      for(const auto* text:{row->name(),row->subtitle(),row->job_caption(),row->status_caption(),row->secondary_status(),row->status_overlay(),row->operator_caption()}){
        if(!text || text->size()>16384)return "invalid places caption";bytes+=text->size();}
      if(const auto* p=row->position())if(p->x()<0 || p->y()<0 || p->z()<0 || p->x()>32767 || p->y()>32767 || p->z()>32767)return "invalid places position";
      if(const auto* a=row->appearance()){
        size_t recipe=0;if(auto error=validateOwnerAppearance(*a,recipe))return error;
        if(!a->layers()->size() || recipe>131072)return "invalid places artwork";bytes+=recipe;
      }
      if(bytes>384*1024)return "places page payload exceeded";
    }
  }else if(s.status()==ManagementStatus::Ok && (s.action()==ManagementAction::PlacesRead || s.action()==ManagementAction::PlacesApply))return "missing places result";
  if(const auto* r=s.tasks()) {
    const bool read=s.action()==ManagementAction::TasksRead,apply=s.action()==ManagementAction::TasksApply;
    if((!read && !apply) || !r->rows() || r->rows()->size()>64 || r->outcome()>TasksOutcome::Unknown)return "invalid tasks result";
    if(s.status()==ManagementStatus::Ok){
      if(read){
        if(r->outcome()!=TasksOutcome::None || !r->list_revision() || r->list_revision()>INT64_MAX || r->total()>1048576 ||
          r->offset()>r->total() || r->rows()->size()>r->total()-r->offset() ||
          (r->offset()<r->total() && r->rows()->size()==0) || r->job_id()!=-1)return "invalid tasks page";
      }else if(r->outcome()!=TasksOutcome::Applied || r->job_id()<0 || r->list_revision() || r->total() || r->offset() || r->rows()->size())return "invalid tasks receipt";
    }else if(s.status()!=ManagementStatus::Rejected || r->list_revision() || r->total() || r->offset() || r->rows()->size() ||
      (read?r->job_id()!=-1:r->job_id()<0) || (r->outcome()!=TasksOutcome::Rejected && r->outcome()!=TasksOutcome::Stale && (!apply || r->outcome()!=TasksOutcome::Unknown)))return "invalid tasks refusal";
    size_t bytes=0;std::unordered_set<int32_t> ids;
    for(const auto* row:*r->rows()){
      if(!row || row->job_id()<0 || !ids.insert(row->job_id()).second || row->worker_id()<-1 || row->building_id()<-1 ||
        !row->revision() || row->revision()>INT64_MAX || !row->caption() || row->caption()->size()>16384 ||
        !row->worker_name() || row->worker_name()->size()>16384 || !row->building_caption() || row->building_caption()->size()>16384)return "invalid tasks row";
      bytes+=128+row->caption()->size()+row->worker_name()->size()+row->building_caption()->size();
      if((row->worker_id()<0 && (row->worker_name()->size() || row->worker_color() || row->worker_position() || row->worker_appearance() || row->can_remove_worker())) ||
        (row->building_id()<0 && (row->building_caption()->size() || row->building_position() || row->building_appearance() || row->can_repeat() || row->can_suspend() || row->can_cancel() || row->can_remove_worker())) ||
        (row->worker_id()>=0 && !row->worker_color()))return "invalid tasks row ownership";
      for(const auto* p:{row->worker_position(),row->building_position()})if(p && (p->x()<0 || p->y()<0 || p->z()<0 || p->x()>32767 || p->y()>32767 || p->z()>32767))return "invalid tasks position";
      if(const auto* c=row->worker_color())if(c->foreground()>7 || c->background()>7 || c->bright()>1 || c->alternate_foreground()>7 || c->alternate_background()>7 || c->alternate_bright()>1 || c->effect()>3)return "invalid tasks color";
      for(const auto* a:{row->worker_appearance(),row->building_appearance()})if(a){
        size_t recipe=0;if(auto error=validateOwnerAppearance(*a,recipe))return error;
        if(!a->layers()->size() || recipe>131072)return "invalid tasks artwork";bytes+=recipe;
      }
      if(bytes>384*1024)return "tasks page payload exceeded";
    }
  }else if(s.status()==ManagementStatus::Ok && (s.action()==ManagementAction::TasksRead || s.action()==ManagementAction::TasksApply))return "missing tasks result";
  if(const auto* r=s.stocks_menu()) {
    const bool read=s.action()==ManagementAction::StocksMenuRead,apply=s.action()==ManagementAction::StocksGroupApply || s.action()==ManagementAction::StocksItemApply;
    if((!read && !apply) || !r->categories() || !r->groups() || !r->items() || r->category()<-1 || r->category()>=93)return "invalid stocks result";
    if(s.status()==ManagementStatus::Ok){
      if(r->outcome()!=(read?StocksMenuOutcome::None:StocksMenuOutcome::Applied) || r->categories()->size()!=93 || r->groups()->size()>65536 || r->items()->size()>64)return "invalid stocks success";
      std::unordered_set<int16_t> types;
      for(const auto* row:*r->categories())if(!row || row->type()<0 || row->type()>=93 || !types.insert(row->type()).second ||
        !row->caption() || !row->caption()->size() || row->caption()->size()>16384 || !row->stored() || !row->stored()->size() || row->stored()->size()>64 || !row->unavailable() || row->unavailable()->size()>64)return "invalid stocks category";
      std::set<std::tuple<int16_t,int16_t,int16_t>> keys;std::unordered_set<int32_t> members;
      for(const auto* row:*r->groups()){
        if(!row || !validStocksKey(row->key()) || row->key()->type()!=r->category() || !row->revision() || row->revision()>INT64_MAX ||
          !row->caption() || !row->caption()->size() || row->caption()->size()>16384 || !row->item_ids() || !row->item_ids()->size() || row->item_ids()->size()>1048576 ||
          !keys.emplace(row->key()->subtype(),row->key()->subcat1(),row->key()->subcat2()).second)return "invalid stocks group";
        for(auto id:*row->item_ids())if(id<0 || !members.insert(id).second || members.size()>1048576)return "invalid stocks membership";
      }
      std::unordered_set<int32_t> rows;
      for(const auto* row:*r->items())if(!row || row->type()!=r->category() || !members.count(row->id()) || !rows.insert(row->id()).second ||
        !row->caption() || !row->caption()->size() || row->caption()->size()>16384 || !row->material_token() || row->material_token()->size()>256 || !row->subtype_raw() || row->subtype_raw()->size()>256)return "invalid stocks item";
      for(const auto* row:*r->items())if(const auto* a=row->appearance())
        if(!validInspectionInstrument(*a,row->type()) || !a->material_token() || !a->material_token()->size() || a->material_token()->size()>256 ||
          !a->subtype_raw() || a->subtype_raw()->size()>128 || !a->color_token() || a->color_token()->size()>128 || a->stack()<1 || (a->flags()&~96) ||
          a->material_token()->str()!=row->material_token()->str() || a->subtype_raw()->str()!=row->subtype_raw()->str())return "invalid stocks appearance";
      if(r->category()==-1 && (r->groups()->size() || r->items()->size()))return "unexpected unselected stocks rows";
    }else if(s.status()!=ManagementStatus::Rejected || r->category()!=-1 || r->categories()->size() || r->groups()->size() || r->items()->size() ||
      (r->outcome()!=StocksMenuOutcome::Rejected && (!apply || (r->outcome()!=StocksMenuOutcome::Stale && r->outcome()!=StocksMenuOutcome::Unknown))))return "invalid stocks refusal";
  }else if(s.status()==ManagementStatus::Ok && (s.action()==ManagementAction::StocksMenuRead || s.action()==ManagementAction::StocksGroupApply || s.action()==ManagementAction::StocksItemApply))return "missing stocks result";
  if(const auto* r=s.stone_use()) {
    const bool read=s.action()==ManagementAction::StoneUseRead,apply=s.action()==ManagementAction::StoneUseApply;
    if((!read && !apply) || !r->rows() || r->rows()->size()>65536 || !validStoneRestrictions(r->restrictions()))return "invalid stone use result";
    if(s.status()==ManagementStatus::Ok){
      if(r->outcome()!=(read?StoneUseOutcome::None:StoneUseOutcome::Applied))return "invalid stone use success";
      if(apply && (r->rows()->size() || r->restrictions()->size()))return "unexpected stone use edit data";
      std::unordered_set<int32_t> seen;
      for(const auto* row:*r->rows()){
        if(!row || row->category()<0 || row->category()>1 || row->index()<0 || uint32_t(row->index())>=r->restrictions()->size() ||
          !seen.insert(row->index()).second || row->restricted()!=(r->restrictions()->Get(row->index())!=0) ||
          !row->name() || !row->name()->size() || row->name()->size()>16384 || !row->uses() || row->uses()->size()>65536 ||
          (row->category()==1 && row->uses()->size()) || !row->material_token() || !row->material_token()->size() || row->material_token()->size()>256)return "invalid stone use row";
      }
    }else if(s.status()!=ManagementStatus::Rejected || r->rows()->size() || r->restrictions()->size() ||
      (r->outcome()!=StoneUseOutcome::Rejected && (!apply || (r->outcome()!=StoneUseOutcome::Stale && r->outcome()!=StoneUseOutcome::Unknown))))return "invalid stone use refusal";
  }else if(s.status()==ManagementStatus::Ok && (s.action()==ManagementAction::StoneUseRead || s.action()==ManagementAction::StoneUseApply))return "missing stone use result";
  if(const auto* r=s.kitchen_menu()) {
    const bool read=s.action()==ManagementAction::KitchenRead,apply=s.action()==ManagementAction::KitchenApply;
    if((!read && !apply) || !r->rows() || !validKitchenExclusions(r->exclusions()) || r->rows()->size()>65536)return "invalid kitchen result";
    if(s.status()==ManagementStatus::Ok){
      if(r->outcome()!=(read?KitchenMenuOutcome::None:KitchenMenuOutcome::Applied))return "invalid kitchen success";
      if(apply && (r->rows()->size() || r->exclusions()->size()))return "unexpected kitchen edit data";
      for(const auto* row:*r->rows())if(!row || !validKitchenReceipt(row->receipt()) || !row->name() || row->name()->size()>16384 ||
        !row->count_caption() || !row->count_caption()->size() || row->count_caption()->size()>64 || row->excluded()>3 ||
        !row->material_token() || row->material_token()->size()>256)return "invalid kitchen row";
    }else if(s.status()!=ManagementStatus::Rejected || r->rows()->size() || r->exclusions()->size() ||
      (r->outcome()!=KitchenMenuOutcome::Rejected && (!apply || (r->outcome()!=KitchenMenuOutcome::Stale && r->outcome()!=KitchenMenuOutcome::Unknown))))return "invalid kitchen refusal";
  }else if(s.status()==ManagementStatus::Ok && (s.action()==ManagementAction::KitchenRead || s.action()==ManagementAction::KitchenApply))return "missing kitchen result";
  if(const auto* r=s.chores()) {
    const bool read=s.action()==ManagementAction::ChoresRead,apply=s.action()==ManagementAction::ChoresApply;
    if((!read && !apply) || !r->children() || !r->labors())return "invalid chores result";
    if(s.status()==ManagementStatus::Ok){
      if(r->outcome()!=(read?ChoresOutcome::None:ChoresOutcome::Applied) || !validChoresSnapshot(r->snapshot()))return "invalid chores success";
      if(read){
        if(r->children()->size()!=r->snapshot()->children()->size() || r->labors()->size()!=14)return "incomplete chores captions";
        size_t i=0;for(const auto* row:*r->children())if(!row || row->id()!=r->snapshot()->children()->Get(i++) || !row->caption() || !row->caption()->size() || row->caption()->size()>16384)return "invalid chores child caption";
        i=0;for(const auto* row:*r->labors())if(!row || row->id()!=r->snapshot()->labors()->Get(i++)->id() || !row->caption() || !row->caption()->size() || row->caption()->size()>2048)return "invalid chores labor caption";
      }else if(r->children()->size() || r->labors()->size())return "unexpected chores edit captions";
    }else if(s.status()!=ManagementStatus::Rejected || r->snapshot() || r->children()->size() || r->labors()->size() ||
      (r->outcome()!=ChoresOutcome::Rejected && (!apply || (r->outcome()!=ChoresOutcome::Stale && r->outcome()!=ChoresOutcome::Unknown))))return "invalid chores refusal";
  }else if(s.status()==ManagementStatus::Ok && (s.action()==ManagementAction::ChoresRead || s.action()==ManagementAction::ChoresApply))return "missing chores result";
  if(const auto* r=s.hunter_ammunition()) {
    using O=HunterAmmunitionOutcome;
    const bool read=s.action()==ManagementAction::HunterAmmunitionRead,choices=s.action()==ManagementAction::HunterAmmunitionCandidates,
      apply=s.action()==ManagementAction::HunterAmmunitionApply;
    if((!read && !choices && !apply) || !r->specs() || !r->rules() || !r->types() || !r->materials())return "invalid ammunition response";
    if(s.status()!=ManagementStatus::Ok){
      if(s.status()!=ManagementStatus::Rejected || (r->outcome()!=O::Rejected && (!apply || (r->outcome()!=O::Stale && r->outcome()!=O::Unknown))) ||
         r->specs()->size() || r->rules()->size() || r->types()->size() || r->materials()->size())return "invalid ammunition refusal";
    }else{
      if(r->outcome()!=(apply?O::Applied:O::None))return "invalid ammunition outcome";
      if(choices ? (r->item_type()!=39 || r->item_subtype()<0 || r->specs()->size() || r->rules()->size() || r->types()->size()) :
         (r->item_type()!=-1 || r->item_subtype()!=-1 || r->materials()->size()))return "invalid ammunition response scope";
      if(read ? r->rules()->size()!=r->specs()->size() : r->rules()->size()!=0)return "invalid ammunition rule details";
      if(apply && r->types()->size())return "unexpected ammunition edit choices";
      for(const auto* v:*r->specs())if(!validHunterSpec(v))return "invalid ammunition spec";
      for(const auto* v:*r->types())if(!v || v->item_type()!=39 || v->item_subtype()<0 || !v->caption())return "invalid ammunition type choice";
      for(const auto* v:*r->materials())if(!v || v->material_class()<-1 || v->mattype()<-1 || v->matindex()<-1 || !v->caption())return "invalid ammunition material choice";
      size_t index=0;for(const auto* row:*r->rules()){
        if(!row || !row->caption() || !row->items() || row->quantity()<0)return "invalid ammunition rule";
        int64_t quantity=0;int32_t prior=-1;const auto* assigned=r->specs()->Get(index++)->assigned();
        for(const auto* item:*row->items()){
          if(!item || item->id()<=prior || !item->caption() || item->quantity()<0 ||
             !std::binary_search(assigned->begin(),assigned->end(),item->id()))return "invalid ammunition assigned stack";
          prior=item->id();quantity+=item->quantity();
		  const auto* a=item->appearance();
		  if(!a || !a->material_token() || a->material_token()->size()==0 || a->material_token()->size()>256 ||
		     !a->subtype_raw() || a->subtype_raw()->size()>128 || !a->color_token() || a->color_token()->size()>128 ||
		     a->stack()<1 || a->stack()!=item->quantity() || (a->flags()&~96) || !validInspectionInstrument(*a,39))return "invalid ammunition appearance";
        }
        if(quantity!=row->quantity())return "ammunition quantity mismatch";
      }
    }
  }else if(s.status()==ManagementStatus::Ok && s.action()>=ManagementAction::HunterAmmunitionRead && s.action()<=ManagementAction::HunterAmmunitionApply)
    return "missing ammunition result";
  if(const auto* r=s.standing_orders()) {
    using O=StandingOrdersOutcome;
    const bool read=s.action()==ManagementAction::StandingOrdersRead,set=s.action()==ManagementAction::StandingOrdersSet;
    if((!read && !set) || !standingCategoryCount(r->category()) || !r->settings())return "invalid standing orders result";
    if(s.status()==ManagementStatus::Ok) {
      if(r->outcome()!=(read?O::None:O::Applied) || r->settings()->size()!=standingCategoryCount(r->category()))return "incomplete standing orders result";
      int id=0;for(const auto* row:*r->settings()) {
        if(!row || row->id()!=id || row->value()>standingValueMax(r->category(),id) || (row->editable() && !row->visible()) || (r->category()==0 && (row->visible()!=row->editable() || (id<6 && !row->visible()))) || (r->category()!=0 && r->category()!=2 && (!row->visible() || !row->editable())))return "invalid standing order setting";
        ++id;
      }
    } else if(s.status()!=ManagementStatus::Rejected || r->settings()->size()!=0 ||
              (r->outcome()!=O::Rejected && (!set || (r->outcome()!=O::Stale && r->outcome()!=O::Unknown))))return "invalid standing orders refusal";
  } else if((s.action()==ManagementAction::StandingOrdersRead || s.action()==ManagementAction::StandingOrdersSet) && s.status()==ManagementStatus::Ok)
    return "missing standing orders result";
  if(const auto* r=s.work_detail_settings()) {
    if((s.action()!=ManagementAction::WorkDetailSettingsRead && s.action()!=ManagementAction::WorkDetailSettingsToggle) ||
       s.status()!=ManagementStatus::Ok || r->detail_index()<0 || r->detail_index()>=128 || !r->revision() || r->revision()>INT64_MAX ||
       !r->labors() || r->labors()->size()>94 || !r->catalog() || r->catalog()->size()!=91)
      return "invalid work-detail settings result";
    int previous=-1;
    for(auto id:*r->labors()){if(id<0 || id>=94 || id<=previous)return "invalid settings labors";previous=id;}
    std::array<bool,107> seen{};int groups=0,labors=0;
    for(const auto* entry:*r->catalog()) {
      if(!entry || !entry->caption() || entry->caption()->size()==0 || entry->caption()->size()>512 ||
         !((entry->id()>=-13 && entry->id()<=-2) || (entry->id()>=1 && entry->id()<=93)))return "invalid settings catalog entry";
      const size_t slot=size_t(entry->id()+13);if(seen[slot])return "duplicate settings catalog entry";seen[slot]=true;
      if(entry->id()<0)++groups;else {if(groups==0)return "settings labor precedes its category";++labors;}
    }
    if(groups!=12 || labors!=79)return "incomplete settings catalog";
  } else if((s.action()==ManagementAction::WorkDetailSettingsRead || s.action()==ManagementAction::WorkDetailSettingsToggle) && s.status()==ManagementStatus::Ok)
    return "missing work-detail settings result";
  if(const auto* r=s.residents_rows()) {
    if((s.action()!=ManagementAction::ResidentsRowsRead && s.action()!=ManagementAction::WorkDetailRowsRead) || s.status()!=ManagementStatus::Ok ||
       !r->rows() || r->rows()->size()==0 || r->rows()->size()>kResidentsRowsLimit)return "invalid residents rows result";
    std::unordered_set<int32_t> ids;size_t bytes=0,appearanceBytes=0;
    for(const auto* row:*r->rows()) {
      if(!row || row->id()<0 || !ids.insert(row->id()).second || !row->name_color())return "invalid residents row";
      if(s.action()==ManagementAction::WorkDetailRowsRead) {
        if(!row->work_detail_skills() || row->work_detail_skills()->size()>149 || row->detail_member()<0 || row->detail_member()>1 ||
           row->happiness()!=-1 || row->activity_target() || row->job_target() || !row->activity() || row->activity()->size())return "invalid work detail row";
        std::unordered_set<int16_t> skills;
        for(const auto* skill:*row->work_detail_skills()) {
          if(!skill || skill->skill()<0 || skill->skill()>=149 || !skills.insert(skill->skill()).second || skill->rating()<=0 ||
             !skill->caption() || skill->caption()->size()>4096 || skill->caption()->str().find('\0')!=std::string::npos)return "invalid work detail skill";
          bytes+=skill->caption()->size();
        }
      } else if(row->work_detail_skills() || row->detail_member()!=-1)return "unexpected work detail row";

      for(const auto* text:{row->combined(),row->name(),row->profession(),row->first_line(),row->second_line(),row->activity()}) {
        if(!text || text->size()>4096 || text->str().find('\0')!=std::string::npos)return "invalid residents row text";
        bytes+=text->size();
      }
      if(const auto* entries=row->assignments()) {
        if(entries->size()>256)return "too many residents assignments";
        auto previous=LocationStaffAssignmentKind::Occupation;
        for(const auto* e:*entries) {
          if(!e || e->kind()>LocationStaffAssignmentKind::WorkDetail || e->kind()<previous || e->id()<0 || e->type()<-1 || e->subtype()<-1 || e->custom()<-1 ||
             !e->name() || e->name()->size()>4096 || !e->custom_code() || e->custom_code()->size()>64 ||
             e->name()->str().find('\0')!=std::string::npos || e->custom_code()->str().find('\0')!=std::string::npos)return "invalid residents assignment";
          const bool building=e->kind()==LocationStaffAssignmentKind::Workshop || e->kind()==LocationStaffAssignmentKind::Furnace;
          if(!building && (e->subtype()!=-1 || e->custom()!=-1))return "foreign residents assignment building fields";
          if(e->kind()!=LocationStaffAssignmentKind::WorkDetail && e->name()->size())return "foreign residents assignment name";
          if((building && e->custom()>=0)!=(e->custom_code()->size()>0))return "invalid residents assignment custom code";
          previous=e->kind();bytes+=e->name()->size()+e->custom_code()->size()+32;
        }
      }
      if(const auto* target=row->job_target()) {
        if(target->job_id()<0 || target->building_id()<0 || row->activity_target())return "invalid residents job target";
      }
      if(const auto* target=row->activity_target())
        if(target->activity_id()<0 || target->event_id()<0)return "invalid residents activity target";
      if(const auto* value=row->specialization())
        if(!value->revision() || value->revision()>INT64_MAX)return "invalid residents specialization receipt";
      if(row->happiness() < -1 || row->happiness()>6)return "invalid residents happiness";
      if(const auto* p=row->position())
        if(p->x()<INT16_MIN || p->x()>INT16_MAX || p->y()<INT16_MIN || p->y()>INT16_MAX || p->z()<INT16_MIN || p->z()>INT16_MAX)return "invalid residents position";
      const auto* c=row->name_color();
      if(const auto* icon=row->sheet_icon())if(auto error=validateOwnerAppearance(*icon,appearanceBytes))return error;
      if(c->foreground()>7 || c->background()>7 || c->bright()>1 || c->alternate_foreground()>7 ||
         c->alternate_background()>7 || c->alternate_bright()>1 || c->effect()>3 ||
         row->activity_foreground()>7 || row->activity_background()>7)return "invalid residents row color";
    }
    if(bytes>131072)return "residents row text budget exceeded";
    if(appearanceBytes>131072)return "residents row appearance budget exceeded";
  } else if((s.action()==ManagementAction::ResidentsRowsRead || s.action()==ManagementAction::WorkDetailRowsRead) && s.status()==ManagementStatus::Ok)
    return "residents rows result required";
  if(const auto* v=s.job_settings_edit()) {
    if(s.action()!=ManagementAction::JobSettingsApply || v->job_id()<0 || v->building_id()<0 || v->unit_id() < -1 ||
       v->outcome()<JobSettingsEditOutcome::Rejected || v->outcome()>JobSettingsEditOutcome::Unknown ||
       (s.status()!=ManagementStatus::Ok && s.status()!=ManagementStatus::Rejected) ||
       ((s.status()==ManagementStatus::Ok)!=(v->outcome()==JobSettingsEditOutcome::Applied)))return "invalid job settings edit result";
  } else if(s.action()==ManagementAction::JobSettingsApply && s.status()==ManagementStatus::Ok)return "job settings edit result required";
  if(const auto* v=s.job_settings()) {
    if((s.action()!=ManagementAction::JobSettingsRead && s.action()!=ManagementAction::JobSettingsApply) || s.status()!=ManagementStatus::Ok ||
       v->job_id()<0 || v->building_id()<0 || v->unit_id() < -1 || !v->revision() || v->revision()>INT64_MAX ||
       !v->caption() || v->caption()->size()>512 || !v->options() || v->options()->size()>65 ||
       v->selected_option() < -1 || (v->selected_option()>=0 && size_t(v->selected_option())>=v->options()->size()) ||
       !v->choices() || v->choices()->size()>64 || v->total()>16384 || v->cursor()>v->total() ||
       v->choices()->size()>v->total()-v->cursor() || (v->cursor()<v->total() && v->choices()->size()==0) ||
       v->next_cursor()!=(v->cursor()+v->choices()->size()<v->total()?v->cursor()+v->choices()->size():0))return "invalid job settings result";
    if((v->selected_option()<0 || v->art()) ? (v->choices_revision()!=0 || v->total()!=0 || v->cursor()!=0 || v->choices()->size()!=0) :
       (!v->choices_revision() || v->choices_revision()>INT64_MAX))return "invalid job settings choice revision";
    for(const auto* o:*v->options())if(!o || o->kind()>6 || o->index() < -1 || !o->caption() || o->caption()->size()>512)return "invalid job settings option";
    if(const auto* a=v->art()) {
      if(v->selected_option()<0 || (v->options()->Get(v->selected_option())->kind()!=1 && v->options()->Get(v->selected_option())->kind()!=3) ||
         (a->page()!=-1 && a->page()!=1 && a->page()!=2 && a->page()!=3 && a->page()!=5 && (a->page()<6 || a->page()>18)) ||
         !a->caption() || a->caption()->size()>512 || !a->rows() || a->rows()->size()>128 || a->total()>262144 || a->rows()->size()>a->total() ||
         a->next_cursor()>a->total() || (a->next_cursor() && (a->next_cursor()>=a->total() || !a->rows()->size())) ||
         a->hovered() < -1)return "invalid job artwork page";
      if(a->page()==-1 ? (a->list_revision()!=0 || a->total()!=6 || a->rows()->size()!=6 || a->next_cursor()!=0 || a->hovered()!=-1 || a->preview()!=nullptr) :
         (!a->list_revision() || a->list_revision()>INT64_MAX))return "invalid job artwork receipt";
      std::set<std::pair<int32_t,int32_t>> ids;bool hovered=a->hovered()==-1;
      for(const auto* row:*a->rows()) {
        if(!row || row->id()<0 || !ids.emplace(row->id(),row->secondary()).second || !row->caption() || row->caption()->size()>1024 ||
           (row->badge() && row->badge()->size()>128) || (a->page()<6 ? row->secondary()!=-1 : row->secondary() < -1))return "invalid job artwork row";
        if(row->id()==a->hovered())hovered=true;
      }
      if(auto error=validateArtDraftState(*a))return error;
      if(a->page()>=6 && a->hovered()!=-1)return "unexpected draft hover";
      if(!hovered || ((a->hovered()>=0)!=(a->preview()!=nullptr)))return "invalid job artwork hover";
      if(a->preview()) {if(a->preview()->size()>128)return "invalid job artwork preview";for(const auto* line:*a->preview())if(!line || line->size()>2048)return "invalid job artwork preview line";}
    }
    if(s.action()==ManagementAction::JobSettingsApply && (!s.job_settings_edit() || !v->art() || !v->art()->draft() ||
       s.job_settings_edit()->outcome()!=JobSettingsEditOutcome::Applied || s.job_settings_edit()->job_id()!=v->job_id() ||
       s.job_settings_edit()->building_id()!=v->building_id() || s.job_settings_edit()->unit_id()!=v->unit_id()))return "invalid job draft write observation";
    std::unordered_set<int32_t> choices;
    for(const auto* c:*v->choices())if(!c || c->id()<0 || c->id()>=16384 || !choices.insert(c->id()).second ||
       !c->caption() || c->caption()->size()>512 || (c->count_caption() && c->count_caption()->size()>128))return "invalid job settings choice";
    if((v->current_value() && v->current_value()->size()>512) || (v->setting_heading() && v->setting_heading()->size()>512))return "invalid job settings heading";
  } else if(s.action()==ManagementAction::JobSettingsRead && s.status()==ManagementStatus::Ok)return "job settings result required";
  if(const auto* value=s.residents_activity()) {
    if(s.action()!=ManagementAction::ResidentsActivityRead || s.status()!=ManagementStatus::Ok ||
       value->unit_id()<0 || value->activity_id()<0 || value->event_id()<0 || value->columns()<1 || value->columns()>1024 ||
       value->max_y()<0 || value->max_y()>32768 || !value->words() || value->words()->size()>16384 ||
       !value->links() || value->links()->size()>4096)return "invalid residents activity result";
    size_t bytes=0;
    for(const auto* word:*value->words()) {
      if(!word || !word->text() || word->text()->size()>131072-bytes || word->text()->str().find('\0')!=std::string::npos ||
         word->flags()>7 || word->link() < -1 || (word->link()>=0 && size_t(word->link())>=value->links()->size()) ||
         word->x() < -1 || word->x()>131072 || word->y() < -1 || word->y()>value->max_y())return "invalid residents activity word";
      bytes+=word->text()->size();
    }
    for(const auto* link:*value->links())if(!link || link->type() < -1 || link->type()>11)return "invalid residents activity link";
  } else if(s.action()==ManagementAction::ResidentsActivityRead && s.status()==ManagementStatus::Ok)
    return "residents activity result required";
  if(const auto* value=s.residents_specialization()) {
    if(s.action()!=ManagementAction::ResidentsSpecialize || value->unit_id()<0 || value->outcome()>ResidentsSpecializationOutcome::Unknown)
      return "invalid residents specialization result";
    const bool applied=value->outcome()==ResidentsSpecializationOutcome::Applied;
    if(s.status()!=(applied?ManagementStatus::Ok:ManagementStatus::Rejected))return "invalid residents specialization outcome";
  } else if(s.action()==ManagementAction::ResidentsSpecialize && s.status()==ManagementStatus::Ok)
    return "residents specialization result required";
  if(const auto* w=s.creature_animal()) {
    if(s.action()!=ManagementAction::CreatureAnimalEdit || w->unit_id()<0 || w->animal_id()<0 ||
       w->outcome()>CreatureAnimalOutcome::Unknown)return "invalid creature animal result";
    const bool applied=w->outcome()==CreatureAnimalOutcome::Applied;
    if((applied && s.status()!=ManagementStatus::Ok) || (!applied && s.status()!=ManagementStatus::Rejected))
      return "invalid creature animal outcome";
  } else if(s.action()==ManagementAction::CreatureAnimalEdit && s.status()==ManagementStatus::Ok)
    return "creature animal result required";
  if(const auto* k=s.creature_knowledge()) {
    if(s.action()!=ManagementAction::CreatureKnowledgeRead || k->unit_id()<0 ||
       k->kind()<14 || k->kind()>17 || k->id()<0 || k->outcome()>CreatureKnowledgeOutcome::Unavailable ||
       !k->text() || k->text()->size()>65536 || k->text()->str().find('\0')!=std::string::npos)
      return "invalid creature knowledge result";
    const bool ready=k->outcome()==CreatureKnowledgeOutcome::Ready;
    if((ready && s.status()!=ManagementStatus::Ok) ||
       (!ready && (s.status()!=ManagementStatus::Rejected || k->text()->size())))
      return "invalid creature knowledge outcome";
  } else if(s.action()==ManagementAction::CreatureKnowledgeRead && s.status()==ManagementStatus::Ok)
    return "creature knowledge result required";
  if(s.creature() && s.action()!=ManagementAction::CreatureInspect) return "unexpected creature result";
  if(const auto* p=s.creature_position()) {
    const auto* tile=p->position();
    if((s.action()!=ManagementAction::CreatureLocate && s.action()!=ManagementAction::CreatureSheetLocate) || s.status()!=ManagementStatus::Ok ||
       p->unit_id()<0 || !tile || tile->x()<INT16_MIN || tile->y()<INT16_MIN || tile->z()<INT16_MIN ||
       tile->x()>32767 || tile->y()>32767 || tile->z()>32767)return "invalid creature position";
    if(s.action()==ManagementAction::CreatureLocate && (tile->x()<0 || tile->y()<0 || tile->z()<0))return "invalid follow position";
    if(s.action()==ManagementAction::CreatureSheetLocate && tile->x()==-30000)return "invalid sheet position";
  } else if((s.action()==ManagementAction::CreatureLocate || s.action()==ManagementAction::CreatureSheetLocate) && s.status()==ManagementStatus::Ok)
    return "creature position required";
  if(const auto* h=s.creature_header()) {
    if((s.action()!=ManagementAction::CreatureHeaderRead && s.action()!=ManagementAction::CreatureHeaderEdit) ||
       h->outcome()>CreatureHeaderOutcome::Unknown)return "invalid creature header result";
    const bool completed=h->outcome()==CreatureHeaderOutcome::Completed;
    if(completed!=(s.status()==ManagementStatus::Ok) || completed!=(h->snapshot()!=nullptr) ||
       (h->mutated() && (s.action()!=ManagementAction::CreatureHeaderEdit ||
        (h->outcome()!=CreatureHeaderOutcome::Completed && h->outcome()!=CreatureHeaderOutcome::Unknown))))return "invalid creature header outcome";
    if(const auto* v=h->snapshot()) {
      if(v->unit_id()<0 || v->historical_figure_id() < -1 || (v->has_figure() && v->historical_figure_id()<0) ||
         !v->revision() || v->revision()>INT64_MAX || !v->nickname() || !v->profession() || !v->figure_nickname() ||
         v->nickname()->size()>1536 || v->profession()->size()>1536 || v->figure_nickname()->size()>1536 ||
         (!v->has_figure() && v->figure_nickname()->size()))return "invalid creature header snapshot";
    }
  } else if((s.action()==ManagementAction::CreatureHeaderRead || s.action()==ManagementAction::CreatureHeaderEdit) &&
            s.status()==ManagementStatus::Ok)return "creature header result required";
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
    if(const auto* pages=c->health_pages()) {
      if(pages->size()!=5)return "invalid creature health page count";
      std::set<uint8_t> kinds;
      size_t healthRows=0;
      for(const auto* page:*pages) {
        if(!page || page->kind()>CreatureHealthPageKind::Description ||
           !kinds.insert(uint8_t(page->kind())).second || !page->rows())return "invalid creature health page";
        for(const auto* row:*page->rows()) {
          if(!row || !text(row,65536) || ++healthRows>4096)return "invalid creature health row";
        }
      }
    }
    if(const auto* pages=c->skills_pages()) {
      if(pages->size()!=5)return "invalid creature skills page count";
      std::set<uint8_t> kinds;size_t skillRows=0;
      for(const auto* page:*pages) {
        if(!page || page->kind()>CreatureSkillsPageKind::Knowledge ||
           !kinds.insert(uint8_t(page->kind())).second || !page->rows())return "invalid creature skills page";
        for(const auto* row:*page->rows()) {
          if(!row || ++skillRows>4096 || !row->caption() || !row->subtitle() ||
             !text(row->caption(),4096) || !text(row->subtitle(),4096))return "invalid creature skills row";
          if(page->kind()==CreatureSkillsPageKind::Knowledge) {
            if(row->knowledge_type()<0 || row->knowledge_type()>17 || row->id()< -1 ||
               (row->knowledge_type()>=14 && row->id()<0) || row->rating()!=0 || row->rust_value()!=0 || row->caption_color()!=-1)
              return "invalid creature knowledge row";
          } else if(row->id()<0 || row->id()>32767 || row->knowledge_type()!=-1 || row->knowledge_bits()!=0 ||
                    row->rating()<0 || row->subtitle()->size() || row->caption_color()<0 || row->caption_color()>127)return "invalid creature skill values";
        }
      }
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
    if(!constructionTextOk(c->warnings(),512))return "invalid construction warnings";
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
              if(!constructionTokenOk(a->gem_shape_raw(),128) ||
                 (a->gem_shape_raw() && a->gem_shape_raw()->size() && v->item_type()!=1))
                return "invalid construction gem shape";
              if(a->slab_engraving() < -2 || a->slab_engraving() > 26 || (a->slab_engraving()!=-2 && v->item_type()!=87))
                return "invalid construction slab facts";
              if(a->instrument_family() < -1 || a->instrument_family() > 3 ||
                 a->instrument_placed() < -1 || a->instrument_placed() > 1 ||
                 (a->instrument_family()==-1)!=(a->instrument_placed()==-1) ||
                 (a->instrument_family()!=-1 && v->item_type()!=13))
                return "invalid construction instrument facts";
              if(const auto* bedding=a->bedding()) {
                if(v->item_type()!=8 || bedding->sheet()<0 || bedding->sheet()>1 || bedding->pillow()<0 || bedding->pillow()>2 ||
                   !constructionTokenOk(bedding->base_color(),128) || !constructionTokenOk(bedding->sheet_color(),128))
                  return "invalid construction bedding facts";
              }
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
    if(a->operation()>AreaOperation::LocationStaffAssignmentsRead || a->area_id()<-1 ||
        textSize(a->list_key())>64 || textSize(a->query())>128 ||
        a->candidate_kind()>3 || a->sort()>(a->candidate_kind()==1?4:3) || a->list_revision()>INT64_MAX ||
        a->build_phase()>3 || a->build_done()>a->build_total() || a->captured_tick()<-1)
      return "invalid area response header";
    if(const auto* bytes=a->query_bytes()) {
      if(a->operation()!=AreaOperation::CandidateList || a->area_id()<0 || (a->candidate_kind()!=1 && a->candidate_kind()!=2) ||
         bytes->size()>33 || textSize(a->query()))return "invalid owner query echo";
    }
    if(a->settings_count() < -1 || (a->settings_count() >= 0 &&
        (a->operation()!=AreaOperation::SettingsPage || uint32_t(a->settings_count())<count(a->settings()) ||
         uint32_t(a->settings_count())<a->next_cursor() || uint32_t(a->settings_count())>a->build_total())))
      return "invalid filtered settings count";
    const bool multi=a->operation()>=AreaOperation::MultiCreate && a->operation()<=AreaOperation::MultiFinish;
    const bool counts=a->operation()==AreaOperation::PaintCounts;
    const bool locationChoices=a->operation()==AreaOperation::LocationChoices;
    const bool staffCandidates=a->operation()==AreaOperation::LocationStaffCandidates;
    const bool locationOpen=a->operation()==AreaOperation::LocationOpen;
    const bool locationAccess=a->operation()==AreaOperation::LocationAccess;
    const bool staffEdit=a->operation()==AreaOperation::LocationStaffEdit;
    const bool nameRead=a->operation()==AreaOperation::LocationNameRead;
    const bool nameChoices=a->operation()==AreaOperation::LocationNameChoices;
    const bool nameEdit=a->operation()==AreaOperation::LocationNameEdit;
    const bool specializationSet=a->operation()==AreaOperation::LocationSpecializationSet;
    const bool assignments=a->operation()==AreaOperation::LocationStaffAssignmentsRead;
    if(a->location_staff_assignments() && !assignments)return "assignments without operation";
    if(assignments) {
      if(s.action()!=ManagementAction::AreaInspect ||
          ((s.status()==ManagementStatus::Ok)!=(a->location_staff_assignments()!=nullptr)))return "invalid assignments presence/action";
      if(a->area_id()!=-1 || a->next_cursor() || a->truncated() || count(a->areas()) || count(a->choices()) ||
          count(a->settings()) || count(a->locations()) || count(a->candidates()) || count(a->links()) ||
          textSize(a->list_key()) || textSize(a->query()) || a->candidate_kind() || a->sort() || a->sort_descending() ||
          a->list_revision() || a->build_phase() || a->build_done() || a->build_total() || a->omitted() ||
          a->location_catalog() || a->location_details() || a->location_name() || a->location_name_page() ||
          a->location_staff_candidates() || a->location_recognition() || a->location_religious_staff() ||
          a->location_religious_candidates() || a->location_religious_assignment() || a->location_specialization())return "mixed assignments reply";
      if(const auto* r=a->location_staff_assignments()) {
        if(r->site_id()<0 || r->location_id()<0 || r->unit_id()<0 || r->histfig_id()<0 || r->occupation_id()<-1 ||
            (r->occupation_id()>=0?(r->entity_id()!=-1 || r->assignment_id()!=-1):(r->entity_id()<0 || r->assignment_id()<0)) ||
            !r->revision() || r->revision()>INT64_MAX || !r->entries())return "invalid assignment target";
        auto previous=LocationStaffAssignmentKind::Occupation;
        for(const auto* e:*r->entries()) {
          if(!e || e->kind()>LocationStaffAssignmentKind::WorkDetail || e->kind()<previous || e->id()<0 ||
              e->type()<-1 || e->subtype()<-1 || e->custom()<-1 || !e->name() || textSize(e->name())>4096)
            return "invalid assignment entry";
          const bool building=e->kind()==LocationStaffAssignmentKind::Workshop || e->kind()==LocationStaffAssignmentKind::Furnace;
          if(!building && (e->subtype()!=-1 || e->custom()!=-1))return "foreign assignment building fields";
          if(e->kind()!=LocationStaffAssignmentKind::WorkDetail && textSize(e->name()))return "foreign assignment name";
          if(textSize(e->custom_code())>64 || ((building && e->custom()>=0)!=(textSize(e->custom_code())>0)))return "invalid assignment custom code";
          previous=e->kind();
        }
      }
    }
    const bool specialization=specializationSet || a->operation()==AreaOperation::LocationSpecializationRead;
    if(a->location_specialization() && !specialization)return "specialization without operation";
    if(specialization) {
      if(s.action()!=(specializationSet?ManagementAction::AreaUpdate:ManagementAction::AreaInspect))return "specialization action mismatch";
      if((s.status()==ManagementStatus::Ok)!=(a->location_specialization()!=nullptr))return "invalid specialization presence";
      if(a->area_id()!=-1 || a->next_cursor() || a->truncated() || count(a->areas()) || count(a->choices()) ||
          count(a->settings()) || count(a->locations()) || count(a->candidates()) || count(a->links()) ||
          textSize(a->list_key()) || textSize(a->query()) || a->candidate_kind() || a->sort() || a->sort_descending() ||
          a->list_revision() || a->build_phase() || a->build_done() || a->build_total() || a->omitted() ||
          a->location_catalog() || a->location_details() || a->location_name() || a->location_name_page() ||
          a->location_staff_candidates() || a->location_recognition() || a->location_religious_staff() ||
          a->location_religious_candidates() || a->location_religious_assignment())return "mixed specialization reply";
      if(specializationSet && (a->location_edit_outcome()==LocationEditOutcome::None || a->location_edit_outcome()>LocationEditOutcome::Unknown ||
          ((a->location_edit_outcome()==LocationEditOutcome::Completed)!=(s.status()==ManagementStatus::Ok))))return "invalid specialization outcome";
      if(const auto* r=a->location_specialization()) {
        if(r->site_id()<0 || r->location_id()<0 || r->unit_id()<0 || r->histfig_id()<0 || r->occupation_id()<-1 ||
            (r->occupation_id()>=0?(r->entity_id()!=-1 || r->assignment_id()!=-1):(r->entity_id()<0 || r->assignment_id()<0)) ||
            !r->revision() || r->revision()>INT64_MAX)return "invalid specialization receipt";
      }
    }
    const bool religiousCandidates=a->operation()==AreaOperation::LocationReligiousCandidates;
    const bool religiousAssignmentRead=a->operation()==AreaOperation::LocationReligiousAssignmentRead;
    const bool religiousAssign=a->operation()==AreaOperation::LocationReligiousAssign;
    if(a->location_religious_candidates() && !religiousCandidates)return "religious candidates without operation";
    if(a->location_religious_assignment() && !religiousAssignmentRead)return "religious assignment receipt without operation";
    if(religiousCandidates || religiousAssignmentRead) {
      if(s.action()!=ManagementAction::AreaInspect)return "religious selection action mismatch";
      if(a->area_id()!=-1 || a->next_cursor() || a->truncated() || count(a->areas()) || count(a->choices()) ||
          count(a->settings()) || count(a->locations()) || count(a->candidates()) || count(a->links()) ||
          textSize(a->list_key()) || textSize(a->query()) || a->candidate_kind() || a->sort() || a->sort_descending() ||
          a->list_revision() || a->build_phase() || a->build_done() || a->build_total() || a->omitted() ||
          a->location_catalog() || a->location_details() || a->location_name() || a->location_name_page() ||
          a->location_staff_candidates() || a->location_recognition() || a->location_religious_staff())return "mixed religious selection reply";
      if((s.status()==ManagementStatus::Ok)!=(religiousCandidates?a->location_religious_candidates()!=nullptr:a->location_religious_assignment()!=nullptr))
        return "invalid religious selection presence";
      if(const auto* c=a->location_religious_candidates()) {
        if(!validLocationReligiousStaff(c->target()))return "invalid religious candidate target";
        if(auto error=validateLocationCandidatePage(*c))return error;
      }
      if(const auto* r=a->location_religious_assignment()) {
        if(!validLocationReligiousStaff(r->target()) || r->unit_id()<0 || r->histfig_id()<0 || r->nemesis_id()<0 ||
            !r->revision() || r->revision()>INT64_MAX || !r->list_revision() || r->list_revision()>INT64_MAX || !r->eligible())
          return "invalid religious assignment receipt";
      }
    }
    const bool religiousRemove=a->operation()==AreaOperation::LocationReligiousStaffRemove;
    const bool religious=religiousRemove || religiousAssign || a->operation()==AreaOperation::LocationReligiousStaffRead;
    if(a->location_religious_staff() && !religious)return "religious staff snapshot without operation";
    if(religious) {
      if(s.action()!=((religiousRemove || religiousAssign)?ManagementAction::AreaUpdate:ManagementAction::AreaInspect))return "religious staff action mismatch";
      if(a->area_id()!=-1 || a->next_cursor() || a->truncated() || count(a->areas()) || count(a->choices()) ||
          count(a->settings()) || count(a->locations()) || count(a->candidates()) || count(a->links()) ||
          textSize(a->list_key()) || textSize(a->query()) || a->candidate_kind() || a->sort() || a->sort_descending() ||
          a->list_revision() || a->build_phase() || a->build_done() || a->build_total() || a->omitted() ||
          a->location_catalog() || a->location_details() || a->location_name() || a->location_name_page() || a->location_staff_candidates() || a->location_recognition())
        return "mixed religious staff reply";
      if((religiousRemove || religiousAssign) && (a->location_edit_outcome()==LocationEditOutcome::None || a->location_edit_outcome()>LocationEditOutcome::Unknown ||
          ((a->location_edit_outcome()==LocationEditOutcome::Completed)!=(s.status()==ManagementStatus::Ok))))return "invalid religious staff outcome";
      if((s.status()==ManagementStatus::Ok)!=(a->location_religious_staff()!=nullptr))return "invalid religious staff presence";
      if(const auto* r=a->location_religious_staff()) {
        if(r->site_id()<0 || r->location_id()<0 || r->entity_id()<0 || r->assignment_id()<0 || r->position_id()<0 ||
            r->holder_id()<-1 || r->unit_id()<-1 || !r->revision() || r->revision()>INT64_MAX ||
            (r->holder_id()==-1 && (r->unit_id()!=-1 || r->removable())) || (religiousRemove && r->removable()) || (religiousAssign && r->holder_id()<0))return "invalid religious staff snapshot";
      }
    }
    const bool recognize=a->operation()==AreaOperation::LocationRecognize;
    const bool recognition=recognize || a->operation()==AreaOperation::LocationRecognitionRead;
    if(a->location_recognition() && !recognition)return "recognition snapshot without operation";
    if(recognition) {
      if(s.action()!=(recognize?ManagementAction::AreaUpdate:ManagementAction::AreaInspect))return "recognition action mismatch";
      if(a->area_id()!=-1 || a->next_cursor() || a->truncated() || count(a->areas()) || count(a->choices()) ||
          count(a->settings()) || count(a->locations()) || count(a->candidates()) || count(a->links()) ||
          textSize(a->list_key()) || textSize(a->query()) || a->candidate_kind() || a->sort() || a->sort_descending() ||
          a->list_revision() || a->build_phase() || a->build_done() || a->build_total() || a->omitted() ||
          a->location_catalog() || a->location_details() || a->location_name() || a->location_name_page() || a->location_staff_candidates())
        return "mixed recognition reply";
      if(recognize && (a->location_edit_outcome()==LocationEditOutcome::None || a->location_edit_outcome()>LocationEditOutcome::Unknown ||
          ((a->location_edit_outcome()==LocationEditOutcome::Completed)!=(s.status()==ManagementStatus::Ok))))return "invalid recognition outcome";
      if((s.status()==ManagementStatus::Ok)!=(a->location_recognition()!=nullptr))return "invalid recognition presence";
      if(a->location_recognition())if(auto error=validateLocationRecognition(*a->location_recognition()))return error;
    }
    const bool naming=nameRead || nameChoices || nameEdit;
    if(a->location_name() && !nameRead && !nameEdit)return "name snapshot without naming operation";
    if(a->location_name_page() && !nameChoices)return "name page without choices operation";
    if(naming) {
      if(s.action()!=(nameEdit?ManagementAction::AreaUpdate:ManagementAction::AreaInspect))return "name operation action mismatch";
      if(a->area_id()!=-1 || a->next_cursor() || a->truncated() || count(a->areas()) || count(a->choices()) ||
          count(a->settings()) || count(a->locations()) || count(a->candidates()) || count(a->links()) ||
          textSize(a->list_key()) || textSize(a->query()) || a->candidate_kind() || a->sort() || a->sort_descending() ||
          a->list_revision() || a->build_phase() || a->build_done() || a->build_total() || a->omitted() || a->location_catalog())
        return "mixed location naming reply";
      if(nameEdit && (a->location_edit_outcome()==LocationEditOutcome::None || a->location_edit_outcome()>LocationEditOutcome::Unknown ||
          ((a->location_edit_outcome()==LocationEditOutcome::Completed)!=(s.status()==ManagementStatus::Ok))))return "invalid name edit outcome";
      if(s.status()==ManagementStatus::Ok && !(nameChoices?a->location_name_page()!=nullptr:a->location_name()!=nullptr))return "missing name result";
      if(a->location_name())if(auto error=validateLocationNameSnapshot(*a->location_name()))return error;
      if(a->location_name_page())if(auto error=validateLocationNamePage(*a->location_name_page()))return error;
    }
    const bool locationEdit=locationAccess || staffEdit || a->operation()==AreaOperation::LocationQuantity;
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
    if(!locationEdit && !nameEdit && !recognize && !religiousRemove && !religiousAssign && !specializationSet && a->location_edit_outcome()!=LocationEditOutcome::None)return "edit outcome without edit operation";
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
    if(a->operation()==AreaOperation::LinkTarget &&
        (count(a->links())>1 || count(a->areas()) || count(a->choices()) || count(a->settings()) || count(a->locations()) || count(a->candidates()) || a->next_cursor()))
      return "invalid stockpile link target response";
    if(families>1 || (count(a->choices()) && (count(a->areas()) || families)) ||
        (families && count(a->areas())>1)) return "area response mixes list families";
    // Sum variable payloads across the entire reply, not just each page's
    // per-row bounds. Scalar/table overhead still fits the 512 KiB channel.
    size_t payload=textSize(a->list_key())+textSize(a->query())+count(a->query_bytes());
    size_t extentTotal=0,linkTotal=0;
    std::set<int32_t> areaIds,choiceIds;
    if (a->areas()) for (const auto* v:*a->areas()) {
      if (!v || v->id()<0 || v->kind()>AreaKind::Zone || !v->origin() ||
          !areaIds.insert(v->id()).second || v->origin()->x()<0 || v->origin()->y()<0 || v->origin()->z()<0 ||
          v->barrels()<0 || v->bins()<0 || v->wheelbarrows()<0 || v->owner_id() < -1 || v->zone_type() < -1 || v->zone_type()>255 ||
          v->width()<1 || v->height()<1 || v->width()>256 || v->height()>256 ||
          !v->extents() || v->extents()->size()!=uint32_t(v->width())*v->height() ||
          v->extents()->size()>65536 || (v->categories() & ~0x1ffffu) ||
          textSize(v->custom_name())>512 || (v->name() && v->name()->size()>512) || (v->owner_name() && v->owner_name()->size()>512) ||
          (v->gives() && v->gives()->size()>1024) || (v->takes() && v->takes()->size()>1024) ||
          v->revision()>INT64_MAX || textSize(v->zone_label())>512 ||
          textSize(v->location_name())>512 || textSize(v->religion())>512 ||
          v->location_id()<-1 || v->location_site_id()<-1 || v->organic()<-1 || v->organic()>1 ||
          v->inorganic()<-1 || v->inorganic()>1 || !validAreaZoneSettings(v->zone_settings()) ||
          v->overlapping()<-1 || v->overlapping()>1 ||
          (v->kind()!=AreaKind::Zone && v->overlapping()!=-1) || v->storage_limit()<-1 || v->storage_limit()>32767 ||
          (v->kind()!=AreaKind::Stockpile && v->storage_limit()!=-1) || v->tile_count()<-1 || v->assigned_count()<-1 || v->location_kind()>5 ||
          v->owner_sex()<-1 || v->owner_sex()>1 || textSize(v->owner_profession())>512) return "invalid area state";
      payload+=4+textSize(v->custom_name())+textSize(v->name())+textSize(v->owner_name())+textSize(v->zone_label())+
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
      if(!row || row->id()<-1 || row->entity()>AreaCandidateEntity::Squad ||
          (row->entity()==AreaCandidateEntity::Item && (row->id()<0 || a->candidate_kind()!=2)) ||
          (row->entity()==AreaCandidateEntity::Squad && (row->id()<0 || a->candidate_kind()!=3)) ||
          (row->entity()==AreaCandidateEntity::Unit && a->candidate_kind()!=1 && a->candidate_kind()!=2) || textSize(row->name())>512 || textSize(row->profession())>512 ||
          row->sex()<-1 || row->sex()>1 || row->mood()>7 || row->squad_use()<-1 || row->squad_use()>15)
        return "invalid area candidate row";
      if(const auto* status=row->animal_status()) {
        if(a->operation()!=AreaOperation::CandidateList || a->candidate_kind()!=2 || row->id()<0 ||
           (row->entity()!=AreaCandidateEntity::Unit && row->entity()!=AreaCandidateEntity::Item) ||
           status->kind()>5 || status->containment()>4 ||
           (row->entity()==AreaCandidateEntity::Item && status->kind()>3) ||
           (status->kind()==4 ? (status->containment()==0 || status->item_id()<0) :
                                (status->containment()!=0 || status->item_id()!=-1)))return "invalid animal status";
        payload+=6;
      }
      if(const auto* c=row->animal_item_color()) {
        if(a->operation()!=AreaOperation::CandidateList || a->candidate_kind()!=2 || row->entity()!=AreaCandidateEntity::Item || row->id()<0 ||
           c->foreground()>7 || c->background()>7 || c->bright()>1)return "invalid animal item color";
        payload+=3;
      }
      if(const auto* s=row->squad_symbol()) {
        if(a->operation()!=AreaOperation::CandidateList || a->candidate_kind()!=3 ||
           row->entity()!=AreaCandidateEntity::Squad || row->id()<0 || s->index()>22)return "invalid squad symbol";
        payload+=7;
      }
      if(const auto* r=row->animal_restraint()) {
        if(!row->animal_status() || row->animal_status()->kind()!=4 || row->animal_container() || textSize(r->solid_color())>128)return "invalid animal restraint";
        payload+=1+textSize(r->solid_color());
      }
      if(const auto* c=row->animal_container()) {
        if(!row->animal_status() || row->animal_status()->kind()!=4 || c->material_family()>2 || textSize(c->solid_color())>128 ||
           c->occupant_entity()>2 || (c->occupant_entity()==0 ? (c->occupant_id()!=-1 || c->occupant()!=nullptr) : c->occupant_id()<0))
          return "invalid animal container";
        payload+=6+textSize(c->solid_color());
        if(const auto* p=c->occupant())if(const auto* error=validateOwnerAppearance(*p,payload))return error;
      }
      if(const auto* display=row->animal_display()) {
        if(a->operation()!=AreaOperation::CandidateList || a->candidate_kind()!=2 || row->entity()!=AreaCandidateEntity::Unit || row->id()<0 ||
           display->columns()<3 || display->columns()>128 || textSize(display->first_line())>384 || textSize(display->second_line())>384 ||
           textSize(display->warning())>256 || (row->grazer()!=(textSize(display->warning())!=0)) ||
           (display->combined_fits() && textSize(display->second_line())!=0))return "invalid animal display";
        const auto* c=display->name_color();
        if(!c || c->foreground()>7 || c->background()>7 || c->bright()>1 || c->alternate_foreground()>7 ||
           c->alternate_background()>7 || c->alternate_bright()>1 || c->effect()>3 ||
           (c->effect()==0 && (c->foreground()!=c->alternate_foreground() || c->background()!=c->alternate_background() || c->bright()!=c->alternate_bright())))
          return "invalid animal name color";
        payload+=10+textSize(display->first_line())+textSize(display->second_line())+textSize(display->warning());
      }
      if(const auto* display=row->owner_display()) {
        if(a->operation()!=AreaOperation::CandidateList || a->candidate_kind()!=1 ||
           display->columns()<3 || display->columns()>128 || display->room_value()<0 ||
           textSize(display->first_line())>384 || textSize(display->second_line())>384 || textSize(display->status())>256 ||
           ((display->room_value()==0)!=(textSize(display->status())==0)))return "invalid owner display";
        payload+=6+textSize(display->first_line())+textSize(display->second_line())+textSize(display->status());
        if(const auto* c=display->name_color()) {
          if(c->foreground()>7 || c->background()>7 || c->bright()>1 || c->alternate_foreground()>7 ||
             c->alternate_background()>7 || c->alternate_bright()>1 || c->effect()>3 ||
             (c->effect()==0 && (c->foreground()!=c->alternate_foreground() || c->background()!=c->alternate_background() || c->bright()!=c->alternate_bright())))
            return "invalid owner name color";
          payload+=7;
        }
      }
      if(const auto* p=row->sheet_icon()) {
        if(a->operation()!=AreaOperation::CandidateList || (a->candidate_kind()!=1 &&
           !(a->candidate_kind()==2 && (row->entity()==AreaCandidateEntity::Unit || row->entity()==AreaCandidateEntity::Item))) || row->id()<0 ||
           !p->tile_pages() || p->tile_pages()->size()>256 || !p->palettes() || p->palettes()->size()>256 ||
           !p->layers() || p->layers()->size()>256)return "invalid owner sheet icon references";
        if(const auto* error=validateOwnerAppearance(*p,payload))return error;
      }
      payload+=10+textSize(row->name())+textSize(row->profession());
    }
    if(a->links()) for(const auto* row:*a->links()) {
      if(!row || row->id()<0 || (row->kind()!=AreaKind::Stockpile && row->kind()!=AreaKind::Workshop) ||
          row->direction()<1 || row->direction()>2 || textSize(row->name())>512) return "invalid area link row";
      payload+=6+textSize(row->name());
    }
    if(payload>224*1024) return "area response exceeds bounded payload";
  }
  if(s.action()==ManagementAction::FarmEdit && s.status()==ManagementStatus::Ok && !s.production())return "missing farm edit result";
  if (const auto* p=s.production()) {
    if(const auto* state=p->workshop_orders()) {
      if(p->workshop_workers() || p->building_header() || p->independent_item() || p->item() || p->item_position() || p->farm() || p->contents() || p->contents_edit() || p->farm_edit_outcome()!=FarmEditOutcome::None ||
         p->selected_building()!=-1 || p->created_job()!=-1 || p->current_season()!=-1 || p->next_cursor() ||
         (p->buildings() && p->buildings()->size()) || (p->recipes() && p->recipes()->size()) ||
         (p->jobs() && p->jobs()->size()) || (p->crops() && p->crops()->size()) ||
         (p->seasonal_crops() && p->seasonal_crops()->size()) || (p->detail() && p->detail()->size()))return "mixed workshop orders response";
      const bool edit=s.action()==ManagementAction::FarmEdit,ok=s.status()==ManagementStatus::Ok;
      if((!edit && s.action()!=ManagementAction::ProductionInspect) || state->building_id()<0 || static_cast<uint8_t>(state->outcome())>4 ||
         (edit ? (state->outcome()==FarmEditOutcome::None || ok!=(state->outcome()==FarmEditOutcome::Completed)) : state->outcome()!=FarmEditOutcome::None))return "invalid workshop orders outcome";
      if(ok) {
        if(!state->revision() || state->revision()>INT64_MAX || !state->order_ids() || state->order_ids()->size()>16384 ||
           state->value()<-1 || state->value()>99 ||
           (edit ? (state->value()>=0 ? (state->delta()!=0 || state->general_order_limit()!=state->value()) : (state->delta()!=-1 && state->delta()!=1)) : (state->delta()!=0 || state->value()!=-1)))return "invalid workshop orders profile";
        for(const auto id:*state->order_ids())if(id<0)return "invalid workshop order id";
      } else if(state->revision() || state->manager_available() || state->general_order_limit() || state->delta() || state->value()!=-1 ||
                (state->order_ids() && state->order_ids()->size()))return "unconfirmed workshop orders authority";
    } else if(const auto* state=p->workshop_workers()) {
      if(p->building_header() || p->independent_item() || p->item() || p->item_position() || p->farm() || p->contents() || p->contents_edit() || p->farm_edit_outcome()!=FarmEditOutcome::None ||
         p->selected_building()!=-1 || p->created_job()!=-1 || p->current_season()!=-1 || p->next_cursor() ||
         (p->buildings() && p->buildings()->size()) || (p->recipes() && p->recipes()->size()) ||
         (p->jobs() && p->jobs()->size()) || (p->crops() && p->crops()->size()) ||
         (p->seasonal_crops() && p->seasonal_crops()->size()) || (p->detail() && p->detail()->size()))return "mixed workshop workers response";
      const bool edit=s.action()==ManagementAction::FarmEdit;const bool ok=s.status()==ManagementStatus::Ok;
      if((!edit && s.action()!=ManagementAction::ProductionInspect) || state->building_id()<0 || static_cast<uint8_t>(state->outcome())>4 ||
         (edit ? (state->outcome()==FarmEditOutcome::None || ok!=(state->outcome()==FarmEditOutcome::Completed)) : state->outcome()!=FarmEditOutcome::None))return "invalid workshop workers outcome";
      if(ok) {
        if(!state->profile_revision() || state->profile_revision()>INT64_MAX || !state->permitted_workers() || state->permitted_workers()->size()>16384)return "invalid workshop worker profile";
        for(const auto id:*state->permitted_workers())if(id<0)return "invalid permitted worker";
        if(const auto* a=state->assigned()) {
          if(state->permitted_workers()->size()==0 || a->id()!=state->permitted_workers()->Get(0) || !a->caption() || a->caption()->size()>8192 ||
             (a->can_specialize() && !a->specialization_visible()))return "invalid assigned worker";
        }
        if(!edit) {
          if(state->operation()!=FarmOperation::Crop)return "unexpected worker read operation";
          if(state->unit_id()!=-1)return "unexpected worker receipt";
          if(auto error=validateLocationCandidatePage(*state,148,149))return error;
          const auto textSize=[](const flatbuffers::String* value)->size_t{return value?value->size():0;};
          if(!state->rows())return "missing worker rows";
          size_t assignmentBytes=0;
          for(const auto* row:*state->rows()) {
            if(!row->assignments() || row->assignments()->size()>512)return "invalid worker assignment list";
            auto previous=LocationStaffAssignmentKind::Occupation;
            for(const auto* e:*row->assignments()) {
              if(!e || e->kind()>LocationStaffAssignmentKind::WorkDetail || e->kind()<previous || e->id()<0 ||
                 e->type()<-1 || e->subtype()<-1 || e->custom()<-1 || !e->name() || textSize(e->name())>4096)return "invalid worker assignment";
              const bool building=e->kind()==LocationStaffAssignmentKind::Workshop || e->kind()==LocationStaffAssignmentKind::Furnace;
              if(!building && (e->subtype()!=-1 || e->custom()!=-1))return "foreign worker assignment fields";
              if(e->kind()!=LocationStaffAssignmentKind::WorkDetail && textSize(e->name()))return "foreign worker assignment name";
              if(textSize(e->custom_code())>64 || ((building && e->custom()>=0)!=(textSize(e->custom_code())>0)))return "invalid worker assignment code";
              assignmentBytes+=64+textSize(e->name())+textSize(e->custom_code());previous=e->kind();
            }
          }
          if(assignmentBytes>224*1024)return "worker assignment payload exceeds budget";
        } else if(state->operation()<FarmOperation::WorkerSelect || state->operation()>FarmOperation::WorkerSpecialize || state->unit_id()<0 || state->revision() || state->cursor() || state->next_cursor() || state->total() || (state->rows() && state->rows()->size()))return "invalid worker selection receipt";
      } else if(state->assigned() || state->operation()!=FarmOperation::Crop || state->profile_revision() || state->revision() || state->cursor() || state->next_cursor() || state->total() || state->unit_id()!=-1 ||
                (state->permitted_workers() && state->permitted_workers()->size()) || (state->rows() && state->rows()->size()))return "unconfirmed worker authority";
    } else if(const auto* state=p->building_header()) {
      if(p->independent_item() || p->item() || p->item_position() || p->farm() || p->contents() || p->contents_edit() || p->farm_edit_outcome()!=FarmEditOutcome::None ||
         p->selected_building()!=-1 || p->created_job()!=-1 || p->current_season()!=-1 || p->next_cursor() ||
         (p->buildings() && p->buildings()->size()) || (p->recipes() && p->recipes()->size()) ||
         (p->jobs() && p->jobs()->size()) || (p->crops() && p->crops()->size()) ||
         (p->seasonal_crops() && p->seasonal_crops()->size()) || (p->detail() && p->detail()->size()))return "mixed building header response";
      const auto* f=state->snapshot();const auto outcome=state->outcome();const auto op=state->operation();
      if(static_cast<uint8_t>(outcome)>4)return "invalid building header outcome";
      if(f) {
        const auto text=[](const flatbuffers::String* t,bool empty){return t && t->size()<=1536 && (empty || t->size()>0) && t->str().find('\0')==std::string::npos;};
        if(f->id()<0 || (f->type()!=10 && f->type()!=5 && f->type()!=13) || !f->revision() || f->revision()>INT64_MAX || f->stage()<0 || f->max_stage()<f->stage() ||
           !text(f->custom_name(),true) || !text(f->native_name(),false) || !text(f->header_name(),false) ||
           (!f->removing() && (f->suspended() || f->has_worker())))return "invalid building header snapshot";
      }
      if(s.action()==ManagementAction::ProductionInspect) {
        if(outcome!=FarmEditOutcome::None || op!=FarmOperation::Crop || ((s.status()==ManagementStatus::Ok)!=(f!=nullptr)))return "invalid building header read";
      } else if(s.action()==ManagementAction::FarmEdit) {
        if(f && f->type()!=10)return "unsupported building header edit target";
        if(outcome==FarmEditOutcome::None)return "missing building header outcome";
        if(outcome==FarmEditOutcome::Completed) {
          if(s.status()!=ManagementStatus::Ok || !f || f->stage()!=f->max_stage() || op<FarmOperation::Rename || op>FarmOperation::CancelRemoval ||
             f->removing()!=(op==FarmOperation::Remove))return "invalid building header completion";
        } else if(s.status()==ManagementStatus::Ok || f || op!=FarmOperation::Crop)return "unconfirmed building header authority";
      } else return "unexpected building header response";
    } else if(const auto* state=p->independent_item()) {
      if(p->item() || p->item_position() || p->farm() || p->contents() || p->contents_edit() || p->farm_edit_outcome()!=FarmEditOutcome::None ||
         p->selected_building()!=-1 || p->created_job()!=-1 || p->current_season()!=-1 || p->next_cursor() ||
         (p->buildings() && p->buildings()->size()) || (p->recipes() && p->recipes()->size()) ||
         (p->jobs() && p->jobs()->size()) || (p->crops() && p->crops()->size()) ||
         (p->seasonal_crops() && p->seasonal_crops()->size()) || (p->detail() && p->detail()->size()))return "mixed independent item response";
      if(s.action()!=ManagementAction::ProductionInspect && s.action()!=ManagementAction::FarmEdit)return "unexpected independent item response";
      const auto* item=state->snapshot();const auto* edit=state->edit();const auto outcome=state->outcome();
      if(static_cast<uint8_t>(outcome)>4)return "invalid independent item outcome";
      if(item) {
        auto text=[](const flatbuffers::String* value,size_t limit){return value && value->size()<=limit;};
        if(item->id()<0 || !item->revision() || item->revision()>INT64_MAX || item->item_type()<0 || item->item_type()>92 ||
           !text(item->name(),128*1024) || !text(item->material_token(),256) || !text(item->subtype_raw(),128) ||
           !text(item->weight(),128) || !text(item->description(),32*1024))return "invalid independent item snapshot";
        for(const auto* link:{item->holder(),item->stockpile()})
          if(link && (link->id()<0 || link->type()<0 || !text(link->name(),512)))return "invalid independent item link";
        if(item->stockpile() ? (item->stockpile_categories()<0 || item->stockpile_categories()>0x1ffff) : item->stockpile_categories()!=-1)return "invalid independent stockpile categories";
        if(item->stockpile() && item->stockpile()->type()!=29)return "invalid item stockpile type";
        if((item->item_type()==30||item->item_type()==13) && !item->appearance())return "missing item appearance";
        if(const auto* a=item->appearance())if(!validInspectionInstrument(*a,item->item_type())||!text(a->material_token(),256)||a->material_token()->size()==0||!text(a->subtype_raw(),128)||!text(a->color_token(),128)||a->stack()<1||(a->flags()&~96)||a->material_token()->str()!=item->material_token()->str()||a->subtype_raw()->str()!=item->subtype_raw()->str())return "invalid item appearance";
        if(const auto* a=item->ammunition_assignment())if(item->item_type()!=39 || a->kind()<0 || a->kind()>2 || (a->kind()==2?a->squad_id()<0:a->squad_id()!=-1) || !text(a->caption(),1024) || (a->kind()==0)!=(a->caption()->size()==0))return "invalid item ammunition assignment";
        if(const auto* rows=item->uses()){
          if(rows->size()>4096)return "too many item uses";
          for(const auto* row:*rows)if(!row || !text(row->caption(),16384) || row->reaction()< -1)return "invalid item use";
        }
        if(const auto* rows=item->contents()) {
          if(rows->size()>4096)return "too many item contents";
          for(const auto* row:*rows) {
            if(!row || row->id()<0 || !text(row->caption(),128*1024) || (row->kind()!=1&&row->kind()!=2))return "invalid item contents row";
            if(row->kind()==2){if(row->item_type()!=-1 || row->flags()!=0 || row->can_dump() || row->can_melt() || row->appearance())return "invalid creature contents row";}
            else {
              const auto* a=row->appearance();
              if(row->item_type()<0 || row->item_type()>92 || !a || !validInspectionInstrument(*a,row->item_type()) || !text(a->material_token(),256) || a->material_token()->size()==0 || !text(a->subtype_raw(),128) || !text(a->color_token(),128) || a->stack()<1 || (a->flags()&~96))return "invalid contained item appearance";
            }
          }
        }
        if(const auto* owner=item->owner())if(owner->id()<0||!text(owner->name(),512))return "invalid item owner";
        if(const auto* c=item->carrier()) {
          if(item->holder() || c->id()<0 || !text(c->name(),512) || (c->kind()!=1&&c->kind()!=2) ||
             (c->kind()==1?(c->item_type()<0||c->item_type()>92):c->item_type()!=-1))return "invalid item carrier";
          if((c->kind()==1)!=(c->appearance()!=nullptr))return "invalid carrier appearance presence";
          if(const auto* a=c->appearance())if(!validInspectionInstrument(*a,c->item_type())||!text(a->material_token(),256)||a->material_token()->size()==0||!text(a->subtype_raw(),128)||!text(a->color_token(),128)||a->stack()<1||(a->flags()&~96))return "invalid carrier appearance";
        }
      }
      if(s.action()==ManagementAction::ProductionInspect) {
        if(edit || outcome!=FarmEditOutcome::None || ((s.status()==ManagementStatus::Ok)!=(item!=nullptr)))return "invalid independent item read";
      } else {
        if(outcome==FarmEditOutcome::None)return "missing independent item outcome";
        if(outcome==FarmEditOutcome::Completed) {
          if(s.status()!=ManagementStatus::Ok || !item || !edit || edit->item_id()<0 || edit->value()<0 || edit->value()>1 ||
             edit->operation()<FarmOperation::ItemForbid || edit->operation()>FarmOperation::ItemHidden)return "invalid independent item receipt";
          bool actual=edit->operation()==FarmOperation::ItemForbid?item->forbid():edit->operation()==FarmOperation::ItemDump?item->dump():
            edit->operation()==FarmOperation::ItemMelt?item->melt():item->hidden();
          if(edit->item_id()!=item->id()) {
            const ItemSheetContent* selected=nullptr;
            if(item->contents())for(const auto* row:*item->contents())if(row->kind()==1 && row->id()==edit->item_id()){selected=row;break;}
            if(!selected)return "missing confirmed contents target";
            const uint32_t mask=edit->operation()==FarmOperation::ItemForbid?0x80000:edit->operation()==FarmOperation::ItemDump?0x200000:edit->operation()==FarmOperation::ItemMelt?0x800000:0x1000000;
            actual=(selected->flags()&mask)!=0;
          }
          if(actual!=(edit->value()!=0))return "unconfirmed independent item value";
        } else if(s.status()==ManagementStatus::Ok || item || edit)return "unconfirmed independent item authority";
      }
    } else {
    if(const auto* value=p->item_position()) {
      const auto* pos=value->position();
      if(s.action()!=ManagementAction::ProductionInspect || s.status()!=ManagementStatus::Ok || value->id()<0 || !pos ||
         pos->x()<0 || pos->y()<0 || pos->z()<0 || pos->x()>32767 || pos->y()>32767 || pos->z()>32767)
        return "invalid item position";
      if(p->item() || p->farm() || p->contents() || p->contents_edit() || p->farm_edit_outcome()!=FarmEditOutcome::None ||
         p->selected_building()!=-1 || p->created_job()!=-1 || p->current_season()!=-1 || p->next_cursor()!=0 ||
         (p->buildings() && p->buildings()->size()) || (p->recipes() && p->recipes()->size()) ||
         (p->jobs() && p->jobs()->size()) || (p->crops() && p->crops()->size()) ||
         (p->seasonal_crops() && p->seasonal_crops()->size()))return "mixed item position response";
    }
    if(const auto* item=p->item()) {
      const auto* row=item->item();
      if(s.action()!=ManagementAction::ProductionInspect || s.status()!=ManagementStatus::Ok ||
         item->building_id()<0 || item->building_id()!=p->selected_building() ||
         !item->revision() || item->revision()>INT64_MAX || !row || !validContentsAppearance(*row) || row->id()<0 || row->role()<0 ||
         !row->name() || row->name()->size()>128*1024 || row->item_type()<0 || row->item_type()>92 ||
         !row->material_token() || row->material_token()->size()>256 || !row->subtype_raw() || row->subtype_raw()->size()>128 ||
         !item->weight() || item->weight()->size()>128 || !item->description() || item->description()->size()>32*1024)
        return "invalid item inspection snapshot";
      if(const auto* holder=item->holder()) {
        if(holder->id()<0 || holder->type()<0 || !holder->name() || holder->name()->size()>512)return "invalid item building holder";
      }
      if(p->farm() || p->contents() || p->contents_edit() || p->farm_edit_outcome()!=FarmEditOutcome::None ||
         (p->buildings() && p->buildings()->size()) || (p->recipes() && p->recipes()->size()) ||
         (p->jobs() && p->jobs()->size()) || (p->crops() && p->crops()->size()) ||
         (p->seasonal_crops() && p->seasonal_crops()->size()) || p->current_season()!=-1 || p->created_job()!=-1)
        return "mixed item inspection response";
    }
    if(const auto* page=p->contents()) {
      if((s.action()!=ManagementAction::ProductionInspect && s.action()!=ManagementAction::FarmEdit) || s.status()!=ManagementStatus::Ok ||
         page->building_id()<0 || page->building_id()!=p->selected_building() ||
         !page->revision() || page->revision()>INT64_MAX || !page->rows() || page->rows()->size()>64 ||
         page->cursor()>page->total() || page->rows()->size()>page->total()-page->cursor())return "invalid contents page";
      const uint64_t end=uint64_t(page->cursor())+page->rows()->size();
      if((end<page->total() && (page->rows()->size()==0 || page->next_cursor()!=end)) ||
         (end==page->total() && page->next_cursor()!=0) ||
         (page->total()>0 && page->cursor()==page->total()))return "invalid contents continuation";
      std::set<int32_t> contentIds;size_t names=0;
      for(const auto* row:*page->rows()) {
        if(!row || row->id()<0 || row->role()<0 || !contentIds.insert(row->id()).second || !row->name())return "invalid contents row";
        if(!validContentsAppearance(*row) || row->item_type()<0 || row->item_type()>92 || !row->material_token() || !row->subtype_raw() ||
           row->material_token()->size()>256 || row->subtype_raw()->size()>128)return "invalid contents item identity";
        names+=row->name()->size();if(names>128*1024)return "contents names exceed payload budget";
      }
      if(p->farm() || (p->buildings() && p->buildings()->size()) || (p->recipes() && p->recipes()->size()) ||
         (p->jobs() && p->jobs()->size()) || (p->crops() && p->crops()->size()))return "mixed contents response";
    }
    if(const auto* edit=p->contents_edit()) {
      if(s.action()!=ManagementAction::FarmEdit || s.status()!=ManagementStatus::Ok ||
         p->farm_edit_outcome()!=FarmEditOutcome::Completed || !p->contents() || p->farm() ||
         !p->contents()->completed() ||
         edit->item_id()<0 || edit->value()<0 || edit->value()>1 ||
         edit->operation()<FarmOperation::ItemForbid || edit->operation()>FarmOperation::ItemHidden)return "invalid contained item receipt";
      const BuildingContentsItem* target=nullptr;
      for(const auto* row:*p->contents()->rows())if(row->id()==edit->item_id())target=row;
      if(!target)return "missing contained item receipt target";
      const bool desired=edit->value()!=0;
      const bool actual=edit->operation()==FarmOperation::ItemForbid?target->forbid():
        edit->operation()==FarmOperation::ItemDump?target->dump():edit->operation()==FarmOperation::ItemMelt?target->melt():target->hidden();
      if(actual!=desired)return "unconfirmed contained item value";
    }
    if(s.action()==ManagementAction::FarmEdit && p->contents() && !p->contents_edit())return "missing contained item receipt";
    const auto outcome=p->farm_edit_outcome();
    if(static_cast<uint8_t>(outcome)>4 || (outcome!=FarmEditOutcome::None && s.action()!=ManagementAction::FarmEdit))return "invalid farm edit outcome";
    if(s.action()==ManagementAction::FarmEdit) {
      if(s.status()==ManagementStatus::Ok && outcome!=FarmEditOutcome::Completed)return "missing farm completion";
      if(outcome==FarmEditOutcome::Completed && (s.status()!=ManagementStatus::Ok || (!p->farm() && !p->contents_edit())))return "invalid farm completion";
      if(outcome!=FarmEditOutcome::Completed && (p->farm() || p->contents() || p->contents_edit()))return "unconfirmed farm authority";
      if((p->crops() && p->crops()->size()) || (p->seasonal_crops() && p->seasonal_crops()->size()))return "legacy farm edit response";
    }
    if(const auto* f=p->farm()) {
      if(auto error=validateFarmSnapshot(*f))return error;
      if(p->selected_building()!=f->building_id())return "native farm identity mismatch";
      if((p->crops() && p->crops()->size()) || (p->seasonal_crops() && p->seasonal_crops()->size()) || p->current_season()!=-1)
        return "mixed legacy and native farm state";
    }
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
    if(p->recipes()) for(const auto* v:*p->recipes()) if(!v || !textOk(v->key(),128) || !v->key()->size() || !keys.insert(v->key()->str()).second || !textOk(v->name(),512) || !requirementsOk(v->requirements()) || (v->availability() && (!textOk(v->availability()->objection(),4096) || (v->availability()->available() && v->availability()->objection()->size())))) return "invalid production recipe";
    ids.clear();
    if(p->jobs()) for(const auto* v:*p->jobs()) if(!v || v->id()<0 || !ids.insert(v->id()).second || v->worker_id() < -1 || v->job_type()<0 || v->completion_timer() < -1 || !textOk(v->name(),512) || !textOk(v->worker_name(),512) || !textOk(v->status(),512) || !requirementsOk(v->requirements())) return "invalid production job";
    ids.clear();
    if(p->crops()) for(const auto* v:*p->crops()) if(!v || v->id()<0 || v->id()>32767 || !ids.insert(v->id()).second || !textOk(v->name(),512) || !v->seasons() || v->seasons()>15) return "invalid farm crop";
    if(p->seasonal_crops()) for(auto id:*p->seasonal_crops()) if(id < -1 || id>32767) return "invalid seasonal crop";
    } // Legacy building/contents production state.
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
    if(const auto* d=w->details()) {
      if(d->id()<0 || !d->revision() || d->revision()>INT64_MAX || !d->caption() || !textOk(d->caption(),1024) || !textOk(d->current_value(),512) ||
         !d->options() || d->options()->size()>65 || d->selected_option() < -1 ||
         (d->selected_option()>=0 && size_t(d->selected_option())>=d->options()->size()) ||
         d->choices_revision()>INT64_MAX || d->total()>16384 || d->next_cursor()>d->total() ||
         (d->selected_option()==-1 && (d->choices() || d->choices_revision() || d->total() || d->next_cursor())) ||
         (d->selected_option()>=0 && !d->art() && (!d->choices() || !d->choices_revision())) ||
         (d->choices() && (d->choices()->size()>128 || d->choices()->size()>d->total())))return "invalid native Details state";
      if(d->current_value() && (d->selected_option()<0 || d->art()))return "unexpected current Details value";
      for(const auto* option:*d->options())if(!option || option->kind()>6 || option->index() < -1 || !option->caption() || !textOk(option->caption(),512))return "invalid native Details option";
      const bool dye=d->selected_option()>=0 && (d->options()->Get(d->selected_option())->kind()==4 || d->options()->Get(d->selected_option())->kind()==5);
      if(d->dye_target() < -1 || d->dye_target()>1023 || !textOk(d->setting_heading(),512) ||
         (!dye && (d->dye_target()!=-1 || d->setting_heading())))return "unexpected dye Details state";
      std::set<int32_t> choices;
      if(d->choices())for(const auto* choice:*d->choices())if(!choice || choice->id()<0 || choice->id()>16383 || !choices.insert(choice->id()).second ||
         !choice->caption() || !textOk(choice->caption(),512) || !textOk(choice->count_caption(),128) || (choice->estimated() && !choice->count_caption()))return "invalid native Details choice";
      if(d->choices())for(const auto* choice:*d->choices()) {
        if(choice->dye_color() < -1 || choice->dye_color()>1023 || (choice->opens_menu() && choice->dye_color()<0) ||
           (!dye && (choice->dye_color()!=-1 || choice->opens_menu() || choice->swatch())) ||
           (d->dye_target()>=0 && (choice->opens_menu() || choice->swatch())))return "invalid dye Details choice";
        if(const auto* c=choice->swatch())if(!(c->red()>=0 && c->red()<=1 && c->green()>=0 && c->green()<=1 && c->blue()>=0 && c->blue()<=1))return "invalid dye color";
      }
      if(const auto* a=d->art()) {
        if(d->selected_option()<0 || d->choices() || d->choices_revision() || d->total() || d->next_cursor() ||
           a->page() < -1 || a->page()==0 || a->page()>18 || !a->caption() || !textOk(a->caption(),1024) ||
           !a->rows() || a->rows()->size()>128 || a->total()>262144 || a->rows()->size()>a->total() ||
           a->next_cursor()>a->total() || a->list_revision()>INT64_MAX ||
           (a->page()==-1 && (a->list_revision() || a->next_cursor() || a->rows()->size()!=a->total())) ||
           (a->page()>0 && !a->list_revision()))return "invalid artwork state";
        std::set<int32_t> ids;std::set<std::pair<int32_t,int32_t>> pairs;
        for(const auto* row:*a->rows())if(!row || row->id()<0 || row->secondary() < -1 || !pairs.emplace(row->id(),row->secondary()).second || (a->page()<6 && (!ids.insert(row->id()).second || row->secondary()!=-1)) ||
           !row->caption() || !textOk(row->caption(),1024) || !textOk(row->badge(),128) || (a->page()==-1 && row->id()>6))return "invalid artwork row";
        if(a->hovered() < -1 || (a->hovered()==-1 ? a->preview()!=nullptr :
           (a->page()<1 || !a->preview() || !ids.count(a->hovered()))) || (a->preview() && a->preview()->size()>128))return "invalid artwork preview";
        if(a->preview())for(const auto* line:*a->preview())if(!line || line->size()>2048)return "invalid artwork preview line";
        if(auto error=validateArtDraftState(*a))return error;
        const auto kind=d->options()->Get(d->selected_option())->kind();
        if(kind!=1 && kind!=3)return "invalid artwork parent";
      }
    }
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
         !textOk(row->name(),128) || !textOk(row->custom_code(),128))return "invalid work order group";
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
      if(const auto* native=o->native_state())
        if(native->phase()<WorkOrderPhase::Active || native->phase()>WorkOrderPhase::Ready || !textOk(native->workshop_name(),512))return "invalid native work order state";
      if(o->inputs())for(const auto* input:*o->inputs()) {
        if(!input || input->mat_type() < -1 || input->mat_index() < -1 ||
           !textOk(input->description(),1024))return "invalid work order input";
        ++inputCount;
      }
      std::set<int32_t> jobs; if(o->generated_jobs()) for(auto id:*o->generated_jobs()) {if(id<0 || !jobs.insert(id).second)return "invalid generated job";++jobCount;}
      for(bool suggested:{false,true}) {
      const auto* group=suggested?o->suggested_conditions():o->conditions();
      if(!group)continue;
      if(suggested && group->size()>128)return "too many suggested conditions";
      std::set<uint32_t> conditions;
      for(const auto* c:*group) {
        if(!c || c->estimate_count() < -1 || c->item_subtype() < -1 || c->mat_type() < -1 || c->mat_index() < -1 ||
           c->satisfaction()>2 || c->kind()>1 || c->index()>(suggested?127:63) || !conditions.insert(uint32_t(c->kind())*128+c->index()).second ||
           !textOk(c->description(),1024) || !textOk(c->item_caption(),1024) || (suggested && (c->kind()!=0 || !c->item_caption() || c->compare()<0 || c->threshold()<0)) || c->compare() < -1 || c->compare()>5 || c->threshold() < -1 || c->item_type() < -1 ||
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
    }
    if(conditionCount>128 || jobCount>2048 || traitCount>2048 || inputCount>128)return "work order aggregate limit exceeded";
    ids.clear();if(w->choices())for(const auto* c:*w->choices())if(!c || c->id()<0 || !ids.insert(c->id()).second || (!textOk(c->name(),512) || (c->label() && c->label()->size())))return "invalid work order choice";
    ids.clear();if(w->managers())for(const auto* m:*w->managers()){
      if(!m || m->unit_id()<0 || !ids.insert(m->unit_id()).second || !textOk(m->name(),512) || !textOk(m->position(),512) || !textOk(m->job(),512) || (m->offices() && m->offices()->size()>64))return "invalid manager role";
      std::set<int32_t> offices;if(m->offices())for(auto id:*m->offices())if(id<0 || !offices.insert(id).second)return "invalid manager office";
    }
    std::set<std::string> keys;if(w->recipes())for(const auto* r:*w->recipes())if(!r || !r->key() || !r->key()->size() || !textOk(r->key(),128) || !keys.insert(r->key()->str()).second || !textOk(r->name(),512) || (r->requirements() && r->requirements()->size()) || r->availability())return "invalid manager recipe";
  }
  if(const auto* c=s.citizen()) {
    if(c->outcome_unknown()) {
      const auto a=s.action();
      const bool write=a==ManagementAction::WorkDetailMembership || a==ManagementAction::WorkDetailMode ||
          (a>=ManagementAction::WorkDetailCreate && a<=ManagementAction::CitizenWorkScope);
      if(!write || s.status()!=ManagementStatus::Rejected ||
         (c->citizens() && c->citizens()->size()) || (c->details() && c->details()->size()) ||
         c->detail_list_revision() || c->next_cursor() || c->selected_unit()!=-1 || c->selected_detail()!=-1)
        return "invalid uncertain citizen outcome";
    }
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
    if(a->tracker()) {
      if((s.action()!=ManagementAction::AgreementList && s.action()!=ManagementAction::AgreementInspect) || s.status()!=ManagementStatus::Ok || !a->tracker_rows() || a->tracker_rows()->size()>4096 ||
          (a->agreements() && a->agreements()->size()) || a->next_before_id()!=-1 || a->pending_only() || (a->detail() && a->detail()->size()))return "invalid tracker state";
      size_t budget=0;
      for(const auto* row:*a->tracker_rows()) {
        if(!row || row->agreement_id()<0 || row->subject_id()<0 || row->entity_id()<0 || row->entity_type()<0 ||
            !row->heading() || row->heading()->size()>128 || !row->applicant() || row->applicant()->size()>4096 || !row->date() || row->date()->size()>128)return "invalid tracker row";
        const bool described=row->entity_type()==5 || row->entity_type()==10;
        if(described && (row->year_tick()<0 || row->year_tick()>=403200 || !row->date()->size()))return "invalid tracker date";
        if(!described && (row->heading()->size() || row->applicant()->size() || row->date()->size()))return "invalid tracker blank row";
        budget+=160+row->heading()->size()+row->applicant()->size()+row->date()->size();
      }
      if(budget>224*1024)return "tracker budget exceeded";
      if(s.action()==ManagementAction::AgreementInspect) {
        const auto* d=a->tracker_details();
        if(!d || a->tracker_rows()->size()!=1 || !d->location_name() || d->location_name()->size()>4096 ||
           d->matching_locations()<0 || d->matching_locations()>65536 || d->location_id() < -1)return "invalid tracker details";
        const auto* row=a->tracker_rows()->Get(0);
        if(d->location_id()<0) {
          if(d->location_value()!=0 || d->location_tier()!=-1 || d->tier_met() || d->location_name()->size())return "invalid absent tracker location";
        } else if(!d->site_available() || d->matching_locations()<1 || d->location_value()<=0 || d->tier_met()!=(d->location_tier()>=row->tier()))return "invalid selected tracker location";
        if(!d->site_available() && d->matching_locations()!=0)return "invalid absent tracker site";
        if(row->entity_type()!=5 && row->entity_type()!=10 && (d->required_value()!=-1 || d->site_available() || d->matching_locations()!=0 || d->location_id()!=-1))return "invalid blank tracker details";
      } else if(a->tracker_details())return "unexpected tracker details";
    } else if(a->tracker_details() || (a->tracker_rows() && a->tracker_rows()->size()))return "unexpected tracker rows";
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
