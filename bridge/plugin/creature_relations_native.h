#pragma once
#include "creature_items_native.h"
#include "zone_native.h"
#include "df/historical_figure.h"
#include "df/historical_figure_info.h"
#include "df/historical_figure_relationships.h"
#include "df/histfig_hf_link.h"
#include "df/unit_relationship_type.h"
#include "df/relationship_profile_hf_visualst.h"
namespace df3d_creature {
// Inputs for the Relations reader. Ordering/merging and row presentation belong
// to that reader; these routines never construct or borrow a native UI sheet.
struct FamilyRelation {
    int32_t historicalFigureId=-1;
    int16_t type=-1;
    bool nativeFlag=false;
    std::string description;
};
struct SocialRelation {int32_t type=-1,priority=0;};
inline bool relationshipSemanticsReady() {
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1a3979,0x1325,UINT64_C(0xac67f2e5dd551e02)},
            {0x1a5a7c,0xcc,UINT64_C(0xeff404e272001458)},
            {0x176deb,0x1da7,UINT64_C(0x99b1f1d1223c7687)},
            {0x19f4a8,0x248,UINT64_C(0x8ee36f1066e3a9ad)},
            {0xa94030,0x6a1,UINT64_C(0xd81db68b3c9b33d2)},
            {0xbb37d0,0x3397,UINT64_C(0xc9f542bee179d6b8)},
            {0x75a580,0x7b1,UINT64_C(0x8d20f1ebd18ed86e)},
            {0x52d650,0x2b4,UINT64_C(0x9e8023d09def7af9)},
            {0x2bf110,0x4d8,UINT64_C(0xbca73649e98a667a)},
        };
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();
    return ready;
}
inline std::optional<std::vector<FamilyRelation>> nativeFamilyRelations(df::historical_figure* figure) {
    if(!figure || !relationshipSemanticsReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    std::vector<int32_t> ids;std::vector<int16_t> types;std::vector<bool> nativeFlag;
    // Unit wrapper13b2cb0 calls bb37d0 after resolving its HF lookup cache.
    // Resolve the HF outside that wrapper and supply three owned output vectors.
    reinterpret_cast<void(*)(df::historical_figure*,std::vector<int32_t>*,std::vector<int16_t>*,std::vector<bool>*)>(base+0xbb37d0)(figure,&ids,&types,&nativeFlag);
    if(ids.size()!=types.size() || ids.size()!=nativeFlag.size())return std::nullopt;
    std::vector<FamilyRelation> rows;rows.reserve(ids.size());
    for(size_t i=0;i<ids.size();++i) {
        FamilyRelation row;row.historicalFigureId=ids[i];row.type=types[i];row.nativeFlag=nativeFlag[i];
        // Native176f0a passes false,false, then capitalizes the owned text.
        reinterpret_cast<void(*)(int16_t,std::string*,bool,bool)>(base+0x75a580)(row.type,&row.description,false,false);
        reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&row.description);
        if(row.description.size()>1024)return std::nullopt;
        rows.push_back(std::move(row));
    }
    return rows;
}
inline std::optional<SocialRelation> nativeSocialRelation(const df::relationship_profile_hf_visualst& source) {
    if(!relationshipSemanticsReady())return std::nullopt;
    static_assert(offsetof(df::relationship_profile_hf_visualst,meet_count)==0x68);
    // Native1a470d uses the same classifier for both its kind and sort priority.
    // The routine reads only this record and writes the supplied priority.
    auto owned=source;SocialRelation result;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    result.type=reinterpret_cast<int32_t(*)(df::relationship_profile_hf_visualst*,int32_t*)>(base+0x2bf110)(&owned,&result.priority);
    return result;
}

