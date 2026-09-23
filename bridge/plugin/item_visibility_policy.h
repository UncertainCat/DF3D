#pragma once

namespace df3d_bridge {

// Map-visible storage is distinct from a permanent building component or inventory.
enum class TemporaryStorage { None, WorkshopVisible, WorkshopHidden, Permanent, OtherBuilding };
struct MapItemPlacement {
    bool onGround = false;
    bool inInventory = false;
    bool inBuilding = false;
    bool removed = false;
    bool garbageCollect = false;
    bool positionValid = false;
    TemporaryStorage storage = TemporaryStorage::None;
    bool holderPositionValid = false;
};
inline bool mapItemEligible(const MapItemPlacement& item) {
    if (item.inInventory || item.inBuilding || item.removed || item.garbageCollect || !item.positionValid)
        return false;
    return item.onGround ||
           (item.storage == TemporaryStorage::WorkshopVisible && item.holderPositionValid);
}

// Observe actual simulation pause state, including pauses outside this frontend.
// Initial load already requests a Full; repeated paused updates require no rescan.
class PauseTransitionTracker {
public:
    bool observe(bool loaded, bool paused) {
        if (!loaded) {
            known_ = false;
            return false;
        }
        const bool enteredPause = known_ && !paused_ && paused;
        known_ = true;
        paused_ = paused;
        return enteredPause;
    }
private:
    bool known_ = false;
    bool paused_ = false;
};

}  // namespace df3d_bridge
