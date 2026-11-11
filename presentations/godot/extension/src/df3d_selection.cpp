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
    return itemIcon(itemType,appearance,genericGroup,itemId,false);
}
Ref<Texture2D> Df3dWorld::item_sheet_icon(int itemType,const Dictionary& appearance,int64_t itemId) {
    return itemIcon(itemType,appearance,false,itemId,true);
}
Ref<Texture2D> Df3dWorld::ammunition_icon(const Dictionary& appearance,int64_t itemId) {
    return itemIcon(39,appearance,false,itemId,true,true);
}
Ref<Texture2D> Df3dWorld::itemIcon(int itemType,const Dictionary& appearance,bool genericGroup,int64_t itemId,bool sheet,bool diagonalAmmo) {
    if(!assets_ || itemType<0 || itemType>=int(wm::ItemKind::BoltThrowerParts) ||
       appearance.size()!=5+int(appearance.has("bedding"))+int(appearance.has("instrument"))+int(appearance.has("slab_engraving"))+int(appearance.has("gem_shape_raw"))+int(appearance.has("contents"))+int(appearance.has("artifact_mood"))+int(appearance.has("floodgate_open"))+int(appearance.has("door"))+int(appearance.has("bucket_liquid"))+int(appearance.has("cage"))+int(appearance.has("restraint"))+int(appearance.has("portrait"))+int(appearance.has("corpse_selector"))+int(appearance.has("legwear_selector"))+int(appearance.has("craft_gem_color")))return {};
    if(itemId < -1 || itemId>INT32_MAX)return {};
    if(appearance.has("legwear_selector")) {
        if(itemType!=60 || appearance["legwear_selector"].get_type()!=Variant::DICTIONARY)return {};
        return candidateIcon(appearance["legwear_selector"],false);
    }
    if(appearance.has("corpse_selector")) {
        if((itemType!=23 && itemType!=46) || appearance["corpse_selector"].get_type()!=Variant::DICTIONARY)return {};
        return candidateIcon(appearance["corpse_selector"],false);
    }
    if(appearance.has("artifact_mood") && (itemType!=24 || appearance["artifact_mood"].get_type()!=Variant::BOOL))return {};
    if(appearance.has("floodgate_open") && (itemType!=7 || appearance["floodgate_open"].get_type()!=Variant::BOOL))return {};
    std::string craftGemColor;
    if(appearance.has("craft_gem_color")) {
        if(itemType<36 || itemType>43 || itemType==39 || appearance["craft_gem_color"].get_type()!=Variant::STRING)return {};
        const String color=appearance["craft_gem_color"];if(color.utf8().length()>128)return {};
        craftGemColor=color.utf8().get_data();
    }
    int8_t bucketLiquid=-1;std::string bucketLiquidColor;
    if(appearance.has("bucket_liquid")) {
        if(itemType!=18 || appearance["bucket_liquid"].get_type()!=Variant::DICTIONARY)return {};
        const Dictionary liquid=appearance["bucket_liquid"];
        if(liquid.size()!=2 || !liquid.has("present") || liquid["present"].get_type()!=Variant::BOOL ||
           !liquid.has("color_token") || liquid["color_token"].get_type()!=Variant::STRING)return {};
        bucketLiquid=bool(liquid["present"])?1:0;const String color=liquid["color_token"];
        if(color.utf8().length()>128 || (!bucketLiquid && !color.is_empty()))return {};
        bucketLiquidColor=color.utf8().get_data();
    }
    std::optional<df3d::assets::DoorItemFacts> door;
    if(appearance.has("door")) {
        if(itemType!=6 || itemId<0 || appearance["door"].get_type()!=Variant::DICTIONARY)return {};
        const Dictionary value=appearance["door"];
        if(value.size()!=3 || !value.has("open") || value["open"].get_type()!=Variant::BOOL ||
           !value.has("forbidden") || value["forbidden"].get_type()!=Variant::BOOL ||
           !value.has("wear") || value["wear"].get_type()!=Variant::INT)return {};
        const int64_t wear=value["wear"];if(wear<0 || wear>3)return {};
        door=df3d::assets::DoorItemFacts{bool(value["open"]),bool(value["forbidden"]),uint8_t(wear)};
    }
    std::optional<wm::ContainerContentsFacts> contents;
    if(appearance.has("contents")) {
        if((itemType!=17 && itemType!=31 && itemType!=32) || appearance["contents"].get_type()!=Variant::DICTIONARY)return {};
        const Dictionary value=appearance["contents"];
        if(value.size()!=(itemType==17?4:2) || !value.has("container") || value["container"].get_type()!=Variant::BOOL ||
           !value.has("entries") || value["entries"].get_type()!=Variant::ARRAY)return {};
        const Array entries=value["entries"];auto& facts=contents.emplace();facts.container=bool(value["container"]);
        if(itemType==17) {
            if(!value.has("material_inorganic") || value["material_inorganic"].get_type()!=Variant::BOOL || !value.has("solid_color") || value["solid_color"].get_type()!=Variant::STRING)return {};
            const String color=value["solid_color"];if(color.utf8().length()>128)return {};
            facts.materialInorganic=bool(value["material_inorganic"])?1:0;facts.solidColor=color.utf8().get_data();
        }
        if(entries.size()>(itemType==32?4096:1) || (itemType!=31 && !facts.container && !entries.is_empty()))return {};
        for(int64_t i=0;i<entries.size();++i) {
            if(entries[i].get_type()!=Variant::DICTIONARY)return {};
            const Dictionary row=entries[i];if(row.size()!=(itemType==17?12:10))return {};
            for(const auto* key:{"item_type","effective_armor_level"})
                if(!row.has(key) || row[key].get_type()!=Variant::INT)return {};
            const int64_t type=row["item_type"],armor=row["effective_armor_level"];
            if(type < -1 || type>92 || armor < -128 || armor>127)return {};
            for(const auto* key:{"metal","coal","contains_powder","rolls_sheets","protects_folded_sheets","contains_writing"})
                if(!row.has(key) || row[key].get_type()!=Variant::BOOL)return {};
            for(const auto* key:{"material_token","color_token"})
                if(!row.has(key) || row[key].get_type()!=Variant::STRING)return {};
            const String material=row["material_token"],color=row["color_token"];
            if(material.utf8().length()>256 || color.utf8().length()>128)return {};
            wm::ContainerContentFacts entry;entry.kind=wm::ItemKind(type+1);entry.effectiveArmorLevel=int8_t(armor);
            entry.materialToken=material.utf8().get_data();entry.colorToken=color.utf8().get_data();
            entry.metal=bool(row["metal"]);entry.coal=bool(row["coal"]);entry.containsPowder=bool(row["contains_powder"]);
            entry.rollsSheets=bool(row["rolls_sheets"]);entry.protectsFoldedSheets=bool(row["protects_folded_sheets"]);entry.containsWriting=bool(row["contains_writing"]);
            if(itemType==17) {
                for(const auto* key:{"liquid","subterranean_plant"})if(!row.has(key) || row[key].get_type()!=Variant::BOOL)return {};
                entry.liquid=bool(row["liquid"]);entry.subterraneanPlant=bool(row["subterranean_plant"]);
            }
            facts.entries.push_back(std::move(entry));
        }
    }
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
    if(appearance.has("restraint")) {
        if(itemType!=10 || appearance["restraint"].get_type()!=Variant::DICTIONARY)return {};
        const Dictionary restraint=appearance["restraint"];if(restraint.size()!=2)return {};
        return animal_restraint_icon(restraint);
    }
    if(appearance.has("cage")) {
        if(itemType!=16 || appearance["cage"].get_type()!=Variant::DICTIONARY)return {};
        const Dictionary cage=appearance["cage"];if(cage.size()!=4+int(cage.has("occupant")))return {};
        for(const char* key:{"material_family","occupant_entity","occupant_id"})if(!cage.has(key) || cage[key].get_type()!=Variant::INT)return {};
        if(!cage.has("solid_color") || cage["solid_color"].get_type()!=Variant::STRING)return {};
        const int64_t family=cage["material_family"],entity=cage["occupant_entity"],id=cage["occupant_id"];
        const auto color=String(cage["solid_color"]).utf8();
        if(family<0 || family>2 || entity<0 || entity>2 || color.length()>128 || (entity==0 ? id!=-1 : id<0 || id>INT32_MAX))return {};
        Ref<Texture2D> occupant;
        if(cage.has("occupant") && (!entity || cage["occupant"].get_type()!=Variant::DICTIONARY))return {};
        if(entity){if(!cage.has("occupant"))return {};occupant=candidate_icon(cage["occupant"]);if(occupant.is_null())return {};}
        const char* families[]={"METAL","WOOD","GLASS"};
        return composite_container_texture(std::string("ITEM_CAGE_")+families[family]+(entity?"_OCCUPIED":""),std::string_view(color.get_data(),color.length()),occupant);
    }
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
    // DF's BOX item selector c7f595 uses the same base/ID overlay as
    // placed chest artwork (cefaa0). Use owned item facts, not terrain presence.
    if(sheet && itemType+1==int(wm::ItemKind::Box)) {
        if(itemId<0)return {};
        df3d::assets::BuildingQuery box;box.kind=wm::BuildingKind::Box;
        box.material=materialToken;box.constructionItemMaterial=materialToken;
        box.constructionItemSolidColor=colorToken;box.constructionItemId=int32_t(itemId);
        const auto resolved=df3d::assets::resolveBuildingTiles(assets_->index,box);
        if(!resolved.found || resolved.tiles.empty())return {};
        std::vector<std::pair<int,Color>> layers;
        for(const auto& tile:resolved.tiles) {
            const int slot=slotFor(tile.sprite.page,resolved.paletteRow,false);
            const auto* texture=slot>=0?spriteResources_.slots.find(slot):nullptr;
            if(!texture || texture->texture.is_null())return {};
            const auto rect=assets_->index.pixels(tile.sprite);
            layers.push_back({slot,Color(float(rect.px)/texture->width,float(rect.py)/texture->height,
                float(rect.pw)/texture->width,float(rect.ph)/texture->height)});
        }
        const int slot=compositeBuildingTile(layers,false,true);
        const auto* texture=slot>=0?spriteResources_.slots.find(slot):nullptr;
        if(texture)return texture->texture;
        return {};
    }
    df3d::assets::ItemQuery query;query.kind=wm::ItemKind(itemType+1);query.material=materialToken;
    query.diagonalAmmo=diagonalAmmo;query.door=door;query.bucketLiquid=bucketLiquid;query.bucketLiquidColor=bucketLiquidColor;query.craftGemColor=craftGemColor;
    if(appearance.has("floodgate_open"))query.floodgateOpen=bool(appearance["floodgate_open"])?1:0;
    if(itemId>=0)query.id=uint32_t(itemId);
    if(contents)query.contents=&*contents;
    query.subtypeRaw=subtypeRaw;query.stack=uint32_t(stack);query.flags=uint8_t(flags);
    // Native weapon selector c7ce83 tests artifact_mood, not artifact.
    // Callers with full item facts can supply it without changing old recordings.
    if(itemType==24 && appearance.has("artifact_mood"))
        query.flags=(query.flags & ~wm::kItemArtifact) | (bool(appearance["artifact_mood"])?wm::kItemArtifact:0);
    query.instrumentFamily=instrumentFamily;query.instrumentPlaced=instrumentPlaced;
    query.slabEngraving=genericGroup && query.kind==wm::ItemKind::Slab ? 0 : slabEngraving;
    const auto resolved=df3d::assets::resolveItem(assets_->index,query);
    if(!resolved.found)return {};
    const bool rawSlab=query.kind==wm::ItemKind::Slab && (genericGroup || (slabEngraving>=1 && slabEngraving<=5));
    // Native hunter list captures142845 use the untinted diagonal sprite for
    // silver, iron and copper alike. Other icon callers retain material tint.
    const bool nativeBarrel=query.kind==wm::ItemKind::Barrel && contents.has_value();
    const int palette=rawSlab || diagonalAmmo ? -1 : (nativeBarrel || colorToken.empty() ? resolved.paletteRow : assets_->index.paletteRow(colorToken));
    if(!colorToken.empty() && palette<0 && !rawSlab && !diagonalAmmo && !nativeBarrel)return {};
    const int slot=slotFor(resolved.sprite.page,palette,false);
    const TextureSlot* texture=slot>=0?spriteResources_.slots.find(slot):nullptr;
    if(!texture || texture->texture.is_null())return {};
    const auto pixels=assets_->index.pixels(resolved.sprite);
    if(!resolved.overlays.empty()) {
        std::vector<std::pair<int,Color>> layers;
        layers.push_back({slot,Color(float(pixels.px)/texture->width,float(pixels.py)/texture->height,
            float(pixels.pw)/texture->width,float(pixels.ph)/texture->height)});
        for(const auto& overlay:resolved.overlays) {
            const int layer=slotFor(overlay.sprite.page,overlay.paletteRow,false);
            const auto* resource=layer>=0?spriteResources_.slots.find(layer):nullptr;
            if(!resource || resource->texture.is_null())return {};
            const auto rect=assets_->index.pixels(overlay.sprite);
            layers.push_back({layer,Color(float(rect.px)/resource->width,float(rect.py)/resource->height,
                float(rect.pw)/resource->width,float(rect.ph)/resource->height)});
        }
        const bool doorLock=query.door && !query.door->open && query.door->forbidden && assets_->index.tile("ITEM_DOOR_FORBIDDEN");
        // BUCKET cf84c9..cf8633 replaces nonzero-alpha liquid pixels, like BIN.
        // Craft cec52e..cec5d4 likewise copies a nontransparent gem pixel,
        // including its alpha, instead of blending it over the base material.
        const bool replaceContents=query.kind==wm::ItemKind::Bin || query.kind==wm::ItemKind::Bag || nativeBarrel || (query.kind==wm::ItemKind::Bucket && query.bucketLiquid>=0) || !query.craftGemColor.empty();
        const int composite=compositeBuildingTile(layers,false,true,false,replaceContents,doorLock);
        const auto* resource=composite>=0?spriteResources_.slots.find(composite):nullptr;
        if(resource)return resource->texture;
        return {};
    }
    Ref<AtlasTexture> icon;icon.instantiate();icon->set_atlas(texture->texture);
    icon->set_region(Rect2(pixels.px,pixels.py,pixels.pw,pixels.ph));return icon;
}

