#include "wm/resident_info.h"
#include <utility>

namespace wm {
namespace {
constexpr uint64_t refreshIntervalMs = 5000, timeoutMs = 15000;
constexpr size_t maxRows = 100000;
class ClientTransport final : public ResidentInfoTransport {
 public:
  explicit ClientTransport(std::unique_ptr<ManagementClient> client) : client_(std::move(client)) {}
  void poll() override { client_->poll(); }
  uint64_t send(const ManagementRequest& r) override { return client_->send(r); }
  const ManagementState& state() const override { return client_->state(); }
  const std::string& error() const override { return client_->lastError(); }
 private:
  std::unique_ptr<ManagementClient> client_;
};
ManagementAction actionFor(ResidentInfoDemand d) {
  if(d == ResidentInfoDemand::Residents) return ManagementAction::CitizenList;
  if(d == ResidentInfoDemand::WorkDetails) return ManagementAction::WorkDetailList;
  return ManagementAction::WorkOrderList;
}
}
ResidentInfoService::ResidentInfoService(std::string name) : managementName_(std::move(name)) {}
ResidentInfoService::ResidentInfoService(std::unique_ptr<ResidentInfoTransport> t)
    : transport_(std::move(t)), injected_(true) {}
void ResidentInfoService::clearCollection() {
  collecting_.reset(); seen_.clear(); cursor_=0; haveDetailRevision_=false; detailPhase_=false;
}
void ResidentInfoService::setDemand(ResidentInfoDemand demand) {
  if(status_.demand == demand) return;
  status_.demand=demand; completed_=cache_[static_cast<size_t>(demand)]; clearCollection();
  status_.generation=++generation_;
  status_.loading=false; status_.stale=bool(completed_); status_.error.clear();
  status_.captureStartedMs=completed_?completed_->captureStartedMs:0;
  status_.captureCompletedMs=completed_?completed_->captureCompletedMs:0;
  obsolete_=pending_!=0; requested_=true;
}
void ResidentInfoService::refresh() { requested_=true; }
void ResidentInfoService::fail(const std::string& error, uint64_t nowMs) {
  clearCollection(); pending_=0; obsolete_=false;
  status_.loading=false; status_.stale=bool(completed_); status_.error=error;
  status_.generation=++generation_;
  nextRefreshMs_=nowMs+refreshIntervalMs; requested_=false;
  // A failed or timed out connection may still own an outstanding request.
  if(!injected_) transport_.reset();
  ready_=false;
}
void ResidentInfoService::update(uint64_t nowMs, uint64_t epoch) {
  if(status_.worldEpoch != epoch) {
    completed_.reset(); cache_={}; clearCollection(); pending_=0; obsolete_=false; ready_=false;
    status_.generation=++generation_;
    status_.worldEpoch=epoch; status_.loading=false; status_.stale=false;
    status_.error.clear(); status_.captureStartedMs=status_.captureCompletedMs=0;
    requested_=true;
    if(!injected_) transport_.reset();
  }
  if(!epoch) return;
  if(!transport_) {
    if(status_.demand==ResidentInfoDemand::None || (!requested_ && nowMs<nextRefreshMs_)) return;
    std::string error;
    auto client=ManagementClient::open(error,managementName_);
    if(!client) { fail(error,nowMs); return; }
    transport_=std::make_unique<ClientTransport>(std::move(client));
  }
  transport_->poll();
  const auto& s=transport_->state();
  // Invalidate even when no panel is demanding data or no request is pending.
  if(s.worldEpoch != epoch) {
    completed_.reset(); cache_={};
    fail("Management world changed; waiting for current fortress",nowMs);
    return;
  }
  if(!transport_->error().empty()) { fail(transport_->error(),nowMs); return; }
  if(pending_) {
    if(nowMs>=sentMs_ && nowMs-sentMs_>=timeoutMs) { fail("Resident information request timed out",nowMs); return; }
    if(s.requestSeq!=pending_ || s.action!=expected_ || s.status==ManagementStatus::Pending || s.status==ManagementStatus::Idle) return;
    pending_=0;
    if(obsolete_) { obsolete_=false; ready_=false; }
    else if(s.status!=ManagementStatus::Ok) { fail(s.message.empty()?"Resident information unavailable":s.message,nowMs); return; }
    else if(expected_==ManagementAction::Catalog) ready_=true;
    else if(collecting_) {
      uint32_t next=0;
      if(expected_==ManagementAction::CitizenList || expected_==ManagementAction::WorkDetailList) {
        const auto revision=s.citizen.detailListRevision;
        if(revision<=0 || (haveDetailRevision_ && uint64_t(revision)!=detailRevision_)) {
          fail("Work details changed during collection; refresh required",nowMs); return;
        }
        detailRevision_=revision; haveDetailRevision_=true;
        collecting_->detailListRevision=revision;
      }
      if(expected_==ManagementAction::CitizenList) {
        for(const auto& row:s.citizen.citizens) if(seen_.insert(row.id).second) collecting_->citizens.push_back(row);
        next=s.citizen.nextCursor;
      } else if(expected_==ManagementAction::WorkDetailList) {
        for(const auto& row:s.citizen.details)
          if(seen_.insert(row.index).second) collecting_->details.push_back(row);
        next=s.citizen.nextCursor;
      } else {
        for(const auto& row:s.workOrder.orders) if(seen_.insert(row.id).second) collecting_->orders.push_back(row);
        next=s.workOrder.nextCursor;
      }
      if(seen_.size()>maxRows) { fail("Resident information exceeds collection limit",nowMs); return; }
      if(next && next<=cursor_) { fail("Resident information cursor did not advance",nowMs); return; }
      cursor_=next;
      if(!next) {
        if((collecting_->demand==ResidentInfoDemand::WorkDetails || collecting_->demand==ResidentInfoDemand::Residents) && !detailPhase_) {
          detailPhase_=true; seen_.clear();
        } else {
          collecting_->captureCompletedMs=nowMs;
          status_.generation=collecting_->generation=++generation_;
          status_.captureStartedMs=collecting_->captureStartedMs;
          status_.captureCompletedMs=nowMs;
          completed_=std::move(collecting_);
          cache_[static_cast<size_t>(status_.demand)]=completed_;
          status_.loading=false; status_.stale=false; status_.error.clear();
          nextRefreshMs_=nowMs+refreshIntervalMs;
          seen_.clear();
          return;
        }
      }
    }
  }
  if(status_.demand==ResidentInfoDemand::None) return;
  if(!collecting_) {
    if(!requested_ && nowMs<nextRefreshMs_) return;
    requested_=false; clearCollection();
    collecting_=std::make_unique<ResidentInfoSnapshot>();
    collecting_->demand=status_.demand; collecting_->worldEpoch=epoch;
    collecting_->generation=++generation_; collecting_->captureStartedMs=nowMs;
    status_.loading=true; status_.stale=bool(completed_); status_.error.clear();
    status_.generation=++generation_;
    status_.captureStartedMs=nowMs;
  }
  ManagementRequest request;
  request.action=ready_?actionFor(status_.demand):ManagementAction::Catalog;
  if(ready_ && (status_.demand==ResidentInfoDemand::WorkDetails || status_.demand==ResidentInfoDemand::Residents))
    request.action=detailPhase_?ManagementAction::WorkDetailList:ManagementAction::CitizenList;
  if(request.action==ManagementAction::WorkDetailList && cursor_>0)
    request.citizen.expectedListRevision=detailRevision_;
  request.citizen.cursor=cursor_; request.workOrder.cursor=cursor_;
  expected_=request.action;
  pending_=transport_->send(request); sentMs_=nowMs;
  if(!pending_) fail(transport_->error().empty()?"Cannot request resident information":transport_->error(),nowMs);
}
} // namespace wm
