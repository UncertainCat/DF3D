#include "entities.h"

#include "modules/Items.h"
#include "modules/Units.h"

#include "df/building.h"
#include "df/building_actual.h"
#include "df/buildingitemst.h"
#include "df/building_item_role_type.h"
#include "df/building_civzonest.h"
#include "df/building_def.h"
#include "df/building_doorst.h"
#include "df/building_hatchst.h"
#include "df/building_type.h"
#include "df/item.h"
#include "df/item_body_component.h"
#include "df/item_type.h"
#include "df/itemdef.h"
#include "df/job.h"
#include "df/job_item_ref.h"
#include "df/unit.h"
#include "df/world.h"

#include "appearance_util.h"
#include "entity_util.h"
#include "item_visibility_policy.h"
#include "terrain_util.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <unordered_map>
#include <unordered_set>
#include <vector>

using namespace DFHack;
using df::global::world;

namespace df3d_entities {

namespace mir = df3d::mirror;
namespace app = df3d_appearance;

namespace {

using Clock = std::chrono::steady_clock;

AppearanceHooks g_hooks;

double usSince(Clock::time_point t0) {
    return std::chrono::duration<double, std::micro>(Clock::now() - t0).count();
}

// ---- enum mapping (verified against df-structures 53.16-r1 at compile time) ----

// BuildingKind = building_type + 1 below Construction, = building_type
// above it; pending Construction is appended. Anchors pin the schema to the enum.
static_assert(static_cast<int>(df::enums::building_type::Chair) == 0 &&
                  static_cast<int>(mir::BuildingKind::Chair) == 1,
              "BuildingKind anchor: Chair");
static_assert(static_cast<int>(df::enums::building_type::ScrewPump) + 1 ==
                  static_cast<int>(mir::BuildingKind::ScrewPump),
              "BuildingKind anchor: ScrewPump (last before Construction)");
static_assert(static_cast<int>(df::enums::building_type::Hatch) ==
                  static_cast<int>(mir::BuildingKind::Hatch),
              "BuildingKind anchor: Hatch (first after Construction)");
static_assert(static_cast<int>(df::enums::building_type::OfferingPlace) ==
                  static_cast<int>(mir::BuildingKind::OfferingPlace),
              "BuildingKind anchor: OfferingPlace (last)");

mir::BuildingKind mapBuildingKind(df::building_type t) {
    const int v = static_cast<int>(t);
    if (v < 0) return mir::BuildingKind::Unknown;
    if (t == df::enums::building_type::Construction) return mir::BuildingKind::Construction;
    if (v < static_cast<int>(df::enums::building_type::Construction)) return static_cast<mir::BuildingKind>(v + 1);
    if (v <= static_cast<int>(df::enums::building_type::OfferingPlace)) return static_cast<mir::BuildingKind>(v);
    return mir::BuildingKind::Unknown;  // a value newer than the schema (append it, never renumber)
}

// ItemKind = item_type + 1 up to Branch; later values (BOLT_THROWER_PARTS
// in 53.x) are Unknown until the schema appends them.
static_assert(static_cast<int>(df::enums::item_type::BAR) == 0 && static_cast<int>(mir::ItemKind::Bar) == 1,
              "ItemKind anchor: Bar");
static_assert(static_cast<int>(df::enums::item_type::BRANCH) + 1 == static_cast<int>(mir::ItemKind::Branch),
              "ItemKind anchor: Branch (last in the schema)");

mir::ItemKind mapItemKind(df::item_type t) {
    const int v = static_cast<int>(t);
    if (v < 0 || v > static_cast<int>(df::enums::item_type::BRANCH)) return mir::ItemKind::Unknown;
    return static_cast<mir::ItemKind>(v + 1);
}

// ---- shadows ----

struct BuildingRec {
    uint8_t kind = 0;
    uint8_t stage = 0;
    uint8_t flags = 0;
    uint16_t subtype = mir::kNoSubtype;
    uint16_t material = 0xFFFF;
    int32_t x1 = 0, y1 = 0, x2 = 0, y2 = 0, z = 0, cx = 0, cy = 0;
    const std::string* custom = nullptr;  // building_def::code (DF memory, stable for the session)
    std::vector<uint8_t> extents;          // empty = whole rectangle
};

bool sameRec(const BuildingRec& a, const BuildingRec& b) {
    return a.kind == b.kind && a.stage == b.stage && a.flags == b.flags && a.subtype == b.subtype &&
           a.material == b.material && a.x1 == b.x1 && a.y1 == b.y1 && a.x2 == b.x2 && a.y2 == b.y2 &&
           a.z == b.z && a.cx == b.cx && a.cy == b.cy && a.custom == b.custom && a.extents == b.extents;
}

struct BuildingShadow {
    int32_t id = 0;
    int32_t sendUntil = 0;   // re-sent while frame < sendUntil
    uint32_t slot = 0;       // refresh rotation slot
    uint32_t stamp = 0;      // resync generation last seen in buildings.all
    BuildingRec rec;
};

struct ItemShadow {
    int32_t id = 0;
    int32_t sendUntil = 0;
    uint32_t slot = 0;
    uint32_t lastPass = 0;   // item pass this shadow was last verified in
    uint8_t kind = 0;
    uint8_t flags = 0;
    bool corpse = false;     // kind Corpse / CorpsePiece: carries corpseFlags and a stack
    uint16_t subtype = mir::kNoSubtype;
    uint16_t material = 0xFFFF;
    uint16_t corpseFlags = 0;
    int32_t corpseUnitId = -1;
    int16_t x = 0, y = 0, z = 0;
    uint32_t stack = 1;
    const std::string* subtypeRaw = nullptr;  // itemdef::id (DF memory)
    // Corpse appearance: the resolved stack, its schema hash and
    // the fingerprint it was resolved at.
    uint32_t appFingerprint = 0;
    uint32_t appHash = 0;
    std::vector<app::Layer> layers;
};

struct Removed {
    int32_t id;
    int32_t until;
};

struct State {
    Config cfg;
    Stats st;

