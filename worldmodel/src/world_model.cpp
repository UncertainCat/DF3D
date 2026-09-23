#include "wm/world_model.h"

#include <algorithm>
#include <iterator>
#include <cmath>
#include <stdexcept>
#include <unordered_set>

#include "wm/keyframes.h"
#include "event_coalescing.h"

namespace wm {

void KeyframeHistory::push(const Keyframe& kf) {
  if (!frames_.empty()) {
    Keyframe& last = frames_.back();
    if (kf.tick <= last.tick) return;
    if (kf.pos == last.pos && kf.job == last.job) {
      last.heldUntil = std::max(last.heldUntil, kf.tick);
      return;
    }
  }
  Keyframe stored = kf;
  stored.heldUntil = std::max(stored.heldUntil, stored.tick);
  frames_.push_back(stored);
  while (frames_.size() > kMaxFrames) frames_.pop_front();
}

const char* jobName(JobKind job) {
  switch (job) {
    case JobKind::Idle: return "Idle";
    case JobKind::Mine: return "Mine";
    case JobKind::HaulItem: return "HaulItem";
    case JobKind::ConstructBuilding: return "ConstructBuilding";
    case JobKind::Sleep: return "Sleep";
    case JobKind::Eat: return "Eat";
    case JobKind::Drink: return "Drink";
    case JobKind::Fight: return "Fight";
    case JobKind::Flee: return "Flee";
  }
  return "?";
}

const char* tileShapeName(TileShape s) {
  switch (s) {
    case TileShape::Empty: return "Empty";
    case TileShape::Wall: return "Wall";
    case TileShape::Floor: return "Floor";
    case TileShape::Ramp: return "Ramp";
    case TileShape::RampTop: return "RampTop";
    case TileShape::StairUp: return "StairUp";
    case TileShape::StairDown: return "StairDown";
    case TileShape::StairUpDown: return "StairUpDown";
    case TileShape::Fortification: return "Fortification";
    case TileShape::Boulder: return "Boulder";
    case TileShape::Pebbles: return "Pebbles";
    case TileShape::TreeTrunk: return "TreeTrunk";
    case TileShape::TreeBranch: return "TreeBranch";
    case TileShape::Shrub: return "Shrub";
    case TileShape::Sapling: return "Sapling";
    case TileShape::Unknown: return "Unknown";
  }
  return "?";
}

const char* materialKindName(MaterialKind k) {
  switch (k) {
    case MaterialKind::None: return "None";
    case MaterialKind::Stone: return "Stone";
    case MaterialKind::Soil: return "Soil";
    case MaterialKind::Mineral: return "Mineral";
    case MaterialKind::Gem: return "Gem";
    case MaterialKind::Ice: return "Ice";
    case MaterialKind::Wood: return "Wood";
    case MaterialKind::Plant: return "Plant";
    case MaterialKind::Grass: return "Grass";
    case MaterialKind::Constructed: return "Constructed";
    case MaterialKind::Water: return "Water";
    case MaterialKind::Magma: return "Magma";
    case MaterialKind::Unknown: return "Unknown";
  }
  return "?";
}

const char* liquidKindName(LiquidKind k) {
  switch (k) {
    case LiquidKind::None: return "None";
    case LiquidKind::Water: return "Water";
    case LiquidKind::Magma: return "Magma";
  }
  return "?";
}

namespace {
constexpr const char* kBuildingKindNames[] = {
    "Unknown",
    "Chair",
    "Bed",
    "Table",
    "Coffin",
    "FarmPlot",
    "Furnace",
    "TradeDepot",
    "Shop",
    "Door",
    "Floodgate",
    "Box",
    "Weaponrack",
    "Armorstand",
    "Workshop",
    "Cabinet",
    "Statue",
    "WindowGlass",
    "WindowGem",
    "Well",
    "Bridge",
    "RoadDirt",
    "RoadPaved",
    "SiegeEngine",
    "Trap",
    "AnimalTrap",
    "Support",
    "ArcheryTarget",
    "Chain",
    "Cage",
    "Stockpile",
    "Civzone",
    "Weapon",
    "Wagon",
    "ScrewPump",
    "Hatch",
    "GrateWall",
    "GrateFloor",
    "BarsVertical",
    "BarsFloor",
    "GearAssembly",
    "AxleHorizontal",
    "AxleVertical",
    "WaterWheel",
    "Windmill",
    "TractionBench",
    "Slab",
    "Nest",
    "NestBox",
    "Hive",
    "Rollers",
    "Instrument",
    "Bookcase",
    "DisplayFurniture",
    "OfferingPlace",
};

constexpr const char* kItemKindNames[] = {
    "Unknown",
    "Bar",
    "SmallGem",
    "Blocks",
    "Rough",
    "Boulder",
    "Wood",
    "Door",
    "Floodgate",
    "Bed",
    "Chair",
    "Chain",
    "Flask",
    "Goblet",
    "Instrument",
    "Toy",
    "Window",
    "Cage",
    "Barrel",
    "Bucket",
    "AnimalTrap",
    "Table",
    "Coffin",
    "Statue",
    "Corpse",
    "Weapon",
    "Armor",
    "Shoes",
    "Shield",
    "Helm",
    "Gloves",
    "Box",
    "Bag",
    "Bin",
    "Armorstand",
    "Weaponrack",
    "Cabinet",
    "Figurine",
    "Amulet",
    "Scepter",
    "Ammo",
    "Crown",
    "Ring",
    "Earring",
    "Bracelet",
    "Gem",
    "Anvil",
    "CorpsePiece",
    "Remains",
    "Meat",
    "Fish",
    "FishRaw",
    "Vermin",
    "Pet",
    "Seeds",
    "Plant",
    "SkinTanned",
    "PlantGrowth",
    "Thread",
    "Cloth",
    "Totem",
    "Pants",
    "Backpack",
    "Quiver",
    "CatapultParts",
    "BallistaParts",
    "SiegeAmmo",
    "BallistaArrowhead",
    "TrapParts",
    "TrapComp",
    "Drink",
    "PowderMisc",
    "Cheese",
    "Food",
    "LiquidMisc",
    "Coin",
    "Glob",
    "Rock",
    "PipeSection",
    "HatchCover",
    "Grate",
    "Quern",
    "Millstone",
    "Splint",
    "Crutch",
    "TractionBench",
    "OrthopedicCast",
    "Tool",
    "Slab",
    "Egg",
    "Book",
    "Sheet",
    "Branch",
};

}  // namespace

const char* buildingKindName(BuildingKind k) {
  const auto i = static_cast<size_t>(k);
  return i < std::size(kBuildingKindNames) ? kBuildingKindNames[i] : "?";
}

const char* buildingStageName(BuildingStage s) {
  switch (s) {
    case BuildingStage::Planned: return "Planned";
    case BuildingStage::InProgress: return "InProgress";
    case BuildingStage::Complete: return "Complete";
  }
  return "?";
}

const char* itemKindName(ItemKind k) {
  const auto i = static_cast<size_t>(k);
  return i < std::size(kItemKindNames) ? kItemKindNames[i] : "?";
}

void WorldModel::resetSession() {
  const auto next = sessionGeneration_ + 1;
  *this = WorldModel(cfg_);
  sessionGeneration_ = next;
}

bool WorldModel::ingest(const SnapshotData& snap, double arrivalWallSeconds) {
  if (latestTick_ && (snap.tick < *latestTick_ || snap.mapSize != mapSize_))
    resetSession();
  ++ingestSerial_;
  ingestBudgetExceeded_ = false;
  clock_.observe(snap.tick, arrivalWallSeconds);
  if (snap.mapSize != mapSize_ || blockIndex_.empty()) {
    // A new map: terrain and the entity stores start over (ids belong to
    // the old world); a Full for each table follows from the bridge.
    resetTerrain(snap.mapSize);
    clearEntities(snap.tick);
  }
  if (!firstTick_) firstTick_ = snap.tick;
  latestTick_ = snap.tick;
  const bool terrain = cfg_.ingestTerrain && snap.terrainScope != TerrainScope::None;
  const bool buildings = cfg_.ingestBuildings && snap.buildingScope != ChangeScope::None;
  const bool items = cfg_.ingestItems && snap.itemScope != ChangeScope::None;
  std::vector<MaterialId> remap;
  const bool spatters = cfg_.ingestTerrain && snap.spatterScope != ChangeScope::None;
  if (terrain || buildings || items || spatters) remap = remapMaterials(snap);
  if (terrain) ingestTerrain(snap, remap);
  if (spatters) ingestSpatters(snap, remap);
  if (buildings) ingestBuildings(snap, remap);
  if (items) ingestItems(snap, remap);
  if (items && snap.itemAppearanceScope != AppearanceScope::None) ingestItemAppearances(snap);
  if (snap.glyphScope != ChangeScope::None) ingestGlyphs(snap);
  if (!snap.commandResults.empty()) ingestCommandResults(snap);

  for (const auto& e : snap.reportEvents) if (e.id > lastReportEventId_) {
    lastReportEventId_ = e.id;
    reportEvents_.push_back(e);
  }
  while (!reportEvents_.empty() && (reportEvents_.size() > 512 ||
         (snap.tick > reportEvents_.front().tick && snap.tick-reportEvents_.front().tick > 600)))
    reportEvents_.pop_front();
  reportEventsDropped_ = std::max(reportEventsDropped_, snap.reportEventsDropped);

  for (const auto& e : snap.projectileCombatEvents) if (e.id > lastProjectileCombatEventId_) {
    lastProjectileCombatEventId_=e.id;
    projectileCombatEvents_.push_back(e);
  }
  while (!projectileCombatEvents_.empty() && (projectileCombatEvents_.size()>512 ||
         (snap.tick>projectileCombatEvents_.front().tick && snap.tick-projectileCombatEvents_.front().tick>600)))
    projectileCombatEvents_.pop_front();
  projectileCombatEventsDropped_=std::max(projectileCombatEventsDropped_,snap.projectileCombatEventsDropped);
  projectileCombatEventsAvailable_=snap.projectileCombatEventsAvailable;
  for (const auto& e : snap.resolvedAttacks) if (e.id > lastResolvedAttackId_) {
    lastResolvedAttackId_ = e.id;
    resolvedAttacks_.push_back(e);
  }
  while (!resolvedAttacks_.empty() && (resolvedAttacks_.size() > 512 ||
         (snap.tick > resolvedAttacks_.front().tick && snap.tick-resolvedAttacks_.front().tick > 600)))
    resolvedAttacks_.pop_front();
  resolvedAttacksDropped_ = std::max(resolvedAttacksDropped_, snap.resolvedAttacksDropped);
  resolvedAttacksAvailable_ = snap.resolvedAttacksAvailable;

  for (const auto& e : snap.itemContacts) if (e.id > lastItemContactId_) {
    lastItemContactId_ = e.id;
    itemContacts_.push_back(e);
  }
  while (!itemContacts_.empty() && (itemContacts_.size() > 512 ||
         (snap.tick > itemContacts_.front().tick && snap.tick-itemContacts_.front().tick > 600)))
    itemContacts_.pop_front();
  itemContactsDropped_ = std::max(itemContactsDropped_, snap.itemContactsDropped);
  itemContactsAvailable_ = snap.itemContactsAvailable;

  for (const auto& e : snap.combatEvents) if (e.id > lastCombatEventId_) {
    lastCombatEventId_ = e.id;
    combatEvents_.push_back(e);
  }
  while (!combatEvents_.empty() && (combatEvents_.size() > 256 ||
         (snap.tick > combatEvents_.front().tick && snap.tick - combatEvents_.front().tick > 600)))
    combatEvents_.pop_front();

  for (const auto& p : snap.projectileSamples) if (p.sequence > lastProjectileSequence_) {
    lastProjectileSequence_ = p.sequence;
    projectileSamples_.push_back(p);
  }
  while (!projectileSamples_.empty() && (projectileSamples_.size() > 512 ||
        (snap.tick > projectileSamples_.front().tick && snap.tick-projectileSamples_.front().tick > 120)))
    projectileSamples_.pop_front();

  // Mark-and-sweep departure detection over units currently alive. Each
  // listed unit is stamped with this ingest's serial; the sweep is one pass
  // over the store with no per-unit search of the snapshot.
  for (const UnitObservation& obs : snap.units) {
    auto [it, inserted] = units_.try_emplace(obs.id);
    UnitEntry& e = it->second;
    e.seenSerial = ingestSerial_;
    if (inserted || e.departedAt) {
      ++unitMembershipVersion_;
      e.species.assign(obs.species);
      e.departedAt.reset();
      if (cfg_.collectLifecycleEvents && reservePendingEventBytes(sizeof(LifecycleEvent)))
        pendingEvents_.push_back({LifecycleEvent::Kind::Appeared, obs.id, snap.tick});
    }
    e.bodyVolumeCm3 = obs.bodyVolumeCm3;
    e.statusFlags = obs.statusFlags;
    e.history.push(Keyframe{snap.tick, obs.pos, obs.job});
    if ((e.attacks.empty() && obs.attack.actionId >= 0) ||
        (!e.attacks.empty() && (obs.attack.actionId != e.attacks.back().attack.actionId ||
                              obs.attack.targetId != e.attacks.back().attack.targetId))) {
      UnitAttack attack = obs.attack;
      attack.observedAt = snap.tick;
      e.attacks.push_back({snap.tick, attack});
      if (e.attacks.size() > KeyframeHistory::kMaxFrames) e.attacks.pop_front();
    }
  }
  for (auto it = units_.begin(); it != units_.end();) {
    const UnitId id = it->first;
    UnitEntry& e = it->second;
    if (e.departedAt) {
      // Evict once the sim is far enough past the departure that no render
      // evaluation can still be asked about it (see kDepartedRetentionTicks).
      if (snap.tick > *e.departedAt + kDepartedRetentionTicks) {
        it = units_.erase(it);
        ++departedEvictions_;
        ++unitMembershipVersion_;
        continue;
      }
    } else if (e.seenSerial != ingestSerial_) {
      ++unitMembershipVersion_;
      e.departedAt = snap.tick;
      if (cfg_.collectLifecycleEvents && reservePendingEventBytes(sizeof(LifecycleEvent)))
        pendingEvents_.push_back({LifecycleEvent::Kind::Departed, id, snap.tick});
    }
    ++it;
  }
  if (snap.appearanceScope != AppearanceScope::None) ingestAppearances(snap);
  return !ingestBudgetExceeded_;
}

// --- unit appearance references ---

PageId WorldModel::internTilePage(std::string_view name) {
  auto it = tilePageIds_.find(name);
  if (it != tilePageIds_.end()) return it->second;
  if (tilePages_.size() >= kNoPage) return kNoPage;  // table full: degrade to none
  const PageId id = static_cast<PageId>(tilePages_.size());
  tilePages_.emplace_back(name);
  tilePageIds_.emplace(std::string(name), id);
  return id;
}

PaletteId WorldModel::internPalette(std::string_view name) {
  auto it = paletteIds_.find(name);
  if (it != paletteIds_.end()) return it->second;
  if (palettes_.size() >= kNoPalette) return kNoPalette;  // table full: degrade to none
  const PaletteId id = static_cast<PaletteId>(palettes_.size());
  palettes_.emplace_back(name);
  paletteIds_.emplace(std::string(name), id);
  return id;
}

void WorldModel::ingestAppearances(const SnapshotData& snap) {
  // Per-snapshot page / palette indices -> model-wide ids.
  std::vector<PageId> pageMap(snap.tilePages.size());
  for (size_t i = 0; i < snap.tilePages.size(); ++i) pageMap[i] = internTilePage(snap.tilePages[i]);
  std::vector<PaletteId> paletteMap(snap.palettes.size());
  for (size_t i = 0; i < snap.palettes.size(); ++i) paletteMap[i] = internPalette(snap.palettes[i]);

  bool anyChanged = false;
  for (const AppearanceObservation& obs : snap.appearances) {
    auto it = units_.find(obs.id);
    if (it == units_.end()) continue;  // validators reject this upstream
    UnitEntry& e = it->second;
    std::vector<AppearanceLayer> layers;
    layers.reserve(obs.layers.size());
    for (AppearanceLayer l : obs.layers) {
      l.page = l.page < pageMap.size() ? pageMap[l.page] : kNoPage;  // never a real page
      if (l.palette != kNoPalette) {
        l.palette = l.palette < paletteMap.size() ? paletteMap[l.palette] : kNoPalette;
        if (l.palette == kNoPalette) l.paletteRow = l.paletteKeyRow = kNoPaletteRow;
      }
      layers.push_back(l);
    }
    // A byte-identical re-send (same version, same layers) is not a change.
    if (e.appearance && e.appearance->version == obs.version && e.appearance->layers == layers) {
      continue;
    }
    if (!e.appearance) e.appearance.emplace();
    e.appearance->version = obs.version;
    e.appearance->tick = snap.tick;
    e.appearance->layers = std::move(layers);
    anyChanged = true;
    if (!e.appearancePending) {
      e.appearancePending = true;
      pendingAppearances_.push_back(obs.id);
    }
  }
  if (anyChanged) ++appearanceVersion_;
}

const UnitAppearance* WorldModel::unitAppearance(UnitId id) const {
  auto it = units_.find(id);
  if (it == units_.end() || !it->second.appearance) return nullptr;
  return &*it->second.appearance;
}

std::string_view WorldModel::tilePageName(PageId id) const {
  if (id == kNoPage || id >= tilePages_.size()) return {};
  return tilePages_[id];
}

std::string_view WorldModel::paletteName(PaletteId id) const {
  if (id == kNoPalette || id >= palettes_.size()) return {};
  return palettes_[id];
}

std::vector<AppearanceEvent> WorldModel::drainAppearanceEvents() {
  std::vector<AppearanceEvent> out;
  out.reserve(pendingAppearances_.size());
  for (UnitId id : pendingAppearances_) {
    auto it = units_.find(id);
    if (it == units_.end()) continue;
    UnitEntry& e = it->second;
    e.appearancePending = false;
    if (!e.appearance) continue;
    out.push_back(AppearanceEvent{id, e.appearance->version, e.appearance->tick});
  }
  pendingAppearances_.clear();
  auto restored = std::move(restoredEvents_.appearances);
  restoredEvents_.appearances.clear();
  detail::mergeLatest(restored, std::move(out), [](const auto& event) { return event.id; });
  return restored;
}

std::vector<ProjectileState> WorldModel::projectilesAt(double tick) const {
  struct Pair { const ProjectileSample* before=nullptr; const ProjectileSample* after=nullptr; };
  std::map<uint64_t,Pair> tracks;
  for (const auto& p : projectileSamples_) {
    auto& pair=tracks[p.projectileId];
    if (double(p.tick)<=tick) pair.before=&p;
    else if (!pair.after) pair.after=&p;
  }
  std::vector<ProjectileState> out;
  for (const auto& [id,pair] : tracks) {
    const auto* a=pair.before;
    if (!a || !a->active || tick-double(a->tick)>2.0) continue;
    Vec3 pos{float(a->pos.x),float(a->pos.y),float(a->pos.z)};
    Vec3 direction{float(a->pos.x-a->previous.x),float(a->pos.y-a->previous.y),float(a->pos.z-a->previous.z)};
    if (pair.after && pair.after->tick>a->tick) {
      const auto& b=*pair.after;
      const float t=float((tick-double(a->tick))/double(b.tick-a->tick));
      direction={float(b.pos.x-a->pos.x),float(b.pos.y-a->pos.y),float(b.pos.z-a->pos.z)};
      pos={pos.x+direction.x*t,pos.y+direction.y*t,pos.z+direction.z*t};
    }
    float length=std::sqrt(direction.x*direction.x+direction.y*direction.y+direction.z*direction.z);
    if (length<.0001f) {
      direction={float(a->target.x-a->origin.x),float(a->target.y-a->origin.y),float(a->target.z-a->origin.z)};
      length=std::sqrt(direction.x*direction.x+direction.y*direction.y+direction.z*direction.z);
    }
    if (length>.0001f) {direction.x/=length;direction.y/=length;direction.z/=length;}
    out.push_back({id,a->itemId,a->firerId,pos,direction});
  }
  return out;
}

double WorldModel::renderTickAt(double wallSeconds) const {
  if (!clock_.hasObservations()) return 0.0;
  const double delayed = clock_.estimate(wallSeconds) - cfg_.renderDelayTicks;
  // Never earlier than the first ingested tick: with a single snapshot (sim
  // paused since attach) the delayed clock would sit before every keyframe
  // and the world would evaluate empty.
  const double floor_ = firstTick_ ? static_cast<double>(*firstTick_) : 0.0;
  return std::max(delayed, floor_);
}

std::vector<UnitId> WorldModel::unitIds() const {
  std::vector<UnitId> ids;
  ids.reserve(units_.size());
  for (const auto& [id, e] : units_) ids.push_back(id);
  std::sort(ids.begin(), ids.end());
  return ids;
}

const std::string* WorldModel::unitSpecies(UnitId id) const {
  auto it = units_.find(id);
  return it == units_.end() ? nullptr : &it->second.species;
}

uint32_t WorldModel::unitBodyVolume(UnitId id) const {
  const auto it = units_.find(id);
  return it == units_.end() ? 0 : it->second.bodyVolumeCm3;
}

uint64_t WorldModel::unitStatusFlags(UnitId id) const {
  const auto it = units_.find(id);
  return it == units_.end() ? 0 : it->second.statusFlags;
}

EvalResult WorldModel::evaluate(UnitId id, double renderTick) const {
  auto it = units_.find(id);
  if (it == units_.end()) return EvalResult{};  // NotYetSeen
  const UnitEntry& e = it->second;
  EvalResult out = evaluateUnit(e.history, renderTick, e.departedAt, cfg_.classifier, cfg_.motion);
  if (out.presence == Presence::Present) {
    const auto next = std::upper_bound(e.attacks.begin(), e.attacks.end(), renderTick,
        [](double tick, const UnitEntry::AttackFrame& frame) { return tick < frame.tick; });
    if (next != e.attacks.begin()) out.attack = std::prev(next)->attack;
  }
  return out;
}

std::vector<std::pair<UnitId, EvalResult>> WorldModel::unitsInBox(
    TilePos min, TilePos max, double renderTick) const {
  std::vector<std::pair<UnitId, EvalResult>> out;
  for (const auto& [id, e] : units_) {
    EvalResult r = evaluate(id, renderTick);
    if (r.presence != Presence::Present) continue;
    if (r.pos.x < static_cast<float>(min.x) || r.pos.x > static_cast<float>(max.x) ||
        r.pos.y < static_cast<float>(min.y) || r.pos.y > static_cast<float>(max.y) ||
        r.pos.z < static_cast<float>(min.z) || r.pos.z > static_cast<float>(max.z)) {
      continue;
    }
    out.emplace_back(id, r);
  }
  std::sort(out.begin(), out.end(),
            [](const auto& a, const auto& b) { return a.first < b.first; });
  return out;
}

std::vector<LifecycleEvent> WorldModel::drainEvents() {
  std::vector<LifecycleEvent> out;
  out.swap(pendingEvents_);
  auto restored = std::move(restoredEvents_.lifecycle);
  restoredEvents_.lifecycle.clear();
  restored.insert(restored.end(), std::make_move_iterator(out.begin()), std::make_move_iterator(out.end()));
  return restored;
}

// --- terrain ---

namespace {
constexpr int32_t blocksAlong(int32_t tiles) { return (tiles + kBlockSize - 1) / kBlockSize; }
}  // namespace

void WorldModel::resetTerrain(TilePos mapSize) {
  mapSize_ = mapSize;
  blocksX_ = std::max(0, blocksAlong(mapSize.x));
  blocksY_ = std::max(0, blocksAlong(mapSize.y));
  const int64_t n = static_cast<int64_t>(blocksX_) * blocksY_ * std::max(0, mapSize.z);
  blockIndex_.assign(static_cast<size_t>(n), -1);
  blocks_.clear();
  pendingBlocks_.clear();
  terrainKnown_ = false;
  spatters_.clear();
  pendingSpatters_.clear();
  ++spatterVersion_;
  // Material ids stay stable for the model's lifetime even across a map
  // change; the table only grows.
}

bool WorldModel::inBlockRange(BlockPos b) const {
  return b.bx >= 0 && b.by >= 0 && b.bz >= 0 && b.bx < blocksX_ && b.by < blocksY_ &&
         b.bz < mapSize_.z;
}

int64_t WorldModel::blockSlot(BlockPos b) const {
  if (!inBlockRange(b)) return -1;
  const size_t cell = (static_cast<size_t>(b.bz) * blocksY_ + b.by) * blocksX_ + b.bx;
  return blockIndex_[cell];
}

MaterialId WorldModel::internMaterial(std::string_view name) {
  auto it = materialIds_.find(name);
  if (it != materialIds_.end()) return it->second;
  if (materials_.size() >= kNoMaterial) return kNoMaterial;  // table full: degrade to none
  const MaterialId id = static_cast<MaterialId>(materials_.size());
  materials_.emplace_back(name);
  materialIds_.emplace(std::string(name), id);
  return id;
}

std::vector<MaterialId> WorldModel::remapMaterials(const SnapshotData& snap) {
  std::vector<MaterialId> remap(snap.materials.size());
  for (size_t i = 0; i < snap.materials.size(); ++i) remap[i] = internMaterial(snap.materials[i]);
  return remap;
}

void WorldModel::ingestTerrain(const SnapshotData& snap, const std::vector<MaterialId>& remap) {
  bool anyChanged = false;
  for (const BlockObservation& obs : snap.blocks) {
    if (!inBlockRange(obs.pos)) continue;  // validators reject this upstream
    int64_t slot = blockSlot(obs.pos);
    bool changed = false;
    if (slot < 0) {
      slot = static_cast<int64_t>(blocks_.size());
      blocks_.push_back(Block{});
      blocks_.back().pos = obs.pos;
      const size_t cell =
          (static_cast<size_t>(obs.pos.bz) * blocksY_ + obs.pos.by) * blocksX_ + obs.pos.bx;
      blockIndex_[cell] = static_cast<int32_t>(slot);
      changed = true;
    }
    Block& blk = blocks_[static_cast<size_t>(slot)];
    const int32_t x0 = obs.pos.bx * kBlockSize, y0 = obs.pos.by * kBlockSize;
    const int32_t xn = std::min(kBlockSize, mapSize_.x - x0);
    const int32_t yn = std::min(kBlockSize, mapSize_.y - y0);
    for (int32_t ly = 0; ly < kBlockSize; ++ly) {
      for (int32_t lx = 0; lx < kBlockSize; ++lx) {
        const uint32_t i = tileIndexInBlock(lx, ly);
        TileState t;  // padding beyond the map stays Empty
        if (lx < xn && ly < yn) {
          t = obs.tiles[i];
          t.material = (t.material == kNoMaterial || t.material >= remap.size())
                           ? kNoMaterial
                           : remap[t.material];
        }
        if (!((*blk.tiles)[i] == t)) {
          if (blk.tiles.use_count() != 1) blk.tiles = std::make_shared<Block::Tiles>(*blk.tiles);
          (*blk.tiles)[i] = t;
          changed = true;
        }
      }
    }
    if (changed) {
      ++blk.version;
      blk.changedAt = snap.tick;
      anyChanged = true;
      if (!blk.pending) {
        blk.pending = true;
        pendingBlocks_.push_back(static_cast<size_t>(slot));
      }
    }
  }
  if (snap.terrainScope == TerrainScope::Full) terrainKnown_ = true;
  if (anyChanged) ++terrainVersion_;
}

std::optional<TileState> WorldModel::tileAt(TilePos p) const {
  if (p.x < 0 || p.y < 0 || p.x >= mapSize_.x || p.y >= mapSize_.y) return std::nullopt;
  const int64_t slot = blockSlot(blockOf(p));
  if (slot < 0) return std::nullopt;
  return (*blocks_[static_cast<size_t>(slot)].tiles)
      [tileIndexInBlock(p.x % kBlockSize, p.y % kBlockSize)];
}

std::optional<BlockView> WorldModel::block(BlockPos b) const {
  const int64_t slot = blockSlot(b);
  if (slot < 0) return std::nullopt;
  const Block& blk = blocks_[static_cast<size_t>(slot)];
  return BlockView{blk.pos, blk.version, blk.tiles->data()};
}

uint64_t WorldModel::blockVersion(BlockPos b) const {
  const int64_t slot = blockSlot(b);
  return slot < 0 ? 0 : blocks_[static_cast<size_t>(slot)].version;
}

std::vector<BlockView> WorldModel::blocksAtZ(int32_t z) const {
  std::vector<BlockView> out;
  if (z < 0 || z >= mapSize_.z) return out;
  for (int32_t by = 0; by < blocksY_; ++by) {
    for (int32_t bx = 0; bx < blocksX_; ++bx) {
      const int64_t slot = blockSlot(BlockPos{bx, by, z});
      if (slot < 0) continue;
      const Block& blk = blocks_[static_cast<size_t>(slot)];
      out.push_back(BlockView{blk.pos, blk.version, blk.tiles->data()});
    }
  }
  return out;
}

std::string_view WorldModel::materialName(MaterialId id) const {
  if (id == kNoMaterial || id >= materials_.size()) return {};
  return materials_[id];
}

std::vector<TerrainBlockEvent> WorldModel::drainTerrainEvents() {
  std::vector<TerrainBlockEvent> out;
  out.reserve(pendingBlocks_.size());
  for (size_t slot : pendingBlocks_) {
    Block& blk = blocks_[slot];
    blk.pending = false;
    out.push_back(TerrainBlockEvent{blk.pos, blk.version, blk.changedAt});
  }
  pendingBlocks_.clear();
  auto restored = std::move(restoredEvents_.terrain);
  restoredEvents_.terrain.clear();
  detail::mergeLatest(restored, std::move(out), [](const auto& event) { return event.pos; });
  return restored;
}

// --- buildings and map items ---

namespace {

MaterialId remapOne(uint16_t local, const std::vector<MaterialId>& remap) {
  return (local == kNoMaterial || local >= remap.size()) ? kNoMaterial : remap[local];
}

// Field-wise equality ignoring version / tick.
bool sameBuilding(const Building& a, const Building& b) {
  return a.kind == b.kind && a.subtype == b.subtype && a.custom == b.custom && a.x1 == b.x1 &&
         a.y1 == b.y1 && a.x2 == b.x2 && a.y2 == b.y2 && a.z == b.z && a.centerX == b.centerX &&
         a.centerY == b.centerY && a.extents == b.extents && a.material == b.material &&
         a.stage == b.stage && a.flags == b.flags;
}

bool sameItem(const MapItem& a, const MapItem& b) {
  return a.kind == b.kind && a.subtype == b.subtype && a.subtypeRaw == b.subtypeRaw &&
         a.material == b.material && a.pos == b.pos && a.stack == b.stack && a.flags == b.flags &&
         a.corpseFlags == b.corpseFlags && a.corpseUnitId == b.corpseUnitId;
}

Building toBuilding(const BuildingObservation& o, const std::vector<MaterialId>& remap) {
  Building b;
  b.id = o.id;
  b.kind = o.kind;
  b.subtype = o.subtype;
  b.custom.assign(o.custom);
  b.x1 = o.x1;
  b.y1 = o.y1;
  b.x2 = o.x2;
  b.y2 = o.y2;
  b.z = o.z;
  b.centerX = o.centerX;
  b.centerY = o.centerY;
  b.extents = o.extents;
  b.material = remapOne(o.material, remap);
  b.stage = o.stage;
  b.flags = o.flags;
  return b;
}

MapItem toItem(const ItemObservation& o, const std::vector<MaterialId>& remap) {
  MapItem it;
  it.id = o.id;
  it.kind = o.kind;
  it.subtype = o.subtype;
  it.subtypeRaw.assign(o.subtypeRaw);
  it.material = remapOne(o.material, remap);
  it.pos = o.pos;
  it.stack = o.stack;
  it.flags = o.flags;
  it.corpseFlags = o.corpseFlags;
  it.corpseUnitId = o.corpseUnitId;
  return it;
}

template <class E>
EntityChange changeKind(bool existedAtDrain, bool existsNow, bool& emit) {
  emit = existedAtDrain || existsNow;
  if (existedAtDrain) return existsNow ? EntityChange::Changed : EntityChange::Removed;
  return EntityChange::Added;
}

}  // namespace

void WorldModel::EntityPending::note(uint32_t id, bool existedBefore, uint64_t version,
                                     Tick tick) {
  auto it = slot.find(id);
  if (it == slot.end()) {
    // First change since the last drain: whether it existed before this
    // change is whether it existed at the drain.
    slot.emplace(id, list.size());
    list.push_back(PendingEntity{id, existedBefore, version, tick});
    return;
  }
  PendingEntity& p = list[it->second];
  p.version = version;
  p.tick = tick;
}

void WorldModel::removeBuildingSlot(size_t slot, Tick tick) {
  const Building& gone = buildings_[slot];
  pendingBuildings_.note(gone.id, true, gone.version, tick);
  buildingIndex_.erase(gone.id);
  const size_t last = buildings_.size() - 1;
  if (slot != last) {
    buildings_[slot] = std::move(buildings_[last]);
    buildingIndex_[buildings_[slot].id] = slot;
  }
  buildings_.pop_back();
}

void WorldModel::removeItemSlot(size_t slot, Tick tick) {
  const MapItem& gone = items_[slot];
  unindexItem(gone.id, gone.pos);
  pendingItems_.note(gone.id, true, gone.version, tick);
  itemIndex_.erase(gone.id);
  itemAppearances_.erase(gone.id);  // pendingItemAppearances_ tolerates the gap
  const size_t last = items_.size() - 1;
  if (slot != last) {
    items_[slot] = std::move(items_[last]);
    itemIndex_[items_[slot].id] = slot;
  }
  items_.pop_back();
}

void WorldModel::clearEntities(Tick tick) {
  bool any = false;
  while (!buildings_.empty()) {
    removeBuildingSlot(buildings_.size() - 1, tick);
    any = true;
  }
  if (any) ++buildingsVersion_;
  buildingsKnown_ = false;
  any = false;
  while (!items_.empty()) {
    removeItemSlot(items_.size() - 1, tick);
    any = true;
  }
  if (any) ++itemsVersion_;
  itemsKnown_ = false;
}

void WorldModel::ingestBuildings(const SnapshotData& snap, const std::vector<MaterialId>& remap) {
  bool any = false;
  for (const BuildingObservation& obs : snap.buildings) {
    Building nb = toBuilding(obs, remap);
    auto it = buildingIndex_.find(obs.id);
    if (it == buildingIndex_.end()) {
      nb.version = 1;
      nb.tick = snap.tick;
      buildingIndex_.emplace(obs.id, buildings_.size());
      buildings_.push_back(std::move(nb));
      pendingBuildings_.note(obs.id, false, 1, snap.tick);
      any = true;
      continue;
    }
    Building& b = buildings_[it->second];
    if (sameBuilding(b, nb)) continue;  // byte-identical re-send: not a change
    nb.version = b.version + 1;
    nb.tick = snap.tick;
    b = std::move(nb);
    pendingBuildings_.note(obs.id, true, b.version, snap.tick);
    any = true;
  }
  for (BuildingId id : snap.removedBuildings) {
    auto it = buildingIndex_.find(id);
    if (it == buildingIndex_.end()) continue;
    removeBuildingSlot(it->second, snap.tick);
    any = true;
  }
  if (snap.buildingScope == ChangeScope::Full) {
    // Anything the Full does not list no longer exists. One id set per
    // ingest keeps the sweep linear in the two table sizes.
    std::unordered_set<BuildingId> listed;
    listed.reserve(snap.buildings.size());
    for (const BuildingObservation& o : snap.buildings) listed.insert(o.id);
    std::vector<size_t> gone;
    for (size_t i = 0; i < buildings_.size(); ++i)
      if (!listed.count(buildings_[i].id)) gone.push_back(i);
    // Remove from the back so swap-and-pop never disturbs a pending slot.
    for (auto it = gone.rbegin(); it != gone.rend(); ++it) removeBuildingSlot(*it, snap.tick);
    if (!gone.empty()) any = true;
    buildingsKnown_ = true;
  }
  if (any) ++buildingsVersion_;
}

void WorldModel::ingestItems(const SnapshotData& snap, const std::vector<MaterialId>& remap) {
  bool any = false;
  for (const ItemObservation& obs : snap.items) {
    MapItem ni = toItem(obs, remap);
    auto it = itemIndex_.find(obs.id);
    if (it == itemIndex_.end()) {
      ni.version = 1;
      ni.tick = snap.tick;
      itemIndex_.emplace(obs.id, items_.size());
      indexItem(ni.id, ni.pos);
      items_.push_back(std::move(ni));
      pendingItems_.note(obs.id, false, 1, snap.tick);
      any = true;
      continue;
    }
    MapItem& cur = items_[it->second];
    if (sameItem(cur, ni)) continue;
    ni.version = cur.version + 1;
    ni.tick = snap.tick;
    if (cur.pos.z != ni.pos.z || itemBlock(cur.pos) != itemBlock(ni.pos)) {
      unindexItem(cur.id, cur.pos);
      indexItem(ni.id, ni.pos);
    }
    cur = std::move(ni);
    pendingItems_.note(obs.id, true, cur.version, snap.tick);
    any = true;
  }
  for (ItemId id : snap.removedItems) {
    auto it = itemIndex_.find(id);
    if (it == itemIndex_.end()) continue;
    removeItemSlot(it->second, snap.tick);
    any = true;
  }
  if (snap.itemScope == ChangeScope::Full) {
    std::unordered_set<ItemId> listed;
    listed.reserve(snap.items.size());
    for (const ItemObservation& o : snap.items) listed.insert(o.id);
    std::vector<size_t> gone;
    for (size_t i = 0; i < items_.size(); ++i)
      if (!listed.count(items_[i].id)) gone.push_back(i);
    for (auto it = gone.rbegin(); it != gone.rend(); ++it) removeItemSlot(*it, snap.tick);
    if (!gone.empty()) any = true;
    itemsKnown_ = true;
  }
  if (any) ++itemsVersion_;
}

const Building* WorldModel::building(BuildingId id) const {
  auto it = buildingIndex_.find(id);
  return it == buildingIndex_.end() ? nullptr : &buildings_[it->second];
}

std::vector<const Building*> WorldModel::buildingsAt(int32_t z) const {
  std::vector<const Building*> out;
  for (const Building& b : buildings_)
    if (b.z == z) out.push_back(&b);
  std::sort(out.begin(), out.end(),
            [](const Building* a, const Building* b) { return a->id < b->id; });
  return out;
}

std::vector<const Building*> WorldModel::buildingsInRect(int32_t x1, int32_t y1, int32_t x2,
                                                         int32_t y2, int32_t z) const {
  std::vector<const Building*> out;
  for (const Building& b : buildings_) {
    if (b.z != z || b.x2 < x1 || b.x1 > x2 || b.y2 < y1 || b.y1 > y2) continue;
    out.push_back(&b);
  }
  std::sort(out.begin(), out.end(),
            [](const Building* a, const Building* b) { return a->id < b->id; });
  return out;
}

const Building* WorldModel::buildingAt(TilePos p) const {
  const Building* best = nullptr;
  for (const Building& b : buildings_) {
    if (b.z != p.z || !b.occupies(p.x, p.y)) continue;
    if (!best || b.id < best->id) best = &b;
  }
  return best;
}

std::vector<BuildingEvent> WorldModel::drainBuildingEvents() {
  std::vector<BuildingEvent> out;
  out.reserve(pendingBuildings_.list.size());
  for (const PendingEntity& p : pendingBuildings_.list) {
    const Building* now = building(p.id);
    bool emit = false;
    const EntityChange kind = changeKind<Building>(p.existedAtDrain, now != nullptr, emit);
    if (!emit) continue;
    out.push_back(BuildingEvent{kind, p.id, now ? now->version : p.version,
                                now ? now->tick : p.tick});
  }
  pendingBuildings_.list.clear();
  pendingBuildings_.slot.clear();
  auto restored = std::move(restoredEvents_.buildings);
  restoredEvents_.buildings.clear();
  detail::mergeEntities(restored, std::move(out));
  return restored;
}

const MapItem* WorldModel::item(ItemId id) const {
  auto it = itemIndex_.find(id);
  return it == itemIndex_.end() ? nullptr : &items_[it->second];
}

void WorldModel::indexItem(ItemId id, TilePos p) {
  if (itemSpatial_.use_count() != 1) itemSpatial_ = std::make_shared<ItemSpatial>(*itemSpatial_);
  auto& level = (*itemSpatial_)[p.z];
  if (!level) level = std::make_shared<ItemLevel>();
  else if (level.use_count() != 1) level = std::make_shared<ItemLevel>(*level);
  auto& bucket = (*level)[itemBlock(p)];
  if (!bucket) bucket = std::make_shared<ItemBucket>();
  else if (bucket.use_count() != 1) bucket = std::make_shared<ItemBucket>(*bucket);
  bucket->insert(id);
}

void WorldModel::unindexItem(ItemId id, TilePos p) {
  if (itemSpatial_.use_count() != 1) itemSpatial_ = std::make_shared<ItemSpatial>(*itemSpatial_);
  auto level = itemSpatial_->find(p.z);
  if (level == itemSpatial_->end()) return;
  if (level->second.use_count() != 1) level->second = std::make_shared<ItemLevel>(*level->second);
  auto& blocks = *level->second;
  auto bucket = blocks.find(itemBlock(p));
  if (bucket == blocks.end()) return;
  if (bucket->second.use_count() != 1) bucket->second = std::make_shared<ItemBucket>(*bucket->second);
  bucket->second->erase(id);
  if (bucket->second->empty()) blocks.erase(bucket);
  if (blocks.empty()) itemSpatial_->erase(level);
}

std::vector<const MapItem*> WorldModel::itemsAt(int32_t z) const {
  std::vector<const MapItem*> out;
  forEachItemInZRange(z, z, [&](const MapItem& it) { out.push_back(&it); });
  std::sort(out.begin(), out.end(),
            [](const MapItem* a, const MapItem* b) { return a->id < b->id; });
  return out;
}

std::vector<const MapItem*> WorldModel::itemsAtTile(TilePos p) const {
  std::vector<const MapItem*> out;
  if (const auto level = itemSpatial_->find(p.z); level != itemSpatial_->end()) {
    if (const auto bucket = level->second->find(itemBlock(p)); bucket != level->second->end())
      for (ItemId id : *bucket->second) {
        const MapItem* it = item(id);
        if (it->pos == p) out.push_back(it);
      }
  }
  std::sort(out.begin(), out.end(),
            [](const MapItem* a, const MapItem* b) { return a->id < b->id; });
  return out;
}

std::vector<ItemEvent> WorldModel::drainItemEvents() {
  std::vector<ItemEvent> out;
  out.reserve(pendingItems_.list.size());
  for (const PendingEntity& p : pendingItems_.list) {
    const MapItem* now = item(p.id);
    bool emit = false;
    const EntityChange kind = changeKind<MapItem>(p.existedAtDrain, now != nullptr, emit);
    if (!emit) continue;
    out.push_back(ItemEvent{kind, p.id, now ? now->version : p.version, now ? now->tick : p.tick});
  }
  pendingItems_.list.clear();
  pendingItems_.slot.clear();
  auto restored = std::move(restoredEvents_.items);
  restoredEvents_.items.clear();
  detail::mergeEntities(restored, std::move(out));
  return restored;
}

}  // namespace wm

