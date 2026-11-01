#pragma once
#include "creature_expel_native.h"
#include "df/army_controller.h"
#include "df/army_controller_goal_move_to_sitest.h"
#include "df/history_event_entity_expels_hfst.h"
#include "df/travel_logst.h"
#include <algorithm>
#include <array>

namespace df3d_creature {
enum class ExpelOutcome { Unsupported, Rejected, Applied, Unknown };
// Native1b1825..1b1c26 semantic effects, with independently owned group/intent.
// Caller owns epoch/save admission. Never replay Unknown: native effects may
// already have published history or retired assignments before an exception.
inline ExpelOutcome applyExpel(df::unit* selected,int32_t destination,const std::vector<int32_t>& expected) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1b1825,0x401,UINT64_C(0x4f07ce07b3911559)},
            {0x13e720,0x71,UINT64_C(0xfdcf85d1494bc6eb)},
            {0xfe960,0x570,UINT64_C(0x53ec126b8c0c3e44)},
            {0x1349f20,0x6b5,UINT64_C(0xa4110de557c04467)},
            {0x13b3090,0x19,UINT64_C(0x901cd2f6d41c1657)},
            {0xb989f0,0xdd,UINT64_C(0xcc01c7b7e2ed1eb2)},
            {0x138f430,0x4a,UINT64_C(0x8857a5136ad3583c)},
            {0x13cbf10,0x173,UINT64_C(0x0992efa035b017f8)},
            {0x1325080,0x33c3,UINT64_C(0xf84d63b3115de7d1)},
            {0x14dec0,0xf1,UINT64_C(0x09f5b836ba2b3ee9)},
            {0xa419f0,0x199,UINT64_C(0x219e1dd9a8149720)},
            {0xfdbc0,0x46,UINT64_C(0x606c4d2f5f3817e1)},
            {0xfdc10,0x31,UINT64_C(0x5c7643da07bb424e)},
            {0x72510,0x34,UINT64_C(0xd507691c7a2ea748)},
            {0x73710,0x4c,UINT64_C(0xe700e2d52b0deb31)},
            {0xbb2f30,0x20d,UINT64_C(0xd2f627c85121b5dd)},
            {0x13eff80,0xa0,UINT64_C(0xb66acd69c2fb79b5)},
            {0xe198e0,0xafb6,UINT64_C(0x69508c275f046381)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported || !df::global::world || !df::global::plotinfo || !df::global::cur_year || !df::global::cur_year_tick)return ExpelOutcome::Unsupported;
    const auto eligible=expelEligible(selected);if(!eligible)return ExpelOutcome::Unsupported;
    if(!*eligible || destination<-1)return ExpelOutcome::Rejected;
    const auto group=expelGroup(selected);if(!group)return ExpelOutcome::Unsupported;
    if(group->reason!=-1 || group->units.empty() || group->units!=expected)return ExpelOutcome::Rejected;
    const auto destinations=expelDestinations();if(!destinations)return ExpelOutcome::Unsupported;
    if(destination!=-1 && !std::binary_search(destinations->begin(),destinations->end(),destination))return ExpelOutcome::Rejected;
    std::vector<df::unit*> departing;departing.reserve(group->units.size());
    for(auto id:group->units){auto* unit=df::unit::find(id);if(!unit)return ExpelOutcome::Rejected;departing.push_back(unit);}
    if(df::global::world->units.active.size()>1000000)return ExpelOutcome::Unsupported;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto figure=reinterpret_cast<df::historical_figure* (*)(df::unit*)>(base+0x13b3090);
    struct alignas(8) Thought {std::array<int32_t,12> fields{};};
    const auto thought=[&](df::unit* unit,int32_t type,int32_t relation=-1) {
        Thought value;reinterpret_cast<void (*)(Thought*)>(base+0x72510)(&value);
        value.fields[0]=type;value.fields[1]=relation;value.fields[3]=100;
        reinterpret_cast<void (*)(df::unit*,Thought*)>(base+0x13eff80)(unit,&value);
    };
    static_assert(sizeof(df::travel_logst)==0x38);
    static_assert(offsetof(df::army_controller,data)==0x130);
    static_assert(offsetof(df::army_controller_goal_move_to_sitest,goal_ab_id)==0x30);
    // No refusal or unsupported exits beyond this point: mutation has begun.
    try {
        auto* controller=reinterpret_cast<df::army_controller* (*)()>(base+0x13e720)();
        reinterpret_cast<void (*)(df::army_controller*,int32_t)>(base+0xfe960)(controller,12);
        auto* goal=controller->data.goal_move_to_site;
        goal->goal_hfid=-1;goal->goal_srbid=-1;goal->goal_ab_id=-1;goal->reason=df::history_event_reason(-1);goal->flag.whole|=1;
        controller->site_id=destination;controller->entity_id=-1;
        controller->year=*df::global::cur_year;controller->year_tick=*df::global::cur_year_tick;
        controller->pos_x=-1;controller->pos_y=-1;controller->master_id=controller->id;
        for(auto* unit:departing) {
            if(destination==-1 && unit->hist_figure_id!=-1) {
                auto* event=reinterpret_cast<df::history_event_entity_expels_hfst* (*)()>(base+0x14dec0)();
                event->civ=df::global::plotinfo->group_id;event->expelled=unit->hist_figure_id;event->site=df::global::plotinfo->site_id;
                event->year=*df::global::cur_year;event->seconds=*df::global::cur_year_tick;event->add_to_classes();
            }
            reinterpret_cast<void (*)(df::unit*,bool)>(base+0x1349f20)(unit,false);
            if(auto* hf=figure(unit))reinterpret_cast<void (*)(df::historical_figure*,int16_t,int32_t,int32_t,int32_t,bool)>(base+0xb989f0)(hf,-1,-1,-1,-1,false);
            reinterpret_cast<void (*)(df::unit*,int32_t,int32_t,int32_t,bool)>(base+0x138f430)(unit,-1,df::global::plotinfo->group_id,0,false);
            reinterpret_cast<void (*)(df::unit*)>(base+0x13cbf10)(unit);
            if(unit->job.current_job)reinterpret_cast<void (*)(df::unit*,bool,int32_t,bool,void*)>(base+0x1325080)(unit,false,0,false,nullptr);
            if(destination==-1) {
                if(reinterpret_cast<bool (*)(df::unit*)>(base+0x73710)(unit))thought(unit,241);
                for(auto* relative:df::global::world->units.active) {
                    if(!relative || relative->flags1.bits.inactive)continue;
                    // Maintainer-approved correction: native reads obsolete UI
                    // view.expel_total_list here. Use this owned departing group.
                    if(std::binary_search(group->units.begin(),group->units.end(),relative->id))continue;
                    auto* hf=figure(relative);if(!hf)continue;
                    const auto relation=reinterpret_cast<int32_t (*)(df::historical_figure*,int32_t)>(base+0xbb2f30)(hf,unit->hist_figure_id);
                    if(relation!=-1)thought(relative,242,relation);
                }
            }
            unit->flags2.bits.visitor=true;
            auto*& travel=unit->enemy.travel_log;
            if(!travel) {
                auto* memory=reinterpret_cast<void* (*)(size_t)>(base+0x1539690)(sizeof(df::travel_logst));
                travel=reinterpret_cast<df::travel_logst* (*)(void*)>(base+0xfdbc0)(memory);
            } else reinterpret_cast<void (*)(df::travel_logst*)>(base+0xfdc10)(travel);
            travel->flags.whole|=4;travel->rumour_type=df::history_event_reason(-1);travel->rumour_location_id=-1;
            travel->year=*df::global::cur_year;travel->year_tick=*df::global::cur_year_tick;
            reinterpret_cast<void (*)(df::unit*)>(base+0xa419f0)(unit);
            unit->enemy.army_controller=controller;unit->enemy.army_controller_id=controller->id;
        }
        return ExpelOutcome::Applied;
    } catch(const std::exception&) {return ExpelOutcome::Unknown;}
}
}
