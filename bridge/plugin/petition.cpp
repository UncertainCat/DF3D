#include "petition.h"
#include "petition_policy.h"
#include "petition_button.h"
#include "modules/Gui.h"
#include "modules/World.h"
#include "modules/Screen.h"
#include "modules/Translation.h"
#include "df/gamest.h"
#include "df/world.h"
#include "df/global_objects.h"
#include "df/viewscreen_dwarfmodest.h"
#include "df/plotinfost.h"
#include "df/agreement.h"
#include "df/agreement_party.h"
#include "df/agreement_details.h"
#include "df/agreement_details_data_location.h"
#include "df/historical_entity.h"
#include "df/historical_figure.h"
#include "df/graphic.h"
#include "df/enabler.h"
#include "df/interface_key.h"
#include "df/profession.h"
#include <set>
namespace df3d_session {
using namespace DFHack;
namespace {
PetitionInfo info;
PetitionReceipt receipts;
PetitionIdentity current,before;
uint64_t currentEpoch=0,operationEpoch=0,revision=0;
bool currentValid=false,currentBusy=false;
int32_t reviewed=-1;
int operation=0,result=0,completedAction=0;
std::string applicantNative;
std::string context() {
 auto* p=df::global::plotinfo;auto* g=df::global::game;auto* w=df::global::world;
 auto* top=virtual_cast<df::viewscreen_dwarfmodest>(Gui::getCurViewscreen(true));
 if(!p||!g||!w||!top||top->keyRepeat||!w->status.popups.empty())return {};
 auto& m=g->main_interface;
 auto f=Gui::getFocusStrings(top);
 if(f.size()!=1 || (f[0]!="dwarfmode/Default"&&f[0]!="dwarfmode/Petitions"))return {};
 if(p->main.mode!=df::ui_sidebar_mode::Default||m.diplomacy.open||m.trade.open||m.assign_trade.open||m.announcement_alert.open||m.info.open||m.stocks.open||m.name_creator.open||m.image_creator.open||m.options.open||m.create_work_order.open||m.job_details.open||m.assign_vehicle.open||m.assign_display_item.open||m.custom_stockpile.open||m.view_sheets.open||m.squads.open)return {};
 if((f[0]=="dwarfmode/Petitions")!=m.petitions.open)return {};
 return f[0];
}
PetitionIdentity capture(int32_t id) {
 PetitionIdentity v;v.id=id;v.context=context();v.screen=reinterpret_cast<uintptr_t>(Gui::getCurViewscreen(true));
 auto* p=df::global::plotinfo;auto* g=df::global::game;
 if(!p||!g||v.context.empty())return v;
 auto& ui=g->main_interface.petitions;
 v.open=ui.open;v.responsible=ui.have_responsible_person;v.selected=ui.selected_agreement_id;
 if(p->petitions.size()>4096||p->continuing_agreement_id.size()>4096||ui.agreement_id.size()>4096)return v;
 v.pending=p->petitions;v.continuing=p->continuing_agreement_id;v.uiIds=ui.agreement_id;
 v.requirements={p->main.custom_difficulty.guildhall_value,p->main.custom_difficulty.grand_guildhall_value};
 v.context+=':'+std::to_string(ui.scroll_position)+':'+std::to_string(ui.scrolling);
 if(id<0){v.complete=v.pending.empty()&&v.uiIds.empty()&&v.selected==-1;return v;}
 auto* a=df::agreement::find(id);
 if(!a||a->details.size()!=1||a->parties.size()!=2)return v;
 auto* d=a->details[0];
 if(!d||d->type!=df::agreement_details_type::Location||!d->data.Location)return v;
 auto* l=d->data.Location;
 if(l->type!=df::abstract_building_type::GUILDHALL||l->tier!=1||l->site!=p->site_id||!is_valid_enum_item(l->profession)||int(l->profession)<0||!ENUM_ATTR(profession,caption,l->profession)||d->year<0||d->year_tick<0||d->year_tick>=403200||v.requirements[0]<0||v.requirements[1]<0)return v;
 v.agreement=reinterpret_cast<uintptr_t>(a);v.subject=reinterpret_cast<uintptr_t>(d);v.location=reinterpret_cast<uintptr_t>(l);v.flags=a->flags.whole;
 v.terms={a->next_party_id,a->next_details_id,a->smm_x,a->smm_y,d->id,d->year,d->year_tick,int(d->type),l->applicant,l->government,l->site,int(l->type),int(l->deity_type),l->deity_data.practice_id,int(l->profession),l->tier,int(l->flags.whole)};
 std::set<int32_t> ids;
 for(auto* party:a->parties) {
  if(!party||party->id<0||!ids.insert(party->id).second||party->entity_ids.size()!=1||!party->histfig_ids.empty()||!party->complaint.empty())return v;
  auto* entity=df::historical_entity::find(party->entity_ids[0]);if(!entity)return v;
  auto english=Translation::translateName(&entity->name,true);auto native=Translation::translateName(&entity->name,false);
  if(english.empty()||english.size()>256||native.size()>256||DF2UTF(english).size()>1024)return v;
  v.parties.push_back({reinterpret_cast<uintptr_t>(party),party->id,party->entity_ids,party->histfig_ids,{english,native}});
 }
 if(l->applicant==l->government||!ids.count(l->applicant)||!ids.count(l->government))return v;
 v.complete=true;return v;
}
void describe(const PetitionIdentity& v) {
 info.id=v.id;info.hasAgreement=v.complete&&v.id>=0;
 if(v.requirements.size()==2){info.guildhallValue=v.requirements[0];info.grandGuildhallValue=v.requirements[1];}
 if(!info.hasAgreement)return;
 auto& a=info.agreement;a={};a.id=v.id;a.notApproved=(v.flags&1)!=0;a.concluded=(v.flags&2)!=0;a.continuing=std::find(v.continuing.begin(),v.continuing.end(),v.id)!=v.continuing.end();
 a.status=std::find(v.pending.begin(),v.pending.end(),v.id)!=v.pending.end()?0:(a.concluded?3:(a.notApproved?2:1));
 const auto& t=v.terms;df3d_management::AgreementDetail d;
 d.id=t[4];d.year=t[5];d.yearTick=t[6];d.kind=t[7];d.applicantParty=t[8];d.governmentParty=t[9];d.siteId=t[10];d.locationType=t[11];d.deityType=t[12];d.deityId=t[13];d.profession=t[14];d.tier=t[15];
 d.description="Guildhall, tier 1, for the "+std::string(ENUM_ATTR(profession,caption,df::profession(d.profession)))+" guild";a.summary=d.description;a.details={d};
 for(const auto& p:v.parties){a.parties.push_back({p.id,p.entities,p.histfigs,DF2UTF(p.names[0])});if(p.id==d.applicantParty)applicantNative=p.names[0];}
}
std::vector<std::string> rows() {
 const auto size=Screen::getWindowSize();if(size.x<32||size.x>512||size.y<1||size.y>256||size.x*size.y>32768)return {};
 std::vector<std::string> out;for(int y=0;y<size.y;++y){std::string row;for(int x=0;x<size.x;++x){char c=char(Screen::readTile(x,y).ch);row+=c?c:' ';}out.push_back(std::move(row));}return out;
}
bool feed(const std::pair<int,int>& target,bool close) {
 auto* top=virtual_cast<df::viewscreen_dwarfmodest>(Gui::getCurViewscreen(true));auto* gps=df::global::gps;auto* e=df::global::enabler;
 if(!top||!gps||!e)return false;
 World::SetPauseState(true);
 const int x=gps->mouse_x,y=gps->mouse_y,px=gps->precise_mouse_x,py=gps->precise_mouse_y;const auto b=e->mouse_lbut,t=e->tracking_on;
 std::set<df::interface_key> keys;
 if(close){e->mouse_lbut=0;keys.insert(df::interface_key::LEAVESCREEN);}
 else{gps->mouse_x=target.first;gps->mouse_y=target.second;gps->precise_mouse_x=target.first*gps->tile_pixel_x;gps->precise_mouse_y=target.second*gps->tile_pixel_y;e->mouse_lbut=1;e->tracking_on=1;}
 top->feed(&keys);e->mouse_lbut=b;e->tracking_on=t;gps->mouse_x=x;gps->mouse_y=y;gps->precise_mouse_x=px;gps->precise_mouse_y=py;World::SetPauseState(true);return true;
}
}
const PetitionInfo& observePetition(uint64_t epoch,bool valid,bool busy) {
 const auto previousInfo=info;const auto previousIdentity=current;
 currentEpoch=epoch;currentValid=valid;currentBusy=busy;info={};info.revision=revision;
 if(!valid||!epoch){if(receipts.pending())receipts.finish(true);receipts.observe(0,{},false);reviewed=-1;operation=0;return info;}
 if(!operation&&df::global::plotinfo&&df::global::game) {
   const auto& ui=df::global::game->main_interface.petitions;
   if(ui.open)reviewed=ui.selected_agreement_id;
   else reviewed=df::global::plotinfo->petitions.size()==1?df::global::plotinfo->petitions[0]:-1;
 }
 current=capture(reviewed);
 if(operation) {
  bool good=epoch==operationEpoch&&!busy&&current.complete;
  if(operation==5||operation==6)good=good&&receipts.transitioned(epoch,current);
  else if(operation==4){auto expected=before;expected.open=true;expected.responsible=current.responsible;expected.uiIds={reviewed};expected.selected=reviewed;expected.context=current.context;good=good&&current.context.find("dwarfmode/Petitions:")==0&&expected==current;}
  else {auto expected=before;expected.open=false;expected.context=current.context;good=good&&current.context.find("dwarfmode/Default:")==0&&expected==current;}
  result=good?2:3;completedAction=operation;if(operation!=4)receipts.finish(good);operation=0;if(epoch==operationEpoch)World::SetPauseState(true);
  if(good&&current.open&&current.pending.empty()&&current.uiIds.empty()&&current.selected==-1){reviewed=-1;current=capture(-1);}
 }
 describe(current);
 const bool single=current.pending==std::vector<int32_t>{current.id}&&std::find(current.continuing.begin(),current.continuing.end(),current.id)==current.continuing.end();
 const bool supported=current.complete&&current.id>=0&&single&&current.flags==1;
 if(busy)info.reason="Wait for the current session operation";
 else if(current.context.empty())info.reason="Close unrelated native panels before reviewing a petition";
 else if(!current.complete)info.reason="Responses currently support one ordinary guildhall request. Review other petitions in Dwarf Fortress.";
 else if(!supported&&current.id>=0)info.reason="Only one pending, unapproved guildhall request can be reviewed; use Dwarf Fortress";
 else if(!current.open){info.canReview=supported;info.reason=supported?"Review this request before responding":"There is no pending request to review";}
 else if(current.id<0&&current.pending.empty())info.reason="No pending request remains in this review. Return to agreements when ready.";
 else if(!current.responsible)info.reason="No responsible person is available; the review can be closed";
 else info.reason="Approval accepts a guildhall obligation; denial removes this pending request. The fortress stays paused.";
 info.canClose=!busy&&current.complete&&current.open;
 info.canRespond=info.canClose&&supported&&current.responsible&&current.selected==current.id&&current.uiIds==current.pending;
 info.receipt=receipts.observe(epoch,current,info.canClose);
 if(!info.receipt){info.canClose=info.canRespond=false;if(receipts.uncertainContext(current))info.reason="The consumed native input was not verified; inspect Dwarf Fortress before continuing";}
 if(!(previousIdentity==current)||previousInfo.canReview!=info.canReview||previousInfo.canRespond!=info.canRespond||previousInfo.canClose!=info.canClose||previousInfo.receipt!=info.receipt||previousInfo.reason!=info.reason)++revision;
 info.revision=revision;
 return info;
}
bool actPetition(uint8_t action,uint64_t epoch,int32_t id,uint64_t receipt,std::string& error) {
 observePetition(currentEpoch,currentValid,currentBusy);
 if(epoch!=currentEpoch||id!=info.id||!currentValid||currentBusy){error="The petition context changed";return false;}
 const bool close=action==7,review=action==4;
 if(review ? (!info.canReview||receipt) : (!receipt||receipt!=info.receipt||!(close?info.canClose:info.canRespond))){error="This petition cannot perform that action; "+info.reason;return false;}
 auto target=std::make_pair(-1,-1);
 if(!close){auto screen=rows();target=review?petitionLauncher(screen):petitionDecisionButton(screen,applicantNative,action==5);if(target.first<0){error="Native petition controls and request body were not uniquely identified";return false;}}
 if(!(capture(reviewed)==current)){error="The native petition changed before input";return false;}
 before=current;operationEpoch=epoch;
 if(!review&&!receipts.consume(epoch,receipt,action==5)){error="The petition receipt was already consumed";return false;}
 operation=action;
 if(!feed(target,close)){operation=0;receipts.finish();error="Native petition input unavailable; inspect Dwarf Fortress";return false;}
 info.canReview=info.canRespond=info.canClose=false;info.receipt=0;result=1;return true;
}
int petitionResult(std::string& message){int value=result;if(value>=2){if(value==2)message=std::string(completedAction==5?"Petition approved":completedAction==6?"Petition denied":completedAction==7?"Review closed":"Petition ready for review")+"; fortress remains paused";else message="The petition action could not be verified; inspect Dwarf Fortress before continuing";result=0;}return value;}
void resetPetition(){info={};receipts=PetitionReceipt{};current={};before={};currentEpoch=operationEpoch=0;reviewed=-1;operation=result=0;currentValid=currentBusy=false;}
flatbuffers::Offset<df3d::mirror::PetitionReviewState> serializePetition(flatbuffers::FlatBufferBuilder& b,const PetitionInfo& p) {
 namespace m=df3d::mirror;flatbuffers::Offset<m::AgreementInfo> agreement;
 if(p.hasAgreement){const auto& a=p.agreement;std::vector<flatbuffers::Offset<m::AgreementDetail>> ds;std::vector<flatbuffers::Offset<m::AgreementParty>> ps;
 for(const auto& d:a.details)ds.push_back(m::CreateAgreementDetail(b,d.id,d.kind,d.siteId,d.year,d.yearTick,d.applicantParty,d.governmentParty,d.locationType,d.tier,d.profession,d.deityType,d.deityId,b.CreateString(d.description)));
 for(const auto& q:a.parties)ps.push_back(m::CreateAgreementParty(b,q.id,b.CreateVector(q.entityIds),b.CreateVector(q.histfigIds),b.CreateString(q.name)));
 agreement=m::CreateAgreementInfo(b,a.id,m::AgreementStatus(a.status),a.notApproved,a.concluded,a.continuing,b.CreateVector(ds),b.CreateVector(ps),b.CreateString(a.summary),a.complete,b.CreateString(a.reason));}
 return m::CreatePetitionReviewState(b,p.id,p.receipt,p.canReview,p.canRespond,p.canClose,b.CreateString(p.reason),agreement,p.guildhallValue,p.grandGuildhallValue);
}
}
