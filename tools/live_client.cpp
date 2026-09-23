// live_client — attaches to a running DF+df3d bridge, mirrors live state,
// and prints inspector reports. Also the client half of the live smoke
// lane:
//   live_client watch                 poll and print a report every second
//   live_client smoke [--expect-terrain-delta] [--expect-item-delta]
//                     [--expect-corpses] [--expect-webs]
//                                     assert ticks advance, pause round-trip
//                                     works, unpause resumes, terrain
//                                     arrives (Full from the grid; with the
//                                     flag, at least one Delta too), every
//                                     dwarf gets a layered appearance, and
//                                     the buildings / items Fulls arrive
//                                     (with the flag: an item Delta and a
//                                     removal while running, building count
//                                     stable); the glyph tables arrive with
//                                     the Full (species and materials non-
//                                     empty); with --expect-corpses every
//                                     Corpse item of a layered species has a
//                                     non-empty stack and at least one does;
//                                     with --expect-webs at least one item
//                                     carries the Web flag; with --commands
//                                     round-trips the designation and
//                                     flag commands: a 3x3 dig on diggable
//                                     rock next to a revealed floor (the
//                                     DigDesignated flags appear, then a
//                                     Remove clears them), a smooth
//                                     designation on a rough stone floor
//                                     (SmoothDesignated, then cleared), a
//                                     tree felling / plant gathering mark, a
//                                     forbid / unforbid on a ground item and
//                                     on a door, a Rejected result for an
//                                     out-of-map rect, and a 100x100 dig +
//                                     remove as the drain-cost benchmark;
//                                     exit 0/1
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include "inspect.h"
#include "wm/mirror_client.h"
#include "wm/world_model.h"

