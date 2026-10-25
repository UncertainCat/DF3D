#include "modules/Materials.h"
#include "df/material.h"
#include "df/material_flags.h"
#include "df/item_slabst.h"
#include "bed_appearance_native.h"
#include "construction_site_native.h"
#include "df/building_bridgest.h"
#include "df/building_siegeenginest.h"
#include "df/building_trapst.h"
#include "df/building_weaponst.h"
#include "df/itemdef_weaponst.h"
#include "df/itemdef_trapcompst.h"
#include "df/building_screw_pumpst.h"
#include "df/building_rollersst.h"
#include "df/building_water_wheelst.h"
#include "df/building_windmillst.h"
#include "df/building_axle_horizontalst.h"
#include "df/machine.h"
#include "df/itemdef_instrumentst.h"
#include "df/itemdef_toolst.h"
#include "df/instrument_flags.h"
#include "df/job_skill.h"
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
#include "df/general_ref.h"
#include "df/general_ref_type.h"
#include "df/item_body_component.h"
#include "df/item_type.h"
#include "df/item_statue_graphics_flag.h"
#include "df/descriptor_color.h"
#include "df/creature_raw.h"
#include "df/caste_raw.h"
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

// ItemKind = item_type + 1 through the supported DF 53.x item types.
// Append future values to the schema before admitting them here.
static_assert(static_cast<int>(df::enums::item_type::BAR) == 0 && static_cast<int>(mir::ItemKind::Bar) == 1,
              "ItemKind anchor: Bar");
static_assert(static_cast<int>(df::enums::item_type::BRANCH) + 1 == static_cast<int>(mir::ItemKind::Branch),
              "ItemKind anchor: Branch");
static_assert(static_cast<int>(df::enums::item_type::BOLT_THROWER_PARTS) + 1 ==
                  static_cast<int>(mir::ItemKind::BoltThrowerParts),
              "ItemKind anchor: BoltThrowerParts (last in the schema)");

mir::ItemKind mapItemKind(df::item_type t) {
    const int v = static_cast<int>(t);
    if (v < 0 || v > static_cast<int>(df::enums::item_type::BOLT_THROWER_PARTS)) return mir::ItemKind::Unknown;
    return static_cast<mir::ItemKind>(v + 1);
}

// ---- shadows ----

struct StatueRec {
    int8_t quality=-1;
    mir::ArtSubject subject=mir::ArtSubject::Unknown;
    const std::string* raw=nullptr;
    const std::string* caste=nullptr;
    mir::ArtEvent event=mir::ArtEvent::Unknown;
    friend bool operator==(const StatueRec&,const StatueRec&)=default;
};

StatueRec statueFacts(df::item* item) {
    StatueRec result;
    if (!item || item->getType()!=df::item_type::STATUE) return result;
    result.quality=static_cast<int8_t>(item->flags.bits.artifact ? 6 : item->getQuality());
    const auto* packed=item->get_art_graphics_type_ptr();
    if (!packed) return result;
    // The native item stores its semantic depiction as the low 31 bits of
    // this documented union: subject, race/shape/event index and caste.
    // Resolve IDs to raw tokens here; no texpos or native viewport is read.
    const df::item_statue_graphics_flag depiction(static_cast<uint32_t>(*packed));
    const int subject=static_cast<int>(depiction.bits.overall);
    if (subject<0 || subject>5) return result;
    result.subject=static_cast<mir::ArtSubject>(subject+1);
    const int index=static_cast<int>(depiction.bits.index_1);
    if (result.subject==mir::ArtSubject::Creature && index>=0 && size_t(index)<world->raws.creatures.all.size()) {
        const auto* raw=world->raws.creatures.all[index];
        result.raw=&raw->creature_id;
        const int caste=static_cast<int>(depiction.bits.index_2);
        if (caste>=0 && size_t(caste)<raw->caste.size()) result.caste=&raw->caste[caste]->caste_id;
    } else if (result.subject==mir::ArtSubject::Event && index>=0 && index<=8)
        result.event=static_cast<mir::ArtEvent>(index+1);
    return result;
}

