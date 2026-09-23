#pragma once
#include "df3d_assets/resolver.h"
#include <string_view>
namespace df3d_godot {
// Selection policy stays in the presentation layer. Unknown material remains
// unknown; a missing item is not proof of a flesh attack.
inline const char* effectMaterial(const df3d::assets::AssetIndex* index, std::string_view token) {
    using namespace df3d::assets;
    if(index) {
        const auto flags=index->materialFlags(token);
        if(flags & kMatMetal)return "metal";
        if(flags & kMatWood)return "wood";
        if(flags & kMatGlass)return "glass";
        if(flags & kMatStone)return "stone";
    }
    if(token.starts_with("PLANT:") && token.ends_with(":WOOD")) return "wood";
    if(token.starts_with("CREATURE:") || token.starts_with("CREATURE_MAT:")) {
        const auto tissue=token.substr(token.rfind(':')+1);
        if(tissue=="BONE" || tissue=="TOOTH" || tissue=="HORN" || tissue=="SHELL") return "bone";
        if(tissue=="MUSCLE" || tissue=="SKIN" || tissue=="FAT" || tissue=="NERVE" || tissue=="BRAIN") return "flesh";
    }
    return "";
}
}
