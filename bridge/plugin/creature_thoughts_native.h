#pragma once
#include "unit_description_native.h"
#include "knowledge_detail_native.h"
namespace df3d_creature {
inline bool thoughtDescriptionReady() {
    static const bool ready=[] {
        if(!inventoryDescriptionReady() || !knowledgeDescriptionReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xe2c460,0x6690,UINT64_C(0xa95b59ad5c95e873)},
            {0xee0380,0x930,UINT64_C(0xfd069343cfbb11fa)},
            {0xef8fb0,0x2450,UINT64_C(0x9385f8fcc58f27df)},
            {0x6dd860,0x66b,UINT64_C(0xaf8d725e61324b3e)},
            {0xbc56b0,0x2581,UINT64_C(0x636f51694245eb2c)},
            {0xcb1720,0x63,UINT64_C(0xb03bc00c14a2d687)},
            {0xa94030,0x6a1,UINT64_C(0xd81db68b3c9b33d2)},
            {0xa946e0,0x7c2,UINT64_C(0xdbc3db5f052419ee)},
            {0xc65450,0xaba,UINT64_C(0x47fa672b7bbcd332)},
            {0x1a7d15,0x16d,UINT64_C(0x3613f07f43a550ca)},
            {0xaa47b0,0x4b,UINT64_C(0x661c9f89182f8905)},
            {0xaa4850,0x6e,UINT64_C(0xd802cdd04b552aaa)},
            {0x1602c60,0xba,UINT64_C(0xdb20e3ff5c8e85ba)},
            {0x1602ad8,0xb,UINT64_C(0x3803be9098ba43c1)},
            {0x1602430,0x1a,UINT64_C(0xd23ecfead90e0c1e)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();return ready;
}
// Native1a7d0d/1a7eba call this semantic formatter, independently of the sheet
// vectors and emotion grammar. The only unit reads are race and sex; the unit
// pointer is not passed to a callee. All text storage is owned. World lookups
// supply names/items/history, including history_event_collection::getName.
inline std::optional<std::string> thoughtCircumstance(const df::unit* source,
        int32_t thought,int32_t subthought,int32_t severity,bool normal,
        uint32_t emotionFlags=0,bool past=false) {
    if(!source || !df::global::world || !thoughtDescriptionReady())return std::nullopt;
    if(thought<0 || thought>280)return std::string{};
    struct OwnedUnit final:df::unit {OwnedUnit():df::unit(){}} owned;
    owned.race=source->race;owned.sex=source->sex;
    static_assert(offsetof(df::unit,race)==0xa4);
    static_assert(offsetof(df::unit,sex)==0x12e);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    InventoryRandomRestore random(base);
    KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::string text;
    using Describe=void(*)(df::unit*,std::string*,int32_t,int32_t,int32_t,bool);
    reinterpret_cast<Describe>(base+0xe2c460)(&owned,&text,thought,subthought,severity,normal);
    // Native1a7d15..1a7e82 is inline in the sheet builder, not a callable
    // semantic routine. Adapt only its flag dispatch using immutable native
    // literals and native pronoun helpers; never call the UI/cache builder.
    // Memory-tab callers omit flags: this elaboration belongs to emotions.
    if(!normal && (emotionFlags&0x70) && (emotionFlags&0x180)) {
        std::string object,possessive;
        using ObjectPronoun=void(*)(uint8_t,std::string*);
        using PossessivePronoun=void(*)(uint8_t,std::string*,bool);
        reinterpret_cast<ObjectPronoun>(base+0xaa47b0)(owned.sex,&object);
        reinterpret_cast<PossessivePronoun>(base+0xaa4850)(owned.sex,&possessive,false);
        const auto literal=[&](size_t rva){return reinterpret_cast<const char*>(base+rva);};
        text+=literal(past?0x1602ad8:0x1602d10);
        text+=literal(0x1602ce8);
        if(emotionFlags&0x100) {
            text+=literal(0x1602cd8);text+=object;text+=literal(0x1602cc8);text+=possessive;
            if(emotionFlags&0x80) {
                text+=literal(0x1602ca0);text+=possessive;text+=literal(0x1602c88);
            } else text+=literal(0x1602c60);
        } else {
            text+=literal(0x1602c78);text+=possessive;text+=literal(0x1602c88);
        }
        text+=literal(past?0x1602440:0x1602430);
    }
    if(text.size()>65536)return std::nullopt;
    return text;
}
}
