#pragma once
#include "standing_orders_native.h"
#include "df/squad_equipment_interfacest.h"
#include "df/squad_ammo_spec.h"
#include "df/item.h"
#include <algorithm>
#include <memory>
#include <cstddef>
#include <vector>

namespace df3d_hunter_ammunition {
struct Material {int16_t category,type;int32_t index;};
struct Type {int16_t type,subtype;bool foreign;};
struct Candidates {std::vector<Material> materials;std::vector<Type> types;};
struct Spec {
    int32_t item_type,item_subtype,material_class,mattype,matindex,amount;
    uint32_t flags;
    std::vector<int32_t> assigned;
    bool operator==(const Spec& other) const {
        return item_type==other.item_type && item_subtype==other.item_subtype &&
            material_class==other.material_class && mattype==other.mattype && matindex==other.matindex &&
            amount==other.amount && flags==other.flags && assigned==other.assigned;
    }
};
using Snapshot=std::vector<Spec>;
inline std::optional<Snapshot> snapshot() {
    if(!df3d_standing::supportedBase() || !df::global::world || !df::global::plotinfo)return std::nullopt;
    Snapshot result;
    for(const auto* spec:df::global::plotinfo->equipment.hunter_ammunition){
        if(!spec)return std::nullopt;
        result.push_back({int32_t(spec->item_type),spec->item_subtype,int32_t(spec->material_class),
            spec->mattype,spec->matindex,spec->amount,spec->flags.whole,spec->assigned});
    }
    return result;
}
enum class EditOutcome {Unavailable,Stale,Applied};
struct EditResult {EditOutcome outcome=EditOutcome::Unavailable;Snapshot specs;};
inline bool editPins() {
    auto* base=df3d_standing::supportedBase();if(!base)return false;
    static const bool valid=[base] {
        for(const auto& pin:std::array<std::array<uint64_t,3>,5>{{
            {0x8bb7cf,0x8a,UINT64_C(0xc035d9a4040f1032)},
            {0x45bc42,0x77,UINT64_C(0x9d0ec69406c9f3a6)},
            {0x45c105,0xd7,UINT64_C(0xffeecffe5e23fb7e)},
            {0x45c844,0x13a,UINT64_C(0x3b5d5c05601f4186)},
            {0x45caab,0xaa,UINT64_C(0xa193c3f30984ed36)}}}){
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin[1];++i){hash^=base[pin[0]+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin[2])return false;
        }
        return true;
    }();
    return valid;
}
// Full ordered receipt includes assignments: index shifts or changed inventory
// invalidate the intent before mutation. Prepare the reply before any writes.
inline EditResult setAmount(const Snapshot& expected,size_t index,int32_t value) {
    if(!editPins() || value<0 || value>5000)return {};
    const auto current=snapshot();if(!current)return {};
    if(*current!=expected)return {EditOutcome::Stale,{}};
    if(index>=current->size())return {};
    EditResult result{EditOutcome::Applied,*current};result.specs[index].amount=value;
    auto& equipment=df::global::plotinfo->equipment;
    auto* spec=equipment.hunter_ammunition[index];
    if(spec->amount!=value){spec->amount=value;equipment.update.whole|=0x40;}
    return result;
}

// Native45e390 writes only the supplied context; global reads are simulation
// raws and civilization resources. Never pass or inspect the global menu.
inline std::optional<Candidates> candidates() {
    auto* base=df3d_standing::supportedBase();
    if(!base || !df::global::world || !df::global::plotinfo)return std::nullopt;
    static_assert(offsetof(df::squad_equipment_interfacest,setting_ammo)==0x44);
    static_assert(offsetof(df::squad_equipment_interfacest,am_cand_civ_mat)==0x80);
    static_assert(offsetof(df::squad_equipment_interfacest,am_cand_type)==0xd0);
    static_assert(offsetof(df::squad_equipment_interfacest,am_cand_foreign)==0x100);
    static const bool pinned=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x7cc;++i){hash^=base[0x45e390+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x4adf6f022c9ef072);
    }();
    if(!pinned || !*reinterpret_cast<void**>(base+0x239a1e8))return std::nullopt;
    df::squad_equipment_interfacest owned;
    using Build=void(__fastcall*)(df::squad_equipment_interfacest*,int32_t);
    reinterpret_cast<Build>(base+0x45e390)(&owned,-1);
    if(owned.am_cand_civ_mat.size()!=owned.am_cand_spec_mat.size() ||
       owned.am_cand_civ_mat.size()!=owned.am_cand_spec_matg.size() ||
       owned.am_cand_type.size()!=owned.am_cand_subtype.size() ||
       owned.am_cand_type.size()!=owned.am_cand_foreign.size())return std::nullopt;
    Candidates result;
    result.materials.reserve(owned.am_cand_civ_mat.size());
    result.types.reserve(owned.am_cand_type.size());
    for(size_t i=0;i<owned.am_cand_civ_mat.size();++i)
        result.materials.push_back({int16_t(owned.am_cand_civ_mat[i]),owned.am_cand_spec_mat[i],owned.am_cand_spec_matg[i]});
    for(size_t i=0;i<owned.am_cand_type.size();++i)
        result.types.push_back({owned.am_cand_type[i],owned.am_cand_subtype[i],owned.am_cand_foreign[i]});
    return result;
}
inline EditResult setMaterial(const Snapshot& expected,size_t index,const Material& value) {
    if(!editPins())return {};
    const auto current=snapshot();if(!current)return {};
    if(*current!=expected)return {EditOutcome::Stale,{}};
    if(index>=current->size())return {};
    const auto choices=candidates();if(!choices)return {};
    bool found=false;
    for(const auto& choice:choices->materials)
        if(choice.category==value.category && choice.type==value.type && choice.index==value.index){found=true;break;}
    if(!found)return {};
    EditResult result{EditOutcome::Applied,*current};auto& row=result.specs[index];
    row.material_class=value.category;row.mattype=value.type;row.matindex=value.index;
    auto& equipment=df::global::plotinfo->equipment;auto* spec=equipment.hunter_ammunition[index];
    spec->material_class=static_cast<df::entity_material_category>(value.category);
    spec->mattype=value.type;spec->matindex=value.index;equipment.update.whole|=0x40;
    return result;
}
inline EditResult add(const Snapshot& expected,const Type& value) {
    if(!editPins())return {};
    const auto current=snapshot();if(!current)return {};
    if(*current!=expected)return {EditOutcome::Stale,{}};
    const auto choices=candidates();if(!choices)return {};
    bool found=false;
    for(const auto& choice:choices->types)
        if(choice.type==value.type && choice.subtype==value.subtype){found=true;break;}
    if(!found)return {};
    auto created=std::make_unique<df::squad_ammo_spec>();
    created->item_type=static_cast<df::item_type>(value.type);created->item_subtype=value.subtype;
    created->material_class=static_cast<df::entity_material_category>(-1);
    created->mattype=-1;created->matindex=-1;created->amount=25;created->flags.whole=3;
    created->assigned.clear();
    EditResult result{EditOutcome::Applied,*current};
    result.specs.push_back({value.type,value.subtype,-1,-1,-1,25,3,{}});
    auto& equipment=df::global::plotinfo->equipment;
    auto prepared=equipment.hunter_ammunition;prepared.push_back(created.get());
    equipment.hunter_ammunition.swap(prepared);created.release();equipment.update.whole|=0x40;
    return result;
}
inline void eraseAssigned(std::vector<int32_t>& ids,int32_t id) {
    const auto found=std::lower_bound(ids.begin(),ids.end(),id);
    if(found!=ids.end() && *found==id)ids.erase(found);
}
inline void insertUnassigned(std::vector<int32_t>& ids,int32_t id) {
    const auto found=std::lower_bound(ids.begin(),ids.end(),id);
    if(found==ids.end() || *found!=id)ids.insert(found,id);
}
// Native deletion skips nonexistent item IDs; Remove uses the selected ID
// directly. All growing vectors and the response are prepared before swaps.
inline EditResult remove(const Snapshot& expected,size_t index,std::optional<int32_t> item) {
    if(!editPins())return {};
    const auto current=snapshot();if(!current)return {};
    if(*current!=expected)return {EditOutcome::Stale,{}};
    if(index>=current->size())return {};
    const auto& selected=(*current)[index];
    if(item && std::find(selected.assigned.begin(),selected.assigned.end(),*item)==selected.assigned.end())return {};
    auto& equipment=df::global::plotinfo->equipment;
    auto assigned=equipment.items_assigned[df::item_type::AMMO];
    auto unassigned=equipment.items_unassigned[df::item_type::AMMO];
    if(!std::is_sorted(assigned.begin(),assigned.end()) || !std::is_sorted(unassigned.begin(),unassigned.end()) ||
       !std::is_sorted(selected.assigned.begin(),selected.assigned.end()))return {};
    EditResult result{EditOutcome::Applied,*current};
    auto specs=equipment.hunter_ammunition;
    std::vector<int32_t> remaining;
    if(item){
        remaining=selected.assigned;eraseAssigned(remaining,*item);
        eraseAssigned(assigned,*item);insertUnassigned(unassigned,*item);
        result.specs[index].assigned=remaining;
    }else{
        for(auto it=selected.assigned.rbegin();it!=selected.assigned.rend();++it){
            if(!df::item::find(*it))continue;
            eraseAssigned(assigned,*it);insertUnassigned(unassigned,*it);
        }
        specs.erase(specs.begin()+index);result.specs.erase(result.specs.begin()+index);
    }
    auto* target=equipment.hunter_ammunition[index];
    equipment.items_assigned[df::item_type::AMMO].swap(assigned);
    equipment.items_unassigned[df::item_type::AMMO].swap(unassigned);
    if(item)target->assigned.swap(remaining);
    else{equipment.hunter_ammunition.swap(specs);delete target;}
    equipment.update.whole|=0x40;
    return result;
}
}