namespace {

double nowSeconds() {
  using namespace std::chrono;
  return duration<double>(steady_clock::now().time_since_epoch()).count();
}

// Polls until the bridge tick changes (or not) within `seconds`; returns
// whether it advanced past `fromTick`. Terrain events observed while
// polling are accumulated into `terrainEvents`.
bool ticksAdvance(wm::MirrorClient& client, wm::WorldModel& model, uint64_t fromTick,
                  double seconds, size_t& terrainEvents) {
  const double deadline = nowSeconds() + seconds;
  while (nowSeconds() < deadline) {
    client.poll(model, nowSeconds());
    terrainEvents += model.drainTerrainEvents().size();
    if (client.bridgeTick() > fromTick) return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }
  return false;
}

// --- command round trips ---

// Polls until the result for `seq` arrives (or `seconds` pass). Other
// results drained meanwhile are kept in `spare` for later lookups.
bool awaitResult(wm::MirrorClient& client, wm::WorldModel& model, uint64_t seq, double seconds,
                 wm::CommandResult& out, std::vector<wm::CommandResult>& spare) {
  for (size_t i = 0; i < spare.size(); ++i) {
    if (spare[i].seq == seq) {
      out = spare[i];
      spare.erase(spare.begin() + static_cast<std::ptrdiff_t>(i));
      return true;
    }
  }
  const double deadline = nowSeconds() + seconds;
  while (nowSeconds() < deadline) {
    client.poll(model, nowSeconds());
    bool found = false;
    for (wm::CommandResult& r : model.drainCommandResults()) {
      if (!found && r.seq == seq) {
        out = std::move(r);
        found = true;
      } else {
        spare.push_back(std::move(r));  // several results can share a snapshot
      }
    }
    if (found) return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return false;
}

const char* statusName(wm::CommandStatus s) {
  switch (s) {
    case wm::CommandStatus::Ok: return "Ok";
    case wm::CommandStatus::Rejected: return "Rejected";
    default: return "Unknown";
  }
}

// Polls until `pred()` holds (or `seconds` pass); reports frames observed.
template <class Pred>
bool awaitState(wm::MirrorClient& client, wm::WorldModel& model, double seconds, Pred&& pred,
                uint64_t& framesSeen) {
  const double deadline = nowSeconds() + seconds;
  uint64_t lastTick = model.latestTick();
  framesSeen = 0;
  while (nowSeconds() < deadline) {
    client.poll(model, nowSeconds());
    if (model.latestTick() != lastTick) {
      ++framesSeen;
      lastTick = model.latestTick();
    }
    if (pred()) return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return pred();
}

bool tileIs(const wm::WorldModel& model, int32_t x, int32_t y, int32_t z, wm::TileShape shape,
            bool revealed) {
  const auto t = model.tileAt(wm::TilePos{x, y, z});
  if (!t || t->shape != shape) return false;
  return !revealed || !(t->flags & wm::kTileHidden);
}

// Finds a 3x3 rectangle of undesignated natural rock (Wall, Stone / Soil
// / Mineral; the tiles behind the first layer are normally still hidden,
// which DF lets the player designate) whose west-middle tile is revealed
// and touches a revealed Floor, on a z level near the units. All nine are
// Walls so every one must take the designation.
bool findDigTarget(const wm::WorldModel& model, int32_t zCenter, wm::TileRect& rect) {
  const wm::TilePos dims = model.mapSize();
  const auto rock = [](const wm::TileState& t) {
    return t.shape == wm::TileShape::Wall && !(t.flags & wm::kTileDigDesignated) &&
           (t.materialKind == wm::MaterialKind::Stone || t.materialKind == wm::MaterialKind::Soil ||
            t.materialKind == wm::MaterialKind::Mineral);
  };
  for (int32_t dz = 0; dz <= 12; ++dz) {
    for (int sign = -1; sign <= 1; sign += 2) {
      const int32_t z = zCenter + sign * dz;
      if (z < 0 || z >= dims.z || (dz == 0 && sign == 1)) continue;
      bool found = false;
      wm::TileRect best;
      model.forEachTileAtZ(z, [&](wm::TilePos p, const wm::TileState& t) {
        if (found) return;
        // p is the north-west corner; a revealed floor west of the middle row.
        if (p.x < 2 || p.y < 2 || p.x + 2 >= dims.x - 2 || p.y + 2 >= dims.y - 2) return;
        if (!tileIs(model, p.x - 1, p.y + 1, z, wm::TileShape::Floor, true)) return;
        if (!tileIs(model, p.x, p.y + 1, z, wm::TileShape::Wall, true)) return;
        for (int32_t y = p.y; y <= p.y + 2; ++y)
          for (int32_t x = p.x; x <= p.x + 2; ++x) {
            const auto tt = model.tileAt(wm::TilePos{x, y, z});
            if (!tt || !rock(*tt)) return;
          }
        (void)t;
        best = wm::TileRect{p.x, p.y, p.x + 2, p.y + 2, z};
        found = true;
      });
      if (found) {
        rect = best;
        return true;
      }
    }
  }
  return false;
}

// A revealed, rough (not Smooth, not designated) natural stone floor
// inside the fort (not Outside: surface river / brook beds classify as
// stone floors too but DF will not smooth them).
bool findSmoothTarget(const wm::WorldModel& model, int32_t zCenter, wm::TilePos& out) {
  const wm::TilePos dims = model.mapSize();
  for (int32_t dz = 0; dz <= 12; ++dz) {
    for (int sign = -1; sign <= 1; sign += 2) {
      const int32_t z = zCenter + sign * dz;
      if (z < 0 || z >= dims.z || (dz == 0 && sign == 1)) continue;
      bool found = false;
      model.forEachTileAtZ(z, [&](wm::TilePos p, const wm::TileState& t) {
        if (found) return;
        if (p.x < 2 || p.y < 2 || p.x >= dims.x - 2 || p.y >= dims.y - 2) return;
        if (t.shape != wm::TileShape::Floor) return;
        if (t.materialKind != wm::MaterialKind::Stone && t.materialKind != wm::MaterialKind::Mineral) return;
        if (t.flags & (wm::kTileHidden | wm::kTileSmooth | wm::kTileSmoothDesignated |
                       wm::kTileEngraveDesignated | wm::kTileDigDesignated | wm::kTileOutside))
          return;
        out = p;
        found = true;
      });
      if (found) return true;
    }
  }
  return false;
}

// A revealed, undesignated tile of the given shape anywhere on the map
// (tree trunks / shrubs for chop / gather), lowest z first: a tree's
// designation tile is on its base level, and the lowest revealed trunk
// tile of the map is the base of some tree.
bool findShapeTarget(const wm::WorldModel& model, wm::TileShape shape, wm::TilePos& out) {
  const wm::TilePos dims = model.mapSize();
  for (int32_t z = 0; z < dims.z; ++z) {
    bool found = false;
    model.forEachTileAtZ(z, [&](wm::TilePos p, const wm::TileState& t) {
      if (found || t.shape != shape) return;
      if (t.flags & (wm::kTileHidden | wm::kTileDigDesignated)) return;
      if (p.x < 2 || p.y < 2 || p.x >= dims.x - 2 || p.y >= dims.y - 2) return;
      out = p;
      found = true;
    });
    if (found) return true;
  }
  return false;
}

int runCommandSmoke(wm::MirrorClient& client, wm::WorldModel& model) {
  std::vector<wm::CommandResult> spare;
  wm::CommandResult res;
  uint64_t frames = 0;
  const double kResultWait = 15.0, kStateWait = 15.0;
  auto fail = [](const char* what) {
    std::fprintf(stderr, "[smoke] FAIL: %s\n", what);
    return 1;
  };
  auto sendAndAwait = [&](uint64_t seq, const char* what, wm::CommandStatus expect) -> bool {
    if (seq == 0) {
      std::fprintf(stderr, "[smoke] FAIL: %s not sent: %s\n", what, client.lastError().c_str());
      return false;
    }
    const double t0 = nowSeconds();
    if (!awaitResult(client, model, seq, kResultWait, res, spare)) {
      std::fprintf(stderr, "[smoke] FAIL: no result for %s (seq %llu) within %.0fs\n", what,
                   static_cast<unsigned long long>(seq), kResultWait);
      return false;
    }
    std::printf("[smoke] %s: seq %llu -> %s \"%s\" (tick %llu, %.0f ms round trip)\n", what,
                static_cast<unsigned long long>(seq), statusName(res.status), res.message.c_str(),
                static_cast<unsigned long long>(res.tick), (nowSeconds() - t0) * 1000.0);
    if (res.status != expect) {
      std::fprintf(stderr, "[smoke] FAIL: %s expected %s, got %s\n", what, statusName(expect),
                   statusName(res.status));
      return false;
    }
    return true;
  };

  // The z of the first present dwarf anchors the search for targets.
  int32_t zCenter = model.mapSize().z / 2;
  {
    const double rt = model.renderTickAt(nowSeconds());
    for (wm::UnitId id : model.unitIds()) {
      const std::string* sp = model.unitSpecies(id);
      if (!sp || *sp != "DWARF") continue;
      const wm::EvalResult e = model.evaluate(id, rt);
      if (e.presence != wm::Presence::Present) continue;
      zCenter = static_cast<int32_t>(e.pos.z);
      break;
    }
  }

  // 1. Rejected: a rect past the map edge (the client validator lets it
  //    through without a map size; the bridge rejects against the live map).
  {
    const wm::TilePos dims = model.mapSize();
    const wm::TileRect bad{dims.x - 2, 5, dims.x + 5, 7, zCenter};
    if (!sendAndAwait(client.sendDesignateDig(bad, wm::DigKind::Dig), "dig out of map",
                      wm::CommandStatus::Rejected))
      return 1;
    if (res.message.find("outside map") == std::string::npos) return fail("rejection message does not name the map");
  }

  // 2. A 3x3 dig on diggable rock next to a revealed floor: all nine tiles
  //    take DigDesignated, then Remove clears them.
  {
    wm::TileRect rect;
    if (!findDigTarget(model, zCenter, rect)) return fail("no 3x3 of revealed undesignated rock next to a floor found");
    std::printf("[smoke] dig target: (%d,%d)-(%d,%d) z %d\n", rect.x1, rect.y1, rect.x2, rect.y2, rect.z);
    const auto designated = [&](bool want) {
      for (int32_t y = rect.y1; y <= rect.y2; ++y)
        for (int32_t x = rect.x1; x <= rect.x2; ++x) {
          const auto t = model.tileAt(wm::TilePos{x, y, rect.z});
          if (!t || static_cast<bool>(t->flags & wm::kTileDigDesignated) != want) return false;
        }
      return true;
    };
    const double t0 = nowSeconds();
    if (!sendAndAwait(client.sendDesignateDig(rect, wm::DigKind::Dig, 5), "dig 3x3", wm::CommandStatus::Ok))
      return 1;
    if (res.message.find("9 of 9") == std::string::npos) return fail("dig 3x3 did not apply to all nine tiles");
    if (!awaitState(client, model, kStateWait, [&] { return designated(true); }, frames))
      return fail("DigDesignated did not appear on the nine tiles");
    std::printf("[smoke] DigDesignated on all 9 tiles after %llu frame(s), %.0f ms from send\n",
                static_cast<unsigned long long>(frames), (nowSeconds() - t0) * 1000.0);
    if (!sendAndAwait(client.sendDesignateDig(rect, wm::DigKind::Remove), "dig remove", wm::CommandStatus::Ok))
      return 1;
    if (!awaitState(client, model, kStateWait, [&] { return designated(false); }, frames))
      return fail("DigDesignated did not clear after Remove");
    std::printf("[smoke] DigDesignated cleared after %llu frame(s)\n", static_cast<unsigned long long>(frames));
    // Removing again: nothing to do -> Rejected (nothing applied).
    if (!sendAndAwait(client.sendDesignateDig(rect, wm::DigKind::Remove), "dig remove (again)",
                      wm::CommandStatus::Rejected))
      return 1;
  }

  // 3. Smooth a rough stone floor: SmoothDesignated appears, Remove clears.
  {
    wm::TilePos p;
    if (!findSmoothTarget(model, zCenter, p)) return fail("no rough revealed stone floor found");
    const wm::TileRect rect{p.x, p.y, p.x, p.y, p.z};
    std::printf("[smoke] smooth target: (%d,%d,%d) %s\n", p.x, p.y, p.z,
                std::string(model.materialName(model.tileAt(p)->material)).c_str());
    const auto flag = [&](uint8_t bit) {
      const auto t = model.tileAt(p);
      return t && (t->flags & bit);
    };
    const double t0 = nowSeconds();
    if (!sendAndAwait(client.sendDesignateSmooth(rect, wm::SmoothKind::Smooth), "smooth 1x1", wm::CommandStatus::Ok))
      return 1;
    if (!awaitState(client, model, kStateWait, [&] { return flag(wm::kTileSmoothDesignated); }, frames))
      return fail("SmoothDesignated did not appear");
    std::printf("[smoke] SmoothDesignated after %llu frame(s), %.0f ms from send\n",
                static_cast<unsigned long long>(frames), (nowSeconds() - t0) * 1000.0);
    // Engrave on a merely designated (not yet smoothed) floor is Rejected.
    if (!sendAndAwait(client.sendDesignateSmooth(rect, wm::SmoothKind::Engrave), "engrave rough floor",
                      wm::CommandStatus::Rejected))
      return 1;
    if (!sendAndAwait(client.sendDesignateSmooth(rect, wm::SmoothKind::Remove), "smooth remove", wm::CommandStatus::Ok))
      return 1;
    if (!awaitState(client, model, kStateWait, [&] { return !flag(wm::kTileSmoothDesignated); }, frames))
      return fail("SmoothDesignated did not clear after Remove");
    std::printf("[smoke] SmoothDesignated cleared after %llu frame(s)\n", static_cast<unsigned long long>(frames));
  }

  // 4. Tree felling and plant gathering (a Default dig designation on the
  //    plant's designation tile), when the map has a revealed tree / shrub.
  for (int pass = 0; pass < 2; ++pass) {
    const bool chop = pass == 0;
    wm::TilePos p;
    if (!findShapeTarget(model, chop ? wm::TileShape::TreeTrunk : wm::TileShape::Shrub, p)) {
      std::printf("[smoke] note: no revealed %s on the map; %s not exercised\n", chop ? "tree trunk" : "shrub",
                  chop ? "chop" : "gather");
      continue;
    }
    // A trunk tile is somewhere in the tree (the lowest ones are roots,
    // below the base level); the designation tile is the south-east trunk
    // tile of the tree's base, so cover a generous rect and walk up a few
    // levels until the bridge finds the tree.
    const char* what = chop ? "chop" : "gather";
    wm::TileRect rect{p.x - 2, p.y - 2, p.x + 2, p.y + 2, p.z};
    bool marked = false;
    for (int32_t dz = 0; dz <= 4 && !marked; ++dz) {
      rect.z = p.z + dz;
      const uint64_t seq = chop ? client.sendDesignateChop(rect, true) : client.sendDesignateGather(rect, true);
      if (seq == 0) return fail("chop / gather not sent");
      if (!awaitResult(client, model, seq, kResultWait, res, spare)) return fail("no chop / gather result");
      std::printf("[smoke] %s at z %d: seq %llu -> %s \"%s\"\n", what, rect.z,
                  static_cast<unsigned long long>(seq), statusName(res.status), res.message.c_str());
      marked = res.status == wm::CommandStatus::Ok;
    }
    if (!marked) return fail("chop / gather found no plant around the trunk / shrub tile");
    const auto anyDesignated = [&]() {
      for (int32_t y = rect.y1; y <= rect.y2; ++y)
        for (int32_t x = rect.x1; x <= rect.x2; ++x) {
          const auto t = model.tileAt(wm::TilePos{x, y, rect.z});
          if (t && (t->flags & wm::kTileDigDesignated)) return true;
        }
      return false;
    };
    if (!awaitState(client, model, kStateWait, anyDesignated, frames))
      return fail("no DigDesignated tile appeared in the chop / gather rect");
    std::printf("[smoke] %s mark visible after %llu frame(s)\n", what, static_cast<unsigned long long>(frames));
    const uint64_t off = chop ? client.sendDesignateChop(rect, false) : client.sendDesignateGather(rect, false);
    if (!sendAndAwait(off, chop ? "chop unmark" : "gather unmark", wm::CommandStatus::Ok)) return 1;
    if (!awaitState(client, model, kStateWait, [&] { return !anyDesignated(); }, frames))
      return fail("chop / gather mark did not clear");
  }

  // 5. Item flags: forbid an unforbidden ground item, then unforbid it; a
  //    melt on a non-metal item is Rejected.
  {
    wm::ItemId target = 0;
    wm::ItemId nonMetal = 0;
    model.forEachItem([&](const wm::MapItem& it) {
      if (!target && !(it.flags & (wm::kItemForbidden | wm::kItemWeb | wm::kItemArtifact))) target = it.id;
      if (!nonMetal && (it.kind == wm::ItemKind::Wood || it.kind == wm::ItemKind::Boulder ||
                        it.kind == wm::ItemKind::Corpse || it.kind == wm::ItemKind::Thread))
        nonMetal = it.id;
    });
    if (!target) return fail("no unforbidden ground item to forbid");
    const auto forbidden = [&]() {
      const wm::MapItem* it = model.item(target);
      return it && (it->flags & wm::kItemForbidden);
    };
    const double t0 = nowSeconds();
    if (!sendAndAwait(client.sendSetItemFlags(target, wm::OptionalBool::Set, wm::OptionalBool::Unchanged,
                                              wm::OptionalBool::Unchanged),
                      "forbid item", wm::CommandStatus::Ok))
      return 1;
    if (!awaitState(client, model, kStateWait, forbidden, frames)) return fail("item Forbidden flag did not appear");
    std::printf("[smoke] item %u Forbidden after %llu frame(s), %.0f ms from send\n", target,
                static_cast<unsigned long long>(frames), (nowSeconds() - t0) * 1000.0);
    if (!sendAndAwait(client.sendSetItemFlags(target, wm::OptionalBool::Clear, wm::OptionalBool::Unchanged,
                                              wm::OptionalBool::Unchanged),
                      "unforbid item", wm::CommandStatus::Ok))
      return 1;
    if (!awaitState(client, model, kStateWait, [&] { return !forbidden(); }, frames))
      return fail("item Forbidden flag did not clear");
    if (nonMetal) {
      if (!sendAndAwait(client.sendSetItemFlags(nonMetal, wm::OptionalBool::Unchanged, wm::OptionalBool::Unchanged,
                                                wm::OptionalBool::Set),
                        "melt non-metal item", wm::CommandStatus::Rejected))
        return 1;
    }
    if (!sendAndAwait(client.sendSetItemFlags(0xFFFFFFF0u, wm::OptionalBool::Set, wm::OptionalBool::Unchanged,
                                              wm::OptionalBool::Unchanged),
                      "forbid unknown item", wm::CommandStatus::Rejected))
      return 1;
  }

  // 6. Building flags: forbid / unforbid a door; a non-door is Rejected.
  {
    wm::BuildingId door = 0, other = 0;
    model.forEachBuilding([&](const wm::Building& b) {
      if (!door && (b.kind == wm::BuildingKind::Door || b.kind == wm::BuildingKind::Hatch) &&
          !(b.flags & wm::kBuildingForbidden) && b.stage == wm::BuildingStage::Complete)
        door = b.id;
      if (!other && b.kind == wm::BuildingKind::Workshop) other = b.id;
    });
    if (!door) {
      std::printf("[smoke] note: no unforbidden door / hatch; building flags not exercised\n");
    } else {
      const auto forbidden = [&]() {
        const wm::Building* b = model.building(door);
        return b && (b->flags & wm::kBuildingForbidden);
      };
      const double t0 = nowSeconds();
      if (!sendAndAwait(client.sendSetBuildingFlags(door, wm::OptionalBool::Set), "forbid door", wm::CommandStatus::Ok))
        return 1;
      if (!awaitState(client, model, kStateWait, forbidden, frames)) return fail("door Forbidden flag did not appear");
      std::printf("[smoke] door %u Forbidden after %llu frame(s), %.0f ms from send\n", door,
                  static_cast<unsigned long long>(frames), (nowSeconds() - t0) * 1000.0);
      if (!sendAndAwait(client.sendSetBuildingFlags(door, wm::OptionalBool::Clear), "unforbid door", wm::CommandStatus::Ok))
        return 1;
      if (!awaitState(client, model, kStateWait, [&] { return !forbidden(); }, frames))
        return fail("door Forbidden flag did not clear");
    }
    if (other) {
      if (!sendAndAwait(client.sendSetBuildingFlags(other, wm::OptionalBool::Set), "forbid workshop",
                        wm::CommandStatus::Rejected))
        return 1;
    }
  }

  // 7. Drain-cost benchmark: a 100x100 dig at the lowest priority followed
  //    by its Remove in the same drain (the dwarves never see it). The
  //    bridge's per-command exec time is in `df3d status` (the lane prints
  //    it); here the round trip is timed.
  {
    const wm::TilePos dims = model.mapSize();
    const int32_t x1 = std::max(1, dims.x / 2 - 50), y1 = std::max(1, dims.y / 2 - 50);
    const wm::TileRect big{x1, y1, std::min(dims.x - 2, x1 + 99), std::min(dims.y - 2, y1 + 99), zCenter};
    const double t0 = nowSeconds();
    const uint64_t s1 = client.sendDesignateDig(big, wm::DigKind::Dig, 7);
    const uint64_t s2 = client.sendDesignateDig(big, wm::DigKind::Remove);
    if (!s1 || !s2) return fail("100x100 dig commands not sent");
    wm::CommandResult r1, r2;
    if (!awaitResult(client, model, s1, kResultWait, r1, spare) || !awaitResult(client, model, s2, kResultWait, r2, spare))
      return fail("no results for the 100x100 dig / remove");
    std::printf("[smoke] 100x100 dig: %s \"%s\"; remove: %s \"%s\"; both results %.0f ms after send\n",
                statusName(r1.status), r1.message.c_str(), statusName(r2.status), r2.message.c_str(),
                (nowSeconds() - t0) * 1000.0);
    if (r1.status != wm::CommandStatus::Ok) return fail("100x100 dig was not Ok");
  }

  std::printf("[smoke] commands: %llu results received, %zu unmatched\n",
              static_cast<unsigned long long>(model.commandResultsReceived()), spare.size());
  return 0;
}

int runSmoke(wm::MirrorClient& client, wm::WorldModel& model, bool expectTerrainDelta,
             bool expectItemDelta, bool expectCorpses, bool expectWebs, bool commands) {
  size_t terrainEvents = 0;
  size_t itemAdded = 0, itemChanged = 0, itemRemoved = 0, buildingEvents = 0;
  auto drainEntities = [&]() {
    for (const wm::ItemEvent& e : model.drainItemEvents()) {
      if (e.change == wm::EntityChange::Added) ++itemAdded;
      else if (e.change == wm::EntityChange::Changed) ++itemChanged;
      else ++itemRemoved;
    }
    buildingEvents += model.drainBuildingEvents().size();
  };

  // DF re-asserts pause at the end of a save load (racing any one-shot
  // unpause in the loader script), so start by commanding the sim to run
  // via our own ring — which also proves the command path cold.
  if (!client.sendSetPause(false)) {
    std::fprintf(stderr, "[smoke] FAIL: command ring full on initial unpause\n");
    return 1;
  }
  std::printf("[smoke] sent SetPause(false); waiting for sim ticks...\n");
  if (!ticksAdvance(client, model, client.bridgeTick(), 60.0, terrainEvents)) {
    std::fprintf(stderr, "[smoke] FAIL: no tick advancement in 60s\n");
    return 1;
  }
  std::printf("[smoke] ticks advancing (tick %llu)\n",
              static_cast<unsigned long long>(client.bridgeTick()));

  // Terrain: the first poll synthesizes a Full from the bridge's grid.
  {
    const double deadline = nowSeconds() + 30.0;
    while (!model.hasTerrain() && nowSeconds() < deadline) {
      client.poll(model, nowSeconds());
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    if (!model.hasTerrain()) {
      std::fprintf(stderr, "[smoke] FAIL: no terrain Full within 30s (epoch %llx, %s)\n",
                   static_cast<unsigned long long>(client.terrainEpoch()),
                   client.lastError().c_str());
      return 1;
    }
    if (!client.terrainSynced() || model.knownBlockCount() != model.mapBlockCount() ||
        model.terrainVersion() == 0) {
      std::fprintf(stderr,
                   "[smoke] FAIL: terrain Full incomplete: synced=%d known=%zu map=%zu version=%llu\n",
                   client.terrainSynced() ? 1 : 0, model.knownBlockCount(),
                   model.mapBlockCount(), static_cast<unsigned long long>(model.terrainVersion()));
      return 1;
    }
    const wm::TilePos dims = model.mapSize();
    std::printf("[smoke] terrain Full: %zu/%zu blocks (%dx%dx%d), %zu materials, grid tick %llu\n",
                model.knownBlockCount(), model.mapBlockCount(), dims.x, dims.y, dims.z,
                model.materialCount(), static_cast<unsigned long long>(client.terrainGridTick()));
    // Every block starts at version 1 after a Full.
    size_t bad = 0;
    for (int32_t z = 0; z < dims.z; ++z)
      for (const wm::BlockView& b : model.blocksAtZ(z))
        if (b.version == 0) ++bad;
    if (bad != 0) {
      std::fprintf(stderr, "[smoke] FAIL: %zu blocks with version 0 after Full\n", bad);
      return 1;
    }
    // A sample of the material vocabulary (raw identifiers).
    std::printf("[smoke] materials:");
    for (wm::MaterialId i = 0; i < model.materialCount() && i < 8; ++i)
      std::printf(" %s", std::string(model.materialName(i)).c_str());
    std::printf("%s\n", model.materialCount() > 8 ? " ..." : "");
    terrainEvents += model.drainTerrainEvents().size();  // the Full's events
    terrainEvents = 0;
  }

  // Appearances: ring snapshots carry changed stacks plus a
  // rotating refresh slice, so every unit's appearance reaches a client
  // within one refresh period (128 frames by default). Wait until every
  // present dwarf has one, and require that dwarves are layered (a dwarf
  // with no layers means the resolver found no LAYER_SET).
  {
    const double deadline = nowSeconds() + 30.0;
    size_t dwarves = 0, dwarvesWithAppearance = 0, layeredDwarves = 0, withAppearance = 0;
    auto count = [&]() {
      dwarves = dwarvesWithAppearance = layeredDwarves = withAppearance = 0;
      const double rt = model.renderTickAt(nowSeconds());
      for (wm::UnitId id : model.unitIds()) {
        if (model.evaluate(id, rt).presence != wm::Presence::Present) continue;
        const wm::UnitAppearance* a = model.unitAppearance(id);
        if (a) ++withAppearance;
        const std::string* sp = model.unitSpecies(id);
        if (!sp || *sp != "DWARF") continue;
        ++dwarves;
        if (a) ++dwarvesWithAppearance;
        if (a && a->layers.size() >= 2) ++layeredDwarves;
      }
    };
    size_t appearanceEvents = 0;
    while (nowSeconds() < deadline) {
      client.poll(model, nowSeconds());
      appearanceEvents += model.drainAppearanceEvents().size();
      count();
      if (dwarves > 0 && dwarvesWithAppearance == dwarves) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    std::printf("[smoke] appearances: %zu units with one; dwarves %zu, with appearance %zu, layered %zu; "
                "%zu events; %zu pages, %zu palettes known\n",
                withAppearance, dwarves, dwarvesWithAppearance, layeredDwarves, appearanceEvents,
                model.tilePageCount(), model.paletteCount());
    if (dwarves == 0 || dwarvesWithAppearance != dwarves) {
      std::fprintf(stderr, "[smoke] FAIL: not every present dwarf has an appearance within 30s\n");
      return 1;
    }
    if (layeredDwarves != dwarves) {
      std::fprintf(stderr, "[smoke] FAIL: %zu of %zu dwarves are not layered (resolver found no LAYER_SET)\n",
                   dwarves - layeredDwarves, dwarves);
      return 1;
    }
    // Print one dwarf's stack as the human-checkable sample.
    for (wm::UnitId id : model.unitIds()) {
      const std::string* sp = model.unitSpecies(id);
      const wm::UnitAppearance* a = model.unitAppearance(id);
      if (!sp || *sp != "DWARF" || !a || a->layers.empty()) continue;
      std::printf("[smoke] dwarf %llu %s\n", static_cast<unsigned long long>(id),
                  inspector::appearanceSummary(model, id).c_str());
      for (const wm::AppearanceLayer& l : a->layers) {
        std::printf("[smoke]   %s (%u,%u) %ux%u", std::string(model.tilePageName(l.page)).c_str(),
                    l.tileX, l.tileY, l.cellsX, l.cellsY);
        if (l.palette != wm::kNoPalette)
          std::printf(" palette %s row %d key %d", std::string(model.paletteName(l.palette)).c_str(),
                      l.paletteRow, l.paletteKeyRow);
        if (l.offsetX || l.offsetY) std::printf(" offset (%d,%d)", l.offsetX, l.offsetY);
        std::printf("\n");
      }
      break;
    }
  }

  // Buildings and map items: the client requested a Full at
  // attach; both tables must arrive. Count by kind for the report.
  size_t buildingsAtFull = 0;
  {
    const double deadline = nowSeconds() + 30.0;
    while (!(model.buildingsKnown() && model.itemsKnown()) && nowSeconds() < deadline) {
      client.poll(model, nowSeconds());
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    if (!model.buildingsKnown() || !model.itemsKnown()) {
      std::fprintf(stderr, "[smoke] FAIL: entity Fulls not seen within 30s (buildings %d, items %d, %llu requests)\n",
                   model.buildingsKnown() ? 1 : 0, model.itemsKnown() ? 1 : 0,
                   static_cast<unsigned long long>(client.entityFullRequests()));
      return 1;
    }
    std::printf("[smoke] entity Fulls after %llu request(s): %zu buildings, %zu items\n",
                static_cast<unsigned long long>(client.entityFullRequests()), model.buildingCount(),
                model.itemCount());
    std::fputs(inspector::buildingSummary(model).c_str(), stdout);
    std::fputs(inspector::itemSummary(model).c_str(), stdout);
    if (model.buildingCount() == 0 || model.itemCount() == 0) {
      std::fprintf(stderr, "[smoke] FAIL: a fort with no buildings or no ground items is not the mature fort\n");
      return 1;
    }
    buildingsAtFull = model.buildingCount();
    // Events from the Fulls themselves are not "changes while running".
    model.drainItemEvents();
    model.drainBuildingEvents();

    // Corpse appearances, webs and glyph tables arrive with the
    // Full. A corpse item's stack is non-empty when its species has CORPSE
    // art (layered or simple); pieces are always empty (hardcoded tiles).
    size_t corpses = 0, corpsesWithStack = 0, corpseLayers = 0, pieces = 0, webs = 0;
    std::string sample;
    model.forEachItem([&](const wm::MapItem& it) {
      if (it.flags & wm::kItemWeb) ++webs;
      if (it.kind == wm::ItemKind::CorpsePiece) ++pieces;
      if (it.kind != wm::ItemKind::Corpse) return;
      ++corpses;
      const wm::ItemAppearance* a = model.itemAppearance(it.id);
      if (a && !a->layers.empty()) {
        ++corpsesWithStack;
        corpseLayers += a->layers.size();
        if (sample.empty()) {
          sample = "corpse item " + std::to_string(it.id) + " material " +
                   std::string(model.materialName(it.material)) + ": " +
                   std::to_string(a->layers.size()) + " layers [";
          for (size_t i = 0; i < a->layers.size() && i < 3; ++i) {
            if (i) sample += ", ";
            sample += std::string(model.tilePageName(a->layers[i].page)) + " (" +
                      std::to_string(a->layers[i].tileX) + "," + std::to_string(a->layers[i].tileY) + ")";
          }
          sample += a->layers.size() > 3 ? ", ...]" : "]";
        }
      }
    });
    std::printf("[smoke] corpses: %zu whole (%zu with a stack, %zu layers), %zu pieces; webs %zu; "
                "item appearances %zu; glyphs %s: species %zu, materials %zu, itemdefs %zu\n",
                corpses, corpsesWithStack, corpseLayers, pieces, webs, model.itemAppearanceCount(),
                model.glyphsKnown() ? "known" : "NOT known", model.creatureGlyphCount(),
                model.materialGlyphCount(), model.itemDefGlyphCount());
    if (!sample.empty()) std::printf("[smoke] %s\n", sample.c_str());
    if (!model.glyphsKnown() || model.creatureGlyphCount() == 0 || model.materialGlyphCount() == 0) {
      std::fprintf(stderr, "[smoke] FAIL: glyph tables missing or empty after the Full\n");
      return 1;
    }
    if (const wm::CreatureGlyph* dwarf = model.creatureGlyph("DWARF")) {
      std::printf("[smoke] DWARF glyph: tile %u colour %u:%u:%u soldier %u\n", dwarf->glyph.tile, dwarf->glyph.fg,
                  dwarf->glyph.bg, dwarf->glyph.bright, dwarf->soldierTile);
    } else {
      std::fprintf(stderr, "[smoke] FAIL: no DWARF creature glyph\n");
      return 1;
    }
    if (expectCorpses && corpses > 0 && corpsesWithStack == 0) {
      std::fprintf(stderr, "[smoke] FAIL: %zu corpse items on the map, none with an appearance stack\n", corpses);
      return 1;
    }
    if (expectWebs && webs == 0) {
      std::fprintf(stderr, "[smoke] FAIL: no item carries the Web flag on the mature fort\n");
      return 1;
    }
  }

  // Command round trips while the sim runs.
  if (commands) {
    const int rc = runCommandSmoke(client, model);
    if (rc != 0) return rc;
  }

  if (!client.sendSetPause(true)) {
    std::fprintf(stderr, "[smoke] FAIL: command ring full\n");
    return 1;
  }
  std::printf("[smoke] sent SetPause(true)\n");
  // Give the bridge a moment to drain and the sim to stop.
  std::this_thread::sleep_for(std::chrono::milliseconds(1500));
  const uint64_t pausedTick = client.bridgeTick();
  if (ticksAdvance(client, model, pausedTick, 3.0, terrainEvents)) {
    std::fprintf(stderr, "[smoke] FAIL: ticks still advancing after SetPause(true)\n");
    return 1;
  }
  std::printf("[smoke] sim paused at tick %llu\n",
              static_cast<unsigned long long>(pausedTick));

  if (!client.sendSetPause(false)) {
    std::fprintf(stderr, "[smoke] FAIL: command ring full on unpause\n");
    return 1;
  }
  std::printf("[smoke] sent SetPause(false)\n");
  if (!ticksAdvance(client, model, pausedTick, 15.0, terrainEvents)) {
    std::fprintf(stderr, "[smoke] FAIL: ticks did not resume after SetPause(false)\n");
    return 1;
  }
  std::printf("[smoke] ticks resumed (tick %llu)\n",
              static_cast<unsigned long long>(client.bridgeTick()));

  // Terrain Deltas: keep the sim running until at least one changed block
  // arrives through the ring (the lane designates a dig before we start,
  // so a Delta is guaranteed; without the flag this is informational).
  {
    const double deadline = nowSeconds() + 20.0;
    while (terrainEvents == 0 && nowSeconds() < deadline) {
      client.poll(model, nowSeconds());
      terrainEvents += model.drainTerrainEvents().size();
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    std::printf("[smoke] terrain Delta events after the Full: %zu (terrain version %llu)\n",
                terrainEvents, static_cast<unsigned long long>(model.terrainVersion()));
    if (expectTerrainDelta && terrainEvents == 0) {
      std::fprintf(stderr, "[smoke] FAIL: no terrain Delta observed within 20s of running\n");
      return 1;
    }
  }

  // Item Deltas: hauling never stops in a 321-dwarf fort, so within a few
  // seconds of running an item must change / appear and one must leave the
  // ground (Removed). Buildings hardly change: their count stays put.
  {
    const double deadline = nowSeconds() + 30.0;
    while ((itemAdded + itemChanged == 0 || itemRemoved == 0) && nowSeconds() < deadline) {
      client.poll(model, nowSeconds());
      drainEntities();
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    std::printf("[smoke] item events while running: %zu added, %zu changed, %zu removed; %zu building events; "
                "buildings %zu -> %zu, items %zu; %llu Full requests\n",
                itemAdded, itemChanged, itemRemoved, buildingEvents, buildingsAtFull, model.buildingCount(),
                model.itemCount(), static_cast<unsigned long long>(client.entityFullRequests()));
    if (expectItemDelta) {
      if (itemAdded + itemChanged == 0) {
        std::fprintf(stderr, "[smoke] FAIL: no item added / changed within 30s of running\n");
        return 1;
      }
      if (itemRemoved == 0) {
        std::fprintf(stderr, "[smoke] FAIL: no item removed (picked up) within 30s of running\n");
        return 1;
      }
      const size_t now = model.buildingCount();
      const size_t drift = now > buildingsAtFull ? now - buildingsAtFull : buildingsAtFull - now;
      if (drift > buildingsAtFull / 20 + 2) {
        std::fprintf(stderr, "[smoke] FAIL: building count moved %zu -> %zu while running\n", buildingsAtFull,
                     now);
        return 1;
      }
    }
    std::fputs(inspector::itemSummary(model).c_str(), stdout);
  }

  const double t = model.renderTickAt(nowSeconds());
  std::printf("[smoke] world model: %zu units known, render tick %.1f\n",
              model.unitIds().size(), t);
  std::printf("[smoke] PASS: mirror live, command round-trip verified, terrain %s, entities %s\n",
              terrainEvents > 0 ? "Full + Delta" : "Full",
              itemAdded + itemChanged + itemRemoved > 0 ? "Full + Delta" : "Full");
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  const std::string mode = argc > 1 ? argv[1] : "watch";
  bool expectTerrainDelta = false, expectItemDelta = false, expectCorpses = false, expectWebs = false;
  bool commands = false;
  for (int i = 2; i < argc; ++i) {
    if (std::strcmp(argv[i], "--commands") == 0) commands = true;
    if (std::strcmp(argv[i], "--expect-terrain-delta") == 0) expectTerrainDelta = true;
    if (std::strcmp(argv[i], "--expect-item-delta") == 0) expectItemDelta = true;
    if (std::strcmp(argv[i], "--expect-corpses") == 0) expectCorpses = true;
    if (std::strcmp(argv[i], "--expect-webs") == 0) expectWebs = true;
  }

  std::string err;
  auto client = wm::MirrorClient::open(err);
  if (!client) {
    std::fprintf(stderr, "error: %s\n", err.c_str());
    return 1;
  }
  std::printf("attached to mirror (bridge tick %llu, terrain epoch %llx)\n",
              static_cast<unsigned long long>(client->bridgeTick()),
              static_cast<unsigned long long>(client->terrainEpoch()));

  wm::WorldModel model;
  if (mode == "smoke")
    return runSmoke(*client, model, expectTerrainDelta, expectItemDelta, expectCorpses, expectWebs, commands);

  // watch mode
  double lastReport = 0.0;
  while (true) {
    const double now = nowSeconds();
    if (client->poll(model, now) && !client->lastError().empty()) {
      std::fprintf(stderr, "warning: %s\n", client->lastError().c_str());
    }
    if (now - lastReport >= 1.0 && model.hasData()) {
      lastReport = now;
      std::fputs(inspector::report(model, model.renderTickAt(now)).c_str(), stdout);
      std::printf("---\n");
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }
}
