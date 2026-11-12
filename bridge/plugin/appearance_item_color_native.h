#pragma once
#include "appearance_template_native.h"
#include "df/item_constructed.h"
#include "df/itemimprovement_threadst.h"
#include "df/itemimprovement_colorationst.h"
#include "df/material.h"
#include "df/descriptor_pattern.h"
#include "df/descriptor_color.h"
#include "df/world.h"
#include <optional>

namespace df3d_appearance {
// Native creature renderer720546..720721 selects the first usable thread or
// coloration dye, resolving its solid-state material pattern. The generic item
// color virtual uses dye color instead and can disagree (ROOT_HIDE:MILL).
// Only semantic items/materials enter this adapter; no renderer/cache inputs.
inline std::optional<int32_t> nativeAppearanceItemColor(df::item* item) {
    using Resolve=df::material* (*)(df::world*,int16_t,int32_t);
    static const auto resolve=[]()->Resolve {
        if(!graphicsTemplateFunction())return nullptr; // supported PE/build
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x12f;++i){hash^=base[0x14add70+i];hash*=UINT64_C(1099511628211);}
        if(hash!=UINT64_C(0x01f897b15772d540))return nullptr;
        return reinterpret_cast<Resolve>(base+0x14add70);
    }();
    if(!resolve || !df::global::world)return std::nullopt;
    if(!item)return -1;
    static_assert(offsetof(df::item_constructed,improvements)==0xd0);
    static_assert(offsetof(df::itemimprovement_threadst,dye)==0x28);
    static_assert(offsetof(df::itemimprovement_threadst,dye_profile)==0x40);
    static_assert(offsetof(df::itemimprovement_colorationst,dye_material)==0x28);
    static_assert(offsetof(df::itemimprovement_colorationst,dye_profile)==0x40);
    static_assert(offsetof(df::material,state_color)==0x9c);
    const auto materialColor=[&](int16_t type,int32_t index)->int32_t {
        const auto* material=resolve(df::global::world,type,index);
        const auto* pattern=material?df::descriptor_pattern::find(material->state_color[0]):nullptr;
        return pattern && !pattern->colors.empty()?int32_t(pattern->colors.front()):-1;
    };
    if(item->isDyed()) {
        const auto* constructed=virtual_cast<df::item_constructed>(item);
        if(!constructed)return std::nullopt;
        for(auto* improvement:constructed->improvements) {
            if(!improvement)continue;
            int32_t color=-1;int16_t type=-1;int32_t index=-1;
            if(const auto* thread=virtual_cast<df::itemimprovement_threadst>(improvement)) {
                color=thread->dye_profile.color_index;type=thread->dye.mat_type;index=thread->dye.mat_index;
            } else if(const auto* coloration=virtual_cast<df::itemimprovement_colorationst>(improvement)) {
                color=coloration->dye_profile.color_index;type=coloration->dye_material;index=coloration->dye_matgloss;
            } else continue;
            if(color==-1 && type!=-1)color=materialColor(type,index);
            if(df::descriptor_color::find(color))return color;
        }
    }
    return materialColor(item->getMaterial(),item->getMaterialIndex());
}
}