    std::vector<BuildingShadow> buildings;
    std::unordered_map<int32_t, uint32_t> buildingIndex;
    std::vector<df::building*> lastAll;   // pointer sequence of buildings.all at the last resync
    uint32_t buildingStamp = 0;
    uint32_t buildingCursor = 0;
    std::vector<Removed> removedBuildings;
    uint32_t nextBuildingSlot = 0;

    std::vector<ItemShadow> items;
    std::unordered_map<int32_t, uint32_t> itemIndex;
    uint32_t itemCursor = 0;
    uint32_t itemPass = 1;                 // current pass id (shadows stamp it when seen)
    std::vector<Removed> removedItems;
    uint32_t nextItemSlot = 0;

    bool initialPassDone = false;
    BuildingRec scratch;

    // Command hints: ids to re-visit on the next scan.
    std::vector<int32_t> hintedItems;
    std::vector<int32_t> hintedBuildings;

    // per-snapshot scratch
    std::vector<flatbuffers::Offset<mir::Building>> bOffsets;
    std::vector<flatbuffers::Offset<mir::MapItem>> iOffsets;
    std::vector<flatbuffers::Offset<mir::ItemAppearance>> aOffsets;
    std::vector<mir::AppearanceLayer> layerBuf;
    std::vector<uint32_t> removedBuf;
};

State s;

void track(double us, double& last, double& ema, double& mx) {
    last = us;
    ema = ema == 0.0 ? us : ema + (us - ema) / 64.0;
    if (us > mx) mx = us;
}

void eraseRemoved(std::vector<Removed>& v, int32_t id) {
    for (size_t i = 0; i < v.size(); ++i) {
        if (v[i].id == id) {
            v[i] = v.back();
            v.pop_back();
            return;
        }
    }
}

// ---- buildings ----

bool extractBuilding(df::building* b, df::building_type type, BuildingRec& rec, GridMaterialFn gm) {
    // Completed construction retires its pending entity on every scan path.
    if (type == df::enums::building_type::Construction &&
        b->getBuildStage() >= b->getMaxBuildStage()) return false;
    const auto bounds = mir::clipBuildingFootprint(
        {b->x1, b->y1, b->x2, b->y2, b->centerx, b->centery}, b->z,
        world->map.x_count, world->map.y_count, world->map.z_count);
    if (!bounds) return false;
    rec.kind = static_cast<uint8_t>(mapBuildingKind(type));
    switch (type) {
    case df::enums::building_type::Workshop:
    case df::enums::building_type::Furnace:
    case df::enums::building_type::Trap:
    case df::enums::building_type::SiegeEngine:
    case df::enums::building_type::Shop:
    case df::enums::building_type::Construction:
    case df::enums::building_type::Civzone: {
        const int16_t st = b->getSubtype();
        rec.subtype = st < 0 ? mir::kNoSubtype : static_cast<uint16_t>(st);
        break;
    }
    default:
        rec.subtype = mir::kNoSubtype;
        break;
    }
    rec.custom = nullptr;
    if (type == df::enums::building_type::Workshop || type == df::enums::building_type::Furnace) {
        const int32_t ct = b->getCustomType();
        if (ct >= 0) {
            if (const df::building_def* def = df::building_def::find(ct)) rec.custom = &def->code;
        }
    }
    rec.x1 = bounds->x1;
    rec.y1 = bounds->y1;
    rec.x2 = bounds->x2;
    rec.y2 = bounds->y2;
    rec.z = b->z;
    rec.cx = bounds->cx;
    rec.cy = bounds->cy;

    rec.extents.clear();
    if (b->room.extents && b->room.width > 0 && b->room.height > 0) {
        const int32_t w = rec.x2 - rec.x1 + 1, h = rec.y2 - rec.y1 + 1;
        rec.extents.resize(static_cast<size_t>(w) * static_cast<size_t>(h), 0);
        bool all = true;
        for (int32_t y = 0; y < h; ++y) {
            for (int32_t x = 0; x < w; ++x) {
                const int32_t rx = rec.x1 + x - b->room.x, ry = rec.y1 + y - b->room.y;
                uint8_t v = 0;
                if (rx >= 0 && ry >= 0 && rx < b->room.width && ry < b->room.height)
                    v = b->room.extents[ry * b->room.width + rx] != 0 ? 1 : 0;
                rec.extents[static_cast<size_t>(y) * w + x] = v;
                if (!v) all = false;
            }
        }
        if (all) rec.extents.clear();
    }

    rec.material = gm(b->mat_type, b->mat_index);

    if (b->flags.bits.exists) rec.stage = static_cast<uint8_t>(mir::BuildingStage::Complete);
    else if (b->getBuildStage() > 0) rec.stage = static_cast<uint8_t>(mir::BuildingStage::InProgress);
    else rec.stage = static_cast<uint8_t>(mir::BuildingStage::Planned);

    uint8_t flags = 0;
    if (type == df::enums::building_type::Door) {
        if (static_cast<df::building_doorst*>(b)->door_flags.bits.forbidden)
            flags |= static_cast<uint8_t>(mir::BuildingFlags::Forbidden);
    } else if (type == df::enums::building_type::Hatch) {
        if (static_cast<df::building_hatchst*>(b)->door_flags.bits.forbidden)
            flags |= static_cast<uint8_t>(mir::BuildingFlags::Forbidden);
    }
    if (type == df::enums::building_type::Civzone) {
        if (static_cast<df::building_civzonest*>(b)->assigned_unit_id != -1)
            flags |= static_cast<uint8_t>(mir::BuildingFlags::RoomAssigned);
    } else {
        for (const df::building_civzonest* z : b->relations) {
            if (z && z->assigned_unit_id != -1) {
                flags |= static_cast<uint8_t>(mir::BuildingFlags::RoomAssigned);
                break;
            }
        }
    }
    rec.flags = flags;
    return true;
}

void removeBuildingAt(uint32_t idx, int32_t frame) {
    BuildingShadow& sh = s.buildings[idx];
    s.removedBuildings.push_back({sh.id, frame + static_cast<int32_t>(s.cfg.repeat)});
    s.buildingIndex.erase(sh.id);
    const uint32_t last = static_cast<uint32_t>(s.buildings.size() - 1);
    if (idx != last) {
        s.buildings[idx] = std::move(s.buildings[last]);
        s.buildingIndex[s.buildings[idx].id] = idx;
    }
    s.buildings.pop_back();
    ++s.st.buildingRemoves;
}

// Re-extracts one building; adds it if unknown. Returns true if changed.
bool visitBuilding(df::building* b, df::building_type type, int32_t frame, GridMaterialFn gm) {
    ++s.st.buildingVisits;
    if (!extractBuilding(b, type, s.scratch, gm)) {
        const auto old = s.buildingIndex.find(b->id);
        if (old == s.buildingIndex.end()) return false;
        removeBuildingAt(old->second, frame);
        return true;
    }
    auto it = s.buildingIndex.find(b->id);
    if (it == s.buildingIndex.end()) {
        BuildingShadow sh;
        sh.id = b->id;
        sh.sendUntil = frame + static_cast<int32_t>(s.cfg.repeat);
        sh.slot = s.nextBuildingSlot++;
        sh.stamp = s.buildingStamp;
        sh.rec = s.scratch;
        s.buildingIndex.emplace(b->id, static_cast<uint32_t>(s.buildings.size()));
        s.buildings.push_back(std::move(sh));
        eraseRemoved(s.removedBuildings, b->id);
        ++s.st.buildingAdds;
        return true;
    }
    BuildingShadow& sh = s.buildings[it->second];
    sh.stamp = s.buildingStamp;
    if (sameRec(sh.rec, s.scratch)) return false;
    sh.rec = s.scratch;
    sh.sendUntil = frame + static_cast<int32_t>(s.cfg.repeat);
    ++s.st.buildingChanges;
    return true;
}

void scanBuildings(int32_t frame, bool fullPass, GridMaterialFn gm) {
    std::vector<df::building*>& all = world->buildings.all;
    for (int32_t id : s.hintedBuildings) {
        df::building* b = df::building::find(id);
        if (b) visitBuilding(b, b->getType(), frame, gm);
    }
    s.hintedBuildings.clear();
    const bool sequenceChanged = buildingSequenceChanged();
    if (fullPass || sequenceChanged) {
        ++s.st.buildingResyncs;
        ++s.buildingStamp;
        s.lastAll = all;
        for (df::building* b : all) {
            if (!b) continue;
            const df::building_type type = b->getType();
            if (fullPass || type == df::enums::building_type::Construction ||
                s.buildingIndex.find(b->id) == s.buildingIndex.end()) {
                visitBuilding(b, type, frame, gm);
            } else {
                s.buildings[s.buildingIndex[b->id]].stamp = s.buildingStamp;
            }
        }
        for (uint32_t i = 0; i < s.buildings.size();) {
            if (s.buildings[i].stamp != s.buildingStamp) removeBuildingAt(i, frame);
            else ++i;
        }
        if (fullPass) {
            s.buildingCursor = 0;
            return;
        }
    }
    if (all.empty()) return;
    const uint32_t pass = s.cfg.buildingPass == 0 ? 1 : s.cfg.buildingPass;
    const uint32_t n = static_cast<uint32_t>((all.size() + pass - 1) / pass);
    for (uint32_t i = 0; i < n; ++i) {
        if (s.buildingCursor >= all.size()) s.buildingCursor = 0;
        df::building* b = all[s.buildingCursor++];
        if (!b) continue;
        const df::building_type type = b->getType();
        visitBuilding(b, type, frame, gm);
    }
}

// ---- items ----

bool isCorpseKind(df::item_type t) {
    return t == df::enums::item_type::CORPSE || t == df::enums::item_type::CORPSEPIECE;
}

// item_body_component::corpse_flags bit for bit into the schema's
// CorpseFlags (same order: unbutchered .. yarn are bits 0..15 with
// use_blood_color at 13 skipped by the schema, so the map is explicit).
uint16_t corpseFlagsOf(const df::item* it) {
    const auto& f = static_cast<const df::item_body_component*>(it)->corpse_flags.bits;
    uint16_t out = 0;
    auto set = [&](bool b, mir::CorpseFlags flag) { if (b) out |= static_cast<uint16_t>(flag); };
    set(f.unbutchered, mir::CorpseFlags::Unbutchered);
    set(f.plant, mir::CorpseFlags::Plant);
    set(f.silk, mir::CorpseFlags::Silk);
    set(f.leather, mir::CorpseFlags::Leather);
    set(f.bone, mir::CorpseFlags::Bone);
    set(f.shell, mir::CorpseFlags::Shell);
    set(f.wood, mir::CorpseFlags::Wood);
    set(f.soap, mir::CorpseFlags::Soap);
    set(f.tooth, mir::CorpseFlags::Tooth);
    set(f.horn, mir::CorpseFlags::Horn);
    set(f.pearl, mir::CorpseFlags::Pearl);
    set(f.rottable, mir::CorpseFlags::Rottable);
    set(f.skull, mir::CorpseFlags::Skull);
    set(f.hair_wool, mir::CorpseFlags::HairWool);
    set(f.yarn, mir::CorpseFlags::Yarn);
    return out;
}

uint32_t hashStack(const std::vector<app::Layer>& layers) {
    uint32_t h = mir::appearanceHashBegin();
    for (const app::Layer& l : layers) {
        const std::string& page = app::pageToken(l.page);
        const std::string* pal = (l.palette && g_hooks.palettePath) ? &g_hooks.palettePath(l.palette) : nullptr;
        h = mir::appearanceHashLayer(h, page.data(), page.size(), l.tileX, l.tileY, l.cellsX, l.cellsY,
                                     pal ? pal->data() : "", pal ? pal->size() : 0, l.row, l.keyRow, l.offX, l.offY);
    }
    return h;
}

bool sameStack(const std::vector<app::Layer>& a, const std::vector<app::Layer>& b) {
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i)
        if (!a[i].sameReference(b[i])) return false;
    return true;
}

// Resolves (or re-resolves) a corpse shadow's stack. Returns true if the
// stack changed (the shadow must then be re-sent).
bool resolveCorpseShadow(df::item* it, ItemShadow& sh, bool first) {
    const auto t0 = Clock::now();
    app::Result r;
    app::resolveCorpse(it, r);
    ++s.st.corpseResolves;
    sh.appFingerprint = app::corpseFingerprint(it);
    bool changed = first;
    if (first || !sameStack(sh.layers, r.layers)) {
        sh.layers = std::move(r.layers);
        sh.appHash = hashStack(sh.layers);
        if (!first) {
            ++s.st.corpseChanges;
            changed = true;
        }
    }
    track(usSince(t0), s.st.corpseResolveUsLast, s.st.corpseResolveUsEma, s.st.corpseResolveUsMax);
    return changed;
}

// Built lazily once per holder during each scan, so a large workshop inventory
// is not searched again for every temporary item. The cache never crosses scans.
std::unordered_map<const df::building*, std::unordered_set<const df::item*>> temporaryContents;

bool visibleWorkshopTemporary(const df::item* it) {
    auto* holder = Items::getHolderBuilding(const_cast<df::item*>(it));
    if (!holder || (holder->getType() != df::building_type::Workshop &&
                    holder->getType() != df::building_type::Furnace)) return false;
    if (it->pos.z != holder->z || it->pos.x < holder->x1 || it->pos.x > holder->x2 ||
        it->pos.y < holder->y1 || it->pos.y > holder->y2) return false;
    auto found = temporaryContents.find(holder);
    if (found == temporaryContents.end()) {
        auto& items = temporaryContents[holder];
        auto* actual = static_cast<df::building_actual*>(holder);
        for (const auto* contained : actual->contained_items)
            if (contained && contained->item && contained->use_mode == df::building_item_role_type::TEMP)
                items.insert(contained->item);
        found = temporaryContents.find(holder);
    }
    return found->second.count(it) != 0;
}

bool itemQualifies(const df::item* it, int32_t mx, int32_t my, int32_t mz) {
    const auto& f = it->flags.bits;
    df3d_bridge::MapItemPlacement placement;
    placement.onGround = f.on_ground;
    placement.inInventory = f.in_inventory;
    placement.inBuilding = f.in_building;
    placement.removed = f.removed;
    placement.garbageCollect = f.garbage_collect;
    placement.positionValid = it->pos.x >= 0 && it->pos.y >= 0 && it->pos.z >= 0 &&
                              it->pos.x < mx && it->pos.y < my && it->pos.z < mz;
    // Preserve the existing ground path. TEMP_PRINTHIDDEN, PERM and arbitrary
    // inventory are never admitted by the additional workshop/furnace path.
    if (!placement.onGround && !placement.inInventory && !placement.inBuilding &&
        !placement.removed && !placement.garbageCollect && placement.positionValid &&
        visibleWorkshopTemporary(it)) {
        placement.storage = df3d_bridge::TemporaryStorage::WorkshopVisible;
        placement.holderPositionValid = true;
    }
    return df3d_bridge::mapItemEligible(placement);
}

uint8_t itemFlags(const df::item* it) {
    const auto& f = it->flags.bits;
    uint8_t out = 0;
    if (f.forbid) out |= static_cast<uint8_t>(mir::ItemFlags::Forbidden);
    if (f.dump) out |= static_cast<uint8_t>(mir::ItemFlags::Dump);
    if (f.melt) out |= static_cast<uint8_t>(mir::ItemFlags::Melt);
    if (f.on_fire) out |= static_cast<uint8_t>(mir::ItemFlags::OnFire);
    if (f.rotten) out |= static_cast<uint8_t>(mir::ItemFlags::Rotten);
    if (f.artifact) out |= static_cast<uint8_t>(mir::ItemFlags::Artifact);
    if (f.spider_web) out |= static_cast<uint8_t>(mir::ItemFlags::Web);
    return out;
}

void removeItemAt(uint32_t idx, int32_t frame) {
    ItemShadow& sh = s.items[idx];
    s.removedItems.push_back({sh.id, frame + static_cast<int32_t>(s.cfg.repeat)});
    s.itemIndex.erase(sh.id);
    const uint32_t last = static_cast<uint32_t>(s.items.size() - 1);
    if (idx != last) {
        s.items[idx] = std::move(s.items[last]);
        s.itemIndex[s.items[idx].id] = idx;
    }
    s.items.pop_back();
    ++s.st.itemRemoves;
}

// Checks one item against its shadow: add / update / remove as needed.
// Field mapping: kind from getType(); subtype = getSubtype() only
// when Items::getSubtypeDef resolves an itemdef (weapons, armour, ammo,
// tools, ...; PLANT_GROWTH's subtype is a growth index, published as none),
// subtype_raw = that itemdef's id; material from getMaterial() /
// getMaterialIndex(); pos verbatim; stack = getStackSize() (>= 1); flags
// from item.flags bits of the same names (Web = spider_web, v5);
// corpse_flags from item_body_component::corpse_flags on Corpse /
// CorpsePiece items, whose appearance stack is resolved here too.
void visitItem(df::item* it, int32_t frame, int32_t mx, int32_t my, int32_t mz, GridMaterialFn gm) {
    ++s.st.itemVisits;
    auto found = s.itemIndex.find(it->id);
    if (!itemQualifies(it, mx, my, mz)) {
        if (found != s.itemIndex.end()) removeItemAt(found->second, frame);
        return;
    }
    const uint8_t flags = itemFlags(it);
    const int32_t stackRaw = it->getStackSize();
    const uint32_t stack = stackRaw < 1 ? 1u : static_cast<uint32_t>(stackRaw);
    if (found != s.itemIndex.end()) {
        ItemShadow& sh = s.items[found->second];
        sh.lastPass = s.itemPass;
        bool changed = false;
        if (sh.corpse) {
            const int32_t owner = static_cast<const df::item_body_component*>(it)->unit_id;
            if (owner != sh.corpseUnitId) { sh.corpseUnitId = owner; changed = true; }
            const uint16_t cf = corpseFlagsOf(it);
            if (cf != sh.corpseFlags) {
                sh.corpseFlags = cf;
                changed = true;
            }
            if (app::corpseFingerprint(it) != sh.appFingerprint && resolveCorpseShadow(it, sh, false)) changed = true;
        }
        if (!changed && sh.x == it->pos.x && sh.y == it->pos.y && sh.z == it->pos.z && sh.stack == stack &&
            sh.flags == flags)
            return;
        sh.x = it->pos.x;
        sh.y = it->pos.y;
        sh.z = it->pos.z;
        sh.stack = stack;
        sh.flags = flags;
        sh.sendUntil = frame + static_cast<int32_t>(s.cfg.repeat);
        ++s.st.itemChanges;
        return;
    }
    ItemShadow sh;
    sh.id = it->id;
    sh.sendUntil = frame + static_cast<int32_t>(s.cfg.repeat);
    sh.slot = s.nextItemSlot++;
    sh.lastPass = s.itemPass;
    const df::item_type type = it->getType();
    sh.kind = static_cast<uint8_t>(mapItemKind(type));
    sh.corpse = isCorpseKind(type);
    if (sh.corpse) {
        sh.corpseFlags = corpseFlagsOf(it);
        sh.corpseUnitId = static_cast<const df::item_body_component*>(it)->unit_id;
        resolveCorpseShadow(it, sh, true);
    }
    const int16_t st = it->getSubtype();
    sh.subtype = mir::kNoSubtype;
    sh.subtypeRaw = nullptr;
    if (st >= 0) {
        if (const df::itemdef* def = Items::getSubtypeDef(type, st)) {
            sh.subtype = static_cast<uint16_t>(st);
            sh.subtypeRaw = &def->id;
        }
    }
    sh.material = gm(it->getMaterial(), it->getMaterialIndex());
    if (sh.corpse && sh.material == 0xFFFF) {
        // item_body_component carries no mat_type / mat_index, so DF's
        // getMaterial() yields nothing for corpses and pieces. The
        // substance a piece counts as is its largest tissue (BONE for a bone / skeleton, MUSCLE
        // for a fresh corpse, SKIN for a hide), which is what the
        // presentation's piece rule keys on.
        auto* c = static_cast<df::item_body_component*>(it);
        if (c->largest_tissue.mat_type >= 0)
            sh.material = gm(c->largest_tissue.mat_type, c->largest_tissue.mat_index);
    }
    sh.x = it->pos.x;
    sh.y = it->pos.y;
    sh.z = it->pos.z;
    sh.stack = stack;
    sh.flags = flags;
    const int32_t newId = sh.id;
    s.itemIndex.emplace(newId, static_cast<uint32_t>(s.items.size()));
    s.items.push_back(std::move(sh));
    eraseRemoved(s.removedItems, newId);
    ++s.st.itemAdds;
}

// End of a complete pass: shadows the pass did not see are verified by id
// (destroyed items never come through the vector again; items skipped by
// a vector shift are re-checked here).
void sweepItems(int32_t frame, int32_t mx, int32_t my, int32_t mz, GridMaterialFn gm) {
    for (uint32_t i = 0; i < s.items.size();) {
        if (s.items[i].lastPass == s.itemPass) {
            ++i;
            continue;
        }
        ++s.st.itemVerifies;
        df::item* it = df::item::find(s.items[i].id);
        if (!it) {
            removeItemAt(i, frame);
            continue;
        }
        const size_t before = s.items.size();
        visitItem(it, frame, mx, my, mz, gm);
        if (s.items.size() == before) ++i;  // still present (possibly updated)
    }
}

void scanItems(int32_t frame, bool fullPass, GridMaterialFn gm) {
    const int32_t mx = world->map.x_count, my = world->map.y_count, mz = world->map.z_count;

    // Command hints: the items a command just touched.
    for (int32_t id : s.hintedItems) {
        if (df::item* it = df::item::find(id)) {
            ++s.st.itemHints;
            visitItem(it, frame, mx, my, mz, gm);
        }
    }
    s.hintedItems.clear();

    // Hints: every item referenced by a unit's current job, every frame.
    for (df::unit* u : world->units.active) {
        if (!u || !Units::isActive(u)) continue;
        const df::job* j = u->job.current_job;
        if (!j) continue;
        for (const df::job_item_ref* ref : j->items) {
            if (ref && ref->item) {
                ++s.st.itemHints;
                visitItem(ref->item, frame, mx, my, mz, gm);
            }
        }
    }

    std::vector<df::item*>& vec = world->items.other.IN_PLAY;
    if (fullPass) {
        for (df::item* it : vec)
            if (it) visitItem(it, frame, mx, my, mz, gm);
        sweepItems(frame, mx, my, mz, gm);
        ++s.itemPass;
        ++s.st.itemPasses;
        s.itemCursor = 0;
        return;
    }
    if (vec.empty()) {
        // Nothing in play: every shadow is stale.
        for (uint32_t i = 0; i < s.items.size();) removeItemAt(i, frame);
        return;
    }
    const uint32_t pass = s.cfg.itemPass == 0 ? 1 : s.cfg.itemPass;
    const uint32_t n = static_cast<uint32_t>((vec.size() + pass - 1) / pass);
    for (uint32_t i = 0; i < n; ++i) {
        if (s.itemCursor >= vec.size()) {
            sweepItems(frame, mx, my, mz, gm);
            ++s.itemPass;
            ++s.st.itemPasses;
            s.itemCursor = 0;
            if (vec.empty()) return;
        }
        if (df::item* it = vec[s.itemCursor++]) visitItem(it, frame, mx, my, mz, gm);
    }
}

}  // namespace

