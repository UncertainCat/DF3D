#pragma once
#include "depot_goods_native.h"
#include "knowledge_detail_native.h"
#include "df/general_ref.h"
#include "df/general_ref_type.h"
#include <array>

namespace df3d_production {
// The category initializer and filter contain inline projection logic around
// native description/matching leaves. Never call their menu/geometry tails.
inline std::optional<std::vector<int16_t>> depotCategories(const DepotGoods& goods,
    std::string query,bool excludeProhibited=false) {
    if(!depotNativeReady() || !df::global::world || query.size()>512 ||
       goods.rows.size()>1048576 || goods.groups.size()>1048576)return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x36c9b8,0x3c1,UINT64_C(0xa7435a45e62032db)},
            {0x37ba00,0x665,UINT64_C(0xce207173b65aeff8)},
            {0xc65450,0xaba,UINT64_C(0x47fa672b7bbcd332)},
            {0xa82c10,0x56ec,UINT64_C(0x66347214dfd39a0b)},
            {0x52cee0,0x19e,UINT64_C(0xc25c2d8a6eb9fcac)},
            {0xe1990,0xc7,UINT64_C(0x1c45e5635f4ffde2)}};
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();
    if(!ready)return {};
    df3d_creature::KnowledgeMaterialCacheRestore restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    using Describe=void(*)(std::string*,int16_t,int16_t,int16_t,int32_t,int32_t,int32_t,bool,void*,int32_t,int32_t,bool,int32_t,int32_t);
    const auto describe=reinterpret_cast<Describe>(base+0xa82c10);
    const auto normalize=reinterpret_cast<void(*)(std::string*)>(base+0x52cee0);
    normalize(&query);
    const auto matches=[&](std::string caption){normalize(&caption);
        return reinterpret_cast<size_t(*)(const char*,size_t,size_t,const char*,size_t)>(base+0xe1990)
            (caption.data(),caption.size(),0,query.data(),query.size())!=size_t(-1);};
    const auto itemMatches=[&](df::item* item){std::string caption;
        reinterpret_cast<void(*)(df::item*,std::string*,bool,int32_t)>(base+0xc65450)(item,&caption,false,-1);
        return matches(std::move(caption));};
    std::array<bool,93> present{},eligible{},matched{};
    for(const auto& group:goods.groups){if(group.type<0 || group.type>=93)return {};present[group.type]=true;}
    for(const auto& row:goods.rows){
        if(excludeProhibited && row.prohibited)continue;
        auto* item=df::item::find(row.id);if(!item)return {};
        const auto type=int(item->getType());if(type<0 || type>=93)return {};
        eligible[type]=true;
        if(query.empty())continue;
        if(itemMatches(item))matched[type]=true;
        if(item->flags.bits.container){
            if(item->general_refs.size()>1048576)return {};
            for(auto* ref:item->general_refs){if(!ref)return {};
                if(ref->getType()==df::general_ref_type::CONTAINS_ITEM)
                    if(auto* child=ref->getItem())if(itemMatches(child))matched[type]=true;
            }
        }
    }
    if(!query.empty())for(const auto& group:goods.groups)if(eligible[group.type]){
        std::string caption;describe(&caption,group.type,group.subtype,group.subcat1,group.subcat2,group.amount,0,false,nullptr,-1,-1,true,0,0);
        if(matches(std::move(caption)))matched[group.type]=true;
    }
    std::array<std::string,93> captions;
    std::vector<int16_t> result;
    // Native first deduplicates types numerically, then inserts before equal names.
    for(int16_t type=0;type<93;++type)if(present[type]){
        describe(&captions[type],type,-1,-1,-1,-1,0,false,nullptr,-1,-1,true,0,0);
        normalize(&captions[type]);
        auto at=result.begin();while(at!=result.end() && captions[*at].compare(captions[type])<0)++at;
        result.insert(at,type);
    }
    result.erase(std::remove_if(result.begin(),result.end(),[&](int16_t type){return !(query.empty()?eligible[type]:matched[type]);}),result.end());
    return result;
}
struct DepotSelectedGroup {DepotGoodsGroup group;bool matches=false;uint32_t flags=0;};
struct DepotSelection {std::vector<int32_t> ids;std::vector<DepotSelectedGroup> groups;};
// Native37a0a0 selects/sorts a category,37cd50 searches owned group/item names,
//37d9c0 aggregates selection flags. None reads the global picker or window size.
// Do not substitute37ba00: its category-list scroll tail reads native geometry.
inline std::optional<DepotSelection> depotSelection(const DepotGoods& goods,int16_t type,
    std::string query,bool sortByDistance=true,bool pendingOnTop=true,bool excludeProhibited=false) {
    if(!depotNativeReady() || !df::global::world || type<0 || type>=93 || query.size()>512 ||
       goods.rows.size()>1048576 || goods.groups.size()>1048576)return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x37a060,0x40,UINT64_C(0x1f410ab43494a2fd)},
            {0x37a0a0,0x348,UINT64_C(0x69e51b5a2ce37ce6)},
            {0x37cd50,0x5f9,UINT64_C(0x16933f93fc2b62f5)},
            {0x37aeb0,0x1d4,UINT64_C(0x28424ba77803a9c7)},
            {0x37d9c0,0x200,UINT64_C(0x196754683223bd32)},
            {0xa82c10,0x56ec,UINT64_C(0x66347214dfd39a0b)},
            {0x52cee0,0x19e,UINT64_C(0xc25c2d8a6eb9fcac)},
            {0xe1990,0xc7,UINT64_C(0x1c45e5635f4ffde2)}};
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();
    if(!ready)return {};
    std::vector<df::tradegoodslistst> records(goods.rows.size());
    df::assign_trade_interfacest owned;owned.current_type=df::item_type(type);owned.item_filter=std::move(query);
    owned.sort_by_distance=sortByDistance;owned.pending_on_top=pendingOnTop;owned.exclude_prohib=excludeProhibited;
    static_assert(offsetof(df::assign_trade_interfacest,current_type_tgi)==0x160);
    static_assert(offsetof(df::assign_trade_interfacest,current_type_a_flag)==0x218);
    for(size_t i=0;i<records.size();++i){const auto& row=goods.rows[i];auto& record=records[i];
        record.it=df::item::find(row.id);if(!record.it)return {};
        record.dist=row.distance;record.tag=row.tag;record.value=row.value;record.prohibited=row.prohibited;
        owned.master_i_list.tgi.push_back(&record);
    }
    for(const auto& group:goods.groups){
        owned.master_a_list.type.push_back(group.type);owned.master_a_list.subtype.push_back(group.subtype);
        owned.master_a_list.subcat1.push_back(group.subcat1);owned.master_a_list.subcat2.push_back(group.subcat2);
        owned.master_a_list.amount.push_back(group.amount);owned.master_a_list.expanded.push_back(group.expanded);
    }
    df3d_creature::KnowledgeMaterialCacheRestore restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    reinterpret_cast<void (*)(df::assign_trade_interfacest*)>(base+0x37a0a0)(&owned);
    DepotSelection result;
    for(auto* row:owned.current_type_tgi)result.ids.push_back(row->it->id);
    const auto count=owned.current_type_a_subtype.size();
    if(owned.current_type_a_subcat1.size()!=count || owned.current_type_a_subcat2.size()!=count ||
       owned.current_type_a_amount.size()!=count || owned.current_type_a_expanded.size()!=count ||
       owned.current_type_a_on.size()!=count || owned.current_type_a_flag.size()!=count)return {};
    for(size_t i=0;i<count;++i)result.groups.push_back({{type,int16_t(owned.current_type_a_subtype[i]),
        int16_t(owned.current_type_a_subcat1[i]),int16_t(owned.current_type_a_subcat2[i]),
        owned.current_type_a_amount[i],owned.current_type_a_expanded[i]},owned.current_type_a_on[i],owned.current_type_a_flag[i].whole});
    return result;
}
}
