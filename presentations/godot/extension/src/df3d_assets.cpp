#include "immutable_material.h"
#include <godot_cpp/classes/resource_loader.hpp>
#include "submission_uploads.h"
#include "df3d_world.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include "df3d_assets/ground_spatter.h"
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <vector>

#include "df3d_assets/resolver.h"
#include "df3d_assets/terrain_fill.h"
#include "df3d_assets/wall_top.h"
#include "df3d_mesher/block_mesher.h"
#include "df3d_mesher/piece_policy.h"
#include "df3d_mesher/unit_presentation.h"
#include "df3d_mesher/cutout.h"

namespace df3d_godot {

using godot::Array;
using godot::Color;
using godot::Dictionary;
using godot::Image;
using godot::ImageTexture;
using godot::Mesh;
using godot::PackedByteArray;
using godot::PackedColorArray;
using godot::PackedInt32Array;
using godot::PackedVector2Array;
using godot::PackedVector3Array;
using godot::Ref;
using godot::Shader;
using godot::ShaderMaterial;
using godot::StandardMaterial3D;
using godot::String;
using godot::Vector2;
using godot::Vector3;
using godot::Vector3i;

namespace mesher = df3d::mesher;
namespace assets = df3d::assets;

namespace {
// Stable debug palette for species without resolved art.
Color speciesColor(const std::string& species) {
    uint32_t h = 2166136261u;
    for (unsigned char c : species) {
        h ^= c;
        h *= 16777619u;
    }
    const auto chan = [](uint32_t v) { return (96.0f + static_cast<float>(v & 0x7F)) / 255.0f; };
    return Color(chan(h), chan(h >> 8), chan(h >> 16), 1.0f);
}

assets::FaceSide sideOf(mesher::FaceDir d) {
    switch (d) {
        case mesher::FaceDir::PosZ: return assets::FaceSide::Top;
        case mesher::FaceDir::NegZ: return assets::FaceSide::Bottom;
        case mesher::FaceDir::Slope: return assets::FaceSide::Slope;
        case mesher::FaceDir::Cross: return assets::FaceSide::Cross;
        default: return assets::FaceSide::Side;
    }
}

assets::SlopeDir slopeOf(mesher::FaceDir high) {
    switch (high) {
        case mesher::FaceDir::NegY: return assets::SlopeDir::North;
        case mesher::FaceDir::PosY: return assets::SlopeDir::South;
        case mesher::FaceDir::NegX: return assets::SlopeDir::West;
        case mesher::FaceDir::PosX: return assets::SlopeDir::East;
        default: return assets::SlopeDir::None;
    }
}

assets::FaceKind partOf(mesher::FacePart p) {
    switch (p) {
        case mesher::FacePart::Feature: return assets::FaceKind::Feature;
        case mesher::FacePart::Liquid: return assets::FaceKind::Liquid;
        default: return assets::FaceKind::Terrain;
    }
}

// Resolver inputs packed for memoisation.
uint64_t lookKey(const mesher::FaceTag& t) {
    return (static_cast<uint64_t>(t.slopeHigh) << 56) | (static_cast<uint64_t>(t.walls) << 48) |
           (static_cast<uint64_t>(t.material) << 32) |
           (static_cast<uint64_t>(t.shape) << 24) | (static_cast<uint64_t>(t.materialKind) << 16) |
           (static_cast<uint64_t>(t.flags) << 8) | (static_cast<uint64_t>(t.dir) << 4) |
           (static_cast<uint64_t>(t.part) << 2) | static_cast<uint64_t>(t.liquid);
}
}
String Df3dWorld::assets_root() const {
    return assets_ ? String(assets_->install.root.c_str()) : String();
}

bool Df3dWorld::load_assets(const String& override_path) {
    assets::ProviderOptions po;
    po.installOverride = override_path.utf8().get_data();
    std::string err;
    auto p = assets::openProvider(po, err);
    if (!p) {
        assetsError_ = String(err.c_str());
        assets_.reset();
        godot::UtilityFunctions::printerr("df3d assets: ", assetsError_);
        return false;
    }
    assets_ = std::move(p);
    assetsError_ = String();
    uiTextures_.clear();
    spriteResources_.clear();
    slotIndex_.clear();
    wallTopIndex_.clear();
    wallTopBitmaps_.clear();
    rockBackingReady_ = false;
    pageImages_.clear();
    paletteImage_.unref();
    paletteTried_ = false;
    minimapTexture_.unref();
    faceLooks_.clear();
    unitLooks_.clear();
    unitGlyphLooks_.clear();
    rawImages_.clear();
    compositeFailed_ = 0;
    compositeWhyPrinted_ = 0;
    materials_.clear();
    glyphSlots_.clear();
    glyphTried_ = false;
    glyphs_ = assets::GlyphRenderer();
    loadGlyphTileset();
    resetTerrain();
    enqueueWindow();
    resetEntities();
    godot::UtilityFunctions::print("df3d assets: ", assets_summary());
    godot::UtilityFunctions::print("df3d glyphs: ", glyph_summary());
    for (const std::string& d : assets_->diagnostics)
        godot::UtilityFunctions::print("df3d assets: ", String(d.c_str()));
    return true;
}

String Df3dWorld::assets_summary() const {
    if (!assets_) return String("no assets");
    const assets::IndexStats& s = assets_->index.stats;
    char buf[512];
    std::snprintf(buf, sizeof buf,
                  "DF %s build %s at %s | %s | %d pages, %d tile graphics, %d plant graphics, "
                  "%d creature graphics (%d simple, %d layered) | index %.0f ms",
                  assets::kPinnedDfVersion, assets_->install.buildId.c_str(),
                  assets_->install.root.c_str(), assets_->cacheHit ? "cache hit" : "index rebuilt",
                  s.tilePages, s.tileGraphics, s.plantGraphics, s.creatureGraphics,
                  s.creatureSimple, s.creatureLayered, assets_->indexMs);
    return String(buf);
}

Ref<Image> Df3dWorld::pageImage(int page) {
    auto it = pageImages_.find(page);
    if (it != pageImages_.end()) return it->second;
    Ref<Image> img;
    const assets::TilePage* p = assets_ ? assets_->index.page(page) : nullptr;
    if (p && !p->absPath.empty()) {
        img = Image::load_from_file(String(p->absPath.c_str()));
        if (img.is_valid() && !img->is_empty()) {
            img->convert(Image::FORMAT_RGBA8);
        } else {
            godot::UtilityFunctions::printerr("df3d assets: cannot load tile page ",
                                              String(p->name.c_str()), " from ",
                                              String(p->absPath.c_str()));
            img.unref();
        }
    }
    pageImages_[page] = img;
    return img;
}

// A texture slot for (page, palette row, fill). Recolouring reproduces
// DF's own mechanism: pixels painted in the palette's default row are
// swapped for the same column of the material's row; with `fill` the
// (translucent, edge-overlay) tile is then composited over the row's base
// colour (column 0) so a cube face is opaque.
int Df3dWorld::slotFor(int page, int paletteRow, bool fill) {
    const auto key = std::make_tuple(page, paletteRow, fill);
    auto it = slotIndex_.find(key);
    if (it != slotIndex_.end()) return it->second;
    PerfScope slotProfile("assets.slot_miss", nullptr, df3d::profiling::detailed());
    Ref<Image> src = pageImage(page);
    if (src.is_null()) {
        slotIndex_[key] = -1;
        return -1;
    }
    if (!paletteTried_ && assets_ && assets_->index.palette) {
        paletteTried_ = true;
        paletteImage_ = Image::load_from_file(String(assets_->index.palette->absPath.c_str()));
        if (paletteImage_.is_valid() && !paletteImage_->is_empty()) {
            paletteImage_->convert(Image::FORMAT_RGBA8);
        } else {
            paletteImage_.unref();
            godot::UtilityFunctions::printerr("df3d assets: cannot load palette image");
        }
    }
    const int w = src->get_width(), h = src->get_height();
    Ref<Image> img = src;
    // The palette swap needs the palette image and a material row; the
    // fill needs neither (it must not silently vanish with the palette).
    const bool swap = paletteImage_.is_valid() && paletteRow >= 0;
    if (swap || fill) {
        PerfScope paletteProfile("assets.palette_bake", nullptr, df3d::profiling::detailed());
        const int defaultRow =
            paletteImage_.is_valid() ? assets_->index.palette->defaultRow : 0;
        const int row = paletteRow >= 0 ? paletteRow : defaultRow;
        const int pw = swap ? paletteImage_->get_width() : 0;  // no keys without a swap
        const int ph = swap ? paletteImage_->get_height() : 0;
        const bool rowsOk = !swap || (row < ph && defaultRow < ph);
        if (rowsOk) {
            PackedByteArray pal;
            if (swap) pal = paletteImage_->get_data();
            const uint8_t* pd = pal.ptr();
            std::vector<uint32_t> keys(static_cast<size_t>(pw));
            std::vector<uint32_t> repl(static_cast<size_t>(pw));
            auto rgb = [&](int x, int y) {
                const size_t o = (static_cast<size_t>(y) * pw + x) * 4;
                return (uint32_t{pd[o]} << 16) | (uint32_t{pd[o + 1]} << 8) | pd[o + 2];
            };
            for (int x = 0; x < pw; ++x) {
                keys[static_cast<size_t>(x)] = rgb(x, defaultRow);
                repl[static_cast<size_t>(x)] = rgb(x, row);
            }
            PackedByteArray data = src->get_data();
            uint8_t* d = data.ptrw();
            const size_t n = static_cast<size_t>(w) * h;
            // Keyed art uses the material palette backing. Already-coloured
            // art uses its own mean even if the material has a palette row.
            const uint32_t base = swap ? repl[0] : 0x404040u;
            const assets::TilePage* pg = assets_->index.page(page);
            const int tw = pg && pg->tileW > 0 ? pg->tileW : w;
            const int th = pg && pg->tileH > 0 ? pg->tileH : h;
            const int tilesX = std::max(1, w / tw), tilesY = std::max(1, h / th);
            std::vector<uint32_t> tileBase;
            if (fill) {
                tileBase.assign(static_cast<size_t>(tilesX) * tilesY, base);
                for (int ty = 0; ty < tilesY; ++ty) {
                    for (int tx = 0; tx < tilesX; ++tx) {
                        tileBase[static_cast<size_t>(ty) * tilesX + tx] =
                            assets::terrainFillBase(d, w, h, tx * tw, ty * th, tw, th, keys, base);
                    }
                }
            }
            for (size_t i = 0; i < n; ++i) {
                uint8_t* px = d + i * 4;
                if (px[3] == 0 && !fill) continue;
                uint32_t b = base;
                if (!tileBase.empty()) {
                    const int x = static_cast<int>(i % static_cast<size_t>(w));
                    const int y = static_cast<int>(i / static_cast<size_t>(w));
                    b = tileBase[static_cast<size_t>(std::min(tilesY - 1, y / th)) * tilesX +
                                 std::min(tilesX - 1, x / tw)];
                }
                const float br = ((b >> 16) & 255) / 255.0f, bg = ((b >> 8) & 255) / 255.0f,
                            bb = (b & 255) / 255.0f;
                const uint32_t c = (uint32_t{px[0]} << 16) | (uint32_t{px[1]} << 8) | px[2];
                if (swap && px[3] != 0) {
                    for (int x = 0; x < pw; ++x) {
                        if (keys[static_cast<size_t>(x)] == c) {
                            const uint32_t r = repl[static_cast<size_t>(x)];
                            px[0] = static_cast<uint8_t>(r >> 16);
                            px[1] = static_cast<uint8_t>(r >> 8);
                            px[2] = static_cast<uint8_t>(r);
                            break;
                        }
                    }
                }
                if (fill && px[3] != 255) {
                    const float a = px[3] / 255.0f;
                    px[0] = static_cast<uint8_t>(std::lround((px[0] / 255.0f * a + br * (1 - a)) * 255));
                    px[1] = static_cast<uint8_t>(std::lround((px[1] / 255.0f * a + bg * (1 - a)) * 255));
                    px[2] = static_cast<uint8_t>(std::lround((px[2] / 255.0f * a + bb * (1 - a)) * 255));
                    px[3] = 255;
                }
            }
            img = Image::create_from_data(w, h, false, Image::FORMAT_RGBA8, data);
        }
    }
    Ref<Image> mip;
    {
        PerfScope mipProfile("assets.mipmaps", nullptr, df3d::profiling::detailed());
        mip = img->duplicate();
        mip->generate_mipmaps();
    }
    // Tier-4 hook: DF3D_DUMP_SLOTS=<dir> writes every baked page texture
    // (after the palette swap and fill) so what the faces sample can be
    // inspected outside the engine. Derived from the install's art: build/
    // is gitignored, never commit the output.
    if (const char* dump = std::getenv("DF3D_DUMP_SLOTS"); dump && *dump) {
        godot::DirAccess::make_dir_recursive_absolute(String(dump));
        char name[128];
        const assets::TilePage* pg = assets_ ? assets_->index.page(page) : nullptr;
        std::snprintf(name, sizeof name, "/slot_%s_row%d_fill%d.png", pg ? pg->name.c_str() : "page",
                      paletteRow, fill ? 1 : 0);
        img->save_png(String((std::string(dump) + name).c_str()));
    }
    TextureSlot slot;
    slot.page = page;
    slot.paletteRow = paletteRow;
    slot.fill = fill;
    slot.width = w;
    slot.height = h;
    {
        PerfScope uploadProfile("assets.texture_create", nullptr, df3d::profiling::detailed());
        slot.texture = submission::texture(mip, submission::TextureSite::Atlas,true);
        const auto* pageInfo = assets_->index.page(page);
        slot.texture->set_meta("world_cell", Vector2(pageInfo->tileW, pageInfo->tileH));
    }
    const int id = spriteResources_.slots.add(std::move(slot));
    slotIndex_[key] = id;
    spriteResources_.images[id] = mip;
    return id;
}

Color Df3dWorld::rock_backing_color() {
    if (!rockBackingReady_ && assets_) {
        const assets::Rgba color = assets::nativeRockBacking(assets_->index,
            [this](const std::string& path) { return rawImage(path); });
        rockBackingColor_ = Color(color.r / 255.0f, color.g / 255.0f, color.b / 255.0f, 1.0f);
        rockBackingReady_ = true;
    }
    return rockBackingColor_;
}

godot::Dictionary Df3dWorld::wall_top_cache_stats() const {
    godot::Dictionary stats;
    stats["hits"] = int64_t(wallTopBitmaps_.hits());
    stats["unique"] = int64_t(wallTopBitmaps_.unique());
    return stats;
}

int Df3dWorld::wallTopSlotFor(const assets::TerrainSprite& wall, uint8_t neighbors) {
    const auto key = std::make_tuple(wall.sprite.page, wall.sprite.x, wall.sprite.y, wall.paletteRow, neighbors);
    if (auto it = wallTopIndex_.find(key); it != wallTopIndex_.end()) return it->second;
    std::string why;
    const assets::RgbaImage image = assets::composeWallTop(assets_->index, wall,
        [this](const std::string& path) { return rawImage(path); }, why);
    if (image.empty()) {
        godot::UtilityFunctions::printerr(String(("Wall top composition failed: " + why).c_str()));
        wallTopIndex_[key] = -1;
        return -1;
    }
    const int candidate = spriteResources_.slots.nextId();
    const int shared = wallTopBitmaps_.intern(image, candidate);
    if (shared != candidate) {
        wallTopIndex_[key] = shared;
        return shared;
    }
    PackedByteArray data;
    data.resize(static_cast<int64_t>(image.pixels.size()));
    std::memcpy(data.ptrw(), image.pixels.data(), image.pixels.size());
    Ref<Image> img = Image::create_from_data(image.width, image.height, false, Image::FORMAT_RGBA8, data);
    if (const char* dump = std::getenv("DF3D_DUMP_SLOTS"); dump && *dump) {
        godot::DirAccess::make_dir_recursive_absolute(String(dump));
        const assets::TilePage* page = assets_->index.page(wall.sprite.page);
        const std::string name = std::string(dump) + "/walltop_" + page->name + "_" +
            std::to_string(wall.sprite.x) + "_" + std::to_string(wall.sprite.y) + "_row" +
            std::to_string(wall.paletteRow) + "_mask" + std::to_string(neighbors) + ".png";
        img->save_png(String(name.c_str()));
    }
    img->generate_mipmaps();
    TextureSlot slot;
    slot.page = wall.sprite.page;
    slot.paletteRow = wall.paletteRow;
    slot.fill = true;
    slot.width = image.width;
    slot.height = image.height;
    slot.texture = submission::texture(img, submission::TextureSite::Walltop,true);
    const int id = spriteResources_.slots.add(std::move(slot));
    wallTopIndex_[key] = id;
    spriteResources_.images[id] = img;
    return id;
}

Ref<godot::ArrayMesh> Df3dWorld::sprite_cutout_mesh(int slot, Color region) {
    if(!spriteResources_.slots.contains(slot)) return {};
    auto texture=spriteResources_.slots[slot].texture;
    const int x=std::lround(region.r*texture->get_width()), y=std::lround(region.g*texture->get_height());
    const int w=std::lround(region.b*texture->get_width()), h=std::lround(region.a*texture->get_height());
    const std::string key=std::to_string(slot)+":"+std::to_string(x)+":"+std::to_string(y)+":"+std::to_string(w)+":"+std::to_string(h);
    if(auto it=spriteResources_.meshes.find(key);it!=spriteResources_.meshes.end())return it->second;
    auto& img=spriteResources_.images[slot];
    if(img.is_null()) img=texture->get_image();
    if(img.is_null() || w<=0 || h<=0) return {};
    std::vector<uint8_t> alpha(size_t(w)*h);
    for(int j=0;j<h;++j)for(int i=0;i<w;++i) if(x+i>=0 && y+j>=0 && x+i<img->get_width() && y+j<img->get_height()) alpha[j*w+i]=uint8_t(img->get_pixel(x+i,y+j).a*255);
    const auto indexed=mesher::indexCutoutMesh(mesher::cutoutMesh(alpha,w,h));
    const auto& vertices=indexed.vertices;
    godot::PackedVector3Array positions; godot::PackedVector2Array uvs; godot::PackedColorArray colors;
    for(const auto& v:vertices){positions.push_back(Vector3(v.x*spriteResources_.slots[slot].cutoutScale.x+spriteResources_.slots[slot].cutoutOffset.x,v.y,v.z*spriteResources_.slots[slot].cutoutScale.y+spriteResources_.slots[slot].cutoutOffset.y));uvs.push_back(Vector2(region.r+v.u*region.b,region.g+v.v*region.a));colors.push_back(Color(v.shade,v.shade,v.shade,1));}
    auto mesh = submission::createMesh(submission::MeshSite::Cutout);
    if(!vertices.empty()){
        godot::PackedInt32Array indices;indices.resize(static_cast<int64_t>(indexed.indices.size()));
        std::copy(indexed.indices.begin(),indexed.indices.end(),indices.ptrw());
        Array a;a.resize(Mesh::ARRAY_MAX);a[Mesh::ARRAY_VERTEX]=positions;a[Mesh::ARRAY_TEX_UV]=uvs;a[Mesh::ARRAY_COLOR]=colors;a[Mesh::ARRAY_INDEX]=indices;
        submission::meshSurface(mesh, a, submission::MeshSite::Cutout);
    }
    spriteResources_.meshes[key]=mesh;return mesh;
}

Ref<godot::Texture2D> Df3dWorld::sprite_texture(int slot) {
    if (!spriteResources_.slots.contains(slot)) return Ref<godot::Texture2D>();
    return spriteResources_.slots[static_cast<size_t>(slot)].texture;
}

// --- classic glyph fallback ---

// Decodes the install's curses tileset (the PNG DF's init names, resolved
// by the provider) into the renderer with the install's colors.txt
// palette. Not fatal: without it the glyph fallback is off and markers
// remain.
void Df3dWorld::loadGlyphTileset() {
    if (glyphTried_ || !assets_) return;
    glyphTried_ = true;
    glyphWhy_.clear();
    const assets::ClassicTileset& ts = assets_->classicTileset;
    if (ts.absPath.empty()) {
        glyphWhy_ = "no curses tileset under data/art";
        return;
    }
    const assets::RgbaImage* img = rawImage(ts.absPath);
    if (!img) {
        glyphWhy_ = "cannot decode " + ts.file;
        return;
    }
    std::string err;
    if (!glyphs_.setTileset(*img, err)) {
        glyphWhy_ = err;
        return;
    }
    glyphs_.setPalette(assets_->classicPalette);
}

String Df3dWorld::glyph_summary() const {
    if (!assets_) return String("no assets");
    if (!glyphs_.ready()) return String(("glyph fallback off: " + glyphWhy_).c_str());
    char buf[256];
    std::snprintf(buf, sizeof buf, "%s %dx%d (%s), colours from %s, %d sheets",
                  assets_->classicTileset.file.c_str(), glyphs_.tileW(), glyphs_.tileH(),
                  assets_->classicTileset.source.c_str(),
                  assets_->classicPaletteFromInstall ? "data/init/colors.txt" : "DF defaults",
                  static_cast<int>(glyphSlots_.size()));
    return String(buf);
}

// One texture per colour triple: the whole tileset tinted, so every glyph
// of that colour shares a MultiMesh. Non-power-of-two glyph cells use
// bounded level-zero sharp sampling; this resource is separate from UI fonts.
int Df3dWorld::glyphSlotFor(uint8_t fg, uint8_t bg, uint8_t bright) {
    if (!glyphs_.ready()) return -1;
    const int key = (fg & 7) | ((bg & 7) << 3) | ((bright ? 1 : 0) << 6);
    auto it = glyphSlots_.find(key);
    if (it != glyphSlots_.end()) return it->second;
    const assets::RgbaImage sheet = glyphs_.renderSheet(fg, bg, bright);
    PackedByteArray data;
    data.resize(static_cast<int64_t>(sheet.pixels.size()));
    std::copy(sheet.pixels.begin(), sheet.pixels.end(), data.ptrw());
    Ref<Image> img = Image::create_from_data(sheet.width, sheet.height, false, Image::FORMAT_RGBA8, data);
    TextureSlot slot;
    slot.page = -2;
    slot.paletteRow = key;
    slot.fill = false;
    slot.width = sheet.width;
    slot.height = sheet.height;
    slot.texture = submission::texture(img, submission::TextureSite::Glyph,true);
    slot.texture->set_meta("world_cell", Vector2(glyphs_.tileW(), glyphs_.tileH()));
    const int id = spriteResources_.slots.add(std::move(slot));
    glyphSlots_[key] = id;
    spriteResources_.images[id] = img;
    return id;
}

Color Df3dWorld::glyphRegion(uint8_t tile) const {
    return Color(static_cast<float>(tile % 16) / 16.0f, static_cast<float>(tile / 16) / 16.0f,
                 1.0f / 16.0f, 1.0f / 16.0f);
}

// One cell tall; the width keeps the tileset's cell aspect (8x12 -> 2/3).
Vector2 Df3dWorld::glyphSize() const {
    if (!glyphs_.ready()) return Vector2(1, 1);
    return Vector2(static_cast<float>(glyphs_.tileW()) / static_cast<float>(glyphs_.tileH()), 1.0f);
}

// A unit with no stack and no simple sprite (procedural creatures)
// draws its species' CREATURE_TILE in the raw's colour. The world model
// cannot tell a soldier apart yet (no squad state in UnitState), so the
// creature tile is used, never SOLDIER_TILE.
const Df3dWorld::ItemLook* Df3dWorld::unitGlyphLookFor(const std::string& species) {
    if (!glyphs_.ready() || !source_.model().glyphsKnown()) return nullptr;
    auto it = unitGlyphLooks_.find(species);
    if (it != unitGlyphLooks_.end()) return it->second.slot >= 0 ? &it->second : nullptr;
    ItemLook look;
    if (const wm::CreatureGlyph* cg = source_.model().creatureGlyph(species)) {
        look.creatureDependency = *cg;
        const wm::Glyph g = assets::classicCreatureGlyph(*cg, false);
        look.slot = glyphSlotFor(g.fg, g.bg, g.bright);
        look.region = glyphRegion(g.tile);
        look.size = glyphSize();
        look.kind = 4;
        look.rule = "glyph.creature";
    }
    const ItemLook& stored = unitGlyphLooks_.emplace(species, look).first->second;
    return stored.slot >= 0 ? &stored : nullptr;
}

const Df3dWorld::FaceLook& Df3dWorld::lookFor(const mesher::FaceTag& tag) {
    const uint64_t key = lookKey(tag);
    auto it = faceLooks_.find(key);
    if (it != faceLooks_.end()) return it->second;
    FaceLook look;
    if (assets_) {
        assets::TerrainQuery q;
        q.shape = tag.shape;
        q.kind = tag.materialKind;
        const std::string_view name = source_.model().materialName(tag.material);
        q.material = name;
        q.flags = tag.flags;
        q.side = sideOf(tag.dir);
        q.part = partOf(tag.part);
        q.liquid = tag.liquid;
        q.slope = slopeOf(tag.slopeHigh);
        q.walls = tag.walls;  // same bit layout (mesher kWall* == assets kWall*)
        const assets::TerrainSprite r = assets::resolveTerrain(assets_->index, q);
        if (r.found) {
            if (r.layeredWall) {
                look.slot = wallTopSlotFor(r, q.walls);
                return faceLooks_.emplace(key, look).first->second;
            }
            const int slot = slotFor(r.sprite.page, r.paletteRow, r.fill);
            if (slot >= 0) {
                const TextureSlot& s = spriteResources_.slots[static_cast<size_t>(slot)];
                const assets::PixelRect px = assets_->index.pixels(r.sprite);
                look.slot = slot;
                look.u0 = static_cast<float>(px.px) / s.width;
                look.v0 = static_cast<float>(px.py) / s.height;
                look.u1 = static_cast<float>(px.px + px.pw) / s.width;
                look.v1 = static_cast<float>(px.py + px.ph) / s.height;
                look.cutout = r.cutout;
            }
        }
    }
    return faceLooks_.emplace(key, look).first->second;
}

godot::Array Df3dWorld::tile_spatters(godot::Vector3i tile) const {
    godot::Array out;
    if(tile.x<0 || tile.y<0 || tile.z<0) return out;
    for(const auto& e:source_.model().spattersAt(wm::blockOf({tile.x,tile.y,tile.z}))) {
        if(e.tile!=(tile.y%16)*16+tile.x%16) continue;
        godot::Dictionary value;
        value["material"]=godot::String(std::string(source_.model().materialName(e.material)).c_str());
        value["amount"]=e.amount; value["state"]=int(e.state);
        out.append(value);
    }
    return out;
}

Df3dWorld::FaceLook Df3dWorld::spatterLookFor(wm::TilePos pos) {
    FaceLook look;
    if (!assets_) return look;
    const auto familyFor=[&](const wm::GroundSpatter& e) {
        const auto material=source_.model().materialName(e.material);
        const auto resolved=assets_->index.materialSpatterFamily(material,e.state==wm::MatterState::Liquid);
        return resolved.empty() ? assets::spatterFamily(material) : resolved;
    };
    const auto dominant = [&](wm::TilePos tile) -> assets::SpatterPile {
        if(tile.x<0 || tile.y<0) return {};
        const uint8_t local=uint8_t((tile.y%16)*16+tile.x%16);
        const auto& entries=source_.model().spattersAt(wm::blockOf(tile));
        auto it=std::lower_bound(entries.begin(),entries.end(),local,[](const auto& e,uint8_t value) { return e.tile<value; });
        assets::SpatterPiles piles;
        for(;it!=entries.end() && it->tile==local;++it)
            piles.add(familyFor(*it),it->amount);
        return piles.dominant();
    };
    const auto entry=dominant(pos);
    if(entry.family.empty()) return look;
    const auto& family=entry.family;
    uint8_t neighbors=0;
    const wm::TilePos offsets[]={{0,-1,0},{0,1,0},{-1,0,0},{1,0,0}};
    if(assets::spatterFull(entry.density())) for(int i=0;i<4;++i) {
        const auto other=dominant({pos.x+offsets[i].x,pos.y+offsets[i].y,pos.z});
        if(assets::spatterFull(other.density()) &&
           other.family==family) neighbors|=uint8_t(1<<i);
    }
    const std::string token=family+":"+assets::spatterVariant(entry.density(),neighbors,pos.x,pos.y);
    const auto* sprite=assets_->index.tile(token);
    if(!sprite) return look;
    look.slot=slotFor(sprite->page,-1,false);
    if(look.slot<0) return look;
    const auto& slot=spriteResources_.slots[size_t(look.slot)];
    const auto rect=assets_->index.pixels(*sprite);
    look.u0=float(rect.px)/slot.width;look.v0=float(rect.py)/slot.height;
    look.u1=float(rect.px+rect.pw)/slot.width;look.v1=float(rect.py+rect.ph)/slot.height;
    return look;
}

const Df3dWorld::PreparedUnitArt& Df3dWorld::prepareUnitArt(wm::UnitId id,
    std::chrono::steady_clock::time_point deadline,bool allowOne) {
    auto& art=unitArtCache_[id];
    const auto* appearance=source_.model().unitAppearance(id);
    const uint32_t version=appearance?appearance->version:0;
    const bool layers=appearance && !appearance->layers.empty();
    const auto volume=source_.model().unitBodyVolume(id);
    const bool baby=(source_.model().unitStatusFlags(id) & wm::UnitStatus::Baby)!=0;
    const auto* species=source_.model().unitSpecies(id);
    static const std::string empty;
    const auto& token=species?*species:empty;
    std::optional<wm::CreatureGlyph> glyph;
    if(art.ready && art.key.glyphDependent)
        if(const auto* row=source_.model().creatureGlyph(token))glyph=*row;
    if(art.ready && art.baby==baby && art.key.matches(unitArtGeneration_,version,layers,volume,token,source_.model().glyphsKnown(),glyph)) {
        ++unitArtHits_;return art;
    }
    ++unitArtMisses_;
    art=PreparedUnitArt{};
    art.baby=baby;
    art.color=speciesColor(token);
    bool fallback=true;
    if(layers) {
        const auto* composite=compositeFor(version,appearance->layers,deadline,allowOne);
        if(!composite) { art.kind=3;fallback=false; }
        else if(!composite->failed) {
            art.slot=composite->slot;art.kind=2;art.region=Color(0,0,1,1);art.size=composite->size;fallback=false;
        }
    }
    if(fallback) {
        const auto& look=unitLookFor(token);
        if(look.slot>=0) { art.slot=look.slot;art.kind=1;art.region=look.region;art.size=look.size; }
        else if(const auto* classic=unitGlyphLookFor(token)) {
            art.slot=classic->slot;art.kind=4;art.region=classic->region;art.size=classic->size;
        }
    }
    // Dwarves are the visual baseline, including their native age/appearance variants.
    art.scale=token=="DWARF" && !baby ? Color(1,0,0,1) : unitScaleFor(art.slot,art.region,art.size,volume);
    art.key.resources=unitArtGeneration_;art.key.appearance=version;art.key.hasLayers=layers;
    art.key.volume=volume;art.key.species=token;
    art.key.glyphDependent=art.kind==0 || art.kind==4;
    if(art.key.glyphDependent) {
        art.key.glyphsKnown=source_.model().glyphsKnown();
        if(const auto* row=source_.model().creatureGlyph(token))art.key.glyph=*row;
    }
    // Pending composites retry within the original budget even while paused.
    art.ready=art.kind!=3;
    return art;
}

godot::Color Df3dWorld::unitScaleFor(int slot, Color region, Vector2 size, uint32_t volume) {
    if (slot < 0 || !volume) return Color(1,0,0,1);
    const auto& source = spriteResources_.slots[slot];
    const int x = std::lround(region.r*source.width), y = std::lround(region.g*source.height);
    const int w = std::lround(region.b*source.width), h = std::lround(region.a*source.height);
    if (w <= 0 || h <= 0) return Color(1,0,0,1);
    const auto key = std::make_tuple(slot,x,y,w,h);
    auto found = spriteResources_.metrics.find(key);
    if (found == spriteResources_.metrics.end()) {
        auto& image = spriteResources_.images[slot];
        if (image.is_null()) image = source.texture->get_image();
        if (image.is_null() || image->is_empty()) return Color(1,0,0,1);
        int opaque = 0, bottom = -1;
        for (int py=0; py<h; ++py) for (int px=0; px<w; ++px)
            if (image->get_pixel(x+px,y+py).a >= 128.0f/255.0f) { ++opaque; bottom=py; }
        found = spriteResources_.metrics.emplace(key, Vector2(float(opaque)/(w*h), float(h-1-bottom)/h)).first;
    }
    const float area = found->second.x * size.x * size.y;
    if (area <= 0) return Color(1,0,0,1);
    // Preserve the reference adult dwarf at its original rendered size:
    // 493 opaque pixels on a 32x32, one-cell sprite at 60,000 cm3.
    // Other creatures scale relative to that dwarf, not a terrain meter scale.
    constexpr float dwarfArea = 493.0f / (32.0f * 32.0f);
    const float target = dwarfArea * std::pow(float(volume)/60000.0f, 2.0f/3.0f);
    return Color(std::sqrt(target/area), found->second.y, 0, 1);
}

const Df3dWorld::UnitLook& Df3dWorld::unitLookFor(const std::string& species) {
    auto it = unitLooks_.find(species);
    if (it != unitLooks_.end()) return it->second;
    UnitLook look;
    if (assets_) {
        const assets::CreatureSprite r = assets::resolveCreature(assets_->index, species);
        if (r.found) {
            const int slot = slotFor(r.sprite.page, -1, false);
            if (slot >= 0) {
                const TextureSlot& s = spriteResources_.slots[static_cast<size_t>(slot)];
                const assets::PixelRect px = assets_->index.pixels(r.sprite);
                look.slot = slot;
                look.region = Color(static_cast<float>(px.px) / s.width,
                                    static_cast<float>(px.py) / s.height,
                                    static_cast<float>(px.pw) / s.width,
                                    static_cast<float>(px.ph) / s.height);
                look.size = Vector2(static_cast<float>(r.sprite.w), static_cast<float>(r.sprite.h));
            }
        }
    }
    return unitLooks_.emplace(species, look).first->second;
}

// --- unit appearance composites ---

// The extension's image loader for the compositor: Godot decodes the PNG
// (the only place art is read), the pixels are kept as plain RGBA8 per
// path. Pages and palettes alike; a failure is remembered as nullptr.
const assets::RgbaImage* Df3dWorld::rawImage(const std::string& absPath) {
    auto it = rawImages_.find(absPath);
    if (it != rawImages_.end()) return it->second.get();
    std::unique_ptr<assets::RgbaImage> out;
    Ref<Image> img = Image::load_from_file(String(absPath.c_str()));
    if (img.is_valid() && !img->is_empty()) {
        img->convert(Image::FORMAT_RGBA8);
        out = std::make_unique<assets::RgbaImage>();
        out->width = img->get_width();
        out->height = img->get_height();
        const PackedByteArray data = img->get_data();
        out->pixels.assign(data.ptr(), data.ptr() + data.size());
        if (out->pixels.size() != static_cast<size_t>(out->width) * out->height * 4) out.reset();
    }
    if (!out) {
        godot::UtilityFunctions::printerr("df3d assets: cannot load image ", String(absPath.c_str()));
    }
    return rawImages_.emplace(absPath, std::move(out)).first->second.get();
}

assets::CompositeContext Df3dWorld::compositeContext() {
    assets::CompositeContext ctx;
    ctx.index = assets_ ? &assets_->index : nullptr;
    ctx.installRoot = assets_ ? assets_->install.root : std::string();
    ctx.names.page = [this](wm::PageId id) { return source_.model().tilePageName(id); };
    ctx.names.palette = [this](wm::PaletteId id) { return source_.model().paletteName(id); };
    ctx.load = [this](const std::string& path) { return rawImage(path); };
    return ctx;
}

const Df3dWorld::CompositeSlot* Df3dWorld::compositeFor(
    uint32_t version, const std::vector<wm::AppearanceLayer>& layers,
    std::chrono::steady_clock::time_point deadline, bool force) {
    auto it = spriteResources_.appearances.find(version);
    if (it != spriteResources_.appearances.end()) return &it->second;
    if (!assets_) return nullptr;
    if (!force && compositeBudgetMs_ > 0.0 && std::chrono::steady_clock::now() >= deadline) {
        return nullptr;  // deferred: the caller draws the cube this frame
    }
    const double profileStart = df3d::profiling::timestampUs();
    const assets::CompositeContext ctx = compositeContext();
    PerfScope compositeProfile("appearance.composite_build", nullptr, df3d::profiling::detailed());
    const assets::CompositeResult& r =
        spriteResources_.composites.put(version, assets::compositeAppearance(ctx, layers));
    CompositeSlot cs;
    if (r.ok) {
        PackedByteArray data;
        data.resize(static_cast<int64_t>(r.image.pixels.size()));
        std::copy(r.image.pixels.begin(), r.image.pixels.end(), data.ptrw());
        Ref<Image> img = Image::create_from_data(r.image.width, r.image.height, false,
                                                 Image::FORMAT_RGBA8, data);
        TextureSlot slot;
        slot.page = -1;
        slot.paletteRow = -1;
        slot.fill = false;
        slot.width = r.image.width;
        slot.height = r.image.height;
        const float bodyW = r.cellsX * r.tileW, bodyH = r.cellsY * r.tileH;
        slot.cutoutScale = Vector2(r.image.width / bodyW, r.image.height / bodyH);
        slot.cutoutOffset = Vector2((r.originX + r.image.width * 0.5f) / bodyW - 0.5f,
                                   (r.originY + r.image.height * 0.5f) / bodyH - 0.5f);
        img->fix_alpha_edges();
        img->generate_mipmaps();
        slot.texture = submission::texture(img, submission::TextureSite::Composite,true);
        cs.slot = spriteResources_.slots.add(std::move(slot));
        spriteResources_.images[cs.slot] = img;
        cs.size = Vector2(static_cast<float>(r.cellsX), static_cast<float>(r.cellsY));
    } else {
        cs.failed = true;
        ++compositeFailed_;
        if (compositeWhyPrinted_ < 8) {
            ++compositeWhyPrinted_;
            char head[64];
            std::snprintf(head, sizeof head, "df3d: appearance v%08x not composited: ", version);
            godot::UtilityFunctions::printerr(String(head), String(r.why.c_str()));
        }
    }
    const double ms = df3d::profiling::elapsedMs(profileStart);
    compositeLastMs_ += ms;
    compositeTotalMs_ += ms;
    ++compositeBuildCount_;
    return &spriteResources_.appearances.emplace(version, cs).first->second;
}

int Df3dWorld::dump_unit_composites(const String& dir, const godot::PackedInt64Array& ids,
                                    int max_units) {
    if (!assets_ || !source_.model().hasData()) return 0;
    const std::string d = dir.utf8().get_data();
    godot::DirAccess::make_dir_recursive_absolute(dir);
    std::vector<wm::UnitId> chosen;
    if (ids.size() > 0) {
        for (int64_t i = 0; i < ids.size(); ++i) chosen.push_back(static_cast<wm::UnitId>(ids[i]));
    } else {
        std::set<uint32_t> seen;
        for (wm::UnitId id : source_.model().unitIds()) {
            if (static_cast<int>(chosen.size()) >= max_units) break;
            const wm::EvalResult r = source_.model().evaluate(id, renderTick_);
            if (r.presence != wm::Presence::Present) continue;
            const wm::UnitAppearance* ap = source_.model().unitAppearance(id);
            if (!ap || ap->layers.empty() || !seen.insert(ap->version).second) continue;
            chosen.push_back(id);
        }
    }
    std::string listing;
    std::vector<Ref<Image>> sheet;
    int written = 0;
    for (wm::UnitId id : chosen) {
        const wm::UnitAppearance* ap = source_.model().unitAppearance(id);
        const std::string* species = source_.model().unitSpecies(id);
        char line[256];
        const wm::EvalResult ev = source_.model().evaluate(id, renderTick_);
        int kind = -1;
        for (int64_t i = 0; i < ids_.size(); ++i) {
            if (ids_[i] == static_cast<int64_t>(id)) {
                kind = spriteKinds_[i];
                break;
            }
        }
        std::snprintf(line, sizeof line, "unit %llu %s %s at (%.2f, %.2f, %.2f) drawn as %s",
                      static_cast<unsigned long long>(id), species ? species->c_str() : "?",
                      ev.presence == wm::Presence::Present ? "present" : "absent", ev.pos.x,
                      ev.pos.y, ev.pos.z,
                      kind == 0 ? "cube" : kind == 1 ? "simple sprite" : kind == 2 ? "composite"
                      : kind == 3 ? "pending" : "not listed");
        listing += line;
        if (!ap || ap->layers.empty()) {
            listing += ": no layer stack\n";
            continue;
        }
        const CompositeSlot* cs = compositeFor(ap->version, ap->layers, {}, true);
        const assets::CompositeResult* res = spriteResources_.composites.find(ap->version);
        std::snprintf(line, sizeof line, " v%08x %zu layers%s\n", ap->version, ap->layers.size(),
                      cs && cs->failed ? " FAILED" : "");
        listing += line;
        if (res && !res->why.empty()) listing += "  why: " + res->why + "\n";
        for (size_t i = 0; i < ap->layers.size(); ++i) {
            const wm::AppearanceLayer& l = ap->layers[i];
            std::snprintf(line, sizeof line, "  [%2zu] %s (%u,%u) %ux%u", i,
                          std::string(source_.model().tilePageName(l.page)).c_str(), l.tileX, l.tileY,
                          l.cellsX, l.cellsY);
            listing += line;
            if (l.palette != wm::kNoPalette) {
                std::snprintf(line, sizeof line, " palette %s row %d key %d",
                              std::string(source_.model().paletteName(l.palette)).c_str(), l.paletteRow,
                              l.paletteKeyRow);
                listing += line;
            }
            if (l.offsetX || l.offsetY) {
                std::snprintf(line, sizeof line, " offset (%d,%d)", l.offsetX, l.offsetY);
                listing += line;
            }
            listing += "\n";
        }
        if (!res || !res->ok) continue;
        PackedByteArray data;
        data.resize(static_cast<int64_t>(res->image.pixels.size()));
        std::copy(res->image.pixels.begin(), res->image.pixels.end(), data.ptrw());
        Ref<Image> img = Image::create_from_data(res->image.width, res->image.height, false,
                                                 Image::FORMAT_RGBA8, data);
        char name[128];
        std::snprintf(name, sizeof name, "unit_%llu_%s_v%08x.png",
                      static_cast<unsigned long long>(id), species ? species->c_str() : "unknown",
                      ap->version);
        img->save_png(String((d + "/" + name).c_str()));
        ++written;
        sheet.push_back(img);
    }
    if (!sheet.empty()) {
        // Contact sheet: 4x nearest, 8 per row, cells of the largest sprite,
        // on a mid-grey ground so transparent backgrounds read as grey.
        int cw = 0, ch = 0;
        for (const Ref<Image>& im : sheet) {
            cw = std::max(cw, static_cast<int>(im->get_width()));
            ch = std::max(ch, static_cast<int>(im->get_height()));
        }
        const int k = 4, cols = 8, pad = 4;
        const int rows = static_cast<int>((sheet.size() + cols - 1) / cols);
        Ref<Image> out = Image::create(cols * (cw * k + pad) + pad, rows * (ch * k + pad) + pad,
                                       false, Image::FORMAT_RGBA8);
        out->fill(Color(0.45f, 0.45f, 0.45f, 1.0f));
        for (size_t i = 0; i < sheet.size(); ++i) {
            Ref<Image> im = sheet[i]->duplicate();
            im->resize(im->get_width() * k, im->get_height() * k, Image::INTERPOLATE_NEAREST);
            const int x = pad + static_cast<int>(i % cols) * (cw * k + pad);
            const int y = pad + static_cast<int>(i / cols) * (ch * k + pad);
            out->blend_rect(im, godot::Rect2i(0, 0, im->get_width(), im->get_height()),
                            godot::Vector2i(x, y));
        }
        out->save_png(String((d + "/composites_sheet.png").c_str()));
    }
    Ref<godot::FileAccess> f =
        godot::FileAccess::open(String((d + "/composites.txt").c_str()), godot::FileAccess::WRITE);
    if (f.is_valid()) f->store_string(String(listing.c_str()));
    godot::UtilityFunctions::print("df3d: dumped ", written, " composites to ", dir);
    return written;
}

Ref<godot::Material> Df3dWorld::materialFor(const SurfaceKey& key) {
    auto it = materials_.find(key);
    if (it != materials_.end()) return it->second;
    // Terrain bodies and the undisclosed mass: the two-sided shader.
    if (key.kind == kSurfOpaque || key.kind == kSurfCutout || key.kind == kSurfHidden) {
        if (terrainShader_.is_null()) {
            terrainShader_ = godot::ResourceLoader::get_singleton()->load("res://shaders/terrain.gdshader");
            terrainCutoutShader_ = godot::ResourceLoader::get_singleton()->load("res://shaders/terrain_cutout.gdshader");
        }
        Ref<ShaderMaterial> sm;
        sm.instantiate();
        sm->set_shader(key.kind == kSurfCutout ? terrainCutoutShader_ : terrainShader_);
        Dictionary parameters;
        if (key.spatterSlot >= 0) {
            parameters["spatter_cell"] = spriteResources_.slots[static_cast<size_t>(key.spatterSlot)].texture->get_meta("world_cell", Vector2());
            parameters["spattered"] = true;
            parameters["spatter_tex"] = spriteResources_.slots[static_cast<size_t>(key.spatterSlot)].texture;
        }
        if (key.kind == kSurfHidden) {
            parameters["rock_backing"] = true;
            parameters["rock_backing_color"] = rock_backing_color();
        }
        if (key.slot >= 0) {
            parameters["albedo_tex"] = spriteResources_.slots[static_cast<size_t>(key.slot)].texture;
            parameters["albedo_cell"] = spriteResources_.slots[static_cast<size_t>(key.slot)].texture->get_meta("world_cell", Vector2());
            parameters["textured"] = true;
        }
        configureImmutableMaterial(sm,parameters);
        materials_[key] = sm;
        return sm;
    }
    // Everything else (liquids, building decals) stays a StandardMaterial3D,
    // unshaded: DF's art is pre-shaded and there is no scene light.
    Ref<StandardMaterial3D> m;
    m.instantiate();
    m->set_flag(StandardMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
    m->set_shading_mode(StandardMaterial3D::SHADING_MODE_UNSHADED);
    m->set_roughness(1.0f);
    m->set_specular(0.1f);
    if (key.slot >= 0) {
        m->set_texture(StandardMaterial3D::TEXTURE_ALBEDO, spriteResources_.slots[static_cast<size_t>(key.slot)].texture);
        m->set_texture_filter(StandardMaterial3D::TEXTURE_FILTER_NEAREST_WITH_MIPMAPS);
    }
    switch (key.kind) {
        case kSurfOpaque:
        case kSurfCutout:
        case kSurfHidden: break;
        case kSurfWater:
            m->set_transparency(StandardMaterial3D::TRANSPARENCY_ALPHA);
            m->set_roughness(0.2f);
            m->set_specular(0.6f);
            break;
        case kSurfMagma:
            m->set_transparency(StandardMaterial3D::TRANSPARENCY_ALPHA);
            m->set_feature(StandardMaterial3D::FEATURE_EMISSION, true);
            m->set_emission(Color(1.0f, 0.35f, 0.05f));
            m->set_emission_energy_multiplier(key.slot >= 0 ? 0.8f : 1.5f);
            m->set_roughness(0.6f);
            break;
        case kSurfDecal:
            // Building tiles lie flat on the slab; DF's art is pre-shaded,
            // and a lit top face gets the same 1.0 shade as terrain tops.
            m->set_transparency(StandardMaterial3D::TRANSPARENCY_ALPHA_SCISSOR);
            m->set_alpha_scissor_threshold(0.5f);
            break;
        case kSurfGhost:
            m->set_transparency(StandardMaterial3D::TRANSPARENCY_ALPHA);
            m->set_cull_mode(StandardMaterial3D::CULL_DISABLED);
            break;
    }
    materials_[key] = m;
    return m;
}

}
