#pragma once
#include "knowledge_detail_native.h"
#include "df/dance_form.h"
#include "df/dance_form_section.h"
#include "df/dance_form_move.h"
namespace df3d_creature {
// Diagnostic formatter, not yet a production provider. Event-type acceptance
// is tracked separately from the independently owned dance data graph.
inline std::optional<std::string> danceDetailProbe(df::dance_form* source) {
    if(!source || !knowledgeDescriptionReady() || source->sections.size()>4096 || source->moves.size()>4096)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    struct Pin {size_t rva,length;uint64_t hash;};
    constexpr Pin pins[]={
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
    for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return std::nullopt;}
    struct OwnedForm final:df::dance_form {OwnedForm():df::dance_form(){}} form;
    struct OwnedSection final:df::dance_form_section {OwnedSection():df::dance_form_section(){}};
    struct OwnedMove final:df::dance_form_move {OwnedMove():df::dance_form_move(){}};
    static_cast<df::dance_form&>(form)=*source;
    form.sections.clear();form.moves.clear();
    std::vector<std::unique_ptr<OwnedSection>> sections;
    std::vector<std::unique_ptr<OwnedMove>> moves;
    for(const auto* original:source->sections){
        if(!original)return std::nullopt;
        auto value=std::make_unique<OwnedSection>();static_cast<df::dance_form_section&>(*value)=*original;
        form.sections.push_back(value.get());sections.push_back(std::move(value));
    }
    for(const auto* original:source->moves){
        if(!original)return std::nullopt;
        auto value=std::make_unique<OwnedMove>();static_cast<df::dance_form_move&>(*value)=*original;
        form.moves.push_back(value.get());moves.push_back(std::move(value));
    }
    std::string result(reinterpret_cast<const char*>(base+0x1602430));
    reinterpret_cast<void(*)(df::dance_form*,std::string*)>(base+0x4ea820)(&form,&result);
    if(result.size()>65536)return std::nullopt;
    return result;
}
}
