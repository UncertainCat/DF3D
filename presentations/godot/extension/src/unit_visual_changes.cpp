#include "df3d_world.h"
#include <unordered_set>

namespace df3d_godot {
void Df3dWorld::updateUnitVisualChanges() {
    godot::PackedInt32Array changed;
    godot::PackedInt64Array removed;
    std::unordered_set<wm::UnitId> live;
    const auto ordinals = unit_stack_ordinals();
    const auto tiles = unit_stack_tiles();
    for (int i = 0; i < ids_.size(); ++i) {
        const wm::UnitId id = ids_[i]; live.insert(id);
        UnitVisualKey key;
        key.from = unitMotionFrom_[i]; key.to = unitMotionTo_[i]; key.epochs = unitMotionEpochs_[i];
        key.region = spriteRegions_[i]; key.scale = unitScaleParams_[i]; key.color = colors_[i];
        key.size = spriteSizes_[i]; key.slot = spriteSlots_[i]; key.job = unitJobs_[i];
        key.segment = unitMotionSegments_[i]; key.attack = unitAttackIds_[i]; key.target = unitAttackTargets_[i];
        key.statusFlags = unitStatusFlags_[i];
        key.ordinal = ordinals[i]; key.stackTile = tiles[i];
        const auto found = unitVisualKeys_.find(id);
        if (found == unitVisualKeys_.end() || found->second != key) {
            changed.push_back(i); unitVisualKeys_[id] = key;
        }
    }
    for (auto it = unitVisualKeys_.begin(); it != unitVisualKeys_.end();) {
        if (!live.count(it->first)) { removed.push_back(it->first); it = unitVisualKeys_.erase(it); }
        else ++it;
    }
    if (changed.is_empty() && removed.is_empty()) return;
    unitChangedIndices_ = changed; unitRemovedIds_ = removed;
    unitDeltaBase_ = unitRenderRevision_++;
}
godot::Dictionary Df3dWorld::unit_render_delta(int64_t since) const {
    godot::Dictionary out;
    const bool same = uint64_t(since) == unitRenderRevision_;
    const bool full = !same && uint64_t(since) != unitDeltaBase_;
    godot::PackedInt32Array changed;
    if (full) { changed.resize(ids_.size()); for (int i = 0; i < ids_.size(); ++i) changed.set(i, i); }
    else if (!same) changed = unitChangedIndices_;
    out["indices"] = changed;
    out["removed"] = same ? godot::PackedInt64Array() : unitRemovedIds_;
    out["full"] = full; out["revision"] = int64_t(unitRenderRevision_);
    return out;
}
}
