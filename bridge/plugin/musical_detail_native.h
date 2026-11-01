#pragma once
#include "knowledge_detail_native.h"
#include "df/musical_form.h"
#include "df/musical_form_passage.h"
#include "df/musical_form_instruments.h"
#include "df/musical_form_melodies.h"
#include "df/musical_form_interval.h"
#include "df/musical_form_play_orderst.h"
namespace df3d_creature {
// Form-owned pointer graphs are independent; referenced definitions are read-only.
// Native sorted sets and iterator scratch live on the formatter's own stack.
class MusicDescriptionContext {
    template<class T> struct Owned final:T {Owned():T(){}};
    template<class T> using Storage=std::vector<std::unique_ptr<Owned<T>>>;
    Owned<df::musical_form> form;
    Storage<df::musical_form_passage> passages;
    Storage<df::musical_form_instruments> instruments;
    Storage<df::musical_form_melodies> melodies;
    Storage<df::musical_form_interval> intervals;
    Storage<df::musical_form_play_orderst> order;
    size_t remaining=65536;
    template<class T> bool copy(const std::vector<T*>& source,std::vector<T*>& destination,Storage<T>& storage) {
        destination.clear();
        if(source.size()>4096 || source.size()>remaining)return false;
        remaining-=source.size();
        for(const auto* value:source){
            if(!value)return false;
            auto item=std::make_unique<Owned<T>>();static_cast<T&>(*item)=*value;
            destination.push_back(item.get());storage.push_back(std::move(item));
        }
        return true;
    }
public:
    bool initialize(const df::musical_form& source) {
        static_cast<df::musical_form&>(form)=source;
        if(!copy(source.passages,form.passages,passages) ||
           !copy(source.instruments,form.instruments,instruments) ||
           !copy(source.melodies,form.melodies,melodies) ||
           !copy(source.play_order,form.play_order,order))return false;
        for(auto& passage:passages){
            const auto originals=passage->melodies;
            if(!copy(originals,passage->melodies,melodies))return false;
        }
        for(auto& melody:melodies){
            const auto originals=melody->intervals;
            if(!copy(originals,melody->intervals,intervals))return false;
        }
        return true;
    }
    df::musical_form* get(){return &form;}
};
inline std::optional<std::string> musicalDetailProbe(df::musical_form* source) {
    if(!source || !knowledgeDescriptionReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    struct Pin {size_t rva,length;uint64_t hash;};
    constexpr Pin pins[]={
        {0xdd5ce0,0x7784,UINT64_C(0xc02c4d9fc6a18c4d)},
        {0xdd4db0,0x10f,UINT64_C(0x3a065e771ab70140)},
        {0x77cf20,0x64c,UINT64_C(0xf13499780b73cd50)},
        {0x71e60,0x9,UINT64_C(0x06f8281ca841a155)},
        {0x657b0,0x7,UINT64_C(0x8ed7b69d3403667e)},
        {0x65b00,0x11,UINT64_C(0xded3414b6bac64b5)},
        {0x65b20,0x5,UINT64_C(0xc3fb6fded432a7cb)},
        {0x6f350,0x8,UINT64_C(0xe230c8a5918dc848)},
        {0x6f370,0xc,UINT64_C(0xe8009075ae23e49b)},
        {0x6f410,0x1d,UINT64_C(0xc4deaa9fd6b78e02)},
        {0xb9f70,0x25,UINT64_C(0xe6e732b038db044e)},
        {0xb9e70,0xf8,UINT64_C(0x7dab880be6ec9cba)},
        {0xbabe0,0xab,UINT64_C(0x1bd318997a061458)},
        {0x6f750,0x5c,UINT64_C(0x181cd460420a0890)},
        {0x70e20,0x117,UINT64_C(0x09aba69f846f6c10)},
    };
    for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return std::nullopt;}
    MusicDescriptionContext context;if(!context.initialize(*source))return std::nullopt;
    std::string result(reinterpret_cast<const char*>(base+0x1602430));
    reinterpret_cast<void(*)(df::musical_form*,std::string*)>(base+0xdd5ce0)(context.get(),&result);
    if(result.size()>65536)return std::nullopt;
    return result;
}
}
