// Entity stream synchronization for a live client. Pure over
// SnapshotData so it is tier-1 testable without shared memory.
//
// The ring is latest-only: a client sees a sample of the bridge's
// snapshots, never guaranteed every one. For buildings and map items the
// bridge therefore (a) answers a Full request from the client with a
// snapshot whose two tables are Full and (b) re-sends every change and
// removal for `repeat` consecutive frames. On the client side this filter
// enforces the stream rule (no Delta before a Full: such tables are
// stripped) and decides when to ask for a Full: at attach, on a map change
// (tick going backwards), and after a tick gap wider than the bridge's
// repeat window, when Deltas may have been lost.
#pragma once

#include <cstdint>

#include "wm/world_model.h"

namespace wm::detail {

struct EntitySyncState {
  bool buildingsSynced = false;  // a Full for the table has been ingested
  bool itemsSynced = false;
  bool buildingsNeedFull = false;
  bool itemsNeedFull = false;
  uint64_t lastTick = 0;         // tick of the last snapshot filtered (0 = none yet)

  void reset() { *this = EntitySyncState(); }
};

// Filters `data` in place and advances `st`. Returns true when the client
// should request a Full from the bridge (call it until it returns false:
// the bridge serves one Full per request and the client may miss it).
inline bool filterEntities(SnapshotData& data, EntitySyncState& st, uint64_t repeatFrames) {
  bool request = false;
  if (st.lastTick != 0 && data.tick < st.lastTick) {
    // Ticks restarted: a new map. Everything the model holds is stale
    // until a Full reconciles it.
    st.buildingsSynced = false;
    st.itemsSynced = false;
  } else if (st.lastTick != 0 && data.tick > st.lastTick + repeatFrames) {
    // Missed more snapshots than the bridge repeats changes for: Deltas in
    // between may be lost. Apply what arrived (harmless) and reconcile
    // with a Full.
    st.buildingsNeedFull = true;
    st.itemsNeedFull = true;
  }

  if (data.buildingScope == ChangeScope::Full) {
    st.buildingsSynced = true;
    st.buildingsNeedFull = false;
  } else if (!st.buildingsSynced) {
    if (data.buildingScope == ChangeScope::Delta) {
      data.buildingScope = ChangeScope::None;
      data.buildings.clear();
      data.removedBuildings.clear();
    }
    request = true;
  }
  if (data.itemScope == ChangeScope::Full) {
    st.itemsSynced = true;
    st.itemsNeedFull = false;
  } else if (!st.itemsSynced) {
    if (data.itemScope == ChangeScope::Delta) {
      data.itemScope = ChangeScope::None;
      data.items.clear();
      data.removedItems.clear();
    }
    request = true;
  }
  st.lastTick = data.tick;
  return request || st.buildingsNeedFull || st.itemsNeedFull;
}

}  // namespace wm::detail
