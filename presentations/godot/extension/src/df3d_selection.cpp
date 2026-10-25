#include "submission_uploads.h"
#include "df3d_world.h"
#include "df3d_assets/bed.h"
#include "df3d_assets/gem.h"
#include <algorithm>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/atlas_texture.hpp>

using namespace godot;
namespace df3d_godot {

int Df3dWorld::bedSlot(std::string_view material, const wm::BeddingFacts& bedding) {
    if(!assets_)return -1;
    const auto part=[](std::string_view s){return std::to_string(s.size())+":"+std::string(s);};
    const std::string key="bed:"+part(material)+":"+std::to_string(bedding.sheet)+":"+
        std::to_string(bedding.pillow)+":"+part(bedding.baseColor)+part(bedding.sheetColor);
    const auto retained=spriteResources_.items.find(key);
    if(retained!=spriteResources_.items.end())return retained->second;
    const auto result=df3d::assets::compositeBed(compositeContext(),material,bedding);
    if(!result.ok)return -1;
    PackedByteArray bytes;bytes.resize(int64_t(result.image.pixels.size()));
    std::copy(result.image.pixels.begin(),result.image.pixels.end(),bytes.ptrw());
    auto image=Image::create_from_data(result.image.width,result.image.height,false,Image::FORMAT_RGBA8,bytes);
    image->generate_mipmaps();
    TextureSlot composite;composite.width=result.image.width;composite.height=result.image.height;
    composite.texture=submission::texture(image,submission::TextureSite::Composite,true);
    const int slot=spriteResources_.slots.add(std::move(composite));
    if(slot<0)return -1;
    spriteResources_.images[slot]=image;spriteResources_.items[key]=slot;
    return slot;
}

Ref<Texture2D> Df3dWorld::construction_item_icon(int itemType,const Dictionary& appearance,bool genericGroup,int64_t itemId) {
    if(!assets_ || itemType<0 || itemType>=int(wm::ItemKind::BoltThrowerParts) ||
       appearance.size()!=5+int(appearance.has("bedding"))+int(appearance.has("instrument"))+int(appearance.has("slab_engraving"))+int(appearance.has("gem_shape_raw")))return {};
    if(itemId < -1 || itemId>INT32_MAX)return {};
    std::string gemShape;
    if(appearance.has("gem_shape_raw")) {
        if(itemType!=1 || appearance["gem_shape_raw"].get_type()!=Variant::STRING)return {};
        const String shape=appearance["gem_shape_raw"];
        if(shape.is_empty() || shape.utf8().length()>128)return {};
        gemShape=shape.utf8().get_data();
    }
    int8_t slabEngraving=-2;
    if(appearance.has("slab_engraving")) {
        if(itemType+1!=int(wm::ItemKind::Slab) || appearance["slab_engraving"].get_type()!=Variant::INT)return {};
        const int64_t value=appearance["slab_engraving"];
        if(value < -1 || value > 26)return {};
        slabEngraving=int8_t(value);
    }
    int8_t instrumentFamily=-1,instrumentPlaced=-1;
    if(appearance.has("instrument")) {
        if(itemType+1!=int(wm::ItemKind::Instrument) || appearance["instrument"].get_type()!=Variant::DICTIONARY)return {};
        const Dictionary instrument=appearance["instrument"];
        if(instrument.size()!=2 || !instrument.has("family") || !instrument.has("placed") ||
           instrument["family"].get_type()!=Variant::INT || instrument["placed"].get_type()!=Variant::INT)return {};
        const int64_t family=instrument["family"],placed=instrument["placed"];
        if(family<0 || family>3 || placed<0 || placed>1)return {};
        instrumentFamily=int8_t(family);instrumentPlaced=int8_t(placed);
    }
    wm::BeddingFacts beddingFacts;
    if(appearance.has("bedding")) {
        if(itemType+1!=int(wm::ItemKind::Bed) || appearance["bedding"].get_type()!=Variant::DICTIONARY)return {};
        const Dictionary bedding=appearance["bedding"];
        if(bedding.size()!=4)return {};
        for(const auto* field:{"sheet","pillow"})
            if(!bedding.has(field) || bedding[field].get_type()!=Variant::INT)return {};
        for(const auto* field:{"base_color","sheet_color"}) {
            if(!bedding.has(field) || bedding[field].get_type()!=Variant::STRING)return {};
            const String value=bedding[field];
            if(value.utf8().length()>128)return {};
        }
        const int64_t sheet=bedding["sheet"],pillow=bedding["pillow"];
        if(sheet<0 || sheet>1 || pillow<0 || pillow>2)return {};
        beddingFacts.sheet=int8_t(sheet);beddingFacts.pillow=int8_t(pillow);
        const String base=bedding["base_color"],sheetColor=bedding["sheet_color"];
        beddingFacts.baseColor=base.utf8().get_data();beddingFacts.sheetColor=sheetColor.utf8().get_data();
    }
    for(const auto* field:{"material_token","subtype_raw","color_token"})
        if(!appearance.has(field) || appearance[field].get_type()!=Variant::STRING)return {};
    for(const auto* field:{"stack","flags"})
        if(!appearance.has(field) || appearance[field].get_type()!=Variant::INT)return {};
    const String material=appearance["material_token"],subtype=appearance["subtype_raw"],color=appearance["color_token"];
    const int64_t stack=appearance["stack"],flags=appearance["flags"];
    if(material.is_empty() || material.utf8().length()>256 || subtype.utf8().length()>128 ||
       color.utf8().length()>128 || stack<1 || stack>INT32_MAX || flags<0 || (flags & ~int64_t(96)))return {};
    // Candidate snapshots own these facts independently of terrain residency.
    // No native texture, UI state or item pointer is consulted here.
    const std::string materialToken=material.utf8().get_data(),subtypeRaw=subtype.utf8().get_data(),colorToken=color.utf8().get_data();
    if(itemType==1 && !genericGroup && !gemShape.empty() && itemId>=0 &&
       assets_->index.tile("GEM_SHAPE:"+gemShape)) {
        df3d::assets::ItemQuery gemQuery;gemQuery.kind=wm::ItemKind::SmallGem;gemQuery.material=materialToken;
        const auto generic=df3d::assets::resolveItem(assets_->index,gemQuery);
        const std::string gemColor=colorToken.empty()?generic.colorName:colorToken;
        const unsigned variant=df3d::assets::gemVariant(uint32_t(itemId));
        const std::string key="gem:"+std::to_string(gemShape.size())+":"+gemShape+":"+
            std::to_string(variant)+":"+gemColor;
        const auto found=spriteResources_.items.find(key);
        if(found!=spriteResources_.items.end()) {
            const auto* slot=spriteResources_.slots.find(found->second);
            if(slot)return slot->texture;
            return {};
        }
        const auto result=df3d::assets::compositeGem(compositeContext(),gemShape,uint32_t(itemId),gemColor);
        if(!result.ok)return {};
        PackedByteArray bytes;bytes.resize(int64_t(result.image.pixels.size()));
        std::copy(result.image.pixels.begin(),result.image.pixels.end(),bytes.ptrw());
        auto image=Image::create_from_data(32,32,false,Image::FORMAT_RGBA8,bytes);
        image->generate_mipmaps();
        TextureSlot composite;composite.width=32;composite.height=32;
        composite.texture=submission::texture(image,submission::TextureSite::Composite,true);
        const int slot=spriteResources_.slots.add(std::move(composite));
        if(slot<0)return {};
        spriteResources_.images[slot]=image;spriteResources_.items[key]=slot;
        return spriteResources_.slots.find(slot)->texture;
    }
    if(beddingFacts.sheet>=0) {
        const int slot=bedSlot(materialToken,beddingFacts);
        const TextureSlot* texture=slot>=0?spriteResources_.slots.find(slot):nullptr;
        if(texture)return texture->texture;
        return {};
    }
    df3d::assets::ItemQuery query;query.kind=wm::ItemKind(itemType+1);query.material=materialToken;
    query.subtypeRaw=subtypeRaw;query.stack=uint32_t(stack);query.flags=uint8_t(flags);
    query.instrumentFamily=instrumentFamily;query.instrumentPlaced=instrumentPlaced;
    query.slabEngraving=genericGroup && query.kind==wm::ItemKind::Slab ? 0 : slabEngraving;
    const auto resolved=df3d::assets::resolveItem(assets_->index,query);
    if(!resolved.found)return {};
    const bool rawSlab=query.kind==wm::ItemKind::Slab && (genericGroup || (slabEngraving>=1 && slabEngraving<=5));
    const int palette=rawSlab ? -1 : colorToken.empty()?resolved.paletteRow:assets_->index.paletteRow(colorToken);
    if(!colorToken.empty() && palette<0 && !rawSlab)return {};
    const int slot=slotFor(resolved.sprite.page,palette,false);
    const TextureSlot* texture=slot>=0?spriteResources_.slots.find(slot):nullptr;
    if(!texture || texture->texture.is_null())return {};
    const auto pixels=assets_->index.pixels(resolved.sprite);
    Ref<AtlasTexture> icon;icon.instantiate();icon->set_atlas(texture->texture);
    icon->set_region(Rect2(pixels.px,pixels.py,pixels.pw,pixels.ph));return icon;
}

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

Ref<Texture2D> Df3dWorld::selection_icon(int kind,int64_t id,bool body_cell) {
    if (id<0 || id>UINT32_MAX || !source_.model().hasData()) return {};
    int slot=-1;
    Color region;
    if (kind==1) {
        for (int64_t i=0;!body_cell && i<ids_.size();++i) if (ids_[i]==id) {
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
                           fact.number<int(wm::ItemKind::BoltThrowerParts))query.kind=wm::ItemKind(int(fact.number)+1);
                        else if(fact.key=="subtype_raw")query.subtypeRaw=fact.text;
                        else if(fact.key=="material_token")query.material=fact.text;
                        else if(fact.key=="color_token")colorToken=fact.text;
                        else if(fact.key=="stack" && fact.hasNumber)query.stack=uint32_t(std::max<int64_t>(1,fact.number));
                    }
                    const auto resolved=df3d::assets::resolveItem(assets_->index,query);
                    if(!resolved.found)continue;
                    const int palette=colorToken.empty()?resolved.paletteRow:assets_->index.paletteRow(colorToken);
                    slot=slotFor(resolved.sprite.page,palette,false);
                    const TextureSlot* found=slot>=0?spriteResources_.slots.find(slot):nullptr;
                    if(!found){slot=-1;continue;}
                    const auto& texture=*found;
                    const auto px=assets_->index.pixels(resolved.sprite);
                    region=Color(float(px.px)/texture.width,float(px.py)/texture.height,
                                 float(px.pw)/texture.width,float(px.ph)/texture.height);
                    break;
                }
            }
        }
    } else if (kind==3 && assets_) {
        const auto* building=source_.model().building(wm::BuildingId(id));
        if (!building || !tileVisible({building->x1,building->y1,building->z})) return {};
        // Native pump headers use this fixed icon for all four intake directions.
        if (building->kind==wm::BuildingKind::ScrewPump)
            return ui_texture("BUILDING_ICON_SCREW_PUMP",-1);
        if (building->kind==wm::BuildingKind::Trap && building->subtype==5)
            return ui_texture("BUILDING_ICON_TRACK_STOP",-1);
        if (building->kind==wm::BuildingKind::Rollers)
            return ui_texture("BUILDING_ICON_ROLLERS",-1);
        if (building->kind==wm::BuildingKind::Instrument)
            return ui_texture("BUILDING_ICON_INSTRUMENT",-1);
        // Multi-tile sheet icons have their own native composition. Do not
        // invent a thumbnail by choosing an arbitrary workshop corner.
        if (building->width()!=1 || building->height()!=1) return {};
        df3d::assets::BuildingQuery query;
        query.kind=building->kind;query.subtype=building->subtype;query.custom=building->custom;
        query.stage=building->stage;query.width=1;query.height=1;query.flags=building->flags;
        query.material=source_.model().materialName(building->material);query.extents=&building->extents;
        query.statue=building->statue;
        query.pumpDirection=building->pumpDirection;query.horizontalAxleVertical=building->horizontalAxleVertical;query.slabEngraving=building->slabEngraving;query.verticalBarsConnections=building->verticalBarsConnections;
        query.constructionItemIsLog=building->constructionItemIsLog;query.constructionItemMaterial=source_.model().materialName(building->constructionItemMaterial);
        query.bridgeDirection=building->bridge.direction;query.bridgeRaised=building->bridge.raised;
        const auto resolved=df3d::assets::resolveBuildingTiles(assets_->index,query);
        std::vector<std::pair<int,Color>> layers;
        for (const auto& tile:resolved.tiles) {
            if (tile.lx!=0 || tile.ly!=0) continue;
            if(building->kind==wm::BuildingKind::Bed && building->bedding.sheet>=0) {
                const int bed=bedSlot(query.material,building->bedding);
                if(bed>=0)layers.push_back({bed,Color(0,0,1,1)});
                continue;
            }
            const int page=buildingSlotFor(building->kind,building->stage,tile.sprite.page,resolved.paletteRow,building->subtype,resolved.plannedHalfAlpha);
            const TextureSlot* found=page>=0?spriteResources_.slots.find(page):nullptr;
            if (!found) continue;
            const auto& texture=*found;const auto pixels=assets_->index.pixels(tile.sprite);
            layers.push_back({page,Color(float(pixels.px)/texture.width,float(pixels.py)/texture.height,
                float(pixels.pw)/texture.width,float(pixels.ph)/texture.height)});
        }
        if (layers.empty()) return {};
        const bool half=building->kind==wm::BuildingKind::BarsVertical && building->stage!=wm::BuildingStage::Complete;
        const bool direct=layers.size()==1 && !half;
        slot=direct ? layers[0].first : compositeBuildingTile(layers,half);
        region=direct ? layers[0].second : Color(0,0,1,1);
    }
    const TextureSlot* found=spriteResources_.slots.find(slot);
    if (!found || found->texture.is_null()) return {};
    const auto& texture=*found;
    Ref<AtlasTexture> icon;icon.instantiate();icon->set_atlas(texture.texture);
    Rect2 pixels(region.r*texture.width,region.g*texture.height,region.b*texture.width,region.a*texture.height);
    // Native staff selectors use the logical body cell, excluding wieldable
    // overflow. Preserve the compositor's origin instead of shrinking the full
    // canvas or assuming that its body always occupies the bottom-right corner.
    if(kind==1 && body_cell) {
        const auto* appearance=source_.model().unitAppearance(wm::UnitId(id));
        if(appearance) {
            const auto entry=spriteResources_.appearances.find(appearance->version);
            const auto* composite=spriteResources_.composites.find(appearance->version);
            if(entry!=spriteResources_.appearances.end() && entry->second.slot==slot && composite && composite->ok)
                pixels=Rect2(-composite->originX,-composite->originY,
                    composite->cellsX*composite->tileW,composite->cellsY*composite->tileH);
        }
    }
    icon->set_region(pixels);
    return icon;
}
} // namespace df3d_godot
