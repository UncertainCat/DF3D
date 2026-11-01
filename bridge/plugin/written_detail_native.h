#pragma once
#include "musical_detail_native.h"
#include "dance_detail_native.h"
#include "df/general_ref.h"
#include "df/general_ref_historical_eventst.h"
#include "df/written_content.h"
#include "df/historical_figure.h"
namespace df3d_creature {
// Diagnostic only. The native body owns its output/scratch. All content fields
// and references are copied; referenced world names/events remain read-only.
// Complete production acceptance still requires the remaining event paths.
inline bool writtenDescriptionReady() {
    if(!knowledgeDescriptionReady())return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    struct Pin {size_t rva,length;uint64_t hash;};
    constexpr Pin pins[]={
        {0xca0d00,0x55,UINT64_C(0x6891982ef52f2367)},
        {0x5be970,0x536,UINT64_C(0xd785ec19f3aa4618)},
        {0x52c2b0,0xd8,UINT64_C(0x38b6489e35387929)},
        {0xc3a590,0xcbf,UINT64_C(0x09a894440651f51f)},
        {0x132e0c0,0x368,UINT64_C(0x5020a6b8e463a24d)},
        {0xb65030,0x1b8,UINT64_C(0x6557e947120f0a0b)},
        {0xb8c2b0,0x6db,UINT64_C(0x393d1fb27e6e1a4b)},
        {0x72280,0x16,UINT64_C(0x6cfdc4a2d0a9e45d)},
        {0xbc080,0x9a,UINT64_C(0x18dd82edba346129)},
        {0xe1560,0xab,UINT64_C(0x4df0c1e27847ffc7)},
        {0x1b3985,0x4d4,UINT64_C(0xf47129abd4770425)},
        {0x1b9960,0x8c,UINT64_C(0xcd65dbe87bf8f8e6)},
        {0xb663a0,0x13e,UINT64_C(0x74d9223f54b96f0c)},
        {0xb8e990,0x272,UINT64_C(0x8cc31767cfe9afcb)},
        {0xc0f660,0x4e,UINT64_C(0x4ffd6c6ce672159c)},
        {0xcc5520,0x830,UINT64_C(0xd1a05c73b7a068b5)},
        {0xcc5d50,0xcc0,UINT64_C(0xb3c5f41a1fdeef31)},
        {0xedfd50,0xf4,UINT64_C(0xf3f44bc40825b8bc)},
        {0xedfe50,0x181,UINT64_C(0xee6e6e3cd75f1faa)},
        {0xedffe0,0x181,UINT64_C(0x52b6fcd72a4cf2e2)},
        {0xee0170,0x13a,UINT64_C(0xe7c602e497653e41)},
        {0xee02b0,0xc2,UINT64_C(0x7a916ff6863e447c)},
        {0xee0380,0x4ac,UINT64_C(0xa184f9ce9dd4d894)},
        {0xee0ca0,0x28b4,UINT64_C(0x719b7456b391ccaf)},
        {0xee3560,0x86,UINT64_C(0x79f5aedef9155114)},
        {0xeec6b0,0x27d,UINT64_C(0xbcde3ab1691c87db)},
        {0xeed3b0,0x46c,UINT64_C(0x32b4a966069c3d98)},
        {0xeedd40,0x71,UINT64_C(0x538c8c3dc5330732)},
        {0xef0690,0x3fe,UINT64_C(0x5f1f9bfbe84777af)},
        {0xef14a0,0x21,UINT64_C(0xd79779d69f461678)},
        {0xef1770,0x236,UINT64_C(0x467ada3742a10b56)},
        {0xef2d60,0x158,UINT64_C(0x99957bc3a6e657bd)},
        {0xef4350,0x1b3,UINT64_C(0x7978d134d2bc2e10)},
        {0xef49a0,0x120,UINT64_C(0xc3649ff6ef71a62b)},
        {0xef4c10,0xb6,UINT64_C(0xcf4e0253422bdc34)},
        {0xef4e10,0xa3,UINT64_C(0x562b69b4ca034972)},
        {0xef5280,0x1a0,UINT64_C(0x6d3bfc2033c5ccac)},
        {0x10cbe50,0x33c,UINT64_C(0xaa4e263ab5438d11)},
        {0x4ea820,0x42e8,UINT64_C(0x9cb7bc42be4693f7)},
        {0x4e99f0,0xe24,UINT64_C(0xbe3650a1c5ba887e)},
        {0x7da30,0xb3,UINT64_C(0xa91f2722090923d0)},
        {0xb69bb0,0x17e,UINT64_C(0x770b7c3e1cfbf0a6)},
        {0xb69d30,0x1c9,UINT64_C(0x8f89c4f250e5b86b)},
        {0xb77430,0x2e7,UINT64_C(0x68e110a467cb9073)},
        {0xb80420,0x6b4,UINT64_C(0xde44fccbc2765650)},
        {0xb93930,0x15a,UINT64_C(0x1ab3438f9be56fa2)},
        {0xb94090,0x368,UINT64_C(0xb4728c2a90d0f54e)},
        {0xb94940,0xf6,UINT64_C(0x9212620ec0e20427)},
        {0xb94a40,0x157,UINT64_C(0x47255515af7da23e)},
        {0xb92640,0x2b4,UINT64_C(0xed9f612ded76daea)},
        {0xb5a6c0,0x13f1,UINT64_C(0x4e95e628626945c4)},
        {0x1ba140,0xa8,UINT64_C(0xdb6eb9072d509b29)},
        {0x6ff00,0xa8,UINT64_C(0x95c810961f82c229)},
        {0x7db20,0xb6,UINT64_C(0x4ee4244d4f7af0ae)},
        {0xbad30,0x118,UINT64_C(0xea445ea01cfc50c1)},
        {0x66b70,0x5c,UINT64_C(0xb65a09fabb030b21)},
        {0xb9980,0x1e,UINT64_C(0xfaa5c1133f00b330)},
    };
    for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
    return true;
}
class WrittenDescriptionContext {
    struct OwnedContent final:df::written_content {OwnedContent():df::written_content(){}} content;
    struct DeleteReference {
        const DFHack::virtual_identity* identity;
        void operator()(df::general_ref* value)const {if(value)identity->destroy(value);}
    };
    std::vector<std::unique_ptr<df::general_ref,DeleteReference>> refs;
public:
    bool prepare(const df::written_content& source) {
        if(source.refs.size()>4096 || source.styles.size()>4096 ||
           source.refs.size()!=source.ref_aux.size() || source.styles.size()!=source.style_strength.size())return false;
        static_cast<df::written_content&>(content)=source;
        content.refs.clear();refs.clear();
        for(auto* original:source.refs){
            if(!original)return false;
            if(original->getType()==df::general_ref_type::HISTORICAL_EVENT &&
               !knowledgeEventInputsValid(static_cast<df::general_ref_historical_eventst*>(original)->event_id))return false;
            const auto* identity=DFHack::virtual_identity::get(original);
            if(!identity || !identity->can_instantiate())return false;
            auto* copy=static_cast<df::general_ref*>(identity->instantiate());
            if(!copy)return false;
            std::unique_ptr<df::general_ref,DeleteReference> owned(copy,DeleteReference{identity});
            if(!identity->copy(copy,original))return false;
            content.refs.push_back(copy);refs.push_back(std::move(owned));
        }
        return true;
    }
    df::written_content* get(){return &content;}
};
inline std::optional<std::string> writtenDetailProbe(df::written_content* source) {
    if(!source || !writtenDescriptionReady())return std::nullopt;
    if(!df::global::world)return std::nullopt;
    KnowledgeMaterialCacheRestore cache_restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    WrittenDescriptionContext owned;if(!owned.prepare(*source))return std::nullopt;
    auto* content=owned.get();auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto literal=[&](size_t rva){return reinterpret_cast<const char*>(base+rva);};
    std::string result(literal(0x1602430));
    const int type=static_cast<int>(content->type);
    // Exact inline native Skills prefix (1b3985..1b3be2), with native literals.
    if(content->title.empty())result+=literal(0x1602da0);
    else {
        result+=content->title;result+=literal(0x15f71e4);
        const bool vowel=type==6 || type==10 || type==17 || type==20 || type==25;
        result+=literal(vowel?0x1602db8:0x1602db4);
    }
    result+=literal(0x15e873c);
    constexpr size_t labels[]={0x1602d94,0x1602d8c,0x1602d80,0x1602d70,0x1602d64,0x1602d58,0x1602d48,0x1602d3c,0x1602d34,0x1602d2c,0x1602d24,0x1602d1c,0x1602ef0,0x1602ee0,0x1602ec8,0x1602eb0,0x1602ea0,0x1602e90,0x1602e78,0x1602e60,0x1602e48,0x1602e20,0x1602e10,0x1602e00,0x1602df0,0x1602de8};
    if(type>=0 && type<26)result+=literal(labels[type]);
    if(auto* author=df::historical_figure::find(content->author)){
        result+=literal(0x1602dd8);
        auto* name=reinterpret_cast<df::language_name*(*)(df::historical_figure*)>(base+0xc0f660)(author);
        if(name && name->has_name){
            std::string formatted;
            reinterpret_cast<void(*)(df::language_name*,std::string*)>(base+0xa94030)(name,&formatted);
            result+=formatted;
        }
    }
    result+=literal(0x15fd968);
    std::optional<std::string> art;
    df::language_name* art_name=nullptr;
    if(type==7){if(auto* form=df::poetic_form::find(content->poetic_form)){art=poeticDetailProbe(form);art_name=&form->name;}}
    else if(type==12){if(auto* form=df::musical_form::find(content->poetic_form)){art=musicalDetailProbe(form);art_name=&form->name;}}
    else if(type==13){if(auto* form=df::dance_form::find(content->poetic_form)){art=danceDetailProbe(form);art_name=&form->name;}}
    if(art_name){
        if(!art)return std::nullopt;
        result+=literal(0x1602dc0);std::string translated;
        reinterpret_cast<void(*)(df::language_name*,std::string*,bool,int)>(base+0xa946e0)(art_name,&translated,true,0);
        result+=translated;result+=literal(0x15fd968);
    }
    reinterpret_cast<void(*)(df::written_content*,std::string*,uint32_t)>(base+0xcc5d50)(content,&result,0);
    if(art){
        const std::string prefix(literal(0x1602430));
        if(art->compare(0,prefix.size(),prefix)!=0)return std::nullopt;
        result+=literal(0x15fd258);result.append(*art,prefix.size(),std::string::npos);
    }
    if(result.size()>65536)return std::nullopt;
    return result;
}
}
