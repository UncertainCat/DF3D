#pragma once
#include "unit_description_native.h"
#include "creature_office_native.h"
#include "df/unitpropertyplacementst.h"
#include "df/unit_demand.h"
#include "df/mandate.h"
#include "df/building_civzonest.h"
#include "df/building_actual.h"
#include "df/buildingitemst.h"
#include "df/administrators_interfacest.h"
#include "df/noblelistst.h"
#include "df/appointment_candidatest.h"
#include "labor_eligibility_cache.h"
#include "df/nemesis_record.h"
#include "df/entity_position.h"
#include "df/entity_position_assignment.h"
#include "df/world.h"
#include "df/squad.h"
#include "df/language_name.h"
#include "df/plotinfost.h"
#include <optional>
#include <vector>
namespace df3d_nobles {
struct Row {
    int32_t unitId=-1,nemesisId=-1,entityId=-1,positionId=-1,assignmentId=-1,value=0;
    std::string positionName,title,squadCaption,holderCaption;
    bool canAppoint=false,hasRoomAssessment=false;
    // Native severity: -1 absent, 0 fulfilled/export-only, 1 pending, 2 urgent, 3 critical.
    int32_t demandStatus=-1,mandateStatus=-1;
    // Office, bedroom, dining room, tomb; chests, cabinets, weapon racks, armor stands.
    std::array<int32_t,4> requiredRooms{},actualRooms{},requiredFurniture{},actualFurniture{};
};
// Native feed425539..425699 and renderer42712b..42726c inline the same
// appointment gate. No standalone helper exists at these call sites. Evaluate
// those semantic tests against the fresh owned list, never the native menu.
inline std::optional<bool> appointmentAvailable(const df::noblelistst& row,const std::vector<df::noblelistst*>& list) {
    if(!row.ep || !df::global::plotinfo)return std::nullopt;
    const auto& position=*row.ep;
    static_assert(offsetof(df::entity_position,appointed_by)==0x2e0);
    static_assert(offsetof(df::entity_position,appointed_by_civ)==0x2f8);
    static_assert(offsetof(df::entity_position,succession_by_position)==0x310);
    static_assert(offsetof(df::historical_figure,died_year)==0x30);
    if(position.appointed_by.size()!=position.appointed_by_civ.size() || position.appointed_by.size()>65536)return std::nullopt;
    bool allowed=row.enid==df::global::plotinfo->group_id && !position.flags.is_set(df::entity_position_flags::ELECTED);
    if((position.flags.is_set(df::entity_position_flags::SUCCESSION_BY_HEIR) || !position.succession_by_position.empty()) && row.epp && row.epp->histfig!=-1)allowed=false;
    if(allowed && !position.appointed_by_civ.empty()) {
        allowed=false;
        for(const auto* other:list) {
            if(!other || !other->ep)return std::nullopt;
            if(other==&row)continue;
            for(size_t i=0;i<position.appointed_by.size();++i) {
                if(position.appointed_by_civ[i]==other->enid && position.appointed_by[i]==other->ep->id && other->un)allowed=true;
            }
        }
    }
    if(!row.un && row.nem) {
        if(!row.nem->figure)return std::nullopt;
        if(row.nem->figure->died_year==-1)allowed=false;
    }
    return allowed;
}
// Native421f30 reads simulation entities, units, historical figures and positions.
// All overview rows, parallel identity vectors and location summaries belong to
// this private context. Never invoke the UI opener424280 or feed424330.
inline bool ready() {
    if(!df::global::world || !df::global::plotinfo || !df3d_creature::inventoryDescriptionReady())return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    // Bind observed RIP operands to semantic world storage, never menu aliases.
    const auto at=[base](const void* address,size_t rva){return address==base+rva;};
    if(!at(&df::global::world->history.figures,0x24f9d18) ||
       !at(&df::global::world->units.all,0x23e50b0) ||
       !at(&df::global::world->units.active,0x23e50c8) ||
       !at(&df::global::world->nemesis.all,0x23e5178) ||
       !at(&df::global::world->entities.all,0x23d17f8) ||
       !at(&df::global::world->mandates.all,0x23d17e0) ||
       !at(&df::global::plotinfo->main.fortress_entity,0x239a1e8))return false;
    if(df::global::world->units.all.size()>1048576 || df::global::world->history.figures.size()>1048576)return false;
    static_assert(sizeof(df::noblelistst)==0x30);
    static_assert(offsetof(df::noblelistst,upplist)==0x10);
    static_assert(offsetof(df::noblelistst,value)==0x2c);
    static_assert(offsetof(df::administrators_interfacest,spec_prof)==0x18);
    static_assert(offsetof(df::administrators_interfacest,candidate)==0x98);
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
        {0x134a920,0x2ee,UINT64_C(0x95c1b7403988ffe4)},
        {0xaca720,0x7a,UINT64_C(0x12b032d63e998c99)},
        {0x42845a,0x18a,UINT64_C(0x1765d28735cd452e)},
        {0x134a5e0,0x246,UINT64_C(0xd73a74b32f6acbe4)},
        {0xba0a0,0xa8,UINT64_C(0xcf6b2a7b534d3331)},
        {0x134c0c0,0x1fc,UINT64_C(0xbc0da304f524beb3)},
        {0x134c2c0,0x1fc,UINT64_C(0x641258127bed8ca1)},
        {0x134c4c0,0x1fc,UINT64_C(0xfd10c46d5a772b97)},
        {0x134c6c0,0x1fc,UINT64_C(0xeb8d0474cfd619b5)},
        {0x52d650,0x2b4,UINT64_C(0x9e8023d09def7af9)},
        {0xede350,0x31b,UINT64_C(0x1fddbdca853294d0)},
        {0xa94030,0x6a1,UINT64_C(0xd81db68b3c9b33d2)},
        {0x426f06,0x222,UINT64_C(0x98970e3046137975)},
        {0x163ce54,0x62,UINT64_C(0x93f00cd61bbe39bd)},
        {0x425539,0x162,UINT64_C(0x497589726e70534e)},
        {0x42712b,0x147,UINT64_C(0x1001eb9865cf74f3)},
        {0x423df0,0x483,UINT64_C(0x76d34506cc3f6746)},
        {0x421ea0,0x90,UINT64_C(0x66ce8e62615f3121)},
        {0x14219a0,0x1e,UINT64_C(0xbd7a0f718d1f235d)},
        {0x99a1f0,0x1c1,UINT64_C(0x29e6da03c674f048)},
        {0x13b1170,0xbd,UINT64_C(0x3e26062d73fefb84)},
        {0xb96d80,0x53e,UINT64_C(0x5249c96a7883418a)},
        {0xb530b0,0xac,UINT64_C(0x7c6f66602bdab157)},
        {0xbbef0,0x9a,UINT64_C(0xb674b3f5153bea03)},
        {0xbbd90,0xa8,UINT64_C(0xe0b2ddde58f5e3fc)},
        {0xbbe40,0xad,UINT64_C(0x062a266340f9bf38)},
        {0x421f30,0x87a,UINT64_C(0x24352b0e8bb5f0ba)},
        {0x421dc0,0xd9,UINT64_C(0x6e40e0a2cdabd7a8)},
        {0x1421960,0x39,UINT64_C(0x5678b62c0493d8f4)},
        {0x136ccc0,0xf00,UINT64_C(0x155550fa55ed7b99)},
        {0x136dbc0,0x5dd,UINT64_C(0x129278c5cfb8c58d)},
        {0x99a9f0,0x17f,UINT64_C(0xd528dde4d0fe9e7b)},
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!pinned)return false;
    return true;
}
struct Context {
    df::administrators_interfacest value;
    uint8_t* base;
    explicit Context(uint8_t* address):base(address){}
    ~Context(){
        reinterpret_cast<void(*)(df::administrators_interfacest*)>(base+0x421ea0)(&value);
        reinterpret_cast<void(*)(df::administrators_interfacest*)>(base+0x421dc0)(&value);
    }
    Context(const Context&)=delete;
    Context& operator=(const Context&)=delete;
};
// Renderer426f06 supplies the office title and a fixed twenty-byte squad
// caption. Holder captions remain full length: viewport clipping belongs to the
// presentation. All mutating string/name/unit formatters receive owned inputs.
inline bool captions(const df::noblelistst& source,Row& row,uint8_t* base) {
    static_assert(offsetof(df::entity_position,name)==0x98);
    static_assert(offsetof(df::entity_position,land_name)==0x258);
    static_assert(offsetof(df::entity_position_assignment,squad_id)==0x28);
    static_assert(offsetof(df::squad,name)==8);
    static_assert(offsetof(df::squad,alias)==0x80);
    static_assert(offsetof(df::historical_figure,name)==0x38);
    row.title=source.ep->land_name.empty()?source.ep->name[0]:source.ep->land_name;
    reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&row.title);
    if(source.epp && source.epp->squad_id!=-1) {
        if(auto* squad=df::squad::find(source.epp->squad_id)) {
            if(!squad->alias.empty())row.squadCaption=squad->alias;
            else {
                auto name=squad->name;
                reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&name,&row.squadCaption,true,false);
            }
            if(row.squadCaption.size()>=21) {
                if(squad->alias.empty())reinterpret_cast<void(*)(std::string*)>(base+0xede350)(&row.squadCaption);
                if(row.squadCaption.size()>=21){row.squadCaption.resize(20);row.squadCaption.replace(17,3,"...");}
            }
        }
    }
    if(source.un) {
        if(source.un->inventory.size()>10000)return false;
        for(auto* entry:source.un->inventory)if(!entry)return false;
        df3d_creature::InventoryDescriptionContext owned(*source.un);
        reinterpret_cast<void(*)(df::unit*,std::string*,bool)>(base+0x1330c30)(owned.unit(),&row.holderCaption,false);
    } else if(source.nem && source.nem->figure && source.nem->figure->died_year==-1) {
        auto name=source.nem->figure->name;
        reinterpret_cast<void(*)(df::language_name*,std::string*)>(base+0xa94030)(&name,&row.holderCaption);
        row.holderCaption.append(reinterpret_cast<const char*>(base+0x163ce58),12);
    } else {
        row.holderCaption.assign(reinterpret_cast<const char*>(base+(source.epp?0x163ceb0:0x163ce54)),source.epp?6:3);
    }
    return true;
}
// Nobles passes these three parallel arrays to the native aggregators. Keep
// the builder's membership/order and copy only assignment fields read by bbe40;
// that helper is allowed to refresh indices in these private records.
struct RequirementsContext {
    std::vector<df::entity_position_assignment> storage;
    std::vector<df::entity_position_assignment*> assignments;
    std::vector<int32_t> holders,entities;
    bool capture(const df::administrators_interfacest& source) {
        const auto count=source.spec_prof.size();
        if(count>65536 || source.spec_hfid.size()!=count || source.spec_enid.size()!=count)return false;
        holders=source.spec_hfid;entities=source.spec_enid;storage.reserve(count);assignments.reserve(count);
        for(const auto* assignment:source.spec_prof) {
            if(!assignment){assignments.push_back(nullptr);continue;}
            storage.emplace_back();storage.back().position_id=assignment->position_id;
            storage.back().position_vector_idx=-1;assignments.push_back(&storage.back());
        }
        return true;
    }
    bool assess(const df::noblelistst& source,Row& row,uint8_t* base) {
        if(!source.un)return true;
        if(!source.upplist)return false;
        const auto actual=df3d_creature::actualRooms(source.un);if(!actual)return false;
        row.actualRooms=*actual;row.hasRoomAssessment=true;
        using Rooms=void(*)(df::unit*,int32_t*,const std::vector<df::entity_position_assignment*>*,const std::vector<int32_t>*,const std::vector<int32_t>*);
        // Supplied arrays select the native branch that only reads unit HF ID.
        reinterpret_cast<Rooms>(base+0x134a5e0)(source.un,row.requiredRooms.data(),&assignments,&holders,&entities);
        using Furniture=int32_t(*)(df::unit*,const std::vector<df::entity_position_assignment*>*,const std::vector<int32_t>*,const std::vector<int32_t>*);
        constexpr size_t functions[]={0x134c0c0,0x134c2c0,0x134c4c0,0x134c6c0};
        for(size_t i=0;i<4;++i)row.requiredFurniture[i]=reinterpret_cast<Furniture>(base+functions[i])(source.un,&assignments,&holders,&entities);
        static_assert(offsetof(df::unitpropertyplacementst,boxcount)==0x4c);
        static_assert(offsetof(df::unitpropertyplacementst,cabcount)==0x50);
        static_assert(offsetof(df::unitpropertyplacementst,rackcount)==0x54);
        static_assert(offsetof(df::unitpropertyplacementst,standcount)==0x58);
        row.actualFurniture={source.upplist->boxcount,source.upplist->cabcount,source.upplist->rackcount,source.upplist->standcount};
        return true;
    }
};
// Native134a920 only reads demand fields, owned zones, contained buildings and
// item type/material getters. Own the unit/demand containers; buildings/items
// remain read-only simulation references. No menu context is reachable here.
inline bool obligations(const df::noblelistst& source,Row& row,uint8_t* base) {
    if(!source.un)return true;
    if(source.un->status.demands.size()>65536 || source.un->owned_buildings.size()>4096 || df::global::world->mandates.all.size()>1048576)return false;
    static_assert(offsetof(df::unit,status)+offsetof(df::unit::T_status,demands)==0xaa0);
    static_assert(offsetof(df::unit_demand,timeout_counter)==0x10);
    static_assert(offsetof(df::mandate,mode)==8);
    static_assert(offsetof(df::mandate,timeout_counter)==0x18);
    static_assert(offsetof(df::mandate,timeout_limit)==0x1c);
    static_assert(offsetof(df::building_civzonest,contained_buildings)==0x188);
    static_assert(offsetof(df::building_actual,contained_items)==0x128);
    struct OwnedUnit final:df::unit {OwnedUnit():df::unit(){}} owned;
    std::vector<df::unit_demand> demands;demands.reserve(source.un->status.demands.size());
    for(const auto* demand:source.un->status.demands){if(!demand)return false;demands.push_back(*demand);}
    for(auto& demand:demands)owned.status.demands.push_back(&demand);
    owned.owned_buildings=source.un->owned_buildings;
    for(const auto* zone:owned.owned_buildings) {
        if(!zone || zone->contained_buildings.size()>65536)return false;
        for(auto* building:zone->contained_buildings) {
            if(!building)return false;
            if(auto* actual=virtual_cast<df::building_actual>(building)) {
                if(actual->contained_items.size()>65536)return false;
                for(const auto* entry:actual->contained_items)if(!entry || !entry->item)return false;
            }
        }
    }
    for(size_t i=0;i<demands.size();++i) {
        const bool fulfilled=reinterpret_cast<bool(*)(df::unit*,int32_t)>(base+0x134a920)(&owned,static_cast<int32_t>(i));
        const int32_t severity=fulfilled?0:demands[i].timeout_counter>=5000?3:demands[i].timeout_counter>=2500?2:1;
        row.demandStatus=std::max(row.demandStatus,severity);
    }
    // Renderer42853b aggregates mandates inline; there is no helper call.
    for(const auto* mandate:df::global::world->mandates.all) {
        if(!mandate)return false;
        if(mandate->unit!=source.un)continue;
        int32_t severity=0;
        if(mandate->mode==df::mandate_type::Make || mandate->mode==df::mandate_type::Guild) {
            // Match the native signed 32-bit subtraction, including wraparound.
            const auto remaining=static_cast<int32_t>(static_cast<uint32_t>(mandate->timeout_limit)-static_cast<uint32_t>(mandate->timeout_counter));
            severity=remaining<2500?3:remaining<5000?2:1;
        }
        row.mandateStatus=std::max(row.mandateStatus,severity);
    }
    return true;
}
inline std::optional<std::vector<Row>> overview() {
    if(!ready())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    // Unit location summaries can choose between equivalent locations using MT.
    df3d_creature::InventoryRandomRestore random(base);
    Context owned(base);
    reinterpret_cast<void(*)(df::administrators_interfacest*)>(base+0x421f30)(&owned.value);
    if(owned.value.noblelist.size()>65536)return std::nullopt;
    RequirementsContext requirements;if(!requirements.capture(owned.value))return std::nullopt;
    std::vector<Row> result;result.reserve(owned.value.noblelist.size());
    for(const auto* source:owned.value.noblelist) {
        if(!source || !source->ep)return std::nullopt;
        const auto available=appointmentAvailable(*source,owned.value.noblelist);if(!available)return std::nullopt;
        Row row;row.canAppoint=*available;row.unitId=source->un?source->un->id:-1;row.nemesisId=source->nem?source->nem->id:-1;
        row.entityId=source->enid;row.positionId=source->ep->id;row.assignmentId=source->epp?source->epp->id:-1;
        row.value=source->value;row.positionName=source->ep->name[0];
        if(!captions(*source,row,base) || !requirements.assess(*source,row,base) || !obligations(*source,row,base))return std::nullopt;
        result.push_back(std::move(row));
    }
    return result;
}
struct Candidate {int32_t unitId=-1,value=0;};
// Selection identity comes from a fresh owned overview; no menu index crosses
// this boundary. This only lists candidates, not permission to appoint them.
inline std::optional<std::vector<Candidate>> candidates(int32_t entityId,int32_t positionId,int32_t assignmentId) {
    if(!ready() || entityId<0 || positionId<0 || assignmentId< -1)return std::nullopt;
    static_assert(sizeof(df::appointment_candidatest)==0x10);
    static_assert(offsetof(df::appointment_candidatest,value)==8);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    df3d_creature::InventoryRandomRestore random(base);
    df3d_creature::LaborEligibilityCacheRestore caches;
    if(df::global::world->units.active.size()>1048576)return std::nullopt;
    for(auto* unit:df::global::world->units.active)if(!caches.capture(unit,-1))return std::nullopt;
    Context owned(base);
    reinterpret_cast<void(*)(df::administrators_interfacest*)>(base+0x421f30)(&owned.value);
    if(owned.value.noblelist.size()>65536)return std::nullopt;
    df::noblelistst* target=nullptr;
    for(auto* row:owned.value.noblelist) {
        if(!row || !row->ep)return std::nullopt;
        if(row->enid==entityId && row->ep->id==positionId && (row->epp?row->epp->id:-1)==assignmentId) {
            if(target)return std::nullopt;
            target=row;
        }
    }
    if(!target)return std::nullopt;
    const auto available=appointmentAvailable(*target,owned.value.noblelist);
    if(!available || !*available)return std::nullopt;
    reinterpret_cast<void(*)(df::administrators_interfacest*,df::noblelistst*)>(base+0x423df0)(&owned.value,target);
    if(owned.value.candidate.size()>1048576)return std::nullopt;
    std::vector<Candidate> result;result.reserve(owned.value.candidate.size());
    for(const auto* row:owned.value.candidate) {
        if(!row)return std::nullopt;
        result.push_back({row->un?row->un->id:-1,row->value});
    }
    return result;
}
}
