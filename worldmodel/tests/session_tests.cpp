#include "doctest.h"
#include "wm/session_client.h"
#include "session_util.h"
#include "shm_layout.h"
#include "client_mailbox.h"
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
namespace {
namespace m = df3d::mirror;
namespace sh = df3d::shm;
struct Publisher {
  HANDLE mapping;
  sh::RegionHeader* r;
  uint64_t generation=0, lastClient=0;
  std::string name = "Local\\df3d_session_test_" + std::to_string(GetCurrentProcessId());
  Publisher() {
    mapping = CreateFileMappingA(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
        DWORD(sh::regionSize(m::kSessionCapacity, m::kSessionCommandCapacity)), name.c_str());
    REQUIRE(mapping);
    REQUIRE(GetLastError() != ERROR_ALREADY_EXISTS);  // a stale publisher would alias this test
    r = static_cast<sh::RegionHeader*>(MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, 0));
    REQUIRE(r);
    reset();
  }
  void reset() {
    sh::initRegion(r, m::kSessionVersion, m::kSessionCapacity, m::kSessionCommandCapacity);
    FILETIME c{},e{},k{},u{}; GetProcessTimes(GetCurrentProcess(), &c,&e,&k,&u);
    sh::atomicStoreRelease(&m::sessionOwner(r)->created, (uint64_t(c.dwHighDateTime)<<32)|c.dwLowDateTime);
    sh::atomicStoreRelease(&m::sessionOwner(r)->pid, GetCurrentProcessId());
    sh::atomicStoreRelease(&m::sessionOwner(r)->generation,++generation);
  }
  ~Publisher() { UnmapViewOfFile(r); CloseHandle(mapping); }
  size_t pop(uint8_t* bytes,size_t size) {
    auto n=sh::popCommand(r,bytes,size);
    if(n && n!=SIZE_MAX)lastClient=flatbuffers::GetRoot<m::SessionCommand>(bytes)->client_id();
    return n;
  }
  bool write(const uint8_t* bytes,size_t size) {
    auto reply=sh::ClientMailbox::open(name,generation,lastClient,m::kSessionVersion,m::kSessionCapacity);
    if(reply)REQUIRE(sh::publishSnapshot(reply->region(),bytes,size,0));
    return sh::publishSnapshot(r,bytes,size,0);
  }
  void publish(uint64_t rev, m::SessionPhase phase, uint64_t seq=0,
               m::LoadRequestStatus status=m::LoadRequestStatus::None, bool empty=false,
               m::SessionAction action=m::SessionAction::LoadFortress, const std::string& savedId={}) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<m::FortressSave>> saves;
    if (!empty) saves.push_back(m::CreateFortressSave(b,b.CreateString("save-a"),b.CreateString("Fort A"),b.CreateString("World A"),100));
    const bool loaded = phase == m::SessionPhase::Ready || phase == m::SessionPhase::Saving;
    auto s = m::CreateSessionState(b,m::kSessionVersion,rev,phase,b.CreateVector(saves),0,seq,status,0,
        action,loaded,true,loaded ? 105:0,loaded ? 33600:0,b.CreateString(loaded ? "Fort A":""),
        phase==m::SessionPhase::Ready,phase==m::SessionPhase::Ready,b.CreateString(savedId),loaded ? 71 : 0,0,0,0,0,true,lastClient);
    b.Finish(s); REQUIRE(write(b.GetBufferPointer(),b.GetSize()));
  }
  void publishInterruption(uint64_t rev,uint64_t epoch,uint64_t receipt,uint32_t count,
      uint64_t seq=0,m::LoadRequestStatus status=m::LoadRequestStatus::None,
      m::SessionPhase phase=m::SessionPhase::Ready) {
    flatbuffers::FlatBufferBuilder b;
    const bool passive=count>0,loaded=phase==m::SessionPhase::Ready || phase==m::SessionPhase::Saving;
    auto notice=m::CreateInterruptionState(b,passive?m::InterruptionKind::PassiveAnnouncement:m::InterruptionKind::ManualPause,
      receipt,b.CreateString(passive?"Identical native notice":""),b.CreateString(""),count,
      passive && receipt && phase==m::SessionPhase::Ready && status!=m::LoadRequestStatus::Pending);
    m::SessionStateBuilder s(b);s.add_schema_version(m::kSessionVersion);s.add_revision(rev);s.add_phase(phase);
    s.add_request_client_id(lastClient);s.add_request_seq(seq);s.add_request_status(status);s.add_request_action(m::SessionAction::AcknowledgeAnnouncement);
    s.add_fortress_valid(loaded);s.add_paused(true);s.add_fortress_epoch(epoch);s.add_interruption(notice);
    b.Finish(s.Finish());
    REQUIRE_FALSE(m::validateSessionState(*flatbuffers::GetRoot<m::SessionState>(b.GetBufferPointer())).has_value());
    REQUIRE(write(b.GetBufferPointer(),b.GetSize()));
  }
};
}
TEST_CASE("session menu/results advance without any simulation tick") {
  Publisher p; p.publish(1,m::SessionPhase::Menu);
  std::string error; auto c = wm::SessionClient::open(error,p.name); REQUIRE(c); REQUIRE(c->poll());
  CHECK(c->state().saves.size()==1); CHECK(sh::atomicLoadAcquire(&p.r->bridgeTick)==0);
  CHECK(c->sendLoadSave("unknown")==0);
  auto seq=c->sendLoadSave("save-a"); REQUIRE(seq==1);
  CHECK(c->sendLoadSave("save-a")==0);
  uint8_t bytes[4096]; auto len=p.pop(bytes,sizeof(bytes)); REQUIRE(len>0);
  flatbuffers::Verifier v(bytes,len); REQUIRE(v.VerifyBuffer<m::SessionCommand>(nullptr));
  auto* cmd=flatbuffers::GetRoot<m::SessionCommand>(bytes); CHECK(cmd->seq()==seq); CHECK(cmd->save_id()->str()=="save-a");
  p.publish(2,m::SessionPhase::Loading,seq,m::LoadRequestStatus::Pending); REQUIRE(c->poll());
  CHECK(c->state().phase==wm::SessionPhase::Loading);
  p.publish(3,m::SessionPhase::Menu,seq,m::LoadRequestStatus::Rejected,true); REQUIRE(c->poll());
  CHECK(c->state().requestStatus==wm::LoadRequestStatus::Rejected); CHECK(c->sendLoadSave("save-a")==0);
  CHECK_FALSE(c->poll());
  auto reconnect=wm::SessionClient::open(error,p.name); REQUIRE(reconnect); REQUIRE(reconnect->poll());
  CHECK(reconnect->state().requestSeq==0); CHECK(reconnect->state().requestStatus==wm::LoadRequestStatus::None);
  p.publish(4,m::SessionPhase::Menu,seq,m::LoadRequestStatus::Rejected); REQUIRE(reconnect->poll());
  CHECK(reconnect->sendLoadSave("save-a")==1);
}
TEST_CASE("session busy receipt is private and cannot replace another client's completion") {
  Publisher p;p.publish(1,m::SessionPhase::Menu);std::string error;
  auto a=wm::SessionClient::open(error,p.name),b=wm::SessionClient::open(error,p.name);
  REQUIRE(a);REQUIRE(b);REQUIRE(a->poll());REQUIRE(b->poll());
  REQUIRE(a->sendLoadSave("save-a")==1);REQUIRE(b->sendLoadSave("save-a")==1);
  uint8_t bytes[4096];REQUIRE(p.pop(bytes,sizeof(bytes))>0);const auto aid=p.lastClient;
  p.publish(2,m::SessionPhase::Loading,1,m::LoadRequestStatus::Pending);
  REQUIRE(p.pop(bytes,sizeof(bytes))>0);const auto bid=p.lastClient;REQUIRE(aid!=bid);
  p.publish(3,m::SessionPhase::Loading,1,m::LoadRequestStatus::Rejected);
  REQUIRE(a->poll());REQUIRE(b->poll());
  CHECK(a->state().requestStatus==wm::LoadRequestStatus::Pending);CHECK(b->state().requestStatus==wm::LoadRequestStatus::Rejected);
  p.lastClient=aid;p.publish(4,m::SessionPhase::Ready,1,m::LoadRequestStatus::Ok);
  REQUIRE(a->poll());REQUIRE(b->poll());CHECK(a->state().requestStatus==wm::LoadRequestStatus::Ok);
  CHECK(b->state().requestStatus==wm::LoadRequestStatus::Rejected);CHECK(b->state().phase==wm::SessionPhase::Ready);
  p.lastClient=0;p.publish(5,m::SessionPhase::Ready);
  REQUIRE(a->poll());REQUIRE(b->poll());CHECK(a->state().requestStatus==wm::LoadRequestStatus::Ok);
  CHECK(b->state().requestStatus==wm::LoadRequestStatus::Rejected);
}
TEST_CASE("new session clients never inherit another request save destination") {
  Publisher p;
  p.publish(1, m::SessionPhase::Menu, 7, m::LoadRequestStatus::Ok, false,
            m::SessionAction::SaveReturn, "appdata/save/region-new");
  std::string error;
  auto client = wm::SessionClient::open(error, p.name);
  REQUIRE(client); REQUIRE(client->poll());
  CHECK(client->state().savedSaveId.empty());
  CHECK(client->state().activeSaveId.empty());
  auto reconnect = wm::SessionClient::open(error, p.name);
  REQUIRE(reconnect); REQUIRE(reconnect->poll());
  CHECK(reconnect->state().savedSaveId == client->state().savedSaveId);
}
TEST_CASE("session stopped owner releases channel and reconnects at a fresh revision") {
  Publisher p; p.publish(5,m::SessionPhase::Menu);
  std::string error; auto c=wm::SessionClient::open(error,p.name); REQUIRE(c); REQUIRE(c->poll());
  sh::atomicStoreRelease(&m::sessionOwner(p.r)->pid,0); REQUIRE(c->poll());
  CHECK(c->state().phase==wm::SessionPhase::Unavailable); CHECK(c->state().saves.empty());
  CHECK_FALSE(c->poll());
  p.reset(); p.publish(1,m::SessionPhase::Menu); REQUIRE(c->poll()); CHECK(c->state().revision==1);
  CHECK(c->sendLoadSave("save-a")==1);
  // Re-enabled plugin in the same process must not reuse a previous revision.
  p.reset(); p.publish(1,m::SessionPhase::Menu); REQUIRE(c->poll());
  CHECK(c->state().phase==wm::SessionPhase::Unavailable); REQUIRE(c->poll());
  CHECK(c->state().phase==wm::SessionPhase::Menu);
  sh::atomicStoreRelease(&m::sessionOwner(p.r)->created,1);
  CHECK_FALSE(wm::SessionClient::open(error,p.name));
}
TEST_CASE("session save uses no path, retains matching result, and carries authoritative status") {
  Publisher p; p.publish(1,m::SessionPhase::Ready);
  std::string error; auto c=wm::SessionClient::open(error,p.name); REQUIRE(c); REQUIRE(c->poll());
  CHECK(c->state().fortressValid); CHECK(c->state().paused); CHECK(c->state().year==105);
  CHECK(c->state().yearTick==33600); CHECK(c->state().fortName=="Fort A");
  const auto seq=c->sendSave(false,"Checkpoint 1"); REQUIRE(seq==1); CHECK(c->sendSave(true)==0);
  uint8_t bytes[4096]; REQUIRE(p.pop(bytes,sizeof(bytes))>0);
  auto* cmd=flatbuffers::GetRoot<m::SessionCommand>(bytes);
  CHECK(cmd->action()==m::SessionAction::SaveContinue); CHECK(cmd->save_id()->str().empty());
  CHECK(cmd->fortress_epoch()==71); CHECK_FALSE(m::validateSessionCommand(*cmd));
  CHECK(m::sessionEpochMatches(cmd->fortress_epoch(),71)); CHECK_FALSE(m::sessionEpochMatches(cmd->fortress_epoch(),72));
  p.publish(10,m::SessionPhase::Ready); REQUIRE(c->poll());
  CHECK(c->state().requestStatus==wm::LoadRequestStatus::Pending); CHECK(c->sendSave(false,"Checkpoint 1")==0);
  p.publish(2,m::SessionPhase::Saving,seq,m::LoadRequestStatus::Pending,false,m::SessionAction::SaveContinue);
  REQUIRE(c->poll()); CHECK_FALSE(c->state().canSave); CHECK(c->sendSave(false,"Checkpoint 1")==0);
  auto reconnect=wm::SessionClient::open(error,p.name); REQUIRE(reconnect); REQUIRE(reconnect->poll());
  CHECK(reconnect->state().requestStatus==wm::LoadRequestStatus::None); CHECK(reconnect->sendSave(false,"Checkpoint 1")==0);
  p.publish(3,m::SessionPhase::Ready,seq,m::LoadRequestStatus::Ok,false,m::SessionAction::SaveContinue);
  REQUIRE(reconnect->poll()); CHECK(reconnect->state().requestStatus==wm::LoadRequestStatus::None);
  CHECK(reconnect->sendSave(true)==1);
  REQUIRE(p.pop(bytes,sizeof(bytes))>0);
  CHECK(flatbuffers::GetRoot<m::SessionCommand>(bytes)->action()==m::SessionAction::SaveReturn);
  sh::atomicStoreRelease(&m::sessionOwner(p.r)->pid,0);
  REQUIRE(c->poll()); CHECK_FALSE(c->state().fortressValid); CHECK(c->sendSave(false,"Checkpoint 1")==0);
}
TEST_CASE("only global lifecycle session actions remain executable") {
  CHECK(m::runtimeSessionAction(m::SessionAction::LoadFortress));
  CHECK(m::runtimeSessionAction(m::SessionAction::SaveContinue));
  CHECK(m::runtimeSessionAction(m::SessionAction::SaveReturn));
  for(int action=int(m::SessionAction::AcknowledgeAnnouncement);action<=int(m::SessionAction::ClosePetition);++action)
    CHECK_FALSE(m::runtimeSessionAction(static_cast<m::SessionAction>(action)));
}
TEST_CASE("session schema validates versions enums metadata and request ownership") {
  flatbuffers::FlatBufferBuilder b;
  auto command=m::CreateSessionCommand(b,1,1,b.CreateString("id")); b.Finish(command);
  CHECK(m::validateSessionCommand(*flatbuffers::GetRoot<m::SessionCommand>(b.GetBufferPointer())).has_value());
  b.Clear(); auto c=m::CreateSessionCommand(b,m::kSessionVersion,0,b.CreateString("id")); b.Finish(c);
  CHECK(m::validateSessionCommand(*flatbuffers::GetRoot<m::SessionCommand>(b.GetBufferPointer())).has_value());
  CHECK_FALSE(m::validSaveId("")); CHECK_FALSE(m::validSaveId(std::string(2049,'x')));
  CHECK(m::validCheckpointName("My fort 105-Granite"));
  for (const auto* name : {"", "../region1", "C:/save", " leading", "trailing ", "NUL", "con", "COM1"})
    CHECK_FALSE(m::validCheckpointName(name));
  for (int which=0; which<3; ++which) {
    b.Clear(); auto bad=m::CreateSessionCommand(b,m::kSessionVersion,1,
        b.CreateString(which==0 ? "arbitrary/path":""), which==1 ? static_cast<m::SessionAction>(99) :
        (which==2 ? m::SessionAction::LoadFortress:m::SessionAction::SaveContinue)); b.Finish(bad);
    CHECK(m::validateSessionCommand(*flatbuffers::GetRoot<m::SessionCommand>(b.GetBufferPointer())).has_value());
  }
  for (int which=0; which<3; ++which) {
    b.Clear(); auto bad=m::CreateSessionState(b,m::kSessionVersion,1,m::SessionPhase::Ready,0,0,0,
        m::LoadRequestStatus::None,0,m::SessionAction::LoadFortress,which!=2,false,
        which==0 ? -1:105,which==1 ? 403200:0,0,true); b.Finish(bad);
    CHECK(m::validateSessionState(*flatbuffers::GetRoot<m::SessionState>(b.GetBufferPointer())).has_value());
  }
  for (int which=0; which<4; ++which) {
    b.Clear(); std::vector<flatbuffers::Offset<m::FortressSave>> saves;
    auto a=m::CreateFortressSave(b,b.CreateString("id"),0,0,which==2 ? -1:100); saves.push_back(a);
    if(which==3) saves.push_back(a);
    auto s=m::CreateSessionState(b,m::kSessionVersion,1,which==0 ? static_cast<m::SessionPhase>(99):m::SessionPhase::Menu,
        b.CreateVector(saves),0,which==1 ? 1:0,m::LoadRequestStatus::None); b.Finish(s);
    CHECK(m::validateSessionState(*flatbuffers::GetRoot<m::SessionState>(b.GetBufferPointer())).has_value());
  }
}
TEST_CASE("passive acknowledgments use full epoch receipts and consume one pending session request") {
  Publisher p;const uint64_t epoch=(uint64_t(1)<<40)+71,receipt=(uint64_t(1)<<40)+93;
  p.publishInterruption(1,epoch,receipt,2);
  std::string error;auto c=wm::SessionClient::open(error,p.name);REQUIRE(c);REQUIRE(c->poll());
  CHECK(c->state().fortressEpoch==epoch);CHECK(c->state().interruption.receipt==receipt);
  CHECK(c->state().interruption.popupCount==2);CHECK(c->state().interruption.text=="Identical native notice");
  CHECK(c->state().interruption.canAcknowledge);
  CHECK(c->sendAcknowledgeAnnouncement(epoch-1,receipt)==0);
  CHECK(c->sendAcknowledgeAnnouncement(epoch,receipt-1)==0);
  auto seq=c->sendAcknowledgeAnnouncement(epoch,receipt);REQUIRE(seq>0);
  uint8_t bytes[4096];auto len=p.pop(bytes,sizeof(bytes));REQUIRE(len>0);
  flatbuffers::Verifier verifier(bytes,len);REQUIRE(verifier.VerifyBuffer<m::SessionCommand>(nullptr));
  const auto* wire=flatbuffers::GetRoot<m::SessionCommand>(bytes);
  REQUIRE_FALSE(m::validateSessionCommand(*wire).has_value());CHECK(wire->action()==m::SessionAction::AcknowledgeAnnouncement);
  CHECK(wire->fortress_epoch()==epoch);CHECK(wire->interruption_receipt()==receipt);
  CHECK(c->sendAcknowledgeAnnouncement(epoch,receipt)==0);CHECK(c->sendSave(false,"Checkpoint")==0);
  p.publishInterruption(2,epoch,0,2,seq,m::LoadRequestStatus::Pending);REQUIRE(c->poll());
  CHECK_FALSE(c->state().interruption.canAcknowledge);
  p.publishInterruption(3,epoch,receipt+1,1,seq,m::LoadRequestStatus::Ok);REQUIRE(c->poll());
  CHECK(c->state().requestFortressEpoch==epoch);
  CHECK(c->sendAcknowledgeAnnouncement(epoch,receipt)==0);
  auto second=c->sendAcknowledgeAnnouncement(epoch,receipt+1);REQUIRE(second>seq);
  REQUIRE(p.pop(bytes,sizeof(bytes))>0);
  p.publishInterruption(4,epoch,0,0,second,m::LoadRequestStatus::Ok);REQUIRE(c->poll());
  CHECK(c->state().paused);CHECK(c->state().interruption.kind==wm::InterruptionKind::ManualPause);
  CHECK(c->state().interruption.text.empty());CHECK_FALSE(c->state().interruption.canAcknowledge);
  auto reconnect=wm::SessionClient::open(error,p.name);REQUIRE(reconnect);REQUIRE(reconnect->poll());
  CHECK(reconnect->sendAcknowledgeAnnouncement(epoch,receipt+1)==0);
}
TEST_CASE("world replacement and saving invalidate passive acknowledgement availability") {
  Publisher p;p.publishInterruption(1,71,9,1);
  std::string error;auto c=wm::SessionClient::open(error,p.name);REQUIRE(c);REQUIRE(c->poll());
  p.publishInterruption(2,72,10,1);REQUIRE(c->poll());
  CHECK(c->sendAcknowledgeAnnouncement(71,9)==0);
  p.publishInterruption(3,72,10,1,1,m::LoadRequestStatus::Pending,m::SessionPhase::Saving);REQUIRE(c->poll());
  CHECK(c->sendAcknowledgeAnnouncement(72,10)==0);
  p.publish(4,m::SessionPhase::Menu);REQUIRE(c->poll());
  CHECK(c->state().fortressEpoch==0);CHECK(c->state().interruption.receipt==0);
  CHECK(c->state().interruption.kind==wm::InterruptionKind::None);
  CHECK(c->sendAcknowledgeAnnouncement(72,10)==0);
}
TEST_CASE("interruption validators reject forged availability and ambiguous acknowledgement payloads") {
  for(int which=0;which<6;++which){
    flatbuffers::FlatBufferBuilder b;
    auto command=m::CreateSessionCommand(b,m::kSessionVersion,1,
      which==3?b.CreateString("unexpected-path"):0,
      which==5?m::SessionAction::SaveReturn:m::SessionAction::AcknowledgeAnnouncement,
      which==4?b.CreateString("unexpected-name"):0,
      which==0?0:71,which==1?0:which==2?(uint64_t(1)<<63):9);
    b.Finish(command);CHECK(m::validateSessionCommand(*flatbuffers::GetRoot<m::SessionCommand>(b.GetBufferPointer())).has_value());
  }
  for(int which=0;which<6;++which){
    flatbuffers::FlatBufferBuilder b;
    auto notice=m::CreateInterruptionState(b,which==0?m::InterruptionKind::Diplomacy:m::InterruptionKind::PassiveAnnouncement,
      which==1?0:9,b.CreateString(which==4?std::string(32769,'x'):"Notice"),b.CreateString(""),which==2?0:1,true);
    m::SessionStateBuilder s(b);s.add_schema_version(m::kSessionVersion);s.add_revision(1);
    s.add_phase(which==5?m::SessionPhase::Saving:m::SessionPhase::Ready);s.add_fortress_valid(true);
    s.add_fortress_epoch(which==3?0:71);s.add_interruption(notice);b.Finish(s.Finish());
    CHECK(m::validateSessionState(*flatbuffers::GetRoot<m::SessionState>(b.GetBufferPointer())).has_value());
  }
}

