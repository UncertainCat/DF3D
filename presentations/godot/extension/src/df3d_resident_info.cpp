#include "df3d_world.h"
#include <algorithm>
#include <godot_cpp/classes/time.hpp>
using namespace godot;
namespace df3d_godot {
void Df3dWorld::reconcile_resident_icons() {
    const auto epoch=sessionClient_ && sessionClient_->state().fortressValid?sessionClient_->state().fortressEpoch:0;
    const auto snapshot=residentInfo_.cached(wm::ResidentInfoDemand::Residents);
    if(!epoch || !snapshot || snapshot->worldEpoch!=epoch) {
        residentIcons_.clear();residentIconPublication_.reset();return;
    }
    if(snapshot==residentIconPublication_)return;
    if(!residentIconPublication_ || residentIconPublication_->worldEpoch!=epoch)residentIcons_.clear();
    std::unordered_set<int32_t> retained;
    for(const auto& row:snapshot->citizens)retained.insert(row.id);
    std::erase_if(residentIcons_,[&](const auto& entry){return !retained.contains(entry.first);});
    residentIconPublication_=snapshot;
}
Ref<Texture2D> Df3dWorld::resident_icon(int64_t id) {
    if(id<0 || id>INT32_MAX || !assets_)return {};
    reconcile_resident_icons();
    if(!residentIconPublication_)return {};
    const auto& rows=residentIconPublication_->citizens;
    const auto it=std::find_if(rows.begin(),rows.end(),[id](const auto& row){return row.id==id;});
    if(it==rows.end())return {};
    auto cached=residentIcons_.find(int32_t(id));
    if(cached!=residentIcons_.end() && cached->second.source==it->sheetIcon) {
        cached->second.used=++residentIconUse_;
        return cached->second.texture;
    }
    // Bound GPU residency even if a user scrolls through thousands of residents.
    if(cached==residentIcons_.end() && residentIcons_.size()>=256) {
        auto oldest=std::min_element(residentIcons_.begin(),residentIcons_.end(),[](const auto& a,const auto& b){return a.second.used<b.second.used;});
        residentIcons_.erase(oldest);
    }
    auto texture=composite_appearance_texture(it->sheetIcon,false);
    residentIcons_[int32_t(id)]={it->sheetIcon,texture,++residentIconUse_};
    return texture;
}
void Df3dWorld::update_resident_info() {
    const auto start=Time::get_singleton()->get_ticks_usec();
    const uint64_t epoch=sessionClient_ && sessionClient_->state().fortressValid ? sessionClient_->state().fortressEpoch : 0;
    residentInfo_.update(start/1000,epoch);
    reconcile_resident_icons();
    creatureInfo_.update(start/1000,epoch);
    residentInfoLastUpdateUs_=Time::get_singleton()->get_ticks_usec()-start;
}
void Df3dWorld::demand_resident_info(int64_t demand) {
    if(demand<0 || demand>3)return;
    residentInfo_.setDemand(static_cast<wm::ResidentInfoDemand>(demand));
}
void Df3dWorld::refresh_resident_info() { residentInfo_.refresh(); }
void Df3dWorld::demand_creature_info(int64_t id) {
    if(id< -1 || id>INT32_MAX)return;
    creatureInfo_.demand(int32_t(id));
}
Dictionary Df3dWorld::creature_info_state(int64_t id) {
    Dictionary result;
    if(id<0 || id>INT32_MAX)return result;
    const auto snapshot=creatureInfo_.snapshot(int32_t(id));
    if(snapshot!=creatureInfoConverted_) {
        creatureInfoConverted_=snapshot;creatureInfoRows_=Dictionary();
        if(snapshot) {
            const auto& c=snapshot->detail;Array sections;
            static const char* keys[]={"identity","skills","attributes","health","inventory","relationships","personality","values","needs","dreams","emotions","preferences","military","labors","rooms","groups","memories","treatment","health_history","knowledge","uniform","kills","workshops","locations","work_animals"};
            for(const auto& s:c.sections) {
                Dictionary section;Array records;
                for(const auto& r:s.records){Dictionary row;Array facts;
                    for(const auto& f:r.facts){Dictionary fact;fact["key"]=String::utf8(f.key.c_str());fact["text"]=String::utf8(f.text.c_str());fact["number"]=f.number;fact["has_number"]=f.hasNumber;fact.make_read_only();facts.push_back(fact);}
                    facts.make_read_only();row["id"]=r.id;row["related_id"]=r.relatedId;row["name"]=String::utf8(r.name.c_str());row["facts"]=facts;row.make_read_only();records.push_back(row);
                }
                records.make_read_only();section["kind"]=int(s.kind);section["key"]=String(keys[int(s.kind)]);section["available"]=s.available;section["truncated"]=s.truncated;section["reason"]=String::utf8(s.reason.c_str());section["records"]=records;section.make_read_only();sections.push_back(section);
            }
            sections.make_read_only();auto& out=creatureInfoRows_;
            out["unit_id"]=c.unitId;out["name"]=String::utf8(c.name.c_str());out["species"]=String::utf8(c.species.c_str());out["profession"]=String::utf8(c.profession.c_str());out["job"]=String::utf8(c.job.c_str());out["age"]=c.age;out["sex"]=c.sex;out["origin"]=Vector3i(c.x,c.y,c.z);out["captured_tick"]=int64_t(c.capturedTick);out["complete"]=c.complete;out["sections"]=sections;
        }
        creatureInfoRows_.make_read_only();
    }
    const auto status=creatureInfo_.status(int32_t(id));
    result["unit_id"]=id;result["world_epoch"]=int64_t(status.worldEpoch);result["generation"]=snapshot?int64_t(snapshot->generation):0;
    result["complete"]=bool(snapshot);result["loading"]=status.loading;result["stale"]=status.stale;result["error"]=String::utf8(status.error.c_str());
    result["capture_started_ms"]=snapshot?int64_t(snapshot->captureStartedMs):0;result["capture_completed_ms"]=snapshot?int64_t(snapshot->captureCompletedMs):0;result["detail"]=creatureInfoRows_;
    return result;
}
Dictionary Df3dWorld::resident_info_state() {
    const auto snapshot=residentInfo_.snapshot();
    // Convert only a new immutable publication. Never rebuild UI arrays per frame.
    if(snapshot!=residentInfoConverted_) {
        residentInfoConverted_=snapshot;
        residentInfoRows_=Dictionary();
        Array citizens,details,orders;
        if(snapshot) {
            for(const auto& u:snapshot->citizens) {
                Dictionary row;
                Array assignments;
                for(const auto& d:u.assignedDetails){Dictionary detail;detail["index"]=d.index;detail["icon"]=d.icon;detail["name"]=String::utf8(d.name.c_str());detail.make_read_only();assignments.push_back(detail);}
                assignments.make_read_only();row["assigned_details"]=assignments;row["only_assigned_jobs"]=u.onlyAssignedJobs;row["social_activity"]=u.socialActivity;
                row["sheet_icon_layers"]=int(u.sheetIcon.layers.size());
                row["id"]=u.id;row["name"]=String::utf8(u.name.c_str());
                row["profession"]=String::utf8(u.profession.c_str());row["job"]=String::utf8(u.job.c_str());
                row["origin"]=Vector3i(u.x,u.y,u.z);row["can_focus"]=u.canFocus;row["reason"]=String::utf8(u.reason.c_str());
                row["profession_color"]=u.professionColor;row["profession_id"]=u.professionId;row["job_type"]=u.jobType;
                row["age"]=u.age;row["stress"]=u.stress;row["has_stress"]=u.hasStress;
                row.make_read_only();citizens.push_back(row);
            }
            for(const auto& d:snapshot->details) {
                Dictionary row;Array assigned,names;
                for(auto id:d.assignedUnits)assigned.push_back(id);
                for(const auto& name:d.laborNames)names.push_back(String::utf8(name.c_str()));
                assigned.make_read_only();names.make_read_only();
                row["index"]=d.index;row["revision"]=int64_t(d.revision);row["name"]=String::utf8(d.name.c_str());
                row["mode"]=d.mode;row["assigned_units"]=assigned;row["labor_names"]=names;
                row.make_read_only();details.push_back(row);
            }
            for(const auto& o:snapshot->orders) {
                Dictionary row;Array conditions;
                for(const auto& c:o.conditions) {Dictionary condition;condition["description"]=String::utf8(c.description.c_str());condition.make_read_only();conditions.push_back(condition);}
                conditions.make_read_only();
                row["id"]=o.id;row["name"]=String::utf8(o.name.c_str());row["remaining"]=o.remaining;row["total"]=o.total;
                row["validated"]=o.validated;row["active"]=o.active;row["workshop_id"]=o.workshopId;row["conditions"]=conditions;
                row.make_read_only();orders.push_back(row);
            }
        }
        citizens.make_read_only();details.make_read_only();orders.make_read_only();
        residentInfoRows_["citizens"]=citizens;residentInfoRows_["details"]=details;residentInfoRows_["orders"]=orders;
        residentInfoRows_.make_read_only();
    }
    const auto& status=residentInfo_.status();
    Dictionary result;
    result["demand"]=int(status.demand);result["world_epoch"]=int64_t(status.worldEpoch);
    result["generation"]=snapshot?int64_t(snapshot->generation):0;
    result["complete"]=bool(snapshot);result["loading"]=status.loading;result["stale"]=status.stale;
    result["error"]=String::utf8(status.error.c_str());result["rows"]=residentInfoRows_;
    result["capture_started_ms"]=snapshot?int64_t(snapshot->captureStartedMs):0;
    result["capture_completed_ms"]=snapshot?int64_t(snapshot->captureCompletedMs):0;
    result["detail_list_revision"]=snapshot?int64_t(snapshot->detailListRevision):0;
    result["update_us"]=int64_t(residentInfoLastUpdateUs_);
    return result;
}
}