struct RelationCandidate {
    int32_t historicalFigureId=-1,unitId=-1,priority=0;
    int16_t familyType=-1,socialType=-1;
    std::string familyDescription;
};
inline std::optional<std::vector<RelationCandidate>> nativeRelationCandidates(df::unit* unit) {
    if(!unit || !df::global::world || !relationshipSemanticsReady())return std::nullopt;
    std::vector<RelationCandidate> rows;
    auto* figure=df::historical_figure::find(unit->hist_figure_id);
    const auto seenFigure=[&](int32_t id){return std::any_of(rows.begin(),rows.end(),[id](const auto& row){return row.historicalFigureId==id;});};
    const auto append=[&](df::historical_figure* other,int16_t family,int16_t social,int32_t priority,std::string description={}) {
        if(!other || seenFigure(other->id))return;
        RelationCandidate row;row.historicalFigureId=other->id;row.familyType=family;row.socialType=social;row.priority=priority;row.familyDescription=std::move(description);
        if(auto* active=df::unit::find(other->unit_id))row.unitId=active->id;
        rows.push_back(std::move(row));
    };
    if(figure) {
        auto family=nativeFamilyRelations(figure);if(!family)return std::nullopt;
        // Inline native1a3ac9..1a3baa priority switch, in family-enum order.
        constexpr int32_t priority[]={10000,9900,9900,15000,15000,15000,12500,12400,12300,12299,12298,12297,12296,12295,12294,12293,12200,12100,12200,12500,12400,12300,12299,12298,12297,12296,12295,12294,12293,12200,12100,12200,12500,12400,12300,12299,12298,12297,12296,12295,12294,12293,12200,12100,12200,9800,9700,9600,9500,9800,9800,9800,9700,9700,9700,9600,9600,9600,9300,9500,9400,9350,9340,9600,9750,9500,9500,9500,9400,9400,9400,9400};
        for(auto& relation:*family) {
            if(relation.type<0 || size_t(relation.type)>=std::size(priority))continue;
            append(df::historical_figure::find(relation.historicalFigureId),relation.type,-1,priority[relation.type],std::move(relation.description));
        }
        // Native1a3e90..1a3f0e retains these non-family HF links, after dedup.
        for(auto* link:figure->histfig_links) {
            if(!link)continue;int16_t type=-1;int32_t rank=0;
            switch(int(link->getType())) {
                case 4:type=15;rank=5000;break;case 5:type=10;rank=6000;break;
                case 8:type=39;rank=4005;break;case 9:type=40;rank=4004;break;
                case 10:type=41;rank=3000;break;case 11:type=42;rank=4003;break;
                case 12:type=43;rank=4002;break;default:continue;
            }
            append(df::historical_figure::find(link->target_hf),-1,type,rank);
        }
    }
    // Fortress creature sheets add owned pets from the active unit vector.
    // The historical-figure-only sheet omits this pass; this reader takes a unit.
    for(auto* pet:df::global::world->units.active) {
        if(!pet || pet->relationship_ids[df::unit_relationship_type::PetOwner]!=unit->id)continue;
        if(std::any_of(rows.begin(),rows.end(),[pet](const auto& row){return row.unitId==pet->id;}))continue;
        RelationCandidate row;row.unitId=pet->id;row.historicalFigureId=pet->hist_figure_id;row.socialType=51;row.priority=501;rows.push_back(std::move(row));
    }
    if(figure && figure->info && figure->info->relationships) {
        // Only visual profiles with a positive meet count are appended by native;
        // historical profiles supply details for existing rows, not extra rows.
        for(const auto* relation:figure->info->relationships->hf_visual) {
            if(!relation || relation->meet_count<=0 || seenFigure(relation->histfig_id))continue;
            auto kind=nativeSocialRelation(*relation);if(!kind)return std::nullopt;
            append(df::historical_figure::find(relation->histfig_id),-1,int16_t(kind->type),kind->priority);
        }
    }
    // Native inserts before the first strictly lower score; ties retain input order.
    std::stable_sort(rows.begin(),rows.end(),[](const auto& a,const auto& b){return a.priority>b.priority;});
    return rows;
}

