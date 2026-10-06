#include "df3d_world.h"
#include "management_codecs.h"
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
    management::writeWorkOrder(result, s.workOrder);
    management::writeCitizen(result, s.citizen);
    management::writeAgreement(result, s.agreement);
    management::writeTrade(result, s.trade);
    management::writeReport(result, s.report);
    return result;
}

namespace {
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
};
}

int64_t Df3dWorld::management_request(const String& domain, const Dictionary& data) {
    const ManagementCodec* codec = nullptr;
    for (const auto& entry : managementCodecs) if (domain == entry.domain) { codec = &entry; break; }
    if (!codec) { lastError_ = "Unknown management domain"; return 0; }
    if (!data.has("action")) { lastError_ = "Missing management field: action"; return 0; }
    if (data["action"].get_type() != Variant::INT) { lastError_ = "Wrong management field type: action"; return 0; }
    const int64_t raw = data["action"];
    if (raw < 0 || raw > static_cast<int64_t>(wm::ManagementAction::DismissAlert)) {
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
