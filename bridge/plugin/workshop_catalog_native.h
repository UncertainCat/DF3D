#pragma once
#include "workshop_job_native.h"
#include "df/job_item_filter.h"
#include "df/item_boulderst.h"
#include "df/item_barst.h"
#include "df/inorganic_raw.h"
#include "df/reaction_reagent.h"
#include "df/reaction_category.h"
#include "df/manager_order_template.h"
#include "df/itemdef_armorst.h"
#include "df/itemdef_pantsst.h"
#include "df/itemdef_helmst.h"
#include "df/itemdef_glovesst.h"
#include "df/itemdef_shoesst.h"
#include "df/itemdef_siegeammost.h"
#include "df/itemdef_trapcompst.h"
#include "df/itemdef_toolst.h"
#include <memory>

namespace df3d_production {
struct WorkshopForgeChoice {
    int32_t category=-1,materialIndex=-1;
    std::string caption;
};
// Native8c9a1a..8c9e8b: fixed forge groups and their six material lists.
// Category6 emits clothing tasks directly and is deliberately not a material
// list. Never call the widget constructors or read their selected menu state.
inline std::optional<std::vector<WorkshopForgeChoice>> workshopForgeChoices(df::building* building,int32_t category) {
    static const bool supported=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x8c9a1a,0x9d,UINT64_C(0xe172233b6fcb2648)},
            {0x8c9ab7,0x3d4,UINT64_C(0x49b4576db0ee7f53)},
            {0x8c2ab0,0x138,UINT64_C(0x34921c5eb7f89894)},
            {0x8c28f0,0x4a,UINT64_C(0xf75668c2b3daf60e)},
            {0x145bee0,0x5e,UINT64_C(0x6abc4e374e372eef)},
            {0x14d1920,0x459,UINT64_C(0xf48e28715360ed9a)},
            {0x14add70,0x12f,UINT64_C(0x01f897b15772d540)},
            {0x16bec58,0x16,UINT64_C(0x404b6b6d6f4c1326)},
            {0x162a038,0x5,UINT64_C(0xed3267c1d2c3a7f4)},
            {0x162ca20,0x9,UINT64_C(0x790f28096e087365)},
            {0x16bed60,0xf,UINT64_C(0xb0e47e9774f8f164)},
            {0x162a420,0xf,UINT64_C(0x1df398a6be7f6052)},
            {0x16bed70,0xd,UINT64_C(0x945d9d2ec61420ed)},
            {0x16bed38,0xe,UINT64_C(0x5b491156908a18d8)},
            {0x1615870,0xd,UINT64_C(0xcd56f05c0ea1035c)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported || !building || !df::global::world || category < -1 || category > 5 ||
       int(building->getType())!=13 || (building->getSubtype()!=5 && building->getSubtype()!=6))return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const std::string suffix(reinterpret_cast<const char*>(base+0x1615870),13);
    std::vector<WorkshopForgeChoice> result;
    if(category==-1) {
        constexpr size_t names[]={0x16bec58,0x162a038,0x162ca20,0x16bed60,0x162a420,0x16bed70,0x16bed38};
        constexpr size_t lengths[]={22,5,9,15,15,13,14};
        for(int32_t i=0;i<7;++i)result.push_back({i,-1,std::string(reinterpret_cast<const char*>(base+names[i]),lengths[i])+suffix});
        return result;
    }
    using Flag=bool (*)(df::world*,int32_t,int16_t,int32_t);
    using Name=void (*)(void*,std::string*,int16_t,int32_t,int32_t,bool,int16_t);
    const auto flag=reinterpret_cast<Flag>(base+0x145bee0);
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    const auto& raws=df::global::world->raws.inorganics.all;
    for(size_t i=0;i<raws.size();++i) {
        if(!raws[i] || !flag(df::global::world,47,0,int32_t(i)))continue;
        bool allowed=false;
        if(category==0) {
            for(int32_t value:{51,52,54,55})if(flag(df::global::world,value,0,int32_t(i))){allowed=true;break;}
        } else allowed=flag(df::global::world,category==1?56:(category==2 || category==5?11:51),0,int32_t(i));
        if(!allowed)continue;
        std::string caption;
        reinterpret_cast<Name>(base+0x14d1920)(df::global::world,&caption,0,int32_t(i),0,false,0);
        result.push_back({category,int32_t(i),caption+suffix});
    }
    return result;
}
// Native8c9e8b..8ca48c: metal clothing bypasses material buttons. Use civ
// resources and raw clothing properties; the global task builder is not called.
inline std::optional<std::vector<df::manager_order_template>> workshopForgeClothing(df::building* building) {
    if(!workshopForgeChoices(building,-1) || !df::global::plotinfo)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x601;++i){hash^=base[0x8c9e8b+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xad813e31d84575d6);
    }();
    if(!pinned)return std::nullopt;
    static_assert(offsetof(df::historical_entity,resources)+offsetof(df::historical_entity::T_resources,armor_type)==0x178);
    static_assert(offsetof(df::historical_entity,resources)+offsetof(df::historical_entity::T_resources,pants_type)==0x1f0);
    static_assert(offsetof(df::itemdef_armorst,props)==0x118);
    static_assert(offsetof(df::itemdef_pantsst,props)==0x128);
    static_assert(offsetof(df::itemdef_helmst,props)==0xe8);
    static_assert(offsetof(df::itemdef_glovesst,props)==0xe8);
    static_assert(offsetof(df::itemdef_shoesst,props)==0xe8);
    auto* civ=df::historical_entity::find(df::global::plotinfo->civ_id);
    using Flag=bool (*)(df::world*,int32_t,int16_t,int32_t);
    const auto flag=reinterpret_cast<Flag>(base+0x145bee0);
    std::vector<df::manager_order_template> result;
    const auto add=[&](int32_t type,int16_t subtype,int32_t material)->bool {
        df::job job;job.job_type=df::job_type(type);job.item_subtype=subtype;job.mat_type=0;job.mat_index=material;
        const auto caption=workshopJobCaption(job);if(!caption)return false;
        df::manager_order_template row;
        row.job_type=job.job_type;row.item_type=job.item_type;row.item_subtype=subtype;
        row.mat_type=0;row.mat_index=material;row.specflag=job.specflag;row.specdata=job.specdata;
        row.material_category=job.material_category;row.art_specifier=job.art_spec.type;
        row.art_specifier_id1=job.art_spec.id;row.art_specifier_id2=job.art_spec.subid;row.name=*caption;
        result.push_back(std::move(row));return true;
    };
    const auto addClothes=[&](const auto& ids,const auto& raws,int32_t type,int32_t material)->bool {
        for(const int16_t id:ids) {
            if(id<0 || size_t(id)>=raws.size() || !raws[id])return false;
            const auto& flags=raws[id]->props.flags;
            if((flags.is_set(df::armor_general_flags::SOFT) || flags.is_set(df::armor_general_flags::HARD)) &&
               !flags.is_set(df::armor_general_flags::METAL) && !add(type,id,material))return false;
        }
        return true;
    };
    const auto& materials=df::global::world->raws.inorganics.all;
    for(size_t i=0;i<materials.size();++i) {
        if(!materials[i] || !flag(df::global::world,47,0,int32_t(i)) || !flag(df::global::world,10,0,int32_t(i)))continue;
        if(civ) {
            const auto& r=civ->resources;
            if(!addClothes(r.armor_type,df::itemdef_armorst::get_vector(),100,int32_t(i)) ||
               !addClothes(r.pants_type,df::itemdef_pantsst::get_vector(),102,int32_t(i)) ||
               !addClothes(r.helm_type,df::itemdef_helmst::get_vector(),101,int32_t(i)) ||
               !addClothes(r.gloves_type,df::itemdef_glovesst::get_vector(),116,int32_t(i)) ||
               !addClothes(r.shoes_type,df::itemdef_shoesst::get_vector(),117,int32_t(i)))return std::nullopt;
        }
        if(!add(131,-1,int32_t(i)) || !add(132,-1,int32_t(i)))return std::nullopt;
    }
    for(size_t i=1;i<result.size();++i) {
        auto row=std::move(result[i]);size_t at=i;
        while(at>0) {
            const auto less=workshopCaptionLess(row.name,result[at-1].name);if(!less)return std::nullopt;
            if(!*less)break;
            result[at]=std::move(result[at-1]);--at;
        }
        result[at]=std::move(row);
    }
    return result;
}
// Native8ca541..8cb3b6 supplies the final tasks after a forge material choice.
// Membership is composed from that inline branch, not the Work orders shop
// classifier (which assigns mechanisms elsewhere and loses siege subtypes).
inline std::optional<std::vector<df::manager_order_template>> workshopForgeTasks(df::building* building,int32_t category,int32_t material) {
    const auto choices=workshopForgeChoices(building,category);
    if(!choices || category<0 || category>5 || !df::global::plotinfo ||
       std::none_of(choices->begin(),choices->end(),[&](const auto& row){return row.materialIndex==material;}))return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        const auto hash=[&](size_t at,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[at+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0x8ca541,0xe75)==UINT64_C(0xb8a07ac314c3630f) &&
            hash(0x8c03a0,0x17ad)==UINT64_C(0xedd2766250590831);
    }();
    if(!pinned)return std::nullopt;
    static_assert(offsetof(df::historical_entity,resources)+offsetof(df::historical_entity::T_resources,siegeammo_type)==0x268);
    static_assert(offsetof(df::historical_entity,resources)+offsetof(df::historical_entity::T_resources,tool_type)==0x280);
    static_assert(offsetof(df::itemdef_siegeammost,ammo_class)==0xa8);
    static_assert(offsetof(df::itemdef_trapcompst,flags)==0xd8);
    static_assert(offsetof(df::itemdef_toolst,flags)==0xa8);
    using Allowed=bool (*)(int16_t,int16_t,int16_t,int32_t);
    using Flag=bool (*)(df::world*,int32_t,int16_t,int32_t);
    const auto allowed=reinterpret_cast<Allowed>(base+0x8c03a0);
    const auto flag=reinterpret_cast<Flag>(base+0x145bee0);
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    auto* civ=df::historical_entity::find(df::global::plotinfo->civ_id);
    std::vector<df::manager_order_template> result;
    const auto add=[&](int32_t type,int16_t subtype=-1)->bool {
        df::job job;job.job_type=df::job_type(type);job.item_subtype=subtype;job.mat_type=0;job.mat_index=material;
        const auto caption=workshopJobCaption(job);if(!caption)return false;
        df::manager_order_template row;
        row.job_type=job.job_type;row.item_type=job.item_type;row.item_subtype=subtype;
        row.mat_type=0;row.mat_index=material;row.specflag=job.specflag;row.specdata=job.specdata;
        row.material_category=job.material_category;row.art_specifier=job.art_spec.type;
        row.art_specifier_id1=job.art_spec.id;row.art_specifier_id2=job.art_spec.subid;row.name=*caption;
        result.push_back(std::move(row));return true;
    };
    const auto armor=[&](const auto& ids,const auto& raws,int32_t job)->bool {
        for(const int16_t id:ids) {
            if(id<0 || size_t(id)>=raws.size() || !raws[id])return false;
            if(raws[id]->props.flags.is_set(df::armor_general_flags::METAL) && !add(job,id))return false;
        }
        return true;
    };
    if(category==0 && civ) {
        const auto& r=civ->resources;
        for(auto id:r.weapon_type)if(allowed(24,id,0,material) && !add(96,id))return std::nullopt;
        for(auto id:r.digger_type)if(std::find(r.weapon_type.begin(),r.weapon_type.end(),id)==r.weapon_type.end() &&
            allowed(24,id,0,material) && !add(96,id))return std::nullopt;
        for(auto id:r.ammo_type)if(allowed(39,id,0,material) && !add(129,id))return std::nullopt;
    } else if(category==1 && civ) {
        const auto& r=civ->resources;
        if(!armor(r.armor_type,df::itemdef_armorst::get_vector(),100) ||
           !armor(r.pants_type,df::itemdef_pantsst::get_vector(),102) ||
           !armor(r.helm_type,df::itemdef_helmst::get_vector(),101) ||
           !armor(r.gloves_type,df::itemdef_glovesst::get_vector(),116) ||
           !armor(r.shoes_type,df::itemdef_shoesst::get_vector(),117))return std::nullopt;
        for(auto id:r.shield_type)if(!add(118,id))return std::nullopt;
    } else if(category==2) {
        for(int32_t job:{119,120,124,126,125,76,80,67,68,198,199,79,78,73,70,71,72,77,75,193,203,204})
            if(!add(job))return std::nullopt;
    } else if(category==3) {
        if(civ)for(auto id:civ->resources.siegeammo_type) {
            const auto& raws=df::itemdef_siegeammost::get_vector();
            if(id<0 || size_t(id)>=raws.size() || !raws[id])return std::nullopt;
            if(raws[id]->ammo_class=="BALLISTA" && !add(133,id))return std::nullopt;
        }
        if(flag(df::global::world,58,0,material))for(int32_t job:{99,98,245})if(!add(job))return std::nullopt;
    } else if(category==4) {
        if(civ)for(auto id:civ->resources.trapcomp_type) {
            const auto& raws=df::itemdef_trapcompst::get_vector();
            if(id<0 || size_t(id)>=raws.size() || !raws[id])return std::nullopt;
            if(raws[id]->flags.is_set(df::trapcomp_flags::METAL) && !add(140,id))return std::nullopt;
        }
        if(flag(df::global::world,11,0,material) && !add(139))return std::nullopt;
    } else if(category==5) {
        if(allowed(45,-1,0,material) && !add(97))return std::nullopt;
        for(int32_t job:{82,122,123})if(!add(job))return std::nullopt;
        if(civ)for(auto id:civ->resources.tool_type) {
            const auto& raws=df::itemdef_toolst::get_vector();
            if(id<0 || size_t(id)>=raws.size() || !raws[id])return std::nullopt;
            if(!raws[id]->flags.is_set(df::tool_flags::NO_DEFAULT_JOB) && allowed(86,id,0,material) && !add(216,id))return std::nullopt;
        }
        for(int32_t job:{121,83,103,231,236,235,233,230,234,237,232})if(!add(job))return std::nullopt;
    }
    for(size_t i=1;i<result.size();++i) {
        auto row=std::move(result[i]);size_t at=i;
        while(at>0) {
            const auto less=workshopCaptionLess(row.name,result[at-1].name);if(!less)return std::nullopt;
            if(!*less)break;
            result[at]=std::move(result[at-1]);--at;
        }
        result[at]=std::move(row);
    }
    return result;
}
struct WorkshopReactionCategory {
    std::string code,caption;
    int32_t hotkey=-1;
};
// Native8c4380..8c47a4 walks permitted reaction ancestry before constructing
// category buttons. Compose that inline branch using owned visited strings;
// only simulation raws and the native permission leaf are consulted.
inline std::optional<std::vector<WorkshopReactionCategory>> workshopReactionCategories(
    df::building* building,const std::string& parent) {
    static const bool supported=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x8c4380,0x424,UINT64_C(0xab15df898db74b83)},
            {0x8c29d0,0xd8,UINT64_C(0x6e575de3e979203e)},
            {0x1615870,0xd,UINT64_C(0xcd56f05c0ea1035c)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported || !building || !df::global::world || !df::global::plotinfo ||
       !df::global::plotinfo->main.fortress_entity)return std::nullopt;
    const auto& raws=df::global::world->raws.reactions;
    const auto find=[&](const std::string& code)->const df::reaction_category* {
        for(const auto* category:raws.reaction_categories)
            if(category && category->id==code)return category;
        return nullptr;
    };
    std::vector<std::string> visited;
    std::vector<WorkshopReactionCategory> result;
    for(size_t index=0;index<raws.reactions.size();++index) {
        const auto* reaction=raws.reactions[index];
        if(!reaction || reaction->category.empty())continue;
        const auto allowed=workshopReactionAllowed(int32_t(index));
        if(!allowed)return std::nullopt;
        if(!*allowed)continue;
        const auto& restrictions=reaction->building;
        if(restrictions.type.size()!=restrictions.subtype.size() ||
           restrictions.type.size()!=restrictions.custom.size())return std::nullopt;
        bool matches=false;
        for(size_t n=restrictions.type.size();n>0;--n) {
            const auto i=n-1;
            if(restrictions.type[i]==building->getType() && restrictions.subtype[i]==building->getSubtype() &&
               restrictions.custom[i]==building->getCustomType()){matches=true;break;}
        }
        if(!matches || std::find(visited.begin(),visited.end(),reaction->category)!=visited.end())continue;
        visited.push_back(reaction->category);
        const auto* category=find(reaction->category);
        if(!category)return std::nullopt;
        while(category->parent!=parent) {
            category=find(category->parent);
            if(!category)break;
            if(std::find(visited.begin(),visited.end(),category->id)!=visited.end()){category=nullptr;break;}
            visited.push_back(category->id);
        }
        if(!category)continue;
        // Native8c29d0 uses the first matching nonempty category name, else ID.
        std::string caption=category->id;
        for(const auto* raw:raws.reaction_categories)
            if(raw && raw->id==category->id && !raw->name.empty()){caption=raw->name;break;}
        const auto* base=reinterpret_cast<const char*>(GetModuleHandleW(nullptr));
        caption.append(base+0x1615870,13);
        result.push_back({category->id,std::move(caption),int32_t(category->key)});
    }
    return result;
}
// Resolve an opaque key through the permitted category tree for this building.
// A raw token alone is insufficient: its ancestors must be reachable too.
inline std::optional<std::string> workshopTaskCategoryToken(df::building* building,const std::string& key) {
    if(key.empty())return std::string{};
    constexpr std::string_view prefix="reaction:";
    if(key.size()>256 || !key.starts_with(prefix) || key.size()==prefix.size() || !df::global::world)return std::nullopt;
    const auto token=key.substr(prefix.size());
    std::vector<std::string> path;std::string current=token;
    const auto& categories=df::global::world->raws.reactions.reaction_categories;
    while(!current.empty()) {
        if(std::find(path.begin(),path.end(),current)!=path.end())return std::nullopt;
        const auto found=std::find_if(categories.begin(),categories.end(),[&](const auto* row){return row && row->id==current;});
        if(found==categories.end())return std::nullopt;
        path.push_back(current);current=(*found)->parent;
    }
    for(auto at=path.rbegin();at!=path.rend();++at) {
        const auto children=workshopReactionCategories(building,current);if(!children)return std::nullopt;
        if(std::none_of(children->begin(),children->end(),[&](const auto& row){return row.code==*at;}))return std::nullopt;
        current=*at;
    }
    return token;
}
inline bool workshopInventoryReady() {
    static const bool ready=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1fb050,0x123,UINT64_C(0x3ea393db12f2c677)},
            {0xed7490,0x3f3,UINT64_C(0xfaa78e37515c7a6b)},
            {0xa29630,0x177b,UINT64_C(0xd483c9c32e4f7fc5)},
            {0xa26990,0x12c3,UINT64_C(0x33e9d093964f527a)},
            {0xa27c60,0x19c4,UINT64_C(0x2810b30401cba53e)},
            {0xc93380,0x98,UINT64_C(0x9455ba082ba604c4)},
            {0x14d3600,0x109,UINT64_C(0xb164e558947da80d)},
            {0x14d34c0,0x13f,UINT64_C(0xf55df28a48d0f031)},
            {0x16beb70,0xa,UINT64_C(0x5e405a170a87e776)},
            {0x16beb80,0xf,UINT64_C(0x3680f8580bd330c1)},
            {0x15fd690,0x1,UINT64_C(0xaf64104c860244e8)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
struct WorkshopReactionRow {
    int32_t rawIndex=-1;
    std::string code,caption,objection;
    bool available=false;
};
// Native8c3fe0 composes reaction availability inline. Its item-search routines
// and reagent methods operate on independent filter/collector/precalc storage.
// The world supplies read-only item/raw records, never native menu vectors.
inline std::optional<std::vector<WorkshopReactionRow>> workshopReactionRows(
    df::building* building,const std::string& category) {
    if(!building || !df::global::world || !workshopInventoryReady())return std::nullopt;
    static_assert(sizeof(df::job_item_filter)==0x110);
    static_assert(offsetof(df::job_item_filter,item_vector)==0x10);
    static_assert(offsetof(df::job_item_filter,building)==0xd0);
    static_assert(offsetof(df::inorganic_raw,metal_ore.mat_index)==0x68);
    static_assert(offsetof(df::inorganic_raw,material.reaction_class)==0x650);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    df3d_creature::InventoryRandomRestore random(base);
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    using Init=void (*)(df::job_item_filter*);
    using Collect=void (*)(df::job_item_filter*,std::vector<df::item*>*);
    using Find=df::item* (*)(df::job_item_filter*);
    const auto& inorganics=df::global::world->raws.inorganics.all;
    std::vector<int32_t> counts(inorganics.size()),ores(inorganics.size()),classCounts;
    std::vector<std::unique_ptr<std::string>> classStorage;
    std::vector<std::string*> classes;
    std::vector<df::item*> boulders(df::global::world->items.other.BOULDER.begin(),df::global::world->items.other.BOULDER.end()),found;
    df::job_item_filter filter;
    reinterpret_cast<Init>(base+0x1fb050)(&filter);
    filter.item_vector=&boulders;
    reinterpret_cast<Collect>(base+0xa29630)(&filter,&found);
    for(auto it=found.rbegin();it!=found.rend();++it) {
        auto* item=*it;if(!item || item->getMaterial()!=0)continue;
        const auto index=item->getMaterialIndex();
        if(index<0 || size_t(index)>=counts.size() || counts[index]>=100)continue;
        ++counts[index];const auto* raw=inorganics[index];if(!raw)continue;
        for(auto ore:raw->metal_ore.mat_index) {
            if(ore<0 || size_t(ore)>=ores.size())return std::nullopt;
            ++ores[ore];
        }
        for(auto itClass=raw->material.reaction_class.rbegin();itClass!=raw->material.reaction_class.rend();++itClass) {
            if(!*itClass)return std::nullopt;
            size_t i=0;while(i<classes.size() && *classes[i]!=**itClass)++i;
            if(i==classes.size()) {
                classStorage.push_back(std::make_unique<std::string>(**itClass));
                classes.push_back(classStorage.back().get());classCounts.push_back(0);
            }
            ++classCounts[i];
        }
    }
    bool fuel=building->needsMagma();
    if(!fuel) {
        std::vector<df::item*> bars(df::global::world->items.other.BAR.begin(),df::global::world->items.other.BAR.end());
        df::job_item_filter fuelFilter;reinterpret_cast<Init>(base+0x1fb050)(&fuelFilter);
        fuelFilter.item_type=df::item_type(0);fuelFilter.mat_type=7;fuelFilter.item_vector=&bars;
        fuelFilter.building=building;fuelFilter.pos=df::coord(building->x1,building->y1,building->z);
        fuel=reinterpret_cast<Find>(base+0xa26990)(&fuelFilter)!=nullptr;
    }
    std::vector<WorkshopReactionRow> result;
    const auto& reactions=df::global::world->raws.reactions.reactions;
    for(size_t i=0;i<reactions.size();++i) {
        auto* reaction=reactions[i];if(!reaction || reaction->category!=category)continue;
        const auto allowed=workshopReactionAllowed(int32_t(i));if(!allowed)return std::nullopt;
        if(!*allowed)continue;
        bool matches=false;
        for(size_t n=reaction->building.type.size();n>0;--n) {
            const auto at=n-1;
            if(at>=reaction->building.subtype.size() || at>=reaction->building.custom.size())return std::nullopt;
            if(reaction->building.type[at]==building->getType() && reaction->building.subtype[at]==building->getSubtype() &&
               reaction->building.custom[at]==building->getCustomType()){matches=true;break;}
        }
        if(!matches)continue;
        df::job job;job.job_type=df::job_type::CustomReaction;job.reaction_name=reaction->code;
        const auto caption=workshopJobCaption(job);if(!caption)return std::nullopt;
        WorkshopReactionRow row{int32_t(i),reaction->code,*caption,{},true};
        if(reaction->flags.is_set(df::reaction_flags::FUEL) && !fuel) {
            row.available=false;row.objection.assign(reinterpret_cast<const char*>(base+0x16beb80),15);
        } else for(auto it=reaction->reagents.rbegin();it!=reaction->reagents.rend();++it) {
            auto* reagent=*it;if(!reagent)return std::nullopt;
            if(reagent->flags.bits.IN_CONTAINER)continue;
            if(reagent->have_enough_from_precalc_info(building,&counts,&ores,&classes,&classCounts,reaction->index))continue;
            std::string description;reagent->getDescription(&description,reaction->index);
            row.available=false;row.objection.assign(reinterpret_cast<const char*>(base+0x16beb70),10);
            row.objection+=description;row.objection.append(reinterpret_cast<const char*>(base+0x15fd690),1);break;
        }
        result.push_back(std::move(row));
    }
    return result;
}
}
