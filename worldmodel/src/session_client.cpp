#include "wm/session_client.h"
#include "session_util.h"
#include "request_channel.h"
#include <algorithm>
namespace wm {
namespace m = df3d::mirror;
struct SessionClient::Impl {
#ifdef _WIN32
  std::unique_ptr<detail::RequestChannel> channel;
  uint64_t replyRevision = 0;
  std::vector<uint8_t> replyScratch;
#endif
  std::vector<uint8_t> scratch;
  std::string name;
};
SessionClient::SessionClient() : impl_(new Impl) {}
SessionClient::~SessionClient() = default;
std::unique_ptr<SessionClient> SessionClient::open(std::string& error, const std::string& name) {
#ifdef _WIN32
  std::unique_ptr<SessionClient> c(new SessionClient);
  c->impl_->channel = detail::RequestChannel::open(
      name.empty() ? m::kSessionRegionName : name,
      {m::kSessionVersion, m::kSessionCapacity, m::kSessionCommandCapacity,
       "DF session bridge is not available", "Could not map DF session bridge",
       "Unexpected session channel capacity", "DF session process has ended",
       "Cannot create session client transport"}, error);
  if (!c->impl_->channel) return nullptr;
  c->impl_->replyScratch.resize(m::kSessionCapacity);
  c->impl_->name = name;
  c->impl_->scratch.resize(m::kSessionCapacity);
  error.clear(); return c;
#else
  error = "Session bridge requires Windows"; return nullptr;
#endif
}
bool SessionClient::poll() {
#ifdef _WIN32
  if (!impl_->channel) {
    auto fresh = open(error_, impl_->name);
    if (!fresh) return false;
    impl_ = std::move(fresh->impl_); state_ = SessionState{}; seq_ = pendingSeq_ = 0;
  }
  if (!impl_->channel->alive()) {
    // A stopped or replaced producer cannot deliver a late receipt. Preserve
    // the submitted identity: a lost read supplies no catalog, while a save's
    // effect remains unknown. Neither request is automatically replayed.
    const auto lostSeq=pendingSeq_,lostEpoch=state_.requestFortressEpoch;
    const auto lostAction=state_.requestAction;
    const auto name = impl_->name;
    impl_.reset(new Impl); impl_->name = name;
    state_ = SessionState{}; state_.phase = SessionPhase::Unavailable;
    pendingSeq_ = 0;
    const bool lostEffect=lostAction==SessionAction::SaveContinue || lostAction==SessionAction::SaveReturn || lostAction==SessionAction::QuitWithoutSaving;
    if(lostSeq && (lostEffect || lostAction==SessionAction::ReadSaveDestinations)) {
      state_.requestSeq=lostSeq;state_.requestFortressEpoch=lostEpoch;
      state_.requestAction=lostAction;
      state_.requestStatus=lostEffect?LoadRequestStatus::UnknownOutcome:LoadRequestStatus::Rejected;
    }
    state_.message = error_ = "Dwarf Fortress has closed"; return true;
  }
  auto& im = *impl_;
  auto len = im.channel->readPublic(im.scratch.data(), im.scratch.size());
  if (!len) return false;
  flatbuffers::Verifier v(im.scratch.data(), len);
  if (!v.VerifyBuffer<m::SessionState>(nullptr)) { error_ = "Invalid session buffer"; return false; }
  auto* s = flatbuffers::GetRoot<m::SessionState>(im.scratch.data());
  if (auto e = m::validateSessionState(*s)) { error_ = *e; return false; }
  const m::SessionState* receipt=nullptr;
  const auto receiptLen=im.channel->readReply(im.replyScratch.data(),im.replyScratch.size());
  if(receiptLen) {
    flatbuffers::Verifier verify(im.replyScratch.data(),receiptLen);
    if(verify.VerifyBuffer<m::SessionState>(nullptr)) {
      auto* candidate=flatbuffers::GetRoot<m::SessionState>(im.replyScratch.data());
      if(!m::validateSessionState(*candidate) && candidate->request_client_id()==im.channel->clientId())receipt=candidate;
    }
  }
  const auto receiptRevision=receipt?receipt->revision():0;
  if(s->revision()==state_.revision && receiptRevision==im.replyRevision){error_.clear();return false;}
  im.replyRevision=receiptRevision;
  SessionState next;
  next.revision = s->revision(); next.phase = static_cast<SessionPhase>(s->phase());
  next.requestSeq = s->request_seq(); next.requestStatus = static_cast<LoadRequestStatus>(s->request_status());
  next.requestAction = static_cast<SessionAction>(s->request_action());
  next.fortressValid = s->fortress_valid(); next.paused = s->paused();
  next.year = s->year(); next.yearTick = s->year_tick();
  next.canSave = s->can_save(); next.canSaveReturn = s->can_save_return();
  next.fortressEpoch=s->fortress_epoch();
  next.activeNotificationsComplete=s->active_notifications_complete();
  next.alertButtonReportCount=s->alert_button_report_count();next.alertButtonComplete=s->alert_button_complete();
  if(s->alert_button_report_ids())for(auto id:*s->alert_button_report_ids())next.alertButtonReportIds.push_back(id);
  if(const auto* groups=s->active_notifications()) for(const auto* group:*groups) {
    ActiveNotificationGroup n;n.category=static_cast<NotificationCategory>(group->category());
    n.reportIds.assign(group->report_ids()->begin(),group->report_ids()->end());
    n.reportCount=group->report_count();n.unitReportCount=group->unit_report_count();n.complete=group->complete();
    for(const auto* ref:*group->unit_reports())n.unitReports.push_back({ref->unit_id(),static_cast<UnitReportCategory>(ref->category())});
    next.activeNotifications.push_back(std::move(n));
  }
  if(const auto* f=s->fortress_summary()) {
    auto& n=next.fortressSummary;n.available=true;n.population=f->population();
    n.elevationOffset=f->elevation_offset();n.levelCount=f->level_count();n.stressAvailable=f->stress_available();
    n.stressCounts.assign(f->stress_counts()->begin(),f->stress_counts()->end());
    n.resourcesAvailable=f->resources_available();
    n.bookkeeperPrecision=f->bookkeeper_precision();
    if(n.resourcesAvailable)n.resourceCounts.assign(f->resource_counts()->begin(),f->resource_counts()->end());
  }
  if(const auto* i=s->interruption()) {
    auto& n=next.interruption;n.kind=static_cast<InterruptionKind>(i->kind());n.receipt=i->receipt();n.popupCount=i->popup_count();n.canAcknowledge=i->can_acknowledge();
    if(i->text())n.text=i->text()->str();
    if(i->reason())n.reason=i->reason()->str();
  }
  if(const auto* v=s->petition()) {
    auto& p=next.petition;p.id=v->id();p.receipt=v->receipt();p.canReview=v->can_review();p.canRespond=v->can_respond();p.canClose=v->can_close();p.reason=v->reason()->str();p.guildhallValue=v->guildhall_value();p.grandGuildhallValue=v->grand_guildhall_value();
    if(const auto* a=v->agreement()) {
      p.hasAgreement=true;auto& n=p.agreement;n.id=a->id();n.status=uint8_t(a->status());n.notApproved=a->not_approved();n.concluded=a->concluded();n.continuing=a->continuing();n.complete=a->complete();n.summary=a->summary()->str();n.reason=a->reason()->str();
      for(const auto* d:*a->details()){AgreementDetail t;t.id=d->id();t.kind=d->kind();t.siteId=d->site_id();t.year=d->year();t.yearTick=d->year_tick();t.applicantParty=d->applicant_party();t.governmentParty=d->government_party();t.locationType=d->location_type();t.tier=d->tier();t.profession=d->profession();t.deityType=d->deity_type();t.deityId=d->deity_id();t.description=d->description()->str();n.details.push_back(std::move(t));}
      for(const auto* q:*a->parties()){AgreementParty t;t.id=q->id();t.name=q->name()->str();t.entityIds.assign(q->entity_ids()->begin(),q->entity_ids()->end());t.histfigIds.assign(q->histfig_ids()->begin(),q->histfig_ids()->end());n.parties.push_back(std::move(t));}
    }
  }
  if (s->fort_name()) next.fortName = s->fort_name()->str();
  if (s->fort_original_name()) next.fortOriginalName = s->fort_original_name()->str();
  next.fortressRank = s->fortress_rank();
  next.fortressCapital = s->fortress_capital();
  next.moonPhase = s->moon_phase();
  if (s->active_save_id()) next.activeSaveId = s->active_save_id()->str();
  if (s->saved_save_id()) next.savedSaveId = s->saved_save_id()->str();
  if (s->message()) next.message = s->message()->str();
  if (s->saves()) for (auto* save : *s->saves()) next.saves.push_back({save->id()->str(),
      save->fort_name() ? save->fort_name()->str() : "", save->world_name() ? save->world_name()->str() : "", save->year()});
  // Global simulation state and this client's durable request receipt advance
  // independently. Never inherit another client's status, sequence or save ID.
  next.requestSeq=receipt?receipt->request_seq():0;
  next.requestFortressEpoch=receipt?receipt->request_fortress_epoch():0;
  next.requestStatus=receipt?static_cast<LoadRequestStatus>(receipt->request_status()):LoadRequestStatus::None;
  next.requestAction=receipt?static_cast<SessionAction>(receipt->request_action()):SessionAction::LoadFortress;
  next.savedSaveId=receipt && receipt->saved_save_id()?receipt->saved_save_id()->str():"";
  if(receipt && receipt->message())next.message=receipt->message()->str();
  // Only our private successful read can authorize a destination choice.
  if(receipt && receipt->save_destinations()) {
    const auto* catalog=receipt->save_destinations();
    next.saveDestinations.receipt=catalog->receipt();
    next.saveDestinations.fortressEpoch=catalog->fortress_epoch();
    for(const auto* destination:*catalog->destinations())
      next.saveDestinations.destinations.push_back({destination->id()->str(),destination->folder()->str()});
  }
  // A status publication made just before the producer drains our request
  // must not reopen the command gate. Keep local ownership until observed.
  if (pendingSeq_ && next.requestSeq < pendingSeq_) {
    next.requestSeq = pendingSeq_; next.requestStatus = LoadRequestStatus::Pending;
    next.requestFortressEpoch=state_.requestFortressEpoch;
    next.requestAction = state_.requestAction; next.canSave = next.canSaveReturn = false;
    next.savedSaveId.clear();
    next.saveDestinations={};
  } else if (pendingSeq_ && next.requestStatus != LoadRequestStatus::Pending) pendingSeq_ = 0;
  state_ = std::move(next); seq_ = std::max(seq_, state_.requestSeq); error_.clear(); return true;
#else
  return false;
#endif
}
uint64_t SessionClient::sendLoadSave(const std::string& id) {
#ifdef _WIN32
  if (state_.phase != SessionPhase::Menu || state_.requestStatus == LoadRequestStatus::Pending) {
    error_ = "DF is not ready to load a fortress"; return 0;
  }
  if (std::none_of(state_.saves.begin(), state_.saves.end(), [&](const FortressSave& s) { return s.id == id; })) {
    error_ = "That save is no longer available"; return 0;
  }
  return send(SessionAction::LoadFortress, id);
#else
  return 0;
#endif
}
uint64_t SessionClient::sendSave(bool returnToMenu, const std::string& checkpointName) {
  if(returnToMenu) { error_="Explicit save destination required";return 0; }
  if ((!returnToMenu && !m::validCheckpointName(checkpointName)) || (returnToMenu && !checkpointName.empty())) {
    error_ = "Use a new checkpoint name with letters, numbers, spaces, hyphens or underscores"; return 0;
  }
  if (state_.phase != SessionPhase::Ready || state_.requestStatus == LoadRequestStatus::Pending ||
      (!state_.fortressEpoch || !(returnToMenu ? state_.canSaveReturn : state_.canSave))) {
    error_ = "DF is not ready for this save operation"; return 0;
  }
  return send(returnToMenu ? SessionAction::SaveReturn : SessionAction::SaveContinue, {}, checkpointName, state_.fortressEpoch);
}
uint64_t SessionClient::sendReadSaveDestinations(uint64_t epoch) {
  if(state_.phase!=SessionPhase::Ready || state_.requestStatus==LoadRequestStatus::Pending ||
     !state_.fortressValid || !state_.canSaveReturn || !epoch || epoch!=state_.fortressEpoch) {
    error_="DF is not ready to inspect save destinations";return 0;
  }
  return send(SessionAction::ReadSaveDestinations,{},{},epoch);
}
uint64_t SessionClient::sendQuitWithoutSaving(uint64_t epoch) {
  if(state_.phase!=SessionPhase::Ready || state_.requestStatus==LoadRequestStatus::Pending ||
     !state_.fortressValid || !state_.canSaveReturn || !epoch || epoch!=state_.fortressEpoch) {
    error_="DF is not ready for this session operation";return 0;
  }
  return send(SessionAction::QuitWithoutSaving,{},{},epoch);
}
uint64_t SessionClient::sendSaveReturn(uint64_t epoch,uint64_t catalogReceipt,SaveReturnMode mode,
                                     const std::string& destinationId,const std::vector<uint8_t>& timelineName) {
  const auto& catalog=state_.saveDestinations;
  if(state_.phase!=SessionPhase::Ready || state_.requestStatus==LoadRequestStatus::Pending ||
     !state_.fortressValid || !state_.canSaveReturn || !epoch || epoch!=state_.fortressEpoch ||
     epoch!=catalog.fortressEpoch || !catalogReceipt || catalogReceipt!=catalog.receipt) {
    error_="Save destination catalog changed or is unavailable";return 0;
  }
  if(mode==SaveReturnMode::ExistingDestination &&
     std::none_of(catalog.destinations.begin(),catalog.destinations.end(),[&](const SaveDestination& d){return d.id==destinationId;})) {
    error_="Save destination is not in this catalog";return 0;
  }
  return send(SessionAction::SaveReturn,{},{},epoch,0,-1,0,catalogReceipt,mode,destinationId,timelineName);
}
uint64_t SessionClient::sendAcknowledgeAnnouncement(uint64_t fortressEpoch,uint64_t receipt) {
  if(state_.phase!=SessionPhase::Ready || state_.requestStatus==LoadRequestStatus::Pending || !state_.interruption.canAcknowledge || !fortressEpoch || fortressEpoch!=state_.fortressEpoch || !receipt || receipt!=state_.interruption.receipt || receipt>INT64_MAX) {
    error_="That announcement changed or cannot be acknowledged";return 0;
  }
  return send(SessionAction::AcknowledgeAnnouncement,{},{},fortressEpoch,receipt);
}
uint64_t SessionClient::sendReviewPetition(uint64_t epoch,int32_t id) {
  if(state_.phase!=SessionPhase::Ready || state_.requestStatus==LoadRequestStatus::Pending || !state_.fortressValid || !epoch || epoch!=state_.fortressEpoch || id<0 || id!=state_.petition.id || !state_.petition.canReview){error_="That petition cannot be reviewed";return 0;}
  return send(SessionAction::ReviewPetition,{},{},epoch,0,id);
}
uint64_t SessionClient::sendPetitionResponse(uint64_t epoch,int32_t id,uint64_t receipt,bool approve) {
  if(state_.phase!=SessionPhase::Ready || state_.requestStatus==LoadRequestStatus::Pending || !state_.fortressValid || !epoch || epoch!=state_.fortressEpoch || id<0 || id!=state_.petition.id || !receipt || receipt>INT64_MAX || receipt!=state_.petition.receipt || !state_.petition.canRespond){error_="That petition response receipt changed";return 0;}
  return send(approve?SessionAction::ApprovePetition:SessionAction::DenyPetition,{},{},epoch,0,id,receipt);
}
uint64_t SessionClient::sendClosePetition(uint64_t epoch,int32_t id,uint64_t receipt) {
  if(state_.phase!=SessionPhase::Ready || state_.requestStatus==LoadRequestStatus::Pending || !state_.fortressValid || !epoch || epoch!=state_.fortressEpoch || id< -1 || id!=state_.petition.id || !receipt || receipt>INT64_MAX || receipt!=state_.petition.receipt || !state_.petition.canClose){error_="That native petition review changed";return 0;}
  return send(SessionAction::ClosePetition,{},{},epoch,0,id,receipt);
}
uint64_t SessionClient::send(SessionAction action, const std::string& id, const std::string& checkpointName,uint64_t fortressEpoch,uint64_t receipt,int32_t petitionId,uint64_t petitionReceipt,
                             uint64_t catalogReceipt,SaveReturnMode mode,const std::string& destinationId,const std::vector<uint8_t>& timelineName) {
#ifdef _WIN32
  if (!impl_->channel || !impl_->channel->alive()) {
    error_ = "DF session is no longer available"; return 0;
  }
  flatbuffers::FlatBufferBuilder b;
  auto c = m::CreateSessionCommand(b, m::kSessionVersion, seq_ + 1, b.CreateString(id), static_cast<m::SessionAction>(action), b.CreateString(checkpointName),fortressEpoch,receipt,petitionId,petitionReceipt,impl_->channel->clientId(),catalogReceipt,static_cast<m::SaveReturnMode>(mode),b.CreateString(destinationId),b.CreateVector(timelineName)); b.Finish(c);
  if(auto error=m::validateSessionCommand(*flatbuffers::GetRoot<m::SessionCommand>(b.GetBufferPointer()))) {error_=*error;return 0;}
  if (!impl_->channel->push(b.GetBufferPointer(), b.GetSize())) { error_ = "Session command queue is full"; return 0; }
  error_.clear(); state_.requestStatus = LoadRequestStatus::Pending;
  state_.savedSaveId.clear();
  state_.saveDestinations={};
  state_.requestFortressEpoch=fortressEpoch;
  state_.requestAction = action; state_.requestSeq = pendingSeq_ = ++seq_; return seq_;
#else
  return 0;
#endif
}
}
