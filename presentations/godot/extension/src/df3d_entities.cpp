#include "immutable_material.h"
#include "submission_uploads.h"
#include "submission_details.h"
// Df3dWorld: buildings and map items.
//
// Buildings retain ID-owned, budgeted meshes. Artwork layers for each tile are
// composited before its single surface/volume is generated. Static depth layout
// separates actual furniture contours, item piles and overlapping flat decals.
// Planned furniture keeps its source art with translucent ghost tint.
//
// Item payload updates live in df3d_items.cpp; lazy allocation is owned by
// df3d_layout.cpp. Geometry here owns fixed installation bands, independent of moving occupants.
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <map>
#include <set>
#include <string>

#include "df3d_assets/classic_glyphs.h"
#include "df3d_assets/resolver.h"
#include "df3d_mesher/block_mesher.h"
#include "df3d_mesher/piece_policy.h"
#include "df3d_mesher/item_stack.h"
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include "df3d_world.h"
#include "entity_color.h"

namespace df3d_godot {

using godot::Array;
using godot::ArrayMesh;
using godot::Color;
using godot::Mesh;
using godot::MeshInstance3D;
using godot::Node3D;
using godot::PackedColorArray;
using godot::PackedInt32Array;
using godot::PackedVector2Array;
using godot::PackedVector3Array;
using godot::Ref;
using godot::String;
using godot::Vector2;
using godot::Vector3;

namespace assets = df3d::assets;
namespace mesher = df3d::mesher;

namespace {

bool isFloorHalfPlannedBuilding(wm::BuildingKind kind, uint16_t subtype) {
    return kind==wm::BuildingKind::ScrewPump || kind==wm::BuildingKind::Instrument ||
           kind==wm::BuildingKind::Rollers || kind==wm::BuildingKind::WaterWheel ||
           kind==wm::BuildingKind::Windmill || (kind==wm::BuildingKind::SiegeEngine && subtype==2) || (kind==wm::BuildingKind::Trap && subtype==5);
}

bool isMaterialPlannedFurniture(wm::BuildingKind kind) {
    return kind==wm::BuildingKind::Armorstand || kind==wm::BuildingKind::Weaponrack;
}

bool isRawPlannedFurniture(wm::BuildingKind kind) {
    return kind==wm::BuildingKind::ArcheryTarget || kind==wm::BuildingKind::Bed || kind==wm::BuildingKind::Bookcase ||
           kind==wm::BuildingKind::DisplayFurniture || kind==wm::BuildingKind::OfferingPlace ||
           kind==wm::BuildingKind::Hive || kind==wm::BuildingKind::NestBox || kind==wm::BuildingKind::TractionBench ||
           kind==wm::BuildingKind::Coffin || kind==wm::BuildingKind::Cage ||
           kind==wm::BuildingKind::Chain || kind==wm::BuildingKind::AnimalTrap ||
           kind==wm::BuildingKind::Door || kind==wm::BuildingKind::Hatch ||
           kind==wm::BuildingKind::GrateWall || kind==wm::BuildingKind::GrateFloor ||
           kind==wm::BuildingKind::Floodgate || kind==wm::BuildingKind::Chair ||
           kind==wm::BuildingKind::Table || kind==wm::BuildingKind::Box || kind==wm::BuildingKind::Cabinet;
}

struct QuadArrays {
    godot::Vector3 ground;
    PackedVector3Array vertices, normals;
    PackedColorArray colors;
    PackedVector2Array uvs;
    PackedInt32Array indices;
    godot::PackedFloat32Array tileCenters;
    void addCenter(float u,float v) {
        tileCenters.push_back(u);tileCenters.push_back(v);
        tileCenters.push_back(0);tileCenters.push_back(0);
    }
    void addCutoutVertices(const std::vector<mesher::CutoutVertex>& vs,int x,int y,float h,float thickness,
                          const Color& region,const Color& tint,float nativeLift=0.0f) {
        df3d::profiling::Scope profile("building.pack_vertices", nullptr, df3d::profiling::detailed());
        if (vs.empty()) return;
        const int base=vertices.size();
        const int indexBase=indices.size();
        const int count=int(vs.size());
        vertices.resize(base+count); normals.resize(base+count);
        uvs.resize(base+count); colors.resize(base+count); indices.resize(indexBase+count);
        tileCenters.resize((base+count)*4);
        // One allocation/write handle per stream, not five engine calls per
        // vertex. Acquire handles only after all resizes; none outlive this job.
        auto* vertexOut=vertices.ptrw()+base;
        auto* normalOut=normals.ptrw()+base;
        auto* uvOut=uvs.ptrw()+base;
        auto* colorOut=colors.ptrw()+base;
        auto* indexOut=indices.ptrw()+indexBase;
        auto* centerOut=tileCenters.ptrw()+base*4;
        for(int i=0;i<int(vs.size());++i) {
            const auto& v=vs[i];
            vertexOut[i]=Vector3(x+.5f+v.x,h+ground.y+ground.x*v.x+ground.z*v.z+v.y*thickness/mesher::kCutoutThickness,y+.5f+v.z);
            uvOut[i]=Vector2(region.r+v.u*region.b,region.g+v.v*region.a);
            colorOut[i]=tint;normalOut[i]=Vector3(0,1,0);indexOut[i]=base+i;
            centerOut[i*4]=region.r+region.b*.5f;centerOut[i*4+1]=region.g+region.a*.5f;
            centerOut[i*4+2]=nativeLift;centerOut[i*4+3]=0;
        }
    }
    // A flat quad over DF tile (x, y) at Godot height h, textured with the
    // uv rectangle (u0, v0, u1, v1): image-down = DF south (+y), as the
    // terrain tops map their tiles. Clockwise seen from above = Godot's
    // front face.
    void addCutout(const Ref<ArrayMesh>& mesh,int x,int y,float h,float thickness,const Color& tint,const Color& region) {
        if(mesh.is_null() || mesh->get_surface_count()==0)return;
        Array a=mesh->surface_get_arrays(0);
        PackedVector3Array vs=a[Mesh::ARRAY_VERTEX]; PackedVector2Array ts=a[Mesh::ARRAY_TEX_UV]; PackedColorArray cs=a[Mesh::ARRAY_COLOR];
        const int base=vertices.size();
        for(int i=0;i<vs.size();++i)addCenter(region.r+region.b*.5f,region.g+region.a*.5f);
        for(int i=0;i<vs.size();++i){vertices.push_back(Vector3(vs[i].x,ground.y+ground.x*vs[i].x+ground.z*vs[i].z+vs[i].y*thickness/mesher::kCutoutThickness,vs[i].z)+Vector3(x+.5f,h,y+.5f));uvs.push_back(ts[i]);colors.push_back(cs[i]*tint);normals.push_back(Vector3(0,1,0));indices.push_back(base+i);}
    }
    void add(int32_t x, int32_t y, float h, const Color& c, const float* uv, bool piece = false) {
        const int32_t base = static_cast<int32_t>(vertices.size());
        const float fx = static_cast<float>(x), fz = static_cast<float>(y);
        const Vector3 v[4] = {Vector3(fx, h, fz), Vector3(fx + 1, h, fz), Vector3(fx + 1, h, fz + 1),
                              Vector3(fx, h, fz + 1)};
        const Vector2 t[4] = {Vector2(uv[0], uv[1]), Vector2(uv[2], uv[1]), Vector2(uv[2], uv[3]),
                              Vector2(uv[0], uv[3])};
        for (int i = 0; i < 4; ++i) {
            auto point=v[i];point.y+=ground.y+ground.x*(point.x-fx-.5f)+ground.z*(point.z-fz-.5f);
            vertices.push_back(point);
            normals.push_back(Vector3(0, 1, 0));
            colors.push_back(c);
            uvs.push_back(t[i]);
            addCenter((uv[0]+uv[2])*.5f,(uv[1]+uv[3])*.5f);
        }
        for (int32_t i : {0, 1, 2, 0, 2, 3}) indices.push_back(base + i);
    }
};

}  // namespace

// --- roots and state ---

void Df3dWorld::set_zone_overlays_visible(bool visible) {
    if (zoneOverlaysVisible_ == visible) return;
    zoneOverlaysVisible_ = visible;
    for (auto& [id, built] : builtBuildings_)
        if (built.kind == wm::BuildingKind::Civzone && built.node)
            built.node->set_visible(visible);
}

void Df3dWorld::set_building_root(Node3D* root) {
    if (root == buildingRoot_) return;
    for (auto& [id, b] : builtBuildings_) freeBuilding(b);
    builtBuildings_.clear();
    clearBuildingLayers();
    if (ownBuildingRoot_ && buildingRoot_) {
        remove_child(buildingRoot_);
        godot::memdelete(buildingRoot_);
    }
    buildingRoot_ = root;
    ownBuildingRoot_ = false;
    enqueueBuildings();
}

Node3D* Df3dWorld::get_building_root() {
    if (!buildingRoot_) {
        buildingRoot_ = memnew(Node3D);
        buildingRoot_->set_name("Buildings");
        add_child(buildingRoot_);
        ownBuildingRoot_ = true;
    }
    return buildingRoot_;
}

void Df3dWorld::resetEntities() {
    projectileIds_.clear();projectilePositions_.clear();projectileDirections_.clear();
    buildingSubmissionReasons_.clear();
    presentationAppearanceVersion_ = UINT64_MAX;
    presentationArtHash_ = UINT64_MAX;
    resetSpriteCeilingCache();
    resetDoorOrientationCache();
    itemRenderGroups_.clear();
    itemRenderGroupRecords_.clear();
    itemRenderGroupsSeen_ = UINT64_MAX;
    buildingBatches_.clear();
    buildingPieceMaterials_.clear();
    buildingPumpMaterials_.clear();
    buildingMachineMaterials_.clear();machinePhasePages_.clear();machinePhaseSlots_.clear();
    machinePhaseFreeSlots_.clear();machinePhaseSources_.clear();
    buildingFootprintCache_.clear();
    buildingAlphaCache_.clear();
    buildingAlphaRecent_.clear();
    ++perfFootprintResets_;
    layoutScopeDirty_=true; tileLayouts_.clear(source_.model().sessionGeneration());
    layoutUnitTiles_.clear(); unitDepthById_.clear(); resetItemPayloads();
    layoutBuildingBlocks_.clear();layoutBuildingsByBlock_.clear();layoutViewDirty_=true;
    layoutBuildingChanges_.clear(); layoutItemChanges_.clear();
    unitCutoutPositions_.clear(); unitThicknesses_.clear(); unitDepthBottoms_.clear();
    unitVisualKeys_.clear();
    unitArtCache_.clear();++unitArtGeneration_;
    ++unitRenderRevision_;
    lastRenderedTick_ = UINT64_MAX;
    depthUnitContents_.clear();
    for (auto& [id, b] : builtBuildings_) freeBuilding(b);
    builtBuildings_.clear();
    clearBuildingLayers();
    buildingQueue_.clear();
    buildingQueued_.clear();
    buildingQueueHead_ = 0;
    buildingsDrawn_ = 0;
    buildingsUnresolved_ = 0;
    buildingsGlyph_ = 0;
    unresolvedBuildingKinds_.clear();
    itemLooks_.clear();
    unitGlyphLooks_.clear();
    itemsDirty_ = true;
    enqueueBuildings();
}

String Df3dWorld::entity_unresolved_summary() const {
    std::string s;
    for (const auto& [k, n] : unresolvedBuildingKinds_) s += (s.empty() ? "" : " ") + k + ":" + std::to_string(n);
    s += " | ";
    bool first = true;
    for (const auto& [k, n] : unresolvedItemKinds_) {
        s += (first ? "" : " ") + k + ":" + std::to_string(n);
        first = false;
    }
    return String(s.c_str());
}

bool Df3dWorld::tileVisible(wm::TilePos p) const {
    if (revealHidden_) return true;
    const std::optional<wm::TileState> t = source_.model().tileAt(p);
    return !t || !(t->flags & wm::kTileHidden);
}

// --- buildings ---
namespace {
bool isAxle(wm::BuildingKind kind) {return kind==wm::BuildingKind::AxleHorizontal || kind==wm::BuildingKind::AxleVertical;}
bool isTransmission(wm::BuildingKind kind) {return isAxle(kind) || kind==wm::BuildingKind::GearAssembly;}
}

uint32_t Df3dWorld::updateMachinePosition(const wm::Building& b) {
    auto it=machinePhaseSlots_.find(b.id);
    if(it==machinePhaseSlots_.end()) {
        if(machinePhaseFreeSlots_.empty()) {
            const uint32_t first=uint32_t(machinePhasePages_.size())*256;
            MachinePhasePage page;
            page.image=godot::Image::create(256,1,false,godot::Image::FORMAT_RF);
            page.image->fill(Color(-129,0,0,1));
            page.texture=godot::ImageTexture::create_from_image(page.image);
            machinePhasePages_.push_back(std::move(page));
            for(uint32_t i=256;i>0;--i)machinePhaseFreeSlots_.push_back(first+i-1);
        }
        const auto slot=machinePhaseFreeSlots_.back();machinePhaseFreeSlots_.pop_back();
        it=machinePhaseSlots_.emplace(b.id,slot).first;
    }
    auto& page=machinePhasePages_[it->second/256];const int x=it->second%256;
    int phase=b.kind==wm::BuildingKind::WaterWheel ? b.waterwheelMachinePosition : b.rollerMachinePosition;
    if(isTransmission(b.kind))phase=b.stage==wm::BuildingStage::Complete ? b.gearAxleMachinePosition : 0;
    if(b.kind==wm::BuildingKind::Windmill) {
        // Presentation payload: installed atlas orientation row and frame.
        static constexpr int rows[3][3]={{3,2,1},{4,0,0},{5,6,7}};
        const bool known=b.windmillOrientX>=-1 && b.windmillOrientX<=1 && b.windmillOrientY>=-1 && b.windmillOrientY<=1;
        const int row=known ? rows[b.windmillOrientX+1][b.windmillOrientY+1] : 0;
        phase=row*2+(b.stage==wm::BuildingStage::Complete && b.windmillRotation!=-129 && b.windmillRotation!=0 ? 1:0);
    }
    if(page.image->get_pixel(x,0).r!=float(phase)) {
        page.image->set_pixel(x,0,Color(float(phase),0,0,1));page.dirty=true;
    }
    return it->second;
}

void Df3dWorld::releaseMachinePosition(wm::BuildingId id) {
    const auto it=machinePhaseSlots_.find(id);if(it==machinePhaseSlots_.end())return;
    auto& page=machinePhasePages_[it->second/256];
    page.image->set_pixel(it->second%256,0,Color(-129,0,0,1));page.dirty=true;
    machinePhaseFreeSlots_.push_back(it->second);machinePhaseSlots_.erase(it);
}

void Df3dWorld::flushMachinePositions() {
    for(auto& page:machinePhasePages_)if(page.dirty) {
        page.texture->update(page.image);page.dirty=false;
    }
}

namespace {
bool sameMachineGeometry(const wm::Building& a,const wm::Building& b) {
    return a.kind==b.kind && a.subtype==b.subtype && a.custom==b.custom &&
        a.x1==b.x1 && a.x2==b.x2 && a.y1==b.y1 && a.y2==b.y2 && a.z==b.z &&
        a.centerX==b.centerX && a.centerY==b.centerY && a.extents==b.extents &&
        a.material==b.material && a.stage==b.stage && a.flags==b.flags &&
        a.statue==b.statue && a.bedding==b.bedding && a.bridge==b.bridge &&
        a.pumpDirection==b.pumpDirection && a.pumpRunning==b.pumpRunning &&
        a.rollerDirection==b.rollerDirection && a.horizontalAxleVertical==b.horizontalAxleVertical && a.constructionItemIsLog==b.constructionItemIsLog &&
        a.constructionItemMaterial==b.constructionItemMaterial;
}
}

void Df3dWorld::enqueueBuilding(wm::BuildingId id, uint32_t reason) {
    if(submission::details().enabled)buildingSubmissionReasons_[id]|=reason;
    if (buildingQueued_.insert(id).second) buildingQueue_.push_back(id);
}

Node3D* Df3dWorld::buildingLayerRoot(int z) {
    auto& root=buildingLayers_[z];
    if (!root) {
        root=memnew(Node3D);
        root->set_name(String("level_")+String::num_int64(z));
        root->set_visible(zInWindow(z));
        get_building_root()->add_child(root);
    }
    return root;
}

void Df3dWorld::clearBuildingLayers() {
    for(auto& [z,root]:buildingLayers_) {
        root->get_parent()->remove_child(root);
        godot::memdelete(root);
    }
    buildingLayers_.clear();
}

void Df3dWorld::updateBuildingVisibility() {
    for(const auto& [z,root]:buildingLayers_)
        if(root->is_visible()!=zInWindow(z))root->set_visible(zInWindow(z));
}

// Geometry follows source versions; level changes only switch parent visibility.
void Df3dWorld::enqueueBuildings() {
    if (!source_.model().buildingsKnown() || topZ_ < 0) return;
    source_.model().forEachBuilding([&](const wm::Building& b) {
        auto it = builtBuildings_.find(b.id);
        if (it != builtBuildings_.end() && it->second.version == b.version) return;
        enqueueBuilding(b.id, submission::Window);
    });
}

void Df3dWorld::freeBuilding(BuiltBuilding& b) {
    if (b.node) {
        buildingBatches_.erase(b.id, false);
        b.node->get_parent()->remove_child(b.node);
        godot::memdelete(b.node);
        b.node = nullptr;
        --buildingsDrawn_;
    }
    if (b.unresolved) {
        --buildingsUnresolved_;
        auto it = unresolvedBuildingKinds_.find(wm::buildingKindName(b.kind));
        if (it != unresolvedBuildingKinds_.end() && --it->second <= 0) unresolvedBuildingKinds_.erase(it);
        b.unresolved = false;
    }
    if (b.glyph) {
        --buildingsGlyph_;
        b.glyph = false;
    }
}

void Df3dWorld::buildBuilding(wm::BuildingId id, uint32_t reason) {
    PerfScope profile("building.geometry", nullptr, df3d::profiling::detailed());
    // An immediate layout repair also consumes any ordinary pending build.
    buildingQueued_.erase(id);
    if(submission::details().enabled) {
        const auto pending=buildingSubmissionReasons_.find(id);
        if(pending!=buildingSubmissionReasons_.end()) {reason|=pending->second;buildingSubmissionReasons_.erase(pending);}
    }
    const wm::Building* b = source_.model().building(id);
    auto slot = builtBuildings_.find(id);
    if (!b) {
        if (slot != builtBuildings_.end()) {
            freeBuilding(slot->second);
            builtBuildings_.erase(slot);
        }
        return;
    }
    BuiltBuilding& built = builtBuildings_[id];
    submission::BuildingDetailScope detail(id,wm::buildingKindName(b->kind),reason,built.submissionFingerprint);
    built.id = id;
    ++perfBuildingBuilds_;
    if (built.lastBuildPoll == perfPollCount_) ++perfBuildingDuplicateBuilds_;
    built.lastBuildPoll = perfPollCount_;
    freeBuilding(built);
    built.version = b->version;
    built.z = b->z;
    built.kind = b->kind;
    if (!assets_) return;

    auto art=buildingFootprintCache_.find(id);
    if(art==buildingFootprintCache_.end() || art->second.version!=b->version)
        art=buildingFootprintCache_.insert_or_assign(id,resolveBuildingFootprint(*b)).first;
    else ++perfBuildingArtHits_;
    const auto& r=art->second.artwork;

    // Vertex colour: white, dimmed for in-progress art the raws lack, a
    // translucent ghost for planned buildings.
    Color tint(1, 1, 1, 1);
    SurfaceKind kind = kSurfDecal;
    if ((isRawPlannedFurniture(b->kind) || isMaterialPlannedFurniture(b->kind) || r.plannedHalfAlpha) && b->stage!=wm::BuildingStage::Complete) {
        kind=kSurfGhost;
    } else if ((b->kind == wm::BuildingKind::Well || b->kind == wm::BuildingKind::WindowGem || b->kind == wm::BuildingKind::WindowGlass || b->kind == wm::BuildingKind::BarsFloor || b->kind == wm::BuildingKind::Support || b->kind == wm::BuildingKind::BarsVertical || b->kind == wm::BuildingKind::Slab || b->kind == wm::BuildingKind::Instrument || b->kind == wm::BuildingKind::ScrewPump || b->kind==wm::BuildingKind::Rollers || b->kind==wm::BuildingKind::WaterWheel || b->kind==wm::BuildingKind::Windmill || isTransmission(b->kind) || (b->kind==wm::BuildingKind::Trap && b->subtype==5)) && b->stage != wm::BuildingStage::Complete) {
        // Native planned pumps and track stops retain painted RGB with half alpha.
        kind=kSurfGhost;
    } else if (b->kind == wm::BuildingKind::Bridge && b->stage != wm::BuildingStage::Complete) {
        // Native stages0..2 retain the bridge's colors and halve source alpha.
        tint=Color(1,1,1,1);kind=kSurfGhost;
    } else if (b->kind == wm::BuildingKind::Construction) {
        // Native planned artwork owns partial alpha (e.g. Track grooves at
        // 115/255). Cutout discards those pixels; retain full source opacity.
        kind = kSurfGhost;
    } else if (r.stageArt) {
        // Native layout construction stages supply their own opacity.
        kind = kSurfGhost;
    } else if (b->stage == wm::BuildingStage::Planned) {
        tint = Color(1, 1, 1, 0.4f);
        kind = kSurfGhost;
    } else if (b->stage == wm::BuildingStage::InProgress && !r.stageArt) {
        tint = Color(0.6f, 0.6f, 0.6f, 1);
    }
    const bool phasedMachine=r.found && (isTransmission(b->kind) || b->kind==wm::BuildingKind::Windmill || ((b->kind==wm::BuildingKind::Rollers || b->kind==wm::BuildingKind::WaterWheel) && b->stage==wm::BuildingStage::Complete));
    const uint32_t machineSlot=phasedMachine ? updateMachinePosition(*b) : 0;
    const bool piece = mesher::isFurniturePiece(b->kind);
    const auto depthAt=[&](int,int y) {
        return piece?mesher::buildingDepth(b->y1,y):mesher::DepthInterval{mesher::installationArtBottom(b->kind),0};
    };
    std::map<SurfaceKey, QuadArrays> surfaces;
    godot::Array drawRecords;
    bool crossesFootprint=false;
    float sortLift=0;
    int quads = 0;
    if (r.found) {
        using DrawCell=std::pair<int,int>;
        std::map<DrawCell,std::vector<std::pair<int,Color>>> tiles;
        for (const assets::BuildingTile& t : r.tiles) {
            const wm::TilePos p{b->x1+t.lx,b->y1+t.ly,b->z};
            if(!tileVisible(p))continue;
            if(b->kind==wm::BuildingKind::Bed && b->stage==wm::BuildingStage::Complete && b->bedding.sheet>=0) {
                const int bed=bedSlot(source_.model().materialName(b->constructionItemIsLog>=0?b->constructionItemMaterial:b->material),b->bedding);
                if(bed>=0)tiles[{p.x,p.y}].push_back({bed,Color(0,0,1,1)});
                continue;
            }
            const int slot=buildingSlotFor(b->kind,b->stage,t.sprite.page,(t.rawPalette || (r.gridLayout && t.foreground)) ? -1 : r.paletteRow,b->subtype,r.plannedHalfAlpha || t.halfAlpha);if(slot<0)continue;
            const TextureSlot* found=spriteResources_.slots.find(slot);
            ERR_CONTINUE_MSG(!found, "stale building sprite slot " + godot::String::num_int64(slot));
            const auto& s=*found;const auto px=assets_->index.pixels(t.sprite);
            tiles[{p.x,p.y}].push_back({slot,Color(float(px.px)/s.width,float(px.py)/s.height,float(px.pw)/s.width,float(px.ph)/s.height)});
        }
        struct Fragment {int slot,w,h;Color region;mesher::DepthInterval depth;std::shared_ptr<const BuildingAlphaRegion> alpha;};
        std::map<DrawCell,Fragment> fragments;
        for(const auto& [pos,layers]:tiles) {
            const auto [x,y]=pos;
            const bool half=(isMaterialPlannedFurniture(b->kind) || b->kind==wm::BuildingKind::BarsVertical || b->kind==wm::BuildingKind::BarsFloor || b->kind==wm::BuildingKind::Support || b->kind==wm::BuildingKind::WindowGem || b->kind==wm::BuildingKind::WindowGlass) && b->stage!=wm::BuildingStage::Complete;
            const bool direct=layers.size()==1 && !half;
            const bool grid = r.gridLayout && b->width() > 1 && b->height() > 1;
            const int slot=direct?layers[0].first:compositeBuildingTile(layers,half,b->constructionItemId>=0,grid);
            const Color region=direct?layers[0].second:Color(0,0,1,1);
            auto depth=depthAt(x,y);
            const TextureSlot* layer=slot>=0?spriteResources_.slots.find(slot):nullptr;
            ERR_CONTINUE_MSG(!layer || layer->texture.is_null(), "stale building tile slot " + godot::String::num_int64(slot));
            auto& image=spriteResources_.images[slot];if(image.is_null())image=layer->texture->get_image();
            if(image.is_null())continue;
            const int iw=image->get_width(),ih=image->get_height();
            const int ox=std::lround(region.r*iw),oy=std::lround(region.g*ih);
            const int w=std::lround(region.b*iw),h=std::lround(region.a*ih);
            auto alpha=buildingAlphaRegion(slot,ox,oy,w,h);
            if(!alpha || std::none_of(alpha->pixels.begin(),alpha->pixels.end(),[](uint8_t a){return a!=0;}))continue;
            fragments.emplace(pos,Fragment{slot,w,h,region,depth,std::move(alpha)});
        }
        for(const auto& [pos,f]:fragments) {
            const auto [x,y]=pos;
            const int slot=f.slot;const auto region=f.region;const auto depth=f.depth;
            const float base=b->z+mesher::kFloorHeight+depth.bottom;
            surfaces[{slot,kind}].ground=ground_support(Vector3(x+.5f,b->z,y+.5f));
            godot::Dictionary record;
            record["x"]=x;record["y"]=y;record["z"]=b->z;
            record["foreground"]=false;record["bottom"]=depth.bottom;
            record["thickness"]=piece?depth.thickness:0.0f;
            record["north_spill"]=y<b->y1;
            crossesFootprint |= x<b->x1 || x>b->x2 || y<b->y1 || y>b->y2;
            drawRecords.push_back(record);
            const float uv[4]={region.r,region.g,region.r+region.b,region.g+region.a};
            if(piece) {
                // Subtract neighbouring opaque vertical spans, never emit
                // coincident per-tile side walls inside one installation.
                std::vector<mesher::CutoutEdgeCover> covers;
                const int dx[4]={0,1,0,-1},dy[4]={-1,0,1,0};
                for(int side=0;side<4;++side) {
                    const auto it=fragments.find({x+dx[side],y+dy[side]});
                    if(it==fragments.end())continue;
                    const auto& n=it->second;
                    const int pixels=side%2?f.h:f.w;
                    for(int pixel=0;pixel<pixels;++pixel) {
                        const int nx=side==1?0:side==3?n.w-1:pixel*n.w/pixels;
                        const int ny=side==0?n.h-1:side==2?0:pixel*n.h/pixels;
                        if(n.alpha->pixels[ny*n.w+nx]<128)continue;
                        const float scale=mesher::kCutoutThickness/depth.thickness;
                        covers.push_back({side,pixel,(n.depth.bottom-depth.bottom)*scale,
                            (n.depth.bottom+n.depth.thickness-depth.bottom)*scale});
                    }
                }
                BuildingAlphaRegion::CoverKey key;
                key.reserve(covers.size());
                for(const auto& c:covers)key.emplace_back(c.side,c.pixel,c.bottom,c.top);
                auto& cache=f.alpha->contours;
                auto cached=cache.find(key);
                if(cached==cache.end()) {
                    PerfScope contourProfile("building.contour", nullptr, df3d::profiling::detailed());
                    if(cache.size()>=8)cache.clear();
                    cached=cache.emplace(std::move(key),mesher::cutoutMesh(f.alpha->pixels,f.w,f.h,covers,true)).first;
                }
                // Native top-down foreground priority is view state, not a
                // physical gap between the statue's two artwork rows.
                const auto nativeDepth=b->kind==wm::BuildingKind::Statue
                    ?mesher::statueFigureDepth(b->y1,y):depth;
                const float nativeLift=nativeDepth.bottom+nativeDepth.thickness-depth.bottom-depth.thickness;
                sortLift=std::max(sortLift,nativeLift);
                surfaces[{slot,kind}].addCutoutVertices(cached->second,x,y,base,depth.thickness,region,tint,nativeLift);
            }
            else {
                auto& array=surfaces[{slot,kind}];
                const auto start=array.tileCenters.size();
                array.add(x,y,base,tint,uv);
                if(phasedMachine) {
                    const int direction=b->rollerDirection;
                    const int coordinate=(direction&1)?x:y;
                    const float code=isTransmission(b->kind) ? 15.0f : b->kind==wm::BuildingKind::Windmill ? 14.0f : b->kind==wm::BuildingKind::WaterWheel ? (b->x2-b->x1>b->y2-b->y1 ? 12.0f : 13.0f)
                        : (direction>=0 && direction<=3 ? float(direction*3+coordinate%3) : -1.0f);
                    auto* data=array.tileCenters.ptrw();
                    for(int64_t i=start;i<array.tileCenters.size();i+=4) {
                        data[i+2]=(float(machineSlot%256)+0.5f)/256.0f;data[i+3]=code;
                    }
                }
            }
            ++quads;
        }
    } else {
        // No art: the classic glyph per occupied tile (shops, the
        // tool workshop), coloured by the material's BUILD_COLOR when the
        // glyph tables know it; a tinted marker only without a tileset.
        int glyphSlot = -1;
        Color glyphUv;
        if (glyphsReady() && source_.model().glyphsKnown()) {
            const assets::ClassicGlyphChoice g = assets::classicBuildingGlyph(
                assets_->index, b->kind, source_.model().materialGlyph(b->material));
            if (g.found) {
                glyphSlot = glyphSlotFor(g.glyph.fg, g.glyph.bg, g.glyph.bright);
                glyphUv = glyphRegion(g.glyph.tile);
            }
        }
        const Color c = glyphSlot >= 0 ? Color(1, 1, 1, 1) : entityKindColor(wm::buildingKindName(b->kind));
        const float uv[4] = {glyphUv.r, glyphUv.g, glyphUv.r + glyphUv.b, glyphUv.g + glyphUv.a};
        const float plain[4] = {0, 0, 1, 1};
        for (int32_t y = b->y1; y <= b->y2; ++y) {
            for (int32_t x = b->x1; x <= b->x2; ++x) {
                if (!b->occupies(x, y)) continue;
                const wm::TilePos p{x, y, b->z};
                if (!tileVisible(p)) continue;
                const auto depth=depthAt(x,y);
                const float base=b->z+mesher::kFloorHeight+depth.bottom;
                surfaces[SurfaceKey{glyphSlot,glyphSlot>=0?kind:kSurfOpaque}].ground=ground_support(Vector3(x+.5f,b->z,y+.5f));
                if (glyphSlot >= 0)
                    if(piece) surfaces[SurfaceKey{glyphSlot,kind}].addCutout(sprite_cutout_mesh(glyphSlot,Color(uv[0],uv[1],uv[2]-uv[0],uv[3]-uv[1])),x,y,base,depth.thickness,c,Color(uv[0],uv[1],uv[2]-uv[0],uv[3]-uv[1]));
                    else surfaces[SurfaceKey{glyphSlot, kind}].add(x, y, base, c, uv);
                else
                    surfaces[SurfaceKey{-1, kSurfOpaque}].add(x, y, base, c, plain);
                ++quads;
            }
        }
        if (glyphSlot >= 0) {
            built.glyph = true;
            ++buildingsGlyph_;
        } else {
            built.unresolved = true;
            ++buildingsUnresolved_;
            unresolvedBuildingKinds_[wm::buildingKindName(b->kind)] += 1;
        }
    }
    if (quads == 0) return;

    Ref<ArrayMesh> mesh;
    mesh = submission::createMesh(submission::MeshSite::Building);
    // Retain copy-on-write CPU streams for spatial batching. Reading arrays
    // back from an uploaded mesh can otherwise synchronize with the GPU.
    Array batchArrays;
    PackedInt32Array pickSlots;
    const bool pump = b->kind==wm::BuildingKind::ScrewPump &&
        b->stage==wm::BuildingStage::Complete && r.found;
    for (auto& [sk, arr] : surfaces) {
        // Flat pumps carry an atlas displacement in CUSTOM2.zw. Its sign encodes
        // the base row's parity; zero means idle/unknown. The batcher retains it.
        if (pump && b->pumpRunning==1 && b->pumpDirection>=0 && b->pumpDirection<4) {
            static constexpr const char* directions[]={"S","W","N","E"};
            const std::string prefix=std::string("SCREWPUMP_")+directions[b->pumpDirection];
            const auto* first=assets_->index.tile(prefix+"_1",0);
            const auto* second=assets_->index.tile(prefix+"_2",0);
            const TextureSlot* slot=spriteResources_.slots.find(sk.slot);
            if(first && second && first->page==second->page && slot) {
                const auto a=assets_->index.pixels(*first),z=assets_->index.pixels(*second);
                const float sign=(b->y1%2)==0?1.0f:-1.0f;
                const float dx=float(z.px-a.px)/slot->width,dy=float(z.py-a.py)/slot->height;
                if(dx>=0 && dy>=0) {
                    auto* payload=arr.tileCenters.ptrw();
                    for(int64_t i=0;i<arr.tileCenters.size();i+=4) {
                        payload[i+2]=sign*dx;payload[i+3]=sign*dy;
                    }
                }
            }
        }
        PerfScope uploadProfile("building.upload_surface", nullptr, df3d::profiling::detailed());
        Array arrays;
        arrays.resize(Mesh::ARRAY_MAX);
        arrays[Mesh::ARRAY_VERTEX] = arr.vertices;
        arrays[Mesh::ARRAY_NORMAL] = arr.normals;
        arrays[Mesh::ARRAY_COLOR] = arr.colors;
        if (sk.slot >= 0) arrays[Mesh::ARRAY_TEX_UV] = arr.uvs;
        arrays[Mesh::ARRAY_INDEX] = arr.indices;
        arrays[Mesh::ARRAY_CUSTOM2] = arr.tileCenters;
        batchArrays.push_back(arrays);
        pickSlots.push_back(piece ? sk.slot : -1);
        detail.surface(arrays);
        const int surface = mesh->get_surface_count();
        if (phasedMachine && sk.slot>=0) {
            submission::meshSurface(mesh,arrays,submission::MeshSite::Building,
                uint64_t(Mesh::ARRAY_CUSTOM_RGBA_FLOAT)<<Mesh::ARRAY_FORMAT_CUSTOM2_SHIFT);
            auto& mat=buildingMachineMaterials_[{sk,machineSlot/256}];
            if(mat.is_null()) {
                mat.instantiate();
                mat->set_shader(godot::ResourceLoader::get_singleton()->load(sk.kind==kSurfGhost ? "res://shaders/machine_ghost.gdshader" : "res://shaders/machine_surface.gdshader"));
                const TextureSlot* sprite=spriteResources_.slots.find(sk.slot);
                ERR_CONTINUE_MSG(!sprite || sprite->texture.is_null(),"stale machinery sprite slot");
                godot::Dictionary parameters;
                parameters["albedo_tex"]=sprite->texture;
                parameters["albedo_cell"]=sprite->texture->get_meta("world_cell",Vector2());
                parameters["machine_positions"]=machinePhasePages_[machineSlot/256].texture;
                configureImmutableMaterial(mat,parameters);
            }
            mesh->surface_set_material(surface,mat);
        } else if (pump && sk.slot>=0) {
            submission::meshSurface(mesh,arrays,submission::MeshSite::Building,
                uint64_t(Mesh::ARRAY_CUSTOM_RGBA_FLOAT)<<Mesh::ARRAY_FORMAT_CUSTOM2_SHIFT);
            auto& mat=buildingPumpMaterials_[sk];
            if(mat.is_null()) {
                mat.instantiate();
                mat->set_shader(godot::ResourceLoader::get_singleton()->load("res://shaders/pump_surface.gdshader"));
                const TextureSlot* sprite=spriteResources_.slots.find(sk.slot);
                ERR_CONTINUE_MSG(!sprite || sprite->texture.is_null(),"stale pump sprite slot");
                godot::Dictionary parameters;
                parameters["albedo_tex"]=sprite->texture;
                parameters["albedo_cell"]=sprite->texture->get_meta("world_cell",Vector2());
                configureImmutableMaterial(mat,parameters);
            }
            mesh->surface_set_material(surface,mat);
        } else if (piece && sk.slot >= 0) {
            submission::meshSurface(mesh, arrays, submission::MeshSite::Building,uint64_t(Mesh::ARRAY_CUSTOM_RGBA_FLOAT)<<Mesh::ARRAY_FORMAT_CUSTOM2_SHIFT);
            // Piece geometry already owns its tint and atlas UVs. The material
            // depends only on its texture slot and compositing mode, allowing
            // different furniture silhouettes to share a single batch surface.
            auto& mat = buildingPieceMaterials_[sk];
            if (mat.is_null()) {
                mat.instantiate();
                mat->set_shader(godot::ResourceLoader::get_singleton()->load(sk.kind == kSurfGhost ? "res://shaders/standee_ghost.gdshader" : "res://shaders/furniture_sprite.gdshader"));
                godot::Dictionary parameters;
                const TextureSlot* sprite=spriteResources_.slots.find(sk.slot);
                ERR_CONTINUE_MSG(!sprite || sprite->texture.is_null(), "stale building piece slot " + godot::String::num_int64(sk.slot));
                parameters["sprite_tex"]=sprite->texture;
                parameters["sprite_cell"]=sprite->texture->get_meta("world_cell", Vector2());
                configureImmutableMaterial(mat,parameters);
            }
            mesh->surface_set_material(surface, mat);
        } else {
            submission::meshSurface(mesh, arrays, submission::MeshSite::Building,uint64_t(Mesh::ARRAY_CUSTOM_RGBA_FLOAT)<<Mesh::ARRAY_FORMAT_CUSTOM2_SHIFT);
            mesh->surface_set_material(surface, materialFor(sk));
        }
    }
    mesh->set_meta("df3d_batch_arrays", batchArrays);
    mesh->set_meta("df3d_pick_slots", pickSlots);
    MeshInstance3D* node = memnew(MeshInstance3D);
    node->set_name(String("building_") + String::num_int64(id));
    if (b->kind == wm::BuildingKind::Civzone) node->set_visible(zoneOverlaysVisible_);
    node->set_mesh(mesh);
    node->set_meta("df3d_draw_fragments",drawRecords);
    node->set_meta("df3d_building_kind",String(wm::buildingKindName(b->kind)));
    if(piece && crossesFootprint) {
        node->set_meta("df3d_transparent_sort",true);
        node->set_meta("df3d_sort_row",b->y1);
        node->set_meta("df3d_sort_lift",sortLift);
        node->set_script(godot::ResourceLoader::get_singleton()->load("res://scripts/furniture_order.gd"));
    }
    if (piece) node->set_extra_cull_margin(1.1f);
    buildingLayerRoot(b->z)->add_child(node);
    built.node = node;
    ++buildingsDrawn_;
    refresh_building_batches(id);
}

void Df3dWorld::refresh_building_batches(int64_t id) {
    const auto found = builtBuildings_.find(wm::BuildingId(id));
    if (found == builtBuildings_.end() || !found->second.node) return;
    const auto* building = source_.model().building(wm::BuildingId(id));
    auto* node = found->second.node;
    // Zone visibility and planned-building transparency have independent
    // semantics. Overhanging alpha art also needs its own camera-sorted draw;
    // a material batch cannot order its filtered edges against neighbours.
    if (!building || building->kind == wm::BuildingKind::Civzone ||
        building->stage == wm::BuildingStage::Planned || node->has_meta("df3d_transparent_sort")) {
        buildingBatches_.erase(wm::BuildingId(id));
        return;
    }
    // Whole installations remain intact, including artwork spilling outside
    // their footprint. Cells bound batch culling; source meshes retain exact
    // per-building geometry for picking and presentation transformations.
    buildingBatches_.put(wm::BuildingId(id), node,
        godot::Vector3i(building->x1 / 32, building->z, building->y1 / 32));
}

// --- items ---

// All source layers become one top image BEFORE silhouette extrusion. This
// removes the coincident contour walls of forbidden/state-overlay furniture.
int Df3dWorld::buildingSlotFor(wm::BuildingKind kind,wm::BuildingStage stage,int page,int paletteRow,uint16_t subtype,bool plannedHalfAlpha) {
    const bool planned=stage!=wm::BuildingStage::Complete;
    const bool rawOpening=isRawPlannedFurniture(kind) && planned;
    const bool floorHalf=isFloorHalfPlannedBuilding(kind,subtype);
    const bool layoutHalf=plannedHalfAlpha;
    const int colored=slotFor(page,rawOpening ? -1 : paletteRow,false);
    if((!rawOpening && !isTransmission(kind) && kind!=wm::BuildingKind::Slab && kind!=wm::BuildingKind::Well && kind!=wm::BuildingKind::Bridge && !floorHalf && !layoutHalf) || (!isAxle(kind) && !planned) || colored<0)return colored;
    const int raw=slotFor(page,-1,false);
    if(raw<0)return -1;
    const std::string key=std::string(rawOpening ? "opening-page:" : layoutHalf ? "layout-half-page:" : floorHalf ? "floor-half-page:" : kind==wm::BuildingKind::Bridge ? "bridge-page:" : isAxle(kind) ? "axle-page:" : kind==wm::BuildingKind::Slab ? "slab-page:" : kind==wm::BuildingKind::Well ? "well-page:" : "gear-page:")+std::to_string(colored)+":"+std::to_string(raw)+(planned ? ":planned" : ":complete");
    if(auto it=spriteResources_.buildings.find(key);it!=spriteResources_.buildings.end())return it->second;
    const auto* base=spriteResources_.slots.find(colored);
    const auto* uncolored=spriteResources_.slots.find(raw);
    ERR_FAIL_COND_V_MSG(!base || !uncolored,-1,"stale building artwork page");
    auto source=base->texture->get_image();auto fittings=uncolored->texture->get_image();
    auto image=source->get_region(godot::Rect2i(0,0,source->get_width(),source->get_height()));
    image->clear_mipmaps();
    // Both native frames are immutable material artwork. Phase updates only
    // select a cell; fittings are never recolored or recomposited per tick.
    if(isAxle(kind))for(const char* family:{"AXLE_HORIZONTAL_NS","AXLE_HORIZONTAL_WE","AXLE_VERTICAL"})for(int frame=1;frame<=2;++frame) {
        const std::string name=family;
        const auto* shaft=assets_->index.tile(name+"_"+std::to_string(frame));
        const auto* fitting=assets_->index.tile(name+"_FITTINGS_"+std::to_string(frame));
        ERR_FAIL_COND_V_MSG(!shaft || !fitting || shaft->page!=page || fitting->page!=page,-1,"missing native axle fittings");
        const auto from=assets_->index.pixels(*fitting),to=assets_->index.pixels(*shaft);
        image->blend_rect(fittings,godot::Rect2i(from.px,from.py,from.pw,from.ph),godot::Vector2i(to.px,to.py));
    }
    // Native planned gears, slabs, bridges and querns round half alpha up; pumps and axles truncate.
    // Apply this before filtering/mipmap generation, once per cached artwork.
    if(planned) {
        image->convert(godot::Image::FORMAT_RGBA8);
        auto bytes=image->get_data();
        const int rounding=(isAxle(kind) || floorHalf) ? 0 : 1;
        for(int64_t i=3;i<bytes.size();i+=4)bytes.set(i,(int(bytes[i])+rounding)/2);
        image->set_data(image->get_width(),image->get_height(),false,godot::Image::FORMAT_RGBA8,bytes);
    }
    image->generate_mipmaps();
    TextureSlot slot;slot.page=page;slot.paletteRow=paletteRow;slot.width=image->get_width();slot.height=image->get_height();
    slot.texture=submission::texture(image,submission::TextureSite::BuildingArt,true);
    const auto* info=assets_->index.page(page);
    slot.texture->set_meta("world_cell",Vector2(info->tileW,info->tileH));
    const int id=spriteResources_.slots.add(std::move(slot));
    ERR_FAIL_COND_V_MSG(id<0,-1,"building artwork slots exhausted");
    spriteResources_.images[id]=image;spriteResources_.buildings[key]=id;return id;
}

int Df3dWorld::compositeBuildingTile(const std::vector<std::pair<int, Color>>& layers,bool floorHalfAlpha,bool nativeItemBlend,bool nativeLayoutBlend) {
    if(layers.empty()) return -1;
    std::string key=nativeLayoutBlend ? "layout-composite:" : nativeItemBlend ? "item-composite:" : floorHalfAlpha ? "half-composite:" : "composite:";
    struct Source {int slot,x,y,w,h; godot::Ref<godot::ImageTexture> texture;};
    std::vector<Source> sources;
    int w=0,h=0;
    for(const auto& [slot,region]:layers) {
        const TextureSlot* found=spriteResources_.slots.find(slot);
        ERR_FAIL_COND_V_MSG(!found || found->texture.is_null(), -1, "stale composite layer slot " + godot::String::num_int64(slot));
        const auto& s=*found;
        const int x=std::lround(region.r*s.width), y=std::lround(region.g*s.height);
        const int sw=std::lround(region.b*s.width), sh=std::lround(region.a*s.height);
        key+=std::to_string(slot)+":"+std::to_string(x)+":"+std::to_string(y)+":"+std::to_string(sw)+":"+std::to_string(sh)+";";
        sources.push_back({slot,x,y,sw,sh,s.texture});
        w=std::max(w,sw);h=std::max(h,sh);
    }
    if(auto it=spriteResources_.buildings.find(key);it!=spriteResources_.buildings.end())return it->second;
    auto image=godot::Image::create(w,h,false,godot::Image::FORMAT_RGBA8);
    image->fill(Color(0,0,0,0));
    bool firstLayer=true;
    for(const auto& src:sources) {
        auto& source=spriteResources_.images[src.slot];if(source.is_null())source=src.texture->get_image();
        ERR_FAIL_COND_V_MSG(source.is_null(), -1, "composite layer slot without image");
        auto layer=source->get_region(godot::Rect2i(src.x,src.y,src.w,src.h));
        if(layer->get_width()!=w || layer->get_height()!=h)layer->resize(w,h,godot::Image::INTERPOLATE_NEAREST);
        if(nativeLayoutBlend && firstLayer) {
            image->blit_rect(layer,godot::Rect2i(0,0,w,h),godot::Vector2i(0,0));
        } else if(nativeItemBlend || nativeLayoutBlend) {
            layer->convert(godot::Image::FORMAT_RGBA8);layer->clear_mipmaps();
            auto dst=image->get_data();const auto src=layer->get_data();
            for(int64_t i=0;i<dst.size();i+=4) {
                assets::Rgba d{dst[i],dst[i+1],dst[i+2],dst[i+3]};
                const assets::Rgba pixel{src[i],src[i+1],src[i+2],src[i+3]};
                if(nativeLayoutBlend) {
                    assets::blendLayoutOver(d,pixel);
                }
                else assets::blendOver(d,pixel);
                dst.set(i,d.r);dst.set(i+1,d.g);dst.set(i+2,d.b);dst.set(i+3,d.a);
            }
            image->set_data(w,h,false,godot::Image::FORMAT_RGBA8,dst);
        } else image->blend_rect(layer,godot::Rect2i(0,0,w,h),godot::Vector2i(0,0));
        firstLayer=false;
    }
    // Native bars halve the finished composite, not each component layer.
    if(floorHalfAlpha) {
        auto bytes=image->get_data();
        for(int64_t i=3;i<bytes.size();i+=4)bytes.set(i,int(bytes[i])/2);
        image->set_data(w,h,false,godot::Image::FORMAT_RGBA8,bytes);
    }
    // Upload preparation clears zero-alpha RGB. Do not dilate edge colors:
    // native Lanczos reconstructs against transparent black, including here.
    image->generate_mipmaps();
    TextureSlot slot;slot.width=w;slot.height=h;slot.texture=submission::texture(image, submission::TextureSite::BuildingArt,true);
    const int id=spriteResources_.slots.add(std::move(slot));
    ERR_FAIL_COND_V_MSG(id < 0, -1, "composite building slots exhausted");
    spriteResources_.images[id]=image;
    spriteResources_.buildings[key]=id;return id;
}

godot::Dictionary Df3dWorld::presentation_perf_stats() const {
    godot::Dictionary out;
    out["profiling_mode"] = df3d::profiling::modeName(df3d::profiling::global().mode());
    out["unit_art_hits"]=int64_t(unitArtHits_); out["unit_art_misses"]=int64_t(unitArtMisses_);
    out["unit_art_cached"]=int64_t(unitArtCache_.size());
    out["poll_count"]=int64_t(perfPollCount_); out["poll_ms"]=perfPollMs_;
    out["snapshot_adoption_ms"]=perfAdoptionMs_;
    out["terrain_update_ms"]=perfTerrainUpdateMs_;
    out["entity_update_ms"]=perfEntityUpdateMs_;
    out["building_drain_ms"]=perfBuildingDrainMs_;
    out["building_geometry_builds"]=int64_t(perfBuildingBuilds_);
    out["building_duplicate_builds"]=int64_t(perfBuildingDuplicateBuilds_);
    out["batch_flush_ms"]=perfBatchFlushMs_;
    out["unit_evaluation_count"]=int64_t(perfUnitCount_); out["unit_evaluation_ms"]=perfUnitMs_;
    out["layout_update_passes"]=int64_t(perfDepthCount_); out["layout_update_ms"]=perfDepthMs_;
    out["footprint_ms"]=perfFootprintMs_; out["depth_building_ms"]=perfDepthBuildingMs_;
    out["footprint_cache_hits"]=int64_t(perfFootprintHits_); out["footprint_cache_misses"]=int64_t(perfFootprintMisses_);
    out["footprint_alpha_pixels"]=int64_t(perfAlphaPixels_);
    out["building_art_cache_hits"]=int64_t(perfBuildingArtHits_);
    out["building_alpha_cache_hits"]=int64_t(perfBuildingAlphaHits_);
    out["building_alpha_cache_misses"]=int64_t(perfBuildingAlphaMisses_);
    out["building_alpha_cache_evictions"]=int64_t(perfBuildingAlphaEvictions_);
    out["building_alpha_cache_regions"]=int64_t(buildingAlphaCache_.size());
    out["footprint_cache_evictions"]=int64_t(perfFootprintEvictions_); out["footprint_cache_resets"]=int64_t(perfFootprintResets_);
    out["item_update_passes"]=int64_t(perfItemCount_); out["item_update_ms"]=perfItemMs_;
    out["corpse_item_changes_pending"]=int64_t(corpseItemChanges_.size());
    out["corpse_item_changes_dropped"]=int64_t(corpseItemChangesDropped_);
    out["event_budget_drops"]=int64_t(source_.model().eventBudgetDrops());
    const auto layout = tileLayouts_.stats();
    if(df3d::profiling::global().mode()==df3d::profiling::Mode::Deep) {
        godot::Array history;
        for(const auto& row:layoutCausalProbe_.rows) {
            godot::Dictionary record;
            record["timestamp_us"]=int64_t(row.timestampUs);record["tick"]=int64_t(row.tick);
            record["scope_reset"]=row.scopeReset;record["view_dirty"]=row.viewDirty;
            record["changed_items"]=row.changedItems;record["tiles_applied"]=row.tilesApplied;
            godot::Array tiles;
            for(const auto& tile:row.tiles) {
                godot::Dictionary t;
                const auto [z,x,y]=tile.tile;
                t["x"]=x;t["y"]=y;t["z"]=z;
                t["item_pieces"]=tile.itemPieces;t["unit_pieces"]=tile.unitPieces;
                t["changed_items"]=tile.changedItems;
                t["item_update_requests"]=tile.causes.itemUpdates;
                t["unit_arrivals"]=tile.causes.unitArrivals;t["unit_departures"]=tile.causes.unitDepartures;
                tiles.push_back(t);
            }
            record["tiles"]=tiles;history.push_back(record);
        }
        out["layout_causal_probe"]=history;
    }
    out["tile_layout_builds"]=int64_t(layout.layoutsBuilt);
    out["tile_layout_hits"]=int64_t(layout.cacheHits);
    out["tile_layout_contributors"]=int64_t(layout.contributorsVisited);
    out["stack_atlas_page_uploads"]=int64_t(stackAtlas_.uploads);
    out["stack_atlas_upload_bytes"]=int64_t(stackAtlas_.uploadedBytes);
    out["terrain_geometry_builds"]=int64_t(terrainGeometryBuilds_);
    out["terrain_surface_inputs"]=int64_t(terrainSurfaceInputs_);
    out["terrain_surface_uploads"]=int64_t(terrainSurfaceUploads_);
    out["stack_atlas_revision"]=int64_t(stackAtlas_.revision);
    out["ramp_support_blocks_checked"]=int64_t(supportBlocksChecked_);
    out["ramp_support_blocks_skipped"]=int64_t(supportBlocksSkipped_);
    out["ramp_support_tiles_evaluated"]=int64_t(supportTilesEvaluated_);
    out["ramp_support_tiles_changed"]=int64_t(supportTilesChanged_);
    out["tile_layout_invalidations"]=int64_t(layout.invalidatedTiles);
    out["item_records_updated"]=int64_t(itemUpdateCount_);
    out["item_groups_updated"]=int64_t(itemGroupBuildCount_);
    out["item_group_members_checked"]=int64_t(itemGroupMemberChecks_);
    const auto& visibility=terrainVisibilityDependencies_.stats();
    out["visibility_blocks_observed"]=int64_t(visibility.blocksObserved);
    out["visibility_blocks_unchanged"]=int64_t(visibility.blocksUnchanged);
    out["visibility_tiles_changed"]=int64_t(visibility.tilesChanged);
    out["layout_candidate_blocks"]=int64_t(layout.candidateBlockChecks);
    out["layout_candidate_tiles"]=int64_t(layout.candidateTileChecks);
    if(source_.live()) {
        const auto stats=source_.liveStats();
        out["worker_poll_ms"]=stats.pollMilliseconds;
        out["worker_publication_ms"]=stats.publicationMilliseconds;
        out["worker_published"]=int64_t(stats.published);
        out["worker_coalesced"]=int64_t(stats.coalesced);
        out["source_publication_index"]=int64_t(stats.sourcePublications.lastIndex);
        out["source_publications_missed"]=int64_t(stats.sourcePublications.missed);
        out["source_gap_events"]=int64_t(stats.sourcePublications.gapEvents);
        out["source_largest_gap"]=int64_t(stats.sourcePublications.largestGap);
    }
    return out;
}

void Df3dWorld::clear_layout_cache() {
    layoutScopeDirty_=true;lastRenderedTick_=UINT64_MAX;
}

std::shared_ptr<const Df3dWorld::BuildingAlphaRegion> Df3dWorld::buildingAlphaRegion(int slot,int x,int y,int width,int height) {
    const BuildingAlphaKey key{slot,x,y,width,height};
    if(auto found=buildingAlphaCache_.find(key);found!=buildingAlphaCache_.end()) {
        ++perfBuildingAlphaHits_;
        buildingAlphaRecent_.splice(buildingAlphaRecent_.begin(),buildingAlphaRecent_,found->second.recent);
        return found->second.region;
    }
    const TextureSlot* source=spriteResources_.slots.find(slot);
    if(!source || source->texture.is_null() || width<=0 || height<=0)return {};
    auto& image=spriteResources_.images[slot];
    if(image.is_null())image=source->texture->get_image();
    if(image.is_null())return {};
    ++perfBuildingAlphaMisses_;
    auto region=std::make_shared<BuildingAlphaRegion>();
    region->pixels.resize(size_t(width)*height);
    for(int py=0;py<height;++py)for(int px=0;px<width;++px) {
        const auto alpha=image->get_pixel(x+px,y+py).a;
        const auto byte=uint8_t(alpha*255);
        region->pixels[size_t(py)*width+px]=byte;
        // Preserve both original predicates, including their rounding boundary.
        region->geometryOpaque |= byte>=128;
        region->footprintOpaque |= alpha>=.5f;
        ++perfAlphaPixels_;
    }
    buildingAlphaRecent_.push_front(key);
    buildingAlphaCache_.emplace(key,BuildingAlphaEntry{region,buildingAlphaRecent_.begin()});
    constexpr size_t kMaxRegions=2048;
    while(buildingAlphaCache_.size()>kMaxRegions) {
        buildingAlphaCache_.erase(buildingAlphaRecent_.back());
        buildingAlphaRecent_.pop_back();
        ++perfBuildingAlphaEvictions_;
    }
    // Fragment owners retain immutable pixels if another lookup evicts this entry.
    return region;
}

Df3dWorld::BuildingDrawFootprint Df3dWorld::resolveBuildingFootprint(const wm::Building& b) {
    ++perfFootprintMisses_;
    BuildingDrawFootprint result;
    result.version=b.version;
    std::set<std::pair<int,int>> cells,foreground;
    for(int y=b.y1;y<=b.y2;++y) for(int x=b.x1;x<=b.x2;++x)
        if(b.occupies(x,y)) cells.emplace(x-b.x1,y-b.y1);
    if(assets_) {
        assets::BuildingQuery q;
        q.kind=b.kind;q.subtype=b.subtype;q.custom=b.custom;q.stage=b.stage;
        q.width=b.width();q.height=b.height();q.flags=b.flags;
        q.material=source_.model().materialName(b.material);q.extents=&b.extents;
        q.statue=b.statue;
        q.instrumentFamily=b.instrumentFamily;q.instrumentPlaced=b.instrumentPlaced;
        q.pumpDirection=b.pumpDirection;q.horizontalAxleVertical=b.horizontalAxleVertical;q.slabEngraving=b.slabEngraving;q.verticalBarsConnections=b.verticalBarsConnections;q.wellChainIsMetal=b.wellChainIsMetal;q.materialSolidColor=b.materialSolidColor;q.containedItemCount=b.containedItemCount;q.constructionToolRaw=b.constructionToolRaw;q.constructionStage=b.constructionStage;q.siegeFacing=b.siegeFacing;q.siegeFireTimer=b.siegeFireTimer;q.trapState=b.trapState;q.trapReadyTimeout=b.trapReadyTimeout;q.trapFillTimer=b.trapFillTimer;q.trapTriggerFlags=b.trapTriggerFlags;q.weaponCount=b.weaponCount;q.weaponRetracted=b.weaponRetracted;q.constructionWeaponRaw=b.constructionWeaponRaw;q.constructionItemId=b.constructionItemId;q.constructionItemSolidColor=b.constructionItemSolidColor;
        q.rollerDirection=b.rollerDirection;q.x1=b.x1;q.y1=b.y1;
        if(b.kind==wm::BuildingKind::Rollers) {
            for(int y=b.y1;y<=b.y2;++y)for(int x=b.x1;x<=b.x2;++x) {
                const auto tile=source_.model().tileAt({x,y,b.z});
                result.completedTracks.push_back(tile?tile->completedTrack:0);
            }
            q.completedTracks=&result.completedTracks;
            // Resident geometry uses frame1; the shader owns machine position.
            if(b.stage==wm::BuildingStage::Complete)q.rollerDirection=-1;
        }
        q.constructionItemIsLog=b.constructionItemIsLog;
        q.constructionItemMaterial=source_.model().materialName(b.constructionItemMaterial);
        if(b.kind==wm::BuildingKind::Trap && b.subtype==5) {
            const auto tile=source_.model().tileAt({b.x1,b.y1,b.z});
            result.completedTrack=tile?tile->completedTrack:0;
            q.completedTrack=result.completedTrack;
        }
        q.bridgeDirection=b.bridge.direction;q.bridgeRaised=b.bridge.raised;
        result.artwork=assets::resolveBuildingTiles(assets_->index,q);
        for(const auto& t:result.artwork.tiles) {
            const int slot=buildingSlotFor(b.kind,b.stage,t.sprite.page,(t.rawPalette || (result.artwork.gridLayout && t.foreground)) ? -1 : result.artwork.paletteRow,b.subtype,result.artwork.plannedHalfAlpha || t.halfAlpha);
            if(slot<0)continue;
            const auto rect=assets_->index.pixels(t.sprite);
            const auto alpha=buildingAlphaRegion(slot,rect.px,rect.py,rect.pw,rect.ph);
            if(!alpha || !alpha->footprintOpaque)continue;
            cells.emplace(t.lx,t.ly);
            if(t.foreground && mesher::isFurniturePiece(b.kind)) foreground.emplace(t.lx,t.ly);
        }
    }
    result.cells.assign(cells.begin(),cells.end());
    result.foreground.assign(foreground.begin(),foreground.end());
    return result;
}

godot::Vector3 Df3dWorld::unit_ground_support(int index) const {
    if(index<0 || index>=positions_.size())return {};
    auto p=positions_[index];p.y-=mesher::kFloorHeight+kUnitCubeHalfHeight;
    if(index<unitMotionFrom_.size() && index<unitMotionTo_.size()) {
        const auto a=unitMotionFrom_[index],b=unitMotionTo_[index];
        if(std::abs(b.g-a.g)>.0001f) {
            const float t=std::clamp(float((p.y-a.g)/(b.g-a.g)),0.f,1.f);
            return {0,ground_support(Vector3(a.r,a.g,a.b)).y*(1-t)+ground_support(Vector3(b.r,b.g,b.b)).y*t,0};
        }
        // Avoid subtractive rounding at large integer Z levels.
        p.y=a.g;
    }
    return ground_support(p);
}

godot::Vector3 Df3dWorld::unitCutoutPosition(int index, float bottom) const {
    auto position=positions_[index];
    const float level=float(std::get<3>(depthUnitContents_[index]));
    // Depth belongs to the authoritative tile; motion belongs to the sampled
    // animation. Retain its vertical displacement as well as its horizontal one.
    // Subtract the identical cube-center expression so stationary heights remain
    // bit-for-bit equal to the original level + floor + stack calculation.
    const float displacement=position.y-(level+(mesher::kFloorHeight+kUnitCubeHalfHeight));
    position.y=level+mesher::kFloorHeight+bottom+displacement;
    position.y+=unit_ground_support(index).y;
    return position;
}

void Df3dWorld::updateUnitCutoutPositions() {
    unitCutoutPositions_.resize(positions_.size());
    for(int i=0;i<positions_.size();++i)
        unitCutoutPositions_.set(i,unitCutoutPosition(i,unitDepthBottoms_[i]));
}

// --- per poll ---

void Df3dWorld::updateEntities() {
    // Building events: Added / Changed rebuild, Removed frees.
    const std::vector<wm::BuildingEvent> bev = source_.model().drainBuildingEvents();
    if (!bev.empty()) lastRenderedTick_=UINT64_MAX;
    buildingEvents_ += static_cast<int64_t>(bev.size());
    for (const wm::BuildingEvent& ev : bev) {
        const auto* current=source_.model().building(ev.id);
        const auto previous=machinePhaseSources_.find(ev.id);
        bool positionOnly=false;
        if(ev.change!=wm::EntityChange::Removed && current && (current->kind==wm::BuildingKind::Rollers || current->kind==wm::BuildingKind::WaterWheel || current->kind==wm::BuildingKind::Windmill || isTransmission(current->kind))) {
            updateMachinePosition(*current);
            // A restarted version denotes a new incarnation even if art matches.
            positionOnly=previous!=machinePhaseSources_.end() && current->version>previous->second.version &&
                sameMachineGeometry(previous->second,*current);
            if(positionOnly) {
                const auto built=builtBuildings_.find(ev.id);
                if(built!=builtBuildings_.end() && built->second.version==previous->second.version)
                    built->second.version=current->version;
                const auto art=buildingFootprintCache_.find(ev.id);
                if(art!=buildingFootprintCache_.end() && art->second.version==previous->second.version)
                    art->second.version=current->version;
            }
            machinePhaseSources_.insert_or_assign(ev.id,*current);
        } else {machinePhaseSources_.erase(ev.id);releaseMachinePosition(ev.id);}
        if(positionOnly)continue;
        layoutBuildingChanges_.insert(ev.id);
        // Version numbers restart after removal/readdition, even when events
        // coalesce to Changed. Every event retires any cached incarnation.
        perfFootprintEvictions_ += buildingFootprintCache_.erase(ev.id);
        if (ev.change == wm::EntityChange::Removed) {
            buildingSubmissionReasons_.erase(ev.id);
            auto it = builtBuildings_.find(ev.id);
            if (it != builtBuildings_.end()) {
                freeBuilding(it->second);
                builtBuildings_.erase(it);
            }
            continue;
        }
        enqueueBuilding(ev.id, submission::Semantic);
    }
    const std::vector<wm::ItemEvent> iev = source_.model().drainItemEvents();
    itemEvents_ += static_cast<int64_t>(iev.size());
    for (const auto& event : iev) {
        if (event.change==wm::EntityChange::Removed) spriteResources_.collectionPending=true;
        const auto* item = source_.model().item(event.id);
        if (event.change == wm::EntityChange::Added && item && item->kind == wm::ItemKind::Corpse && item->corpseUnitId >= 0) {
            if (corpseItemChanges_.size() < 1024) {
                godot::Dictionary entry; entry["item_id"] = int64_t(item->id);
                entry["unit_id"] = item->corpseUnitId; corpseItemChanges_.push_back(entry);
            } else ++corpseItemChangesDropped_;  // capped per drain; visible in presentation_perf_stats
        }
        layoutItemChanges_.insert(event.id);
        itemUpdateIDs_.insert(event.id);
    }
    // A corpse whose stack changed (rotting) resolves to its new
    // version on the next rebuild.
    const std::vector<wm::ItemAppearanceEvent> aev = source_.model().drainItemAppearanceEvents();
    itemAppearanceEvents_ += static_cast<int64_t>(aev.size());
    if (!aev.empty()) spriteResources_.collectionPending=true;
    for (const auto& event : aev) itemUpdateIDs_.insert(event.id);
    refreshGlyphDependencies();

    if (itemsDirty_ || !itemUpdateIDs_.empty() || !pendingItemComposites_.empty()) {
        updateItems();
        lastRenderedTick_ = UINT64_MAX;  // the script re-reads the item arrays with the units
    }

}

void Df3dWorld::drainBuildingGeometry() {
    PerfScope timer("building.queue_drain", &perfBuildingDrainMs_);
    if (topZ_ >= 0 && buildingQueueHead_ < buildingQueue_.size()) {
        const auto t0 = std::chrono::steady_clock::now();
        const auto deadline =
            t0 + std::chrono::microseconds(static_cast<int64_t>(entityBudgetMs_ * 1000.0));
        while (buildingQueueHead_ < buildingQueue_.size()) {
            if (entityBudgetMs_ > 0.0 && std::chrono::steady_clock::now() >= deadline) break;
            const wm::BuildingId id = buildingQueue_[buildingQueueHead_++];
            if (!buildingQueued_.erase(id)) continue;
            buildBuilding(id);
        }
        if (buildingQueueHead_ >= buildingQueue_.size()) {
            buildingQueue_.clear();
            buildingQueueHead_ = 0;
        }
        buildingLastMs_ = df3d::profiling::global().mode() == df3d::profiling::Mode::Off ? 0.0 :
            std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
        buildingTotalMs_ += buildingLastMs_;
    }


}

}  // namespace df3d_godot
