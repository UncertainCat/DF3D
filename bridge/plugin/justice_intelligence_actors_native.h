#pragma once
#include "df/world.h"
#include "df/plotinfost.h"
#include "df/historical_entity.h"
#include "df/historical_figure.h"
#include "df/evidence_repositoryst.h"
#include "df/evidence_hf_filest.h"
#include "df/identity.h"
#include <algorithm>
#include <optional>
#include <string>
#include <vector>
namespace df3d_justice {
struct IntelligenceActor {int32_t historicalFigure=-1,identity=-1;std::string name,searchName;std::vector<int32_t> aliases;};
// Isolate2b6832's actor membership/name pass from2b6760's mutable organization
// scratch and menu insertion. Names and search normalization still come from DF.
inline bool intelligenceActorsReady(){
    if(!df::global::world || !df::global::plotinfo)return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<const uint8_t*>(&df::global::plotinfo->main.fortress_entity)!=base+0x239a1e8 ||
       reinterpret_cast<const uint8_t*>(&df::global::world->history.figures)!=base+0x24f9d18 ||
       reinterpret_cast<const uint8_t*>(&df::global::world->identities.all)!=base+0x24e7ce8)return false;
    static_assert(offsetof(df::historical_entity,evidence_repository)==0x1358 && offsetof(df::evidence_hf_filest,used_identity)==0x80);
    static const bool pinned=[base]{
        struct Pin {size_t at,length;uint64_t hash;};constexpr Pin pins[]={
            {0x2b6832,0x1d7,UINT64_C(0x11c27b63306d4022)},
            {0x479a20,0x19a,UINT64_C(0x42424319fe0435bd)},
            {0x479845,0x16a,UINT64_C(0x71f172fd7d77b54e)},
            {0xc3a4f0,0x98,UINT64_C(0x90965a9fe84783f6)},
            {0xa946e0,0x7c2,UINT64_C(0xdbc3db5f052419ee)},
            {0x52cee0,0x19e,UINT64_C(0xc25c2d8a6eb9fcac)},
        };
        for(const auto& p:pins){uint64_t hash=UINT64_C(14695981039346656037);for(size_t i=0;i<p.length;++i){hash^=base[p.at+i];hash*=UINT64_C(1099511628211);}if(hash!=p.hash)return false;}return true;
    }();return pinned;
}
inline std::optional<std::vector<IntelligenceActor>> intelligenceActors(std::string query={}){
    if(!intelligenceActorsReady() || query.size()>512)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto* entity=df::global::plotinfo->main.fortress_entity;std::vector<IntelligenceActor> result;
    if(!entity || !entity->evidence_repository)return result;
    const auto& files=entity->evidence_repository->hf_file;if(files.size()>65536)return std::nullopt;
    const auto normalize=reinterpret_cast<void(*)(std::string*)>(base+0x52cee0);normalize(&query);
    const auto name=[base](const df::language_name& source){auto owned=source;std::string value;reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&owned,&value,true,false);return value;};
    for(const auto* file:files){
        if(!file || file->used_identity.size()>65536)return std::nullopt;
        const auto* figure=df::historical_figure::find(file->hfid);if(!figure)continue;
        IntelligenceActor row;row.historicalFigure=file->hfid;row.aliases=file->used_identity;
        if(file->flags.bits.basic_name_attached_to_visual)row.name=figure->name.has_name?name(figure->name):"Nameless";
        else if(!row.aliases.empty()){
            auto* identity=df::identity::find(row.aliases.front());row.name="Nameless";
            if(identity){row.identity=identity->id;auto owned=*identity;
                const auto* source=reinterpret_cast<const df::language_name*(*)(df::identity*)>(base+0xc3a4f0)(&owned);
                if(source && source->has_name)row.name=name(*source);
            }
        }else row.name="Unidentified";
        if(row.name.size()>16384)return std::nullopt;
        row.searchName=row.name;normalize(&row.searchName);
        if(row.searchName.find(query)!=std::string::npos)result.push_back(std::move(row));
    }
    //479a20 inserts after equal normalized names, preserving evidence order.
    std::stable_sort(result.begin(),result.end(),[](const auto& a,const auto& b){return a.searchName<b.searchName;});
    return result;
}
}