namespace {
flatbuffers::Offset<m::AgreementInfo> petitionAgreement(flatbuffers::FlatBufferBuilder& b,int32_t id=0,bool badParty=false,int invalidRecord=0) {
  auto party=m::CreateAgreementParty(b,badParty?-2:0,b.CreateVector(std::vector<int32_t>{0}),b.CreateVector(std::vector<int32_t>{}),b.CreateString("Native guild"));
  auto government=m::CreateAgreementParty(b,1,b.CreateVector(std::vector<int32_t>{483}),b.CreateVector(std::vector<int32_t>{}),b.CreateString("Fortress government"));
  auto parties=b.CreateVector(std::vector<flatbuffers::Offset<m::AgreementParty>>{party,government});
  auto description=b.CreateString("Guildhall for fishery workers");
  m::AgreementDetailBuilder d(b);d.add_id(0);d.add_kind(12);d.add_site_id(378);d.add_year(104);d.add_year_tick(168260);
  d.add_applicant_party(0);d.add_government_party(1);d.add_location_type(11);d.add_tier(1);d.add_profession(37);d.add_description(description);
  if(invalidRecord==3)d.add_deity_type(-2);
  if(invalidRecord==4)d.add_deity_id(-2);
  auto details=b.CreateVector(std::vector<flatbuffers::Offset<m::AgreementDetail>>{d.Finish()});
  auto summary=b.CreateString("Native guildhall request"),reason=b.CreateString("");
  m::AgreementInfoBuilder a(b);a.add_id(id);a.add_status(invalidRecord==1?m::AgreementStatus::Accepted:m::AgreementStatus::Pending);a.add_not_approved(true);
  a.add_complete(invalidRecord!=2);a.add_parties(parties);a.add_details(details);a.add_summary(summary);a.add_reason(reason);return a.Finish();
}
}
TEST_CASE("petition commands preserve ID zero and separate review response and close receipts") {
  auto invalid=[](m::SessionAction action,int32_t id,uint64_t epoch,uint64_t receipt,uint64_t notice=0,bool path=false,bool checkpoint=false){
    flatbuffers::FlatBufferBuilder b;
    auto a=path?b.CreateString("unexpected-path"):flatbuffers::Offset<flatbuffers::String>{};
    auto n=checkpoint?b.CreateString("unexpected-name"):flatbuffers::Offset<flatbuffers::String>{};
    m::SessionCommandBuilder c(b);c.add_schema_version(m::kSessionVersion);c.add_client_id(1);c.add_seq(1);c.add_action(action);
    c.add_petition_id(id);c.add_fortress_epoch(epoch);c.add_petition_receipt(receipt);c.add_interruption_receipt(notice);
    if(path)c.add_save_id(a);
    if(checkpoint)c.add_checkpoint_name(n);
    b.Finish(c.Finish());
    return m::validateSessionCommand(*flatbuffers::GetRoot<m::SessionCommand>(b.GetBufferPointer())).has_value();
  };
  CHECK_FALSE(invalid(m::SessionAction::ReviewPetition,0,71,0));
  CHECK_FALSE(invalid(m::SessionAction::ApprovePetition,0,71,9));
  CHECK_FALSE(invalid(m::SessionAction::DenyPetition,0,71,9));
  CHECK_FALSE(invalid(m::SessionAction::ClosePetition,-1,71,10));
  CHECK_FALSE(invalid(m::SessionAction::ClosePetition,0,71,9));
  CHECK(invalid(m::SessionAction::ReviewPetition,-1,71,0));
  CHECK(invalid(m::SessionAction::ReviewPetition,0,0,0));
  CHECK(invalid(m::SessionAction::ReviewPetition,0,71,9));
  CHECK(invalid(m::SessionAction::ApprovePetition,0,71,0));
  CHECK(invalid(m::SessionAction::ApprovePetition,0,71,uint64_t(1)<<63));
  CHECK(invalid(m::SessionAction::DenyPetition,-1,71,9));
  CHECK(invalid(m::SessionAction::ClosePetition,-2,71,9));
  CHECK(invalid(m::SessionAction::ClosePetition,-1,71,0));
  CHECK(invalid(m::SessionAction::ApprovePetition,0,71,9,8));
  CHECK(invalid(m::SessionAction::ApprovePetition,0,71,9,0,true));
  CHECK(invalid(m::SessionAction::ReviewPetition,0,71,0,0,false,true));
  CHECK(invalid(m::SessionAction::SaveReturn,0,0,0));
  CHECK(invalid(m::SessionAction::AcknowledgeAnnouncement,-1,71,9,8));
}
TEST_CASE("petition review validates nested identity and bounded actionable state") {
  for(int which=-2;which<14;++which){
    flatbuffers::FlatBufferBuilder b;
    const bool emptyClose=which==-2;
    auto agreement=emptyClose||which==0||which==9?flatbuffers::Offset<m::AgreementInfo>{}:petitionAgreement(b,which==1?1:0,which==6,which>=10?which-9:0);
    auto reason=b.CreateString(which==7?std::string(2049,'x'):"");
    m::PetitionReviewStateBuilder p(b);p.add_id(emptyClose?-1:0);p.add_receipt(which==2||which==10||which==11?0:9);
    p.add_can_review(which==10||which==11);p.add_can_respond(!emptyClose&&which!=9&&which!=10&&which!=11);p.add_can_close(which!=10&&which!=11);p.add_agreement(agreement);p.add_reason(reason);
    p.add_guildhall_value(which==8?-1:2000);p.add_grand_guildhall_value(10000);auto petition=p.Finish();
    m::SessionStateBuilder state(b);state.add_schema_version(m::kSessionVersion);state.add_revision(1);
    state.add_phase(which==4?m::SessionPhase::Saving:m::SessionPhase::Ready);state.add_fortress_valid(which!=5);
    state.add_fortress_epoch(which==3||which==5?0:71);state.add_paused(true);state.add_petition(petition);b.Finish(state.Finish());
    CHECK(m::validateSessionState(*flatbuffers::GetRoot<m::SessionState>(b.GetBufferPointer())).has_value()==(which>=0));
  }
}

