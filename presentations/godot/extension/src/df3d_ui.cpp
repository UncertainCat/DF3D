#include "submission_uploads.h"
#include "df3d_world.h"
#include <algorithm>
#include <cmath>
#include <limits>

using namespace godot;
namespace df3d_godot {
Dictionary Df3dWorld::elevation_overview(int x, int y) const {
    Dictionary out;
    const auto size = source_.model().mapSize();
    out["level_count"] = size.z;
    out["surface_z"] = -1;
    if (!source_.model().hasTerrain() || x < 0 || y < 0 || x >= size.x || y >= size.y) return out;
    // This is a presentation query over known terrain, not a reveal of hidden
    // caves. The silhouette uses the highest known outdoor ground in this column.
    for (int z = size.z - 1; z >= 0; --z) {
        const auto tile = source_.model().tileAt({x, y, z});
        if (!tile || (tile->flags & wm::kTileHidden) || !(tile->flags & wm::kTileOutside)) continue;
        if (tile->shape == wm::TileShape::Empty || tile->shape == wm::TileShape::RampTop ||
            tile->shape == wm::TileShape::Unknown || tile->materialKind == wm::MaterialKind::Wood ||
            tile->materialKind == wm::MaterialKind::Plant) continue;
        out["surface_z"] = z;
        break;
    }
    return out;
}
Ref<Texture2D> Df3dWorld::ui_texture(const String& name, int variant) {
    if (!assets_) return {};
    const std::string nameKey = name.utf8().get_data();
    const std::string key = nameKey + ":" + std::to_string(variant);
    if (const auto it = uiTextures_.find(key); it != uiTextures_.end()) return it->second;
    const auto& index = assets_->index;
    const auto* layout = variant < 0 ? index.layout(nameKey) : nullptr;
    const auto* single = index.tile(nameKey, variant < 0 ? 0 : size_t(variant));
    if (!layout && !single) return {};
    const auto* first = layout ? layout->tile(-1, 0, 0) : single;
    if (!first) return {};
    const auto* page = index.page(first->page);
    if (!page) return {};
    const int width = layout ? layout->width : first->w;
    const int height = layout ? layout->height : first->h;
    Ref<Image> composite = Image::create_empty(width * page->tileW, height * page->tileH, false, Image::FORMAT_RGBA8);
    composite->fill(Color(0,0,0,0));
    auto copy = [&](const df3d::assets::SpriteRef& sprite, int x, int y) {
        const int slot = slotFor(sprite.page, -1, false);
        if (slot < 0) return;
        const auto rect = index.pixels(sprite);
        composite->blit_rect(spriteResources_.slots[slot].texture->get_image(), Rect2i(rect.px, rect.py, rect.pw, rect.ph), Vector2i(x * page->tileW, y * page->tileH));
    };
    if (layout) {
        for (int y=0; y<height; ++y) for (int x=0; x<width; ++x)
            if (const auto* sprite=layout->tile(-1,x,y)) copy(*sprite,x,y);
    } else copy(*single,0,0);
    Ref<Texture2D> texture = submission::texture(composite, submission::TextureSite::Ui);
    uiTextures_[key] = texture;
    return texture;
}
String Df3dWorld::ui_font_path() const {
    return assets_ ? String::utf8(assets_->classicTileset.absPath.c_str()) : String();
}
Array Df3dWorld::buildings_at_tile(const Vector3i& tile) const {
    Array out;
    const auto state = source_.model().tileAt({tile.x,tile.y,tile.z});
    if (!state || (state->flags & wm::kTileHidden)) return out;
    for (const auto* b : source_.model().buildingsInRect(tile.x,tile.y,tile.x,tile.y,tile.z)) {
        if (!b->occupies(tile.x,tile.y)) continue;
        Dictionary row;
        row["id"] = int64_t(b->id);
        row["name"] = String(wm::buildingKindName(b->kind));
        row["forbidden"] = bool(b->flags & wm::kBuildingForbidden);
        row["can_forbid"] = b->kind == wm::BuildingKind::Door || b->kind == wm::BuildingKind::Hatch;
        row["complete"] = b->stage == wm::BuildingStage::Complete;
        out.push_back(row);
    }
    return out;
}
Vector3i Df3dWorld::unit_tile(int64_t id) const {
    // Display/depth arrays retain WorldModel::unitIds() sorted order.
    const auto entry=std::lower_bound(depthUnitContents_.begin(),depthUnitContents_.end(),id,
        [](const auto& value,int64_t key){return std::get<0>(value)<key;});
    if(entry!=depthUnitContents_.end() && std::get<0>(*entry)==id) {
        const wm::TilePos p{std::get<1>(*entry),std::get<2>(*entry),std::get<3>(*entry)};
        const auto tile=source_.model().tileAt(p);
        if(tile && !(tile->flags & wm::kTileHidden)) return Vector3i(p.x,p.y,p.z);
    }
    return Vector3i(-1,-1,-1);
}
Dictionary Df3dWorld::pick_building(const Vector3& origin, const Vector3& direction, int z) const {
    Dictionary out;
    float nearest = std::numeric_limits<float>::infinity();
    uint32_t nearestId = UINT32_MAX;
    for (const auto* b : source_.model().buildingsAt(z)) {
        const auto built = builtBuildings_.find(b->id);
        if (built == builtBuildings_.end() || !built->second.node) continue;
        const auto mesh = built->second.node->get_mesh();
        if (mesh.is_null()) continue;
        const auto faces = mesh->get_faces();
        for (int i=0; i+2<faces.size(); i+=3) {
            const Vector3 a=faces[i], edge1=faces[i+1]-a, edge2=faces[i+2]-a;
            const Vector3 p=direction.cross(edge2);
            const float det=edge1.dot(p);
            if (std::abs(det)<0.000001f) continue;
            const float inv=1.0f/det;
            const Vector3 t=origin-a;
            const float u=t.dot(p)*inv;
            if(u<0 || u>1) continue;
            const Vector3 q=t.cross(edge1);
            const float v=direction.dot(q)*inv;
            if(v<0 || u+v>1) continue;
            const float distance=edge2.dot(q)*inv;
            if(distance<0 || distance>nearest || (distance==nearest && b->id>=nearestId)) continue;
            const Vector3 hit=origin+direction*distance;
            const wm::TilePos tile{std::clamp(int(std::floor(hit.x)),b->x1,b->x2),std::clamp(int(std::floor(hit.z)),b->y1,b->y2),z};
            const auto state=source_.model().tileAt(tile);
            if(!state || (state->flags & wm::kTileHidden) || !b->occupies(tile.x,tile.y)) continue;
            nearest=distance; nearestId=b->id;
            out["id"]=int64_t(b->id);
            out["depth"]=origin.distance_squared_to(hit);
            out["tile"]=Vector3i(tile.x,tile.y,tile.z);
        }
    }
    return out;
}
} // namespace df3d_godot