Ref<Texture2D> Df3dWorld::farm_crop_icon(const String& rawId) {
    return plantItemIcon(rawId,wm::ItemKind::Plant);
}

Ref<Texture2D> Df3dWorld::farm_seed_icon(const String& rawId) {
    return plantItemIcon(rawId,wm::ItemKind::Seeds);
}

Ref<Texture2D> Df3dWorld::farm_potash_icon() {
    // Native delivered-fertilizer sheet uses the installed BARS_GRAPHICS POTASH
    // entry with original page colors, as does the farm's contents row.
    return originalItemIcon("POTASH",wm::ItemKind::Bar);
}

Ref<Texture2D> Df3dWorld::plantItemIcon(const String& rawId,wm::ItemKind kind) {
    const auto raw=rawId.utf8();
    if(!assets_ || !raw.length() || raw.length()>128)return {};
    // Native farm renderer199cbc selects PLANT/PICKED via c83890. Contents
    // SEEDS takes c8745b..c87484 through plant seed lookup c5df30. Neither
    // branch applies the material palette used by map items. Owned raw ID only.
    // Reuse installed selection rules, but retain the original page colors.
    return originalItemIcon("PLANT:"+std::string(raw.get_data(),raw.length())+
        (kind==wm::ItemKind::Seeds?":SEED":":STRUCTURAL"),kind);
}

