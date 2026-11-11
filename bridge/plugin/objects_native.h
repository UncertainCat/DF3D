#pragma once
#include "building_item_native.h"
#include "df/artifacts_interfacest.h"
#include "df/artifact_record.h"
#include "df/item.h"
#include "df/plotinfost.h"
#include "df/world.h"
#include "df/artifact_claim.h"
#include "df/entity_position_assignment.h"
#include "df/entity_position.h"
#include "df/historical_entity.h"
#include "df/historical_figure.h"
#include "df/historical_figure_info.h"
#include "df/historical_figure_relationships.h"
#include "df/relationship_profile_artifactst.h"
#include "df/nemesis_record.h"
#include "df/familyst.h"
#include "df/family_artifact_claimst.h"
#include <array>
#include <optional>
#include <unordered_set>
#include <vector>

namespace df3d_objects {
using Lists=std::array<std::vector<int32_t>,4>;
struct Names {int32_t artifactId=-1,itemId=-1;std::string nativeName,translatedName;};
struct Destination {int32_t itemId=-1;bool available=false;df::coord position;};
// Input39f64e uses native IN_PLAY lookup; both controls then resolve the same
// effective holder position. c8baa0 is the standalone form of the inlined
// resolver at39f694/39f7c6 and renderer3a0a44. Navigation remains viewer-owned.
inline std::optional<Destination> destination(int32_t id) {
    auto* artifact=df::artifact_record::find(id);
    if(!df::global::world || !artifact || !artifact->item)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto& items=df::global::world->items.other[df::items_other_id::IN_PLAY];
    if(reinterpret_cast<const uint8_t*>(&items)!=base+0x23e5468 || items.size()>1048576)return std::nullopt;
    static const bool pinned=[base]{uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x9c;++i){hash^=base[0x1f9dc0+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x7cff96b5a9586fec);}();
    if(!pinned)return std::nullopt;
    Destination result;result.itemId=artifact->item->id;
    using Find=int32_t(*)(int32_t,const std::vector<df::item*>*);
    if(reinterpret_cast<Find>(base+0x1f9dc0)(result.itemId,&items)==-1)return result;
    const auto position=df3d_production::itemPosition(artifact->item);if(!position)return std::nullopt;
    result.available=position->x!=-30000;
    if(result.available)result.position=*position;
    return result;
}
// Native renderer3a0cc2..3a147e has no standalone caption helper. Preserve its
// claim precedence here, calling native lookup/title/history formatters with
// owned formatting scratch. Never invoke the renderer or inspect its menu.
inline std::optional<std::string> ownership(int32_t id) {
    auto* world=df::global::world;auto* plot=df::global::plotinfo;
    if(!world || !plot || !plot->main.fortress_entity || !df::artifact_record::find(id))return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto at=[base](const void* p,size_t rva){return reinterpret_cast<const uint8_t*>(p)==base+rva;};
    if(!at(&plot->king_arrived,0x23912da) || !at(&plot->civ_id,0x2393670) ||
       !at(&plot->main.fortress_entity,0x239a1e8) || !at(&world->family_info.family,0x2506068) ||
       !at(&world->history,0x24f9cb8))return std::nullopt;
    static const bool pinned=[base] {
        struct Pin {size_t at,length;uint64_t expected;};
        constexpr Pin pins[]={
            {0x3a0cc2,0x7bc,UINT64_C(0x9ebb33b65430ce65)},
            {0xb9dc0,0xa7,UINT64_C(0x4d8961b901732215)},
            {0xbbe40,0xad,UINT64_C(0x062a266340f9bf38)},
            {0x99a3c0,0x113,UINT64_C(0x14b5664261afc791)},
            {0xb92900,0x178,UINT64_C(0x7485ca6699669626)},
            {0xb92f10,0xa17,UINT64_C(0x07701ee83ad6d384)},
            {0x72080,0xed,UINT64_C(0xe0cf31f3be155555)},
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.at+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.expected)return false;}
        return true;
    }();
    if(!pinned)return std::nullopt;
    static_assert(offsetof(df::historical_entity,artifact_claims)==0x1318);
    static_assert(offsetof(df::historical_entity,nemesis)==0x1450);
    static_assert(offsetof(df::historical_figure,info)==0x130);
    static_assert(offsetof(df::historical_figure,family_head_id)==0xc0);
    static_assert(offsetof(df::historical_figure,id)==0xe0);
    static_assert(offsetof(df::historical_figure_info,relationships)==0x60);
    static_assert(offsetof(df::historical_figure_relationships,artifact_claims)==0x60);
    const auto literal=[base](size_t rva){return reinterpret_cast<const char*>(base+rva);};
    const auto prefix=[&](int32_t type)->const char* {
        switch(type){case 0:return literal(0x162bf70);case 1:return literal(0x162bfc8);
            case 2:return literal(0x162bfb8);case 3:return literal(0x162bff0);default:return nullptr;}
    };
    using Lookup=void*(*)(int32_t,const void*);
    const auto lookup=reinterpret_cast<Lookup>(base+0xb9dc0);
    std::string text;
    const auto entityCaption=[&](df::historical_entity* entity) {
        if(!entity)return;
        auto* claim=static_cast<df::artifact_claim*>(lookup(id,&entity->artifact_claims));
        if(!claim || claim->renounce_event!=-1)return;
        const auto* start=prefix(int32_t(claim->claim_type));if(!start)return;text=start;
        if(int32_t(claim->claim_type)==0){
            auto* assignment=static_cast<df::entity_position_assignment*>(lookup(claim->symbol_claim_id,&entity->positions.assignments));
            if(assignment){
                auto owned=*assignment; // bbe40 updates the position-index cache.
                using Position=df::entity_position*(*)(df::historical_entity*,df::entity_position_assignment*);
                if(auto* position=reinterpret_cast<Position>(base+0xbbe40)(entity,&owned)){
                    using Title=const std::string*(*)(df::entity_position*,int8_t,bool,bool);
                    text+=literal(0x15e8e48); // Native3a0f61/3a0ff2 appends "the ".
                    text+=*reinterpret_cast<Title>(base+0x99a3c0)(position,-1,false,false);return;
                }
            }
        }
        // b92900 ignores its first argument and appends the semantic entity name.
        reinterpret_cast<void(*)(void*,std::string*,int32_t,int32_t)>(base+0xb92900)(nullptr,&text,entity->id,0);
    };
    const auto figureName=[&](int32_t figureId) {
        alignas(8) std::array<uint8_t,0xc8> context{};
        reinterpret_cast<void(*)(void*)>(base+0x72080)(context.data());
        using Name=void(*)(void*,std::string*,int32_t,void*,int16_t,int16_t);
        reinterpret_cast<Name>(base+0xb92f10)(&world->history,&text,figureId,context.data(),2,1);
    };
    entityCaption(plot->main.fortress_entity);
    if(text.empty() && plot->king_arrived)entityCaption(df::historical_entity::find(plot->civ_id));
    if(text.empty())for(const auto* resident:plot->main.fortress_entity->nemesis){
        auto* figure=resident?resident->figure:nullptr;
        if(!figure || !figure->info || !figure->info->relationships)continue;
        for(const auto* claim:figure->info->relationships->artifact_claims){
            if(!claim || claim->artifact_id!=id || claim->renounce_event!=-1)continue;
            if(int32_t(claim->type)==1 || int32_t(claim->type)==2){text=prefix(int32_t(claim->type));figureName(figure->id);}
            break;
        }
        if(!text.empty())break;
        if(figure->family_head_id==-1)continue;
        auto* family=static_cast<df::familyst*>(lookup(figure->family_head_id,&world->family_info.family));
        if(!family)continue;
        for(const auto* claim:family->claims){
            if(!claim || claim->artifact!=id || claim->renounced_heid!=-1)continue;
            if(df::historical_figure::find(figure->family_head_id) &&
               (int32_t(claim->type)==1 || int32_t(claim->type)==2)){
                figureName(figure->id);text+=literal(int32_t(claim->type)==1?0x162bfd8:0x162be80);
            }
            break;
        }
        if(!text.empty())break;
    }
    if(text.size()>16384)return std::nullopt;
    return text;
}
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
