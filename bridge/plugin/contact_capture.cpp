#include "contact_capture.h"
#include "simulation_events.h"
#include "attack_assembler.h"
#include "modules/Combat.h"
#include "df/world.h"
#include "df/unit.h"
#include "df/item.h"
#include "df/unit_wound.h"
#include "df/unit_wound_layerst.h"
#include "df/caste_body_info.h"
#include "df/body_part_raw.h"
#include "df/global_objects.h"
#include "df/proj_itemst.h"
#include "df/item_weaponst.h"
#include "df/itemdef_weaponst.h"
#include "df/job_skill.h"
#include <deque>
#include <fstream>
namespace df3d_contact {
namespace {
namespace mir=df3d::mirror;
struct Observation {
    uint64_t id,tick;
    df3d_events::ItemSource first,second;
    mir::TilePos pos;
    int32_t attacker,defender,action;
};
std::deque<Observation> journal;
uint64_t nextId=1,discarded=0,probeStart=0;
bool active=false;
AttackAssembler<df3d_events::ItemSource> attacks;
uint64_t attackProbeStart=0;
struct ProjectileRecord {
    uint64_t id,tick;
    int32_t projectile,source,target;
    mir::ProjectileCombatKind kind;
    mir::WeaponLauncher launcher=mir::WeaponLauncher::Unknown;
    df3d_events::ItemSource ammunition,weapon;
    mir::TilePos pos;
    bool complete=false;
};
std::deque<ProjectileRecord> projectiles;
uint64_t projectileDiscarded=0;
void observeProjectile(const DFHack::Combat::ProjectileEvent& event) {
    auto* world=df::global::world;auto* p=event.projectile;
    if(!active || !world || !p || p->id<0)return;
    const auto pos=p->cur_pos;
    if(pos.x<0 || pos.y<0 || pos.z<0 || pos.x>=world->map.x_count || pos.y>=world->map.y_count || pos.z>=world->map.z_count)return;
    ProjectileRecord record{event.occurrence_id,static_cast<uint64_t>(world->frame_counter),p->id,
        p->firer?p->firer->id:-1,event.target?event.target->id:-1,static_cast<mir::ProjectileCombatKind>(event.kind)};
    record.ammunition=df3d_events::itemSource(p->item);
    auto* weapon=df::item::find(p->bow_id);record.weapon=df3d_events::itemSource(weapon);
    if(auto* bow=virtual_cast<df::item_weaponst>(weapon);bow && bow->subtype) {
        if(bow->subtype->skill_ranged==df::job_skill::BOW)record.launcher=mir::WeaponLauncher::Bow;
        else if(bow->subtype->skill_ranged==df::job_skill::CROSSBOW)record.launcher=mir::WeaponLauncher::Crossbow;
    } else if(p->item && p->item->getType()==df::item_type::SIEGEAMMO)record.launcher=mir::WeaponLauncher::Ballista;
    record.pos=mir::TilePos(pos.x,pos.y,pos.z);
    record.complete=record.ammunition.id>=0 && record.launcher!=mir::WeaponLauncher::Unknown &&
        (record.kind!=mir::ProjectileCombatKind::Release || record.weapon.id>=0);
    while(!projectiles.empty() && record.tick>projectiles.front().tick && record.tick-projectiles.front().tick>600)projectiles.pop_front();
    projectiles.push_back(std::move(record));
    if(projectiles.size()>512){projectiles.pop_front();++projectileDiscarded;}
}
AttackAssembler<df3d_events::ItemSource>::Wound copyWound(const DFHack::Combat::AttackEvent& event) {
    AttackAssembler<df3d_events::ItemSource>::Wound result;
    result.id=event.wound_id;result.victim=event.wound_victim_id;
    result.severed=event.severed_part;result.popped=event.popped_out;
    if(!event.wound || !event.defender){result.parts_complete=false;return result;}
    const auto* body=event.defender->body.body_plan;
    for(const auto* part:event.wound->parts) {
        if(result.parts.size()==128){result.parts_complete=false;break;}
        if(!part || part->body_part_id<0 || part->layer_idx<-1){result.parts_complete=false;continue;}
        AttackAssembler<df3d_events::ItemSource>::WoundPart value;
        value.body_part_id=part->body_part_id;value.layer_id=part->layer_idx;
        // Portable semantic bits declared by AttackDamageFlag, not the native
        // flag-word layout. These report injury observations, never severity.
        value.damage=(part->flags1.bits.cut?1u:0u) | (part->flags1.bits.smashed?2u:0u) |
            (part->flags1.bits.smashed_apart?4u:0u) | (part->flags1.bits.broken?8u:0u) |
            (part->flags1.bits.gouged?16u:0u) | (part->flags1.bits.compound_fracture?32u:0u) |
            (part->flags1.bits.motor_nerve_severed?64u:0u) | (part->flags1.bits.sensory_nerve_severed?128u:0u) |
            (part->flags1.bits.major_artery?256u:0u) | (part->flags1.bits.guts_spilled?512u:0u);
        if(body && static_cast<size_t>(part->body_part_id)<body->body_parts.size() && body->body_parts[part->body_part_id]) {
            const auto* raw=body->body_parts[part->body_part_id];
            value.token=raw->token;value.category=raw->category;
            value.anatomy=(raw->flags.is_set(df::body_part_raw_flags::HEAD)?1u:0u) |
                (raw->flags.is_set(df::body_part_raw_flags::THOUGHT)?2u:0u) |
                (raw->flags.is_set(df::body_part_raw_flags::CIRCULATION)?4u:0u) |
                (raw->flags.is_set(df::body_part_raw_flags::THROAT)?8u:0u) |
                (raw->flags.is_set(df::body_part_raw_flags::INTERNAL)?16u:0u);
        } else result.parts_complete=false;
        result.parts.push_back(std::move(value));
    }
    return result;
}
void prune(uint64_t tick) {
    while(!journal.empty() && tick>journal.front().tick && tick-journal.front().tick>600)journal.pop_front();
}
void observe(const DFHack::Combat::ItemContact& event) {
    auto* world=df::global::world;
    if(!active || !world || !event.defender || !event.attacking_item || !event.struck_item ||
       event.attacking_item->id<0 || event.struck_item->id<0)return;
    const auto pos=event.defender->pos;
    if(pos.x<0 || pos.y<0 || pos.z<0 || pos.x>=world->map.x_count || pos.y>=world->map.y_count || pos.z>=world->map.z_count)return;
    const auto tick=static_cast<uint64_t>(world->frame_counter);prune(tick);
    // Resolve metadata now, while exact native objects are alive. No borrowed
    // pointers or later current-equipment guesses survive this callback.
    journal.push_back({nextId++,tick,df3d_events::itemSource(event.attacking_item),
        df3d_events::itemSource(event.struck_item),mir::TilePos(pos.x,pos.y,pos.z),
        event.attacker?event.attacker->id:-1,event.defender->id,event.action_id});
    if(journal.size()>512){journal.pop_front();++discarded;}
}
void observeAttack(const DFHack::Combat::AttackEvent& event) {
    if(!active)return;
    if(event.phase==DFHack::Combat::AttackPhase::Begin) {
        auto* world=df::global::world;
        if(!world || !event.attacker || !event.defender)return;
        const auto pos=event.defender->pos;
        if(pos.x<0 || pos.y<0 || pos.z<0 || pos.x>=world->map.x_count || pos.y>=world->map.y_count || pos.z>=world->map.z_count)return;
        AttackAssembler<df3d_events::ItemSource>::Record record;
        record.id=event.occurrence_id;record.tick=static_cast<uint64_t>(world->frame_counter);
        record.attacker=event.attacker->id;record.defender=event.defender->id;record.action=event.action_id;
        record.weapon=df3d_events::itemSource(event.weapon);record.pos={pos.x,pos.y,pos.z};
        record.weapon_context_complete=event.weapon_context_complete;
        record.timer1=event.entry_timer1;record.timer2=event.entry_timer2;
        attacks.prune(record.tick);attacks.begin(std::move(record));
    } else if(event.phase==DFHack::Combat::AttackPhase::Contact) {
        attacks.contact(event.occurrence_id,df3d_events::itemSource(event.weapon),df3d_events::itemSource(event.struck_item));
        observe({event.attacker,event.defender,event.weapon,event.struck_item,event.action_id});
    } else if(event.phase==DFHack::Combat::AttackPhase::Wound) {
        attacks.wound(event.occurrence_id,copyWound(event));
    } else attacks.end(event.occurrence_id,event.equipment_contacts_complete,event.native_event_count,event.wounds_complete,
        static_cast<uint8_t>(event.outcome),event.outcome_complete);
}
DFHack::command_result command(DFHack::color_ostream& out,std::vector<std::string>& args) {
    if(args.size()==2 && args[0]=="projectiles") {
        std::ofstream f(args[1]);if(!f)return DFHack::CR_FAILURE;
        for(const auto& row:projectiles)f<<"{\"id\":"<<row.id<<",\"tick\":"<<row.tick
            <<",\"projectile\":"<<row.projectile<<",\"source\":"<<row.source<<",\"target\":"<<row.target
            <<",\"kind\":"<<int(row.kind)<<",\"launcher\":"<<int(row.launcher)
            <<",\"ammunition\":"<<row.ammunition.id<<",\"weapon\":"<<row.weapon.id
            <<",\"complete\":"<<(row.complete?"true":"false")<<"}\n";
        out.print("projectile events={} dropped={}\n",projectiles.size(),projectileDiscarded);return DFHack::CR_OK;
    }
    if(args.size()==1 && args[0]=="start") {
        probeStart=nextId;attackProbeStart=attacks.records().empty()?0:attacks.records().back().id;
        out.print("contact hook enabled={} status={}\n",active,status());
        return active?DFHack::CR_OK:DFHack::CR_FAILURE;
    }
    if(args.size()==2 && args[0]=="attacks") {
        std::ofstream f(args[1]);if(!f)return DFHack::CR_FAILURE;
        size_t count=0;
        for(const auto& row:attacks.records())if(row.id>attackProbeStart) {
            ++count;f<<"{\"id\":"<<row.id<<",\"tick\":"<<row.tick<<",\"attacker\":"<<row.attacker
                <<",\"victim\":"<<row.defender<<",\"weapon\":"<<row.weapon.id<<",\"action\":"<<row.action
                <<",\"contacts\":"<<row.contacts.size()<<",\"complete\":"<<(row.complete?"true":"false")
                <<",\"native_events\":"<<row.native_events<<",\"timer1\":"<<row.timer1<<",\"timer2\":"<<row.timer2
                <<",\"outcome\":"<<int(row.outcome)<<",\"outcome_complete\":"<<(row.outcome_complete?"true":"false")
                <<",\"weapon_context_complete\":"<<(row.weapon_context_complete?"true":"false")
                <<",\"wounds_complete\":"<<(row.wounds_complete?"true":"false")<<",\"wounds\":[";
            bool firstWound=true;
            for(const auto& wound:row.wounds) {
                if(!firstWound)f<<',';firstWound=false;
                f<<"{\"id\":"<<wound.id<<",\"victim\":"<<wound.victim<<",\"severed\":"<<(wound.severed?"true":"false")
                 <<",\"popped\":"<<(wound.popped?"true":"false")<<",\"parts_complete\":"<<(wound.parts_complete?"true":"false")<<",\"parts\":[";
                bool firstPart=true;
                for(const auto& part:wound.parts) {
                    if(!firstPart)f<<',';firstPart=false;
                    f<<"{\"body_part\":"<<part.body_part_id<<",\"layer\":"<<part.layer_id<<",\"token\":\""<<part.token
                     <<"\",\"category\":\""<<part.category<<"\",\"damage\":"<<part.damage<<",\"anatomy\":"<<part.anatomy<<'}';
                }
                f<<"]}";
            }
            f<<"]}\n";
        }
        out.print("resolved attacks={} dropped={} pending={}\n",count,attacks.dropped(),attacks.pending());return DFHack::CR_OK;
    }
    if(args.size()==2 && args[0]=="dump") {
        std::ofstream f(args[1]);if(!f)return DFHack::CR_FAILURE;
        size_t count=0;
        for(const auto& row:journal)if(row.id>=probeStart) {
            ++count;f<<"{\"id\":"<<row.id<<",\"tick\":"<<row.tick<<",\"attacker\":"<<row.attacker
                <<",\"victim\":"<<row.defender<<",\"weapon\":"<<row.first.id<<",\"action\":"<<row.action
                <<",\"item\":"<<row.second.id<<",\"first_material\":\""<<row.first.material
                <<"\",\"second_material\":\""<<row.second.material<<"\"}\n";
        }
        out.print("contact hook rows={} dropped={} status={}\n",count,discarded,status());return DFHack::CR_OK;
    }
    return DFHack::CR_WRONG_USAGE;
}
}
void registerCommands(std::vector<DFHack::PluginCommand>& commands) {
    commands.emplace_back("df3d-contact-probe","Dump positively resolved native equipment contacts",command);
}
void setEnabled(bool enabled) {
    if(enabled && !active) {
        active=DFHack::Combat::registerAttackCallback(observeAttack);
        if(active && !DFHack::Combat::registerProjectileCallback(observeProjectile)) {
            active=false;DFHack::Combat::unregisterAttackCallback(observeAttack);
        }
    } else if(!enabled && active){active=false;DFHack::Combat::unregisterAttackCallback(observeAttack);DFHack::Combat::unregisterProjectileCallback(observeProjectile);attacks.cancelPending();}
}
void reset(){journal.clear();nextId=1;discarded=0;probeStart=0;attacks.reset();attackProbeStart=0;projectiles.clear();projectileDiscarded=0;}
void shutdown(){setEnabled(false);reset();}
bool available(){return active;}
uint64_t dropped(){return discarded;}
uint64_t attacksDropped(){return attacks.dropped();}
const char* status(){return DFHack::Combat::itemContactStatus();}
flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mir::ItemContactEvent>>>
build(flatbuffers::FlatBufferBuilder& fbb,uint64_t tick) {
    prune(tick);std::vector<flatbuffers::Offset<mir::ItemContactEvent>> records;records.reserve(journal.size());
    for(const auto& event:journal)if(event.tick<=tick) {
        const auto first=df3d_events::buildItem(fbb,event.first),second=df3d_events::buildItem(fbb,event.second);
        records.push_back(mir::CreateItemContactEvent(fbb,event.id,event.tick,first,second,&event.pos));
    }
    return fbb.CreateVector(records);
}
flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mir::ResolvedAttack>>>
buildAttacks(flatbuffers::FlatBufferBuilder& fbb,uint64_t tick) {
    attacks.prune(tick);std::vector<flatbuffers::Offset<mir::ResolvedAttack>> records;records.reserve(attacks.records().size());
    for(const auto& event:attacks.records())if(event.tick<=tick) {
        const auto weapon=df3d_events::buildItem(fbb,event.weapon);
        std::vector<flatbuffers::Offset<mir::AttackContact>> contacts;contacts.reserve(event.contacts.size());
        for(const auto& contact:event.contacts) {
            const auto first=df3d_events::buildItem(fbb,contact.first),second=df3d_events::buildItem(fbb,contact.second);
            contacts.push_back(mir::CreateAttackContact(fbb,first,second));
        }
        const auto pairs=fbb.CreateVector(contacts);
        std::vector<flatbuffers::Offset<mir::AttackWound>> wounds;wounds.reserve(event.wounds.size());
        for(const auto& wound:event.wounds) {
            std::vector<flatbuffers::Offset<mir::AttackWoundPart>> parts;parts.reserve(wound.parts.size());
            for(const auto& part:wound.parts) {
                const auto token=fbb.CreateString(part.token),category=fbb.CreateString(part.category);
                parts.push_back(mir::CreateAttackWoundPart(fbb,part.body_part_id,part.layer_id,token,category,part.damage,part.anatomy));
            }
            const auto partVector=fbb.CreateVector(parts);
            wounds.push_back(mir::CreateAttackWound(fbb,wound.id,wound.victim,wound.severed,wound.popped,partVector,wound.parts_complete));
        }
        const auto woundVector=fbb.CreateVector(wounds);
        const mir::TilePos pos(event.pos.x,event.pos.y,event.pos.z);
        records.push_back(mir::CreateResolvedAttack(fbb,event.id,event.tick,event.attacker,event.defender,event.action,weapon,&pos,pairs,event.complete,woundVector,event.wounds_complete,
            static_cast<mir::AttackOutcome>(event.outcome),event.outcome_complete,event.weapon_context_complete));
    }
    return fbb.CreateVector(records);
}
uint64_t projectilesDropped(){return projectileDiscarded;}
flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mir::ProjectileCombatEvent>>>
buildProjectiles(flatbuffers::FlatBufferBuilder& fbb,uint64_t tick) {
    std::vector<flatbuffers::Offset<mir::ProjectileCombatEvent>> records;
    for(const auto& event:projectiles)if(event.tick<=tick && tick-event.tick<=600) {
        const auto ammunition=df3d_events::buildItem(fbb,event.ammunition),weapon=df3d_events::buildItem(fbb,event.weapon);
        records.push_back(mir::CreateProjectileCombatEvent(fbb,event.id,event.tick,event.projectile,event.source,event.target,
            event.kind,event.launcher,ammunition,weapon,&event.pos,event.complete));
    }
    return fbb.CreateVector(records);
}
}
