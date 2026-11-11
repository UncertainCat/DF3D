#pragma once
#include "df/artifacts_interfacest.h"
#include "df/artifact_record.h"
#include "df/item.h"
#include "df/plotinfost.h"
#include "df/world.h"
#include <array>
#include <optional>
#include <unordered_set>
#include <vector>

namespace df3d_objects {
using Lists=std::array<std::vector<int32_t>,4>;
struct Names {int32_t artifactId=-1,itemId=-1;std::string nativeName,translatedName;};
// Renderer3a06ca/3a083a formats both names using a94030/a946e0. Copy the
// semantic name before calling DF, and leave width-dependent clipping to UI.
inline std::optional<Names> names(int32_t id) {
    auto* artifact=df::artifact_record::find(id);if(!artifact || !artifact->item)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        const auto hash=[base](size_t at,size_t count){uint64_t result=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){result^=base[at+i];result*=UINT64_C(1099511628211);}return result;};
        return hash(0xa94030,0x6a1)==UINT64_C(0xd81db68b3c9b33d2) &&
            hash(0xa946e0,0x7c2)==UINT64_C(0xdbc3db5f052419ee);
    }();
    if(!pinned)return std::nullopt;
    static_assert(offsetof(df::artifact_record,name)==8);
    Names result;result.artifactId=id;result.itemId=artifact->item->id;
    auto owned=artifact->name;
    reinterpret_cast<void(*)(df::language_name*,std::string*)>(base+0xa94030)(&owned,&result.nativeName);
    reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&owned,&result.translatedName,true,false);
    result.translatedName='"'+result.translatedName+'"'; // Native3a0816/3a086c quote literal.
    if(result.nativeName.size()>16384 || result.translatedName.size()>16384)return std::nullopt;
    return result;
}

// Native323aba invokes375a70. Only the supplied context/list vectors are
// written. Native membership, category and ordered unique insertion remain DF
// decisions; position helpers write local coordinates, never rendering scratch.
inline std::optional<Lists> lists() {
    if(!df::global::world || !df::global::plotinfo || !df::global::plotinfo->main.fortress_entity ||
       df::global::world->artifacts.all.size()>1048576)return std::nullopt;
    static_assert(sizeof(df::artifacts_interfacest)==0x80);
    static_assert(offsetof(df::artifacts_interfacest,list)==8);
    static_assert(offsetof(df::artifacts_interfacest,scroll_position)==0x68);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<uint8_t*>(&df::global::plotinfo->main.fortress_entity)!=base+0x239a1e8 ||
       reinterpret_cast<uint8_t*>(&df::global::world->artifacts.all)!=base+0x23e6180)return std::nullopt;
    static const bool pinned=[base] {
        struct Pin {size_t at,length;uint64_t expected;};
        constexpr Pin pins[]={
            {0x375a70,0x7f7,UINT64_C(0xa963ab4fbb14ce9a)},
            {0xb9fa0,0xf5,UINT64_C(0x545aad70c57dd20f)},
            {0xc8baa0,0x11a,UINT64_C(0x2c62fce4a0555c66)},
            {0x1367430,0xc6,UINT64_C(0xc0292be8a6dacf2c)},
            {0xb9dc0,0xa7,UINT64_C(0x4d8961b901732215)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.at+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.expected)return false;
        }
        return true;
    }();
    if(!pinned)return std::nullopt;
    df::artifacts_interfacest owned;
    reinterpret_cast<void(*)(df::artifacts_interfacest*)>(base+0x375a70)(&owned);
    Lists result;
    for(size_t mode=0;mode<result.size();++mode) {
        if(owned.list[mode].size()>1048576)return std::nullopt;
        std::unordered_set<int32_t> seen;
        for(const auto* artifact:owned.list[mode]) {
            if(!artifact || artifact->id<0 || !seen.insert(artifact->id).second)return std::nullopt;
            result[mode].push_back(artifact->id);
        }
    }
    return result;
}
}
