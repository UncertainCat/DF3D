#pragma once
#include "creature_office_native.h"
#include "df/historical_figure_info.h"
#include "df/reputation_profilest.h"
#include "df/entity_personal_reputation_profilest.h"
#include "df/entity_focusst.h"
#include "df/squad.h"
namespace df3d_creature {
struct GroupRow {
    int32_t entityId=-1,linkType=-1,positionId=-1,assignmentId=-1,reputation=-1,reputationLevel=0;
    bool spouse=false;
    std::string caption,typeCaption,role;
};
inline bool groupsReady() {
    static const bool ready=[] {
        if(!df3d_production::farmFunctions())return false;
        auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
        {0x1a4cbb,0x6ae,UINT64_C(0xd4a4fd7a5e666c47)},
        {0x1a5b48,0x26,UINT64_C(0x0863e2a40d7021af)},
        {0x178f51,0x1cfb,UINT64_C(0xc9d3d1383c096c51)},
        {0x19f6f0,0xe8,UINT64_C(0x57c05a237016cc18)},
        {0xa946e0,0x7c2,UINT64_C(0xdbc3db5f052419ee)},
        {0x52d650,0x2b4,UINT64_C(0x9e8023d09def7af9)},
        {0x99a3c0,0x113,UINT64_C(0x14b5664261afc791)},
        {0x9bdfb0,0x148,UINT64_C(0x044d2f90a27b9a05)},
        {0xb98d30,0x5f,UINT64_C(0x0b20f43042d158dc)},
        {0x132cc10,0x14a4,UINT64_C(0x32cb3990ee45026b)},
        {0x30cea0,0xc3,UINT64_C(0x47a07e027acb5ada)},
        {0x30cf70,0x174,UINT64_C(0x6f623c8eaf55f9c1)},
        {0x1bb330,0xcc,UINT64_C(0x22cd601a57c49cb0)},
        {0x1600280,0xb00,UINT64_C(0x4d9a61a048b5be0f)},
        {0x15ec868,0xd,UINT64_C(0x17ca32928a8b2800)},
        {0x15ec8d8,0x9,UINT64_C(0x23d957f99b5eb8f2)},
        {0x15ec950,0x8,UINT64_C(0xdd808e958e26a920)},
        {0x15ff7a8,0x8,UINT64_C(0x70a902be1fdce211)},
        {0x15ffd10,0xa,UINT64_C(0x73efc1b07144b721)},
        {0x15ec998,0x9,UINT64_C(0xa21c9490897e4233)},
        {0x15ec958,0x6,UINT64_C(0xe24f1ca51e959991)},
        {0x15ec960,0x9,UINT64_C(0x7f14ecdecd66f798)},
        {0x15eca08,0x8,UINT64_C(0x4f75c23966076cdc)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();return ready;
}
// Groups has no standalone list producer. Mirror inline1a4cbb..1a5369 over
// semantic records, with owned rows; never read the native sheet's vectors.
inline std::optional<std::vector<GroupRow>> nativeGroups(df::unit* unit) {
    if(!unit || !groupsReady() || !df::global::plotinfo)return std::nullopt;
    std::vector<GroupRow> rows;
    auto* hf=df::historical_figure::find(unit->hist_figure_id);if(!hf)return rows;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto literal=[&](size_t rva){return std::string(reinterpret_cast<const char*>(base+rva));};
    const auto capitalize=[&](std::string& s){reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&s);};
    const auto findId=[](const auto& values,int32_t id){
        using Pointer=typename std::decay_t<decltype(values)>::value_type;
        for(auto* value:values)if(value && value->id==id)return value;
        return Pointer(nullptr);
    };
    const auto links=[&](df::historical_figure* source,bool spouse) {
        for(auto* link:source->entity_links) {
            if(!link)continue;
            const int kind=int(link->getType());if(spouse && kind!=10)continue;
            auto* entity=df::historical_entity::find(link->entity_id);if(!entity)continue;
            GroupRow row;row.entityId=entity->id;row.linkType=kind;row.spouse=spouse;
            auto* assignment=findId(entity->positions.assignments,link->getPosition());
            if(assignment) {
                auto* position=findId(entity->positions.own,assignment->position_id);if(!position)continue;
                if(spouse && position->spouse[0].empty() && position->spouse_female[0].empty() && position->spouse_male[0].empty())continue;
                row.positionId=position->id;row.assignmentId=assignment->id;
            } else if(spouse)continue;
            else if(kind==13 || kind==14) {
                auto* squad=df::squad::find(link->getSquadId());if(!squad)continue;
                row.positionId=squad->leader_position;row.assignmentId=squad->leader_assignment;
            }
            rows.push_back(std::move(row));
        }
    };
    links(hf,false);
    // HF overload reads relationship records only; no unit lookup cache writes.
    const auto spouseId=reinterpret_cast<int32_t(*)(df::historical_figure*,int16_t)>(base+0xb98d30)(hf,2);
    if(auto* spouse=df::historical_figure::find(spouseId))links(spouse,true);
    constexpr size_t reputationText[30][5]={
    {0x1600528,0x1600518,0x16000f4,0x16004f0,0x16004d0},
    {0x0,0x0,0x0,0x0,0x0},
    {0x16005d0,0x16005c0,0x16005b0,0x1600590,0x1600578},
    {0x1600560,0x1600548,0x1600538,0x16007e0,0x16007c8},
    {0x0,0x0,0x0,0x0,0x0},
    {0x0,0x0,0x0,0x0,0x0},
    {0x1600750,0x1600740,0x1600730,0x1600710,0x16006f8},
    {0x16006e0,0x16006c8,0x16006b8,0x1600698,0x1600980},
    {0x0,0x0,0x0,0x0,0x0},
    {0x0,0x0,0x0,0x0,0x0},
    {0x0,0x0,0x0,0x0,0x0},
    {0x1600968,0x1600950,0x1600938,0x1600910,0x16008f0},
    {0x16008d8,0x16008c8,0x16008b8,0x1600898,0x1600880},
    {0x1600640,0x1600630,0x1600620,0x1600600,0x16005e8},
    {0x16003b0,0x1600398,0x1600688,0x1600668,0x1600650},
    {0x1600868,0x1600850,0x1600838,0x1600818,0x1600800},
    {0x1600428,0x1600410,0x1600400,0x16003e0,0x16003c8},
    {0x0,0x0,0x0,0x0,0x0},
    {0x0,0x0,0x0,0x0,0x0},
    {0x0,0x0,0x0,0x0,0x0},
    {0x0,0x0,0x0,0x0,0x0},
    {0x0,0x0,0x0,0x0,0x0},
    {0x0,0x0,0x0,0x0,0x0},
    {0x16007b0,0x16007a0,0x1600790,0x1600780,0x1600768},
    {0x1600ba8,0x1600b88,0x1600b68,0x1600b38,0x1600b10},
    {0x1600a20,0x1600a08,0x16009f0,0x16009c8,0x16009a8},
    {0x1600998,0x1600cb0,0x1600ca0,0x1600c80,0x1600c68},
    {0x0,0x0,0x0,0x0,0x0},
    {0x1600ae8,0x1600ac0,0x1600a98,0x1600a68,0x1600a40},
    {0x16004b8,0x16004a0,0x1600480,0x1600458,0x1600440},
    };
    if(hf->info && hf->info->reputation)for(auto* profile:hf->info->reputation->wanted) {
        if(!profile)continue;
        const auto& rep=profile->reputation;if(rep.types.size()!=rep.levels.size())return std::nullopt;
        for(size_t i=0;i<rep.types.size();++i) {
            const int kind=int(rep.types[i]);if(kind<0 || kind>=30 || !reputationText[kind][0] || rep.levels[i]<=0)continue;
            GroupRow row;row.entityId=profile->entity_id;row.reputation=kind;row.reputationLevel=rep.levels[i];rows.push_back(std::move(row));
        }
    }
    constexpr size_t entityTypes[]={0x15ec868,0x1600310,0x1600300,0x16002f0,0x16002e0,0x15ec8d8,0x16002c8,0x15ec950,0x16002b0,0x1600298};
    constexpr size_t linkRoles[]={0,0x1600c38,0x15ffd10,0x1600c50,0x1600c30,0x1600c20,0x15ec998,0x1600c10,0x15ec958,0x15ec960,0,0,0,0,0,0x1600c08,0x1600bf8};
    std::vector<GroupRow> result;result.reserve(rows.size());
    for(auto& row:rows) {
        auto* entity=df::historical_entity::find(row.entityId);if(!entity)continue;
        auto ownedName=entity->name;
        reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&ownedName,&row.caption,true,false);
        capitalize(row.caption);
        const int type=int(entity->type);
        if(type>=0 && type<10)row.typeCaption=literal(entityTypes[type]);
        else if(type==10) {
            int16_t profession=-1;
            for(auto* focus:entity->guild_professions)if(focus && int(focus->type)==0){profession=int16_t(focus->profession);break;}
            if(profession!=-1) {
                std::string plural;bool flag=false;
                static_assert(offsetof(df::plotinfost,race_id)==0x244c);
                using Profession=void(*)(std::string*,std::string*,int16_t,int16_t,bool*,int16_t,bool,bool);
                reinterpret_cast<Profession>(base+0x132cc10)(&row.typeCaption,&plural,profession,df::global::plotinfo->race_id,&flag,-1,true,false);
            } else row.typeCaption=literal(0x160028c);
            row.typeCaption+=literal(0x1600284);capitalize(row.typeCaption);
        }
        if(row.reputation>=0) {
            const int level=row.reputationLevel;
            row.role=literal(reputationText[row.reputation][level>=100?0:level>=75?1:level>=50?2:level>=25?3:4]);
        } else if(row.linkType==0)row.role=literal(type==0?0x15ff7a8:0x1600c48);
        else if(row.linkType==10 || row.linkType==11) {
            auto* position=findId(entity->positions.own,row.positionId);
            if(position) {
                using Title=const std::string*(*)(const df::entity_position*,int8_t,bool,bool);
                if(auto* title=reinterpret_cast<Title>(base+0x99a3c0)(position,hf->sex,false,row.spouse))row.role=*title;
                if(auto* assignment=findId(entity->positions.assignments,row.assignmentId);assignment && position->land_holder>0)
                    reinterpret_cast<bool(*)(df::historical_entity*,df::entity_position_assignment*,std::string*)>(base+0x9bdfb0)(entity,assignment,&row.role);
            }
            if(row.linkType==11)row.role.insert(0,literal(0x15eca08));
        } else if(row.linkType==13 || row.linkType==14) {
            if(auto* position=findId(entity->positions.own,row.positionId))row.role=position->squad[0];
            if(row.linkType==14)row.role.insert(0,literal(0x15eca08));
        } else if(row.linkType>=0 && row.linkType<17 && linkRoles[row.linkType])row.role=literal(linkRoles[row.linkType]);
        capitalize(row.role);result.push_back(std::move(row));
    }
    return result;
}
}