flatbuffers::Offset<mir::StatueFacts> writeStatue(flatbuffers::FlatBufferBuilder& fbb,const StatueRec& s) {
    if (s.quality<0 && s.subject==mir::ArtSubject::Unknown) return 0;
    return mir::CreateStatueFactsDirect(fbb,s.quality,s.subject,s.raw ? s.raw->c_str() : nullptr,
        s.caste ? s.caste->c_str() : nullptr,s.event);
}

flatbuffers::Offset<mir::BeddingFacts> writeBedding(flatbuffers::FlatBufferBuilder& fbb,const df3d_bed::Facts& b) {
    if (b.sheet<0 || b.pillow<0) return 0;
    return mir::CreateBeddingFactsDirect(fbb,b.sheet,b.pillow,
        b.baseColor.empty() ? nullptr : b.baseColor.c_str(),
        b.sheetColor.empty() ? nullptr : b.sheetColor.c_str());
}

struct BuildingRec {
    uint8_t kind = 0;
    uint8_t stage = 0;
    uint8_t flags = 0;
    uint16_t subtype = mir::kNoSubtype;
    uint16_t material = 0xFFFF;
    int32_t x1 = 0, y1 = 0, x2 = 0, y2 = 0, z = 0, cx = 0, cy = 0;
    const std::string* custom = nullptr;  // building_def::code (DF memory, stable for the session)
    std::vector<uint8_t> extents;          // empty = whole rectangle
    StatueRec statue;
    df3d_bed::Facts bedding;
    int8_t pumpDirection=-1, pumpRunning=-1;
  int8_t rollerDirection=-1;
  int16_t rollerMachinePosition=-129;
  int16_t waterwheelMachinePosition=-129;
  int8_t windmillOrientX=-2, windmillOrientY=-2;
  int16_t windmillRotation=-129;
  int16_t gearAxleMachinePosition=-129;
  int8_t horizontalAxleVertical=-1;
  int8_t slabEngraving=-2;
  int8_t verticalBarsConnections=-1;
  int8_t wellChainIsMetal=-1;
  std::string materialSolidColor;
  int32_t constructionItemId=-1;
  std::string constructionItemSolidColor;
  int32_t containedItemCount=-1;
  std::string constructionToolRaw;
  int32_t constructionStage = -1;
  int8_t siegeFacing = -1;
  int16_t siegeFireTimer = -129;
  int16_t trapState = -129;
  int32_t trapReadyTimeout = -32769;
  int32_t trapFillTimer = -32769;
  int16_t trapTriggerFlags = -1;
  int32_t weaponCount = -1;
  int8_t weaponRetracted = -1;
  std::string constructionWeaponRaw;
  int8_t instrumentFamily=-1, instrumentPlaced=-1;
    int8_t constructionItemIsLog=-1;
    uint16_t constructionItemMaterial=0xffff;
    int8_t bridgeDirection=-2;
    uint8_t bridgeFlags=0;
};

