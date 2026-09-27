#pragma once
#include "wm/management_client.h"
#include <memory>
#include <string>
#include <unordered_set>
#include <array>

namespace wm {
enum class ResidentInfoDemand { None, Residents, WorkDetails, WorkOrders };
// A completed paginated observation, not a same-tick simulation snapshot.
struct ResidentInfoSnapshot {
  ResidentInfoDemand demand = ResidentInfoDemand::None;
  uint64_t generation = 0, worldEpoch = 0;
  uint64_t captureStartedMs = 0, captureCompletedMs = 0;
  std::vector<CitizenInfo> citizens;
  std::vector<WorkDetailInfo> details;
  std::vector<WorkOrderInfo> orders;
  uint64_t detailListRevision = 0;
};
struct ResidentInfoStatus {
  ResidentInfoDemand demand = ResidentInfoDemand::None;
  uint64_t generation = 0, worldEpoch = 0;
  bool loading = false, stale = false;
  std::string error;
  uint64_t captureStartedMs = 0, captureCompletedMs = 0;
};
// Small transport seam for deterministic, engine-free pipeline tests.
class ResidentInfoTransport {
 public:
  virtual ~ResidentInfoTransport() = default;
  virtual void poll() = 0;
  virtual uint64_t send(const ManagementRequest&) = 0;
  virtual const ManagementState& state() const = 0;
  virtual const std::string& error() const = 0;
};
// Call on one owning thread at modest frequency. Getters never poll or copy rows.
class ResidentInfoService {
 public:
  explicit ResidentInfoService(std::string managementName = {});
  explicit ResidentInfoService(std::unique_ptr<ResidentInfoTransport> transport);
  void setDemand(ResidentInfoDemand demand);
  void refresh();
  void update(uint64_t nowMs, uint64_t worldEpoch);
  std::shared_ptr<const ResidentInfoSnapshot> snapshot() const { return completed_; }
  std::shared_ptr<const ResidentInfoSnapshot> cached(ResidentInfoDemand demand) const {
    const auto index=static_cast<size_t>(demand);
    return index<cache_.size()?cache_[index]:nullptr;
  }
  const ResidentInfoStatus& status() const { return status_; }
 private:
  void fail(const std::string& error, uint64_t nowMs);
  void clearCollection();
  std::string managementName_;
  std::unique_ptr<ResidentInfoTransport> transport_;
  bool injected_ = false, ready_ = false, requested_ = true;
  bool obsolete_ = false;
  uint64_t pending_ = 0, sentMs_ = 0, nextRefreshMs_ = 0, generation_ = 0;
  uint32_t cursor_ = 0;
  ManagementAction expected_ = ManagementAction::Catalog;
  ResidentInfoStatus status_;
  std::unique_ptr<ResidentInfoSnapshot> collecting_;
  std::shared_ptr<const ResidentInfoSnapshot> completed_;
  std::array<std::shared_ptr<const ResidentInfoSnapshot>,4> cache_{};
  bool detailPhase_ = false;
  std::unordered_set<int32_t> seen_;
  uint64_t detailRevision_ = 0;
  bool haveDetailRevision_ = false;
};
} // namespace wm
