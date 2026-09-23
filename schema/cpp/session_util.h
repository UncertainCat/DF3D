#pragma once
#include "mirror_generated.h"
#include "command_util.h"
#include "shm_layout.h"
#include <optional>
#include <set>
#include <string>
namespace df3d::mirror {
// Session-only metadata occupies the transport header's reserved space.
struct SessionOwner { volatile uint64_t pid; volatile uint64_t created; volatile uint64_t generation; };
inline SessionOwner* sessionOwner(df3d::shm::RegionHeader* r) {
  return reinterpret_cast<SessionOwner*>(r->reserved);
}
inline constexpr uint32_t kSessionVersion = 8;
inline constexpr const char* kSessionRegionName = "Local\\df3d_session_v8";
inline constexpr uint32_t kSessionCapacity = 1024 * 1024;
inline constexpr uint32_t kSessionCommandCapacity = 16384;
inline constexpr uint32_t kMaxNotificationGroups = 64;
inline constexpr uint32_t kMaxNotificationReferences = 256;
// Retired native panel endpoints remain in the wire vocabulary for explicit
// unsupported responses; validation does not authorize runtime execution.
inline bool sessionEpochMatches(uint64_t requested, uint64_t current) { return requestEpochMatches(requested,current); }
inline bool runtimeSessionAction(SessionAction action) {
  return action>=SessionAction::LoadFortress && action<=SessionAction::SaveReturn;
}
inline bool validSaveId(const std::string& id) {
  return !id.empty() && id.size() <= 2048 && id.find('\0') == std::string::npos;
}
inline bool validCheckpointName(const std::string& name) {
  if (name.empty() || name.size() > 80 || name.front() == ' ' || name.back() == ' ' ||
      name == "." || name == "..") return false;
  for (unsigned char c : name) if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') || c == ' ' || c == '-' || c == '_')) return false;
  std::string upper = name;
  for (char& c : upper) if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
  if (upper == "CON" || upper == "PRN" || upper == "AUX" || upper == "NUL" ||
      (upper.size() == 4 && (upper.substr(0, 3) == "COM" || upper.substr(0, 3) == "LPT") &&
       upper[3] >= '1' && upper[3] <= '9')) return false;
  return true;
}
inline std::optional<std::string> validateSessionCommand(const SessionCommand& c) {
  if (c.schema_version() != kSessionVersion) return "session schema version mismatch";
  if (!c.client_id()) return "session client identity required";
  if (!c.seq()) return "load request seq must be nonzero";
  if (c.action() < SessionAction::LoadFortress || c.action() > SessionAction::ClosePetition) return "invalid session action";
  if(c.action()>=SessionAction::ReviewPetition) {
    if(!c.fortress_epoch() || c.fortress_epoch()>INT64_MAX || c.interruption_receipt() || c.petition_id() < -1 || c.petition_receipt()>INT64_MAX)return "invalid petition command";
    if(c.action()==SessionAction::ReviewPetition ? (c.petition_id()<0 || c.petition_receipt()!=0) : (!c.petition_receipt() || (c.action()!=SessionAction::ClosePetition && c.petition_id()<0)))return "invalid petition receipt";
  } else if(c.petition_id()!=-1 || c.petition_receipt())return "unexpected petition identity";
  if(c.action()==SessionAction::AcknowledgeAnnouncement) {
    if(!c.fortress_epoch() || c.fortress_epoch()>INT64_MAX || !c.interruption_receipt() || c.interruption_receipt()>INT64_MAX) return "invalid interruption receipt";
  } else if(c.action()==SessionAction::SaveContinue || c.action()==SessionAction::SaveReturn) {
    if(!c.fortress_epoch() || c.fortress_epoch()>INT64_MAX || c.interruption_receipt()) return "save fortress epoch required";
  } else if(c.action()<SessionAction::ReviewPetition && (c.fortress_epoch() || c.interruption_receipt())) return "unexpected interruption receipt";
  if (c.action() == SessionAction::LoadFortress) {
    if (!c.save_id() || !validSaveId(c.save_id()->str())) return "invalid save id";
  } else if (c.save_id() && c.save_id()->size()) return "save action cannot specify a path";
  if (c.action() == SessionAction::SaveContinue) {
    if (!c.checkpoint_name() || !validCheckpointName(c.checkpoint_name()->str())) return "invalid checkpoint name";
  } else if (c.checkpoint_name() && c.checkpoint_name()->size()) return "unexpected checkpoint name";
  return std::nullopt;
}
inline std::optional<std::string> validateSessionState(const SessionState& s) {
  if (s.schema_version() != kSessionVersion) return "session schema version mismatch";
  if (!s.revision()) return "session revision must be nonzero";
  if (s.phase() < SessionPhase::Starting || s.phase() > SessionPhase::Saving ||
      s.request_status() < LoadRequestStatus::None || s.request_status() > LoadRequestStatus::Rejected)
    return "invalid session enum";
  if (s.request_action() < SessionAction::LoadFortress || s.request_action() > SessionAction::ClosePetition) return "invalid session action";
  if (const auto* groups=s.active_notifications()) {
    if (groups->size()>kMaxNotificationGroups || (groups->size() && (!s.fortress_valid() || !s.fortress_epoch()))) return "invalid active notification groups";
    for (const auto* group:*groups) {
      if (!group || group->category()>NotificationCategory::Hunting || !group->report_ids() || !group->unit_reports()) return "invalid notification category or references";
      if (group->report_ids()->size()>kMaxNotificationReferences || group->unit_reports()->size()>kMaxNotificationReferences || group->report_ids()->size()>group->report_count() || group->unit_reports()->size()>group->unit_report_count()) return "invalid notification counts";
      if (group->complete() && (group->report_ids()->size()!=group->report_count() || group->unit_reports()->size()!=group->unit_report_count())) return "incomplete notification references";
      for (auto id:*group->report_ids()) if(id<0) return "invalid notification report identity";
      for (const auto* ref:*group->unit_reports()) if(!ref || ref->unit_id()<0 || ref->category()>UnitReportCategory::Hunting) return "invalid unit report identity";
    }
  }
  if (const auto* f=s.fortress_summary()) {
    if (!s.fortress_valid() || !s.fortress_epoch() || f->population()<0 ||
        f->population()>100000 || !f->level_count() || f->level_count()>65536 ||
        f->elevation_offset() < -65536 || f->elevation_offset()>65536)
      return "invalid fortress summary";
    if (!f->stress_counts() || f->stress_counts()->size()!=7) return "invalid stress categories";
    const auto* resources=f->resource_counts();
    if (f->resources_available()) {
      if (!resources || resources->size()!=7) return "invalid resource categories";
      for (auto count:*resources) if(count<0) return "negative resource count";
    } else if(resources && resources->size()) return "unavailable resource counts";
    uint64_t total=0;
    for (auto count:*f->stress_counts()) total+=count;
    if (total>100000 || (!f->stress_available() && total)) return "invalid stress counts";
  }
  if(s.fortress_epoch()>INT64_MAX || (!s.fortress_valid() && s.fortress_epoch())) return "invalid fortress epoch";
  if(const auto* i=s.interruption()) {
    if(i->kind()>InterruptionKind::OtherDecision || i->receipt()>INT64_MAX || (i->text() && i->text()->size()>32768) || (i->reason() && i->reason()->size()>2048)) return "invalid interruption state";
    if(i->can_acknowledge() && (i->kind()!=InterruptionKind::PassiveAnnouncement || !i->receipt() || !i->popup_count() || !s.fortress_epoch() || !s.fortress_valid() || s.phase()!=SessionPhase::Ready)) return "invalid acknowledgement availability";
    if(i->receipt() && i->kind()!=InterruptionKind::PassiveAnnouncement) return "unexpected interruption receipt";
  }
  if(const auto* p=s.petition()) {
    if(p->id() < -1 || p->receipt()>INT64_MAX || !p->reason() || p->reason()->size()>2048 || p->guildhall_value()<0 || p->grand_guildhall_value()<0)return "invalid petition state";
    if((p->can_review() || p->can_respond() || p->can_close() || p->receipt()) && (!s.fortress_valid() || !s.fortress_epoch() || s.phase()!=SessionPhase::Ready))return "invalid petition availability";
    if((p->can_respond() || p->can_close())!=bool(p->receipt()) || (p->can_review() && (p->id()<0 || !p->agreement())) || (p->can_respond() && (p->id()<0 || !p->can_close() || !p->agreement())))return "inconsistent petition receipt";
    if(p->can_close() && p->id()>=0 && (!p->agreement() || !p->agreement()->complete()))return "incomplete petition close identity";
    if(const auto* a=p->agreement()) {
      auto text=[](const flatbuffers::String* t){return t && t->size()<=2048;};
      if(a->id()!=p->id() || a->id()<0 || a->status()>AgreementStatus::Concluded || !text(a->summary()) || !text(a->reason()) || !a->details() || a->details()->size()!=1 || !a->parties() || a->parties()->size()!=2)return "invalid petition agreement";
      std::set<int32_t> parties;
      for(const auto* q:*a->parties()) {
        if(!q || q->id()<0 || !parties.insert(q->id()).second || !text(q->name()))return "invalid petition party";
        for(auto* v:{q->entity_ids(),q->histfig_ids()}) {if(!v || v->size()>32)return "invalid petition membership";std::set<int32_t> ids;for(auto id:*v)if(id<0 || !ids.insert(id).second)return "invalid petition member";}
      }
      const auto* d=a->details()->Get(0);
      if(!d || d->id()<0 || d->kind()!=12 || d->location_type()!=11 || d->tier()!=1 || d->profession()<0 || d->deity_type()< -1 || d->deity_id()< -1 || d->site_id()<0 || d->year()<0 || d->year_tick()<0 || d->year_tick()>=403200 || !parties.count(d->applicant_party()) || !parties.count(d->government_party()) || d->applicant_party()==d->government_party() || !text(d->description()))return "invalid petition terms";
      if((p->can_review() || p->can_respond()) && (!a->complete() || a->status()!=AgreementStatus::Pending || !a->not_approved() || a->concluded() || a->continuing()))return "invalid petition response availability";
    }
  }
  if (s.year() < 0 || s.year_tick() < 0 || s.year_tick() >= 403200 ||
      (s.fort_name() && s.fort_name()->size() > 4096)) return "invalid fortress status";
  if ((s.can_save() || s.can_save_return()) && (!s.fortress_valid() || s.phase() != SessionPhase::Ready)) return "invalid save availability";
  if ((s.request_seq() == 0) != (s.request_status() == LoadRequestStatus::None)) return "inconsistent load result";
  if (s.message() && s.message()->size() > 8192) return "session message too long";
  if (s.active_save_id() && s.active_save_id()->size() > 2048) return "active save id too long";
  if (s.saved_save_id() && !s.saved_save_id()->str().empty() &&
      (!validSaveId(s.saved_save_id()->str()) || s.request_status() != LoadRequestStatus::Ok ||
       (s.request_action() != SessionAction::SaveContinue && s.request_action() != SessionAction::SaveReturn))) return "invalid saved destination";
  std::set<std::string> ids;
  if (s.saves()) {
    if (s.saves()->size() > 2048) return "too many saves";
    for (auto* save : *s.saves()) {
      if (!save || !save->id() || !validSaveId(save->id()->str()) || !ids.insert(save->id()->str()).second)
        return "invalid or duplicate save id";
      if ((save->fort_name() && save->fort_name()->size() > 4096) ||
          (save->world_name() && save->world_name()->size() > 4096) || save->year() < 0)
        return "invalid save metadata";
    }
  }
  return std::nullopt;
}
}
