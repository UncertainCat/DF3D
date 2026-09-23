#include "submission_uploads.h"
#include "submission_details.h"
#include "df3d_world.h"
#include "terrain_occluders.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include "df3d_assets/ground_spatter.h"
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <string>
#include <stdexcept>
#include <vector>

#include "df3d_mesher/block_mesher.h"
#include "df3d_mesher/piece_policy.h"
#include "df3d_mesher/unit_presentation.h"
#include "df3d_mesher/minimap.h"

namespace df3d_godot {

using godot::Array;
using godot::ArrayMesh;
using godot::Color;
using godot::Dictionary;
using godot::Image;
using godot::Mesh;
using godot::MeshInstance3D;
using godot::Node3D;
using godot::PackedByteArray;
using godot::PackedColorArray;
using godot::PackedInt32Array;
using godot::PackedVector2Array;
using godot::PackedVector3Array;
using godot::Ref;
using godot::String;
using godot::Vector2;
using godot::Vector3;
using godot::Vector3i;

namespace mesher = df3d::mesher;
namespace assets = df3d::assets;

namespace {

// DF (x, y, z) -> Godot (x, z, y) is a reflection: the mesher's CCW winding becomes Godot's CW front faces, so vertex order is kept.
Vector3 toGodot(mesher::Vec3 v) { return Vector3(v.x, v.z, v.y); }

// --- placeholder palette (layer 4; used only for faces no tile resolves) ---

Color materialBase(wm::MaterialKind k) {
    using M = wm::MaterialKind;
    switch (k) {
        case M::Stone: return Color(0.47f, 0.47f, 0.50f);
        case M::Soil: return Color(0.51f, 0.38f, 0.24f);
        case M::Mineral: return Color(0.75f, 0.59f, 0.24f);
        case M::Gem: return Color(0.35f, 0.75f, 0.78f);
        case M::Ice: return Color(0.75f, 0.84f, 0.92f);
        case M::Wood: return Color(0.43f, 0.28f, 0.16f);
        case M::Plant: return Color(0.27f, 0.55f, 0.24f);
        case M::Grass: return Color(0.27f, 0.51f, 0.20f);
        case M::Constructed: return Color(0.59f, 0.59f, 0.63f);
        case M::Water: return Color(0.16f, 0.31f, 0.63f);
        case M::Magma: return Color(0.78f, 0.27f, 0.08f);
        case M::None:
        case M::Unknown: break;
    }
    return Color(0.35f, 0.30f, 0.38f);
}

Color scale(Color c, float k) { return Color(c.r * k, c.g * k, c.b * k, c.a); }
Color add(Color c, float d) {
    return Color(std::min(1.0f, c.r + d), std::min(1.0f, c.g + d), std::min(1.0f, c.b + d), c.a);
}

// Only shading: a per-face-direction multiplier baked into vertex colour (tops full, east brightest side, west darkest, bottoms dark).
float directionalShade(mesher::FaceDir dir) {
    switch (dir) {
        case mesher::FaceDir::PosZ: return 1.0f;
        case mesher::FaceDir::NegZ: return 0.45f;
        case mesher::FaceDir::Slope: return 0.92f;
        case mesher::FaceDir::Cross: return 1.0f;
        case mesher::FaceDir::PosX: return 0.88f;
        case mesher::FaceDir::NegX: return 0.68f;
        default: return 0.80f;  // PosY (south), NegY (north)
    }
}

// Terrain shaders: unshaded, two-sided with black back faces (a clipped camera sees black, not rooms beyond); `textured` multiplies the page; cutout variant alpha-scissors.

Color faceColor(const mesher::FaceTag& tag) {
    using S = wm::TileShape;
    if (tag.part == mesher::FacePart::Liquid) {
        const float t = static_cast<float>(tag.liquidLevel) / 7.0f;
        if (tag.liquid == wm::LiquidKind::Magma) return Color(1.0f, 0.42f + 0.1f * t, 0.05f, 0.92f);
        return Color(0.16f, 0.36f, 0.85f, 0.45f + 0.35f * t);
    }
    Color c = materialBase(tag.materialKind);
    if (tag.part == mesher::FacePart::Feature) {
        switch (tag.shape) {
            case S::StairUp:
            case S::StairDown:
            case S::StairUpDown: c = Color(0.90f, 0.86f, 0.45f); break;
            case S::Boulder:
            case S::Pebbles: c = scale(c, 0.8f); break;
            case S::TreeBranch:
            case S::Shrub:
            case S::Sapling: c = Color(0.30f, 0.58f, 0.24f); break;
            default: break;
        }
    } else {
        switch (tag.shape) {
            case S::Floor: c = scale(c, 0.78f); break;
            case S::Ramp: c = scale(c, 0.9f); break;
            case S::Fortification: c = scale(c, 0.85f); break;
            case S::TreeTrunk: c = Color(0.40f, 0.26f, 0.14f); break;
            case S::Unknown: c = Color(0.55f, 0.20f, 0.55f); break;
            default: break;
        }
    }
    if (tag.flags & wm::kTileEngraved) c = add(c, 0.16f);
    else if (tag.flags & wm::kTileSmooth) c = add(c, 0.08f);
    if (tag.flags & wm::kTileDigDesignated) c = c.lerp(Color(0.85f, 0.65f, 0.15f), 0.6f);
    return scale(c, directionalShade(tag.dir));
}

// Textured face vertex colour: white shaded by direction, amber for dig designations.
Color texturedTint(const mesher::FaceTag& tag) {
    Color c(1, 1, 1, 1);
    if (tag.part == mesher::FacePart::Liquid) {
        const float t = static_cast<float>(tag.liquidLevel) / 7.0f;
        c.a = tag.liquid == wm::LiquidKind::Magma ? 0.95f : 0.55f + 0.3f * t;
    }
    if (tag.flags & wm::kTileDigDesignated) c = c.lerp(Color(1.0f, 0.7f, 0.2f), 0.5f);
    return scale(c, directionalShade(tag.dir));
}

// UV convention (README "UV / orientation"): tops/bottoms/ramps map the tile straight down; vertical faces stand it upright with image-up = +z.
Vector2 faceUv(const mesher::Face& f, const mesher::Vec3& v, float minX, float minY, float minZ) {
    const bool leaf = f.tag.shape == wm::TileShape::TreeBranch &&
                      f.tag.part == mesher::FacePart::Feature;
    const auto local = [leaf](float c) {
        return std::clamp(leaf ? mesher::leafTextureCoordinate(c) : c, 0.0f, 1.0f);
    };
    const float lx = local(v.x - minX);
    const float ly = local(v.y - minY);
    const float lz = local(v.z - minZ);
    switch (f.tag.dir) {
        case mesher::FaceDir::PosZ:
        case mesher::FaceDir::NegZ:
        case mesher::FaceDir::Slope: return Vector2(lx, ly);
        case mesher::FaceDir::PosX:
        case mesher::FaceDir::NegX: return Vector2(ly, 1.0f - lz);
        case mesher::FaceDir::Cross:
            return Vector2(mesher::crossPlaneU(f.normal.x, lx, ly), 1.0f - lz);
        default: return Vector2(lx, 1.0f - lz);  // PosY, NegY
    }
}

struct SurfaceArrays {
    PackedVector3Array vertices, normals;
    PackedColorArray colors;
    PackedVector2Array uvs, spatterUvs;
    PackedInt32Array indices;
    bool textured = false;
    void add(const mesher::Face& f, const Color& color, const float* uvRect, const float* spatterRect = nullptr) {
        const int32_t base = static_cast<int32_t>(vertices.size());
        const Vector3 n = toGodot(f.normal);
        float minX = 1e9f, minY = 1e9f, minZ = 1e9f;
        for (const mesher::Vec3& v : f.v) {
            minX = std::min(minX, v.x);
            minY = std::min(minY, v.y);
            minZ = std::min(minZ, v.z);
        }
        // The tile origin: faces on a tile's far boundary (x = tx + 1) do not
        // use that axis, so flooring the minimum is safe.
        minX = std::floor(minX + 1e-4f);
        minY = std::floor(minY + 1e-4f);
        minZ = std::floor(minZ + 1e-4f);
        for (const mesher::Vec3& v : f.v) {
            vertices.push_back(toGodot(v));
            normals.push_back(n);
            colors.push_back(color);
            if (spatterRect) {
                const Vector2 t = faceUv(f, v, minX, minY, minZ);
                spatterUvs.push_back(Vector2(spatterRect[0] + (spatterRect[2]-spatterRect[0])*t.x,
                                            spatterRect[1] + (spatterRect[3]-spatterRect[1])*t.y));
            }
            if (uvRect) {
                const Vector2 t = faceUv(f, v, minX, minY, minZ);
                uvs.push_back(Vector2(uvRect[0] + (uvRect[2] - uvRect[0]) * t.x,
                                      uvRect[1] + (uvRect[3] - uvRect[1]) * t.y));
            }
        }
        for (int32_t i : {0, 1, 2, 0, 2, 3}) indices.push_back(base + i);
    }
};

}  // namespace

Df3dWorld::Df3dWorld() : source_([] {
    wm::WorldModelConfig config;
    config.collectLifecycleEvents = false; // The viewer samples residents, not lifecycle transitions.
    return config;
}()) {}

Df3dWorld::~Df3dWorld() = default;

double Df3dWorld::nowSeconds() const {
    return std::chrono::duration<double>(std::chrono::steady_clock::now() - epoch_).count();
}

// --- assets ---

// --- sources ---

void Df3dWorld::detach_live() { source_.detachLive(); }

bool Df3dWorld::attach() {
    wm::BufferedWorldConfig config;
    config.collectTimings = df3d::profiling::global().mode() != df3d::profiling::Mode::Off;
    if (df3d::profiling::global().mode() == df3d::profiling::Mode::Deep) {
        config.timingObserver = [](const char* name, double startUs, double durationUs) {
            df3d::profiling::global().record(name, startUs, durationUs);
        };
    }
    const auto epoch = epoch_;
    config.clock = [epoch] { return std::chrono::duration<double>(std::chrono::steady_clock::now()-epoch).count(); };
    const bool wasLive = source_.live();
    const bool opened = source_.attach(std::move(config));
    lastError_ = String::utf8(source_.error().c_str());
    if (opened && !wasLive) sessionSeen_ = UINT64_MAX;
    return opened;
}

bool Df3dWorld::load_fixture(const String& path) {
    const double start = df3d::profiling::timestampUs();
    const bool opened = source_.loadFixture(path.utf8().get_data(), nowSeconds());
    lastError_ = String::utf8(source_.error().c_str());
    if (!opened) return false;
    godot::UtilityFunctions::print("df3d: fixture ", path, " opened: ", int64_t(source_.fixtureSnapshots()), " snapshots");
    if (df3d::profiling::global().mode() != df3d::profiling::Mode::Off)
        godot::UtilityFunctions::print("df3d: fixture open ", df3d::profiling::elapsedMs(start), " ms");
    return true;
}

void Df3dWorld::set_fixed_render_tick(double tick) {
    if (!source_.setFixedTick(tick)) lastError_ = String::utf8(source_.error().c_str());
}

bool Df3dWorld::is_attached() const { return source_.attached(); }

String Df3dWorld::unit_species(int64_t unit_id) const {
    const std::string* s = source_.model().unitSpecies(static_cast<wm::UnitId>(unit_id));
    return s ? String(s->c_str()) : String();
}

Vector3i Df3dWorld::map_size() const {
    const wm::TilePos d = source_.model().mapSize();
    return Vector3i(d.x, d.z, d.y);  // same axis mapping as positions
}

Dictionary Df3dWorld::minimap_data(int z, int resolution) {
    Dictionary out;
    const auto size=source_.model().mapSize();
    out["map_size"]=godot::Vector2i(size.x,size.y);
    out["generation"]=static_cast<int64_t>(source_.model().sessionGeneration());
    out["terrain_version"]=static_cast<int64_t>(source_.model().terrainVersion());
    out["z"]=z;
    if(!assets_ || !source_.model().hasTerrain() || size.x<=0 || size.y<=0 || z<0 || z>=size.z) {
        minimapTexture_.unref();
        out["available"]=false;
        return out;
    }
    resolution=std::clamp(resolution,16,256);
    const bool levelChanged = minimapLevel_.update(source_.model(), z);
    if(minimapTexture_.is_null() || levelChanged || minimapZ_!=z || minimapResolution_!=resolution) {
        const double scale=std::min(1.0,static_cast<double>(resolution)/std::max(size.x,size.y));
        const int w=std::max(1,static_cast<int>(std::round(size.x*scale)));
        const int h=std::max(1,static_cast<int>(std::round(size.y*scale)));
        std::vector<int8_t> pixels(size_t(w)*h, -1);
        for(int y=0;y<h;++y) for(int x=0;x<w;++x) {
            const int index=mesher::minimapPalette(source_.model().tileAt({mesher::minimapSample(x,w,size.x),mesher::minimapSample(y,h,size.y),z}));
            pixels[size_t(y)*w+x] = static_cast<int8_t>(index);
        }
        minimapSamples_ += pixels.size(); ++minimapEvaluations_;
        // Water depth/order/material metadata may change without changing the
        // overview's palette output. Keep the existing GPU texture in that case.
        if(minimapTexture_.is_null() || minimapTexture_->get_width()!=w || minimapTexture_->get_height()!=h || pixels!=minimapPixels_) {
            Ref<Image> image=Image::create(w,h,false,Image::FORMAT_RGBA8);
            image->fill(Color(0,0,0,0));
            for(int y=0;y<h;++y) for(int x=0;x<w;++x) {
                const int index=pixels[size_t(y)*w+x];
                if(index<0)continue;
                const auto c=assets_->classicPalette.colors[static_cast<size_t>(index)];
                image->set_pixel(x,y,Color(c.r/255.0f,c.g/255.0f,c.b/255.0f,1));
            }
            minimapTexture_=submission::texture(image, submission::TextureSite::Minimap); ++minimapBuilds_;
        }
        minimapPixels_=std::move(pixels);
        minimapZ_=z; minimapResolution_=resolution;
    } else ++minimapCacheHits_;
    out["available"]=true;
    out["texture"]=minimapTexture_;
    out["build_count"]=static_cast<int64_t>(minimapBuilds_);
    return out;
}

Dictionary Df3dWorld::auxiliary_cache_stats() const {
    Dictionary out;
    out["minimap_builds"]=int64_t(minimapBuilds_);
    out["minimap_evaluations"]=int64_t(minimapEvaluations_);
    out["minimap_cache_hits"]=int64_t(minimapCacheHits_);
    out["minimap_tile_samples"]=int64_t(minimapSamples_);
    out["minimap_block_checks"]=int64_t(minimapLevel_.blockChecks);
    out["designation_builds"]=int64_t(designationBuilds_);
    out["designation_cache_hits"]=int64_t(designationCacheHits_);
    out["designation_tile_samples"]=int64_t(designationSamples_);
    out["designation_block_checks"]=int64_t(designationLevel_.blockChecks);
    return out;
}

int64_t Df3dWorld::bridge_tick() const {
    if (source_.live()) return static_cast<int64_t>(source_.liveStats().bridgeTick);
    return static_cast<int64_t>(source_.model().latestTick());
}

double Df3dWorld::floor_height() { return mesher::kFloorHeight; }

Dictionary Df3dWorld::tile_hover_info(const Vector3i& tile) const {
    Dictionary out;
    const auto t = source_.model().tileAt({tile.x, tile.y, tile.z});
    // Inspection must never disclose hidden material, even with debug reveal.
    if (!t || (t->flags & wm::kTileHidden)) return out;
    out["shape"] = String(wm::tileShapeName(t->shape));
    out["outside"] = bool(t->flags & wm::kTileOutside);
    out["material"] = String(std::string(source_.model().materialName(t->material)).c_str());
    out["material_kind"] = String(wm::materialKindName(t->materialKind));
    out["smooth"] = bool(t->flags & wm::kTileSmooth);
    out["engraved"] = bool(t->flags & wm::kTileEngraved);
    out["liquid"] = String(wm::liquidKindName(t->liquidKind));
    out["liquid_level"] = int(t->liquidLevel);
    return out;
}

String Df3dWorld::tile_summary(const Vector3i& tile) const {
    if (!source_.model().hasTerrain()) return String("no terrain");
    const wm::TilePos p{tile.x, tile.y, tile.z};
    const wm::TilePos m = source_.model().mapSize();
    if (p.x < 0 || p.y < 0 || p.z < 0 || p.x >= m.x || p.y >= m.y || p.z >= m.z)
        return String("outside the map");
    const std::optional<wm::TileState> t = source_.model().tileAt(p);
    if (!t) return String("block not observed");
    char buf[256];
    std::snprintf(buf, sizeof buf, "%s %s %s%s%s", wm::tileShapeName(t->shape),
                  wm::materialKindName(t->materialKind),
                  std::string(source_.model().materialName(t->material)).c_str(),
                  (t->flags & wm::kTileHidden) ? " hidden" : "",
                  inWindow(wm::blockOf(p)) ? "" : " (outside the z window)");
    return String(buf);
}

Array Df3dWorld::items_at_tile(const Vector3i& tile) const {
    Array out;
    const wm::TilePos p{tile.x, tile.y, tile.z};
    const auto t = source_.model().tileAt(p);
    if (!t || (t->flags & wm::kTileHidden)) return out;
    for (const auto* item : source_.model().itemsAtTile(p)) {
        Dictionary d;
        d["id"] = static_cast<int64_t>(item->id);
        d["name"] = String(wm::itemKindName(item->kind));
        d["stack"] = static_cast<int64_t>(item->stack);
        d["forbidden"] = bool(item->flags & wm::kItemForbidden);
        d["dump"] = bool(item->flags & wm::kItemDump);
        d["melt"] = bool(item->flags & wm::kItemMelt);
        out.push_back(d);
    }
    return out;
}

Vector3i Df3dWorld::item_tile(int64_t id) const {
    if (id < 0 || id > 0xFFFFFFFFll) return Vector3i(-1, -1, -1);
    const auto* item = source_.model().item(static_cast<wm::ItemId>(id));
    if (!item) return Vector3i(-1, -1, -1);
    const auto tile = source_.model().tileAt(item->pos);
    if (!tile || (tile->flags & wm::kTileHidden)) return Vector3i(-1, -1, -1);
    return Vector3i(item->pos.x, item->pos.y, item->pos.z);
}

double Df3dWorld::selection_height(const Vector3i& tile) const {
    const auto t = source_.model().tileAt({tile.x, tile.y, tile.z});
    if (!t) return -1.0;
    return (t->shape == wm::TileShape::Wall || (t->flags & wm::kTileHidden)) ? 1.0 : mesher::kFloorHeight;
}

Vector3i Df3dWorld::pick_tile(const Vector3& origin, const Vector3& direction, int z) const {
    const auto size = source_.model().mapSize();
    const Vector3i invalid(-1, -1, -1);
    if (z < 0 || z >= size.z || direction.y >= -0.00001f) return invalid;
    const double high = (z + 1.0 - origin.y) / direction.y;
    const double low = (z + mesher::kFloorHeight - origin.y) / direction.y;
    if (low < 0) return invalid;
    const Vector3 a = origin + direction * std::max(0.0, high);
    const Vector3 b = origin + direction * low;
    const int x1 = std::max(0, static_cast<int>(std::floor(std::min(a.x, b.x))));
    const int x2 = std::min(size.x - 1, static_cast<int>(std::floor(std::max(a.x, b.x))));
    const int y1 = std::max(0, static_cast<int>(std::floor(std::min(a.z, b.z))));
    const int y2 = std::min(size.y - 1, static_cast<int>(std::floor(std::max(a.z, b.z))));
    double nearest = low + 1.0;
    Vector3i hit = invalid;
    for (int y = y1; y <= y2; ++y) for (int x = x1; x <= x2; ++x) {
        const double height = selection_height(Vector3i(x, y, z));
        if (height < 0) continue;
        const double distance = (z + height - origin.y) / direction.y;
        if (distance < 0 || distance >= nearest) continue;
        const Vector3 p = origin + direction * distance;
        if (p.x >= x && p.x < x + 1 && p.z >= y && p.z < y + 1) {
            hit = Vector3i(x, y, z);
            nearest = distance;
        }
    }
    return hit;
}

Array Df3dWorld::designation_tiles(int z) const {
    Array out;
    const auto size = source_.model().mapSize();
    if (z < 0 || z >= size.z) return out;
    if (!designationLevel_.update(source_.model(), z)) {
        ++designationCacheHits_;
        return designationTiles_.duplicate(true);
    }
    ++designationBuilds_;
    for (int y = 0; y < size.y; ++y) for (int x = 0; x < size.x; ++x) {
        ++designationSamples_;
        const auto t = source_.model().tileAt({x, y, z});
        if (!t) continue;
        // Designations stay visible on unexplored terrain without revealing its shape or material.
        const int kind = (t->flags & wm::kTileEngraveDesignated) ? 3 :
                         (t->flags & wm::kTileSmoothDesignated) ? 2 :
                         (t->flags & wm::kTileDigDesignated) ? 1 : 0;
        if (kind || t->track || (t->traffic && !(t->flags & wm::kTileHidden)) || t->warnings) {
            Dictionary d;
            d["tile"] = Vector3i(x, y, z);
            d["kind"] = kind;
            auto operation=t->designation;
            if(operation==wm::DesignationKind::None)
                operation=kind==3?wm::DesignationKind::Engrave:kind==2?wm::DesignationKind::Smooth:wm::DesignationKind::Unknown;
            d["operation"] = int(operation);
            d["priority"] = int(t->designationPriority);
            d["marker"] = t->designationMarker;
            d["auto"] = bool(t->flags & wm::kTileDigAuto);
            d["track"] = int(t->track);
            d["traffic"] = (t->flags & wm::kTileHidden) ? 0 : int(t->traffic);
            d["warnings"] = int(t->warnings);
            d["height"] = selection_height(Vector3i(x, y, z));
            out.push_back(d);
        }
    }
    designationTiles_ = out.duplicate(true);
    return out;
}

// --- per-frame ---

bool Df3dWorld::poll() {
    ++perfPollCount_;
    if(submission::details().enabled)submission::details().poll=perfPollCount_;
    PerfScope pollTimer{"world.poll", &perfPollMs_};
    const double now = nowSeconds();
    wm::WorldSource::Update update;
    {
        PerfScope adoptionTimer{"world.adopt", &perfAdoptionMs_};
        update = source_.poll(now);
    }
    if (!source_.error().empty()) lastError_ = String::utf8(source_.error().c_str());
    const bool sourceChanged = update.changed;
    if (source_.model().sessionGeneration() != sessionSeen_) {
        sessionSeen_ = source_.model().sessionGeneration();
        resetTerrain();
        topZ_ = -1;
        builtMapSize_ = {};
        resetEntities();
        faceLooks_.clear();
        unitLooks_.clear();
        spriteResources_.resetSession();
        glyphVersionSeen_ = 0;
        positions_.clear(); colors_.clear(); ids_.clear();
        unitJobs_.clear(); unitStatusFlags_.clear(); unitMotionSegments_.clear();
        unitAttackIds_.clear(); unitAttackTargets_.clear(); unitAttackTicks_.clear();
        spriteSlots_.clear(); spriteRegions_.clear(); spriteSizes_.clear(); unitScaleParams_.clear(); spriteKinds_.clear();
        itemPositions_.clear(); itemIds_.clear(); itemSlots_.clear();
        itemRegions_.clear(); itemSizes_.clear(); itemThicknesses_.clear(); itemStackOrdinals_.clear(); itemColors_.clear(); itemKinds_.clear();
        ++itemRenderRevision_;
        itemsDrawn_ = 0;
        lastRenderedTick_ = UINT64_MAX;
        // Session-owned resources retire together; handles are never reused.
    }
    if (!update.available || !source_.model().hasData()) return false;

    renderTick_ = update.renderTick;

    { PerfScope timer{"terrain.update", &perfTerrainUpdateMs_}; updateTerrain(); }
    { PerfScope timer{"entities.update", &perfEntityUpdateMs_}; updateEntities(); }

    // A changed stack resolves to a new version on the next rebuild, even with a frozen clock.
    const std::vector<wm::AppearanceEvent> appearanceEvents = source_.model().drainAppearanceEvents();
    if (!appearanceEvents.empty()) {
        spriteResources_.collectionPending=true;
        appearanceEvents_ += static_cast<int64_t>(appearanceEvents.size());
        lastRenderedTick_ = UINT64_MAX;
    }

    // Projectile positions have their own continuous evaluation; a unit's
    // resident interval must not throttle their rendering.
    const auto projectiles=source_.model().projectilesAt(renderTick_);
    projectileIds_.resize(projectiles.size());projectilePositions_.resize(projectiles.size());projectileDirections_.resize(projectiles.size());
    for (int i=0;i<int(projectiles.size());++i) {
        const auto& p=projectiles[i];
        projectileIds_.set(i,int64_t(p.id));
        projectilePositions_.set(i,Vector3(p.pos.x+.5f,p.pos.z+.6f,p.pos.y+.5f));
        projectileDirections_.set(i,Vector3(p.direction.x,p.direction.z,p.direction.y));
    }
    // Clock-only frames between integral DF ticks need only interaction positions, not a visual-delta scan.
    // Replay/rewind ticks may be negative or non-finite; clamp before the
    // unsigned conversion (UB otherwise) and keep UINT64_MAX free as the
    // "never rendered" sentinel.
    const double flooredTick = std::floor(renderTick_);
    const uint64_t tickNow = !(flooredTick > 0.0) ? 0
        : flooredTick >= 18446744073709551615.0 ? UINT64_MAX - 1
        : static_cast<uint64_t>(flooredTick);
    if (!sourceChanged && tickNow == lastRenderedTick_) {
        for (int i=0; i<positions_.size(); ++i) {
            const auto first=unitMotionFrom_[i], last=unitMotionTo_[i];
            const auto epochs=unitMotionEpochs_[i];
            const double start=double(epochs.x)*4096.0+first.a;
            const double end=double(epochs.y)*4096.0+last.a;
            const float phase=end>start?float(std::clamp((renderTick_-start)/(end-start),0.0,1.0)):0.0f;
            positions_.set(i,Vector3(first.r,first.g,first.b).lerp(Vector3(last.r,last.g,last.b),phase)
                +Vector3(0,mesher::kFloorHeight+kUnitCubeHalfHeight,0));
        }
        updateUnitCutoutPositions();
        flushPresentationGeometry();
        return false;
    }
    lastRenderedTick_ = tickNow;
    {
        ++perfUnitCount_;
        PerfScope unitTimer{"units.prepare", &perfUnitMs_};

        positions_.clear();
        ids_.clear();
        unitJobs_.clear(); unitStatusFlags_.clear();
        unitMotionFrom_.clear(); unitMotionTo_.clear(); unitMotionEpochs_.clear();
        unitMotionSegments_.clear();
        unitAttackIds_.clear(); unitAttackTargets_.clear(); unitAttackTicks_.clear();
        compositedUnits_ = simpleUnits_ = cubeUnits_ = compositePending_ = glyphUnits_ = 0;
        compositeLastMs_ = 0.0;
        const auto deadline =
            std::chrono::steady_clock::now() +
            std::chrono::microseconds(static_cast<int64_t>(compositeBudgetMs_ * 1000.0));
        const auto unitCompositesBefore = compositeBuildCount_;
        const float lift = mesher::kFloorHeight + kUnitCubeHalfHeight;
        const auto knownUnitIds=source_.model().unitIds();
        for (wm::UnitId id : knownUnitIds) {
            const wm::EvalResult current = source_.model().evaluate(id, double(source_.model().latestTick()));
            const auto presented = mesher::presentUnit(current, source_.model().evaluate(id, renderTick_));
            const auto& r = presented.state;
            if (r.presence != wm::Presence::Present) continue;
            // Units above the z-slice would float over the cut; hide them with
            // the terrain they stand on.
            if (sliceUnits_ && source_.model().hasTerrain() && topZ_ >= 0 &&
                (presented.sliceZ > static_cast<float>(topZ_) ||
                 presented.sliceZ <= static_cast<float>(topZ_ - windowDepth_))) {
                continue;
            }
            positions_.push_back(Vector3(r.pos.x + 0.5f, r.pos.z + lift, r.pos.y + 0.5f));
            ids_.push_back(static_cast<int64_t>(id));
            unitJobs_.push_back(static_cast<int32_t>(r.job));
            unitStatusFlags_.push_back(static_cast<int64_t>(source_.model().unitStatusFlags(id)));
            // Split tick values keep sub-tick precision in shaders on old forts.
            const auto& span = r.motion;
            unitMotionFrom_.push_back(Color(span.from.x + .5f, span.from.z, span.from.y + .5f, float(span.start % 4096)));
            unitMotionTo_.push_back(Color(span.to.x + .5f, span.to.z, span.to.y + .5f, float(span.end % 4096)));
            unitMotionEpochs_.push_back(Vector2(double(span.start / 4096), double(span.end / 4096)));
            unitMotionSegments_.push_back(static_cast<int32_t>(r.segment));
            unitAttackIds_.push_back(r.attack.actionId);
            unitAttackTargets_.push_back(r.attack.targetId);
            unitAttackTicks_.push_back(static_cast<int64_t>(r.attack.observedAt));

            const auto& art=prepareUnitArt(id,deadline,compositeBuildCount_==unitCompositesBefore);
            const int index=ids_.size()-1;
            if(spriteSlots_.size()<=index) {
                const int count=index+1;
                colors_.resize(count);spriteSlots_.resize(count);spriteRegions_.resize(count);
                spriteSizes_.resize(count);unitScaleParams_.resize(count);spriteKinds_.resize(count);
            }
            if(colors_[index]!=art.color)colors_.set(index,art.color);
            if(spriteSlots_[index]!=art.slot)spriteSlots_.set(index,art.slot);
            if(spriteRegions_[index]!=art.region)spriteRegions_.set(index,art.region);
            if(spriteSizes_[index]!=art.size)spriteSizes_.set(index,art.size);
            if(unitScaleParams_[index]!=art.scale)unitScaleParams_.set(index,art.scale);
            if(spriteKinds_[index]!=art.kind)spriteKinds_.set(index,art.kind);
            switch(art.kind) {
                case 1:++simpleUnits_;break;
                case 2:++compositedUnits_;break;
                case 3:++compositePending_;break;
                case 4:++glyphUnits_;break;
                default:++cubeUnits_;break;
            }
        }
        if(spriteSlots_.size()!=ids_.size()) {
            const int count=ids_.size();
            colors_.resize(count);spriteSlots_.resize(count);spriteRegions_.resize(count);
            spriteSizes_.resize(count);unitScaleParams_.resize(count);spriteKinds_.resize(count);
        }
        // Bound retained invisible artwork by the model's known population.
        // Pruning is exceptional, never another all-unit sweep per fractional tick.
        if(unitArtCache_.size()>knownUnitIds.size())
            for(auto it=unitArtCache_.begin();it!=unitArtCache_.end();)
                if(!std::binary_search(knownUnitIds.begin(),knownUnitIds.end(),it->first))it=unitArtCache_.erase(it);else ++it;
        updatePresentationLayout();
        updateUnitVisualChanges();
        // Deferred composites: finish them next frame even if the clock is frozen.
        if (compositePending_ > 0) lastRenderedTick_ = UINT64_MAX;
    }
    flushPresentationGeometry();
    collectAppearanceResources();
    return true;
}

void Df3dWorld::flushPresentationGeometry() {
    // Layout first, then geometry, then batch work last (a later geometry edit would cancel it).
    drainBuildingGeometry();
    PerfScope timer("batches.flush", &perfBatchFlushMs_);
    terrainBatches_.flush(2.0);
    buildingBatches_.flush(2.0);
}

// --- terrain ---

uint64_t Df3dWorld::key(wm::BlockPos p) {
    return (static_cast<uint64_t>(static_cast<uint32_t>(p.bz)) << 40) |
           (static_cast<uint64_t>(static_cast<uint32_t>(p.by) & 0xFFFFF) << 20) |
           (static_cast<uint32_t>(p.bx) & 0xFFFFF);
}

bool Df3dWorld::inWindow(wm::BlockPos p) const {
    return p.bz <= topZ_ && p.bz > topZ_ - windowDepth_;
}

bool Df3dWorld::blockInMap(wm::BlockPos p) const {
    if (p.bx < 0 || p.by < 0 || p.bz < 0) return false;
    const wm::TilePos map = source_.model().mapSize();
    const int32_t bxCount = (map.x + wm::kBlockSize - 1) / wm::kBlockSize;
    const int32_t byCount = (map.y + wm::kBlockSize - 1) / wm::kBlockSize;
    return p.bx < bxCount && p.by < byCount && p.bz < map.z;
}

int Df3dWorld::suggest_top_z() const {
    std::map<int, int> perZ;
    for (wm::UnitId id : source_.model().unitIds()) {
        const wm::EvalResult r = source_.model().evaluate(id, renderTick_);
        if (r.presence != wm::Presence::Present) continue;
        perZ[static_cast<int>(std::lround(r.pos.z))] += 1;
    }
    int best = source_.model().mapSize().z - 1, bestCount = 0;
    for (const auto& [z, n] : perZ) {
        if (n > bestCount) {
            best = z;
            bestCount = n;
        }
    }
    return best;
}

void Df3dWorld::set_terrain_root(Node3D* root) {
    if (root == terrainRoot_) return;
    resetTerrain();
    if (ownRoot_ && terrainRoot_) {
        remove_child(terrainRoot_);
        godot::memdelete(terrainRoot_);
    }
    terrainRoot_ = root;
    ownRoot_ = false;
    enqueueWindow();
}

Node3D* Df3dWorld::get_terrain_root() {
    if (!terrainRoot_) {
        terrainRoot_ = memnew(Node3D);
        terrainRoot_->set_name("Terrain");
        add_child(terrainRoot_);
        ownRoot_ = true;
    }
    return terrainRoot_;
}

void Df3dWorld::set_top_z(int z) {
    if (source_.model().hasTerrain()) {
        z = std::clamp(z, 0, std::max(0, source_.model().mapSize().z - 1));
    }
    if (z == topZ_) return;
    topZ_ = z;
    lastRenderedTick_ = UINT64_MAX;  // unit slice changed: re-evaluate even if paused
    itemsDirty_ = true;
    layoutScopeDirty_ = true;
    enqueueBuildingWindow();
    if (!source_.model().hasTerrain()) return;
    // Blocks leaving the window go; the old and new top layers are re-cut
    // (enqueueWindow compares the built top_z); blocks entering are built.
    for (auto it = built_.begin(); it != built_.end();) {
        const wm::BlockPos p{static_cast<int32_t>(it->first & 0xFFFFF),
                             static_cast<int32_t>((it->first >> 20) & 0xFFFFF),
                             static_cast<int32_t>(it->first >> 40)};
        if (!inWindow(p)) {
            freeBlock(it->second);
            it = built_.erase(it);
        } else {
            ++it;
        }
    }
    enqueueWindow();
}

void Df3dWorld::set_window_depth(int levels) {
    levels = std::max(1, levels);
    if (levels == windowDepth_) return;
    windowDepth_ = levels;
    itemsDirty_ = true;
    layoutScopeDirty_ = true;
    enqueueBuildingWindow();
    if (!source_.model().hasTerrain()) return;
    for (auto it = built_.begin(); it != built_.end();) {
        const wm::BlockPos p{static_cast<int32_t>(it->first & 0xFFFFF),
                             static_cast<int32_t>((it->first >> 20) & 0xFFFFF),
                             static_cast<int32_t>(it->first >> 40)};
        if (!inWindow(p)) {
            freeBlock(it->second);
            it = built_.erase(it);
        } else {
            ++it;
        }
    }
    enqueueWindow();
}

void Df3dWorld::set_reveal_hidden(bool reveal) {
    if (reveal == revealHidden_) return;
    revealHidden_ = reveal;
    resetTerrain();
    enqueueWindow();
    resetEntities();
}

void Df3dWorld::enqueue(wm::BlockPos p) {
    if (!inWindow(p) || !blockInMap(p)) return;
    const uint64_t k = key(p);
    if (queued_.insert(k).second) queue_.push_back(p);
}

// Queues every block of the window that is not built against the current
// top_z / version, top layer first so the visible surface appears first.
void Df3dWorld::enqueueWindow() {
    if (!source_.model().hasTerrain() || topZ_ < 0) return;
    const wm::TilePos map = source_.model().mapSize();
    const int32_t bxCount = (map.x + wm::kBlockSize - 1) / wm::kBlockSize;
    const int32_t byCount = (map.y + wm::kBlockSize - 1) / wm::kBlockSize;
    for (int32_t z = std::min(topZ_, map.z - 1); z > topZ_ - windowDepth_ && z >= 0; --z) {
        for (int32_t by = 0; by < byCount; ++by)
            for (int32_t bx = 0; bx < bxCount; ++bx) {
                const wm::BlockPos p{bx, by, z};
                // Only the top layer depends on the cut: a block built as
                // the top layer (or becoming it) must be re-meshed.
                auto it = built_.find(key(p));
                if (it != built_.end() && it->second.version == source_.model().blockVersion(p) &&
                    (it->second.topZ == topZ_ || (it->second.topZ != z && topZ_ != z))) {
                    continue;
                }
                enqueue(p);
            }
    }
}

void Df3dWorld::freeBlock(Built& b) {
    PerfScope profile("terrain.free_block", nullptr, df3d::profiling::detailed());
    hiddenFaces_ -= b.hidden;
    b.hidden = 0;
    if (b.node) {
        terrainBatches_.erase(b.node->get_instance_id());
        faceCount_ -= static_cast<int64_t>(b.node->get_meta("df3d_faces", 0));
        terrainRoot_->remove_child(b.node);
        godot::memdelete(b.node);
        b.node = nullptr;
        --meshCount_;
    }
    unresolvedFaces_ -= b.unresolved;
    texturedFaces_ -= b.textured;
    b.unresolved = 0;
    b.textured = 0;
}

void Df3dWorld::resetTerrain() {
    terrainVisibilityDependencies_.clear();
    spatterEdges_.clear();
    terrainBatches_.clear();
    for (auto& [k, b] : built_) freeBlock(b);
    built_.clear();
    queue_.clear();
    queued_.clear();
    queueHead_ = 0;
    meshCount_ = 0;
    faceCount_ = 0;
    unresolvedFaces_ = 0;
    texturedFaces_ = 0;
    hiddenFaces_ = 0;
    if (backdrop_) {
        terrainRoot_->remove_child(backdrop_);
        godot::memdelete(backdrop_);
        backdrop_ = nullptr;
        backdropTopZ_ = -1;
    }
}

void Df3dWorld::updateBackdrop() {
    if (!source_.model().hasTerrain() || topZ_ < 0) return;
    if (backdrop_ && backdropTopZ_ == topZ_ && backdropDepth_ == windowDepth_) return;
    if (backdrop_) {
        terrainRoot_->remove_child(backdrop_);
        godot::memdelete(backdrop_);
        backdrop_ = nullptr;
    }
    const wm::TilePos m = source_.model().mapSize();
    // Just under the lowest window layer's bottom faces, past the map edges.
    const float y = static_cast<float>(topZ_ - windowDepth_ + 1) - 0.05f;
    const float pad = 8.0f;
    PackedVector3Array v;
    v.push_back(Vector3(-pad, y, -pad));
    v.push_back(Vector3(static_cast<float>(m.x) + pad, y, -pad));
    v.push_back(Vector3(static_cast<float>(m.x) + pad, y, static_cast<float>(m.y) + pad));
    v.push_back(Vector3(-pad, y, static_cast<float>(m.y) + pad));
    PackedColorArray c;
    PackedVector3Array n;
    for (int i = 0; i < 4; ++i) {
        // Hidden color is a source_color material uniform; avoid low-precision
        // UNorm8 vertex-color quantization of dark linear color values.
        c.push_back(Color(1, 1, 1, 1));
        n.push_back(Vector3(0, 1, 0));
    }
    PackedInt32Array idx;
    for (int32_t i : {0, 1, 2, 0, 2, 3}) idx.push_back(i);
    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = v;
    arrays[Mesh::ARRAY_NORMAL] = n;
    arrays[Mesh::ARRAY_COLOR] = c;
    arrays[Mesh::ARRAY_INDEX] = idx;
    Ref<ArrayMesh> mesh;
    mesh = submission::createMesh(submission::MeshSite::Backdrop);
    submission::meshSurface(mesh, arrays, submission::MeshSite::Backdrop);
    mesh->surface_set_material(0, materialFor(SurfaceKey{-1, kSurfHidden}));
    backdrop_ = memnew(MeshInstance3D);
    backdrop_->set_name("backdrop");
    backdrop_->set_mesh(mesh);
    get_terrain_root()->add_child(backdrop_);
    backdropTopZ_ = topZ_;
    backdropDepth_ = windowDepth_;
}

void Df3dWorld::ensureMaterials() {
    // Materials are created per surface key on demand (materialFor).
}

void Df3dWorld::buildBlock(wm::BlockPos p) {
    PerfScope buildProfile("terrain.build_block", nullptr, df3d::profiling::detailed());
    const char* occlusionOption = std::getenv("DF3D_OCCLUSION");
    const bool buildOcclusion = !occlusionOption || std::strcmp(occlusionOption,"0")!=0;
    mesher::MeshOptions opts;
    opts.topZ = topZ_;
    opts.revealHidden = revealHidden_;
    const mesher::WorldModelSource src(source_.model());
    mesher::BlockMesh bm;
    {
        PerfScope profile("terrain.mesh_block", nullptr, df3d::profiling::detailed());
        bm = mesher::meshBlock(src, p, opts);
    }

    ERR_FAIL_COND_MSG(!blockInMap(p), "block outside the map grid");
    Built& b = built_[key(p)];
    freeBlock(b);
    b.version = bm.version;
    b.topZ = topZ_;
    if (bm.faces.empty()) return;

    // One surface per (texture slot, surface kind); the untextured
    // placeholder surfaces (slot -1) carry the faces no tile resolved.
    std::map<SurfaceKey, SurfaceArrays> surfaces;
    std::vector<mesher::Face> occluderFaces;
    {
        PerfScope packProfile("terrain.pack_faces", nullptr, df3d::profiling::detailed());
        for (const mesher::Face& f : bm.faces) {
            if (f.tag.part == mesher::FacePart::Hidden) {
                // Ordinary and merged hidden caps share the native rock backing.
                // No hidden tile material/shape is inspected to choose this color.
                surfaces[SurfaceKey{-1, kSurfHidden}].add(f, Color(1, 1, 1, 1), nullptr);
                if (buildOcclusion) occluderFaces.push_back(f);
                ++b.hidden;
                continue;
            }
            const FaceLook& look = lookFor(f.tag);
            SurfaceKind kind = kSurfOpaque;
            if (f.tag.part == mesher::FacePart::Liquid) {
                kind = f.tag.liquid == wm::LiquidKind::Magma ? kSurfMagma : kSurfWater;
            } else if (look.cutout || f.tag.dir == mesher::FaceDir::Cross) {
                kind = kSurfCutout;
            }
            if (buildOcclusion && kind == kSurfOpaque && f.tag.part == mesher::FacePart::Terrain) occluderFaces.push_back(f);
            FaceLook spatter;
            if (kind == kSurfOpaque && f.tag.part == mesher::FacePart::Terrain &&
                (f.tag.dir == mesher::FaceDir::PosZ || f.tag.dir == mesher::FaceDir::Slope) &&
                f.tag.shape != wm::TileShape::Wall && f.tag.shape != wm::TileShape::Unknown &&
                f.tag.shape != wm::TileShape::TreeTrunk && f.tag.shape != wm::TileShape::Fortification)
                spatter = spatterLookFor({p.bx*16+f.tag.lx,p.by*16+f.tag.ly,p.bz});
            const float stainRect[4] = {spatter.u0,spatter.v0,spatter.u1,spatter.v1};
            const float* stain = spatter.slot >= 0 ? stainRect : nullptr;
            if (look.slot >= 0) {
                const float rect[4] = {look.u0, look.v0, look.u1, look.v1};
                surfaces[SurfaceKey{look.slot, kind, spatter.slot}].add(f, texturedTint(f.tag), rect, stain);
                ++b.textured;
            } else {
                surfaces[SurfaceKey{-1, kind, spatter.slot}].add(
                    f, faceColor(f.tag), nullptr, stain);
                ++b.unresolved;
            }
        }

    }
    Ref<ArrayMesh> mesh;
    mesh = submission::createMesh(submission::MeshSite::Terrain);
    Array cpuSurfaces;
    for (auto& [sk, arr] : surfaces) {
        if (arr.vertices.is_empty()) continue;
        PerfScope uploadProfile("terrain.upload_surface", nullptr, df3d::profiling::detailed());
        Array arrays;
        arrays.resize(Mesh::ARRAY_MAX);
        arrays[Mesh::ARRAY_VERTEX] = arr.vertices;
        arrays[Mesh::ARRAY_NORMAL] = arr.normals;
        arrays[Mesh::ARRAY_COLOR] = arr.colors;
        if (sk.slot >= 0) arrays[Mesh::ARRAY_TEX_UV] = arr.uvs;
        if (sk.spatterSlot >= 0) arrays[Mesh::ARRAY_TEX_UV2] = arr.spatterUvs;
        arrays[Mesh::ARRAY_INDEX] = arr.indices;
        const int surface = mesh->get_surface_count();
        cpuSurfaces.append(arrays);
        submission::meshSurface(mesh, arrays, submission::MeshSite::Terrain);
        mesh->surface_set_material(surface, materialFor(sk));
    }

    mesh->set_meta("df3d_batch_arrays", cpuSurfaces);

    MeshInstance3D* node = memnew(MeshInstance3D);
    node->set_name(String("block_") + String::num_int64(p.bx) + "_" + String::num_int64(p.by) +
                   "_" + String::num_int64(p.bz));
    node->set_mesh(mesh);
    node->set_meta("df3d_faces", static_cast<int64_t>(bm.faces.size()));
    get_terrain_root()->add_child(node);
    b.node = node;
    if (buildOcclusion) {
        PerfScope occluderProfile("terrain.occluder", nullptr, df3d::profiling::detailed());
        attachTerrainOccluder(node,occluderFaces);
    }
    bool opaque = true;
    for (const auto& [sk, arr] : surfaces)
        if (sk.kind == kSurfWater || sk.kind == kSurfMagma || sk.kind == kSurfGhost) opaque = false;
    if (opaque) terrainBatches_.put(node->get_instance_id(), node, Vector3i(p.bx / 2, p.bz / 4, p.by / 2));
    ++meshCount_;
    faceCount_ += static_cast<int64_t>(bm.faces.size());
    unresolvedFaces_ += b.unresolved;
    texturedFaces_ += b.textured;
    hiddenFaces_ += b.hidden;
}

void Df3dWorld::updateTerrain() {
    if (!source_.model().hasTerrain()) return;
    // A new map (live epoch change or a different fixture) drops everything.
    if (!(source_.model().mapSize() == builtMapSize_)) {
        resetTerrain();
        builtMapSize_ = source_.model().mapSize();
        topZ_ = -1;
    }
    if (topZ_ < 0) {
        topZ_ = suggest_top_z();
        enqueueWindow();
        itemsDirty_ = true;
        enqueueBuildingWindow();
    }
    // Source-only visual changes. Do not dirty unit/item layouts, roof queries,
    // semantic terrain versions or occluder dependencies for contamination.
    for (const auto p : source_.model().drainSpatterEvents()) {
        if (!blockInMap(p)) continue;
        enqueue(p);
        std::array<uint64_t,4> edges{};
        for(const auto& e:source_.model().spattersAt(p)) {
            if(!assets::spatterFull(e.amount)) continue;
            const bool boundary[]={e.tile%16==0,e.tile%16==15,e.tile/16==0,e.tile/16==15};
            const uint64_t value=(uint64_t(e.material)<<16)|(uint64_t(e.state)<<8)|e.tile;
            for(int i=0;i<4;++i)if(boundary[i])edges[i]=(edges[i]^value)*1099511628211ull+1;
        }
        auto& previous=spatterEdges_[key(p)];
        const wm::BlockPos adjacent[]={{p.bx-1,p.by,p.bz},{p.bx+1,p.by,p.bz},{p.bx,p.by-1,p.bz},{p.bx,p.by+1,p.bz}};
        for(int i=0;i<4;++i)if(previous[i]!=edges[i])enqueue(adjacent[i]);
        previous=edges;
    }
    for (const wm::TerrainBlockEvent& ev : source_.model().drainTerrainEvents()) {
        if (!blockInMap(ev.pos)) continue;
        enqueue(ev.pos);
        refreshTerrainSupport(ev.pos);
        const auto p=ev.pos;
        const auto block=source_.model().block(p);
        const auto visibility=terrainVisibilityDependencies_.observe(p,block?block->tiles:nullptr,revealHidden_);
        if(!inWindow(p) || visibility.tiles.none())continue;
        source_.model().forEachItemInBox({p.bx*16,p.by*16,p.bz},{p.bx*16+15,p.by*16+15,p.bz},[&](const auto& item) {
            if(!visibility.contains(item.pos.x,item.pos.y))return;
            itemUpdateIDs_.insert(item.id);layoutItemChanges_.insert(item.id);
        });
        const auto owners=layoutBuildingsByBlock_.find({p.bz,p.bx,p.by});
        if(owners!=layoutBuildingsByBlock_.end())for(auto id:owners->second) {
            const auto* building=source_.model().building(id);
            const auto art=buildingFootprintCache_.find(id);
            if(!building || art==buildingFootprintCache_.end())continue;
            for(const auto& [lx,ly]:art->second.cells) {
                if(!visibility.contains(building->x1+lx,building->y1+ly))continue;
                layoutBuildingChanges_.insert(id);enqueueBuilding(id,submission::Visibility);
                break;
            }
        }
        lastRenderedTick_=UINT64_MAX;
    }
    updateBackdrop();

    if (queueHead_ >= queue_.size()) return;
    const double profileStart = df3d::profiling::timestampUs();
    int n = 0;
    while (queueHead_ < queue_.size() && n < buildBudget_) {
        const wm::BlockPos p = queue_[queueHead_++];
        queued_.erase(key(p));
        ++n;
        if (!inWindow(p)) continue;  // window moved since it was queued
        buildBlock(p);
    }
    if (queueHead_ >= queue_.size()) {
        queue_.clear();
        queueHead_ = 0;
    }
    lastBuildMs_ = df3d::profiling::elapsedMs(profileStart);
    totalBuildMs_ += lastBuildMs_;
}

}  // namespace df3d_godot

void df3d_godot::Df3dWorld::set_mesh_batching_enabled(bool enabled) {
    terrainBatches_.set_enabled(enabled);
    buildingBatches_.set_enabled(enabled);
}
godot::Dictionary df3d_godot::Df3dWorld::mesh_batch_stats() const {
    godot::Dictionary out;
    out["terrain"] = terrainBatches_.stats();
    out["buildings"] = buildingBatches_.stats();
    return out;
}
