#pragma once
#include "work_order_rows_native.h"
#include "df/job_item_filter.h"
#include "df/work_orders_conditions_interfacest.h"
#include "df/wqc_item_traitst.h"
#include <new>
#include <type_traits>

namespace df3d_production {
struct WorkOrderFilterChoice {
    std::string search;
    int16_t itemType=-1,itemSubtype=-1,materialType=-1;
    int32_t materialIndex=-1,materialState=-1;
    std::optional<df::wqc_item_traitst> trait;
};
inline bool workOrderSuggestionsSupported() {
    static const bool supported=[] {
        if(!workOrderRowsSupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xa9ce10,0x890,UINT64_C(0x45f247042723739d)},
            {0xd160c0,0x1047,UINT64_C(0x824b3791b709c77c)},
            {0x14eda2,0x28,UINT64_C(0x9eb9c219b43e040e)},
            {0x1fb050,0x123,UINT64_C(0x3ea393db12f2c677)},
            {0xa2adb0,0x185c,UINT64_C(0x236e98c86197e94e)},
            {0x3926b1,0x1ef,UINT64_C(0x07d2b75807214414)},
            {0x3c54b5,0x160,UINT64_C(0x4656e100c0a9d60c)},
            {0x3c5671,0x1ae,UINT64_C(0xf630e9734b5a8891)},
            {0x3c534d,0xbf,UINT64_C(0xa3ed7f994900fc90)},
            {0x3c5273,0x4,UINT64_C(0x53530d88aba7d93d)},
            {0x3c528d,0x12,UINT64_C(0x1e833228f3884819)},
            {0x3c52b5,0x1d,UINT64_C(0xaa03b472cb42644f)},
            {0xa9daa0,0x26c1,UINT64_C(0xb1841e71e0165504)},
            {0x3c3300,0x3b7,UINT64_C(0x0524ef1750a9c49a)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return supported;
}
// A9daa0 builds the three filter catalogs from world raws. Its tail3c3300
// filters the supplied catalog, not a global menu. The fresh context is owned,
// never copied from game.main_interface. Traits additionally read the owned
// recipe's job type/reaction to include reaction-specific reagent restrictions.
inline std::optional<std::vector<WorkOrderFilterChoice>> nativeWorkOrderFilterChoices(const df::manager_order& source,int kind) {
    if(kind<0 || kind>2 || source.reaction_name.size()>128 || !workOrderSuggestionsSupported() || !df::global::world)return std::nullopt;
    static_assert(offsetof(df::work_orders_conditions_interfacest,filter)==0x78);
    static_assert(offsetof(df::work_orders_conditions_interfacest,change_type)==0xb0);
    static_assert(offsetof(df::work_orders_conditions_interfacest,item_trait_master)==0x180);
    static_assert(sizeof(df::wqc_item_traitst)==0x88);
    df::work_orders_conditions_interfacest scratch;
    df::manager_order recipe;recipe.job_type=source.job_type;recipe.reaction_name=source.reaction_name;
    scratch.wq=&recipe;
    scratch.change_type=static_cast<df::work_order_condition_change_type>(kind);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    struct Cleanup {
        df::work_orders_conditions_interfacest& s;const uint8_t* base;
        ~Cleanup() {
            using Clear=void (*)(void*);using Free=void (*)(void*,size_t);
            auto clear=[&](size_t rva,void* value){reinterpret_cast<Clear>(base+rva)(value);};
            for(auto* row:s.item_trait_master)if(row) {
                clear(0x6f850,&row->reaction_class);clear(0x6f850,&row->reaction_product_class);
                clear(0x6f850,&row->display_string);
                reinterpret_cast<Free>(base+0x1539680)(row,0x88);
            }
            clear(0x66b70,&s.item_trait_master);
            clear(0xbb9b0,&s.compare_master);clear(0x66b70,&s.compare_master);
            clear(0x6f7b0,&s.item_type_master);clear(0x6f7b0,&s.item_subtype_master);
            clear(0x6f7b0,&s.item_material_master);clear(0x6f750,&s.item_matgloss_master);
            clear(0x6f7b0,&s.item_matstate_master);
            // MSVC vector<bool> stores its owned word vector first, followed by
            // bit count. Clear native allocations before the C++ owner dies.
            clear(0x6f750,&s.item_type_on);s.item_type_on.clear();
            clear(0x6f750,&s.item_material_on);s.item_material_on.clear();
            clear(0x6f850,&s.filter);
        }
    } cleanup{scratch,base};
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    using Build=void (*)(df::work_orders_conditions_interfacest*);
    reinterpret_cast<Build>(base+0xa9daa0)(&scratch);
    const auto count=scratch.compare_master.size();
    if(count>32768 || (kind==0 && (scratch.item_type_master.size()!=count || scratch.item_subtype_master.size()!=count)) ||
       (kind==1 && (scratch.item_material_master.size()!=count || scratch.item_matgloss_master.size()!=count || scratch.item_matstate_master.size()!=count)) ||
       (kind==2 && scratch.item_trait_master.size()!=count))return std::nullopt;
    std::vector<WorkOrderFilterChoice> result;result.reserve(count);
    for(size_t i=0;i<count;++i) {
        if(!scratch.compare_master[i] || scratch.compare_master[i]->size()>2048)return std::nullopt;
        WorkOrderFilterChoice row;row.search=*scratch.compare_master[i];
        if(kind==0){row.itemType=int16_t(scratch.item_type_master[i]);row.itemSubtype=scratch.item_subtype_master[i];}
        else if(kind==1){row.materialType=scratch.item_material_master[i];row.materialIndex=scratch.item_matgloss_master[i];row.materialState=int32_t(scratch.item_matstate_master[i]);}
        else {if(!scratch.item_trait_master[i])return std::nullopt;row.trait=*scratch.item_trait_master[i];}
        result.push_back(std::move(row));
    }
    return result;
}
// Compose the renderer's condition-to-filter mapping (3926b1..39289a),
// then call its item-description leaf. All filter storage belongs to this call.
inline std::optional<std::string> nativeWorkOrderConditionCaption(const df::manager_order_condition_item& source) {
    if(!workOrderSuggestionsSupported() || !df::global::world || source.contains.size()>64 ||
       source.reaction_class.size()>128 || source.has_material_reaction_product.size()>128)return std::nullopt;
    static_assert(sizeof(df::job_item_filter)==0x110);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Init=void (*)(df::job_item_filter*);
    using Describe=void (*)(df::job_item_filter*,std::string*,int16_t);
    df::job_item_filter filter;
    reinterpret_cast<Init>(base+0x1fb050)(&filter);
    filter.item_type=source.item_type;filter.item_subtype=source.item_subtype;
    filter.mat_type=source.mat_type;filter.mat_index=source.mat_index;filter.use_mat_index=source.mat_index!=-1;
    filter.flags1=source.flags1;
    filter.flags2=source.flags2;filter.use_flags2=source.flags2.whole!=0;
    filter.flags3=source.flags3;filter.use_flags3=source.flags3.whole!=0;
    filter.flags4=source.flags4;filter.use_flags4=source.flags4!=0;
    filter.flags5=source.flags5;filter.use_flags5=source.flags5!=0;
    filter.metal_ore=source.metal_ore;filter.use_metal_ore=source.metal_ore!=-1;
    filter.reaction_class=source.reaction_class;filter.use_reaction_class=!source.reaction_class.empty();
    filter.has_material_reaction_product=source.has_material_reaction_product;
    filter.use_reaction_product=!source.has_material_reaction_product.empty();
    filter.min_dimension=source.min_dimension;filter.reaction_id=source.reaction_id;
    filter.contains=source.contains;filter.use_contains=!source.contains.empty();
    filter.has_tool_use=source.has_tool_use;filter.dye_color=source.dye_color;
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::string result;
    reinterpret_cast<Describe>(base+0xa2adb0)(&filter,&result,-1);
    if(result.size()>1024)return std::nullopt;
    return result;
}
// A9ce10 is the suggestion builder, not the conditions renderer/input handler.
// Its only context input is order+8 and its only output is the pointer vector
// at+58. Supply this independent scratch layout, never an open native panel.
inline std::optional<std::vector<df::manager_order_condition_item>> nativeWorkOrderSuggestions(const df::manager_order& source) {
    if(!workOrderSuggestionsSupported() || !df::global::world || source.reaction_name.size()>128)return std::nullopt;
    df::manager_order recipe;
    recipe.job_type=source.job_type;recipe.reaction_name=source.reaction_name;
    recipe.item_type=source.item_type;recipe.item_subtype=source.item_subtype;
    recipe.mat_type=source.mat_type;recipe.mat_index=source.mat_index;
    recipe.specflag=source.specflag;recipe.specdata=source.specdata;recipe.material_category=source.material_category;
    recipe.art_spec=source.art_spec;recipe.items=nullptr;
    struct Scratch {
        uint64_t reserved=0;
        df::manager_order* order=nullptr;
        std::array<uint8_t,0x48> unused{};
        std::vector<df::manager_order_condition_item*> rows;
    } scratch;
    static_assert(offsetof(Scratch,order)==8 && offsetof(Scratch,rows)==0x58);
    static_assert(sizeof(df::manager_order_condition_item)==0x98);
    static_assert(offsetof(df::manager_order_condition_item,contains)==0x70);
    scratch.order=&recipe;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    struct Cleanup {
        Scratch& scratch;const uint8_t* base;
        ~Cleanup() {
            using Clear=void (*)(void*);using Free=void (*)(void*,size_t);
            for(auto* row:scratch.rows)if(row) {
                reinterpret_cast<Clear>(base+0x6f750)(&row->contains);
                reinterpret_cast<Clear>(base+0x6f850)(&row->has_material_reaction_product);
                reinterpret_cast<Clear>(base+0x6f850)(&row->reaction_class);
                reinterpret_cast<Free>(base+0x1539680)(row,0x98);
            }
        }
    } cleanup{scratch,base};
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    using Build=void (*)(Scratch*);
    reinterpret_cast<Build>(base+0xa9ce10)(&scratch);
    if(scratch.rows.size()>128)return std::nullopt;
    std::vector<df::manager_order_condition_item> result;
    result.reserve(scratch.rows.size());
    for(const auto* row:scratch.rows) {
        if(!row || row->contains.size()>64 || row->reaction_class.size()>128 || row->has_material_reaction_product.size()>128)return std::nullopt;
        result.push_back(*row);
    }
    return result;
}
// Native duplicate predicate3c54b5..3c5615 intentionally does not compare
// threshold, comparison, or contains. Preserve the actual suggestion rule.
inline bool sameNativeSuggestedFilter(const df::manager_order_condition_item& a,const df::manager_order_condition_item& b) {
    return a.item_type==b.item_type && a.item_subtype==b.item_subtype && a.mat_type==b.mat_type && a.mat_index==b.mat_index &&
        a.flags1.whole==b.flags1.whole && a.flags2.whole==b.flags2.whole && a.flags3.whole==b.flags3.whole &&
        a.flags4==b.flags4 && a.flags5==b.flags5 && a.reaction_class==b.reaction_class &&
        a.has_material_reaction_product==b.has_material_reaction_product && a.metal_ore==b.metal_ore &&
        a.min_dimension==b.min_dimension && a.reaction_id==b.reaction_id && a.has_tool_use==b.has_tool_use && a.dye_color==b.dye_color;
}
inline bool nativeSuggestionAvailable(const df::manager_order& order,const df::manager_order_condition_item& suggestion) {
    for(const auto* condition:order.item_conditions)if(!condition || sameNativeSuggestedFilter(*condition,suggestion))return false;
    return true;
}
inline NativeWorkOrderEdit addNativeWorkOrderSuggestion(int32_t buildingId,int32_t id,uint64_t revision,int16_t index) {
    NativeWorkOrderEdit result;
    if(index<0 || !workOrderSuggestionsSupported() || !workshopOrdersProfile(df::building::find(buildingId)))return result;
    const auto& all=df::global::world->manager_orders.all;
    const auto found=std::find_if(all.begin(),all.end(),[&](const auto* row){return row && row->id==id && row->workshop_id==buildingId;});
    if(found==all.end())return result;
    auto& order=**found;const int32_t position=int32_t(found-all.begin());
    const auto before=nativeWorkOrderRow(order,position);if(!before)return result;
    if(!revision || before->revision!=revision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
    const auto suggestions=nativeWorkOrderSuggestions(order);
    const size_t count=order.item_conditions.size()+order.order_conditions.size();
    if(!suggestions || size_t(index)>=suggestions->size() || count>=64 || count+1+suggestions->size()>128)return result;
    const auto& source=(*suggestions)[size_t(index)];
    if(!nativeSuggestionAvailable(order,source))return result;
    // Complete all throwing copies/reservations before registration. Allocate
    // the record using DF's allocator, then transfer the owned string/vector
    // storage without throwing, as the native inline deep copy does.
    df::manager_order_condition_item prepared(source);
    static_assert(std::is_nothrow_move_constructible_v<df::manager_order_condition_item>);
    order.item_conditions.reserve(order.item_conditions.size()+1);
    using Allocate=void* (*)(size_t);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    void* memory=reinterpret_cast<Allocate>(base+0x1539690)(sizeof(prepared));
    if(!memory)return result;
    auto* added=new(memory) df::manager_order_condition_item(std::move(prepared));
    order.item_conditions.push_back(added);
    if(order.frequency==df::workquota_frequency_type::OneTime)order.frequency=df::workquota_frequency_type::Daily;
    result.outcome=WorkshopOrdersOutcome::Unknown;
    try {
        auto after=nativeWorkOrderRow(order,position);
        if(after && order.item_conditions.back()==added && sameNativeSuggestedFilter(*added,source) &&
           added->compare_type==source.compare_type && added->compare_val==source.compare_val && added->contains==source.contains) {
            result.row=std::move(after);result.outcome=WorkshopOrdersOutcome::Applied;
        }
    }catch(...) {}
    return result;
}
inline NativeWorkOrderEdit setNativeWorkOrderConditionAmount(int32_t buildingId,int32_t id,uint64_t revision,int16_t index,int8_t comparison,int32_t threshold) {
    NativeWorkOrderEdit result;
    if(index<0 || comparison<0 || comparison>5 || threshold<0 || !workOrderSuggestionsSupported() || !workshopOrdersProfile(df::building::find(buildingId)))return result;
    const auto& all=df::global::world->manager_orders.all;
    const auto found=std::find_if(all.begin(),all.end(),[&](const auto* row){return row && row->id==id && row->workshop_id==buildingId;});
    if(found==all.end())return result;
    auto& order=**found;const int32_t position=int32_t(found-all.begin());
    const auto before=nativeWorkOrderRow(order,position);if(!before)return result;
    if(!revision || before->revision!=revision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
    if(size_t(index)>=order.item_conditions.size())return result;
    auto* condition=order.item_conditions[size_t(index)];
    // Native increment/decrement and six-way comparison cycle write these
    // two scalars only; filter fields, frequency and scheduling are unchanged.
    condition->compare_type=df::logic_condition_type(comparison);condition->compare_val=threshold;
    result.outcome=WorkshopOrdersOutcome::Unknown;
    try {
        auto after=nativeWorkOrderRow(order,position);
        if(after && condition->compare_type==df::logic_condition_type(comparison) && condition->compare_val==threshold) {
            result.row=std::move(after);result.outcome=WorkshopOrdersOutcome::Applied;
        }
    }catch(...) {}
    return result;
}
inline NativeWorkOrderEdit removeNativeWorkOrderCondition(int32_t buildingId,int32_t id,uint64_t revision,uint8_t kind,int16_t index,
    void** holding,size_t& held,size_t capacity) {
    NativeWorkOrderEdit result;
    if(index<0 || kind>1 || held>=capacity || !workOrderSuggestionsSupported() || !workshopOrdersProfile(df::building::find(buildingId)))return result;
    const auto& all=df::global::world->manager_orders.all;
    const auto found=std::find_if(all.begin(),all.end(),[&](const auto* row){return row && row->id==id && row->workshop_id==buildingId;});
    if(found==all.end())return result;
    auto& order=**found;const int32_t position=int32_t(found-all.begin());
    const auto before=nativeWorkOrderRow(order,position);if(!before)return result;
    if(!revision || before->revision!=revision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
    if(size_t(index)>=(kind?order.order_conditions.size():order.item_conditions.size()))return result;
    // Native3c534d..3c540c removes only this condition, preserving frequency,
    // order status and scheduled date. Retain retired storage as for order
    // removal: native sheets may still hold borrowed pointers to these records.
    if(kind) {
        holding[held++]=order.order_conditions[size_t(index)];
        order.order_conditions.erase(order.order_conditions.begin()+index);
    } else {
        holding[held++]=order.item_conditions[size_t(index)];
        order.item_conditions.erase(order.item_conditions.begin()+index);
    }
    result.outcome=WorkshopOrdersOutcome::Unknown;
    try {
        auto after=nativeWorkOrderRow(order,position);
        if(after && after->itemConditions.size()+after->orderConditions.size()+1==before->itemConditions.size()+before->orderConditions.size()) {
            result.row=std::move(after);result.outcome=WorkshopOrdersOutcome::Applied;
        }
    }catch(...) {}
    return result;
}
}
