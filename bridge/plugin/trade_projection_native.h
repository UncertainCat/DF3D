#pragma once
#include "trade_goods_native.h"
#include "df/general_ref.h"
#include <algorithm>

namespace df3d_production {
struct TradeProjectedGroup {int32_t type=-1,subtype=-1;bool expanded=false,on=false;uint32_t flags=0;};
enum class TradeDraftAction {Item,Group,MarkAll,UnmarkAll,ExpandGroup,ExpandContainer,Filter};
struct TradeSelectionIntent {int32_t side=-1,item=-1;TradeDraftAction action=TradeDraftAction::Item;int32_t type=-1,subtype=-1;std::string query;};
struct TradeProjectedSide {
    std::vector<int32_t> items,amounts;
    std::vector<uint8_t> flags;
    std::vector<TradeProjectedGroup> groups;
    int32_t height=0;
};
// Server-owned selection state only; never accept these derived flags from a
// client as action authority. Session identity/source revision belong to the
// caller. Negotiation/counteroffer state is deliberately not represented yet.
struct TradeDraftCheckpoint {
    std::array<TradeProjectedSide,2> sides;
    std::array<std::string,2> filters;
};
// Native draft storage is independently owned. Construct and use it within one
// safe-point operation: item pointers must not survive a simulation advance.
// A persistent public session must revalidate identities/source before use.
// Native helpers own filtering, group flags, selection and height calculations.
inline bool tradeProjectionNativeReady() {
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x385007,0x595,UINT64_C(0x352b23e04118d802)},
            {0x37c780,0x5cc,UINT64_C(0xbb97b0e36dee07ec)},
            {0x37d750,0x263,UINT64_C(0x7c5835146ecefb8c)},
            {0x37acc0,0x1ea,UINT64_C(0x02b0383285e5f9ff)},
            {0x36a840,0x17b,UINT64_C(0xe74fe58ae7b5234c)},
            {0x316aeb,0x1277,UINT64_C(0xfb5f763c9e669383)},
            {0xc65450,0xaba,UINT64_C(0x47fa672b7bbcd332)},
            {0xa82c10,0x56ec,UINT64_C(0x66347214dfd39a0b)},
            {0x52cee0,0x19e,UINT64_C(0xc25c2d8a6eb9fcac)},
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}if(hash!=pin.hash)return false;}
        return true;
    }();return ready;
}
class TradeDraftNative {
    friend class TradeNegotiationNative;
    df::trade_interfacest owned{};
    bool valid=false;
public:
    TradeDraftNative(const TradeDraftNative&)=delete;
    TradeDraftNative& operator=(const TradeDraftNative&)=delete;
    explicit TradeDraftNative(df::building* building,size_t caravanIndex) {
        const auto sources=tradeGoodsSources(building,caravanIndex);
        if(!sources || !tradeProjectionNativeReady())return;
        static_assert(offsetof(df::trade_interfacest,good)==0xe0);
        static_assert(offsetof(df::trade_interfacest,current_type_a_type)==0x218);
        static_assert(offsetof(df::trade_interfacest,current_type_a_on)==0x2b8);
        static_assert(offsetof(df::trade_interfacest,item_filter)==0x338);
        for(size_t side=0;side<2;++side) {
            auto& goods=owned.good[side];auto& flags=owned.goodflag[side];auto& amounts=owned.good_amount[side];
            auto& types=owned.master_type_a_type[side];auto& subtypes=owned.master_type_a_subtype[side];
            for(auto id:(*sources)[side]) {
                auto* item=df::item::find(id);if(!item)return;
                goods.push_back(item);
                const auto type=int32_t(item->getType()),subtype=int32_t(item->getSubtype());
                if(types.empty() || types.back()!=type || subtypes.back()!=subtype){types.push_back(type);subtypes.push_back(subtype);}
            }
            flags.resize(goods.size());amounts.resize(goods.size(),0);
            owned.master_type_a_expanded[side].assign(types.size(),true);
            owned.current_type_a_type[side]=types;owned.current_type_a_subtype[side]=subtypes;
            owned.current_type_a_expanded[side]=owned.master_type_a_expanded[side];
            owned.current_type_a_on[side].assign(types.size(),false);
            owned.current_type_a_flag[side].resize(types.size());
            // Native inserts each bin child at parent+1, preserving its reversal of
            // reference order. Other container types are not expanded here.
            for(size_t i=0;i<goods.size();++i) {
                auto* item=goods[i];if(item->getType()!=df::item_type::BIN)continue;
                if(item->general_refs.size()>1048576)return;
                for(auto* ref:item->general_refs) {
                    if(!ref)return;
                    if(ref->getType()!=df::general_ref_type::CONTAINS_ITEM)continue;
                    auto* child=ref->getItem();if(!child)continue;
                    if(child->id<0 || goods.size()>=1048576)return;
                    goods.insert(goods.begin()+i+1,child);
                    flags.insert(flags.begin()+i+1,df::trade_interface_good_flag(2));
                    amounts.insert(amounts.begin()+i+1,0);
                }
            }
        }
        valid=true;
        for(int32_t side=0;side<2;++side)setFilter(side,{});
    }
    explicit operator bool() const {return valid;}
    std::optional<TradeDraftCheckpoint> checkpoint() const {
        const auto sides=snapshot();if(!sides || owned.counter_offer || !owned.counter_offer_item.empty())return {};
        return TradeDraftCheckpoint{*sides,owned.item_filter};
    }
    // Restore into freshly resolved storage, never retain pointers across DF
    // frames. The owner must also validate caravan/trader/epoch and source
    // revision: matching list shape alone is not sufficient action authority.
    bool restore(const TradeDraftCheckpoint& saved) {
        if(!valid || owned.counter_offer || !owned.counter_offer_item.empty())return false;
        for(size_t side=0;side<2;++side) {
            const auto& value=saved.sides[side];const auto& goods=owned.good[side];
            if(saved.filters[side].size()>512 || value.height<0 || value.items.size()!=goods.size() ||
               value.flags.size()!=goods.size() || value.amounts.size()!=goods.size() ||
               value.groups.size()!=owned.current_type_a_type[side].size())return false;
            for(size_t i=0;i<goods.size();++i)if(value.items[i]!=goods[i]->id || value.amounts[i]!=0 ||
                (value.flags[i]&~uint8_t(15)) || (value.flags[i]&2)!=(owned.goodflag[side][i].whole&2))return false;
            for(size_t i=0;i<value.groups.size();++i)if(value.groups[i].type!=owned.current_type_a_type[side][i] ||
                value.groups[i].subtype!=owned.current_type_a_subtype[side][i] || (value.groups[i].flags&~uint32_t(3)))return false;
        }
        // Validate both sides before altering the owned draft. Preserve native
        // derived flags exactly: expansion intentionally does not refresh them.
        for(size_t side=0;side<2;++side) {
            const auto& value=saved.sides[side];owned.item_filter[side]=saved.filters[side];
            owned.i_height[side]=value.height;owned.good_amount[side]=value.amounts;
            for(size_t i=0;i<value.items.size();++i)owned.goodflag[side][i].whole=value.flags[i];
            for(size_t i=0;i<value.groups.size();++i) {
                owned.current_type_a_expanded[side][i]=value.groups[i].expanded;
                owned.current_type_a_on[side][i]=value.groups[i].on;
                owned.current_type_a_flag[side][i].whole=value.groups[i].flags;
            }
        }
        return true;
    }
    bool setFilter(int32_t side,const std::string& query) {
        if(!valid || side<0 || side>1 || query.size()>512)return false;
        const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        owned.item_filter[side]=query;
        using Project=void(*)(df::trade_interfacest*,int32_t);
        reinterpret_cast<Project>(base+0x37c780)(&owned,side);
        reinterpret_cast<Project>(base+0x37acc0)(&owned,side);
        return true;
    }
    bool apply(const TradeSelectionIntent& intent) {
        if(!valid || intent.side<0 || intent.side>1)return false;
        if(intent.action==TradeDraftAction::Filter)return setFilter(intent.side,intent.query);
        const auto side=intent.side;
        auto& goods=owned.good[side];auto& flags=owned.goodflag[side];
        const auto& types=owned.current_type_a_type[side];const auto& subtypes=owned.current_type_a_subtype[side];
        const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        using Project=void(*)(df::trade_interfacest*,int32_t);
        using Toggle=void(*)(df::trade_interfacest*,int32_t,int32_t,int32_t,bool);
        const auto toggle=[&](size_t i){reinterpret_cast<Toggle>(base+0x36a840)(&owned,side,int32_t(i),0,false);};
        if(intent.action==TradeDraftAction::Item || intent.action==TradeDraftAction::ExpandContainer) {
            auto found=std::find_if(goods.begin(),goods.end(),[&](const auto* item){return item->id==intent.item;});
            if(found==goods.end())return false;
            const auto index=size_t(found-goods.begin());
            if(intent.action==TradeDraftAction::ExpandContainer) {
                if((*found)->getType()!=df::item_type::BIN || flags[index].bits.contained)return false;
                flags[index].whole^=4;
            }else toggle(index);
        } else if(intent.action==TradeDraftAction::MarkAll || intent.action==TradeDraftAction::UnmarkAll) {
            // Native buttons scan the whole side, including hidden groups.
            const bool selected=intent.action==TradeDraftAction::MarkAll;
            for(size_t i=0;i<goods.size();++i)if(bool(flags[i].bits.selected)!=selected)toggle(i);
        } else if(intent.action==TradeDraftAction::Group || intent.action==TradeDraftAction::ExpandGroup) {
            size_t group=0;while(group<types.size() && (types[group]!=intent.type || subtypes[group]!=intent.subtype))++group;
            if(group==types.size())return false;
            if(intent.action==TradeDraftAction::ExpandGroup)owned.current_type_a_expanded[side][group]=!owned.current_type_a_expanded[side][group];
            else {
                const auto state=owned.current_type_a_flag[side][group];
                for(size_t i=0;i<goods.size();++i)if(!flags[i].bits.contained &&
                    int32_t(goods[i]->getType())==intent.type && int32_t(goods[i]->getSubtype())==intent.subtype &&
                    (state.bits.all_selected || (state.bits.can_do_select && !flags[i].bits.selected)))toggle(i);
            }
        } else return false;
        // Native expansion changes height only; do not incidentally refresh
        // group selection flags. Selection actions explicitly refresh them.
        if(intent.action!=TradeDraftAction::ExpandGroup && intent.action!=TradeDraftAction::ExpandContainer)
            reinterpret_cast<Project>(base+0x37d750)(&owned,int32_t(side));
        reinterpret_cast<Project>(base+0x37acc0)(&owned,side);
        return true;
    }
    std::optional<std::array<TradeProjectedSide,2>> snapshot() const {
        if(!valid)return {};
        std::array<TradeProjectedSide,2> result;
        for(size_t side=0;side<2;++side) {
            auto& projected=result[side];projected.height=owned.i_height[side];projected.amounts=owned.good_amount[side];
            const auto& goods=owned.good[side];const auto& flags=owned.goodflag[side];
            const auto& types=owned.current_type_a_type[side];const auto& subtypes=owned.current_type_a_subtype[side];
            for(size_t i=0;i<goods.size();++i){projected.items.push_back(goods[i]->id);projected.flags.push_back(flags[i].whole);}
            for(size_t i=0;i<types.size();++i)projected.groups.push_back({types[i],subtypes[i],owned.current_type_a_expanded[side][i],owned.current_type_a_on[side][i],owned.current_type_a_flag[side][i].whole});
        }
        return result;
    }
};
// Compatibility adapter for stateless providers. Initialization remains the
// renderer's inline385007..38559c construction; no renderer or appraisal call.
inline std::optional<std::array<TradeProjectedSide,2>> tradeProjection(
    df::building* building,size_t caravanIndex,const std::array<std::string,2>& filters={},
    const std::vector<TradeSelectionIntent>& selections={}) {
    if(filters[0].size()>512 || filters[1].size()>512 || selections.size()>4096)return {};
    TradeDraftNative draft(building,caravanIndex);if(!draft)return {};
    for(int32_t side=0;side<2;++side)if(!draft.setFilter(side,filters[side]))return {};
    for(const auto& intent:selections)if(!draft.apply(intent))return {};
    return draft.snapshot();
}
}
