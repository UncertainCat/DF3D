#pragma once
#include "display_assignment_native.h"
#include "df/assign_display_item_interfacest.h"

namespace df3d_production {
inline bool displayPickerReady() {
    if(!buildingItemFunctions())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x379df0,0x264,UINT64_C(0xdfd22c4bd09252aa)},
            {0x37c390,0x3e7,UINT64_C(0xd0eb4b1c72f3e183)},
            {0x37a670,0x64e,UINT64_C(0x430e1ef6ea0f969c)},
            {0x36797b,0x1f4,UINT64_C(0x68998ca68cc0322b)},
            {0xa82c10,0x56ec,UINT64_C(0x66347214dfd39a0b)},
            {0x52d650,0x2b4,UINT64_C(0x9e8023d09def7af9)},
            {0x52cee0,0x19e,UINT64_C(0xc25c2d8a6eb9fcac)},
            {0xe1990,0xc7,UINT64_C(0x1c45e5635f4ffde2)}};
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
struct DisplayPicker {
    int16_t type=-1;
    int32_t height=0;
    df3d_stocks::Totals counts;
    std::vector<df3d_stocks::CategoryDisplay> captions;
    std::vector<int16_t> categories,order;
    std::vector<df3d_stocks::SelectedGroup> groups;
    std::vector<int32_t> items;
};
// Type projection, group filtering and height aggregation operate solely on this
// owned context plus semantic item/material facts. Never call the global opener
// or category filter37b6e0, whose final clamp reads native window dimensions.
inline std::optional<DisplayPicker> displayPicker(df::building* building,int16_t type,std::string query) {
    if(!displayPickerReady() || type<-1 || type>=93 || query.size()>1024)return {};
    const auto ids=displayInventory(building);if(!ids)return {};
    const auto groups=df3d_stocks::groups(*ids);if(!groups)return {};
    const auto categories=df3d_stocks::categories(query,&*groups);if(!categories)return {};
    if(type<0){if(categories->empty())return {};type=categories->front();}
    df::assign_display_item_interfacest owned;
    static_assert(sizeof(owned)==0x230);
    static_assert(offsetof(df::assign_display_item_interfacest,master_a_list)==0xd8);
    static_assert(offsetof(df::assign_display_item_interfacest,current_type_i_list)==0x178);
    static_assert(offsetof(df::assign_display_item_interfacest,current_type_a_on)==0x210);
    owned.current_type=df::item_type(type);owned.item_filter=std::move(query);
    DisplayPicker result;result.type=type;result.categories=*categories;
    const auto order=owned.item_filter.empty()?categories:df3d_stocks::categories("");if(!order)return {};result.order=*order;
    for(auto id:*ids) {
        auto* item=df::item::find(id);if(!item)return {};
        owned.master_i_list.l_item.push_back(item);
        const int itemType=int(item->getType());if(itemType<0 || itemType>=113)return {};
        auto& count=(item->flags.bits.in_building?result.counts.unavailable:result.counts.stored)[itemType];
        count=int32_t(uint32_t(count)+uint32_t(item->getStackSize()));
    }
    const auto captions=df3d_stocks::categoryDisplay(result.counts);if(!captions)return {};
    result.captions=*captions;
    for(const auto& group:*groups) {
        auto& list=owned.master_a_list;
        list.type.push_back(group.type);list.subtype.push_back(group.subtype);
        list.subcat1.push_back(group.subcat1);list.subcat2.push_back(group.subcat2);
        list.amount.push_back(group.amount);list.expanded.push_back(group.expanded);
    }
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    df3d_creature::KnowledgeMaterialCacheRestore restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    reinterpret_cast<void(*)(df::assign_display_item_interfacest*)>(base+0x379df0)(&owned);
    result.height=owned.i_height;
    size_t index=0;
    for(const auto& group:*groups)if(group.type==type) {
        if(index>=owned.current_type_a_on.size() || index>=owned.current_type_a_expanded.size())return {};
        df3d_stocks::SelectedGroup row{group,owned.current_type_a_on[index],0};
        row.group.expanded=owned.current_type_a_expanded[index++];
        using Describe=void(*)(std::string*,int16_t,int16_t,int16_t,int32_t,int32_t,int32_t,bool,void*,int32_t,int32_t,bool,int32_t,int32_t);
        reinterpret_cast<Describe>(base+0xa82c10)(&row.caption,type,group.subtype,group.subcat1,group.subcat2,group.amount,0,false,nullptr,-1,-1,true,0,0);
        reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&row.caption);
        result.groups.push_back(std::move(row));
    }
    // Use the shared native abstract-group matcher rather than reconstructing
    // material/historical-figure grouping rules in the presentation.
    for(auto* item:owned.current_type_i_list) {
        if(!item)return {};
        result.items.push_back(item->id);
        const auto groupIndex=reinterpret_cast<int32_t(*)(df::abstractitemlistst*,df::item*)>(base+0xac9890)(&owned.master_a_list,item);
        if(groupIndex<0 || size_t(groupIndex)>=groups->size())return {};
        size_t local=0;
        for(int32_t i=0;i<groupIndex;++i)if((*groups)[i].type==type)++local;
        if(local>=result.groups.size())return {};
        result.groups[local].ids.push_back(item->id);
    }
    return result;
}
struct DisplayBodyRow {
    int32_t id=-1;
    bool resolved=false,onDisplay=false;
    std::string name,status;
    uint8_t statusColor=15;
};
inline std::optional<std::vector<DisplayBodyRow>> displayBody(df::building* building) {
    const auto state=displayAssignments(building);const auto lookup=itemBuildingLookup();
    if(!state || !lookup)return {};
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0xc7e;++i){hash^=base[0x18abbe+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xb5d7584fd39790ea) &&
            std::strcmp(reinterpret_cast<const char*>(base+0x16014c0),"On display")==0 &&
            std::strcmp(reinterpret_cast<const char*>(base+0x16014b0),"Assigned")==0;
    }();if(!ready)return {};
    std::vector<DisplayBodyRow> result;
    for(auto id:state->items) {
        DisplayBodyRow row;row.id=id;
        if(auto* item=df::item::find(id)) {
            const auto name=buildingItemCaption(item);if(!name)return {};
            row.resolved=true;row.name=*name;row.onDisplay=lookup(item,36)==building;
            row.status=reinterpret_cast<const char*>(base+(row.onDisplay?0x16014c0:0x16014b0));
            row.statusColor=row.onDisplay?10:15;
        }
        result.push_back(std::move(row));
    }
    return result;
}
}
