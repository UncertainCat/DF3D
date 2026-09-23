#pragma once
#include <algorithm>
#include <cstdint>
#include <string>
#include <tuple>
#include <vector>
namespace df3d_session {
struct PetitionPartyIdentity {
  uintptr_t identity=0; int32_t id=-1;
  std::vector<int32_t> entities,histfigs;
  std::vector<std::string> names;
  bool operator==(const PetitionPartyIdentity& o)const{return std::tie(identity,id,entities,histfigs,names)==std::tie(o.identity,o.id,o.entities,o.histfigs,o.names);}
};
struct PetitionIdentity {
  // Process-local identities are compared only, never serialized or dereferenced.
  uintptr_t agreement=0,subject=0,location=0,screen=0;
  int32_t id=-1,selected=-1; uint32_t flags=0;
  std::vector<int32_t> terms,pending,continuing,uiIds,requirements;
  std::vector<PetitionPartyIdentity> parties;
  std::string context;
  bool complete=false,open=false,responsible=false;
  bool operator==(const PetitionIdentity& o)const{return std::tie(agreement,subject,location,screen,id,selected,flags,terms,pending,continuing,uiIds,requirements,parties,context,complete,open,responsible)==std::tie(o.agreement,o.subject,o.location,o.screen,o.id,o.selected,o.flags,o.terms,o.pending,o.continuing,o.uiIds,o.requirements,o.parties,o.context,o.complete,o.open,o.responsible);}
};
class PetitionReceipt {
 public:
  uint64_t observe(uint64_t epoch,const PetitionIdentity& now,bool allowed) {
    allowed=allowed&&epoch&&now.complete&&now.open&&now.pending.size()<=1&&(now.pending.empty()||now.pending[0]==now.id)&&((now.uiIds.empty()&&now.selected==-1)||(now.uiIds==std::vector<int32_t>{now.id}&&now.selected==now.id))&&!(blockedEpoch_==epoch&&uncertainContext(now));
    if(epoch!=epoch_||!(now==current_)||allowed!=allowed_){epoch_=epoch;current_=now;allowed_=allowed;receipt_=allowed?++counter_:0;}
    return pending_?0:receipt_;
  }
  bool consume(uint64_t epoch,uint64_t receipt,bool approve) {
    if(pending_||!allowed_||!receipt||receipt!=receipt_||epoch!=epoch_)return false;
    before_=current_;consumedEpoch_=epoch;approve_=approve;pending_=true;receipt_=0;allowed_=false;return true;
  }
  bool transitioned(uint64_t epoch,const PetitionIdentity& now)const {
    if(!pending_||epoch!=consumedEpoch_||!now.complete)return false;
    auto expected=before_;expected.pending.clear();expected.uiIds.clear();expected.selected=-1;
    auto observed=now;
    if(approve_){expected.flags&=~uint32_t(1);if(std::count(observed.continuing.begin(),observed.continuing.end(),expected.id)!=1||std::count(expected.continuing.begin(),expected.continuing.end(),expected.id))return false;observed.continuing.erase(std::find(observed.continuing.begin(),observed.continuing.end(),expected.id));}
    return expected==observed;
  }
  bool pending()const{return pending_;}
  // An uncertain consumed input is never automatically retried.
  void finish(bool verified=false){pending_=false;allowed_=false;receipt_=0;if(!verified){blocked_=before_;blockedEpoch_=consumedEpoch_;hasBlocked_=true;}}
  bool uncertainContext(const PetitionIdentity& now)const{return hasBlocked_&&now==blocked_;}
 private:
  uint64_t epoch_=0,counter_=0,receipt_=0,consumedEpoch_=0,blockedEpoch_=0;
  bool allowed_=false,pending_=false,approve_=false,hasBlocked_=false;
  PetitionIdentity current_,before_,blocked_;
};
}