Ref<Texture2D> Df3dWorld::originalItemIcon(std::string_view material,wm::ItemKind kind) {
    if(!assets_)return {};
    df3d::assets::ItemQuery query;query.kind=kind;query.material=material;
    const auto resolved=df3d::assets::resolveItem(assets_->index,query);
    if(!resolved.found)return {};
    const int slot=slotFor(resolved.sprite.page,-1,false);
    const TextureSlot* texture=slot>=0?spriteResources_.slots.find(slot):nullptr;
    if(!texture || texture->texture.is_null())return {};
    const auto pixels=assets_->index.pixels(resolved.sprite);
    Ref<AtlasTexture> icon;icon.instantiate();icon->set_atlas(texture->texture);
    icon->set_region(Rect2(pixels.px,pixels.py,pixels.pw,pixels.ph));return icon;
}

Ref<Texture2D> Df3dWorld::candidate_icon(const Dictionary& recipe) {return candidateIcon(recipe,false);}
Ref<Texture2D> Df3dWorld::item_portrait_icon(const Dictionary& recipe) {return candidateIcon(recipe,true);}
Ref<Texture2D> Df3dWorld::candidateIcon(const Dictionary& recipe,bool portrait) {
    // Only caller-owned original-asset references; no live/map identity lookup.
    wm::SelectionAppearance source;
    for(const char* key:{"tile_pages","palettes","layers"})
        if(!recipe.has(key) || recipe[key].get_type()!=Variant::ARRAY || Array(recipe[key]).size()>256)return {};
    for(const char* key:{"tile_pages","palettes"}) {
        auto& names=std::string_view(key)=="tile_pages"?source.tilePages:source.palettes;
        const Array values=recipe[key];
        for(int i=0;i<values.size();++i) {
            if(values[i].get_type()!=Variant::STRING)return {};
            const auto name=String(values[i]).utf8();
            if(name.length()>(std::string_view(key)=="tile_pages"?256:512))return {};
            names.emplace_back(name.get_data(),name.length());
        }
    }
    const Array layers=recipe["layers"];
    const int low[10]={0,0,0,1,1,0,-32768,-32768,-128,-128};
    const int high[10]={65535,65535,65535,255,255,65535,32767,32767,127,127};
    for(int i=0;i<layers.size();++i) {
        if(layers[i].get_type()!=Variant::ARRAY)return {};
        const Array values=layers[i];if(values.size()!=10)return {};
        int v[10];for(int j=0;j<10;++j) {
            if(values[j].get_type()!=Variant::INT)return {};
            const int64_t n=values[j];if(n<low[j] || n>high[j])return {};v[j]=int(n);
        }
        if(size_t(v[0])>=source.tilePages.size() || (v[5]!=65535 && size_t(v[5])>=source.palettes.size()))return {};
        source.layers.push_back({uint16_t(v[0]),uint16_t(v[1]),uint16_t(v[2]),uint8_t(v[3]),uint8_t(v[4]),uint16_t(v[5]),int16_t(v[6]),int16_t(v[7]),int8_t(v[8]),int8_t(v[9])});
    }
    return portrait?composite_portrait(source):composite_appearance_texture(source,false,true);
}

