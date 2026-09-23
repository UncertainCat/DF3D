#include "wm/world_model.h"
#include <set>
#include <tuple>

namespace wm {
void WorldModel::ingestSpatters(const SnapshotData& snap, const std::vector<MaterialId>& remap) {
  std::set<BlockPos> seen;
  const auto mark = [&](BlockPos p) { pendingSpatters_.insert(p); ++spatterVersion_; };
  for (const auto& obs : snap.spatters) {
    if (!inBlockRange(obs.pos)) continue;
    seen.insert(obs.pos);
    auto entries = obs.entries;
    for (auto& e : entries) e.material = e.material < remap.size() ? remap[e.material] : kNoMaterial;
    std::sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) {
      return std::tie(a.tile,a.material,a.state,a.amount) < std::tie(b.tile,b.material,b.state,b.amount);
    });
    const auto old = spatters_.find(obs.pos);
    if (entries.empty()) {
      if (old != spatters_.end()) { spatters_.erase(old); mark(obs.pos); }
    } else if (old == spatters_.end() || *old->second != entries) {
      spatters_[obs.pos] = std::make_shared<const std::vector<GroundSpatter>>(std::move(entries));
      mark(obs.pos);
    }
  }
  if (snap.spatterScope == ChangeScope::Full) for (auto it = spatters_.begin(); it != spatters_.end();) {
    if (!seen.count(it->first)) { mark(it->first); it = spatters_.erase(it); } else ++it;
  }
}
const std::vector<GroundSpatter>& WorldModel::spattersAt(BlockPos pos) const {
  static const std::vector<GroundSpatter> empty;
  const auto it = spatters_.find(pos);
  return it == spatters_.end() ? empty : *it->second;
}
std::vector<BlockPos> WorldModel::drainSpatterEvents() {
  std::vector<BlockPos> out(pendingSpatters_.begin(), pendingSpatters_.end());
  pendingSpatters_.clear();
  out.insert(out.end(), restoredEvents_.spatters.begin(), restoredEvents_.spatters.end());
  restoredEvents_.spatters.clear();
  std::sort(out.begin(),out.end());
  out.erase(std::unique(out.begin(),out.end()),out.end());
  return out;
}
}
