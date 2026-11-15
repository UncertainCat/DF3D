#pragma once
#include "tile_selection_native.h"
#include "work_order_art_native.h"
#include "df/location_detailst.h"

namespace df3d_selection {
// Planned engraving inputs come from the semantic per-tile specification.
// The actual native opener also allocates an empty specification when absent;
// collecting candidates needs only an owned default in that case.
inline std::optional<df3d_production::WorkOrderArtSubjects> engravingArtSubjects(int x,int y,int z,int kind) {
    const auto selection=collect(x,y,z);
    if(!selection || !df::global::plotinfo)return std::nullopt;
    const auto planned=df::view_sheet_type::ENGRAVING_PLANNED;
    bool eligible=selection->active.kind==planned;
    for(const auto& tab:selection->tabs)eligible|=tab.kind==planned;
    if(!eligible)return std::nullopt;
    df::location_detailst detail;detail.pos=df::coord(uint16_t(x),uint16_t(y),uint16_t(z));
    for(const auto* value:df::global::plotinfo->waypoints.location_detail)
        if(value && value->pos==detail.pos){detail=*value;break;}
    uint64_t revision=UINT64_C(14695981039346656037);
    for(auto value:{x,y,z,int(detail.art_specifier),detail.art_spec_id1,detail.art_spec_id2})
        for(unsigned shift=0;shift<32;shift+=8){revision^=(uint32_t(value)>>shift)&255;revision*=UINT64_C(1099511628211);}
    revision&=INT64_MAX;if(!revision)revision=1;
    df::image_creation_specifierst inputs;inputs.location_detail=&detail;
    inputs.image_ent=df::global::plotinfo->main.fortress_entity;
    return df3d_production::nativeArtSubjects(inputs,revision,kind,{},df::image_creator_context_type::DESIGNATION_ENGRAVING);
}
}
