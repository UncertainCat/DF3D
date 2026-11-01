#pragma once
#include "creature_thoughts_native.h"
#include "df/unit_soul.h"
#include "df/unit_personality.h"
#include "df/curse_attr_change.h"
#include "df/unit_misc_trait.h"
namespace df3d_creature {
inline std::optional<std::string> personalityValues(const df::unit* source) {
    if(!source || !df::global::world || !thoughtDescriptionReady())return std::nullopt;
    if(!source->status.current_soul)return std::string{};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xe248a0,0x2400,UINT64_C(0xaa9ae807069b6006)},
            {0x52c130,0xb3,UINT64_C(0xf2e358ad54df1c09)},
            {0x52c2b0,0xd8,UINT64_C(0x38b6489e35387929)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();if(!ready)return std::nullopt;
    const auto& soul=*source->status.current_soul;
    auto personality=soul.personality;
    struct OwnedUnit final:df::unit {OwnedUnit():df::unit(){}} unit;
    unit.race=source->race;unit.sex=source->sex;
    InventoryRandomRestore random(base);
    KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::string text;
    // Native4815a4..4815d6: cultural/personal values, memory causes and dreams.
    // The personality vectors and output are owned; pointed-to value/memory
    // records and cultural world records are read-only. The unit is used only
    // by the native circumstance formatter (race/sex); no sheet state is used.
    using Describe=void(*)(df::unit_personality*,df::unit*,int32_t,int8_t,std::string*,bool,int32_t);
    reinterpret_cast<Describe>(base+0xe248a0)(&personality,&unit,soul.race,soul.sex,&text,true,3);
    if(text.size()>65536)return std::nullopt;
    return text;
}

inline std::optional<std::string> personalityTraits(const df::unit* source) {
    if(!source || !df::global::world || !thoughtDescriptionReady())return std::nullopt;
    if(!source->status.current_soul)return std::string{};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x13811b0,0x1184,UINT64_C(0xf2fe25a89199f079)},
            {0xe26ca0,0x53e4,UINT64_C(0x56a2e42e20379423)},
            {0x10e3280,0x5284,UINT64_C(0xab89c310d1f9c928)},
            {0x13b3030,0x56,UINT64_C(0xf9404dd6eb50e2af)},
            {0xb530b0,0xac,UINT64_C(0x7c6f66602bdab157)},
            {0xbba90,0x4d,UINT64_C(0xed2f3182ec70fe9a)},
            {0x4818ee,0x383,UINT64_C(0x58a5d3b4290050f2)},
            {0x1602430,0xa,UINT64_C(0xd4bd098ef4c1f7c2)},
            {0x1640270,0x2e,UINT64_C(0x64abea4892eaf460)},
            {0x1640248,0x28,UINT64_C(0x2f983e23ffdb5824)},
            {0x16400f0,0xa,UINT64_C(0x50ceb72087334050)},
            {0x16400b8,0x34,UINT64_C(0xcc3413b655342e4d)},
            {0x1640098,0x1a,UINT64_C(0xaa1af086e3774ecf)},
            {0x1640060,0x34,UINT64_C(0xccdef8d629270fef)},
            {0x15fd968,0x4,UINT64_C(0xf813dda63efcb2bb)},
            {0x1640150,0x49,UINT64_C(0x027a0fb7ae343ce0)},
            {0x16401a0,0x36,UINT64_C(0x68968aeb4c374a9a)},
            {0x1640120,0x2f,UINT64_C(0x164b0a76616e8e81)},
            {0x1640100,0x1d,UINT64_C(0xdfcddb4a98afc0cc)},
            {0x1640000,0x1f,UINT64_C(0x8470a44def923231)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();if(!ready)return std::nullopt;
    auto soul=*source->status.current_soul;
    struct OwnedUnit final:df::unit {OwnedUnit():df::unit(){}} unit;
    unit.race=source->race;unit.sex=source->sex;
    unit.hist_figure_id=source->hist_figure_id;
    unit.enemy.histfig_vector_idx=-1;
    unit.status.current_soul=&soul;
    df::curse_attr_change attributes;
    if(source->uwss_att_change){attributes=*source->uwss_att_change;unit.uwss_att_change=&attributes;}
    static_assert(offsetof(df::unit,status.current_soul)==0xa98);
    static_assert(offsetof(df::unit,enemy.histfig_vector_idx)==0x1274);
    InventoryRandomRestore random(base);
    KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::string text,paragraph;
    const auto append=[&] {if(!paragraph.empty()){if(!text.empty())text+="[B]";text+=paragraph;paragraph.clear();}};
    // Native Traits uses three independent semantic formatters. Soul vectors,
    // output and the identity lookup's mutable unit cache are owned. Pointed-to
    // personality records, historical identities and creature raws are read-only.
    using Attributes=void(*)(df::unit*,std::string*);
    reinterpret_cast<Attributes>(base+0x13811b0)(&unit,&paragraph);append();
    using Facets=void(*)(df::unit_personality*,df::unit*,int32_t,int8_t,std::string*,bool);
    reinterpret_cast<Facets>(base+0xe26ca0)(&soul.personality,&unit,soul.race,soul.sex,&paragraph,true);append();
    using Mannerisms=void(*)(df::unit_soul*,std::string*);
    reinterpret_cast<Mannerisms>(base+0x10e3280)(&soul,&paragraph);append();
    // Conditions are inline in4818ee..481c71, not an independent routine.
    // Reproduce that scalar composition with pinned installed literals and the
    // native pronoun formatter; never invoke the sheet-writing wrapper.
    const auto literal=[&](size_t rva){return reinterpret_cast<const char*>(base+rva);};
    const auto subject=[&](bool capitalized){std::string value;using Pronoun=void(*)(int8_t,std::string*,bool);reinterpret_cast<Pronoun>(base+0xaa4730)(unit.sex,&value,capitalized);return value;};
    for(const auto* trait:source->status.misc_traits)if(trait && int(trait->id)==13){
        paragraph=literal(0x1602430);paragraph+=subject(true);paragraph+=literal(0x1640270);
        if(trait->value>=403200){paragraph+=literal(0x1640248);paragraph+=subject(false);paragraph+=literal(0x16400f0);}
        else if(trait->value>=302400)paragraph+=literal(0x16400b8);
        else if(trait->value>=201600)paragraph+=literal(0x1640098);
        else if(trait->value>=100800)paragraph+=literal(0x1640060);
        paragraph+=literal(0x15fd968);break;
    }
    if(paragraph.empty())paragraph=literal(0x1602430);
    if(soul.personality.likes_outdoors==2)paragraph+=subject(true)+literal(0x1640150);
    else if(soul.personality.likes_outdoors==1)paragraph+=subject(true)+literal(0x16401a0);
    if(soul.personality.combat_hardened==100)paragraph+=subject(true)+literal(0x1640120);
    else if(soul.personality.combat_hardened>=67)paragraph+=subject(true)+literal(0x1640100);
    else if(soul.personality.combat_hardened>=33)paragraph+=subject(true)+literal(0x1640000);
    append();
    if(text.size()>65536)return std::nullopt;
    return text;
}
}
