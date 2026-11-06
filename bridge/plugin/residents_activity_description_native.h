#pragma once
#include "residents_activity_native.h"
#include "knowledge_detail_native.h"
#include "df/activity_event.h"
#include "df/markup_text_boxst.h"
#include "df/markup_text_wordst.h"
#include "df/markup_text_linkst.h"

namespace df3d_residents {
struct ActivityDescriptionWord {
    std::string text;
    uint8_t red=0,green=0,blue=0;
    int32_t link=-1;
    uint32_t flags=0;
    int32_t x=-1,y=-1;
};
struct ActivityDescriptionLink {int32_t type=-1,id=-1,subid=-1;};
struct ActivityDescription {
    int32_t activityId=-1,eventId=-1,eventType=-1;
    int32_t columns=-1,maxY=0;
    std::vector<ActivityDescriptionWord> words;
    std::vector<ActivityDescriptionLink> links;
};

inline bool activityDescriptionSupported() {
    static const bool ready=[] {
        if(!activitySupported() || !df3d_creature::knowledgeDescriptionReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x26b800,0x205c,UINT64_C(0xc00212548287b163)},
            {0xd51eb0,0x2626,UINT64_C(0xbc86b2cda638fc04)},
            {0xd544e0,0x127,UINT64_C(0x36adbc5cd57ef939)},
            {0xe37d0,0xa8,UINT64_C(0xe980a54cde994535)},
            {0xe610e0,0x73,UINT64_C(0x645a0692ae800d0b)},
            {0xd51c80,0x22b,UINT64_C(0x5793dc6c0895227b)},
        };
        for(const auto& pin:pins){
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}
            if(h!=pin.hash)return false;
        }
        return true;
    }();return ready;
}

// Staged semantic reader; broader event families still need native acceptance
// before the Residents page is exposed.
// The actual menu handlers1427f70/14287c0 must never be used: they clear live
// markup and create/activate native widgets.26b800 accepts separate output.
inline df::activity_event* activityDescriptionEvent(df::unit* unit) {
    if(!unit || !df::global::world || !activityDescriptionSupported() || unit->job.current_job)return nullptr;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    using Event=df::activity_event* (*)(df::unit*);
    // Same native readers and precedence as1426ba6..1426be3/14277b5.
    auto* source=reinterpret_cast<Event>(base+0x13d0800)(unit);
    if(!source){
        if(reinterpret_cast<void*(*)(df::unit*)>(base+0x13cc1d0)(unit))return nullptr;
        source=reinterpret_cast<Event>(base+0x13d0950)(unit);
    }
    return source;
}
struct ActivityTarget {int32_t activityId=-1,eventId=-1;};
inline std::optional<ActivityTarget> activityDescriptionTarget(df::unit* unit) {
    const auto* event=activityDescriptionEvent(unit);
    if(!event || event->activity_id<0 || event->event_id<0)return std::nullopt;
    return ActivityTarget{event->activity_id,event->event_id};
}
inline std::optional<ActivityDescription> activityDescription(df::unit* unit,int32_t columns=0,int32_t expectedActivity=-1,int32_t expectedEvent=-1) {
    if(columns<0 || columns>1024)return std::nullopt;
    auto* source=activityDescriptionEvent(unit);if(!source)return std::nullopt;
    if((expectedActivity>=0 && source->activity_id!=expectedActivity) || (expectedEvent>=0 && source->event_id!=expectedEvent))return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto* identity=DFHack::virtual_identity::get(source);
    if(!identity || !identity->can_instantiate())return std::nullopt;
    auto* empty=static_cast<df::activity_event*>(identity->instantiate());
    if(!empty)return std::nullopt;
    const auto destroyEmpty=[identity](df::activity_event* value){identity->destroy(value);};
    std::unique_ptr<df::activity_event,decltype(destroyEmpty)> emptyOwner(empty,destroyEmpty);
    auto* copy=static_cast<df::activity_event*>(identity->instantiate());
    if(!copy)return std::nullopt;
    // Generated assignment owns value/vector backing storage, but event
    // item/building references are shallow, read-only simulation references.
    // Restore the empty value before native virtual destruction so it cannot
    // delete referenced world records. Declaration order keeps empty alive.
    const auto destroy=[identity,empty](df::activity_event* value){identity->copy(value,empty);identity->destroy(value);};
    std::unique_ptr<df::activity_event,decltype(destroy)> owned(copy,destroy);
    if(!identity->copy(copy,source))return std::nullopt;

    static_assert(sizeof(df::markup_text_boxst)==0x40);
    static_assert(sizeof(df::markup_text_wordst)==0x38);
    static_assert(sizeof(df::markup_text_linkst)==0xc);
    df::markup_text_boxst box;
    box.current_width=-1;box.max_y=0;box.environment=nullptr;
    struct Cleanup {
        df::markup_text_boxst& box;uint8_t* base;
        ~Cleanup(){reinterpret_cast<void(*)(df::markup_text_boxst*)>(base+0xe37d0)(&box);}
    } cleanup{box,base};
    // Numeric [C:f:b:bright] markup changes only the current pen bytes at
    // gps+0x8c. Restore them even on exceptions. The palette is read-only.
    // A null owned script environment prevents markup script evaluation.
    struct PenRestore {
        uint8_t* pen;std::array<uint8_t,4> saved;
        explicit PenRestore(uint8_t* p):pen(p){std::memcpy(saved.data(),pen,saved.size());}
        ~PenRestore(){std::memcpy(pen,saved.data(),saved.size());}
    } pen(base+0x264a47c);
    df3d_creature::InventoryRandomRestore random(base);
    df3d_creature::KnowledgeMaterialCacheRestore materials(df::global::world->raws.creatures.hist_fig_to_creature_map);
    // The receiver is unused by26b800. Deliberately pass null rather than a
    // borrowed viewunit_interfacest. Event names and bodies come entirely from DF.
    reinterpret_cast<void(*)(void*,df::activity_event*,int32_t,df::markup_text_boxst*)>(base+0x26b800)(nullptr,copy,unit->id,&box);
    if(box.word.size()>16384 || box.link.size()>4096)return std::nullopt;
    // Direct semantic word layout: no widget arrangement, rendering or globals.
    if(columns)reinterpret_cast<void(*)(df::markup_text_boxst*,int32_t)>(base+0xd51c80)(&box,columns);
    ActivityDescription result;
    result.activityId=copy->activity_id;result.eventId=copy->event_id;result.eventType=static_cast<int32_t>(copy->getType());
    result.columns=box.current_width;result.maxY=box.max_y;
    size_t bytes=0;
    for(const auto* word:box.word){
        if(!word || word->flags.whole>7 || word->str.size()>131072-bytes)return std::nullopt;
        bytes+=word->str.size();
        if(word->link_index < -1 || (word->link_index>=0 && static_cast<size_t>(word->link_index)>=box.link.size()))return std::nullopt;
        result.words.push_back({word->str,word->red,word->green,word->blue,word->link_index,word->flags.whole,word->px,word->py});
    }
    for(const auto* link:box.link){
        if(!link)return std::nullopt;
        result.links.push_back({static_cast<int32_t>(link->type),link->id,link->subid});
    }
    return result;
}
}
