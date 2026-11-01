#pragma once
#include "knowledge_detail_native.h"
#include "df/general_ref_knowledge_scholar_flagst.h"
#include "df/musical_form.h"
#include "df/dance_form.h"
#include "df/written_content.h"
namespace df3d_creature {
// Native Skills primary captions; owned strings/reference scratch, read-only raws.
inline bool skillsCaptionReady() {
    if(!knowledgeDescriptionReady())return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    struct Pin {size_t rva,length;uint64_t hash;};
    constexpr Pin pins[]={
        {0x7737c0,0x1c8,UINT64_C(0x92329f264495e495)},
        {0x774730,0xda0,UINT64_C(0x3eed13f482acea4f)},
        {0xef8fb0,0x2758,UINT64_C(0x21f1b754b5322386)},
        {0x30cea0,0xc3,UINT64_C(0x47a07e027acb5ada)},
        {0x30cf70,0x174,UINT64_C(0x6f623c8eaf55f9c1)},
        {0x764a70,0x3c9,UINT64_C(0xfe54e4ebd35a80fa)},
    };
    for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
    return true;
}
inline std::string nativeSkillCaption(int16_t skill,int32_t rating,int16_t race,int16_t caste) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    std::string text,noun;
    reinterpret_cast<void(*)(std::string*,int32_t)>(base+0x7737c0)(&text,rating);
    if(!text.empty())text+=reinterpret_cast<const char*>(base+0x15e873c);
    reinterpret_cast<void(*)(std::string*,int16_t,int16_t,int16_t)>(base+0x774730)(&noun,skill,race,caste);
    text+=noun;return text;
}
inline std::string nativeKnowledgeCaption(int32_t type,int32_t id,uint32_t bits) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    std::string text;df::language_name* name=nullptr;
    if(type>=0 && type<14){
        struct OwnedRef final:df::general_ref_knowledge_scholar_flagst {OwnedRef():df::general_ref_knowledge_scholar_flagst(){}} ref;
        ref.knowledge.flag_type=static_cast<decltype(ref.knowledge.flag_type)>(type);
        ref.knowledge.flag_data.whole=bits;
        reinterpret_cast<void(*)(df::general_ref_knowledge_scholar_flagst*,std::string*)>(base+0xef8fb0)(&ref,&text);
    } else if(type==14){if(auto* form=df::poetic_form::find(id))name=&form->name;}
    else if(type==15){if(auto* form=df::musical_form::find(id))name=&form->name;}
    else if(type==16){if(auto* form=df::dance_form::find(id))name=&form->name;}
    else if(type==17){if(auto* content=df::written_content::find(id)){text=content->title;if(text.empty())text=reinterpret_cast<const char*>(base+0x15fda98);}}
    if(name)reinterpret_cast<void(*)(df::language_name*,std::string*,bool,int)>(base+0xa946e0)(name,&text,true,0);
    reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&text);
    return text;
}
}
