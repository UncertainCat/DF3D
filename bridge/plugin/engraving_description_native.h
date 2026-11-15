#pragma once
#include "tile_selection_native.h"
#include "unit_description_native.h"
#include "knowledge_detail_native.h"
#include "df/art_image.h"
#include "df/art_image_chunk.h"
#include "df/art_image_element.h"
#include "df/art_image_property.h"
#include "df/art_image_property_intransitive_verbst.h"
#include "df/art_image_property_transitive_verbst.h"
#include "df/general_ref_mapsquare.h"

namespace df3d_selection {
// Staged formatter probe. Cold semantic-art initialization is deliberately a
// separate unresolved operation; this never invokes sheet population1a9cc0.
struct EngravingDescription {std::string title,description;};
inline uint64_t engravingHash(const uint8_t* p,size_t count) {
    uint64_t value=UINT64_C(14695981039346656037);
    for(size_t i=0;i<count;++i){value^=p[i];value*=UINT64_C(1099511628211);}
    return value;
}
inline bool engravingDescriptionReady() {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        for(const auto& p:std::initializer_list<Pin>{
            {0x1458b0,0xe03,UINT64_C(0xe863f0cb03756390)}, // existing artwork chunk loader
            {0x144cb0,0xa5,UINT64_C(0x5b86c4fc644fe651)}, // chunk allocation/registration
            {0x1443f0,0x7f,UINT64_C(0x93648c11fc43c8ee)}, // image construction
            {0x144890,0x41a,UINT64_C(0x5832ca5a0d1254d4)}, // image deserialization
            {0xa94030,0x6a1,UINT64_C(0xd81db68b3c9b33d2)},
            {0xa946e0,0x7c2,UINT64_C(0xdbc3db5f052419ee)},
            {0x1451b10,0x161c,UINT64_C(0x5afdbfca1604e13b)}})
            if(engravingHash(base+p.rva,p.length)!=p.hash)return false;
        struct Virtual {size_t table,slot,fn,length;uint64_t hash;};
        for(const auto& p:std::initializer_list<Virtual>{
            {0x15fdc90,7,0x148320,0xbaf,UINT64_C(0xfbcff940a763398f)},
            {0x15fdf68,7,0x147b60,0x5b2,UINT64_C(0x35e1eca3b00e0a7e)},
            {0x15fdd10,7,0x149120,0x1fe,UINT64_C(0x0ed6d4003df03970)},
            {0x15fdf00,7,0x149120,0x1fe,UINT64_C(0x0ed6d4003df03970)},
            {0x15fdbf0,7,0x147640,0x2cb,UINT64_C(0x37cc79d065976e4e)},
            {0x15fdde8,5,0x146eb0,0x790,UINT64_C(0x8b03a96c7e40f760)},
            {0x15fddb0,5,0x146750,0x754,UINT64_C(0x152484f78089e402)},
            {0x16cc0f8,2,0x67530,6,UINT64_C(0xe59b01b045c53219)}}) {
            if(*reinterpret_cast<const void* const*>(base+p.table+p.slot*8)!=base+p.fn ||
               engravingHash(base+p.fn,p.length)!=p.hash)return false;
        }
        return true;
    }();
    return ready;
}
class EngravingImageContext {
    struct OwnedImage final:df::art_image {} image;
    struct Delete {
        const DFHack::virtual_identity* identity;
        void operator()(void* value)const {if(value)identity->destroy(value);}
    };
    // Keep the concrete allocation address: converting to the empty
    // virtual_class base can adjust it before identity->destroy receives it.
    std::vector<std::unique_ptr<void,Delete>> children;
    template<class T>T* copy(T* source) {
        const auto* identity=DFHack::virtual_identity::get(source);
        if(!identity || !identity->can_instantiate())return nullptr;
        auto* result=static_cast<T*>(identity->instantiate());
        if(!result)return nullptr;
        std::unique_ptr<void,Delete> owned(result,Delete{identity});
        if(!identity->copy(result,source))return nullptr;
        children.push_back(std::move(owned));return result;
    }
public:
    bool prepare(const df::art_image& source,std::string& failure) {
        failure="image-size";
        if(source.elements.size()>256 || source.properties.size()>256)return false;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        failure="reference-dispatch";
        if(source.ref && *reinterpret_cast<const void* const*>(source.ref)!=base+0x16cc0f8)return false;
        static_cast<df::art_image&>(image)=source;
        image.elements.clear();image.properties.clear();image.ref=nullptr;
        for(auto* element:source.elements) {
            failure="missing-element";
            // Negative amounts represent an unspecified group. Native naming
            // uses singular only for1 and prints quantities only from2 upward.
            if(!element)return false;
            const auto* table=*reinterpret_cast<const uint8_t* const*>(element);
            failure="element-dispatch";
            if(table!=base+0x15fdc90 && table!=base+0x15fdf68 && table!=base+0x15fdd10 &&
               table!=base+0x15fdf00 && table!=base+0x15fdbf0)return false;
            failure="element-copy";
            auto* owned=copy(element);if(!owned)return false;image.elements.push_back(owned);
        }
        for(auto* property:source.properties) {
            failure="property";
            if(!property)return false;
            const auto* table=*reinterpret_cast<const uint8_t* const*>(property);
            int subject=-1,object=-1,verb=-1;
            if(table==base+0x15fdde8) {
                const auto* value=static_cast<df::art_image_property_intransitive_verbst*>(property);
                subject=value->subject;verb=value->verb;
            } else if(table==base+0x15fddb0) {
                const auto* value=static_cast<df::art_image_property_transitive_verbst*>(property);
                subject=value->subject;object=value->object;verb=value->verb;
                if(object<0 || size_t(object)>=source.elements.size())return false;
            } else return false;
            if(subject<0 || size_t(subject)>=source.elements.size() || verb<0 || verb>47)return false;
            failure="property-copy";
            auto* owned=copy(property);if(!owned)return false;image.properties.push_back(owned);
        }
        // Native1451c08 explicitly accepts absent references.
        failure="reference-copy";
        if(source.ref){image.ref=copy(source.ref);if(!image.ref)return false;}
        return true;
    }
    df::art_image* get(){return &image;}
};
inline std::optional<EngravingDescription> engravingDescriptionProbe(int x,int y,int z,std::string& failure) {
    failure="selection";
    const auto selected=collect(x,y,z);
    if(!selected)return std::nullopt;
    failure="compatibility";if(!engravingDescriptionReady())return std::nullopt;
    failure="engraving";
    df::engraving* engraving=nullptr;
    for(auto* candidate:df::global::world->event.engravings)
        if(candidate && candidate->pos.x==x && candidate->pos.y==y && candidate->pos.z==z){engraving=candidate;break;}
    if(!engraving || engraving->art_id<0 || engraving->art_subid<0 || engraving->art_subid>=500)return std::nullopt;
    failure="artwork-load";
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    // Native lookup scans the semantic chunk cache before loading saved art.
    // Keep its registered world-owned chunk alive, just as a native read does.
    // This neither populates a sheet nor generates an engraving's missing art.
    using LoadChunk=df::art_image_chunk*(*)(df::art_image_chunk_handlerst*,int32_t);
    auto* chunk=reinterpret_cast<LoadChunk>(base+0x1458b0)(&df::global::world->art_image_chunks,engraving->art_id);
    if(!chunk || !chunk->images[engraving->art_subid].art_image)return std::nullopt;
    EngravingImageContext owned;if(!owned.prepare(*chunk->images[engraving->art_subid].art_image,failure))return std::nullopt;
    auto* image=owned.get();
    df3d_creature::InventoryRandomRestore random(base);
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    EngravingDescription result;
    reinterpret_cast<void(*)(df::language_name*,std::string*)>(base+0xa94030)(&image->name,&result.title);
    if(result.title.empty())result.title="Untitled"; // native1a9e66 immediate literal
    else {
        std::string translated;
        reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&image->name,&translated,true,false);
        result.title+=", \"";result.title+=translated;result.title+='"';
    }
    using Describe=void(*)(df::world*,df::art_image*,std::string*,bool,bool,bool,int32_t,int16_t,int32_t,bool,bool);
    reinterpret_cast<Describe>(base+0x1451b10)(df::global::world,image,&result.description,false,false,true,19,int16_t(engraving->quality),engraving->artist,false,false);
    failure="output-size";
    if(result.title.size()>4096 || result.description.size()>65536)return std::nullopt;
    result.title=DF2UTF(result.title);result.description=DF2UTF(result.description);
    failure.clear();return result;
}
}