TEST_CASE("petition transport retains exact review identity and consumes pending ownership across reconnect") {
  Publisher p;
  auto publish=[&](uint64_t rev,uint64_t epoch,int32_t id,uint64_t receipt,bool review,bool respond,bool close,
                   uint64_t seq=0,m::SessionAction action=m::SessionAction::LoadFortress){
    flatbuffers::FlatBufferBuilder b;
    auto agreement=id<0?flatbuffers::Offset<m::AgreementInfo>{}:petitionAgreement(b,id);
    auto reason=b.CreateString("");m::PetitionReviewStateBuilder petition(b);
    petition.add_id(id);petition.add_receipt(receipt);petition.add_can_review(review);petition.add_can_respond(respond);
    petition.add_can_close(close);petition.add_reason(reason);petition.add_agreement(agreement);
    petition.add_guildhall_value(2500);petition.add_grand_guildhall_value(12000);auto data=petition.Finish();
    m::SessionStateBuilder state(b);state.add_schema_version(m::kSessionVersion);state.add_revision(rev);
    state.add_phase(m::SessionPhase::Ready);state.add_fortress_valid(true);state.add_paused(true);state.add_fortress_epoch(epoch);
    state.add_request_client_id(p.lastClient);state.add_request_seq(seq);state.add_request_status(seq?m::LoadRequestStatus::Ok:m::LoadRequestStatus::None);
    state.add_request_action(action);state.add_petition(data);b.Finish(state.Finish());
    REQUIRE_FALSE(m::validateSessionState(*flatbuffers::GetRoot<m::SessionState>(b.GetBufferPointer())).has_value());
    REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));
  };
  auto pop=[&](uint64_t seq,m::SessionAction action,int32_t id,uint64_t receipt){
    uint8_t bytes[4096];auto size=p.pop(bytes,sizeof(bytes));REQUIRE(size>0);
    flatbuffers::Verifier verifier(bytes,size);REQUIRE(verifier.VerifyBuffer<m::SessionCommand>(nullptr));
    const auto* wire=flatbuffers::GetRoot<m::SessionCommand>(bytes);CHECK(wire->seq()==seq);CHECK(wire->action()==action);
    CHECK(wire->petition_id()==id);CHECK(wire->petition_receipt()==receipt);CHECK(wire->interruption_receipt()==0);
    REQUIRE_FALSE(m::validateSessionCommand(*wire).has_value());
  };
  publish(1,71,0,0,true,false,false);
  std::string error;auto c=wm::SessionClient::open(error,p.name);REQUIRE(c);REQUIRE(c->poll());
  const auto& initial=c->state().petition;CHECK(initial.id==0);CHECK(initial.hasAgreement);CHECK(initial.canReview);
  CHECK(initial.guildhallValue==2500);CHECK(initial.grandGuildhallValue==12000);
  REQUIRE(initial.agreement.details.size()==1);CHECK(initial.agreement.details[0].profession==37);
  REQUIRE(initial.agreement.parties.size()==2);CHECK(initial.agreement.parties[0].entityIds==std::vector<int32_t>{0});
  CHECK(c->sendReviewPetition(70,0)==0);CHECK(c->sendReviewPetition(71,1)==0);
  auto seq=c->sendReviewPetition(71,0);REQUIRE(seq==1);pop(seq,m::SessionAction::ReviewPetition,0,0);
  CHECK(c->sendReviewPetition(71,0)==0);
  publish(2,71,0,0,true,false,false);REQUIRE(c->poll());
  CHECK(c->state().requestStatus==wm::LoadRequestStatus::Pending);CHECK(c->sendReviewPetition(71,0)==0);
  publish(3,71,0,9,false,true,true,seq,m::SessionAction::ReviewPetition);REQUIRE(c->poll());
  CHECK(c->state().petition.canRespond);CHECK(c->state().petition.receipt==9);
  CHECK(c->sendPetitionResponse(71,1,9,true)==0);CHECK(c->sendPetitionResponse(70,0,9,true)==0);
  CHECK(c->sendPetitionResponse(71,0,8,true)==0);
  seq=c->sendClosePetition(71,0,9);REQUIRE(seq==2);pop(seq,m::SessionAction::ClosePetition,0,9);
  CHECK(c->sendPetitionResponse(71,0,9,false)==0);
  publish(4,71,0,0,true,false,false,seq,m::SessionAction::ClosePetition);REQUIRE(c->poll());
  CHECK(c->sendPetitionResponse(71,0,9,true)==0);
  seq=c->sendReviewPetition(71,0);REQUIRE(seq==3);pop(seq,m::SessionAction::ReviewPetition,0,0);
  publish(5,71,0,10,false,true,true,seq,m::SessionAction::ReviewPetition);REQUIRE(c->poll());
  CHECK(c->sendClosePetition(71,0,9)==0);
  seq=c->sendPetitionResponse(71,0,10,true);REQUIRE(seq==4);pop(seq,m::SessionAction::ApprovePetition,0,10);
  publish(6,71,-1,11,false,false,true,seq,m::SessionAction::ApprovePetition);REQUIRE(c->poll());
  CHECK_FALSE(c->state().petition.hasAgreement);CHECK(c->state().petition.agreement.details.empty());
  auto reconnect=wm::SessionClient::open(error,p.name);REQUIRE(reconnect);REQUIRE(reconnect->poll());
  CHECK(reconnect->sendPetitionResponse(71,0,10,false)==0);CHECK(reconnect->sendClosePetition(71,0,11)==0);
  seq=reconnect->sendClosePetition(71,-1,11);REQUIRE(seq==1);pop(seq,m::SessionAction::ClosePetition,-1,11);
  publish(7,72,0,0,true,false,false,seq,m::SessionAction::ClosePetition);REQUIRE(reconnect->poll());
  CHECK(reconnect->sendReviewPetition(71,0)==0);CHECK(reconnect->sendClosePetition(71,-1,11)==0);
  sh::atomicStoreRelease(&m::sessionOwner(p.r)->pid,0);REQUIRE(reconnect->poll());
  CHECK_FALSE(reconnect->state().petition.hasAgreement);CHECK_FALSE(reconnect->state().petition.canReview);
  CHECK(reconnect->sendReviewPetition(72,0)==0);
}

