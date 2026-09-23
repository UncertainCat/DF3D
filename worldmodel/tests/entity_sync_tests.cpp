// Live-client entity stream synchronization. Tier 1: the filter
// that strips Deltas before a Full, asks for a Full at attach, after a
// tick gap wider than the bridge's repeat window, and on a map change.
#include <doctest.h>

#include "entity_sync.h"

using namespace wm;
using wm::detail::EntitySyncState;
using wm::detail::filterEntities;

namespace {

SnapshotData snap(Tick tick, ChangeScope buildings, ChangeScope items) {
  SnapshotData d;
  d.tick = tick;
  d.mapSize = TilePos{16, 16, 4};
  d.buildingScope = buildings;
  d.itemScope = items;
  if (buildings != ChangeScope::None) {
    BuildingObservation b;
    b.id = 7;
    b.kind = BuildingKind::Bed;
    d.buildings.push_back(b);
    if (buildings == ChangeScope::Delta) d.removedBuildings.push_back(8);
  }
  if (items != ChangeScope::None) {
    ItemObservation it;
    it.id = 70;
    it.kind = ItemKind::Wood;
    d.items.push_back(it);
    if (items == ChangeScope::Delta) d.removedItems.push_back(71);
  }
  return d;
}

}  // namespace

TEST_CASE("entity sync: Deltas before the Full are stripped and a Full is requested") {
  EntitySyncState st;
  SnapshotData d = snap(10, ChangeScope::Delta, ChangeScope::Delta);
  CHECK(filterEntities(d, st, 8));
  CHECK(d.buildingScope == ChangeScope::None);
  CHECK(d.buildings.empty());
  CHECK(d.removedBuildings.empty());
  CHECK(d.itemScope == ChangeScope::None);
  CHECK(d.items.empty());
  CHECK(d.removedItems.empty());
  CHECK_FALSE(st.buildingsSynced);
  CHECK_FALSE(st.itemsSynced);

  // Snapshots without entity tables keep asking.
  SnapshotData none = snap(11, ChangeScope::None, ChangeScope::None);
  CHECK(filterEntities(none, st, 8));
}

TEST_CASE("entity sync: a Full syncs its table; the other keeps asking") {
  EntitySyncState st;
  SnapshotData d = snap(10, ChangeScope::Full, ChangeScope::Delta);
  CHECK(filterEntities(d, st, 8));  // items still unsynced
  CHECK(d.buildingScope == ChangeScope::Full);
  CHECK(d.buildings.size() == 1);
  CHECK(d.itemScope == ChangeScope::None);
  CHECK(st.buildingsSynced);
  CHECK_FALSE(st.itemsSynced);

  SnapshotData e = snap(11, ChangeScope::Delta, ChangeScope::Full);
  CHECK_FALSE(filterEntities(e, st, 8));
  CHECK(e.buildingScope == ChangeScope::Delta);
  CHECK(e.removedBuildings.size() == 1);
  CHECK(e.itemScope == ChangeScope::Full);
  CHECK(st.itemsSynced);

  // Steady state: consecutive Deltas pass through untouched, no request.
  SnapshotData f = snap(12, ChangeScope::Delta, ChangeScope::Delta);
  CHECK_FALSE(filterEntities(f, st, 8));
  CHECK(f.buildings.size() == 1);
  CHECK(f.items.size() == 1);
}

TEST_CASE("entity sync: a tick gap wider than the repeat window requests a Full but applies the Delta") {
  EntitySyncState st;
  SnapshotData full = snap(100, ChangeScope::Full, ChangeScope::Full);
  CHECK_FALSE(filterEntities(full, st, 8));

  SnapshotData within = snap(108, ChangeScope::Delta, ChangeScope::Delta);  // gap == repeat: fine
  CHECK_FALSE(filterEntities(within, st, 8));

  SnapshotData beyond = snap(117, ChangeScope::Delta, ChangeScope::Delta);  // gap 9 > 8
  CHECK(filterEntities(beyond, st, 8));
  CHECK(beyond.buildingScope == ChangeScope::Delta);  // still applied
  CHECK(beyond.items.size() == 1);
  CHECK(st.buildingsSynced);  // the request reconciles; nothing is stripped meanwhile

  SnapshotData lost = snap(119, ChangeScope::Delta, ChangeScope::Delta);
  CHECK(filterEntities(lost, st, 8)); // response at 118 was overwritten
  SnapshotData partial = snap(119, ChangeScope::Full, ChangeScope::None);
  CHECK(filterEntities(partial, st, 8)); // only one table recovered

  // The Full that answers the request clears the condition.
  SnapshotData answer = snap(120, ChangeScope::Full, ChangeScope::Full);
  CHECK_FALSE(filterEntities(answer, st, 8));
}

TEST_CASE("entity sync: ticks going backwards (new map) drop the sync and ask again") {
  EntitySyncState st;
  SnapshotData full = snap(500, ChangeScope::Full, ChangeScope::Full);
  CHECK_FALSE(filterEntities(full, st, 8));

  SnapshotData restarted = snap(3, ChangeScope::Delta, ChangeScope::None);
  CHECK(filterEntities(restarted, st, 8));
  CHECK(restarted.buildingScope == ChangeScope::None);  // Delta of the new map before its Full
  CHECK_FALSE(st.buildingsSynced);
  CHECK_FALSE(st.itemsSynced);
  CHECK(st.lastTick == 3);

  SnapshotData fresh = snap(4, ChangeScope::Full, ChangeScope::Full);
  CHECK_FALSE(filterEntities(fresh, st, 8));
  CHECK(st.buildingsSynced);
  CHECK(st.itemsSynced);
}
