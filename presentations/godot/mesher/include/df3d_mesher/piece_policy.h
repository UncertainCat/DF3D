#pragma once
#include "wm/types.h"
namespace df3d::mesher {
// Loose bodies, body fragments and liquid globs rest on the ground rather
// than inheriting the camera-facing pose used by living actors and other items.
inline bool itemLiesOnGround(wm::ItemKind kind) {
    using I = wm::ItemKind;
    return kind == I::Corpse || kind == I::CorpsePiece || kind == I::Remains ||
           kind == I::Glob || kind == I::LiquidMisc;
}
// Layer-4 choice: installations/decals keep their map footprint; movable
// furniture gets silhouette volume. Explicit allow-list keeps new kinds flat.
// Cross faces use the axis along the plane, never its constant axis.
inline float crossPlaneU(float normalX, float localX, float localY) {
    return normalX > 0.5f || normalX < -0.5f ? localY : localX;
}
// Semantic planes stay stable under arrival/removal of other installations.
// Stockpile/zone overlays cannot become coplanar with door/bridge artwork.
inline float installationArtBottom(wm::BuildingKind kind) {
    if(kind==wm::BuildingKind::Stockpile)return .002f;
    if(kind==wm::BuildingKind::Civzone)return .003f;
    return .004f;
}
inline bool isFurniturePiece(wm::BuildingKind kind) {
    using B = wm::BuildingKind;
    switch (kind) {
        case B::Chair: case B::Bed: case B::Table: case B::Coffin:
        case B::Box: case B::Weaponrack: case B::Armorstand: case B::Cabinet:
        case B::Statue: case B::Well: case B::Cage: case B::Bookcase:
        case B::TractionBench: case B::Slab: case B::NestBox: case B::Hive:
        case B::Instrument: case B::DisplayFurniture: case B::OfferingPlace:
        case B::AnimalTrap: case B::ArcheryTarget:
        case B::Workshop: case B::Furnace: case B::TradeDepot: return true;
        default: return false;
    }
}
}