bool sameRec(const BuildingRec& a, const BuildingRec& b) {
    return a.kind == b.kind && a.stage == b.stage && a.flags == b.flags && a.subtype == b.subtype &&
           a.material == b.material && a.x1 == b.x1 && a.y1 == b.y1 && a.x2 == b.x2 && a.y2 == b.y2 &&
           a.z == b.z && a.cx == b.cx && a.cy == b.cy && a.custom == b.custom && a.extents == b.extents && a.statue==b.statue && a.bedding==b.bedding && a.bridgeDirection==b.bridgeDirection && a.bridgeFlags==b.bridgeFlags && a.pumpDirection==b.pumpDirection && a.pumpRunning==b.pumpRunning && a.constructionItemIsLog==b.constructionItemIsLog && a.constructionItemMaterial==b.constructionItemMaterial && a.rollerDirection==b.rollerDirection && a.rollerMachinePosition==b.rollerMachinePosition && a.waterwheelMachinePosition==b.waterwheelMachinePosition && a.windmillOrientX==b.windmillOrientX && a.windmillOrientY==b.windmillOrientY && a.windmillRotation==b.windmillRotation && a.gearAxleMachinePosition==b.gearAxleMachinePosition && a.horizontalAxleVertical==b.horizontalAxleVertical && a.slabEngraving==b.slabEngraving && a.verticalBarsConnections==b.verticalBarsConnections && a.wellChainIsMetal==b.wellChainIsMetal && a.materialSolidColor==b.materialSolidColor && a.constructionItemId==b.constructionItemId && a.constructionItemSolidColor==b.constructionItemSolidColor && a.containedItemCount==b.containedItemCount && a.constructionToolRaw==b.constructionToolRaw && a.constructionStage==b.constructionStage && a.siegeFacing==b.siegeFacing && a.siegeFireTimer==b.siegeFireTimer && a.trapState==b.trapState && a.trapReadyTimeout==b.trapReadyTimeout && a.trapFillTimer==b.trapFillTimer && a.trapTriggerFlags==b.trapTriggerFlags && a.weaponCount==b.weaponCount && a.weaponRetracted==b.weaponRetracted && a.constructionWeaponRaw==b.constructionWeaponRaw && a.instrumentFamily==b.instrumentFamily && a.instrumentPlaced==b.instrumentPlaced;
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
    uint32_t containedCount = UINT32_MAX;
    mir::ItemKind containedKind = mir::ItemKind::Unknown;
    uint16_t containedMaterial = 0xFFFF;
    const std::string* containedSubtypeRaw = nullptr;
    const std::string* containedColor = nullptr;
    StatueRec statue;
    df3d_bed::Facts bedding;
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
    rec.materialSolidColor.clear();
    if(type==df::building_type::WindowGlass || type==df::building_type::Bridge || type==df::building_type::Armorstand || type==df::building_type::Weaponrack) {
        MaterialInfo material(b->mat_type,b->mat_index);
        if(material.isValid() && material.material) {
            const int color=material.material->state_color[0];
            const auto& colors=world->raws.descriptors.colors;
            if(color>=0 && size_t(color)<colors.size() && colors[color] && colors[color]->id.size()<=128)
                rec.materialSolidColor=colors[color]->id;
        }
    }
    rec.instrumentFamily=-1;rec.instrumentPlaced=-1;rec.slabEngraving=-2;
    rec.verticalBarsConnections=type==df::building_type::BarsVertical ? int8_t(df3d_construction::verticalBarsConnections(b->centerx,b->centery,b->z)) : -1;
    rec.wellChainIsMetal=-1;
    if(type==df::building_type::Well) {
        rec.wellChainIsMetal=0;
        for(const auto* entry:static_cast<df::building_actual*>(b)->contained_items) {
            if(!entry || !entry->item || entry->item->getType()!=df::item_type::CHAIN)continue;
            MaterialInfo material(entry->item->getActualMaterial(),entry->item->getActualMaterialIndex());
            if(!material.isValid() || !material.material)rec.wellChainIsMetal=-1;
            else if(material.material->flags.is_set(df::material_flags::IS_METAL)){rec.wellChainIsMetal=1;break;}
        }
    }
    rec.constructionToolRaw.clear();
    if(type==df::building_type::Bookcase || type==df::building_type::DisplayFurniture || type==df::building_type::OfferingPlace || type==df::building_type::NestBox || type==df::building_type::Hive) {
        df::item* tool=nullptr;
        if(b->getBuildStage()<b->getMaxBuildStage()) {
            for(const auto* job:b->jobs)if(job && job->job_type==df::job_type::ConstructBuilding) {
                for(const auto* ref:job->items)if(ref && ref->item && ref->item->getType()==df::item_type::TOOL){tool=ref->item;break;}
                if(tool)break;
            }
        } else {
            const auto& items=static_cast<df::building_actual*>(b)->contained_items;
            if(!items.empty() && items.front())tool=items.front()->item;
        }
        if(tool && tool->getType()==df::item_type::TOOL) {
            const auto subtype=tool->getSubtype();const auto& raws=world->raws.itemdefs.tools;
            if(subtype>=0 && size_t(subtype)<raws.size() && raws[subtype] && raws[subtype]->id.size()<=128)rec.constructionToolRaw=raws[subtype]->id;
        }
    }
    rec.siegeFacing=-1;rec.siegeFireTimer=-129;
    if(type==df::building_type::SiegeEngine) {
        const auto* siege=static_cast<const df::building_siegeenginest*>(b);
        const int facing=static_cast<int>(siege->facing);
        if(facing>=0 && facing<8)rec.siegeFacing=int8_t(facing);
        rec.siegeFireTimer=siege->fire_timer;
    }
    const bool mechanismTrap=type==df::building_type::Trap && b->getSubtype()>=0 && b->getSubtype()<=3;
    const bool weaponBuilding=type==df::building_type::Weapon || (type==df::building_type::Trap && b->getSubtype()==4);
    rec.weaponCount=-1;rec.weaponRetracted=-1;rec.constructionWeaponRaw.clear();
    df::item* weaponComponent=nullptr;
    if(weaponBuilding) {
        rec.weaponCount=0;
        for(const auto* held:static_cast<const df::building_actual*>(b)->contained_items) {
            if(!held || !held->item)continue;
            const auto itemType=held->item->getType();
            if(itemType!=df::item_type::WEAPON && itemType!=df::item_type::TRAPCOMP)continue;
            if(!weaponComponent)weaponComponent=held->item;
            if(rec.weaponCount<INT32_MAX)++rec.weaponCount;
        }
        if(type==df::building_type::Weapon)rec.weaponRetracted=static_cast<const df::building_weaponst*>(b)->gate_flags.bits.retracted?1:0;
        if(weaponComponent) {
            const int subtype=weaponComponent->getSubtype();
            if(weaponComponent->getType()==df::item_type::WEAPON) {
                const auto& defs=world->raws.itemdefs.weapons;
                if(subtype>=0 && size_t(subtype)<defs.size() && defs[subtype] && defs[subtype]->id.size()<=128)rec.constructionWeaponRaw=defs[subtype]->id;
            } else {
                const auto& defs=world->raws.itemdefs.trapcomps;
                if(subtype>=0 && size_t(subtype)<defs.size() && defs[subtype] && defs[subtype]->id.size()<=128)rec.constructionWeaponRaw=defs[subtype]->id;
            }
        }
    }
    rec.trapState=-129;rec.trapReadyTimeout=-32769;rec.trapFillTimer=-32769;rec.trapTriggerFlags=-1;
    if(mechanismTrap) {
        const auto* trap=static_cast<const df::building_trapst*>(b);
        rec.trapState=trap->state;rec.trapReadyTimeout=trap->ready_timeout;
        rec.trapFillTimer=trap->fill_timer;rec.trapTriggerFlags=int16_t(trap->plate_info.flags.whole & 63);
    }
    if(type==df::building_type::Trap && b->getSubtype()==4)rec.trapState=static_cast<const df::building_trapst*>(b)->state;
    rec.containedItemCount=-1;
    if(mechanismTrap || weaponBuilding || type==df::building_type::SiegeEngine || type==df::building_type::Coffin || type==df::building_type::Armorstand || type==df::building_type::Weaponrack) {
        const auto count=static_cast<df::building_actual*>(b)->contained_items.size();
        if(count<=INT32_MAX)rec.containedItemCount=int32_t(count);
    }
    rec.constructionItemIsLog=-1;rec.constructionItemMaterial=0xffff;rec.constructionItemId=-1;rec.constructionItemSolidColor.clear();
    const bool gridComponent = type==df::building_type::Workshop || type==df::building_type::Furnace || type==df::building_type::TradeDepot;
    if(mechanismTrap || weaponBuilding || gridComponent || type==df::building_type::SiegeEngine || type==df::building_type::Door || type==df::building_type::Hatch || type==df::building_type::Chair || type==df::building_type::Table || type==df::building_type::Box || type==df::building_type::Cabinet || type==df::building_type::Coffin || type==df::building_type::Cage || type==df::building_type::AnimalTrap || type==df::building_type::Bookcase || type==df::building_type::DisplayFurniture || type==df::building_type::OfferingPlace || type==df::building_type::NestBox || type==df::building_type::Bed || type==df::building_type::BarsFloor || type==df::building_type::Support || type==df::building_type::BarsVertical || type==df::building_type::Slab || type==df::building_type::Instrument || type==df::building_type::Rollers || type==df::building_type::WaterWheel || type==df::building_type::Windmill || type==df::building_type::GearAssembly || type==df::building_type::AxleHorizontal || type==df::building_type::AxleVertical || (type==df::building_type::Trap && b->getSubtype()==5)) {
        // Native Track Stop, Roller, Water Wheel, Windmill, Gear, Axle, Slab, Vertical Bars and Instrument draw uses entry zero, without filtering use_mode.
        const auto& items=static_cast<df::building_actual*>(b)->contained_items;
        df::item* component = !items.empty() && items.front() ? items.front()->item : nullptr;
        // Layout bases prefer the first permanent construction component,
        // falling back to entry zero when the building only has temporary contents.
        if(gridComponent) for(const auto* held : items) {
            if(held && held->item && held->use_mode==df::building_item_role_type::PERM) {
                component=held->item; break;
            }
        }
        if(mechanismTrap) {
            component=nullptr;
            for(const auto* held:items) if(held && held->item && held->item->getType()==df::item_type::TRAPPARTS) {
                component=held->item;break;
            }
        }
        if(weaponBuilding)component=weaponComponent;
        if(component) {
            auto* item=component;
            rec.constructionItemIsLog=item->getType()==df::item_type::WOOD ? 1 : 0;
            rec.constructionItemMaterial=gm(item->getActualMaterial(),item->getActualMaterialIndex());
            if(mechanismTrap || weaponBuilding || gridComponent || type==df::building_type::SiegeEngine || type==df::building_type::Door || type==df::building_type::Hatch || type==df::building_type::Chair || type==df::building_type::Table || type==df::building_type::Box || type==df::building_type::Cabinet || type==df::building_type::Coffin || type==df::building_type::Cage || type==df::building_type::AnimalTrap || type==df::building_type::Bookcase || type==df::building_type::DisplayFurniture || type==df::building_type::OfferingPlace || type==df::building_type::NestBox) {
                rec.constructionItemId=item->id;
                MaterialInfo material(item->getActualMaterial(),item->getActualMaterialIndex());
                if(material.isValid() && material.material) {
                    const int color=material.material->state_color[0];
                    const auto& colors=world->raws.descriptors.colors;
                    if(color>=0 && size_t(color)<colors.size() && colors[color] && colors[color]->id.size()<=128)
                        rec.constructionItemSolidColor=colors[color]->id;
                }
            }
            if(type==df::building_type::Slab && item->getType()==df::item_type::SLAB) {
                const int engraving=static_cast<df::item_slabst*>(item)->engraving_type;
                if(engraving>=-1 && engraving<=26)rec.slabEngraving=int8_t(engraving);
            }
            if(type==df::building_type::Instrument && item->getType()==df::item_type::INSTRUMENT) {
                const int subtype=item->getSubtype();
                const auto& definitions=world->raws.itemdefs.instruments;
                if(subtype>=0 && size_t(subtype)<definitions.size() && definitions[subtype]) {
                    const auto* definition=definitions[subtype];
                    switch(definition->music_skill) {
                    case df::job_skill::PLAY_KEYBOARD_INSTRUMENT: rec.instrumentFamily=0;break;
                    case df::job_skill::PLAY_STRINGED_INSTRUMENT: rec.instrumentFamily=1;break;
                    case df::job_skill::PLAY_WIND_INSTRUMENT: rec.instrumentFamily=2;break;
                    case df::job_skill::PLAY_PERCUSSION_INSTRUMENT: rec.instrumentFamily=3;break;
                    default: break;
                    }
                    if(rec.instrumentFamily!=-1)
                        rec.instrumentPlaced=definition->flags.is_set(df::instrument_flags::PLACED_AS_BUILDING)?1:0;
                }
            }
        }
    }
    rec.gearAxleMachinePosition=-129;rec.horizontalAxleVertical=-1;
    if(type==df::building_type::GearAssembly || type==df::building_type::AxleHorizontal || type==df::building_type::AxleVertical) {
        const auto* info=b->getMachineInfo();
        const auto* machine=info ? df::machine::find(info->machine_id) : nullptr;
        rec.gearAxleMachinePosition=machine ? int16_t(machine->visual_phase) : 0;
        if(type==df::building_type::AxleHorizontal)rec.horizontalAxleVertical=static_cast<df::building_axle_horizontalst*>(b)->is_vertical ? 1:0;
    }
    rec.windmillOrientX=-2;rec.windmillOrientY=-2;rec.windmillRotation=-129;
    if(type==df::building_type::Windmill) {
        const auto* windmill=static_cast<df::building_windmillst*>(b);
        if(windmill->orient_x>=-1 && windmill->orient_x<=1 && windmill->orient_y>=-1 && windmill->orient_y<=1) {
            rec.windmillOrientX=int8_t(windmill->orient_x);rec.windmillOrientY=int8_t(windmill->orient_y);
        }
        rec.windmillRotation=windmill->rotation;
    }
    rec.waterwheelMachinePosition=-129;
    if(type==df::building_type::WaterWheel) {
        const auto* wheel=static_cast<df::building_water_wheelst*>(b);
        const auto* machine=df::machine::find(wheel->machine.machine_id);
        rec.waterwheelMachinePosition=machine ? int16_t(machine->visual_phase) : 0;
    }
    rec.rollerDirection=-1;rec.rollerMachinePosition=-129;
    if(type==df::building_type::Rollers) {
        const auto* roller=static_cast<df::building_rollersst*>(b);
        const int direction=roller->direction;
        if(direction>=0 && direction<=3) rec.rollerDirection=int8_t(direction);
        // Simulation-owned position; absent machinery uses zero in native draw.
        const auto* machine=df::machine::find(roller->machine.machine_id);
        rec.rollerMachinePosition=machine ? int16_t(machine->visual_phase) : 0;
    }
    rec.pumpDirection=-1;rec.pumpRunning=-1;
    if(type==df::building_type::ScrewPump) {
        const int direction=static_cast<df::building_screw_pumpst*>(b)->direction;
        if(direction>=0 && direction<=3) rec.pumpDirection=int8_t(direction);
        rec.pumpRunning=static_cast<df::building_screw_pumpst*>(b)->pump_energy!=0 ? 1 : 0;
    }
    rec.bridgeDirection=-2;rec.bridgeFlags=0;
    if(type==df::building_type::Bridge) {
        const auto* bridge=static_cast<df::building_bridgest*>(b);
        const int direction=bridge->direction;
        if(direction>=-1 && direction<=3) {
            rec.bridgeDirection=int8_t(direction);rec.bridgeFlags=uint8_t(bridge->gate_flags.whole & 15);
        }
    }
    rec.bedding={};
    if (type==df::building_type::Bed) {
        for (const auto* contained : static_cast<df::building_actual*>(b)->contained_items)
            if (contained && contained->item && contained->item->getType()==df::item_type::BED) {
                rec.bedding=df3d_bed::facts(contained->item); break;
            }
    }
    rec.statue={};
    if (type==df::building_type::Statue) {
        for (const auto* contained : static_cast<df::building_actual*>(b)->contained_items)
            if (contained && contained->item && contained->item->getType()==df::item_type::STATUE) {
                rec.statue=statueFacts(contained->item); break;
            }
    }

    rec.constructionStage = b->getBuildStage();
    if (b->flags.bits.exists) rec.stage = static_cast<uint8_t>(mir::BuildingStage::Complete);
    else if (rec.constructionStage > 0) rec.stage = static_cast<uint8_t>(mir::BuildingStage::InProgress);
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

// Direct item contents are semantic facts. No native viewport or graphics
// cache participates. Rechecking on ordinary visits catches fills/empties and
// content replacements even while the container itself does not move.
bool updateContents(df::item* it, ItemShadow& sh, GridMaterialFn gm) {
    const auto type=it->getType();
    if (type!=df::item_type::BIN && type!=df::item_type::BARREL && type!=df::item_type::BAG &&
        type!=df::item_type::BUCKET && type!=df::item_type::TOOL) return false;
    uint32_t count=0;
    df::item* first=nullptr;
    for (auto* ref : it->general_refs) if (ref && ref->getType()==df::general_ref_type::CONTAINS_ITEM) {
        if (auto* child=ref->getItem()) { if (!first) first=child; ++count; }
    }
    const auto kind=first ? mapItemKind(first->getType()) : mir::ItemKind::Unknown;
    const uint16_t material=first ? gm(first->getMaterial(),first->getMaterialIndex()) : 0xFFFF;
    const df::itemdef* def=first ? Items::getSubtypeDef(first->getType(),first->getSubtype()) : nullptr;
    const std::string* raw=def ? &def->id : nullptr;
    const auto* descriptor=first ? df::descriptor_color::find(first->getColorWhetherDyedOrNot()) : nullptr;
    const std::string* color=descriptor ? &descriptor->id : nullptr;
    const bool changed=sh.containedColor!=color || sh.containedCount!=count || sh.containedKind!=kind ||
        sh.containedMaterial!=material || sh.containedSubtypeRaw!=raw;
    sh.containedColor=color;
    sh.containedCount=count; sh.containedKind=kind; sh.containedMaterial=material; sh.containedSubtypeRaw=raw;
    return changed;
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
        bool changed = updateContents(it,sh,gm);
        const auto bedding=df3d_bed::facts(it);
        if (sh.bedding!=bedding) { sh.bedding=bedding; changed=true; }
        const auto statue=statueFacts(it);
        if (sh.statue!=statue) { sh.statue=statue; changed=true; }
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
    updateContents(it,sh,gm);
    sh.statue=statueFacts(it);
    sh.bedding=df3d_bed::facts(it);
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
        const uint16_t constructionMat = r.constructionItemMaterial == 0xFFFF
            ? mir::kNoMaterial : localMaterial(fbb,r.constructionItemMaterial);
        s.bOffsets.push_back(mir::CreateBuilding(
            fbb, static_cast<uint32_t>(sh.id), static_cast<mir::BuildingKind>(r.kind), r.subtype, custom,
            r.x1, r.y1, r.x2, r.y2, r.z, r.cx, r.cy, extents, mat, static_cast<mir::BuildingStage>(r.stage),
            static_cast<mir::BuildingFlags>(r.flags),writeStatue(fbb,r.statue),writeBedding(fbb,r.bedding),
            r.bridgeDirection==-2 ? 0 : mir::CreateBridgeState(fbb,r.bridgeDirection,
                (r.bridgeFlags&1)!=0,(r.bridgeFlags&2)!=0,(r.bridgeFlags&4)!=0,(r.bridgeFlags&8)!=0),r.pumpDirection,r.pumpRunning,r.constructionItemIsLog,constructionMat,r.rollerDirection,r.rollerMachinePosition,r.instrumentFamily,r.instrumentPlaced,r.waterwheelMachinePosition,r.windmillOrientX,r.windmillOrientY,r.windmillRotation,r.gearAxleMachinePosition,r.horizontalAxleVertical,r.slabEngraving,r.verticalBarsConnections,r.wellChainIsMetal,r.materialSolidColor.empty()?0:fbb.CreateString(r.materialSolidColor),r.constructionItemId,r.constructionItemSolidColor.empty()?0:fbb.CreateString(r.constructionItemSolidColor),r.containedItemCount,r.constructionToolRaw.empty()?0:fbb.CreateString(r.constructionToolRaw),r.constructionStage,r.siegeFacing,r.siegeFireTimer,r.trapState,r.trapReadyTimeout,r.trapFillTimer,r.trapTriggerFlags,r.weaponCount,r.weaponRetracted,r.constructionWeaponRaw.empty()?0:fbb.CreateString(r.constructionWeaponRaw)));
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
                                                static_cast<mir::CorpseFlags>(sh.corpseFlags), sh.corpseUnitId,
                                                sh.containedCount, sh.containedKind,
                                                sh.containedMaterial == 0xFFFF ? mir::kNoMaterial : localMaterial(fbb,sh.containedMaterial),
                                                sh.containedSubtypeRaw ? fbb.CreateString(*sh.containedSubtypeRaw) : 0,
                                                writeStatue(fbb,sh.statue),
                                                sh.containedColor ? fbb.CreateString(*sh.containedColor) : 0,writeBedding(fbb,sh.bedding)));
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