// ---- public API ----

Config& config() { return s.cfg; }
const Stats& stats() {
    s.st.buildings = s.buildings.size();
    s.st.items = s.items.size();
    s.st.corpses = 0;
    s.st.corpsesWithStack = 0;
    for (const ItemShadow& sh : s.items) {
        if (!sh.corpse) continue;
        ++s.st.corpses;
        if (!sh.layers.empty()) ++s.st.corpsesWithStack;
    }
    return s.st;
}
void resetStatsMax() {
    s.st.scanUsMax = 0;
    s.st.corpseResolveUsMax = 0;
}

void setAppearanceHooks(const AppearanceHooks& hooks) { g_hooks = hooks; }

void reset() {
    const Config cfg = s.cfg;
    s = State();
    s.cfg = cfg;
}

bool buildingSequenceChanged() {
    if (!world) return false;
    const auto& all = world->buildings.all;
    return all.size() != s.lastAll.size() ||
        (!all.empty() && std::memcmp(all.data(), s.lastAll.data(), all.size() * sizeof(df::building*)) != 0);
}

bool pendingConstructionChanged(void (*hintTerrain)(int32_t,int32_t,int32_t)) {
    if (!world) return false;
    bool changed = false;
    for (const auto& shadow : s.buildings) {
        if (shadow.rec.kind != static_cast<uint8_t>(mir::BuildingKind::Construction)) continue;
        auto* b = df::building::find(shadow.id);
        bool differs = !b || b->getType() != df::enums::building_type::Construction;
        if (!differs) {
            const int stage = b->getBuildStage();
            differs = stage >= b->getMaxBuildStage() || b->getSubtype() != shadow.rec.subtype ||
                (stage > 0) != (shadow.rec.stage == static_cast<uint8_t>(mir::BuildingStage::InProgress));
        }
        if (!differs) continue;
        changed = true;
        // Refresh the authoritative terrain before retiring its pending marker.
        if (hintTerrain) hintTerrain(shadow.rec.x1,shadow.rec.y1,shadow.rec.z);
    }
    return changed;
}

