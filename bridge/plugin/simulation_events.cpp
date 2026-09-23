#include "simulation_events.h"
#include "DataDefs.h"
#include "modules/Items.h"
#include "modules/Materials.h"
#include "df/item.h"
#include "df/itemdef.h"
#include "df/material.h"
#include "df/job_skill.h"
#include "df/report.h"
#include "df/unit.h"
#include "df/unit_action.h"
#include "df/unit_action_type.h"
#include "df/world.h"
#include "df/announcement_type.h"
#include <algorithm>

using namespace DFHack;
namespace m=df3d::mirror;
namespace df3d_events {
namespace { ReportJournal journal; }
ItemSource itemSource(df::item* item) {
    ItemSource out;
    if(!item || item->id<0) return out;
    out.id=item->id;
    out.type=ENUM_KEY_STR(item_type,item->getType());
    if(const auto* def=Items::getSubtypeDef(item->getType(),item->getSubtype())) out.subtype=def->id;
    MaterialInfo material(item->getActualMaterial(),item->getActualMaterialIndex());
    if(material.isValid()) {
        out.material=material.getToken();
        if(material.material) {
            out.material_flags_known=true;
            out.material_flags=(material.material->flags.is_set(df::material_flags::IS_GLASS)?1u:0u) |
                (material.material->flags.is_set(df::material_flags::IS_METAL)?2u:0u) |
                (material.material->flags.is_set(df::material_flags::BONE)?4u:0u);
        }
    }
    out.melee_skill=ENUM_KEY_STR(job_skill,item->getMeleeSkill());
    return out;
}
AttackSource attackSource(df::unit* attacker, int32_t victim) {
    AttackSource out;
    if(!attacker || attacker->actions.size()>64) return out;
    const df::unit_action* match=nullptr;
    // Do not guess from carried weapons or a queued future strike. There is
    // still no causal action ID in UNIT_ATTACK, so this remains qualified
    // contemporaneous context even when the recovering action is unique.
    for(const auto* action:attacker->actions) {
        if(!action || action->id<0 || action->type!=df::unit_action_type::Attack) continue;
        const auto& attack=action->data.attack;
        if(attack.target_unit_id!=victim || attack.timer1>0 || attack.timer2<0) continue;
        if(match) return out;
        match=action;
    }
    if(match) {
        out.actionId=match->id;
        out.weapon=itemSource(df::item::find(match->data.attack.attack_item_id));
    }
    return out;
}
flatbuffers::Offset<m::EventItem> buildItem(flatbuffers::FlatBufferBuilder& f, const ItemSource& item) {
    if(item.id<0) return {};
    auto type=f.CreateSharedString(item.type), subtype=f.CreateSharedString(item.subtype), material=f.CreateSharedString(item.material);
    auto skill=f.CreateSharedString(item.melee_skill);
    return m::CreateEventItem(f,item.id,type,subtype,material,item.material_flags,item.material_flags_known,skill);
}
void resetReports(bool newSession) {
    const auto* world=df::global::world;
    // No old announcements replay on attach, re-enable or map replacement.
    const auto baseline=world ? world->status.next_report_id-1 : -1;
    if(newSession) journal.reset(baseline);
    else journal.lastReport=std::max(journal.lastReport,baseline);
}
void observeReport(int32_t id) {
    const auto* world=df::global::world;
    if(!world) return;
    auto* report=df::report::find(id);
    if(!report) return;
    ReportObservation out;
    out.tick=uint64_t(world->frame_counter); out.reportId=id;
    if(report->type>=df::announcement_type::REACHED_PEAK && report->type<=ENUM_LAST_ITEM(announcement_type))
        out.type=ENUM_KEY_STR(announcement_type,report->type);
    auto valid=[&](const df::coord& p) {
        return p.x>=0 && p.y>=0 && p.z>=0 && p.x<world->map.x_count && p.y<world->map.y_count && p.z<world->map.z_count;
    };
    out.hasPosition=valid(report->pos);out.hasSecondary=valid(report->pos2);
    if(out.hasPosition) {out.x=report->pos.x;out.y=report->pos.y;out.z=report->pos.z;}
    if(out.hasSecondary) {out.x2=report->pos2.x;out.y2=report->pos2.y;out.z2=report->pos2.z;}
    out.repeatCount=uint32_t(std::max(0,report->repeat_count));
    out.speakerId=std::max(-1,report->speaker_id);
    journal.observe(std::move(out),report->flags.bits.continuation);
}
flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<m::ReportEvent>>>
buildReports(flatbuffers::FlatBufferBuilder& f, uint64_t tick) {
    journal.expire(tick);
    std::vector<flatbuffers::Offset<m::ReportEvent>> result;
    result.reserve(journal.records.size());
    for(const auto& e:journal.records) if(e.tick<=tick) {
        m::TilePos pos(e.x,e.y,e.z),pos2(e.x2,e.y2,e.z2);
        auto type=f.CreateSharedString(e.type);
        result.push_back(m::CreateReportEvent(f,e.id,e.tick,e.reportId,type,
            e.hasPosition?&pos:nullptr,e.hasSecondary?&pos2:nullptr,e.repeatCount,e.speakerId));
    }
    return f.CreateVector(result);
}
const ReportJournal& reports() { return journal; }
}
