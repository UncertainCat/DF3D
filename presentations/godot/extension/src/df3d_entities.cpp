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

struct QuadArrays {
    godot::Vector3 ground;
    PackedVector3Array vertices, normals;
    PackedColorArray colors;
    PackedVector2Array uvs;
    PackedInt32Array indices;
    void addCutoutVertices(const std::vector<mesher::CutoutVertex>& vs,int x,int y,float h,float thickness,
                          const Color& region,const Color& tint) {
        df3d::profiling::Scope profile("building.pack_vertices", nullptr, df3d::profiling::detailed());
        if (vs.empty()) return;
        const int base=vertices.size();
        const int indexBase=indices.size();
        const int count=int(vs.size());
        vertices.resize(base+count); normals.resize(base+count);
        uvs.resize(base+count); colors.resize(base+count); indices.resize(indexBase+count);
        // One allocation/write handle per stream, not five engine calls per
        // vertex. Acquire handles only after all resizes; none outlive this job.
        auto* vertexOut=vertices.ptrw()+base;
        auto* normalOut=normals.ptrw()+base;
        auto* uvOut=uvs.ptrw()+base;
        auto* colorOut=colors.ptrw()+base;
        auto* indexOut=indices.ptrw()+indexBase;
        for(int i=0;i<int(vs.size());++i) {
            const auto& v=vs[i];
            vertexOut[i]=Vector3(x+.5f+v.x,h+ground.y+ground.x*v.x+ground.z*v.z+v.y*thickness/mesher::kCutoutThickness,y+.5f+v.z);
            uvOut[i]=Vector2(region.r+v.u*region.b,region.g+v.v*region.a);
            colorOut[i]=tint;normalOut[i]=Vector3(0,1,0);indexOut[i]=base+i;
        }
    }
    // A flat quad over DF tile (x, y) at Godot height h, textured with the
    // uv rectangle (u0, v0, u1, v1): image-down = DF south (+y), as the
    // terrain tops map their tiles. Clockwise seen from above = Godot's
    // front face.
    void addCutout(const Ref<ArrayMesh>& mesh,int x,int y,float h,float thickness,const Color& tint) {
        if(mesh.is_null() || mesh->get_surface_count()==0)return;
        Array a=mesh->surface_get_arrays(0);
        PackedVector3Array vs=a[Mesh::ARRAY_VERTEX]; PackedVector2Array ts=a[Mesh::ARRAY_TEX_UV]; PackedColorArray cs=a[Mesh::ARRAY_COLOR];
        const int base=vertices.size();
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
    if (ownBuildingRoot_ && buildingRoot_) {
        remove_child(buildingRoot_);
        godot::memdelete(buildingRoot_);
    }
    buildingRoot_ = root;
    ownBuildingRoot_ = false;
    enqueueBuildingWindow();
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
    enqueueBuildingWindow();
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

void Df3dWorld::enqueueBuilding(wm::BuildingId id, uint32_t reason) {
    if(submission::details().enabled)buildingSubmissionReasons_[id]|=reason;
    if (buildingQueued_.insert(id).second) buildingQueue_.push_back(id);
}

// Frees buildings that left the z window and queues those in it that
// carry no mesh (or an outdated one). Cheap: the store is a flat vector.
void Df3dWorld::enqueueBuildingWindow() {
    if (!source_.model().buildingsKnown() || topZ_ < 0) return;
    for (auto it = builtBuildings_.begin(); it != builtBuildings_.end();) {
        if (!zInWindow(it->second.z)) {
            freeBuilding(it->second);
            it = builtBuildings_.erase(it);
        } else {
            ++it;
        }
    }
    source_.model().forEachBuilding([&](const wm::Building& b) {
        if (!zInWindow(b.z)) return;
        auto it = builtBuildings_.find(b.id);
        if (it != builtBuildings_.end() && it->second.version == b.version) return;
        enqueueBuilding(b.id, submission::Window);
    });
}

void Df3dWorld::freeBuilding(BuiltBuilding& b) {
    if (b.node) {
        buildingBatches_.erase(b.id);
        get_building_root()->remove_child(b.node);
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
    if (!zInWindow(b->z)) {
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
    if (b->stage == wm::BuildingStage::Planned) {
        tint = Color(1, 1, 1, 0.4f);
        kind = kSurfGhost;
    } else if (b->stage == wm::BuildingStage::InProgress && !r.stageArt) {
        tint = Color(0.6f, 0.6f, 0.6f, 1);
    }
    const bool piece = mesher::isFurniturePiece(b->kind);
    const auto depthAt=[&](int,int y) {
        return piece?mesher::buildingDepth(b->y1,y):mesher::DepthInterval{mesher::installationArtBottom(b->kind),0};
    };
    std::map<SurfaceKey, QuadArrays> surfaces;
    godot::Array drawRecords;
    int quads = 0;
    if (r.found) {
        using DrawCell=std::pair<int,int>;
        std::map<DrawCell,std::vector<std::pair<int,Color>>> tiles;
        for (const assets::BuildingTile& t : r.tiles) {
            const wm::TilePos p{b->x1+t.lx,b->y1+t.ly,b->z};
            if(!tileVisible(p))continue;
            const int slot=slotFor(t.sprite.page,r.paletteRow,false);if(slot<0)continue;
            const TextureSlot* found=spriteResources_.slots.find(slot);
            ERR_CONTINUE_MSG(!found, "stale building sprite slot " + godot::String::num_int64(slot));
            const auto& s=*found;const auto px=assets_->index.pixels(t.sprite);
            tiles[{p.x,p.y}].push_back({slot,Color(float(px.px)/s.width,float(px.py)/s.height,float(px.pw)/s.width,float(px.ph)/s.height)});
        }
        struct Fragment {int slot,w,h;Color region;mesher::DepthInterval depth;std::shared_ptr<const BuildingAlphaRegion> alpha;};
        std::map<DrawCell,Fragment> fragments;
        for(const auto& [pos,layers]:tiles) {
            const auto [x,y]=pos;
            const int slot=layers.size()==1?layers[0].first:compositeBuildingTile(layers);
            const Color region=layers.size()==1?layers[0].second:Color(0,0,1,1);
            auto depth=depthAt(x,y);
            const TextureSlot* layer=slot>=0?spriteResources_.slots.find(slot):nullptr;
            ERR_CONTINUE_MSG(!layer || layer->texture.is_null(), "stale building tile slot " + godot::String::num_int64(slot));
            auto& image=spriteResources_.images[slot];if(image.is_null())image=layer->texture->get_image();
            if(image.is_null())continue;
            const int iw=image->get_width(),ih=image->get_height();
            const int ox=std::lround(region.r*iw),oy=std::lround(region.g*ih);
            const int w=std::lround(region.b*iw),h=std::lround(region.a*ih);
            auto alpha=buildingAlphaRegion(slot,ox,oy,w,h);
            if(!alpha || !alpha->geometryOpaque)continue;
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
                    cached=cache.emplace(std::move(key),mesher::cutoutMesh(f.alpha->pixels,f.w,f.h,covers)).first;
                }
                surfaces[{slot,kind}].addCutoutVertices(cached->second,x,y,base,depth.thickness,region,tint);
            }
            else surfaces[{slot,kind}].add(x,y,base,tint,uv);
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
                    if(piece) surfaces[SurfaceKey{glyphSlot,kind}].addCutout(sprite_cutout_mesh(glyphSlot,Color(uv[0],uv[1],uv[2]-uv[0],uv[3]-uv[1])),x,y,base,depth.thickness,c);
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
    for (auto& [sk, arr] : surfaces) {
        PerfScope uploadProfile("building.upload_surface", nullptr, df3d::profiling::detailed());
        Array arrays;
        arrays.resize(Mesh::ARRAY_MAX);
        arrays[Mesh::ARRAY_VERTEX] = arr.vertices;
        arrays[Mesh::ARRAY_NORMAL] = arr.normals;
        arrays[Mesh::ARRAY_COLOR] = arr.colors;
        if (sk.slot >= 0) arrays[Mesh::ARRAY_TEX_UV] = arr.uvs;
        arrays[Mesh::ARRAY_INDEX] = arr.indices;
        batchArrays.push_back(arrays);
        detail.surface(arrays);
        const int surface = mesh->get_surface_count();
        if (piece && sk.slot >= 0) {
            submission::meshSurface(mesh, arrays, submission::MeshSite::Building);
            // Piece geometry already owns its tint and atlas UVs. The material
            // depends only on its texture slot and compositing mode, allowing
            // different furniture silhouettes to share a single batch surface.
            auto& mat = buildingPieceMaterials_[sk];
            if (mat.is_null()) {
                mat.instantiate();
                mat->set_shader(godot::ResourceLoader::get_singleton()->load(sk.kind == kSurfGhost ? "res://shaders/standee_ghost.gdshader" : "res://shaders/unit_sprite.gdshader"));
                godot::Dictionary parameters;
                const TextureSlot* sprite=spriteResources_.slots.find(sk.slot);
                ERR_CONTINUE_MSG(!sprite || sprite->texture.is_null(), "stale building piece slot " + godot::String::num_int64(sk.slot));
                parameters["sprite_tex"]=sprite->texture;
                parameters["sprite_cell"]=sprite->texture->get_meta("world_cell", Vector2());
                configureImmutableMaterial(mat,parameters);
            }
            mesh->surface_set_material(surface, mat);
        } else {
            submission::meshSurface(mesh, arrays, submission::MeshSite::Building);
            mesh->surface_set_material(surface, materialFor(sk));
        }
    }
    mesh->set_meta("df3d_batch_arrays", batchArrays);
    MeshInstance3D* node = memnew(MeshInstance3D);
    node->set_name(String("building_") + String::num_int64(id));
    if (b->kind == wm::BuildingKind::Civzone) node->set_visible(zoneOverlaysVisible_);
    node->set_mesh(mesh);
    node->set_meta("df3d_draw_fragments",drawRecords);
    node->set_meta("df3d_building_kind",String(wm::buildingKindName(b->kind)));
    if (piece) node->set_extra_cull_margin(1.1f);
    get_building_root()->add_child(node);
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
    // semantics. Keep their individual draws (including transparent sorting).
    if (!building || building->kind == wm::BuildingKind::Civzone ||
        building->stage == wm::BuildingStage::Planned) {
        buildingBatches_.erase(wm::BuildingId(id));
        return;
    }
    // Whole installations remain intact, including artwork spilling outside
    // their footprint. Cells bound batch culling; source meshes retain exact
    // per-building geometry for picking and presentation transformations.
    buildingBatches_.put(wm::BuildingId(id), node,
        godot::Vector3i(building->x1 / 32, building->z / 4, building->y1 / 32));
}

// --- items ---

// All source layers become one top image BEFORE silhouette extrusion. This
// removes the coincident contour walls of forbidden/state-overlay furniture.
int Df3dWorld::compositeBuildingTile(const std::vector<std::pair<int, Color>>& layers) {
    if(layers.empty()) return -1;
    std::string key;
    struct Source {int slot,x,y,w,h;};
    std::vector<Source> sources;
    int w=0,h=0;
    for(const auto& [slot,region]:layers) {
        const TextureSlot* found=spriteResources_.slots.find(slot);
        ERR_FAIL_COND_V_MSG(!found || found->texture.is_null(), -1, "stale composite layer slot " + godot::String::num_int64(slot));
        const auto& s=*found;
        const int x=std::lround(region.r*s.width), y=std::lround(region.g*s.height);
        const int sw=std::lround(region.b*s.width), sh=std::lround(region.a*s.height);
        key+=std::to_string(slot)+":"+std::to_string(x)+":"+std::to_string(y)+":"+std::to_string(sw)+":"+std::to_string(sh)+";";
        sources.push_back({slot,x,y,sw,sh});
        w=std::max(w,sw);h=std::max(h,sh);
    }
    if(auto it=spriteResources_.buildings.find(key);it!=spriteResources_.buildings.end())return it->second;
    auto image=godot::Image::create(w,h,false,godot::Image::FORMAT_RGBA8);
    image->fill(Color(0,0,0,0));
    for(const auto& src:sources) {
        auto& source=spriteResources_.images[src.slot];if(source.is_null())source=spriteResources_.slots.find(src.slot)->texture->get_image();
        ERR_FAIL_COND_V_MSG(source.is_null(), -1, "composite layer slot without image");
        auto layer=source->get_region(godot::Rect2i(src.x,src.y,src.w,src.h));
        if(layer->get_width()!=w || layer->get_height()!=h)layer->resize(w,h,godot::Image::INTERPOLATE_NEAREST);
        image->blend_rect(layer,godot::Rect2i(0,0,w,h),godot::Vector2i(0,0));
    }
    image->fix_alpha_edges();
    image->generate_mipmaps();
    TextureSlot slot;slot.width=w;slot.height=h;slot.texture=submission::texture(image, submission::TextureSite::BuildingArt,true);
    const int id=spriteResources_.slots.add(std::move(slot));
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
        result.artwork=assets::resolveBuildingTiles(assets_->index,q);
        for(const auto& t:result.artwork.tiles) {
            const int slot=slotFor(t.sprite.page,result.artwork.paletteRow,false);
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
    for (const auto& event : bev) layoutBuildingChanges_.insert(event.id);
    if (!bev.empty()) lastRenderedTick_=UINT64_MAX;
    buildingEvents_ += static_cast<int64_t>(bev.size());
    for (const wm::BuildingEvent& ev : bev) {
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