void scan(int32_t frame, bool fullPass, GridMaterialFn gridMaterial) {
    temporaryContents.clear();
    if (!world) return;
    const auto t0 = Clock::now();
    const bool full = fullPass || !s.initialPassDone;
    scanBuildings(frame, full, gridMaterial);
    scanItems(frame, full, gridMaterial);
    s.initialPassDone = true;
    const double us = usSince(t0);
    if (full) s.st.fullPassUsLast = us;
    else track(us, s.st.scanUsLast, s.st.scanUsEma, s.st.scanUsMax);
}

void build(flatbuffers::FlatBufferBuilder& fbb, int32_t frame, bool full, LocalMaterialFn localMaterial,
           Built& out, bool ring) {
    out = Built();
    s.bOffsets.clear();
    s.iOffsets.clear();
    // The ring slot bounds a snapshot; a recording entry has no bound and
    // must not disturb the ring's repeat windows.
    const size_t cap = !ring ? SIZE_MAX : (s.cfg.maxPerSnapshot == 0 ? 1 : s.cfg.maxPerSnapshot);
    const uint32_t refresh = s.cfg.refresh;
    const auto due = [&](int32_t sendUntil, uint32_t slot) {
        return full || frame < sendUntil ||
               (refresh > 0 && ((static_cast<uint32_t>(frame) + slot) % refresh) == 0);
    };
    bool spilled = false;

    // Buildings.
    for (BuildingShadow& sh : s.buildings) {
        if (!due(sh.sendUntil, sh.slot)) continue;
        if (out.count >= cap) {
            // Spill: keep it due for the next frame (a Full's remainder
            // follows as Delta adds).
            sh.sendUntil = std::max(sh.sendUntil, frame + 2);
            spilled = true;
            continue;
        }
        const BuildingRec& r = sh.rec;
        flatbuffers::Offset<flatbuffers::String> custom;
        if (r.custom) custom = fbb.CreateSharedString(*r.custom);
        flatbuffers::Offset<flatbuffers::Vector<uint8_t>> extents;
        if (!r.extents.empty()) extents = fbb.CreateVector(r.extents);
        const uint16_t mat = r.material == 0xFFFF ? mir::kNoMaterial : localMaterial(fbb, r.material);
        s.bOffsets.push_back(mir::CreateBuilding(
            fbb, static_cast<uint32_t>(sh.id), static_cast<mir::BuildingKind>(r.kind), r.subtype, custom,
            r.x1, r.y1, r.x2, r.y2, r.z, r.cx, r.cy, extents, mat, static_cast<mir::BuildingStage>(r.stage),
            static_cast<mir::BuildingFlags>(r.flags)));
        ++out.count;
        if (full && ring) sh.sendUntil = 0;
    }
    s.removedBuf.clear();
    if (!full) {
        for (const Removed& r : s.removedBuildings)
            if (frame < r.until) s.removedBuf.push_back(static_cast<uint32_t>(r.id));
    }
    if (!s.bOffsets.empty() || !s.removedBuf.empty() || full) {
        out.buildingScope = full ? mir::ChangeScope::Full : mir::ChangeScope::Delta;
        out.buildings = fbb.CreateVector(s.bOffsets);
        if (!s.removedBuf.empty()) out.removedBuildings = fbb.CreateVector(s.removedBuf);
    }
    s.st.lastSentBuildings = s.bOffsets.size();
    s.st.sentBuildings += s.bOffsets.size();
    size_t removedCount = s.removedBuf.size();

    // Items (a corpse's stack rides with its record).
    s.aOffsets.clear();
    s.layerBuf.clear();
    for (ItemShadow& sh : s.items) {
        if (!due(sh.sendUntil, sh.slot)) continue;
        if (out.count >= cap) {
            sh.sendUntil = std::max(sh.sendUntil, frame + 2);
            spilled = true;
            continue;
        }
        flatbuffers::Offset<flatbuffers::String> raw;
        if (sh.subtypeRaw) raw = fbb.CreateSharedString(*sh.subtypeRaw);
        const uint16_t mat = sh.material == 0xFFFF ? mir::kNoMaterial : localMaterial(fbb, sh.material);
        const mir::TilePos pos(sh.x, sh.y, sh.z);
        s.iOffsets.push_back(mir::CreateMapItem(fbb, static_cast<uint32_t>(sh.id),
                                                static_cast<mir::ItemKind>(sh.kind), sh.subtype, raw, mat,
                                                &pos, sh.stack, static_cast<mir::ItemFlags>(sh.flags),
                                                static_cast<mir::CorpseFlags>(sh.corpseFlags), sh.corpseUnitId));
        if (sh.corpse && g_hooks.encodeLayer) {
            s.layerBuf.clear();
            for (const app::Layer& l : sh.layers) s.layerBuf.push_back(g_hooks.encodeLayer(fbb, l));
            auto layersVec = fbb.CreateVectorOfStructs(s.layerBuf);
            s.aOffsets.push_back(mir::CreateItemAppearance(fbb, static_cast<uint32_t>(sh.id), sh.appHash, layersVec));
        }
        ++out.count;
        if (full && ring) sh.sendUntil = 0;
    }
    if (!s.aOffsets.empty()) {
        out.itemAppearanceScope = full ? mir::AppearanceScope::Full : mir::AppearanceScope::Delta;
        out.itemAppearances = fbb.CreateVector(s.aOffsets);
    } else if (full) {
        out.itemAppearanceScope = mir::AppearanceScope::Full;  // vacuous: no corpse items
    }
    s.st.lastSentItemAppearances = s.aOffsets.size();
    s.removedBuf.clear();
    if (!full) {
        for (const Removed& r : s.removedItems)
            if (frame < r.until) s.removedBuf.push_back(static_cast<uint32_t>(r.id));
    }
    if (!s.iOffsets.empty() || !s.removedBuf.empty() || full) {
        out.itemScope = full ? mir::ChangeScope::Full : mir::ChangeScope::Delta;
        out.items = fbb.CreateVector(s.iOffsets);
        if (!s.removedBuf.empty()) out.removedItems = fbb.CreateVector(s.removedBuf);
    }
    s.st.lastSentItems = s.iOffsets.size();
    s.st.sentItems += s.iOffsets.size();
    removedCount += s.removedBuf.size();
    s.st.lastSentRemoved = removedCount;

    if (full) ++s.st.fullsBuilt;
    else if (out.count > 0 || removedCount > 0) ++s.st.deltasBuilt;
    if (spilled) ++s.st.spills;
}

