#pragma once
#include "justice_intelligence_graph_native.h"
#include "management_util.h"
#include "MiscUtils.h"
namespace df3d_justice {
struct IntelligenceGraphRead {
    df3d::mirror::JusticeOutcome outcome=df3d::mirror::JusticeOutcome::Rejected;
    df3d::mirror::JusticeGraphKind kind=df3d::mirror::JusticeGraphKind::None;
    uint64_t revision=0;uint32_t total=0,offset=0,count=0;
    IntelligenceGraph facts;
    std::vector<uint32_t> nodeOffsets;
};
inline IntelligenceGraphRead readIntelligenceGraph(const df3d::mirror::JusticeRequest& q){
    namespace m=df3d::mirror;
    IntelligenceGraphRead refused;
    try {
        auto facts=intelligenceGraph();if(!facts)return refused;
        IntelligenceGraphRead result;result.kind=q.graph_kind();result.facts=std::move(*facts);
        uint64_t hash=UINT64_C(14695981039346656037);
        const auto number=[&](uint64_t n){for(unsigned i=0;i<8;++i){hash^=uint8_t(n>>(8*i));hash*=UINT64_C(1099511628211);}};
        const auto text=[&](std::string& value){value=DF2UTF(value);if(value.size()>16384)throw std::runtime_error("intelligence caption limit");number(value.size());for(unsigned char c:value){hash^=c;hash*=UINT64_C(1099511628211);}};
        const auto ids=[&](const auto& values){number(values.size());for(auto id:values)number(uint32_t(id));};
        number(result.facts.actors.size());
        for(auto& row:result.facts.actors){number(uint32_t(row.historicalFigure));number(uint32_t(row.identity));text(row.name);ids(row.aliases);number(uint32_t(row.principalOrganization));ids(row.organizations);ids(row.plots);number(row.lines.size());for(auto& line:row.lines)text(line);}
        number(result.facts.organizations.size());uint32_t nodes=0;
        for(auto& row:result.facts.organizations){
            result.nodeOffsets.push_back(nodes);nodes+=uint32_t(row.nodes.size());text(row.name);number(uint32_t(row.principalActor));number(row.nodes.size());
            for(auto& node:row.nodes){number(uint32_t(node.actor));number(uint32_t(node.parent));number(uint32_t(node.sort));number(uint32_t(node.tier));text(node.label);text(node.name);text(node.status);number(uint16_t(node.foreground));number(uint16_t(node.background));number(uint8_t(node.bright));}
        }
        result.nodeOffsets.push_back(nodes);number(result.facts.plots.size());
        for(auto& row:result.facts.plots){number(uint32_t(row.agreement));number(uint32_t(row.master));text(row.name);number(uint32_t(row.organization));}
        result.revision=(hash&INT64_MAX)?hash&INT64_MAX:1;
        if(q.expected_list_revision() && q.expected_list_revision()!=result.revision){refused.outcome=m::JusticeOutcome::Stale;return refused;}
        const std::array<uint32_t,4> totals{uint32_t(result.facts.actors.size()),uint32_t(result.facts.organizations.size()),uint32_t(result.facts.plots.size()),nodes};
        const auto kind=size_t(result.kind);if(kind<1 || kind>4)return refused;
        result.total=totals[kind-1];result.offset=q.offset();
        if(result.offset>result.total){refused.outcome=m::JusticeOutcome::Stale;return refused;}
        size_t bytes=256;
        for(size_t i=result.offset;i<result.total && result.count<q.limit();++i){
            size_t cost=0;
            if(result.kind==m::JusticeGraphKind::Actors){const auto& row=result.facts.actors[i];cost=128+row.name.size()+4*(row.aliases.size()+row.organizations.size()+row.plots.size());for(const auto& line:row.lines)cost+=16+line.size();}
            else if(result.kind==m::JusticeGraphKind::Organizations)cost=96+result.facts.organizations[i].name.size();
            else if(result.kind==m::JusticeGraphKind::Plots)cost=64+result.facts.plots[i].name.size();
            else {const auto org=size_t(std::upper_bound(result.nodeOffsets.begin(),result.nodeOffsets.end(),uint32_t(i))-result.nodeOffsets.begin()-1);const auto& node=result.facts.organizations[org].nodes[i-result.nodeOffsets[org]];cost=128+node.label.size()+node.name.size()+node.status.size();}
            if(bytes+cost>384*1024)break;bytes+=cost;++result.count;
        }
        if(result.offset<result.total && !result.count)return refused;
        result.outcome=m::JusticeOutcome::None;return result;
    }catch(const std::exception&){return refused;}
}
inline flatbuffers::Offset<df3d::mirror::JusticeGraphPage> encodeIntelligenceGraph(flatbuffers::FlatBufferBuilder& b,const IntelligenceGraphRead& page){
    namespace m=df3d::mirror;
    std::vector<flatbuffers::Offset<m::JusticeGraphActor>> actors;
    std::vector<flatbuffers::Offset<m::JusticeGraphOrganization>> organizations;
    std::vector<flatbuffers::Offset<m::JusticeGraphPlot>> plots;
    std::vector<flatbuffers::Offset<m::JusticeGraphNode>> nodes;
    for(size_t i=page.offset;i<size_t(page.offset)+page.count;++i){
        if(page.kind==m::JusticeGraphKind::Actors){const auto& row=page.facts.actors[i];actors.push_back(m::CreateJusticeGraphActor(b,row.historicalFigure,row.identity,b.CreateString(row.name),b.CreateVector(row.aliases),row.principalOrganization,b.CreateVector(row.organizations),b.CreateVector(row.plots),b.CreateVectorOfStrings(row.lines)));}
        else if(page.kind==m::JusticeGraphKind::Organizations){const auto& row=page.facts.organizations[i];organizations.push_back(m::CreateJusticeGraphOrganization(b,b.CreateString(row.name),row.principalActor,page.nodeOffsets[i],uint32_t(row.nodes.size())));}
        else if(page.kind==m::JusticeGraphKind::Plots){const auto& row=page.facts.plots[i];plots.push_back(m::CreateJusticeGraphPlot(b,row.agreement,row.master,b.CreateString(row.name),row.organization));}
        else {const auto org=size_t(std::upper_bound(page.nodeOffsets.begin(),page.nodeOffsets.end(),uint32_t(i))-page.nodeOffsets.begin()-1);const auto& node=page.facts.organizations[org].nodes[i-page.nodeOffsets[org]];
            nodes.push_back(m::CreateJusticeGraphNode(b,uint32_t(org),node.actor,node.parent<0?-1:int32_t(page.nodeOffsets[org])+node.parent,node.sort,node.tier,b.CreateString(node.label),b.CreateString(node.name),b.CreateString(node.status),node.foreground,node.background,node.bright));}
    }
    return m::CreateJusticeGraphPage(b,page.kind,uint32_t(page.facts.actors.size()),uint32_t(page.facts.organizations.size()),uint32_t(page.facts.plots.size()),page.nodeOffsets.back(),b.CreateVector(actors),b.CreateVector(organizations),b.CreateVector(plots),b.CreateVector(nodes));
}
}
