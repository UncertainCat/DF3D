#include "df3d_world.h"
#include "management_codecs.h"
#include <unordered_set>
#include <algorithm>
#include <godot_cpp/variant/packed_byte_array.hpp>
namespace df3d_godot {
using namespace godot;

Dictionary Df3dWorld::poll_session() {
    Dictionary result;
    std::string error;
    if (!sessionClient_) sessionClient_ = wm::SessionClient::open(error);
    if (!sessionClient_) {
        result["phase"] = 4;
        result["message"] = String::utf8(error.c_str());
        return result;
    }
    sessionClient_->poll();
    const auto& state = sessionClient_->state();
    result["phase"] = int(state.phase);
    result["revision"] = int64_t(state.revision);
    result["request_seq"] = int64_t(state.requestSeq);
    result["request_status"] = int(state.requestStatus);
    result["request_action"] = int(state.requestAction);
    result["fortress_valid"] = state.fortressValid;
    result["paused"] = state.paused;
    result["year"] = state.year;
    result["year_tick"] = state.yearTick;
    result["fort_name"] = String::utf8(state.fortName.c_str());
    result["fort_original_name"] = String::utf8(state.fortOriginalName.c_str());
    result["fortress_rank"] = state.fortressRank;
    result["fortress_capital"] = state.fortressCapital;
    result["moon_phase"] = state.moonPhase;
    result["active_save_id"] = String::utf8(state.activeSaveId.c_str());
    result["saved_save_id"] = String::utf8(state.savedSaveId.c_str());
    result["can_save"] = state.canSave;
    result["can_save_return"] = state.canSaveReturn;
    result["fortress_epoch"]=int64_t(state.fortressEpoch);
    result["request_fortress_epoch"]=int64_t(state.requestFortressEpoch);
    if(state.saveDestinations.receipt) {
        Dictionary catalog;Array destinations;
        catalog["receipt"]=int64_t(state.saveDestinations.receipt);
        catalog["fortress_epoch"]=int64_t(state.saveDestinations.fortressEpoch);
        for(const auto& destination:state.saveDestinations.destinations) {
            Dictionary row;row["id"]=String::utf8(destination.id.c_str());row["folder"]=String::utf8(destination.folder.c_str());destinations.push_back(row);
        }
        catalog["destinations"]=destinations;result["save_destinations"]=catalog;
    }
    Dictionary summary;const auto& f=state.fortressSummary;
    summary["available"]=f.available;summary["population"]=f.population;summary["stress_available"]=f.stressAvailable;
    summary["elevation_offset"]=f.elevationOffset;summary["level_count"]=int64_t(f.levelCount);
    Array stress;for(auto value:f.stressCounts)stress.push_back(int64_t(value));summary["stress_counts"]=stress;
    summary["resources_available"]=f.resourcesAvailable;
    summary["bookkeeper_precision"]=f.bookkeeperPrecision;
    Array resources;for(auto value:f.resourceCounts)resources.push_back(int64_t(value));summary["resource_counts"]=resources;
    result["fortress_summary"]=summary;
    Array notificationGroups;
    for(const auto& group:state.activeNotifications) {
        Dictionary row;row["category"]=int(group.category);
        row["category_name"]=wm::notificationCategoryName(group.category);
        row["report_count"]=int64_t(group.reportCount);row["unit_report_count"]=int64_t(group.unitReportCount);row["complete"]=group.complete;
        Array ids,units;for(auto id:group.reportIds)ids.push_back(id);
        for(auto ref:group.unitReports){Dictionary unit;unit["unit_id"]=ref.unitId;unit["category"]=int(ref.category);units.push_back(unit);}
        row["report_ids"]=ids;row["unit_reports"]=units;notificationGroups.push_back(row);
    }
    result["active_notifications"]=notificationGroups;
    result["active_notifications_complete"]=state.activeNotificationsComplete;
    Array alertIds;for(auto id:state.alertButtonReportIds)alertIds.push_back(id);result["alert_button_report_ids"]=alertIds;
    result["alert_button_report_count"]=int64_t(state.alertButtonReportCount);result["alert_button_complete"]=state.alertButtonComplete;
    const auto& interruption=state.interruption;
    Dictionary notice;notice["kind"]=int(interruption.kind);notice["receipt"]=int64_t(interruption.receipt);notice["text"]=String::utf8(interruption.text.c_str());notice["reason"]=String::utf8(interruption.reason.c_str());notice["popup_count"]=int64_t(interruption.popupCount);notice["can_acknowledge"]=interruption.canAcknowledge;result["interruption"]=notice;
    const auto& p=state.petition;Dictionary petition;
    petition["id"]=p.id;petition["receipt"]=int64_t(p.receipt);petition["can_review"]=p.canReview;petition["can_respond"]=p.canRespond;petition["can_close"]=p.canClose;petition["reason"]=String::utf8(p.reason.c_str());petition["guildhall_value"]=p.guildhallValue;petition["grand_guildhall_value"]=p.grandGuildhallValue;
    if(p.hasAgreement){const auto& a=p.agreement;Dictionary row;row["id"]=a.id;row["status"]=a.status;row["not_approved"]=a.notApproved;row["concluded"]=a.concluded;row["continuing"]=a.continuing;row["complete"]=a.complete;row["summary"]=String::utf8(a.summary.c_str());row["reason"]=String::utf8(a.reason.c_str());Array ds,ps;
      for(const auto& d:a.details){Dictionary v;v["id"]=d.id;v["kind"]=d.kind;v["site_id"]=d.siteId;v["year"]=d.year;v["year_tick"]=d.yearTick;v["applicant_party"]=d.applicantParty;v["government_party"]=d.governmentParty;v["location_type"]=d.locationType;v["tier"]=d.tier;v["profession"]=d.profession;v["deity_type"]=d.deityType;v["deity_id"]=d.deityId;v["description"]=String::utf8(d.description.c_str());ds.push_back(v);}
      for(const auto& q:a.parties){Dictionary v;v["id"]=q.id;v["name"]=String::utf8(q.name.c_str());Array es,hs;for(auto id:q.entityIds)es.push_back(id);for(auto id:q.histfigIds)hs.push_back(id);v["entity_ids"]=es;v["histfig_ids"]=hs;ps.push_back(v);}row["details"]=ds;row["parties"]=ps;petition["agreement"]=row;
    }
    result["petition"]=petition;
    result["message"] = String::utf8(state.message.c_str());
    result["error"] = String::utf8(sessionClient_->lastError().c_str());
    Array saves;
    for (const auto& save : state.saves) {
        Dictionary row;
        row["id"] = String::utf8(save.id.c_str());
        row["fort"] = String::utf8(save.fortName.c_str());
        row["world"] = String::utf8(save.worldName.c_str());
        row["year"] = save.year;
        saves.push_back(row);
    }
    result["saves"] = saves;
    return result;
}

int64_t Df3dWorld::load_fortress(const String& id) {
    return sessionClient_ ? int64_t(sessionClient_->sendLoadSave(id.utf8().get_data())) : 0;
}

Dictionary Df3dWorld::poll_management() { return pollManagement(true); }
Dictionary Df3dWorld::poll_management_header() { return pollManagement(false); }

Dictionary Df3dWorld::management_payload(int64_t epoch, int64_t revision, int64_t sequence) const {
    if (!managementClient_ || !managementClient_->transportAlive()) return {};
    const auto& state = managementClient_->state();
    if (epoch <= 0 || revision <= 0 || sequence <= 0 ||
        uint64_t(epoch) != state.worldEpoch || uint64_t(revision) != state.revision ||
        uint64_t(sequence) != state.requestSeq) return {};
    // The main-thread service requests the payload only for the matching terminal
    // receipt. Do not poll again between identity validation and conversion.
    return managementState(true);
}

Dictionary Df3dWorld::pollManagement(bool includePayload) {
    PerfScope profile("management.poll", nullptr, df3d::profiling::detailed());
    Dictionary result; std::string error;
    if (!managementClient_) managementClient_=wm::ManagementClient::open(error);
    if (!managementClient_) {result["transport_alive"]=false;result["status"]=int(wm::ManagementStatus::Rejected);result["message"]=String::utf8(error.c_str());return result;}
    { PerfScope profile("management.transport_poll", nullptr, df3d::profiling::detailed()); managementClient_->poll(); }
    if (!managementClient_->transportAlive()) {
        result["transport_alive"]=false;
        result["status"]=int(wm::ManagementStatus::Rejected);
        result["message"]=String::utf8(managementClient_->lastError().c_str());
        // Report this loss before a replacement can reuse its sequence space.
        // Always retire a dead owner, including one lost during recovery.
        managementClient_.reset();
        return result;
    }
    return managementState(includePayload);
}

Dictionary Df3dWorld::managementState(bool includePayload) const {
    Dictionary result;
    const auto& s=managementClient_->state();
    result["transport_alive"]=true;
    result["revision"]=int64_t(s.revision);result["world_epoch"]=int64_t(s.worldEpoch);
    result["request_seq"]=int64_t(s.requestSeq);result["action"]=int(s.action);result["status"]=int(s.status);
    result["message"]=String::utf8(s.message.c_str());result["error"]=String::utf8(managementClient_->lastError().c_str());
    if (!includePayload) return result;
    { PerfScope profile("management.convert_construction", nullptr, df3d::profiling::detailed()); management::writeConstruction(result, s); }
    management::writeArea(result, s.area);
    management::writeProduction(result, s.production);
    if(s.creatureExpel) {
        Dictionary expel;expel["outcome"]=int(s.creatureExpel->outcome);
        if(s.creatureExpel->preview) {
            const auto& p=*s.creatureExpel->preview;Dictionary preview;Array units,destinations;
            preview["unit_id"]=p.unitId;preview["eligible"]=p.eligible;preview["reason"]=p.reason;
            for(const auto& v:p.units) {
                Dictionary row,color,icon;Array primary,alternate,pages,palettes,layers;
                row["id"]=v.id;row["name"]=String::utf8(v.name.c_str());
                for(auto c:v.nameColor.color)primary.push_back(int(c));
                for(auto c:v.nameColor.alternate)alternate.push_back(int(c));
                color["color"]=primary;color["alternate"]=alternate;color["effect"]=int(v.nameColor.effect);row["name_color"]=color;
                for(const auto& name:v.sheetIcon.tilePages)pages.push_back(String::utf8(name.c_str()));
                for(const auto& name:v.sheetIcon.palettes)palettes.push_back(String::utf8(name.c_str()));
                for(const auto& l:v.sheetIcon.layers) {Array layer;
                    for(int value:{int(l.page),int(l.tileX),int(l.tileY),int(l.cellsX),int(l.cellsY),int(l.palette),int(l.paletteRow),int(l.paletteKeyRow),int(l.offsetX),int(l.offsetY)})layer.push_back(value);
                    layers.push_back(layer);
                }
                icon["tile_pages"]=pages;icon["palettes"]=palettes;icon["layers"]=layers;row["sheet_icon"]=icon;units.push_back(row);
            }
            for(const auto& v:p.destinations) {Dictionary row;row["id"]=v.id;row["name"]=String::utf8(v.name.c_str());destinations.push_back(row);}
            preview["units"]=units;preview["destinations"]=destinations;expel["preview"]=preview;
        }
        result["creature_expel"]=expel;
    }
    if(s.creatureWorkshop) {
        const auto& w=*s.creatureWorkshop;Dictionary value;
        value["unit_id"]=w.unitId;value["building_id"]=w.buildingId;value["outcome"]=int(w.outcome);
        result["creature_workshop"]=value;
    }
    if(s.creatureLocation) {
        const auto& w=*s.creatureLocation;Dictionary value;
        value["unit_id"]=w.unitId;value["occupation_id"]=w.occupationId;value["outcome"]=int(w.outcome);
        result["creature_location"]=value;
    }
    if(s.residents) {
        Dictionary value;PackedInt32Array ids;
        for(auto id:s.residents->unitIds)ids.push_back(id);
        value["unit_ids"]=ids;result["residents"]=value;
    }
    if(s.residentsSpecialization) {
        const auto& v=*s.residentsSpecialization;Dictionary value;
        value["unit_id"]=v.unitId;value["outcome"]=int(v.outcome);value["only_assigned"]=v.onlyAssigned;
        result["residents_specialization"]=value;
    }
    if(s.jobSettingsEdit) {
        const auto& v=*s.jobSettingsEdit;Dictionary value;value["job_id"]=v.jobId;value["building_id"]=v.buildingId;value["unit_id"]=v.unitId;
        value["outcome"]=int(v.outcome);result["job_settings_edit"]=value;
    }
    if(s.jobSettings) {
        const auto& v=*s.jobSettings;Dictionary value;Array options,choices;
        value["job_id"]=v.jobId;value["building_id"]=v.buildingId;value["unit_id"]=v.unitId;value["revision"]=int64_t(v.revision);value["caption"]=String::utf8(v.caption.c_str());
        value["selected_option"]=int(v.selectedOption);value["choices_revision"]=int64_t(v.choicesRevision);value["total"]=int64_t(v.total);value["cursor"]=int64_t(v.cursor);value["next_cursor"]=int64_t(v.nextCursor);
        for(const auto& o:v.options){Dictionary row;row["kind"]=int(o.kind);row["index"]=o.index;row["caption"]=String::utf8(o.caption.c_str());options.push_back(row);}
        for(const auto& c:v.choices){Dictionary row;row["id"]=c.id;row["caption"]=String::utf8(c.caption.c_str());row["estimated"]=c.estimated;if(c.countCaption)row["count_caption"]=String::utf8(c.countCaption->c_str());choices.push_back(row);}
        if(v.currentValue)value["current_value"]=String::utf8(v.currentValue->c_str());
        if(v.settingHeading)value["setting_heading"]=String::utf8(v.settingHeading->c_str());
        if(v.art)value["art"]=df3d_godot::management::writeArtState(*v.art);
        value["options"]=options;value["choices"]=choices;result["job_settings"]=value;
    }
    if(s.residentsActivity) {
        const auto& v=*s.residentsActivity;Dictionary value;Array words,links;
        value["unit_id"]=v.unitId;value["activity_id"]=v.activityId;value["event_id"]=v.eventId;value["columns"]=int(v.columns);value["max_y"]=v.maxY;
        for(const auto& w:v.words){Dictionary word;Array rgb;rgb.push_back(int(w.red));rgb.push_back(int(w.green));rgb.push_back(int(w.blue));
            word["text"]=String::utf8(w.text.c_str());word["rgb"]=rgb;word["link"]=w.link;word["flags"]=int(w.flags);word["x"]=w.x;word["y"]=w.y;words.push_back(word);}
        for(const auto& l:v.links){Dictionary link;link["type"]=l.type;link["id"]=l.id;link["subid"]=l.subid;links.push_back(link);}
        value["words"]=words;value["links"]=links;result["residents_activity"]=value;
    }
    if(s.stoneUse) {
        const auto& v=*s.stoneUse;Dictionary value;Array rows,flags;
        for(const auto& row:v.rows){Dictionary d;d["category"]=row.category;d["index"]=row.index;d["restricted"]=row.restricted;
            d["name"]=String::utf8(row.name.c_str());d["uses"]=String::utf8(row.uses.c_str());d["magma_safe"]=row.magmaSafe;d["material_token"]=String::utf8(row.materialToken.c_str());rows.push_back(d);}
        for(auto flag:v.restrictions)flags.push_back(int(flag));
        value["outcome"]=int(v.outcome);value["rows"]=rows;value["restrictions"]=flags;result["stone_use"]=value;
        if(v.outcome==wm::StoneUseOutcome::Unknown)result["outcome"]="unknown";
    }
    if(s.kitchenMenu) {
        const auto& v=*s.kitchenMenu;Dictionary value;Array rows,exclusions;
        const auto key=[](const wm::KitchenFoodKey& k){Dictionary d;d["item_type"]=k.itemType;d["item_subtype"]=k.itemSubtype;d["mat_type"]=k.matType;d["mat_index"]=k.matIndex;return d;};
        for(const auto& row:v.rows){Dictionary d,receipt;receipt["key"]=key(row.receipt.key);receipt["count"]=row.receipt.count;receipt["capabilities"]=int(row.receipt.capabilities);
            d["receipt"]=receipt;d["name"]=String::utf8(row.name.c_str());d["count_caption"]=String::utf8(row.countCaption.c_str());d["estimated"]=row.estimated;d["excluded"]=int(row.excluded);d["material_token"]=String::utf8(row.materialToken.c_str());rows.push_back(d);}
        for(const auto& row:v.exclusions){Dictionary d;d["key"]=key(row.key);d["flags"]=int(row.flags);exclusions.push_back(d);}
        value["outcome"]=int(v.outcome);value["rows"]=rows;value["exclusions"]=exclusions;result["kitchen_menu"]=value;
        if(v.outcome==wm::KitchenMenuOutcome::Unknown)result["outcome"]="unknown";
    }
    if(s.chores) {
        const auto& v=*s.chores;Dictionary value;value["outcome"]=int(v.outcome);Array children,labors;
        if(v.snapshot){Dictionary snap;PackedInt32Array ids,exempted;Array settings;
            snap["enabled"]=v.snapshot->enabled;
            for(int32_t id:v.snapshot->children)ids.push_back(id);
            for(int32_t id:v.snapshot->exempted)exempted.push_back(id);
            for(const auto& row:v.snapshot->labors){Dictionary entry;entry["id"]=row.id;entry["enabled"]=row.enabled;settings.push_back(entry);}
            snap["children"]=ids;snap["exempted"]=exempted;snap["labors"]=settings;value["snapshot"]=snap;}
        for(const auto& row:v.children){Dictionary entry;entry["id"]=row.id;entry["caption"]=String::utf8(row.caption.c_str());children.push_back(entry);}
        for(const auto& row:v.labors){Dictionary entry;entry["id"]=row.id;entry["caption"]=String::utf8(row.caption.c_str());labors.push_back(entry);}
        value["children"]=children;value["labors"]=labors;result["chores"]=value;
        if(v.outcome==wm::ChoresOutcome::Unknown)result["outcome"]="unknown";
    }
    if(s.hunterAmmunition) {
        const auto& v=*s.hunterAmmunition;Dictionary value;Array specs,rules,types,materials;
        value["outcome"]=int(v.outcome);value["item_type"]=v.itemType;value["item_subtype"]=v.itemSubtype;
        for(const auto& row:v.specs){Dictionary item;PackedInt32Array assigned;
            item["item_type"]=row.itemType;item["item_subtype"]=row.itemSubtype;item["material_class"]=row.materialClass;
            item["mattype"]=row.matType;item["matindex"]=row.matIndex;item["amount"]=row.amount;item["flags"]=int64_t(row.flags);
            for(auto id:row.assigned)assigned.push_back(id);item["assigned"]=assigned;specs.push_back(item);}
        for(const auto& row:v.rules){Dictionary item;Array stacks;item["caption"]=String::utf8(row.caption.c_str());item["quantity"]=row.quantity;
            for(const auto& entry:row.items){Dictionary stack,appearance;const auto& a=entry.appearance;
                appearance["material_token"]=String::utf8(a.materialToken.c_str());appearance["subtype_raw"]=String::utf8(a.subtypeRaw.c_str());appearance["color_token"]=String::utf8(a.colorToken.c_str());appearance["stack"]=a.stack;appearance["flags"]=int(a.flags);
                stack["id"]=entry.id;stack["caption"]=String::utf8(entry.caption.c_str());stack["quantity"]=entry.quantity;stack["appearance"]=appearance;stacks.push_back(stack);}
            item["items"]=stacks;rules.push_back(item);}
        for(const auto& row:v.types){Dictionary item;item["item_type"]=row.itemType;item["item_subtype"]=row.itemSubtype;item["foreign"]=row.foreign;item["caption"]=String::utf8(row.caption.c_str());types.push_back(item);}
        for(const auto& row:v.materials){Dictionary item;item["material_class"]=row.materialClass;item["mattype"]=row.matType;item["matindex"]=row.matIndex;item["caption"]=String::utf8(row.caption.c_str());materials.push_back(item);}
        value["specs"]=specs;value["rules"]=rules;value["types"]=types;value["materials"]=materials;result["hunter_ammunition"]=value;
        if(v.outcome==wm::HunterAmmunitionOutcome::Unknown)result["outcome"]="unknown";
    }
    if(s.standingOrders) {
        const auto& v=*s.standingOrders;Dictionary value;Array rows;
        value["category"]=v.category;value["outcome"]=int(v.outcome);
        for(const auto& row:v.settings){Dictionary item;item["id"]=row.id;item["value"]=row.value;item["visible"]=row.visible;item["editable"]=row.editable;rows.push_back(item);}
        value["settings"]=rows;result["standing_orders"]=value;
        if(v.outcome==wm::StandingOrdersOutcome::Unknown)result["outcome"]="unknown";
    }
    if(s.workDetailSettings) {
        const auto& v=*s.workDetailSettings;Dictionary value;Array catalog;PackedInt32Array labors;
        value["detail_index"]=v.detailIndex;value["revision"]=int64_t(v.revision);value["editable"]=v.editable;value["no_modify"]=v.noModify;
        for(auto id:v.labors)labors.push_back(id);
        for(const auto& entry:v.catalog){Dictionary row;row["id"]=entry.id;row["caption"]=String::utf8(entry.caption.c_str());catalog.push_back(row);}
        value["labors"]=labors;value["catalog"]=catalog;result["work_detail_settings"]=value;
    }
    if(s.residentsRows) {
        Dictionary value;Array rows;
        for(const auto& v:s.residentsRows->rows) {
            Dictionary row,color,activity;Array primary,alternate;
            if(v.workDetailSkills) {
                Array skills;for(const auto& skill:*v.workDetailSkills){Dictionary value;value["skill"]=skill.skill;value["rating"]=skill.rating;value["caption"]=String::utf8(skill.caption.c_str());skills.push_back(value);}
                row["skills"]=skills;row["member"]=bool(v.detailMember);
            }
            row["id"]=v.id;row["combined"]=String::utf8(v.combined.c_str());row["name"]=String::utf8(v.name.c_str());
            row["profession"]=String::utf8(v.profession.c_str());row["first_line"]=String::utf8(v.firstLine.c_str());
            row["second_line"]=String::utf8(v.secondLine.c_str());
            if(v.assignments) {
                Array entries;
                for(const auto& e:*v.assignments) {Dictionary entry;entry["kind"]=int(e.kind);entry["id"]=e.id;entry["type"]=e.type;entry["subtype"]=e.subtype;entry["custom"]=e.custom;entry["name"]=String::utf8(e.name.c_str());entry["custom_code"]=String::utf8(e.customCode.c_str());entries.push_back(entry);}
                row["assignments"]=entries;
            }
            if(v.specialization) {Dictionary state;state["only_assigned"]=v.specialization->onlyAssigned;state["revision"]=int64_t(v.specialization->revision);row["specialization"]=state;}
            if(v.happiness>=0)row["happiness"]=int(v.happiness);
            if(v.jobTarget){Dictionary target;target["job_id"]=v.jobTarget->jobId;target["building_id"]=v.jobTarget->buildingId;row["job_target"]=target;}
            if(v.activityTarget){Dictionary target;target["activity_id"]=v.activityTarget->activityId;target["event_id"]=v.activityTarget->eventId;row["activity_target"]=target;}
            if(v.position)row["position"]=Vector3i(v.position->x,v.position->y,v.position->z);
            for(auto c:v.nameColor.color)primary.push_back(int(c));
            for(auto c:v.nameColor.alternate)alternate.push_back(int(c));
            color["color"]=primary;color["alternate"]=alternate;color["effect"]=int(v.nameColor.effect);row["name_color"]=color;
            activity["caption"]=String::utf8(v.activity.c_str());activity["fg"]=int(v.activityForeground);
            activity["bg"]=int(v.activityBackground);activity["bright"]=v.activityBright;row["activity"]=activity;
            if(v.sheetIcon) {
                Dictionary icon;Array pages,palettes,layers;
                for(const auto& name:v.sheetIcon->tilePages)pages.push_back(String::utf8(name.c_str()));
                for(const auto& name:v.sheetIcon->palettes)palettes.push_back(String::utf8(name.c_str()));
                for(const auto& l:v.sheetIcon->layers) {
                    Array layer;
                    for(int n:{int(l.page),int(l.tileX),int(l.tileY),int(l.cellsX),int(l.cellsY),int(l.palette),int(l.paletteRow),int(l.paletteKeyRow),int(l.offsetX),int(l.offsetY)})layer.push_back(n);
                    layers.push_back(layer);
                }
                icon["tile_pages"]=pages;icon["palettes"]=palettes;icon["layers"]=layers;row["sheet_icon"]=icon;
            }
            rows.push_back(row);
        }
        value["rows"]=rows;result["residents_rows"]=value;
    }
    if(s.creatureAnimal) {
        const auto& w=*s.creatureAnimal;Dictionary value;
        value["unit_id"]=w.unitId;value["animal_id"]=w.animalId;value["outcome"]=int(w.outcome);value["assigned"]=w.assigned;
        result["creature_animal"]=value;
    }
    if(s.creatureKnowledge) {
        const auto& k=*s.creatureKnowledge;Dictionary value;
        value["unit_id"]=k.unitId;value["kind"]=k.kind;value["id"]=k.id;
        value["outcome"]=int(k.outcome);value["text"]=String::utf8(k.text.c_str());
        result["creature_knowledge"]=value;
    }
    if(s.creaturePosition) {
        const auto& p=*s.creaturePosition;Dictionary value;
        value["unit_id"]=p.unitId;value["position"]=Vector3i(p.position.x,p.position.y,p.position.z);
        result["creature_position"]=value;
    }
    if(s.creatureHeader) {
        const auto& h=*s.creatureHeader;Dictionary header;
        header["outcome"]=int(h.outcome);header["mutated"]=h.mutated;
        if(h.snapshot) {
            const auto& v=*h.snapshot;Dictionary snapshot;
            snapshot["unit_id"]=v.unitId;snapshot["historical_figure_id"]=v.historicalFigureId;
            snapshot["has_figure"]=v.hasFigure;snapshot["revision"]=v.revision;
            snapshot["nickname"]=String::utf8(v.nickname.c_str());snapshot["profession"]=String::utf8(v.profession.c_str());
            snapshot["figure_nickname"]=String::utf8(v.figureNickname.c_str());header["snapshot"]=snapshot;
        }
        result["creature_header"]=header;
    }
    management::writeWorkOrder(result, s.workOrder);
    management::writeCitizen(result, s.citizen);
    management::writeAgreement(result, s.agreement);
    management::writeTrade(result, s.trade);
    management::writeReport(result, s.report);
    if(s.worldHover) {
        const auto& t=*s.worldHover;Dictionary description;
        description["tile"]=Vector3i(t.x,t.y,t.z);
        Array entries;
        for(const auto& e:t.entries) {
            Dictionary row;row["text"]=String::utf8(e.text.c_str());row["foreground"]=e.foreground;
            row["background"]=e.background;row["bright"]=e.bright;row["kind"]=e.kind;row["object_id"]=e.objectId;
            entries.push_back(row);
        }
        description["entries"]=entries;
        result["world_hover"]=description;
    }
    return result;
}

namespace {
bool validateHover(const Dictionary& data,String& error) {
    if(!data.has("origin") || data["origin"].get_type()!=Variant::VECTOR3I || data.size()!=2) {
        error="World hover requires only action and origin";return false;
    }
    const Vector3i tile=data["origin"];
    if(tile.x<0 || tile.y<0 || tile.z<0 || tile.x>32767 || tile.y>32767 || tile.z>32767) {
        error="Invalid world hover tile";return false;
    }
    return true;
}
bool readHover(const Dictionary& data,wm::ManagementRequest& request,String&) {
    const Vector3i tile=data["origin"];
    request.action=wm::ManagementAction::WorldHover;
    request.x=tile.x;request.y=tile.y;request.z=tile.z;return true;
}
bool validateCreatureWorkshop(const Dictionary& data,String& error) {
    if(data.size()!=4 || !data.has("unit_id") || !data.has("building_id") || !data.has("expected_revision") ||
       data["unit_id"].get_type()!=Variant::INT || data["building_id"].get_type()!=Variant::INT || data["expected_revision"].get_type()!=Variant::INT) {
        error="Invalid creature workshop fields";return false;
    }
    const int64_t unit=data["unit_id"],building=data["building_id"],revision=data["expected_revision"];
    if(unit<0 || unit>INT32_MAX || building<0 || building>INT32_MAX || revision<=0) {
        error="Invalid creature workshop identity or revision";return false;
    }
    return true;
}
bool readCreatureWorkshop(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction::CreatureWorkshopRemove;
    request.creatureWorkshop={int32_t(int64_t(data["unit_id"])),int32_t(int64_t(data["building_id"])),uint64_t(int64_t(data["expected_revision"]))};return true;
}
bool validateCreatureLocation(const Dictionary& data,String& error) {
    if(data.size()!=4 || !data.has("unit_id") || !data.has("occupation_id") || !data.has("expected_revision") ||
       data["unit_id"].get_type()!=Variant::INT || data["occupation_id"].get_type()!=Variant::INT || data["expected_revision"].get_type()!=Variant::INT) {
        error="Invalid creature location fields";return false;
    }
    const int64_t unit=data["unit_id"],occupation=data["occupation_id"],revision=data["expected_revision"];
    if(unit<0 || unit>INT32_MAX || occupation<0 || occupation>INT32_MAX || revision<=0) {
        error="Invalid creature location identity or revision";return false;
    }
    return true;
}
bool readCreatureLocation(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction::CreatureLocationRemove;
    request.creatureLocation={int32_t(int64_t(data["unit_id"])),int32_t(int64_t(data["occupation_id"])),uint64_t(int64_t(data["expected_revision"]))};return true;
}
bool validateJobSettings(const Dictionary& data,String& error) {
    if(data.has("art")) {
        if(data.size()!=7 || data["art"].get_type()!=Variant::DICTIONARY){error="Invalid job draft fields";return false;}
        for(const char* key:{"job_id","building_id","unit_id","option","expected_revision"})
            if(!data.has(key) || data[key].get_type()!=Variant::INT){error="Invalid job draft authority";return false;}
        const int64_t job=data["job_id"],building=data["building_id"],unit=data["unit_id"],option=data["option"];
        if(job<0 || job>INT32_MAX || building<0 || building>INT32_MAX || unit < -1 || unit>INT32_MAX || option<0 || option>64 || int64_t(data["expected_revision"])<=0){error="Invalid job draft bounds";return false;}
        const Dictionary art=data["art"];
        for(const char* key:{"page","subject","expected_list_revision","cursor","hovered","preview_columns"})
            if(art.has(key) && art[key].get_type()!=Variant::INT){error="Invalid draft field type";return false;}
        if(!art.has("draft") || (art.has("query") && art["query"].get_type()!=Variant::STRING)){error="Invalid draft payload";return false;}
        wm::WorkOrderArtRequest value;
        if(!management::readArtRequest(art,value)){error="Invalid draft payload bounds";return false;}
        return true;
    }
    if(int64_t(data["action"])==int64_t(wm::ManagementAction::JobSettingsApply)) {
        const bool art=data.has("art_page");
        if(data.size()!=(art?10:8)){error="Invalid job edit fields";return false;}
        for(const char* key:{"job_id","building_id","unit_id","option","expected_revision","expected_choices_revision","choice"})
            if(!data.has(key) || data[key].get_type()!=Variant::INT){error="Invalid job edit fields";return false;}
        const int64_t job=data["job_id"],building=data["building_id"],unit=data["unit_id"],option=data["option"],choice=data["choice"];
        if(job<0 || job>INT32_MAX || building<0 || building>INT32_MAX || unit < -1 || unit>INT32_MAX || option<0 || option>64 || choice < -1 || choice>INT32_MAX ||
           int64_t(data["expected_revision"])<=0 || int64_t(data["expected_choices_revision"])<0){error="Invalid job edit bounds";return false;}
        const int64_t receipt=data["expected_choices_revision"];
        if(!art){if(choice<0 || choice>=16384 || receipt<=0){error="Invalid ordinary job choice";return false;}}
        else {
            if(data["art_page"].get_type()!=Variant::INT || !data.has("query") || data["query"].get_type()!=Variant::STRING){error="Invalid artwork edit fields";return false;}
            const int64_t page=data["art_page"];const String query=data["query"];const auto bytes=query.utf8();
            if(bytes.length()>128 || std::string(bytes.get_data(),bytes.length()).find('\0')!=std::string::npos ||
               (page==-1 || page==0 ? (choice!=-1 || bytes.length()!=0 || (page==-1 ? receipt<=0 : receipt!=0)) :
                ((page!=1 && page!=2 && page!=3 && page!=5) || receipt<=0 || choice<0 || (page==5 && choice>=262144)))){error="Invalid artwork edit bounds";return false;}
        }
        return true;
    }
    const bool art=data.has("art_page");
    if(data.size()!=(art?11:7)){error="Invalid job settings fields";return false;}
    for(const char* key:{"job_id","building_id","unit_id","option","cursor"})
        if(!data.has(key) || data[key].get_type()!=Variant::INT){error="Invalid job settings fields";return false;}
    const int64_t job=data["job_id"],building=data["building_id"],unit=data["unit_id"],option=data["option"],cursor=data["cursor"];
    if(job<0 || job>INT32_MAX || building<0 || building>INT32_MAX || unit < -1 || unit>INT32_MAX || option < -1 || option>64 || cursor<0 || cursor>(art?262144:16384) ||
       !data.has("query") || data["query"].get_type()!=Variant::STRING){error="Invalid job settings identity or bounds";return false;}
    const String query=data["query"];const auto bytes=query.utf8();
    if(bytes.length()>128 || std::string(bytes.get_data(),bytes.length()).find('\0')!=std::string::npos){error="Invalid job settings query";return false;}
    if(art) {
        for(const char* key:{"art_page","expected_list_revision","hovered","preview_columns"})if(!data.has(key) || data[key].get_type()!=Variant::INT){error="Invalid job artwork fields";return false;}
        const int64_t page=data["art_page"],revision=data["expected_list_revision"],hovered=data["hovered"],columns=data["preview_columns"];
        if(option<0 || (page!=-1 && page!=1 && page!=2 && page!=3 && page!=5) || revision<0 || hovered < -1 || hovered>INT32_MAX || columns<0 || columns>1024 ||
           (hovered>=0 ? (!revision || !columns) : columns!=0) || (page==-1 && (cursor || bytes.length() || revision || hovered!=-1))){error="Invalid job artwork bounds";return false;}
    }
    return true;
}
bool readJobSettings(const Dictionary& data,wm::ManagementRequest& request,String&) {
    if(data.has("art")) {
        wm::WorkOrderArtRequest art;if(!management::readArtRequest(Dictionary(data["art"]),art))return false;
        request.action=wm::ManagementAction(int64_t(data["action"]));
        if(request.action==wm::ManagementAction::JobSettingsApply) {
            auto& q=request.jobSettingsEdit;q.jobId=int32_t(int64_t(data["job_id"]));q.buildingId=int32_t(int64_t(data["building_id"]));q.unitId=int32_t(int64_t(data["unit_id"]));q.option=int16_t(int64_t(data["option"]));q.expectedRevision=uint64_t(int64_t(data["expected_revision"]));q.art=std::move(art);
        } else {
            auto& q=request.jobSettings;q.jobId=int32_t(int64_t(data["job_id"]));q.buildingId=int32_t(int64_t(data["building_id"]));q.unitId=int32_t(int64_t(data["unit_id"]));q.option=int16_t(int64_t(data["option"]));q.expectedRevision=uint64_t(int64_t(data["expected_revision"]));q.art=std::move(art);
        }
        return true;
    }
    if(int64_t(data["action"])==int64_t(wm::ManagementAction::JobSettingsApply)) {
        request.action=wm::ManagementAction::JobSettingsApply;
        request.jobSettingsEdit={int32_t(int64_t(data["job_id"])),int32_t(int64_t(data["building_id"])),int32_t(int64_t(data["unit_id"])),int16_t(int64_t(data["option"])),uint64_t(int64_t(data["expected_revision"])),uint64_t(int64_t(data["expected_choices_revision"])),int32_t(int64_t(data["choice"]))};
        if(data.has("art_page")){request.jobSettingsEdit.artPage=int16_t(int64_t(data["art_page"]));const String query=data["query"];request.jobSettingsEdit.query=query.utf8().get_data();}
        return true;
    }
    request.action=wm::ManagementAction::JobSettingsRead;
    request.jobSettings.jobId=int32_t(int64_t(data["job_id"]));request.jobSettings.buildingId=int32_t(int64_t(data["building_id"]));request.jobSettings.unitId=int32_t(int64_t(data["unit_id"]));
    request.jobSettings.option=int16_t(int64_t(data["option"]));request.jobSettings.cursor=uint32_t(int64_t(data["cursor"]));
    if(data.has("art_page")){auto& q=request.jobSettings;q.artPage=int16_t(int64_t(data["art_page"]));q.expectedListRevision=uint64_t(int64_t(data["expected_list_revision"]));q.hovered=int32_t(int64_t(data["hovered"]));q.previewColumns=uint16_t(int64_t(data["preview_columns"]));}
    const String query=data["query"];request.jobSettings.query=query.utf8().get_data();return true;
}
bool validateResidentsActivity(const Dictionary& data,String& error) {
    if(data.size()!=5){error="Invalid residents activity fields";return false;}
    for(const char* key:{"unit_id","activity_id","event_id","columns"}) {
        if(!data.has(key) || data[key].get_type()!=Variant::INT){error="Invalid residents activity fields";return false;}
        const int64_t n=data[key];if(n<0 || n>INT32_MAX){error="Invalid residents activity identity";return false;}
    }
    const int64_t columns=data["columns"];if(columns<1 || columns>1024){error="Invalid residents activity width";return false;}
    return true;
}
bool readResidentsActivity(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction::ResidentsActivityRead;
    request.residentsActivity={int32_t(int64_t(data["unit_id"])),int32_t(int64_t(data["activity_id"])),int32_t(int64_t(data["event_id"])),uint16_t(int64_t(data["columns"]))};return true;
}
bool validateResidentsSpecialization(const Dictionary& data,String& error) {
    if(data.size()!=4 || !data.has("unit_id") || !data.has("expected_revision") || !data.has("only_assigned") ||
       data["unit_id"].get_type()!=Variant::INT || data["expected_revision"].get_type()!=Variant::INT || data["only_assigned"].get_type()!=Variant::BOOL) {
        error="Invalid residents specialization fields";return false;
    }
    const int64_t id=data["unit_id"],revision=data["expected_revision"];
    if(id<0 || id>INT32_MAX || revision<=0) {error="Invalid residents specialization identity or revision";return false;}
    return true;
}
bool readResidentsSpecialization(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction::ResidentsSpecialize;
    request.residentsSpecialization={int32_t(int64_t(data["unit_id"])),uint64_t(int64_t(data["expected_revision"])),bool(data["only_assigned"])};return true;
}
bool validateStoneUse(const Dictionary& data,String& error) {
    error="Invalid stone use request";
    if(int64_t(data["action"])==int64_t(wm::ManagementAction::StoneUseRead)){
        if(data.size()!=1)return false;
    }else{
        const auto integer=[](const Dictionary& d,const char* key,int64_t lo,int64_t hi){return d.has(key) && d[key].get_type()==Variant::INT && int64_t(d[key])>=lo && int64_t(d[key])<=hi;};
        if(data.size()!=4 || !integer(data,"category",0,1) || !integer(data,"index",0,65535) || !data.has("expected") || data["expected"].get_type()!=Variant::ARRAY)return false;
        const Array flags=data["expected"];if(flags.size()>65536 || int64_t(data["index"])>=flags.size())return false;
        for(int64_t i=0;i<flags.size();++i)if(flags[i].get_type()!=Variant::INT || int64_t(flags[i])<0 || int64_t(flags[i])>1)return false;
    }
    error=String();return true;
}
bool readStoneUse(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction(int64_t(data["action"]));
    if(request.action==wm::ManagementAction::StoneUseApply){auto& q=request.stoneUse;
        q.category=int32_t(int64_t(data["category"]));q.index=int32_t(int64_t(data["index"]));q.expected.emplace();
        const Array flags=data["expected"];for(int64_t i=0;i<flags.size();++i)q.expected->push_back(uint8_t(int64_t(flags[i])));
    }
    return true;
}
bool validateKitchenMenu(const Dictionary& data,String& error) {
    const auto integer=[](const Dictionary& d,const char* k,int64_t lo,int64_t hi){return d.has(k) && d[k].get_type()==Variant::INT && int64_t(d[k])>=lo && int64_t(d[k])<=hi;};
    const auto key=[&](const Variant& v){if(v.get_type()!=Variant::DICTIONARY)return false;const Dictionary d=v;
        return d.size()==4 && integer(d,"item_type",0,INT16_MAX) && integer(d,"item_subtype",-1,INT16_MAX) && integer(d,"mat_type",-1,INT16_MAX) && integer(d,"mat_index",-1,INT32_MAX);};
    const bool apply=int64_t(data["action"])==int64_t(wm::ManagementAction::KitchenApply);
    error="Invalid kitchen request";
    if(!apply){
        if(data.size()!=5 || !integer(data,"type_filter",-1,3) || !integer(data,"capability_filter",0,3) || !data.has("query") || data["query"].get_type()!=Variant::STRING ||
           String(data["query"]).utf8().length()>4096 || !data.has("sorts") || data["sorts"].get_type()!=Variant::ARRAY)return false;
        const Array sorts=data["sorts"];if(sorts.size()<1 || sorts.size()>65536)return false;
        unsigned seen=0,reversed=0;for(int64_t i=0;i<sorts.size();++i){if(sorts[i].get_type()!=Variant::DICTIONARY)return false;const Dictionary d=sorts[i];
            if(d.size()!=2 || !integer(d,"column",0,4) || !d.has("reverse") || d["reverse"].get_type()!=Variant::BOOL)return false;
            const unsigned bit=1u<<int64_t(d["column"]);if((seen&bit) && bool(reversed&bit)!=bool(d["reverse"]))return false;seen|=bit;if(bool(d["reverse"]))reversed|=bit;}
    }else{
        if(data.size()!=4 || !integer(data,"permission",1,2) || !data.has("target") || data["target"].get_type()!=Variant::DICTIONARY || !data.has("expected") || data["expected"].get_type()!=Variant::ARRAY)return false;
        const Dictionary d=data["target"];if(d.size()!=3 || !d.has("key") || !key(d["key"]) || !integer(d,"count",0,INT32_MAX) || !integer(d,"capabilities",1,3) || !(int64_t(d["capabilities"])&int64_t(data["permission"])))return false;
        const Array expected=data["expected"];if(expected.size()>65536)return false;
        for(int64_t i=0;i<expected.size();++i){if(expected[i].get_type()!=Variant::DICTIONARY)return false;const Dictionary row=expected[i];if(row.size()!=2 || !row.has("key") || !key(row["key"]) || !integer(row,"flags",0,3))return false;}
    }
    error=String();return true;
}
bool readKitchenMenu(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction(int64_t(data["action"]));auto& q=request.kitchenMenu;
    if(request.action==wm::ManagementAction::KitchenRead){q.query.emplace();auto& v=*q.query;v.typeFilter=int8_t(int64_t(data["type_filter"]));v.capabilityFilter=uint8_t(int64_t(data["capability_filter"]));v.query=String(data["query"]).utf8().get_data();v.sorts.clear();
        const Array sorts=data["sorts"];for(int64_t i=0;i<sorts.size();++i){const Dictionary d=sorts[i];v.sorts.push_back({wm::KitchenSortColumn(int64_t(d["column"])),bool(d["reverse"])});}
    }else{
        const auto key=[](const Dictionary& d){return wm::KitchenFoodKey{int16_t(int64_t(d["item_type"])),int16_t(int64_t(d["item_subtype"])),int16_t(int64_t(d["mat_type"])),int32_t(int64_t(d["mat_index"]))};};
        const Dictionary d=data["target"];q.target=wm::KitchenFoodReceipt{key(d["key"]),int32_t(int64_t(d["count"])),uint8_t(int64_t(d["capabilities"]))};q.permission=uint8_t(int64_t(data["permission"]));q.expected.emplace();
        const Array rows=data["expected"];for(int64_t i=0;i<rows.size();++i){const Dictionary row=rows[i];q.expected->push_back({key(row["key"]),uint8_t(int64_t(row["flags"]))});}
    }
    return true;
}
bool validateChores(const Dictionary& data,String& error) {
    const bool apply=int64_t(data["action"])==int64_t(wm::ManagementAction::ChoresApply);
    if(data.size()!=(apply?5:1)){error="Invalid chores fields";return false;}
    if(!apply)return true;
    if(!data.has("operation") || data["operation"].get_type()!=Variant::INT || int64_t(data["operation"])<1 || int64_t(data["operation"])>3 ||
       !data.has("id") || data["id"].get_type()!=Variant::INT || int64_t(data["id"])<-1 || int64_t(data["id"])>INT32_MAX ||
       !data.has("value") || data["value"].get_type()!=Variant::BOOL || !data.has("expected") || data["expected"].get_type()!=Variant::DICTIONARY){error="Invalid chores edit";return false;}
    const Dictionary snap=data["expected"];
    if(snap.size()!=4 || !snap.has("enabled") || snap["enabled"].get_type()!=Variant::BOOL ||
       !snap.has("children") || snap["children"].get_type()!=Variant::PACKED_INT32_ARRAY || !snap.has("exempted") || snap["exempted"].get_type()!=Variant::PACKED_INT32_ARRAY ||
       !snap.has("labors") || snap["labors"].get_type()!=Variant::ARRAY){error="Invalid chores receipt";return false;}
    const PackedInt32Array children=snap["children"],exempted=snap["exempted"];const Array labors=snap["labors"];
    if(children.size()>65536 || exempted.size()>65536 || labors.size()!=14){error="Invalid chores receipt size";return false;}
    std::unordered_set<int32_t> ids;for(int64_t i=0;i<children.size();++i)if(children[i]<0 || !ids.insert(children[i]).second){error="Invalid chores child";return false;}
    int32_t prior=-1;for(int64_t i=0;i<exempted.size();++i){if(exempted[i]<=prior){error="Invalid chores exemption";return false;}prior=exempted[i];}
    constexpr int32_t catalog[]={23,37,1,2,6,3,4,5,7,8,74,77,9,75};
    for(int64_t i=0;i<14;++i){if(labors[i].get_type()!=Variant::DICTIONARY){error="Invalid chore labor";return false;}
        const Dictionary row=labors[i];if(row.size()!=2 || !row.has("id") || row["id"].get_type()!=Variant::INT || int64_t(row["id"])!=catalog[i] || !row.has("enabled") || row["enabled"].get_type()!=Variant::BOOL){error="Invalid chore labor";return false;}}
    const int64_t op=data["operation"],id=data["id"];
    if((op==1 && id!=-1) || (op==2 && std::find(std::begin(catalog),std::end(catalog),id)==std::end(catalog)) || (op==3 && !ids.count(int32_t(id)))){error="Invalid chores target";return false;}
    return true;
}
bool readChores(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction(int64_t(data["action"]));if(request.action==wm::ManagementAction::ChoresRead)return true;
    auto& q=request.chores;q.operation=wm::ChoresOperation(int64_t(data["operation"]));q.id=int32_t(int64_t(data["id"]));q.value=bool(data["value"]);
    const Dictionary snap=data["expected"];q.expected.emplace();q.expected->enabled=bool(snap["enabled"]);
    const PackedInt32Array children=snap["children"],exempted=snap["exempted"];const Array labors=snap["labors"];
    for(int64_t i=0;i<children.size();++i)q.expected->children.push_back(children[i]);
    for(int64_t i=0;i<exempted.size();++i)q.expected->exempted.push_back(exempted[i]);
    for(int64_t i=0;i<labors.size();++i){const Dictionary row=labors[i];q.expected->labors.push_back({int32_t(int64_t(row["id"])),bool(row["enabled"])});}
    return true;
}
bool validateHunterAmmunition(const Dictionary& data,String& error) {
    const auto action=wm::ManagementAction(int64_t(data["action"]));
    const bool apply=action==wm::ManagementAction::HunterAmmunitionApply,choices=action==wm::ManagementAction::HunterAmmunitionCandidates;
    const auto integer=[](const Dictionary& row,const char* key,int64_t low,int64_t high){return row.has(key) && row[key].get_type()==Variant::INT && int64_t(row[key])>=low && int64_t(row[key])<=high;};
    if(data.size()!=(apply?11:choices?3:1)){error="Invalid ammunition request fields";return false;}
    if(choices && (!integer(data,"item_type",39,39) || !integer(data,"item_subtype",0,INT16_MAX))){error="Invalid ammunition candidate type";return false;}
    if(!apply)return true;
    if(!integer(data,"operation",1,5) || !integer(data,"index",-1,INT32_MAX) || !integer(data,"item_id",-1,INT32_MAX) ||
       !integer(data,"amount",-1,5000) || !integer(data,"item_type",-1,39) || !integer(data,"item_subtype",-1,INT16_MAX) ||
       !integer(data,"material_class",-1,INT16_MAX) || !integer(data,"mattype",-1,INT16_MAX) || !integer(data,"matindex",-1,INT32_MAX) ||
       !data.has("expected") || data["expected"].get_type()!=Variant::ARRAY){error="Invalid ammunition edit";return false;}
    const Array specs=data["expected"];
    for(int64_t i=0;i<specs.size();++i){
        if(specs[i].get_type()!=Variant::DICTIONARY){error="Invalid ammunition snapshot";return false;}
        const Dictionary row=specs[i];
        if(row.size()!=8 || !integer(row,"item_type",39,39) || !integer(row,"item_subtype",0,INT16_MAX) ||
           !integer(row,"material_class",-1,INT16_MAX) || !integer(row,"mattype",-1,INT16_MAX) || !integer(row,"matindex",-1,INT32_MAX) ||
           !integer(row,"amount",0,INT32_MAX) || !integer(row,"flags",0,3) || !row.has("assigned") || row["assigned"].get_type()!=Variant::PACKED_INT32_ARRAY){error="Invalid ammunition snapshot fields";return false;}
        const PackedInt32Array assigned=row["assigned"];int32_t prior=-1;
        for(int64_t j=0;j<assigned.size();++j){if(assigned[j]<=prior){error="Invalid ammunition assignments";return false;}prior=assigned[j];}
    }
    const int64_t op=data["operation"],index=data["index"],item=data["item_id"],amount=data["amount"],type=data["item_type"],subtype=data["item_subtype"],category=data["material_class"],mat=data["mattype"],matindex=data["matindex"];
    if((op==3?index!=-1:(index<0 || index>=specs.size())) || (op==1?amount<0:amount!=-1) || (op==5?item<0:item!=-1) ||
       (op==3?(type!=39 || subtype<0):(type!=-1 || subtype!=-1)) || (op!=2 && (category!=-1 || mat!=-1 || matindex!=-1))){error="Invalid ammunition operation fields";return false;}
    return true;
}
bool readHunterAmmunition(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction(int64_t(data["action"]));auto& q=request.hunterAmmunition;
    if(request.action==wm::ManagementAction::HunterAmmunitionRead)return true;
    q.itemType=int16_t(int64_t(data["item_type"]));q.itemSubtype=int16_t(int64_t(data["item_subtype"]));
    if(request.action==wm::ManagementAction::HunterAmmunitionCandidates)return true;
    q.operation=wm::HunterAmmunitionOperation(int64_t(data["operation"]));q.index=int32_t(int64_t(data["index"]));q.itemId=int32_t(int64_t(data["item_id"]));q.amount=int32_t(int64_t(data["amount"]));
    q.materialClass=int16_t(int64_t(data["material_class"]));q.matType=int16_t(int64_t(data["mattype"]));q.matIndex=int32_t(int64_t(data["matindex"]));
    const Array specs=data["expected"];
    for(int64_t i=0;i<specs.size();++i){const Dictionary row=specs[i];wm::HunterAmmunitionSpec v;
        v.itemType=int16_t(int64_t(row["item_type"]));v.itemSubtype=int16_t(int64_t(row["item_subtype"]));v.materialClass=int16_t(int64_t(row["material_class"]));
        v.matType=int16_t(int64_t(row["mattype"]));v.matIndex=int32_t(int64_t(row["matindex"]));v.amount=int32_t(int64_t(row["amount"]));v.flags=uint32_t(int64_t(row["flags"]));
        const PackedInt32Array assigned=row["assigned"];for(int64_t j=0;j<assigned.size();++j)v.assigned.push_back(assigned[j]);q.expected.push_back(std::move(v));}
    return true;
}
bool validateStandingOrders(const Dictionary& data,String& error) {
    const bool set=int64_t(data["action"])==int64_t(wm::ManagementAction::StandingOrdersSet);
    if(data.size()!=(set?5:2) || !data.has("category") || data["category"].get_type()!=Variant::INT || (int64_t(data["category"])<0 || int64_t(data["category"])>6 || int64_t(data["category"])==5)){error="Invalid standing orders category";return false;}
    if(set){
        for(const char* key:{"setting_id","expected_value","value"})if(!data.has(key) || data[key].get_type()!=Variant::INT){error="Invalid standing orders value";return false;}
        const int64_t id=data["setting_id"],expected=data["expected_value"],value=data["value"];
        const int64_t category=data["category"];
        if(id<0 || id>=(category==0?11:category==1 || category==4?6:category==6?7:10) || expected<0 || value<0 || expected>(category==3 || category==4 || (category==0 && id==0)?2:category==6 && id==0?3:1) || value>(category==3 || category==4 || (category==0 && id==0)?2:category==6 && id==0?3:1)){error="Invalid standing orders edit";return false;}
    }
    return true;
}
bool readStandingOrders(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction(int64_t(data["action"]));request.standingOrders.category=uint8_t(int64_t(data["category"]));
    if(request.action==wm::ManagementAction::StandingOrdersSet)request.standingOrders={uint8_t(int64_t(data["category"])),int32_t(int64_t(data["setting_id"])),int8_t(int64_t(data["expected_value"])),int8_t(int64_t(data["value"]))};
    return true;
}
bool validateWorkDetailSettings(const Dictionary& data,String& error) {
    const bool toggle=int64_t(data["action"])==int64_t(wm::ManagementAction::WorkDetailSettingsToggle);
    if(data.size()!=(toggle?4:3) || !data.has("detail_index") || !data.has("expected_revision") ||
       data["detail_index"].get_type()!=Variant::INT || data["expected_revision"].get_type()!=Variant::INT ||
       int64_t(data["detail_index"])<0 || int64_t(data["detail_index"])>=128 || int64_t(data["expected_revision"])<=0) {error="Invalid work-detail settings authority";return false;}
    if(toggle){
        if(!data.has("setting_id") || data["setting_id"].get_type()!=Variant::INT){error="Invalid setting identity";return false;}
        const int64_t id=data["setting_id"];
        if(!((id>=-13 && id<=-2) || (id>=1 && id<=93))){error="Invalid setting identity";return false;}
    }
    return true;
}
bool readWorkDetailSettings(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction(int64_t(data["action"]));
    request.workDetailSettings={int32_t(int64_t(data["detail_index"])),uint64_t(int64_t(data["expected_revision"])),data.has("setting_id")?int32_t(int64_t(data["setting_id"])):-1};return true;
}
bool validateWorkDetailWorkers(const Dictionary& data,String& error) {
    if(data.size()!=6 || !data.has("detail_index") || !data.has("expected_revision") || !data.has("sort") || !data.has("descending") || !data.has("query_bytes") ||
       data["detail_index"].get_type()!=Variant::INT || data["expected_revision"].get_type()!=Variant::INT || data["sort"].get_type()!=Variant::INT ||
       data["descending"].get_type()!=Variant::BOOL || data["query_bytes"].get_type()!=Variant::PACKED_BYTE_ARRAY) {error="Invalid work-detail worker fields";return false;}
    const int64_t index=data["detail_index"],revision=data["expected_revision"],sort=data["sort"];const PackedByteArray bytes=data["query_bytes"];
    if(index<0 || index>=128 || revision<=0 || sort<0 || sort>3 || bytes.size()>128 || bytes.has(0)) {error="Invalid work-detail worker query";return false;}
    return true;
}
bool readWorkDetailWorkers(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction::WorkDetailWorkersQuery;
    auto& query=request.workDetailWorkers;
    query.detailIndex=int32_t(int64_t(data["detail_index"]));query.expectedRevision=uint64_t(int64_t(data["expected_revision"]));
    query.sort=wm::WorkDetailWorkerSort(int64_t(data["sort"]));query.descending=bool(data["descending"]);
    const PackedByteArray bytes=data["query_bytes"];for(int64_t i=0;i<bytes.size();++i)query.queryBytes.push_back(bytes[i]);
    return true;
}
bool validateResidents(const Dictionary& data,String& error) {
    if(data.size()!=4 || !data.has("sort") || !data.has("descending") || !data.has("query_bytes") ||
       data["sort"].get_type()!=Variant::INT || data["descending"].get_type()!=Variant::BOOL ||
       data["query_bytes"].get_type()!=Variant::PACKED_BYTE_ARRAY) {error="Invalid residents query fields";return false;}
    const int64_t sort=data["sort"];const PackedByteArray bytes=data["query_bytes"];
    if(sort<0 || sort>4 || bytes.size()>128 || bytes.has(0)) {error="Invalid residents query";return false;}
    return true;
}
bool validateResidentsRows(const Dictionary& data,String& error) {
    const bool detail=int64_t(data["action"])==int64_t(wm::ManagementAction::WorkDetailRowsRead);
    if(data.size()!=(detail?6:4) || !data.has("unit_ids") || !data.has("columns") || !data.has("show_gender") ||
       data["unit_ids"].get_type()!=Variant::PACKED_INT32_ARRAY || data["columns"].get_type()!=Variant::INT ||
       data["show_gender"].get_type()!=Variant::BOOL) {error="Invalid residents row fields";return false;}
    if(detail && (!data.has("detail_index") || !data.has("expected_revision") || data["detail_index"].get_type()!=Variant::INT ||
        data["expected_revision"].get_type()!=Variant::INT || int64_t(data["detail_index"])<0 || int64_t(data["detail_index"])>=128 || int64_t(data["expected_revision"])<=0)) {error="Invalid work detail row authority";return false;}
    const PackedInt32Array ids=data["unit_ids"];const int64_t columns=data["columns"];
    if(ids.is_empty() || ids.size()>64 || columns<3 || columns>30) {error="Invalid residents row bounds";return false;}
    for(int64_t i=0;i<ids.size();++i) {
        if(ids[i]<0) {error="Invalid resident identity";return false;}
        for(int64_t j=0;j<i;++j)if(ids[i]==ids[j]) {error="Duplicate resident identity";return false;}
    }
    return true;
}
bool readResidentsRows(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction(int64_t(data["action"]));
    if(request.action==wm::ManagementAction::WorkDetailRowsRead){request.residentsRows.detailIndex=int32_t(int64_t(data["detail_index"]));request.residentsRows.expectedRevision=uint64_t(int64_t(data["expected_revision"]));}
    request.residentsRows.columns=uint16_t(int64_t(data["columns"]));request.residentsRows.showGender=bool(data["show_gender"]);
    const PackedInt32Array ids=data["unit_ids"];
    for(int64_t i=0;i<ids.size();++i)request.residentsRows.unitIds.push_back(ids[i]);
    return true;
}
bool readResidents(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction::ResidentsQuery;
    request.residents.sort=wm::ResidentsSort(int64_t(data["sort"]));request.residents.descending=bool(data["descending"]);
    const PackedByteArray bytes=data["query_bytes"];
    for(int64_t i=0;i<bytes.size();++i)request.residents.queryBytes.push_back(bytes[i]);
    return true;
}
bool validateCreatureAnimal(const Dictionary& data,String& error) {
    if(data.size()!=5 || !data.has("assigned") || data["assigned"].get_type()!=Variant::BOOL || !data.has("unit_id") || !data.has("animal_id") || !data.has("expected_revision") ||
       data["unit_id"].get_type()!=Variant::INT || data["animal_id"].get_type()!=Variant::INT || data["expected_revision"].get_type()!=Variant::INT) {
        error="Invalid creature animal fields";return false;
    }
    const int64_t unit=data["unit_id"],occupation=data["animal_id"],revision=data["expected_revision"];
    if(unit<0 || unit>INT32_MAX || occupation<0 || occupation>INT32_MAX || revision<=0) {
        error="Invalid creature animal identity or revision";return false;
    }
    return true;
}
bool readCreatureAnimal(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction::CreatureAnimalEdit;
    request.creatureAnimal={int32_t(int64_t(data["unit_id"])),int32_t(int64_t(data["animal_id"])),uint64_t(int64_t(data["expected_revision"])),bool(data["assigned"])};return true;
}
bool validateCreatureKnowledge(const Dictionary& data,String& error) {
    if(data.size()!=4 || !data.has("unit_id") || !data.has("kind") || !data.has("id") ||
       data["unit_id"].get_type()!=Variant::INT || data["kind"].get_type()!=Variant::INT || data["id"].get_type()!=Variant::INT) {
        error="Invalid creature knowledge fields";return false;
    }
    const int64_t unit=data["unit_id"],kind=data["kind"],id=data["id"];
    if(unit<0 || unit>INT32_MAX || kind<14 || kind>17 || id<0 || id>INT32_MAX) {
        error="Invalid creature knowledge identity";return false;
    }
    return true;
}
bool readCreatureKnowledge(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction::CreatureKnowledgeRead;
    request.creatureKnowledge={int32_t(int64_t(data["unit_id"])),int32_t(int64_t(data["kind"])),int32_t(int64_t(data["id"]))};return true;
}
bool validateCreatureFollow(const Dictionary& data,String& error) {
    if(data.size()!=2 || !data.has("unit_id") || data["unit_id"].get_type()!=Variant::INT) {
        error="Creature follow requires only action and unit_id";return false;
    }
    const int64_t id=data["unit_id"];
    if(id<0 || id>INT32_MAX){error="Invalid creature follow identity";return false;}
    return true;
}
bool readCreatureFollow(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction::CreatureLocate;request.creatureUnitId=int64_t(data["unit_id"]);return true;
}
bool readCreatureSheetLocation(const Dictionary& data,wm::ManagementRequest& request,String&) {
    request.action=wm::ManagementAction::CreatureSheetLocate;request.creatureUnitId=int64_t(data["unit_id"]);return true;
}
bool validateCreatureHeader(const Dictionary& data,String& error) {
    const bool edit=int64_t(data["action"])==int64_t(wm::ManagementAction::CreatureHeaderEdit);
    if(data.size()!=(edit?5:2) || !data.has("unit_id") || data["unit_id"].get_type()!=Variant::INT ||
       (edit && (!data.has("profession") || data["profession"].get_type()!=Variant::BOOL ||
        !data.has("expected_revision") || data["expected_revision"].get_type()!=Variant::INT ||
        !data.has("name") || data["name"].get_type()!=Variant::STRING))) {
        error="Invalid creature header fields";return false;
    }
    return true;
}
bool readCreatureHeader(const Dictionary& data,wm::ManagementRequest& request,String& error) {
    const int64_t id=data["unit_id"],revision=data.get("expected_revision",0);
    const String name=data.get("name",String());
    const auto utf8=name.utf8();
    if(id<0 || id>INT32_MAX || revision<0 || utf8.length()>90 ||
       (int64_t(data["action"])==int64_t(wm::ManagementAction::CreatureHeaderEdit) && !revision)) {
        error="Invalid creature header values";return false;
    }
    request.action=wm::ManagementAction(int64_t(data["action"]));
    request.creatureHeader={int32_t(id),bool(data.get("profession",false)),uint64_t(revision),std::string(utf8.get_data(),utf8.length())};
    return true;
}
bool validateCreatureExpel(const Dictionary& data,String& error) {
    const bool apply=int64_t(data["action"])==int64_t(wm::ManagementAction::CreatureExpelApply);
    if(data.size()!=(apply?4:2) || !data.has("unit_id") || data["unit_id"].get_type()!=Variant::INT ||
       (apply && (!data.has("destination_id") || data["destination_id"].get_type()!=Variant::INT ||
                  !data.has("expected_unit_ids") || data["expected_unit_ids"].get_type()!=Variant::ARRAY))) {
        error="Invalid creature expel fields";return false;
    }
    return true;
}
bool readCreatureExpel(const Dictionary& data,wm::ManagementRequest& request,String& error) {
    const int64_t id=data["unit_id"],destination=data.get("destination_id",-1);
    if(id<0 || id>INT32_MAX || destination < -1 || destination>INT32_MAX) {error="Invalid creature expel identity";return false;}
    request.action=wm::ManagementAction(int64_t(data["action"]));
    auto& e=request.creatureExpel;e.unitId=int32_t(id);e.destinationId=int32_t(destination);
    if(request.action==wm::ManagementAction::CreatureExpelApply) {
        const Array ids=data["expected_unit_ids"];int64_t previous=-1;bool selected=false;
        if(ids.is_empty() || ids.size()>4096) {error="Invalid creature expel group size";return false;}
        for(int i=0;i<ids.size();++i) {
            if(ids[i].get_type()!=Variant::INT) {error="Invalid creature expel group type";return false;}
            const int64_t member=ids[i];
            if(member<=previous || member>INT32_MAX) {error="Invalid creature expel group order";return false;}
            previous=member;selected|=member==id;e.expectedUnitIds.push_back(int32_t(member));
        }
        if(!selected) {error="Creature expel selected unit missing";return false;}
    }
    return true;
}
struct ManagementCodec {
    const char* domain;
    bool (*validate)(const Dictionary&, String&);
    bool (*read)(const Dictionary&, wm::ManagementRequest&, String&);
};
const ManagementCodec managementCodecs[] = {
    {"construction", management::validateConstructionShape, management::readConstruction},
    {"areas", management::validateAreaShape, management::readArea},
    {"production", management::validateProductionShape, management::readProduction},
    {"work_orders", management::validateWorkOrderShape, management::readWorkOrder},
    {"citizens", management::validateCitizenShape, management::readCitizen},
    {"reports", management::validateReportShape, management::readReport},
    {"agreements", management::validateAgreementShape, management::readAgreement},
    {"trade", management::validateTradeShape, management::readTrade},
    {"hover", validateHover, readHover},
    {"creature_header",validateCreatureHeader,readCreatureHeader},
    {"creature_follow",validateCreatureFollow,readCreatureFollow},
    {"creature_sheet_location",validateCreatureFollow,readCreatureSheetLocation},
    {"creature_workshop",validateCreatureWorkshop,readCreatureWorkshop},
    {"creature_location",validateCreatureLocation,readCreatureLocation},
    {"creature_animal",validateCreatureAnimal,readCreatureAnimal},
    {"residents",validateResidents,readResidents},
    {"work_detail_workers",validateWorkDetailWorkers,readWorkDetailWorkers},
    {"residents_rows",validateResidentsRows,readResidentsRows},
    {"work_detail_rows",validateResidentsRows,readResidentsRows},
    {"work_detail_settings",validateWorkDetailSettings,readWorkDetailSettings},
    {"hunter_ammunition",validateHunterAmmunition,readHunterAmmunition},
    {"stone_use",validateStoneUse,readStoneUse},
    {"kitchen_menu",validateKitchenMenu,readKitchenMenu},
    {"chores",validateChores,readChores},
    {"standing_orders",validateStandingOrders,readStandingOrders},
    {"residents_specialization",validateResidentsSpecialization,readResidentsSpecialization},
    {"residents_activity",validateResidentsActivity,readResidentsActivity},
    {"job_settings",validateJobSettings,readJobSettings},
    {"creature_knowledge",validateCreatureKnowledge,readCreatureKnowledge},
    {"creature_expel",validateCreatureExpel,readCreatureExpel},
};
}

int64_t Df3dWorld::management_request(const String& domain, const Dictionary& data) {
    const ManagementCodec* codec = nullptr;
    for (const auto& entry : managementCodecs) if (domain == entry.domain) { codec = &entry; break; }
    if (!codec) { lastError_ = "Unknown management domain"; return 0; }
    if (!data.has("action")) { lastError_ = "Missing management field: action"; return 0; }
    if (data["action"].get_type() != Variant::INT) { lastError_ = "Wrong management field type: action"; return 0; }
    const int64_t raw = data["action"];
    if (raw < 0 || raw > static_cast<int64_t>(wm::ManagementAction::StoneUseApply)) {
        lastError_ = "Invalid management action"; return 0;
    }
    const auto action = static_cast<wm::ManagementAction>(raw);
    if (action != wm::ManagementAction::Catalog && domain != wm::managementDomain(action)) {
        lastError_ = "Management action does not match domain"; return 0;
    }
    // Defence in depth: retired actions currently fail the domain check above.
    if (!wm::isRuntimeAction(action)) { lastError_ = "Retired management action"; return 0; }
    if (action == wm::ManagementAction::Catalog) codec = &managementCodecs[0];
    if (!codec->validate(data, lastError_)) return 0;
    if (!managementClient_) { lastError_ = "Management bridge unavailable"; return 0; }
    wm::ManagementRequest request;
    if (!codec->read(data, request, lastError_)) return 0;
    const auto sequence = managementClient_->send(request);
    if (!sequence) lastError_ = String::utf8(managementClient_->lastError().c_str());
    else lastError_ = String();
    return int64_t(sequence);
}

int64_t Df3dWorld::construction_request(const Dictionary& data) { return management_request("construction", data); }
int64_t Df3dWorld::area_request(const Dictionary& data) { return management_request("areas", data); }
int64_t Df3dWorld::report_request(const Dictionary& data) { return management_request("reports", data); }
int64_t Df3dWorld::work_order_request(const Dictionary& data) { return management_request("work_orders", data); }
int64_t Df3dWorld::save_fortress(bool return_to_menu, const String& checkpoint_name) {
    if (!sessionClient_) { lastError_ = "DF session is unavailable"; return 0; }
    const auto seq = sessionClient_->sendSave(return_to_menu, checkpoint_name.utf8().get_data());
    if (!seq) lastError_ = String::utf8(sessionClient_->lastError().c_str());
    return int64_t(seq);
}

int64_t Df3dWorld::read_save_destinations(int64_t epoch) {
    if(!sessionClient_ || epoch<=0)return 0;
    const auto seq=sessionClient_->sendReadSaveDestinations(uint64_t(epoch));
    lastError_=seq?String():String::utf8(sessionClient_->lastError().c_str());return int64_t(seq);
}
int64_t Df3dWorld::quit_without_saving(int64_t epoch) {
    if(!sessionClient_ || epoch<=0)return 0;
    const auto seq=sessionClient_->sendQuitWithoutSaving(uint64_t(epoch));
    lastError_=seq?String():String::utf8(sessionClient_->lastError().c_str());return int64_t(seq);
}
int64_t Df3dWorld::save_return_explicit(int64_t epoch,int64_t receipt,int mode,const String& id,const PackedByteArray& name) {
    if(!sessionClient_ || epoch<=0 || receipt<=0 || mode<1 || mode>3)return 0;
    std::vector<uint8_t> bytes;
    if(!name.is_empty())bytes.assign(name.ptr(),name.ptr()+name.size());
    const auto seq=sessionClient_->sendSaveReturn(uint64_t(epoch),uint64_t(receipt),wm::SaveReturnMode(mode),id.utf8().get_data(),bytes);
    lastError_=seq?String():String::utf8(sessionClient_->lastError().c_str());return int64_t(seq);
}
int64_t Df3dWorld::save_fortress_bytes(const PackedByteArray& checkpoint_name) {
    if (!sessionClient_) { lastError_ = "DF session is unavailable"; return 0; }
    // Native text editing is byte-oriented and can leave incomplete UTF-8.
    // Preserve the bytes through validation instead of substituting characters.
    std::string name;
    if (!checkpoint_name.is_empty())
        name.assign(reinterpret_cast<const char*>(checkpoint_name.ptr()), checkpoint_name.size());
    const auto seq = sessionClient_->sendSave(false, name);
    if (!seq) lastError_ = String::utf8(sessionClient_->lastError().c_str());
    else lastError_ = String();
    return int64_t(seq);
}

}
