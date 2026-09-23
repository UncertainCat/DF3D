#include "df3d_world.h"
#include "effect_material.h"
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3i.hpp>

namespace df3d_godot {
using namespace godot;
namespace {
Dictionary itemSource(const wm::EventItem& item,const df3d::assets::AssetIndex* index) {
    Dictionary out;
    if(item.id<0) return out;
    out["id"]=item.id;out["type"]=String(item.type.c_str());out["subtype_raw"]=String(item.subtypeRaw.c_str());
    out["material_token"]=String(item.material.c_str());
    out["material_flags"]=int64_t(item.materialFlags);out["material_flags_known"]=item.materialFlagsKnown;
    out["melee_skill"]=String(item.meleeSkill.c_str());
    const auto* material=effectMaterial(index,item.material);
    if(*material) out["material"]=String(material);
    return out;
}
}
Array Df3dWorld::projectile_release_events(int64_t after_id) const {
    Array out;
    const auto* index=assets_?&assets_->index:nullptr;
    for (const auto& p : source_.model().projectileSamples()) {
        if (!p.firstObserved || p.sequence<=uint64_t(std::max<int64_t>(0,after_id)) || double(p.tick)>renderTick_) continue;
        Dictionary d;d["id"]=int64_t(p.sequence);d["tick"]=int64_t(p.tick);d["firer_id"]=p.firerId;
        d["projectile_id"]=int64_t(p.projectileId);d["item_id"]=p.itemId;
        d["origin"]=Vector3(p.origin.x+.5f,p.origin.z+.6f,p.origin.y+.5f);
        d["target"]=Vector3(p.target.x+.5f,p.target.z+.6f,p.target.y+.5f);
        d["ammunition"]=itemSource(p.ammunition,index);d["launcher"]=itemSource(p.launcher,index);
        const auto* ammoMaterial=effectMaterial(index,p.ammunition.material);
        const auto* launcherMaterial=effectMaterial(index,p.launcher.material);
        if(*ammoMaterial) d["ammunition_material"]=String(ammoMaterial);
        if(*launcherMaterial) d["launcher_material"]=String(launcherMaterial);
        if(p.launcher.id>=0) d["launcher_type"]=String(p.launcher.subtypeRaw.c_str());
        out.push_back(d);
    }
    return out;
}
Array Df3dWorld::unit_combat_events(int64_t after_id) const {
    Array out;
    const auto* index=assets_?&assets_->index:nullptr;
    for (const auto& e : source_.model().combatEvents()) {
        if (e.id<=uint64_t(std::max<int64_t>(0,after_id)) || double(e.tick)>renderTick_) continue;
        Dictionary d;
        d["id"]=int64_t(e.id);d["tick"]=int64_t(e.tick);d["kind"]=int(e.kind);
        d["attacker_id"]=e.attackerId;d["victim_id"]=e.victimId;d["wound_id"]=e.woundId;
        d["position"]=Vector3i(e.pos.x,e.pos.y,e.pos.z);d["report_id"]=e.reportId;
        d["source_action_id"]=e.sourceActionId;
        if(e.sourceActionId>=0) d["weapon_source"]="observed_action";
        if(e.weapon.id>=0) {
            d["weapon"]=itemSource(e.weapon,index);
            const auto* material=effectMaterial(index,e.weapon.material);
            if(*material) d["weapon_material"]=String(material);
        }
        out.push_back(d);
    }
    return out;
}
Array Df3dWorld::projectile_combat_events(int64_t after_id) const {
    Array out;
    const auto* index=assets_?&assets_->index:nullptr;
    for(const auto& e:source_.model().projectileCombatEvents()) {
        if(e.id<=uint64_t(std::max<int64_t>(0,after_id)) || double(e.tick)>renderTick_) continue;
        Dictionary d;
        d["id"]=int64_t(e.id);d["tick"]=int64_t(e.tick);d["projectile_id"]=e.projectileId;
        d["source_unit_id"]=e.sourceUnitId;d["target_unit_id"]=e.targetUnitId;
        d["kind"]=int64_t(e.kind);d["launcher"]=int64_t(e.launcher);
        d["ammunition"]=itemSource(e.ammunition,index);d["weapon"]=itemSource(e.weapon,index);
        d["position"]=Vector3i(e.pos.x,e.pos.y,e.pos.z);d["context_complete"]=e.contextComplete;
        out.push_back(d);
    }
    return out;
}
Dictionary Df3dWorld::projectile_combat_stats() const {
    Dictionary out;
    out["retained"]=int64_t(source_.model().projectileCombatEvents().size());
    out["source_dropped"]=int64_t(source_.model().projectileCombatEventsDropped());
    out["available"]=source_.model().projectileCombatEventsAvailable();return out;
}
Array Df3dWorld::resolved_attack_events(int64_t after_id) const {
    Array out;
    const auto* index=assets_?&assets_->index:nullptr;
    for(const auto& e:source_.model().resolvedAttacks()) {
        if(e.id<=uint64_t(std::max<int64_t>(0,after_id)) || double(e.tick)>renderTick_) continue;
        Dictionary d;
        d["id"]=int64_t(e.id);d["tick"]=int64_t(e.tick);
        d["attacker_id"]=e.attackerId;d["defender_id"]=e.defenderId;d["action_id"]=e.actionId;
        d["weapon"]=itemSource(e.weapon,index);d["position"]=Vector3i(e.pos.x,e.pos.y,e.pos.z);
        d["equipment_contacts_complete"]=e.equipmentContactsComplete;
        d["wounds_complete"]=e.woundsComplete;
        d["outcome"]=int64_t(e.outcome);d["outcome_complete"]=e.outcomeComplete;
        d["weapon_context_complete"]=e.weaponContextComplete;
        Array wounds;
        for(const auto& w:e.wounds) {
            Dictionary wound;wound["wound_id"]=w.woundId;wound["victim_id"]=w.victimId;
            wound["severed_part"]=w.severedPart;wound["popped_out"]=w.poppedOut;
            wound["parts_complete"]=w.partsComplete;
            Array parts;
            for(const auto& p:w.parts) {
                Dictionary part;part["body_part_id"]=p.bodyPartId;part["layer_id"]=p.layerId;
                part["body_part_token"]=String(p.bodyPartToken.c_str());
                part["body_part_category"]=String(p.bodyPartCategory.c_str());
                part["damage_flags"]=int64_t(p.damageFlags);part["anatomy_flags"]=int64_t(p.anatomyFlags);
                parts.push_back(part);
            }
            wound["parts"]=parts;wounds.push_back(wound);
        }
        d["wounds"]=wounds;
        Array contacts;
        for(const auto& c:e.contacts) {
            Dictionary pair;pair["first"]=itemSource(c.first,index);pair["second"]=itemSource(c.second,index);
            contacts.push_back(pair);
        }
        d["contacts"]=contacts;out.push_back(d);
    }
    return out;
}
Dictionary Df3dWorld::resolved_attack_stats() const {
    Dictionary out;
    out["retained"]=int64_t(source_.model().resolvedAttacks().size());
    out["source_dropped"]=int64_t(source_.model().resolvedAttacksDropped());
    out["available"]=source_.model().resolvedAttacksAvailable();return out;
}
Array Df3dWorld::item_contact_events(int64_t after_id) const {
    Array out;
    const auto* index=assets_?&assets_->index:nullptr;
    for(const auto& e:source_.model().itemContacts()) {
        if(e.id<=uint64_t(std::max<int64_t>(0,after_id)) || double(e.tick)>renderTick_) continue;
        Dictionary d;
        d["id"]=int64_t(e.id);d["tick"]=int64_t(e.tick);
        d["first"]=itemSource(e.first,index);d["second"]=itemSource(e.second,index);
        d["position"]=Vector3i(e.pos.x,e.pos.y,e.pos.z);
        out.push_back(d);
    }
    return out;
}
Dictionary Df3dWorld::item_contact_stats() const {
    Dictionary out;
    out["retained"]=int64_t(source_.model().itemContacts().size());
    out["source_dropped"]=int64_t(source_.model().itemContactsDropped());
    out["available"]=source_.model().itemContactsAvailable();
    return out;
}
Array Df3dWorld::effect_events(int64_t after_id) const {
    Array out;
    for(const auto& e:source_.model().reportEvents()) {
        if(e.id<=uint64_t(std::max<int64_t>(0,after_id)) || double(e.tick)>renderTick_) continue;
        Dictionary d;
        d["id"]=int64_t(e.id);d["tick"]=int64_t(e.tick);d["report_id"]=e.reportId;d["type"]=String(e.type.c_str());
        d["position"]=Vector3i(e.pos.x,e.pos.y,e.pos.z);d["position2"]=Vector3i(e.pos2.x,e.pos2.y,e.pos2.z);
        d["has_position"]=e.hasPosition;d["has_secondary"]=e.hasSecondary;
        d["repeat_count"]=int64_t(e.repeatCount);d["speaker_id"]=e.speakerId;
        out.push_back(d);
    }
    return out;
}
Dictionary Df3dWorld::effect_event_stats() const {
    Dictionary out;
    out["retained"]=int64_t(source_.model().reportEvents().size());out["source_dropped"]=int64_t(source_.model().reportEventsDropped());
    out["latest_id"]=int64_t(source_.model().latestReportEventId());
    return out;
}
}
