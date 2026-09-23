#include "df3d_world.h"

namespace df3d_godot {
void Df3dWorld::collectAppearanceResources() {
    if (!spriteResources_.collectionPending && spriteResources_.membershipSeen==source_.model().unitMembershipVersion() &&
        spriteResources_.buildsSeen==compositeBuildCount_) return;
    spriteResources_.collectionPending=false;
    spriteResources_.membershipSeen=source_.model().unitMembershipVersion();
    spriteResources_.buildsSeen=compositeBuildCount_;
    ++spriteResources_.collections;
    std::set<uint32_t> versions;
    std::set<int> published;
    std::set<wm::UnitId> residents;
    for (const auto id:source_.model().unitIds()) {
        // Preserve interpolation across a departure, and offscreen residents.
        const bool current=source_.model().evaluate(id,source_.model().latestTick()).presence==wm::Presence::Present;
        const bool displayed=source_.model().evaluate(id,renderTick_).presence==wm::Presence::Present;
        if (!current && !displayed) continue;
        if (!current && displayed) spriteResources_.collectionPending=true;
        residents.insert(id);
        if (const auto* appearance=source_.model().unitAppearance(id)) versions.insert(appearance->version);
    }
    std::erase_if(unitArtCache_,[&](const auto& entry) {
        const auto* appearance=source_.model().unitAppearance(entry.first);
        return !residents.contains(entry.first) || entry.second.key.appearance!=(appearance?appearance->version:0);
    });
    source_.model().forEachItem([&](const wm::MapItem& item) {
        if (const auto* appearance=source_.model().itemAppearance(item.id)) versions.insert(appearance->version);
    });
    // Deferred preparation may still publish an older handle. Keep it until
    // the native payload no longer references it; scripts retire on revision.
    for (int i=0;i<spriteSlots_.size();++i) published.insert(spriteSlots_[i]);
    for (int i=0;i<itemSlots_.size();++i) published.insert(itemSlots_[i]);
    spriteResources_.retainAppearances(versions,published);
}

godot::Dictionary Df3dWorld::sprite_resource_stats() const {
    godot::Dictionary out;
    out["revision"]=int64_t(spriteResources_.revision);
    out["slots"]=int64_t(spriteResources_.slots.size());
    out["appearances"]=int64_t(spriteResources_.appearances.size());
    out["building_composites"]=int64_t(spriteResources_.buildings.size());
    out["composite_bytes"]=int64_t(spriteResources_.composites.imageBytes());
    out["images"]=int64_t(spriteResources_.images.size());
    out["meshes"]=int64_t(spriteResources_.meshes.size());
    out["metrics"]=int64_t(spriteResources_.metrics.size());
    out["collections"]=int64_t(spriteResources_.collections);
    return out;
}
}