TEST_CASE("fortress resource statistics reject invalid counts and clear stale data") {
  Publisher p;
  auto publish=[&](uint64_t rev,uint64_t epoch,bool available,std::vector<int32_t> counts,bool loaded=true) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<uint32_t> stress(7);
    auto summary=m::CreateFortressSummary(b,177,b.CreateVector(stress),false,-129,256,
      counts.empty()?0:b.CreateVector(counts),available);
    m::SessionStateBuilder state(b);state.add_schema_version(m::kSessionVersion);state.add_revision(rev);
    state.add_phase(loaded?m::SessionPhase::Ready:m::SessionPhase::Menu);
    state.add_fortress_valid(loaded);state.add_fortress_epoch(loaded?epoch:0);
    if(loaded)state.add_fortress_summary(summary);
    b.Finish(state.Finish());
    auto bad=m::validateSessionState(*flatbuffers::GetRoot<m::SessionState>(b.GetBufferPointer()));
    if(bad)return false;
    REQUIRE(sh::publishSnapshot(p.r,b.GetBufferPointer(),b.GetSize(),0));return true;
  };
  CHECK_FALSE(publish(1,71,true,{}));
  CHECK_FALSE(publish(1,71,true,{1,2,3,4,5,6}));
  CHECK_FALSE(publish(1,71,true,{1,2,3,4,5,6,7,8}));
  CHECK_FALSE(publish(1,71,true,{1,2,3,-1,5,6,7}));
  CHECK_FALSE(publish(1,71,false,{0,0,0,0,0,0,0}));
  REQUIRE(publish(1,71,true,{852,135,310,206,14,453,247}));
  std::string error;auto c=wm::SessionClient::open(error,p.name);REQUIRE(c);REQUIRE(c->poll());
  CHECK(c->state().fortressSummary.resourcesAvailable);
  CHECK(c->state().fortressSummary.resourceCounts==std::vector<int32_t>{852,135,310,206,14,453,247});
  REQUIRE(publish(2,71,true,{0,INT32_MAX,0,0,0,0,0}));REQUIRE(c->poll());
  CHECK(c->state().fortressSummary.resourceCounts[1]==INT32_MAX);
  REQUIRE(publish(3,72,false,{}));REQUIRE(c->poll());
  CHECK_FALSE(c->state().fortressSummary.resourcesAvailable);CHECK(c->state().fortressSummary.resourceCounts.empty());
  REQUIRE(publish(4,72,true,{1,2,3,4,5,6,7}));REQUIRE(c->poll());
  REQUIRE(publish(5,0,false,{},false));REQUIRE(c->poll());
  CHECK_FALSE(c->state().fortressSummary.resourcesAvailable);CHECK(c->state().fortressSummary.resourceCounts.empty());
  REQUIRE(publish(6,73,true,{1,2,3,4,5,6,7}));REQUIRE(c->poll());
  sh::atomicStoreRelease(&m::sessionOwner(p.r)->pid,0);REQUIRE(c->poll());
  CHECK_FALSE(c->state().fortressSummary.resourcesAvailable);CHECK(c->state().fortressSummary.resourceCounts.empty());
}