Ref<Texture2D> Df3dWorld::animal_container_icon(const Dictionary& facts) {
    if(!assets_)return {};
    for(const char* key:{"material_family","occupant_entity","occupant_id"})
        if(!facts.has(key) || facts[key].get_type()!=Variant::INT)return {};
    if(!facts.has("solid_color") || facts["solid_color"].get_type()!=Variant::STRING)return {};
    const int64_t family=facts["material_family"],entity=facts["occupant_entity"],id=facts["occupant_id"];
    if(family<0 || family>2 || entity<0 || entity>2 || (entity==0 ? id!=-1 : id<0 || id>INT32_MAX))return {};
    const auto color=String(facts["solid_color"]).utf8();if(color.length()>128)return {};
    const char* families[]={"METAL","WOOD","GLASS"};
    const std::string token=std::string("ITEM_CAGE_")+families[family]+(entity?"_OCCUPIED":"");
    Ref<Texture2D> occupant;
    if(entity) {
        if(!facts.has("occupant") || facts["occupant"].get_type()!=Variant::DICTIONARY)return {};
        occupant=candidate_icon(facts["occupant"]);if(occupant.is_null())return {};
    } else if(facts.has("occupant"))return {};
    return composite_container_texture(token,std::string_view(color.get_data(),color.length()),occupant);
}
Ref<Texture2D> Df3dWorld::animal_restraint_icon(const Dictionary& facts) {
    if(!facts.has("rope") || facts["rope"].get_type()!=Variant::BOOL || !facts.has("solid_color") || facts["solid_color"].get_type()!=Variant::STRING)return {};
    const auto color=String(facts["solid_color"]).utf8();if(color.length()>128)return {};
    return composite_container_texture(bool(facts["rope"])?"ITEM_CHAIN_ROPE":"ITEM_CHAIN_METAL",std::string_view(color.get_data(),color.length()),{});
}
Ref<Texture2D> Df3dWorld::composite_container_texture(std::string_view token,std::string_view color,const Ref<Texture2D>& body) {
    if(!assets_)return {};
    const auto* sprite=assets_->index.tile(token);if(!sprite)return {};
    const auto* page=assets_->index.page(sprite->page);if(!page)return {};
    const auto* source=rawImage(page->absPath);if(!source)return {};
    const auto rect=assets_->index.pixels(*sprite);
    if(rect.px<0 || rect.py<0 || rect.pw<=0 || rect.ph<=0 || rect.px+rect.pw>source->width || rect.py+rect.ph>source->height)return {};
    auto frame=df3d::assets::RgbaImage::blank(rect.pw,rect.ph);
    for(int y=0;y<rect.ph;++y)for(int x=0;x<rect.pw;++x)frame.set(x,y,source->get(rect.px+x,rect.py+y));
    df3d::assets::RgbaImage occupant;
    if(body.is_valid()) {
        const auto image=body->get_image();if(image.is_null())return {};
        image->convert(Image::FORMAT_RGBA8);
        // Atlas readback can retain mip levels. The CPU compositor accepts
        // exactly the base image, not the appended smaller texture levels.
        image->clear_mipmaps();const auto bytes=image->get_data();
        occupant.width=image->get_width();occupant.height=image->get_height();
        occupant.pixels.assign(bytes.ptr(),bytes.ptr()+bytes.size());
    }
    df3d::assets::PaletteSwap swap;
    if(color.length()) {
        const auto& palette=assets_->index.palette;if(!palette)return {};
        const auto row=assets_->index.paletteRow(color);
        const auto* image=rawImage(palette->absPath);
        if(!image || image->width<18 || row<0 || row>=image->height || palette->defaultRow<0 || palette->defaultRow>=image->height)return {};
        // The cage and restraint renderers compare exactly the first 18 descriptor colors.
        auto ramp=df3d::assets::RgbaImage::blank(18,2);
        for(int x=0;x<18;++x){ramp.set(x,0,image->get(x,palette->defaultRow));ramp.set(x,1,image->get(x,row));}
        if(!df3d::assets::buildPaletteSwap(ramp,0,1,swap))return {};
    }
    const auto result=df3d::assets::compositeContainer(occupant,frame,color.length()?&swap:nullptr);
    if(result.empty())return {};
    PackedByteArray bytes;bytes.resize(int64_t(result.pixels.size()));std::copy(result.pixels.begin(),result.pixels.end(),bytes.ptrw());
    return submission::texture(Image::create_from_data(result.width,result.height,false,Image::FORMAT_RGBA8,bytes),submission::TextureSite::Portrait);
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
Ref<Texture2D> Df3dWorld::composite_appearance_texture(const wm::SelectionAppearance& source, bool framed, bool bodyCell) {
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
    if(bodyCell)portrait=portrait->get_region(Rect2i(-result.originX,-result.originY,result.cellsX*result.tileW,result.cellsY*result.tileH));
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
