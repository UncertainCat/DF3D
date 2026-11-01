#pragma once
#include "creature_thoughts_native.h"
#include "df/unit_soul.h"
#include "df/unit_preference.h"
#include "df/plant_raw.h"
#include "df/creature_raw.h"
#include "df/poetic_form.h"
#include "df/musical_form.h"
#include "df/dance_form.h"
namespace df3d_creature {
// Preferences composition is inline in4800b2..48149c. Its reusable semantic
// formatters receive owned output strings and scalar IDs, never sheet state.
inline std::optional<std::string> personalityPreferences(const df::unit* source) {
    if(!source || !df::global::world || !thoughtDescriptionReady())return std::nullopt;
    if(!source->status.current_soul || source->status.current_soul->preferences.empty())return std::string{};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x4800b2,0x13ea,UINT64_C(0xf8c43360dd6e77a9)},
            {0x481e8c,0x72,UINT64_C(0x4316334befb6c2d9)},
            {0xa82c10,0x56ec,UINT64_C(0x66347214dfd39a0b)},
            {0x14d1920,0x459,UINT64_C(0xf48e28715360ed9a)},
            {0x145bee0,0x5e,UINT64_C(0x6abc4e374e372eef)},
            {0x14add70,0x12f,UINT64_C(0x01f897b15772d540)},
            {0x144d90,0xba,UINT64_C(0x97aed5d23117e68f)},
            {0xe35d60,0xe9,UINT64_C(0x5450dbfd5d937129)},
            {0xe35c70,0xed,UINT64_C(0x2ef277a490ac3178)},
            {0xaa3bd0,0x1c3,UINT64_C(0x0f9cd818efc6bad8)},
            {0x420fc0,0x5f,UINT64_C(0xa70d69145292d4ff)},
            {0x1437f0,0x6b,UINT64_C(0x73b20c2855ada814)},
            {0x13e5a90,0x8c,UINT64_C(0x18f14fd96d2fb5d7)},
            {0xc3a4f0,0x98,UINT64_C(0x90965a9fe84783f6)},
            {0xb530b0,0xac,UINT64_C(0x7c6f66602bdab157)},
            {0x1602430,0xa,UINT64_C(0xd4bd098ef4c1f7c2)},
            {0x163fff8,0x8,UINT64_C(0x83e86596b3f138a5)},
            {0x163fff0,0x6,UINT64_C(0xfcfda3f4ddd2429a)},
            {0x163ffe8,0x8,UINT64_C(0xb2ebf84455119fe2)},
            {0x1640050,0xc,UINT64_C(0x82419a25a0271bf2)},
            {0x1640040,0xb,UINT64_C(0x6797299fb6d5a9f3)},
            {0x1640030,0xe,UINT64_C(0x91f40a8a41c4b8ea)},
            {0x1640020,0xe,UINT64_C(0x81b30088eee9ee94)},
            {0x1640600,0xe,UINT64_C(0x387c241cce6a22a2)},
            {0x16405f0,0x10,UINT64_C(0x987748d7550a6c8c)},
            {0x16405d8,0x15,UINT64_C(0x7ce5d759684e703d)},
            {0x16405c8,0xd,UINT64_C(0x3a806261c1e39058)},
            {0x1640640,0xd,UINT64_C(0x0daca2590e2d25ab)},
            {0x1640630,0xf,UINT64_C(0xc0ca0ca970ec2fcb)},
            {0x1640620,0xe,UINT64_C(0x9adc958d69e2b295)},
            {0x1640610,0xf,UINT64_C(0xb3347a00d66241b9)},
            {0x1640570,0xe,UINT64_C(0x85d85896268377bd)},
            {0x1640560,0xf,UINT64_C(0x991aead70a054dd5)},
            {0x1640550,0xf,UINT64_C(0x8b5f3ec87076ef26)},
            {0x1640540,0xf,UINT64_C(0x52e142599baa8192)},
            {0x16405b8,0xd,UINT64_C(0x2e8d0ad090af64d4)},
            {0x16405a0,0x15,UINT64_C(0x76b6032461599b85)},
            {0x15e90d8,0x3,UINT64_C(0xe7305e17e30bba23)},
            {0x15e9110,0x6,UINT64_C(0x572c8c2eaca12328)},
            {0x15fd968,0x4,UINT64_C(0xf813dda63efcb2bb)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();if(!ready)return std::nullopt;
    std::vector<df::unit_preference> preferences;
    for(const auto* p:source->status.current_soul->preferences){if(!p)return std::nullopt;preferences.push_back(*p);}
    struct OwnedUnit final:df::unit {OwnedUnit():df::unit(){}} unit;
    unit.name=source->name;unit.hist_figure_id=source->hist_figure_id;unit.enemy.histfig_vector_idx=-1;
    InventoryRandomRestore random(base); // Preference reasons reseed the split RNG.
    KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    const auto literal=[&](size_t rva){return reinterpret_cast<const char*>(base+rva);};
    const auto pronoun=[&](bool capitalized){std::string value;using Fn=void(*)(int8_t,std::string*,bool);reinterpret_cast<Fn>(base+0xaa4730)(source->sex,&value,capitalized);return value;};
    using Item=void(*)(std::string*,int16_t,int16_t,int16_t,int32_t,int32_t,int32_t,bool,void*,int32_t,int32_t,bool,int32_t,int32_t);
    const auto item=[&](std::string& out,int type,int subtype,int mat,int index,int quantity){reinterpret_cast<Item>(base+0xa82c10)(&out,int16_t(type),int16_t(subtype),int16_t(mat),index,quantity,0,false,nullptr,-1,-1,true,0,0);};
    const auto creatureName=[&](int id,int form){const auto& raws=df::global::world->raws.creatures.all;return id>=0 && size_t(id)<raws.size()?raws[id]->name[form]:std::string{};};
    std::string text=literal(0x1602430);
    for(int group=0;group<3;++group){
        const auto belongs=[&](const df::unit_preference& p){return p.flags.bits.visible && (group==0?(int(p.type)!=2 && int(p.type)!=3):int(p.type)==group+1);};
        int remaining=0;for(const auto& p:preferences)if(belongs(p))++remaining;
        if(!remaining)continue;
        if(group==0){
            using Name= df::language_name*(*)(df::unit*);
            auto* name=reinterpret_cast<Name>(base+0x13e5a90)(&unit);
            std::string caption;
            if(name && name->has_name)reinterpret_cast<void(*)(df::language_name*,std::string*)>(base+0xa94030)(name,&caption);
            text+=caption;text+=literal(0x163fff8);
        }else if(group==1){text+=literal(0x16405f0);text+=pronoun(false);text+=literal(0x16405d8);}
        else {text+=pronoun(true);text+=literal(0x16405a0);}
        for(const auto& p:preferences){
            if(!belongs(p))continue;
            std::string part;
            if(group==2)part=creatureName(int16_t(p.creature_id),1);
            else if(group==1){
                size_t fallback=0x16405b8;
                switch(p.item_type){
                    case 48:part=creatureName(int16_t(p.matindex),0);fallback=0x16405c8;break;
                    case 49:part=creatureName(int16_t(p.mattype),0);fallback=0x1640640;break;
                    case 54:{const auto& plants=df::global::world->raws.plants.all;if(p.matindex>=0 && size_t(p.matindex)<plants.size())part=plants[p.matindex]->name_plural;fallback=0x1640630;break;}
                    case 69:case 73:case 53:case 70:case 71:
                        item(part,p.item_type,-1,p.mattype,p.matindex,1);
                        fallback=p.item_type==69?0x1640620:p.item_type==73?0x1640610:p.item_type==53?0x1640570:p.item_type==70?0x1640550:0x1640540;break;
                    case 56:item(part,56,p.item_subtype,p.mattype,p.matindex,-1);fallback=0x1640560;break;
                    default:item(part,p.item_type,p.item_subtype,p.mattype,p.matindex,1);break;
                }
                if(part.empty())part=literal(fallback);
            }else switch(int(p.type)){
                case 0:{
                    using Material=void(*)(void*,std::string*,int16_t,int32_t,int32_t,bool,int16_t);
                    reinterpret_cast<Material>(base+0x14d1920)(df::global::world,&part,int16_t(p.mattype),p.matindex,0,false,int16_t(p.mat_state));
                    if(int(p.mat_state)==0 && p.mattype>=419 && p.mattype<=618){
                        using Flag=bool(*)(void*,int32_t,int16_t,int32_t);
                        auto flag=reinterpret_cast<Flag>(base+0x145bee0);
                        if(flag(df::global::world,23,int16_t(p.mattype),p.matindex))part+=literal(0x163fff0);
                        else if(flag(df::global::world,24,int16_t(p.mattype),p.matindex))part+=literal(0x163ffe8);
                    }break;
                }
                case 4:item(part,p.item_type,p.item_subtype,-1,-1,-1);break;
                case 1:{
                    using Name=void(*)(int16_t,std::string*,bool,int16_t);
                    reinterpret_cast<Name>(base+0xaa3bd0)(int16_t(p.creature_id),&part,true,-1);
                    std::string reason;using Reason=void(*)(void*,std::string*,int16_t,int32_t);
                    reinterpret_cast<Reason>(base+0xe35c70)(&df::global::world->raws.creatures,&reason,int16_t(p.creature_id),p.prefstring_seed);
                    part+=literal(0x1640050);part+=reason;break;
                }
                case 5:case 6:{
                    using Name=void(*)(void*,int32_t,std::string*,bool,bool);
                    reinterpret_cast<Name>(base+0x144d90)(&df::global::world->raws.plants.all,p.plant_id,&part,false,true);
                    std::string reason;using Reason=void(*)(void*,std::string*,int32_t,int32_t);
                    reinterpret_cast<Reason>(base+0xe35d60)(&df::global::world->raws.plants.all,&reason,p.plant_id,p.prefstring_seed);
                    part+=literal(0x1640050);part+=reason;break;
                }
                case 7:{using Name=void(*)(void*,std::string*,int16_t);reinterpret_cast<Name>(base+0x420fc0)(&df::global::world->raws.descriptors,&part,int16_t(p.color_id));part=literal(0x1640040)+part;break;}
                case 8:{using Name=void(*)(void*,std::string*,int16_t,bool);reinterpret_cast<Name>(base+0x1437f0)(&df::global::world->raws.descriptors,&part,int16_t(p.shape_id),true);break;}
                case 9:case 10:case 11:{
                    df::language_name* name=nullptr;
                    if(int(p.type)==9){auto* form=df::poetic_form::find(p.poetic_form_id);if(form)name=&form->name;}
                    else if(int(p.type)==10){auto* form=df::musical_form::find(p.musical_form_id);if(form)name=&form->name;}
                    else {auto* form=df::dance_form::find(p.dance_form_id);if(form)name=&form->name;}
                    if(name && name->has_name){using Name=void(*)(df::language_name*,std::string*,bool,bool);reinterpret_cast<Name>(base+0xa946e0)(name,&part,true,false);part=literal(int(p.type)==9?0x1640030:int(p.type)==10?0x1640020:0x1640600)+part;}break;
                }
            }
            text+=part;--remaining;text+=literal(remaining>1?0x15e90d8:remaining>0?0x15e9110:0x15fd968);
            if(text.size()>65536)return std::nullopt;
        }
    }
    return text;
}
}