// --- corpse appearance references ---

namespace wm {

void WorldModel::ingestItemAppearances(const SnapshotData& snap) {
  std::vector<PageId> pageMap(snap.tilePages.size());
  for (size_t i = 0; i < snap.tilePages.size(); ++i) pageMap[i] = internTilePage(snap.tilePages[i]);
  std::vector<PaletteId> paletteMap(snap.palettes.size());
  for (size_t i = 0; i < snap.palettes.size(); ++i) paletteMap[i] = internPalette(snap.palettes[i]);

  bool anyChanged = false;
  for (const ItemAppearanceObservation& obs : snap.itemAppearances) {
    if (!itemIndex_.count(obs.id)) continue;  // validators reject this upstream
    std::vector<AppearanceLayer> layers;
    layers.reserve(obs.layers.size());
    for (AppearanceLayer l : obs.layers) {
      l.page = l.page < pageMap.size() ? pageMap[l.page] : kNoPage;  // never a real page
      if (l.palette != kNoPalette) {
        l.palette = l.palette < paletteMap.size() ? paletteMap[l.palette] : kNoPalette;
        if (l.palette == kNoPalette) l.paletteRow = l.paletteKeyRow = kNoPaletteRow;
      }
      layers.push_back(l);
    }
    auto [it, inserted] = itemAppearances_.try_emplace(obs.id);
    ItemAppearanceEntry& e = it->second;
    if (!inserted && e.appearance.version == obs.version && e.appearance.layers == layers) continue;
    e.appearance.version = obs.version;
    e.appearance.tick = snap.tick;
    e.appearance.layers = std::move(layers);
    anyChanged = true;
    if (!e.pending) {
      e.pending = true;
      pendingItemAppearances_.push_back(obs.id);
    }
  }
  if (anyChanged) ++itemAppearanceVersion_;
}

const ItemAppearance* WorldModel::itemAppearance(ItemId id) const {
  auto it = itemAppearances_.find(id);
  return it == itemAppearances_.end() ? nullptr : &it->second.appearance;
}

std::vector<ItemAppearanceEvent> WorldModel::drainItemAppearanceEvents() {
  std::vector<ItemAppearanceEvent> out;
  out.reserve(pendingItemAppearances_.size());
  for (ItemId id : pendingItemAppearances_) {
    auto it = itemAppearances_.find(id);
    if (it == itemAppearances_.end()) continue;  // the item left the map meanwhile
    it->second.pending = false;
    out.push_back(ItemAppearanceEvent{id, it->second.appearance.version, it->second.appearance.tick});
  }
  pendingItemAppearances_.clear();
  auto restored = std::move(restoredEvents_.itemAppearances);
  restoredEvents_.itemAppearances.clear();
  detail::mergeLatest(restored, std::move(out), [](const auto& event) { return event.id; });
  return restored;
}

// --- classic glyph tables ---

void WorldModel::ingestGlyphs(const SnapshotData& snap) {
  bool any = false;
  for (const CreatureGlyphObservation& obs : snap.creatureGlyphs) {
    if (obs.species.empty()) continue;
    auto it = creatureGlyphs_.find(obs.species);
    if (it == creatureGlyphs_.end()) {
      creatureGlyphs_.emplace(std::string(obs.species), obs.glyph);
      any = true;
    } else if (!(it->second == obs.glyph)) {
      it->second = obs.glyph;
      any = true;
    }
  }
  for (const MaterialGlyphObservation& obs : snap.materialGlyphs) {
    if (obs.material.empty()) continue;
    const MaterialId id = internMaterial(obs.material);
    if (id == kNoMaterial) continue;
    auto it = materialGlyphs_.find(id);
    if (it == materialGlyphs_.end()) {
      materialGlyphs_.emplace(id, obs.glyph);
      any = true;
    } else if (!(it->second == obs.glyph)) {
      it->second = obs.glyph;
      any = true;
    }
  }
  for (const ItemDefGlyphObservation& obs : snap.itemDefGlyphs) {
    if (obs.subtypeRaw.empty()) continue;
    std::string key = std::to_string(static_cast<unsigned>(obs.kind)) + ":";
    key.append(obs.subtypeRaw);
    auto it = itemDefGlyphs_.find(key);
    if (it == itemDefGlyphs_.end()) {
      itemDefGlyphs_.emplace(std::move(key),
                             ItemDefGlyph{obs.kind, std::string(obs.subtypeRaw), obs.tile});
      any = true;
    } else if (it->second.tile != obs.tile) {
      it->second.tile = obs.tile;
      any = true;
    }
  }
  if (snap.glyphScope == ChangeScope::Full) glyphsKnown_ = true;
  if (any) ++glyphVersion_;
}

// --- command results ---

namespace {
// Seqs remembered for repeat suppression. The bridge repeats a result for
// kCommandResultRepeatFrames snapshots; a window this wide covers any
// burst of commands a presentation can issue in that time.
constexpr size_t kSeenCommandWindow = 4096;
}  // namespace

void WorldModel::ingestCommandResults(const SnapshotData& snap) {
  for (const CommandResultObservation& obs : snap.commandResults) {
    if (seenCommandSeqs_.count(obs.seq)) continue;  // a repeat
    // Budget first: a result that does not fit stays unseen so the bridge's
    // repeat can deliver it once the consumer drains.
    if (!reservePendingEventBytes(sizeof(CommandResult) + obs.message.size())) continue;
    if (seenCommandOrder_.size() < kSeenCommandWindow) {
      seenCommandOrder_.push_back(obs.seq);
    } else {
      seenCommandSeqs_.erase(seenCommandOrder_[seenCommandCursor_]);
      seenCommandOrder_[seenCommandCursor_] = obs.seq;
      seenCommandCursor_ = (seenCommandCursor_ + 1) % kSeenCommandWindow;
    }
    seenCommandSeqs_.insert(obs.seq);
    pendingCommandResults_.push_back(
        CommandResult{obs.seq, obs.status, std::string(obs.message), snap.tick});
    pendingCommandBytes_ += sizeof(CommandResult) + obs.message.size();
    ++commandResultsReceived_;
  }
}

std::vector<CommandResult> WorldModel::drainCommandResults() {
  std::vector<CommandResult> out;
  out.swap(pendingCommandResults_);
  pendingCommandBytes_ = 0;
  auto restored = std::move(restoredEvents_.commands);
  restoredEvents_.commands.clear();
  restored.insert(restored.end(), std::make_move_iterator(out.begin()), std::make_move_iterator(out.end()));
  return restored;
}

const CreatureGlyph* WorldModel::creatureGlyph(std::string_view species) const {
  auto it = creatureGlyphs_.find(species);
  return it == creatureGlyphs_.end() ? nullptr : &it->second;
}

const MaterialGlyph* WorldModel::materialGlyph(MaterialId material) const {
  auto it = materialGlyphs_.find(material);
  return it == materialGlyphs_.end() ? nullptr : &it->second;
}

const ItemDefGlyph* WorldModel::itemDefGlyph(ItemKind kind, std::string_view subtypeRaw) const {
  std::string key = std::to_string(static_cast<unsigned>(kind)) + ":";
  key.append(subtypeRaw);
  auto it = itemDefGlyphs_.find(key);
  return it == itemDefGlyphs_.end() ? nullptr : &it->second;
}

}  // namespace wm