TEST_CASE("fortress summary validates and clears across epochs and unload") {
  Publisher p;
  auto publish=[&](uint64_t revision,uint64_t epoch,int32_t offset,bool loaded,bool withSummary,int invalid=-1) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<uint32_t> bins{8,8,21,38,27,18,57};
    if(invalid==0)bins.pop_back();
    if(invalid==1)bins[0]=100001;
    auto summary=m::CreateFortressSummary(b,invalid==2?-1:177,b.CreateVector(bins),invalid!=3,
      invalid==4?65537:offset,invalid==5?0:256);
    m::SessionStateBuilder s(b);s.add_schema_version(m::kSessionVersion);s.add_revision(revision);
    s.add_phase(loaded?m::SessionPhase::Ready:m::SessionPhase::Menu);s.add_fortress_valid(loaded);
    s.add_fortress_epoch(epoch);if(withSummary)s.add_fortress_summary(summary);
    b.Finish(s.Finish());
    bool bad=m::validateSessionState(*flatbuffers::GetRoot<m::SessionState>(b.GetBufferPointer())).has_value();
    if(invalid>=0 || (withSummary && (!loaded || !epoch))) {CHECK(bad);return;}
    REQUIRE_FALSE(bad);REQUIRE(sh::publishSnapshot(p.r,b.GetBufferPointer(),b.GetSize(),0));
  };
  for(int invalid=0;invalid<6;++invalid)publish(1,71,-129,true,true,invalid);
  publish(1,0,0,false,true);publish(1,0,0,true,true);
  publish(1,71,-129,true,true);
  std::string error;auto c=wm::SessionClient::open(error,p.name);REQUIRE(c);REQUIRE(c->poll());
  CHECK(c->state().fortressSummary.available);CHECK(c->state().fortressSummary.population==177);
  CHECK(c->state().fortressSummary.stressCounts==std::vector<uint32_t>{8,8,21,38,27,18,57});
  CHECK(143+c->state().fortressSummary.elevationOffset==14);
  CHECK(c->state().fortressSummary.levelCount==256);
  publish(2,72,-20,true,true);REQUIRE(c->poll());CHECK(c->state().fortressSummary.elevationOffset==-20);
  publish(3,0,0,false,false);REQUIRE(c->poll());CHECK_FALSE(c->state().fortressSummary.available);
  CHECK(c->state().fortressSummary.stressCounts.empty());
  publish(4,73,-9,true,false);REQUIRE(c->poll());CHECK_FALSE(c->state().fortressSummary.available);
  sh::atomicStoreRelease(&m::sessionOwner(p.r)->pid,0);REQUIRE(c->poll());CHECK_FALSE(c->state().fortressSummary.available);
}
TEST_CASE("active notification groups validate and replace without simulation ticks") {
  Publisher p;std::string error;
  auto publish=[&](uint64_t revision,uint64_t epoch,bool loaded,int bad=-1) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<int32_t> ids{0,42};
    if(bad==0)ids[0]=-1;
    if(bad==1)ids.resize(257,1);
    auto unit=m::CreateUnitReportReference(b,bad==2?-1:17,bad==3?static_cast<m::UnitReportCategory>(9):m::UnitReportCategory::Hunting);
    std::vector<flatbuffers::Offset<m::UnitReportReference>> units{unit};
    auto group=m::CreateActiveNotificationGroup(b,bad==4?static_cast<m::NotificationCategory>(99):m::NotificationCategory::Weather,
      b.CreateVector(ids),bad==5?1:uint32_t(ids.size()),b.CreateVector(units),bad==6?2:1,bad!=7);
    std::vector<flatbuffers::Offset<m::ActiveNotificationGroup>> groups;
    if(loaded || bad==8)groups.push_back(group);
    if(bad==9)groups.resize(65,group);
    auto vector=b.CreateVector(groups);
    m::SessionStateBuilder state(b);state.add_schema_version(m::kSessionVersion);state.add_revision(revision);
    state.add_phase(loaded?m::SessionPhase::Ready:m::SessionPhase::Menu);state.add_fortress_valid(loaded);state.add_fortress_epoch(epoch);
    state.add_active_notifications(vector);b.Finish(state.Finish());
    const auto invalid=m::validateSessionState(*flatbuffers::GetRoot<m::SessionState>(b.GetBufferPointer()));
    CHECK(invalid.has_value()==(bad>=0 && bad!=7));
    if(!invalid)REQUIRE(sh::publishSnapshot(p.r,b.GetBufferPointer(),b.GetSize(),0));
  };
  for(int bad=0;bad<10;++bad)publish(1,bad==8?0:50,bad!=8,bad);
  publish(1,50,true);auto c=wm::SessionClient::open(error,p.name);REQUIRE(c);REQUIRE(c->poll());
  REQUIRE(c->state().activeNotifications.size()==1);
  const auto& group=c->state().activeNotifications[0];
  CHECK(group.category==wm::NotificationCategory::Weather);CHECK(group.reportIds==std::vector<int32_t>({0,42}));
  REQUIRE(group.unitReports.size()==1);CHECK(group.unitReports[0].unitId==17);CHECK(group.unitReports[0].category==wm::UnitReportCategory::Hunting);
  publish(2,0,false);REQUIRE(c->poll());CHECK(c->state().activeNotifications.empty());
  publish(3,51,true);REQUIRE(c->poll());CHECK(c->state().activeNotifications.size()==1);CHECK(c->state().fortressEpoch==51);
  sh::atomicStoreRelease(&m::sessionOwner(p.r)->pid,0);REQUIRE(c->poll());CHECK(c->state().activeNotifications.empty());
}
TEST_CASE("global pause remains observable without granting fortress capabilities") {
  Publisher p;
  auto publish=[&](uint64_t revision,bool paused) {
    flatbuffers::FlatBufferBuilder b;
    m::SessionStateBuilder state(b);
    state.add_schema_version(m::kSessionVersion);state.add_revision(revision);
    state.add_phase(m::SessionPhase::Unavailable);state.add_paused(paused);
    state.add_fortress_valid(false);state.add_fortress_epoch(0);
    b.Finish(state.Finish());
    REQUIRE_FALSE(m::validateSessionState(*flatbuffers::GetRoot<m::SessionState>(b.GetBufferPointer())).has_value());
    REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));
  };
  publish(1,true);
  std::string error;auto client=wm::SessionClient::open(error,p.name);REQUIRE(client);REQUIRE(client->poll());
  CHECK(client->state().paused);CHECK_FALSE(client->state().fortressValid);
  CHECK(client->state().fortressEpoch==0);CHECK_FALSE(client->state().canSave);
  publish(2,false);REQUIRE(client->poll());CHECK_FALSE(client->state().paused);
  CHECK_FALSE(client->state().fortressValid);CHECK(client->sendSave(false,"Checkpoint")==0);
}

TEST_CASE("session transport rejects replaced producer identity before sending") {
  Publisher p; p.publish(1,m::SessionPhase::Menu);
  std::string error; auto c=wm::SessionClient::open(error,p.name);
  REQUIRE(c); REQUIRE(c->poll());
  auto* owner=m::sessionOwner(p.r);
  SUBCASE("process id") { sh::atomicStoreRelease(&owner->pid,GetCurrentProcessId()+1); }
  SUBCASE("creation time") { sh::atomicStoreRelease(&owner->created,1); }
  SUBCASE("generation") { sh::atomicStoreRelease(&owner->generation,99); }
  CHECK(c->sendLoadSave("save-a")==0);
  uint8_t bytes[4096]; CHECK(sh::popCommand(p.r,bytes,sizeof(bytes))==0);
  REQUIRE(c->poll()); CHECK(c->state().phase==wm::SessionPhase::Unavailable);
}
#endif