struct RelationRow : RelationCandidate {
    std::string caption,description;
    std::optional<df3d_area::ZoneOwnerNameColor> nameColor;
    int32_t descriptionColor=15;
};
inline std::optional<std::vector<RelationRow>> nativeRelations(df::unit* unit) {
    auto candidates=nativeRelationCandidates(unit);
    if(!candidates || !inventoryDescriptionReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    InventoryRandomRestore restore(base);
    auto* figure=df::historical_figure::find(unit->hist_figure_id);
    std::vector<RelationRow> rows;rows.reserve(candidates->size());
    // Native renderer176deb..178b92 selects these installed literal addresses.
    constexpr size_t labels[]={0x15ffe90,0x15ffe84,0x15ffe7c,0x15ffe74,0x0,0x0,0x0,0x0,0x0,0x0,0x15ffe6c,0x0,0x15ffe64,0x0,0x0,0x0,0x1600118,0x1600100,0x15ffe5c,0x16000f4,0x1600028,0x1600010,0x1600270,0x1600260,0x1600248,0x1600230,0x1600228,0x1600208,0x16001f0,0x16001e0,0x16001c8,0x16000a8,0x16000b8,0x16001b8,0x16000d0,0x1600090,0x1600068,0x1600058,0x1600040,0x16001ac,0x16001a0,0x1600190,0x1600180,0x1600168,0x1600150,0x1600380,0x1600378,0x1600360,0x1600338,0x160032c,0x1600348,0x15ffe9c,0x16000e8,0x1600078};
    constexpr int32_t colors[]={10,12,11,11,15,15,15,15,15,15,12,15,11,15,13,14,7,7,15,11,12,13,14,7,12,13,15,14,13,13,15,12,12,15,13,11,11,11,11,14,14,11,6,6,12,12,15,11,14,13,13,10,13,11};
    constexpr int32_t familyColors[]={11,11,11,12,12,12,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,3,3,3,3,3,3,3,11,11,11,11,11,11,3,3,3,3,3,3,3,11,11,11,11,11,11,3};
    constexpr size_t friends[]={0x15ffe48,0x15ffe38,0x15ffe28,0x0,0x0,0x0,0x1600000,0x15ffff0,0x15fffe0};
    constexpr size_t hates[]={0x15fff58,0x0,0x0,0x0,0x0,0x0,0x15fffa8,0x15fff98,0x15fff70,0x15fff68,0x15fff88,0x15fff40};
    for(auto& candidate:*candidates) {
        RelationRow row;static_cast<RelationCandidate&>(row)=std::move(candidate);
        auto* target=df::historical_figure::find(row.historicalFigureId);
        if(auto* active=df::unit::find(row.unitId)) {
            if(!active->body.body_plan)return std::nullopt;
            InventoryDescriptionContext owned(*active);
            reinterpret_cast<void(*)(df::unit*,std::string*,bool)>(base+0x1330c30)(owned.unit(),&row.caption,false);
            auto color=df3d_area::nativeZoneOwnerNameColor(*active);if(!color)return std::nullopt;
            row.nameColor=*color;
        }else if(target) {
            auto owned=target->name;
            reinterpret_cast<void(*)(df::language_name*,std::string*)>(base+0xa94030)(&owned,&row.caption);
        }
        size_t address=0;
        if(row.familyType>=0 && size_t(row.familyType)<std::size(familyColors)) {
            row.description=std::move(row.familyDescription);row.descriptionColor=familyColors[row.familyType];
        }else if(row.socialType>=0 && size_t(row.socialType)<std::size(labels)) {
            address=labels[row.socialType];row.descriptionColor=colors[row.socialType];
            if(row.socialType==13 || row.socialType==14) {
                const df::relationship_profile_hf_visualst* profile=nullptr;
                if(figure && figure->info && figure->info->relationships)
                    for(const auto* entry:figure->info->relationships->hf_visual)if(entry && entry->histfig_id==row.historicalFigureId){profile=entry;break;}
                const int rank=profile?int(profile->rank):0,love=profile?profile->core.love:0;
                if(row.socialType==13) {
                    if(rank>0 && size_t(rank)<std::size(friends))address=friends[rank];
                    if(!address)address=love>=100?0x15fffd0:love>=75?0x15fffc0:0x15fffb8;
                }else {
                    if(rank>=3 && size_t(rank-3)<std::size(hates))address=hates[rank-3];
                    if(!address)address=love<=-100?0x15fff30:love<=-75?0x15fff24:0x15fff18;
                }
            }else if(row.socialType==15)address=target && target->flags.is_set(df::histfig_flags::deity)?0x1600144:target && target->flags.is_set(df::histfig_flags::force)?0x15ed068:0x1600130;
            if(address)row.description=reinterpret_cast<const char*>(base+address);
        }
        if(row.caption.size()>512 || row.description.size()>1024)return std::nullopt;
        rows.push_back(std::move(row));
    }
    return rows;
}
}