namespace wm {
bool WorldModel::reservePendingEventBytes(size_t bytes) {
  const size_t pending = pendingCommandBytes_ + pendingEvents_.size() * sizeof(LifecycleEvent);
  if (pending + bytes <= ModelEvents::kMaxRetainedBytes) return true;
  // Checked before anything is mutated: the model stays consistent, every
  // earlier receipt is kept, and later ingests are not poisoned.
  ++eventBudgetDrops_;
  ingestBudgetExceeded_ = true;
  lastIngestError_ = "ordered event backlog would exceed 32 MiB; receipts dropped; command outcomes may be unknown";
  return false;
}
ModelEvents WorldModel::drainAllEvents() {
  ModelEvents out;
  out.lifecycle = drainEvents();
  out.terrain = drainTerrainEvents();
  out.spatters = drainSpatterEvents();
  out.appearances = drainAppearanceEvents();
  out.buildings = drainBuildingEvents();
  out.items = drainItemEvents();
  out.itemAppearances = drainItemAppearanceEvents();
  out.commands = drainCommandResults();
  if (out.retainedBytes() > ModelEvents::kMaxRetainedBytes)
    throw std::length_error("event backlog exceeded 32 MiB; refresh complete state before continuing");
  return out;
}
void WorldModel::restoreEvents(ModelEvents events) { restoredEvents_.append(std::move(events)); }
} // namespace wm
