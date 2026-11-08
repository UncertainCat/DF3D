#pragma once
#include "standing_orders_native.h"
#include "df/squad_equipment_interfacest.h"
#include <cstddef>
#include <vector>

namespace df3d_hunter_ammunition {
struct Material {int16_t category,type;int32_t index;};
struct Type {int16_t type,subtype;bool foreign;};
struct Candidates {std::vector<Material> materials;std::vector<Type> types;};

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
}
