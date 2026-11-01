#pragma once
#include "unit_description_native.h"
#include "df/poetic_form.h"
#include "df/poetic_form_part.h"
#include "df/poetic_form_perspective.h"
#include <memory>
namespace df3d_creature {
// Native poetic-form prose with independently owned form/part/persona storage.
// Historical and raw name helpers read world records; their mutable strings and
// historical-format context are created by the formatter, never borrowed from UI.
inline bool knowledgeDescriptionReady() {
    if(!inventoryDescriptionReady())return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    struct Pin {size_t rva,length;uint64_t hash;};
    constexpr Pin pins[]={
        {0xe76400,0x6ac8,UINT64_C(0x42da003339c26ed2)},
        {0xe76080,0x37c,UINT64_C(0x6a5c75842832cda8)},
        {0xb92900,0x178,UINT64_C(0x7485ca6699669626)},
        {0xb92f10,0xa17,UINT64_C(0x07701ee83ad6d384)},
        {0xb94ed0,0x14c,UINT64_C(0xe8574022184115a7)},
        {0x72080,0xed,UINT64_C(0xe0cf31f3be155555)},
        {0x67dc0,0x70,UINT64_C(0x17c7b286d4141624)},
        {0xb9dc0,0xa7,UINT64_C(0x4d8961b901732215)},
        {0x756690,0xcec,UINT64_C(0x65737daa3f8504f3)},
        {0xaa3770,0xf8,UINT64_C(0xe12c977ce710042a)},
        {0xaa3bd0,0x1c3,UINT64_C(0x0f9cd818efc6bad8)},
        {0x52d080,0x19e,UINT64_C(0x227987757895dfeb)},
        {0x52d650,0x2b4,UINT64_C(0x9e8023d09def7af9)},
        {0x52e360,0x80c,UINT64_C(0xee45c63ac127591b)},
        {0x52eb70,0x520,UINT64_C(0xbc59e8efca06a7fb)},
        {0x52c130,0xb3,UINT64_C(0xf2e358ad54df1c09)},
        {0x7daf0,0x25,UINT64_C(0xe08224475d4dff6a)},
        {0xba0a0,0xa8,UINT64_C(0xcf6b2a7b534d3331)},
    };
    for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
    return true;
}
inline std::optional<std::string> poeticDetailProbe(df::poetic_form* source) {
    if(!source || !knowledgeDescriptionReady() || source->parts.size()>4096 || source->perspectives.size()>4096)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    struct OwnedForm final:df::poetic_form {OwnedForm():df::poetic_form(){}} form;
    struct OwnedPart final:df::poetic_form_part {OwnedPart():df::poetic_form_part(){}};
    struct OwnedPerspective final:df::poetic_form_perspective {OwnedPerspective():df::poetic_form_perspective(){}};
    static_cast<df::poetic_form&>(form)=*source;
    form.parts.clear();form.perspectives.clear();
    std::vector<std::unique_ptr<OwnedPart>> parts;
    std::vector<std::unique_ptr<OwnedPerspective>> perspectives;
    for(const auto* original:source->parts){
        if(!original)return std::nullopt;
        auto part=std::make_unique<OwnedPart>();static_cast<df::poetic_form_part&>(*part)=*original;
        form.parts.push_back(part.get());parts.push_back(std::move(part));
    }
    for(const auto* original:source->perspectives){
        if(!original)return std::nullopt;
        auto perspective=std::make_unique<OwnedPerspective>();static_cast<df::poetic_form_perspective&>(*perspective)=*original;
        form.perspectives.push_back(perspective.get());perspectives.push_back(std::move(perspective));
    }
    std::string result(reinterpret_cast<const char*>(base+0x1602430)); // Native1b4094 prefix.
    reinterpret_cast<void(*)(df::poetic_form*,std::string*)>(base+0xe76400)(&form,&result);
    if(result.size()>65536)return std::nullopt;
    return result;
}
}
