#include "submission_uploads.h"
#include "df3d_world.h"
#include <algorithm>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/atlas_texture.hpp>

using namespace godot;
namespace df3d_godot {

Ref<Texture2D> Df3dWorld::creature_portrait(int64_t id) {
    if(id<0 || id>INT32_MAX || !assets_)return {};
    const auto snapshot=creatureInfo_.snapshot(int32_t(id));
    if(!snapshot || !sessionClient_ || !sessionClient_->state().fortressValid ||
       snapshot->worldEpoch!=sessionClient_->state().fortressEpoch || unit_tile(id).x<0)return {};
    return composite_portrait(snapshot->detail.portrait);
}
Ref<Texture2D> Df3dWorld::composite_portrait(const wm::SelectionAppearance& source) {
    if(source==selectionPortraitSource_ && selectionPortraitTexture_.is_valid())return selectionPortraitTexture_;
    selectionPortraitSource_=source;
    selectionPortraitTexture_=composite_appearance_texture(source,true);
    return selectionPortraitTexture_;
}
Ref<Texture2D> Df3dWorld::composite_appearance_texture(const wm::SelectionAppearance& source, bool framed) {
    if(!assets_ || source.layers.empty())return {};
    auto context=compositeContext();
    context.names.page=[&source](wm::PageId id)->std::string_view {
        return id<source.tilePages.size() ? std::string_view(source.tilePages[id]) : std::string_view();
    };
    context.names.palette=[&source](wm::PaletteId id)->std::string_view {
        return id<source.palettes.size() ? std::string_view(source.palettes[id]) : std::string_view();
    };
    const auto result=df3d::assets::compositeAppearance(context,source.layers);
    if (!result.ok) {lastError_=String::utf8(result.why.c_str());return {};}
    PackedByteArray bytes;bytes.resize(int64_t(result.image.pixels.size()));
    std::copy(result.image.pixels.begin(),result.image.pixels.end(),bytes.ptrw());
    auto portrait=Image::create_from_data(result.image.width,result.image.height,false,Image::FORMAT_RGBA8,bytes);
    // Native cached portraits include these original presentation assets around
    // the creature's PORTRAIT layers (DF53.16 reference captures). Keep this
    // framing in layer 4, outside the bridge's creature appearance recipe.
    const auto background=framed?ui_texture("DEFAULT_PORTRAIT_BACKGROUND",-1):Ref<Texture2D>{};
    const auto frame=framed?ui_texture("DEFAULT_PORTRAIT_FRAME",-1):Ref<Texture2D>{};
    if (framed && background.is_valid() && frame.is_valid() &&
        background->get_width()==portrait->get_width() && background->get_height()==portrait->get_height()) {
        auto canvas=background->get_image();
        const Rect2i rect(0,0,portrait->get_width(),portrait->get_height());
        canvas->blend_rect(portrait,rect,Vector2i());
        canvas->blend_rect(frame->get_image(),rect,Vector2i());
        portrait=canvas;
    }
    return submission::texture(portrait, submission::TextureSite::Portrait);
}

Ref<Texture2D> Df3dWorld::selection_icon(int kind,int64_t id) {
    if (id<0 || id>UINT32_MAX || !source_.model().hasData()) return {};
    int slot=-1;
    Color region;
    if (kind==1) {
        for (int64_t i=0;i<ids_.size();++i) if (ids_[i]==id) {
            slot=spriteSlots_[i];region=spriteRegions_[i];break;
        }
        // Roster thumbnails consume resident actor appearance even when the
        // actor is outside the current render window. Reuse the render art
        // cache; never request a native screen or reveal an unknown actor.
        if(slot<0 && assets_ && unit_tile(id).x>=0 && source_.model().unitSpecies(wm::UnitId(id))) {
            const auto& art=prepareUnitArt(wm::UnitId(id),
                std::chrono::steady_clock::now()+std::chrono::milliseconds(1),true);
            slot=art.slot;region=art.region;
        }
    } else if (kind==2) {
        for (int64_t i=0;i<itemIds_.size();++i) if (itemIds_[i]==id) {
            slot=itemSlots_[i];region=itemRegions_[i];break;
        }
        if (slot<0) {
            const auto* item=source_.model().item(wm::ItemId(id));
            if (item && tileVisible(item->pos)) {
                const auto& look=itemLookFor(*item);slot=look.slot;region=look.region;
            }
        }
        // Carried items intentionally do not inhabit the terrain item stream.
        // Resolve their resident semantic description without an extra RPC or
        // requiring a native inventory screen. The snapshot bounds this scan.
        if(slot<0 && assets_ && creatureInfoConverted_ && sessionClient_ &&
           sessionClient_->state().fortressValid &&
           creatureInfoConverted_->worldEpoch==sessionClient_->state().fortressEpoch &&
           unit_tile(creatureInfoConverted_->detail.unitId).x>=0) {
            for(const auto& section:creatureInfoConverted_->detail.sections) {
                if(int(section.kind)!=4 || !section.available)continue;
                for(const auto& row:section.records) {
                    if(row.id!=id)continue;
                    df3d::assets::ItemQuery query;
                    std::string_view colorToken;
                    for(const auto& fact:row.facts) {
                        if(fact.key=="item_type" && fact.hasNumber && fact.number>=0 &&
                           fact.number<int(wm::ItemKind::Branch))query.kind=wm::ItemKind(int(fact.number)+1);
                        else if(fact.key=="subtype_raw")query.subtypeRaw=fact.text;
                        else if(fact.key=="material_token")query.material=fact.text;
                        else if(fact.key=="color_token")colorToken=fact.text;
                        else if(fact.key=="stack" && fact.hasNumber)query.stack=uint32_t(std::max<int64_t>(1,fact.number));
                    }
                    const auto resolved=df3d::assets::resolveItem(assets_->index,query);
                    if(!resolved.found)continue;
                    const int palette=colorToken.empty()?resolved.paletteRow:assets_->index.paletteRow(colorToken);
                    slot=slotFor(resolved.sprite.page,palette,false);
                    if(slot<0)continue;
                    const auto& texture=spriteResources_.slots[slot];
                    const auto px=assets_->index.pixels(resolved.sprite);
                    region=Color(float(px.px)/texture.width,float(px.py)/texture.height,
                                 float(px.pw)/texture.width,float(px.ph)/texture.height);
                    break;
                }
            }
        }
    } else if (kind==3 && assets_) {
        const auto* building=source_.model().building(wm::BuildingId(id));
        // Multi-tile sheet icons have their own native composition. Do not
        // invent a thumbnail by choosing an arbitrary workshop corner.
        if (!building || building->width()!=1 || building->height()!=1 ||
            !tileVisible({building->x1,building->y1,building->z})) return {};
        df3d::assets::BuildingQuery query;
        query.kind=building->kind;query.subtype=building->subtype;query.custom=building->custom;
        query.stage=building->stage;query.width=1;query.height=1;query.flags=building->flags;
        query.material=source_.model().materialName(building->material);query.extents=&building->extents;
        const auto resolved=df3d::assets::resolveBuildingTiles(assets_->index,query);
        std::vector<std::pair<int,Color>> layers;
        for (const auto& tile:resolved.tiles) {
            if (tile.lx!=0 || tile.ly!=0) continue;
            const int page=slotFor(tile.sprite.page,resolved.paletteRow,false);
            if (page<0) continue;
            const auto& texture=spriteResources_.slots[page];const auto pixels=assets_->index.pixels(tile.sprite);
            layers.push_back({page,Color(float(pixels.px)/texture.width,float(pixels.py)/texture.height,
                float(pixels.pw)/texture.width,float(pixels.ph)/texture.height)});
        }
        if (layers.empty()) return {};
        slot=layers.size()==1 ? layers[0].first : compositeBuildingTile(layers);
        region=layers.size()==1 ? layers[0].second : Color(0,0,1,1);
    }
    if (!spriteResources_.slots.contains(slot)) return {};
    const auto& texture=spriteResources_.slots[slot];
    Ref<AtlasTexture> icon;icon.instantiate();icon->set_atlas(texture.texture);
    icon->set_region(Rect2(region.r*texture.width,region.g*texture.height,region.b*texture.width,region.a*texture.height));
    return icon;
}
} // namespace df3d_godot
