#pragma once
#include <cstring>
#include <memory>
#include "residents_order_native.h"
#include "df/widget_container.h"
#include "df/widget_text.h"

namespace df3d_residents {
struct ActivityText {
    std::string caption,key;
    int16_t foreground=0,background=0;
    bool bright=false;
};

inline bool activitySupported() {
    static const bool ready=[] {
        if(!orderingSupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1425c40,0x1fa4,UINT64_C(0x55e44401bd1cc438)},
            {0xed220,0x82,UINT64_C(0xed480bf398d20fb6)},
            {0x140ff20,0x1ef,UINT64_C(0x2b45435862aab28f)},
            {0xbb680,0x34,UINT64_C(0xa59ab4176fd0d437)},
            {0xbb5c0,0x7d,UINT64_C(0xcb3bb04a949eb0d9)},
            {0x1412c70,0x1ec,UINT64_C(0x647bd270977eba22)},
            {0xefc00,0x2ba,UINT64_C(0x28973d6a2131a70b)},
            {0x3c8650,0x159,UINT64_C(0x39c48a9557706bf8)},
            {0x255e70,0x188,UINT64_C(0x624b7b481f04fd40)},
            {0xd03170,0x12b,UINT64_C(0x90da46373e49508e)},
            {0xd032b0,0x5024,UINT64_C(0xba755d2dfd15322d)},
            {0x13d0800,0x141,UINT64_C(0xca19cb88568ace2d)},
            {0x13cc1d0,0x224,UINT64_C(0xc9ff3ea4503393a7)},
            {0x13d0950,0xe6,UINT64_C(0x563b2943f56fed6d)},
            {0x138ef40,0x307,UINT64_C(0x7b4a15f7c1d361ee)},
            {0x138f620,0x9a4,UINT64_C(0xde9c11c90d78dddc)},
            {0x138ee20,0x111,UINT64_C(0xe642446f7d90deb4)},
            {0x138ffd0,0xd20,UINT64_C(0x904926737b452832)},
            {0xe5d0a0,0x5b,UINT64_C(0x4d75b5473a0eb5f5)},
            {0xe53830,0x33,UINT64_C(0x1287acfd533c3e54)},
            {0xd15ef0,0x1d0,UINT64_C(0x41e934528fc15d5a)},
            {0x14af80,0xf8,UINT64_C(0x14ac0e392f8466f3)},
            {0xf06a0,0xf2,UINT64_C(0x4b6f13296ac6bcb7)},
            {0xf0b80,0xde,UINT64_C(0xb4b9c1e78b760eba)},
            {0xecf00,0x140,UINT64_C(0x3b6bc2f4a3474a09)},
            {0xed040,0x8a,UINT64_C(0xd03e693daf7a6544)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}

// Safe-point diagnostic adapter. The native producer builds an independently
// owned row tree. We never feed, arrange or render it, or invoke its callbacks.
// In particular, displaying_tooltip stays false: native widget destruction's
// global tooltip retirement branch must not run for this temporary tree.
inline std::optional<ActivityText> activityText(df::unit* unit) {
    if(!unit || !df::global::world || !activitySupported())return std::nullopt;
    static_assert(sizeof(df::widget_container)==0x178);
    static_assert(sizeof(std::shared_ptr<df::widget_container>)==16);
    static_assert(sizeof(std::string)==32);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    // Keep allocation, construction and destruction in the native module.
    using Allocate=void* (*)(size_t);
    using Free=void (*)(void*,size_t);
    using Construct=void* (*)(void*);
    using Destroy=void* (*)(void*,unsigned);
    using Produce=std::string (*)(void*,std::shared_ptr<df::widget_container>,df::unit*,bool);
    const auto allocate=reinterpret_cast<Allocate>(const_cast<uint8_t*>(base+0x1539690));
    const auto release=reinterpret_cast<Free>(const_cast<uint8_t*>(base+0x1539680));
    const auto construct=reinterpret_cast<Construct>(const_cast<uint8_t*>(base+0xed220));
    const auto destroy=reinterpret_cast<Destroy>(const_cast<uint8_t*>(base+0xbb680));
    const auto produce=reinterpret_cast<Produce>(const_cast<uint8_t*>(base+0x1425c40));
    void* storage=allocate(sizeof(df::widget_container));
    std::memset(storage,0,sizeof(df::widget_container));
    try {construct(storage);} catch(...) {release(storage,sizeof(df::widget_container));throw;}
    std::shared_ptr<df::widget_container> row(static_cast<df::widget_container*>(storage),
        [destroy](df::widget_container* value){destroy(value,1);});
    // The list pointer is only captured by deferred button callbacks. Passing
    // null prevents accidental borrowing of a native menu. The actual by-value
    // shared_ptr ABI gives the callee its own reference to consume.
    ActivityText result;result.key=produce(nullptr,row,unit,true);
    const auto found=row->children_by_name.find("Job");
    if(found==row->children_by_name.end())return std::nullopt;
    const auto* job=static_cast<const df::widget_container*>(found->second.get());
    if(job->children.empty())return std::nullopt;
    // 1425da7 creates the first child using the native truncated-text factory.
    const auto* text=static_cast<const df::widget_text*>(job->children.front().get());
    result.caption=text->str;result.foreground=text->fg;result.background=text->bg;result.bright=text->bright;
    return result;
}
}
