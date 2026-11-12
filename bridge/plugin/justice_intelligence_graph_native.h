#pragma once
#include "justice_intelligence_actors_native.h"
#include "unit_description_native.h"
#include "df/actor_entryst.h"
#include "df/organization_entryst.h"
#include "df/organization_entry_nodest.h"
#include "df/plot_entryst.h"
#include "df/agreement.h"
#include <array>
#include <memory>
#include <stdexcept>

namespace df3d_justice {
struct IntelligenceGraphActor {
    int32_t historicalFigure=-1,identity=-1,principalOrganization=-1;
    std::string name;
    std::vector<int32_t> aliases,organizations,plots;
};
struct IntelligenceGraphNode {
    int32_t actor=-1,parent=-1,sort=0,tier=0,descendants=0;
    std::string label,name,status;
    int16_t foreground=0,background=0;int8_t bright=0;
};
struct IntelligenceGraphOrganization {
    std::string name;int32_t principalActor=-1;
    std::vector<IntelligenceGraphNode> nodes;
};
struct IntelligenceGraphPlot {int32_t agreement=-1,master=-1;std::string name;};
struct IntelligenceGraph {
    std::vector<IntelligenceGraphActor> actors;
    std::vector<IntelligenceGraphOrganization> organizations;
    std::vector<IntelligenceGraphPlot> plots;
};
namespace detail {
// Data-only ABI context for2b6760. No widget, callback, vtable or native menu
// storage is constructed or borrowed. Mode0 avoids width-dependent detail
// formatters in479330; only the three owning base lists are exported.
struct IntelligenceGraphContext {
    std::array<std::byte,0x248> prefix{};
    std::vector<df::actor_entryst*> baseActors;
    std::vector<df::organization_entryst*> baseOrganizations;
    std::vector<df::plot_entryst*> basePlots;
    int32_t mode=0,selected=-1;
    std::string query;
    bool entering=false;std::array<std::byte,7> gap{};
    df::organization_entry_nodest* selectedNode=nullptr;
    int32_t scroll=0;bool scrolling=false;std::array<std::byte,3> gap2{};
    std::vector<df::actor_entryst*> valueActors;
    std::vector<df::organization_entryst*> valueOrganizations;
    std::vector<df::plot_entryst*> valuePlots;
    std::vector<df::actor_entryst*> actors;
    std::vector<df::organization_entryst*> organizations;
    std::vector<df::plot_entryst*> plots;
    ~IntelligenceGraphContext(){
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        const auto clear=reinterpret_cast<void(*)(df::curses_text_boxst*)>(base+0xbb9b0);
        for(auto* row:baseActors){clear(&row->main_text_box);delete row;}
        for(auto* row:baseOrganizations){for(auto* node:row->node)delete node;clear(&row->main_text_box);delete row;}
        for(auto* row:basePlots)delete row;
    }
};
static_assert(offsetof(IntelligenceGraphContext,baseActors)==0x248);
static_assert(offsetof(IntelligenceGraphContext,baseOrganizations)==0x260);
static_assert(offsetof(IntelligenceGraphContext,basePlots)==0x278);
static_assert(offsetof(IntelligenceGraphContext,mode)==0x290);
static_assert(offsetof(IntelligenceGraphContext,query)==0x298);
static_assert(offsetof(IntelligenceGraphContext,selectedNode)==0x2c0);
static_assert(offsetof(IntelligenceGraphContext,valueActors)==0x2d0);
static_assert(offsetof(IntelligenceGraphContext,plots)==0x348);
static_assert(sizeof(df::actor_entryst)==0xf8 && sizeof(df::organization_entryst)==0xa0);
static_assert(sizeof(df::plot_entryst)==0x90 && sizeof(df::organization_entry_nodest)==0x88);
struct IntelligenceEntityScope {
    df::historical_entity*& slot;df::historical_entity* original;
    explicit IntelligenceEntityScope(df::historical_entity* owned):slot(df::global::plotinfo->main.fortress_entity),original(slot){slot=owned;}
    ~IntelligenceEntityScope(){slot=original;}
    IntelligenceEntityScope(const IntelligenceEntityScope&)=delete;
    IntelligenceEntityScope& operator=(const IntelligenceEntityScope&)=delete;
};
template<class T> int32_t graphIndex(const std::vector<T*>& values,const T* pointer){
    if(!pointer)return -1;
    const auto found=std::find(values.begin(),values.end(),pointer);
    if(found==values.end())throw std::runtime_error("unowned intelligence graph edge");
    return static_cast<int32_t>(found-values.begin());
}
}
inline bool intelligenceGraphReady(){
    if(!intelligenceActorsReady() || !df3d_creature::inventoryDescriptionReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<const uint8_t*>(&df::global::world->agreements.all)!=base+0x24e7e98)return false;
    static const bool pinned=[base]{
        struct Pin {size_t at,length;uint64_t hash;};constexpr Pin pins[]={
            {0x2b6760,0x28e0,UINT64_C(0x43d5e3c0f8cfd5c2)},
            {0x479bc0,0x19a,UINT64_C(0xe0b23c86f6bd257c)},
            {0x479d60,0x195,UINT64_C(0xb434bf9a9c1eb930)},
            {0x479330,0x6eb,UINT64_C(0xd9b29dfbbf6a9b96)},
            {0xbb9b0,0x80,UINT64_C(0xcc2c8d1b49288e49)},
        };
        for(const auto& p:pins){uint64_t hash=UINT64_C(14695981039346656037);for(size_t i=0;i<p.length;++i){hash^=base[p.at+i];hash*=UINT64_C(1099511628211);}if(hash!=p.hash)return false;}return true;
    }();return pinned;
}
// Safe-point only. The collector writes evidence temp_flags, so both repository
// vectors and every file are cloned. Its global semantic entity lookup is
// redirected only for this synchronous call and restored before export.
inline std::optional<IntelligenceGraph> intelligenceGraph(){
    if(!intelligenceGraphReady())return std::nullopt;
    const auto* source=df::global::plotinfo->main.fortress_entity;
    if(!source || !source->evidence_repository)return IntelligenceGraph{};
    const auto& repository=*source->evidence_repository;
    constexpr size_t limit=65536;
    if(repository.hf_file.size()>limit || repository.foiled_plot_agreements.size()>limit || repository.known_events.size()>limit)return std::nullopt;
    try {
        auto ownedEntity=std::make_unique<df::historical_entity>(*source);
        auto ownedRepository=repository;
        std::vector<std::unique_ptr<df::evidence_hf_filest>> files;size_t evidenceCount=0;
        ownedRepository.hf_file.clear();
        for(const auto* file:repository.hf_file){
            if(!file || file->evidence.size()>limit || file->agreement.size()>limit || file->evidence_flag.size()>limit ||
               file->wanted_crime.size()>limit || file->wanted_crime_agreement.size()>limit || file->used_identity.size()>limit)return std::nullopt;
            evidenceCount+=file->evidence.size()+file->agreement.size()+file->evidence_flag.size()+file->wanted_crime.size()+file->wanted_crime_agreement.size()+file->used_identity.size();
            if(evidenceCount>1048576)return std::nullopt;
            files.push_back(std::make_unique<df::evidence_hf_filest>(*file));ownedRepository.hf_file.push_back(files.back().get());
        }
        ownedEntity->evidence_repository=&ownedRepository;
        detail::IntelligenceGraphContext context;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        {
            df3d_creature::InventoryRandomRestore random(base);
            detail::IntelligenceEntityScope entity(ownedEntity.get());
            reinterpret_cast<void(*)(df::world*,void*,detail::IntelligenceGraphContext*)>(base+0x2b6760)(df::global::world,nullptr,&context);
        }
        if(context.baseActors.size()>limit || context.baseOrganizations.size()>limit || context.basePlots.size()>limit)return std::nullopt;
        IntelligenceGraph result;size_t textBytes=0,nodeCount=0;
        const auto text=[&](const std::string& value){textBytes+=value.size();if(value.size()>16384 || textBytes>4*1024*1024)throw std::runtime_error("intelligence text limit");return value;};
        for(const auto* actor:context.baseActors){
            IntelligenceGraphActor row;row.historicalFigure=actor->hf?actor->hf->id:-1;row.identity=actor->iden?actor->iden->id:-1;
            row.name=text(actor->list_name);row.aliases=actor->alias_identity_id;
            row.principalOrganization=detail::graphIndex(context.baseOrganizations,actor->principle_org);
            for(auto* org:actor->associated_org)row.organizations.push_back(detail::graphIndex(context.baseOrganizations,org));
            for(auto* plot:actor->associated_plot)row.plots.push_back(detail::graphIndex(context.basePlots,plot));
            result.actors.push_back(std::move(row));
        }
        for(const auto* org:context.baseOrganizations){
            IntelligenceGraphOrganization row;row.name=text(org->list_name);row.principalActor=detail::graphIndex(context.baseActors,org->principle_actor_entry);
            nodeCount+=org->node.size();if(nodeCount>limit)return std::nullopt;
            for(const auto* node:org->node){
                IntelligenceGraphNode value;value.actor=detail::graphIndex(context.baseActors,node->actor_entry);value.parent=detail::graphIndex(org->node,node->master);
                value.sort=node->sort_id;value.tier=node->tier;value.descendants=node->descendant_sum;
                value.label=text(node->label);value.name=text(node->name);value.status=text(node->status);
                value.foreground=node->fcol;value.background=node->bcol;value.bright=node->br;row.nodes.push_back(std::move(value));
            }
            result.organizations.push_back(std::move(row));
        }
        for(const auto* plot:context.basePlots){
            result.plots.push_back({plot->agreement?plot->agreement->id:-1,plot->master_hfid,text(plot->list_name)});
            // organization_name is clipped using native window width. It is
            // not a semantic input to this graph and must not cross the bridge.
        }
        return result;
    }catch(const std::exception&){return std::nullopt;}
}
}
