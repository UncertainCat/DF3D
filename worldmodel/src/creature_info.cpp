#include "wm/creature_info.h"
#include <algorithm>
namespace wm {
namespace {
class CreatureTransport final:public ResidentInfoTransport {
 public:
  explicit CreatureTransport(std::unique_ptr<ManagementClient> client):client_(std::move(client)){}
  void poll() override {client_->poll();}
  uint64_t send(const ManagementRequest& r) override{return client_->send(r);}
  const ManagementState& state()const override{return client_->state();}
  const std::string& error()const override{return client_->lastError();}
 private:std::unique_ptr<ManagementClient> client_;
};
}
void CreatureInfoService::demand(int32_t id) {
 if(id==demand_)return;
 if(demand_>=0)states_[demand_].loading=false;
 demand_=id;requested_=true;obsolete_=pending_!=0;
 if(id>=0){auto& s=states_[id];s.worldEpoch=epoch_;s.stale=bool(snapshot(id));}
 while(states_.size()>64){auto it=std::find_if(states_.begin(),states_.end(),[&](const auto& entry){return entry.first!=demand_ && entry.first!=pendingId_ && !cache_.count(entry.first);});if(it==states_.end())break;states_.erase(it);}
}
std::shared_ptr<const CreaturePublication> CreatureInfoService::snapshot(int32_t id)const {
 const auto it=cache_.find(id);return it==cache_.end()?nullptr:it->second;
}
CreatureInfoStatus CreatureInfoService::status(int32_t id)const {
 const auto it=states_.find(id);return it==states_.end()?CreatureInfoStatus{epoch_,false,false,{}}:it->second;
}
void CreatureInfoService::failure(std::string error,uint64_t nowMs) {
 if(demand_>=0)states_[demand_]={epoch_,false,bool(snapshot(demand_)),std::move(error)};
 pending_=0;obsolete_=false;ready_=false;requested_=false;nextMs_=nowMs+5000;
 if(!injected_)transport_.reset();
}
void CreatureInfoService::update(uint64_t nowMs,uint64_t epoch) {
 if(epoch_!=epoch){epoch_=epoch;cache_.clear();states_.clear();pending_=0;obsolete_=false;ready_=false;requested_=true;if(!injected_)transport_.reset();}
 if(!epoch)return;
 if(!transport_) {
  if(demand_<0 || (!requested_ && nowMs<nextMs_))return;
  std::string error;auto client=ManagementClient::open(error);
  if(!client){failure(error,nowMs);return;}
  transport_=std::make_unique<CreatureTransport>(std::move(client));
 }
 transport_->poll();const auto& s=transport_->state();
 if(s.worldEpoch!=epoch){cache_.clear();states_.clear();failure("Creature world changed",nowMs);return;}
 if(!transport_->error().empty()){failure(transport_->error(),nowMs);return;}
 if(pending_) {
  if(nowMs>=sentMs_ && nowMs-sentMs_>=15000){failure("Creature request timed out",nowMs);return;}
  if(s.requestSeq!=pending_ || s.action!=action_ || s.status==ManagementStatus::Pending || s.status==ManagementStatus::Idle)return;
  pending_=0;
  if(obsolete_){obsolete_=false;ready_=false;}
  else if(s.status!=ManagementStatus::Ok){failure(s.message,nowMs);return;}
  else if(action_==ManagementAction::Catalog)ready_=true;
  else {
   if(s.creature.unitId!=pendingId_){failure("Creature response identity changed",nowMs);return;}
   auto value=std::make_shared<CreaturePublication>();value->detail=s.creature;
   value->worldEpoch=epoch;value->generation=++generation_;value->captureStartedMs=startedMs_;value->captureCompletedMs=nowMs;
   cache_[pendingId_]=value;states_[pendingId_]={epoch,false,false,{}};nextMs_=nowMs+5000;
   // Bound retained creature details, evicting the oldest publication.
   while(cache_.size()>32){auto oldest=std::min_element(cache_.begin(),cache_.end(),[](const auto& a,const auto& b){return a.second->generation<b.second->generation;});states_.erase(oldest->first);cache_.erase(oldest);}
   return;
  }
 }
 if(demand_<0 || (!requested_ && nowMs<nextMs_))return;
 if(!states_[demand_].loading)startedMs_=nowMs;
 states_[demand_]={epoch,true,bool(snapshot(demand_)),{}};
 ManagementRequest r;r.action=ready_?ManagementAction::CreatureInspect:ManagementAction::Catalog;r.creatureUnitId=demand_;
 action_=r.action;pendingId_=demand_;sentMs_=nowMs;pending_=transport_->send(r);
 // Catalog completion must still issue the desired creature request.
 if(ready_)requested_=false;
 if(!pending_)failure(transport_->error().empty()?"Cannot request creature":transport_->error(),nowMs);
}
}
