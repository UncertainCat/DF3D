#pragma once
#include "trade_row_values_native.h"

namespace df3d_production {
enum class TradeItemDisposition {Local,Imported,ExportRestricted,Stolen,Offered};
struct TradeDisplayRow {
    bool group=false,expanded=false;
    int32_t id=-1,parent=-1,type=-1,subtype=-1,amount=0;
    uint32_t flags=0;
    TradeItemDisposition disposition=TradeItemDisposition::Local;
    int32_t containedCount=0;bool expandable=false;
    std::string caption,contentsCaption;
    std::optional<TradeRowValue> valuation;
};
struct TradeDisplayPage {size_t offset=0,total=0;std::vector<TradeDisplayRow> rows;};
inline bool tradeDisplayFactsReady(){
    if(!tradeProjectionNativeReady())return false;
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x387518,0x75,UINT64_C(0xc10acc2ca7f61bd7)},
            {0x387b3c,0x18,UINT64_C(0xd6864fd3eaa8dc42)},
            {0x37acc0,0x1ea,UINT64_C(0x02b0383285e5f9ff)},
            {0x52c130,0xb3,UINT64_C(0xf2e358ad54df1c09)},
            {0xcb2210,0x65,UINT64_C(0xf276e92e9197e8b2)},
            {0x387a20,0xf2,UINT64_C(0xf117a2856c04cae3)},
            {0x387c0e,0x131,UINT64_C(0xe4f1925e98881e3c)}};
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);const auto* bytes=reinterpret_cast<const uint8_t*>(base+pin.rva);for(size_t i=0;i<pin.length;++i){h^=bytes[i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();return ready;
}
// Shared native item-row facts for ordinary goods and counteroffer rows.
inline bool tradeDisplayItemFacts(df::item* item,int32_t side,uint8_t flag,TradeDisplayRow& row){
    if(!item || side<0 || side>1)return false;
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    reinterpret_cast<void(*)(df::item*,std::string*,bool,int32_t)>(base+0xc65450)(item,&row.caption,false,-1);
    if(row.caption.size()>16384)return false;
    // Native row status priority387a20..387b0d; only the fortress
    // side consults the native export-mandate predicate cb2210.
    bool offered=false,stolen=false;
    if(item->general_refs.size()>1048576)return false;
    for(auto* ref:item->general_refs){if(!ref)return false;
        offered|=ref->getType()==df::general_ref_type::ENTITY_OFFERED;
        stolen|=ref->getType()==df::general_ref_type::ENTITY_STOLEN;
        if(item->flags.bits.container && ref->getType()==df::general_ref_type::CONTAINS_ITEM && ref->getItem())++row.containedCount;
    }
    const bool restricted=side==1 && reinterpret_cast<bool(*)(df::item*)>(base+0xcb2210)(item);
    row.disposition=offered?TradeItemDisposition::Offered:stolen?TradeItemDisposition::Stolen:restricted?TradeItemDisposition::ExportRestricted:item->flags.bits.foreign?TradeItemDisposition::Imported:TradeItemDisposition::Local;
    row.expandable=item->getType()==df::item_type::BIN && !(flag&2);
    if(row.containedCount>0){
        row.contentsCaption=reinterpret_cast<const char*>(base+0x161bb50);
        reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c130)(row.containedCount,&row.contentsCaption);
        row.contentsCaption+=reinterpret_cast<const char*>(base+0x15f71ec);
        if(row.containedCount!=1)row.contentsCaption+=reinterpret_cast<const char*>(base+0x15e9298);
        if(row.contentsCaption.size()>512)return false;
    }
    return true;
}
// Server-owned projection only. The session owner validates source and revision
// before calling this at the same safe point. Native37acc0 supplies visibility:
// visible group, its expansion, then matching top-level items and open children.
// filtered_off affects row appearance, not membership within a visible group.
inline std::optional<TradeDisplayPage> tradeDisplayPage(df::building* building,size_t caravanIndex,
    const TradeProjectedSide& projected,size_t offset,size_t limit,int32_t side) {
    if(side<0 || side>1 || !limit || limit>64 || !tradeProjectionNativeReady() || projected.items.size()!=projected.flags.size() || projected.items.size()!=projected.amounts.size())return {};
    if(!tradeDisplayFactsReady())return {};
    TradeDisplayPage result;result.offset=offset;
    std::vector<df::item*> items;items.reserve(projected.items.size());
    for(auto id:projected.items){auto* item=df::item::find(id);if(!item)return {};items.push_back(item);}
    const auto wanted=[&] {const auto index=result.total++;return index>=offset && result.rows.size()<limit;};
    if(!items.empty())for(const auto& group:projected.groups) {
        if(!group.on)continue;
        if(wanted()) {
            if(group.type<0 || group.type>=93 || group.subtype<-1 || group.subtype>INT16_MAX)return {};
            auto caption=depotGroupCaption(int16_t(group.type),int16_t(group.subtype));if(!caption || caption->size()>16384)return {};
            TradeDisplayRow row;row.group=true;row.type=group.type;row.subtype=group.subtype;row.flags=group.flags;row.expanded=group.expanded;row.caption=std::move(*caption);result.rows.push_back(std::move(row));
        }
        if(!group.expanded)continue;
        bool children=true;int32_t parent=-1;
        for(size_t i=0;i<items.size();++i) {
            const auto flag=projected.flags[i];auto* item=items[i];bool visible;
            if(flag&2)visible=children;
            else {visible=int(item->getType())==group.type && item->getSubtype()==group.subtype;children=visible && !(flag&4);parent=visible?item->id:-1;}
            if(!visible || !wanted())continue;
            TradeDisplayRow row;row.id=item->id;row.parent=(flag&2)?parent:-1;row.type=int(item->getType());row.subtype=item->getSubtype();row.flags=flag;row.amount=projected.amounts[i];row.expanded=!(flag&4);
            if(!tradeDisplayItemFacts(item,side,flag,row))return {};
            result.rows.push_back(std::move(row));
        }
    }
    if(offset>result.total || projected.height<0 || size_t(projected.height)!=result.total*3)return {};
    std::vector<int32_t> ids;for(const auto& row:result.rows)if(!row.group)ids.push_back(row.id);
    const auto values=tradeRowValuesForItems(building,caravanIndex,ids);if(!values)return {};
    size_t index=0;for(auto& row:result.rows)if(!row.group)row.valuation=(*values)[index++];
    return result;
}
}
