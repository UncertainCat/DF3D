#pragma once
#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace df3d_production {
// Owned original-asset references, independent of native item and UI lifetimes.
struct ItemAppearanceRecipe {
    std::vector<std::string> pages,palettes;
    std::vector<std::array<int32_t,10>> layers;
};
inline bool validItemRecipe(const ItemAppearanceRecipe& r,size_t& bytes) {
    if(r.pages.empty() || r.pages.size()>256 || r.palettes.size()>256 || r.layers.empty() || r.layers.size()>256)return false;
    bytes+=12;
    for(const auto* names:{&r.pages,&r.palettes})for(const auto& s:*names){
        if(s.empty() || s.size()>(names==&r.pages?256u:512u))return false;
        bytes+=4+s.size();
    }
    const int low[]={0,0,0,1,1,0,-32768,-32768,-128,-128};
    const int high[]={65535,65535,65535,255,255,65535,32767,32767,127,127};
    for(const auto& l:r.layers){
        for(size_t i=0;i<10;++i)if(l[i]<low[i] || l[i]>high[i])return false;
        if(size_t(l[0])>=r.pages.size() || (l[5]!=65535 && size_t(l[5])>=r.palettes.size()))return false;
        bytes+=16;
    }
    return bytes<=131072;
}
template<class Number,class Text>
inline void hashItemRecipe(const std::optional<ItemAppearanceRecipe>& r,Number number,Text text) {
    number(r.has_value());if(!r)return;
    for(const auto* names:{&r->pages,&r->palettes}){number(names->size());for(const auto& s:*names)text(s);}
    number(r->layers.size());for(const auto& l:r->layers)for(auto n:l)number(n);
}
}
