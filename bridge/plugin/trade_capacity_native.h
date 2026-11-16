#pragma once
#include "trade_projection_native.h"
#include "df/massst.h"
#include <cstring>

namespace df3d_production {
struct TradeCapacity {int32_t whole=0,fraction=0,color=7;bool excess=false;std::string caption;};
// Native38819a..389076 accumulates remaining capacity inline, with global-menu
// reads in some branches. Never invoke that block. Feed the same whole-item
// ownership adjustments to native mass helpers using independent projected rows.
inline std::optional<TradeCapacity> tradeCapacity(df::building* building,size_t caravanIndex,
    const std::array<TradeProjectedSide,2>& projected) {
    if(!tradeEntryFacts(building,caravanIndex))return {};
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x38819a,0xedc,UINT64_C(0xbdb1816dc17646d1)},
            {0x30cb20,0x29,UINT64_C(0xb786d1034c9246c7)},
            {0x30cb50,0x29,UINT64_C(0x9ecea42502e5f347)},
            {0x30c700,0x86,UINT64_C(0x400d19f1916f26cd)},
            {0x7754d0,0x47,UINT64_C(0xc09925c3c2dce604)},
            {0xc65f10,0x106,UINT64_C(0x440442082189ed12)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);const auto* bytes=reinterpret_cast<const uint8_t*>(base+pin.rva);for(size_t i=0;i<pin.length;++i){hash^=bytes[i];hash*=UINT64_C(1099511628211);}if(hash!=pin.hash)return false;}
        return std::memcmp(reinterpret_cast<const void*>(base+0x162b298),"Allowed Weight: ",16)==0 &&
            std::memcmp(reinterpret_cast<const void*>(base+0x162b288),"Excess Weight: ",15)==0;
    }();if(!ready)return {};
    auto mass=df::global::plotinfo->caravans[caravanIndex]->total_capacity;
    const auto add=[&](df::item* item,bool positive) {
        // These may lazily refresh semantic item/contents weight caches.
        const auto fraction=reinterpret_cast<int32_t(*)(df::item*)>(base+0x30cb50)(item);
        const auto whole=reinterpret_cast<int32_t(*)(df::item*)>(base+0x30cb20)(item);
        if(!positive && (whole==INT32_MIN || fraction==INT32_MIN))return false;
        reinterpret_cast<void(*)(df::massst*,int32_t,int32_t)>(base+0x30c700)(&mass,positive?whole:-whole,positive?fraction:-fraction);
        return true;
    };
    for(size_t side=0;side<2;++side) {
        const auto& rows=projected[side];if(rows.items.size()!=rows.flags.size() || rows.items.size()!=rows.amounts.size())return {};
        std::vector<df::item*> items;items.reserve(rows.items.size());
        for(size_t i=0;i<rows.items.size();++i){if(rows.amounts[i]!=0)return {};auto* item=df::item::find(rows.items[i]);if(!item)return {};items.push_back(item);}
        const auto retained=[&](size_t index){const bool selected=(rows.flags[index]&1)!=0;return side==0?!selected:selected;};
        for(size_t i=0;i<items.size();++i) {
            auto* item=items[i];if(item->general_refs.size()>1048576)return {};
            bool contained=false;
            for(auto* ref:item->general_refs){if(!ref)return {};if(ref->getType()==df::general_ref_type::CONTAINED_IN_ITEM)contained=true;}
            if(contained)continue;
            const bool parentRetained=retained(i);
            if(parentRetained && !add(item,false))return {};
            if(item->getType()!=df::item_type::BIN)continue;
            for(auto* ref:item->general_refs)if(ref->getType()==df::general_ref_type::CONTAINS_ITEM) {
                const auto childId=ref->getID();
                for(size_t child=0;child<items.size();++child)if(items[child]->id==childId && retained(child)!=parentRetained)
                    if(!add(items[child],parentRetained))return {};
            }
        }
    }
    TradeCapacity result;result.whole=mass.whole;result.fraction=mass.fraction;result.excess=mass.whole<0;result.color=result.excess?4:7;
    if(mass.whole==INT32_MIN)return {};
    if(result.excess)mass.whole=-mass.whole; // Native display negates whole only.
    std::string value;reinterpret_cast<void(*)(df::massst*,std::string*)>(base+0x7754d0)(&mass,&value);
    result.caption=reinterpret_cast<const char*>(base+(result.excess?0x162b288:0x162b298));result.caption+=value;
    if(result.caption.size()>512)return {};
    return result;
}
}