void published(int32_t frame, bool full) {
    if (full) {
        // A Full supersedes every pending removal; the shadows it could not
        // fit are already marked due (spill rule).
        s.removedBuildings.clear();
        s.removedItems.clear();
        return;
    }
    // Retire expired removals (kept `repeat` frames for slow clients).
    auto expire = [frame](std::vector<Removed>& v) {
        for (size_t i = 0; i < v.size();) {
            if (frame + 1 >= v[i].until) {
                v[i] = v.back();
                v.pop_back();
            } else {
                ++i;
            }
        }
    };
    expire(s.removedBuildings);
    expire(s.removedItems);
}

void printStatus(color_ostream& out) {
    const Stats& st = stats();
    out.print("  entities:            {} buildings, {} items tracked\n", st.buildings, st.items);
    out.print("    periods:           item pass {} frames, building pass {} frames, repeat {} frames, "
              "refresh every {} frames, cap {} records/snapshot\n",
              s.cfg.itemPass, s.cfg.buildingPass, s.cfg.repeat, s.cfg.refresh, s.cfg.maxPerSnapshot);
    out.print("    buildings:         {} resyncs, {} visits, {} adds, {} changes, {} removes\n",
              st.buildingResyncs, st.buildingVisits, st.buildingAdds, st.buildingChanges, st.buildingRemoves);
    out.print("    items:             {} passes, {} visits ({} hints, {} verifies), {} adds, {} changes, {} removes\n",
              st.itemPasses, st.itemVisits, st.itemHints, st.itemVerifies, st.itemAdds, st.itemChanges,
              st.itemRemoves);
    out.print("    published:         {} Fulls, {} Deltas, {} buildings + {} items sent, {} spills; "
              "last snapshot {} buildings, {} items, {} removed ({} bytes); last Full {} bytes\n",
              st.fullsBuilt, st.deltasBuilt, st.sentBuildings, st.sentItems, st.spills, st.lastSentBuildings,
              st.lastSentItems, st.lastSentRemoved, st.lastEntityBytes, st.lastFullBytes);
    out.print("    entity scan (us):  {:.0f} / {:.0f} / {:.0f}  (last/ema/max; full pass {:.0f} us)\n",
              st.scanUsLast, st.scanUsEma, st.scanUsMax, st.fullPassUsLast);
    out.print("    corpses:           {} tracked, {} with a stack; {} resolves, {} stack changes; last snapshot {} item appearances; "
              "resolve (us) {:.0f} / {:.0f} / {:.0f}\n",
              st.corpses, st.corpsesWithStack, st.corpseResolves, st.corpseChanges, st.lastSentItemAppearances,
              st.corpseResolveUsLast, st.corpseResolveUsEma, st.corpseResolveUsMax);
}

Stats& mutableStats() { return s.st; }

void hintItem(int32_t id) { s.hintedItems.push_back(id); }
void hintBuilding(int32_t id) { s.hintedBuildings.push_back(id); }

}  // namespace df3d_entities
