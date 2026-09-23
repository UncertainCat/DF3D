#include "interruption.h"
#include "interruption_policy.h"
#include "announcement_button.h"
#include "modules/Gui.h"
#include "modules/World.h"
#include "modules/Screen.h"
#include "modules/Translation.h"
#include "df/gamest.h"
#include "df/world.h"
#include "df/global_objects.h"
#include "df/viewscreen_dwarfmodest.h"
#include "df/popup_message.h"
#include "df/interface_key.h"
#include "df/plotinfost.h"
#include "df/graphic.h"
#include "df/enabler.h"
#include "df/markup_text_wordst.h"
#include <set>
namespace df3d_session {
using namespace DFHack;
namespace {
InterruptionInfo info;
InterruptionReceipt receipts;
uint64_t currentEpoch=0;
uint64_t ackEpoch=0;
bool currentValid=false,currentBusy=false;
int result=0;
PopupIdentity identity() {
  PopupIdentity value;
  if(!df::global::world)return value;
  const auto& popups=df::global::world->status.popups;
  if(popups.size()>256){value.complete=false;return value;}
  for(auto* p:popups)value.queue.push_back(reinterpret_cast<uintptr_t>(p));
  if(!popups.empty()&&popups.front()) {
    if(popups.front()->text.size()<=32768)value.text=popups.front()->text;else value.complete=false;
    value.portrait=popups.front()->portrait_hfid;
    value.color=popups.front()->color;value.bright=popups.front()->bright;
  }
  return value;
}
}
const InterruptionInfo& observeInterruption(uint64_t epoch,bool valid,bool busy) {
  currentEpoch=epoch;currentValid=valid;currentBusy=busy;info={};
  const auto current=identity();
  if(receipts.pending()) {
    result=valid&&!busy&&receipts.transitioned(epoch,current)?2:3;
    receipts.finish();
    if(valid&&epoch==ackEpoch)World::SetPauseState(true);
  }
  if(!valid||!df::global::game||!df::global::world) {receipts.observe(0,{},false);return info;}
  auto& m=df::global::game->main_interface;
  auto* top=Gui::getCurViewscreen(true);
  auto focus=Gui::getFocusStrings(top);
  auto* fortScreen=virtual_cast<df::viewscreen_dwarfmodest>(top);
  const bool defaultView=fortScreen&&focus.size()==1&&focus.front()=="dwarfmode/Default";
  auto* p=df::global::plotinfo;
  const char* otherPanel=nullptr;
  if(!p)otherPanel="Fortress interface unavailable";
  // DF can retain keyRepeat while an information screen is open. Only the
  // default map context represents single-stepping; preserve the modal's identity.
  else if(defaultView&&fortScreen->keyRepeat)otherPanel="Single-step input";
  else if(p->main.mode!=df::ui_sidebar_mode::Default && (p->main.mode!=df::ui_sidebar_mode::Squads || p->squads.in_kill_order || p->squads.in_move_order))otherPanel="Sidebar action";
  else if(m.squads.open&&(m.squads.giving_kill_order||m.squads.giving_move_order||m.squads.giving_patrol_order||m.squads.giving_burrow_order))otherPanel="Squad orders";
  else if(m.bottom_mode_selected==df::main_bottom_mode_type::BUILDING_PICK_MATERIALS)otherPanel="Building material selection";
  else if(m.view_sheets.open&&m.view_sheets.unit_overview_expelling)otherPanel="Citizen expulsion";
  else if(m.create_work_order.open)otherPanel="Work order editor";
  else if(m.info.open) {
    const bool administrators=fortScreen && focus.size()==1 &&
      (focus.front()=="dwarfmode/Info/ADMINISTRATORS/Default" ||
       focus.front()=="dwarfmode/Info/ADMINISTRATORS/Candidates");
    const bool kitchen=fortScreen && focus.size()==1 &&
      (focus.front()=="dwarfmode/Info/LABOR/KITCHEN/PLANTS" ||
       focus.front()=="dwarfmode/Info/LABOR/KITCHEN/SEEDS" ||
       focus.front()=="dwarfmode/Info/LABOR/KITCHEN/DRINK" ||
       focus.front()=="dwarfmode/Info/LABOR/KITCHEN/OTHER" ||
       focus.front()=="dwarfmode/Info/LABOR/KITCHEN/NONE");
    otherPanel=administrators?"Nobles and administrators panel":kitchen?"Kitchen panel":"Information panel";
  }
  else if(m.stocks.open)otherPanel="Stocks panel";
  else if(m.name_creator.open)otherPanel="Name editor";
  else if(m.image_creator.open)otherPanel="Image editor";
  else if(m.assign_vehicle.open)otherPanel="Vehicle assignment";
  else if(m.job_details.open)otherPanel="Job details";
  else if(m.options.open)otherPanel="Options menu";
  else if(m.assign_display_item.open)otherPanel="Display item assignment";
  else if(m.custom_stockpile.open)otherPanel="Stockpile settings";
  const auto& popups=df::global::world->status.popups;
  info.popupCount=static_cast<uint32_t>(popups.size());
  // Explicit decision categories win over passive text. Unknown native panels never close.
  if(m.diplomacy.open){info.kind=4;info.reason="Diplomacy needs a decision in Dwarf Fortress";}
  else if(m.petitions.open){info.kind=5;info.reason="A petition needs a decision in Dwarf Fortress";}
  else if(m.trade.open||m.assign_trade.open){info.kind=6;info.reason="Trade is open in Dwarf Fortress";}
  else if(m.announcement_alert.open){info.kind=3;info.reason="An announcement viewer is open in Dwarf Fortress";}
  else if(!defaultView||otherPanel){info.kind=7;info.reason=otherPanel?std::string(otherPanel)+" needs attention in Dwarf Fortress":"A native screen needs attention in Dwarf Fortress";}
  else if(!popups.empty()) {
    info.kind=2;
    if(popups.size()>256||!popups.front()||popups.front()->text.size()>32768)info.reason="This announcement exceeds the supported text or queue limit; read it in Dwarf Fortress";
    else {
      info.text=DF2UTF(popups.front()->text);
      if(info.text.size()>32768){info.text.clear();info.reason="This announcement exceeds the supported text limit; read it in Dwarf Fortress";}
      else if(busy||!epoch)info.reason="Wait for the current session operation";
      else info.canAcknowledge=true;
    }
  } else if(World::ReadPauseState()) {
    if(df::global::pause_state&&*df::global::pause_state)info.kind=1;
    else {info.kind=7;info.reason="Dwarf Fortress is waiting for a native action";}
  }
  info.receipt=receipts.observe(epoch,current,info.canAcknowledge);
  return info;
}
bool acknowledgeInterruption(uint64_t epoch,uint64_t receipt,std::string& error) {
  // Re-observe immediately, including native top screen and full front content.
  observeInterruption(currentEpoch,currentValid,currentBusy);
  if(!info.canAcknowledge||epoch!=currentEpoch||receipt!=info.receipt) {
    error="That announcement changed or cannot be acknowledged";return false;
  }
  const auto size=Screen::getWindowSize();
  if(size.x<32||size.y<1||size.x>512||size.y>256||size.x*size.y>32768){error="Native announcement viewport is unsupported";return false;}
  const auto& box=df::global::world->status.mega_text;
  std::string anchor;int firstY=-1;size_t wordsScanned=0;
  for(auto* word:box.word) {
    if(++wordsScanned>128)break;
    if(!word||word->str.empty())continue;
    if(firstY<0)firstY=word->py;
    if(word->py!=firstY||anchor.size()+word->str.size()+1>48)break;
    if(!anchor.empty())anchor+=' ';
    anchor+=word->str;
    if(anchor.size()>=20)break;
  }
  std::vector<std::string> rows;
  for(int y=0;y<size.y;++y){std::string row;for(int x=0;x<size.x;++x){char ch=char(Screen::readTile(x,y).ch);row+=ch?ch:' ';}rows.push_back(std::move(row));}
  const auto target=passiveAnnouncementButton(rows,anchor,box.max_y,info.popupCount);
  if(target.first<0){error="The native announcement button was not uniquely identified beneath this announcement";return false;}
  auto* gps=df::global::gps;auto* enabler=df::global::enabler;
  if(!gps||!enabler||!receipts.consume(epoch,receipt)){error="Native announcement input changed";return false;}
  auto* top=virtual_cast<df::viewscreen_dwarfmodest>(Gui::getCurViewscreen(true));
  if(!top){receipts.finish();error="The native screen changed";return false;}
  World::SetPauseState(true);
  const int x=gps->mouse_x,y=gps->mouse_y,px=gps->precise_mouse_x,py=gps->precise_mouse_y;
  const auto button=enabler->mouse_lbut,tracking=enabler->tracking_on;
  gps->mouse_x=target.first;gps->mouse_y=target.second;
  gps->precise_mouse_x=target.first*gps->tile_pixel_x;gps->precise_mouse_y=target.second*gps->tile_pixel_y;
  enabler->mouse_lbut=1;enabler->tracking_on=1;
  std::set<df::interface_key> keys;
  top->feed(&keys);
  enabler->mouse_lbut=button;enabler->tracking_on=tracking;
  gps->mouse_x=x;gps->mouse_y=y;gps->precise_mouse_x=px;gps->precise_mouse_y=py;
  World::SetPauseState(true);
  ackEpoch=epoch;result=1;info.canAcknowledge=false;info.receipt=0;return true;
}
int interruptionResult(std::string& message) {
  const int value=result;
  if(value>=2){message=value==2?"Announcement acknowledged; fortress remains paused":"Native announcement transition was not verified; inspect Dwarf Fortress";result=0;}
  return value;
}
void resetInterruption(){info={};receipts=InterruptionReceipt{};currentEpoch=0;currentValid=currentBusy=false;result=0;}
}
