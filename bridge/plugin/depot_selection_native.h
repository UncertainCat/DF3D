#pragma once
#include "depot_goods_native.h"
#include "knowledge_detail_native.h"

namespace df3d_production {
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
