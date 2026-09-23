#include "df3d_world.h"
#include <algorithm>
#include <string>

using namespace godot;
namespace df3d_godot {
namespace {
bool knownVisible(const wm::WorldModel& model, wm::TilePos p) {
    const auto tile=model.tileAt(p);
    return tile && !(tile->flags & wm::kTileHidden);
}
bool selectable(const wm::Building& b) {
    return b.kind!=wm::BuildingKind::Stockpile && b.kind!=wm::BuildingKind::Civzone;
}
String materialText(const wm::WorldModel& model, wm::MaterialId material) {
    const std::string name(model.materialName(material));
    return String::utf8(name.c_str());
}
}
Dictionary Df3dWorld::inspect_entity(int64_t kind, int64_t id) const {
    Dictionary row;
    if(id<0 || ((kind==2 || kind==3) && id>UINT32_MAX)) return row;
    if(kind==1) {
        const auto position=unit_tile(id);
        if(position.x<0) return row;
        const auto* species=source_.model().unitSpecies(static_cast<wm::UnitId>(id));
        if(!species) return row;
        row["tile"]=position;
        row["species"]=String::utf8(species->c_str());
        row["name"]=String::utf8(species->c_str());
        row["summary_available"]=false;
        // Summary age is explicit: these resident caches are periodic,
        // independently collected observations, not live entity details.
        auto summary=residentInfo_.cached(wm::ResidentInfoDemand::Residents);
        const auto details=residentInfo_.cached(wm::ResidentInfoDemand::WorkDetails);
        if(details && (!summary || details->generation>summary->generation)) summary=details;
        if(summary && sessionClient_ && sessionClient_->state().fortressValid &&
           summary->worldEpoch==sessionClient_->state().fortressEpoch) {
            const auto found=std::find_if(summary->citizens.begin(),summary->citizens.end(),
                [id](const auto& u){return u.id==id;});
            if(found!=summary->citizens.end()) {
                row["name"]=String::utf8(found->name.c_str());
                row["job"]=String::utf8(found->job.c_str());
                row["profession"]=String::utf8(found->profession.c_str());
                row["age"]=found->age;row["stress"]=found->stress;row["has_stress"]=found->hasStress;
                row["summary_available"]=true;
                row["summary_generation"]=int64_t(summary->generation);
                row["summary_capture_completed_ms"]=int64_t(summary->captureCompletedMs);
            }
        }
        // Units have no per-entity semantic revision here; use model tick and
        // compare tile and summary_generation too (paused summaries can change).
        row["version"]=int64_t(source_.model().latestTick());
        row["tick"]=int64_t(source_.model().latestTick());
    } else if(kind==2) {
        const auto* item=source_.model().item(static_cast<wm::ItemId>(id));
        if(!item || !knownVisible(source_.model(),item->pos)) return row;
        row["tile"]=Vector3i(item->pos.x,item->pos.y,item->pos.z);
        row["name"]=String(wm::itemKindName(item->kind));
        row["material"]=materialText(source_.model(),item->material);
        row["item_kind"]=int(item->kind);row["subtype"]=item->subtype;
        row["subtype_raw"]=String::utf8(item->subtypeRaw.c_str());
        row["stack"]=int64_t(item->stack);row["flags"]=item->flags;
        row["forbidden"]=bool(item->flags & wm::kItemForbidden);
        row["dump"]=bool(item->flags & wm::kItemDump);row["melt"]=bool(item->flags & wm::kItemMelt);
        row["on_fire"]=bool(item->flags & wm::kItemOnFire);row["rotten"]=bool(item->flags & wm::kItemRotten);
        row["artifact"]=bool(item->flags & wm::kItemArtifact);
        row["version"]=int64_t(item->version);row["tick"]=int64_t(item->tick);
    } else if(kind==3) {
        const auto* b=source_.model().building(static_cast<wm::BuildingId>(id));
        if(!b || !selectable(*b) || !knownVisible(source_.model(),{b->centerX,b->centerY,b->z})) return row;
        row["tile"]=Vector3i(b->centerX,b->centerY,b->z);
        row["name"]=String(wm::buildingKindName(b->kind));
        row["material"]=materialText(source_.model(),b->material);
        row["building_kind"]=int(b->kind);row["subtype"]=b->subtype;
        row["custom"]=String::utf8(b->custom.c_str());
        row["stage"]=int(b->stage);row["flags"]=b->flags;
        row["complete"]=b->stage==wm::BuildingStage::Complete;
        row["forbidden"]=bool(b->flags & wm::kBuildingForbidden);
        row["room_assigned"]=bool(b->flags & wm::kBuildingRoomAssigned);
        row["footprint_min"]=Vector3i(b->x1,b->y1,b->z);
        row["footprint_max"]=Vector3i(b->x2,b->y2,b->z);
        row["version"]=int64_t(b->version);row["tick"]=int64_t(b->tick);
    } else return row;
    row["kind"]=kind;row["id"]=id;row["origin"]=row["tile"];
    return row;
}
Array Df3dWorld::inspect_tile(const Vector3i& tile) const {
    Array rows;
    const wm::TilePos p{tile.x,tile.y,tile.z};
    if(!knownVisible(source_.model(),p)) return rows;
    const auto add=[&](int kind,int64_t id) {
        const auto row=inspect_entity(kind,id);
        if(!row.is_empty()) rows.push_back(row);
    };
    // Depth occupants are sorted by unit ID and reflect current model tiles.
    // This click-only query does not scan or copy the full WorldModel.
    for(const auto& [id,x,y,z]:depthUnitContents_)
        if(x==tile.x && y==tile.y && z==tile.z) add(1,id);
    for(const auto* b:source_.model().buildingsInRect(tile.x,tile.y,tile.x,tile.y,tile.z))
        if(selectable(*b) && b->occupies(tile.x,tile.y)) add(3,b->id);
    for(const auto* item:source_.model().itemsAtTile(p)) add(2,item->id);
    return rows;
}
} // namespace df3d_godot
