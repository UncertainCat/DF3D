#pragma once
#include "wm/resident_info.h"
#include <map>
namespace wm {
struct CreaturePublication {
  CreatureInfo detail;
  uint64_t worldEpoch=0,generation=0,captureStartedMs=0,captureCompletedMs=0;
};
struct CreatureInfoStatus {
  uint64_t worldEpoch=0;
  bool loading=false,stale=false;
  std::string error;
};
class CreatureInfoService {
 public:
  CreatureInfoService()=default;
  explicit CreatureInfoService(std::unique_ptr<ResidentInfoTransport> transport):transport_(std::move(transport)),injected_(true){}
  void demand(int32_t unitId);
  void update(uint64_t nowMs,uint64_t worldEpoch);
  std::shared_ptr<const CreaturePublication> snapshot(int32_t id) const;
  CreatureInfoStatus status(int32_t id) const;
 private:
  void failure(std::string error,uint64_t nowMs);
  std::unique_ptr<ResidentInfoTransport> transport_;
  bool injected_=false,ready_=false,obsolete_=false,requested_=true;
  int32_t demand_=-1,pendingId_=-1;
  uint64_t epoch_=0,pending_=0,sentMs_=0,startedMs_=0,nextMs_=0,generation_=0;
  ManagementAction action_=ManagementAction::Catalog;
  std::map<int32_t,std::shared_ptr<const CreaturePublication>> cache_;
  std::map<int32_t,CreatureInfoStatus> states_;
};
}
