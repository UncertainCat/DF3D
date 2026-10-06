#pragma once
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include "wm/management_client.h"
namespace wm {
enum class SessionPhase : uint8_t { Starting, Menu, Loading, Ready, Unavailable, Error, Saving, Unloading };
enum class SessionAction : uint8_t { LoadFortress, SaveContinue, SaveReturn, AcknowledgeAnnouncement, ReviewPetition, ApprovePetition, DenyPetition, ClosePetition, ReadSaveDestinations, QuitWithoutSaving };
enum class SaveReturnMode : uint8_t { None, ExistingDestination, NewFolder, NewTimeline };
struct SaveDestination { std::string id, folder; };
struct SaveDestinationCatalog {
  uint64_t receipt=0, fortressEpoch=0;
  std::vector<SaveDestination> destinations;
};
struct PetitionReviewState {int32_t id=-1,guildhallValue=0,grandGuildhallValue=0;uint64_t receipt=0;bool canReview=false,canRespond=false,canClose=false,hasAgreement=false;std::string reason;AgreementInfo agreement;};
enum class InterruptionKind : uint8_t { None, ManualPause, PassiveAnnouncement, AnnouncementViewer, Diplomacy, Petition, Trade, OtherDecision };
struct InterruptionState { InterruptionKind kind=InterruptionKind::None; uint64_t receipt=0; std::string text,reason; uint32_t popupCount=0; bool canAcknowledge=false; };
enum class LoadRequestStatus : uint8_t { None, Pending, Ok, Rejected, UnknownOutcome };
struct FortressSave { std::string id, fortName, worldName; int32_t year = 0; };
struct FortressSummary {
  bool available=false, stressAvailable=false, resourcesAvailable=false;
  int32_t population=0,elevationOffset=0;
  uint32_t levelCount=0;
  std::vector<uint32_t> stressCounts;
  // Total food, drink, seeds, meat, fish, plant, other; native cached totals.
  std::vector<int32_t> resourceCounts;
  int32_t bookkeeperPrecision=-1;
};
enum class NotificationCategory : uint8_t { General, EraChange, Underground, Migrant, Monster, Ambush, Trade, Noble, Animal, Birth, Mood, LaborChange, Military, Marriage, Berserk, MartialTrance, LoseEmotion, Stress, ArtDefacement, Masterpiece, JobFailed, Death, Ghost, UndeadAttack, Weather, Vermin, CuriousGuzzler, ResearchBreakthrough, GuestArrival, Holdings, Rumor, Agreement, Crime, DeityCurse, Combat, Sparring, Hunting };
inline const char* notificationCategoryName(NotificationCategory category) {
  static constexpr const char* names[]={"General","EraChange","Underground","Migrant","Monster","Ambush","Trade","Noble","Animal","Birth","Mood","LaborChange","Military","Marriage","Berserk","MartialTrance","LoseEmotion","Stress","ArtDefacement","Masterpiece","JobFailed","Death","Ghost","UndeadAttack","Weather","Vermin","CuriousGuzzler","ResearchBreakthrough","GuestArrival","Holdings","Rumor","Agreement","Crime","DeityCurse","Combat","Sparring","Hunting"};
  return uint8_t(category)<37?names[uint8_t(category)]:"Unknown";
}
enum class UnitReportCategory : uint8_t { Combat, Sparring, Hunting };
struct UnitReportReference { int32_t unitId=0; UnitReportCategory category=UnitReportCategory::Combat; };
struct ActiveNotificationGroup { NotificationCategory category=NotificationCategory::General; std::vector<int32_t> reportIds; uint32_t reportCount=0,unitReportCount=0; std::vector<UnitReportReference> unitReports; bool complete=true; };
struct SessionState {
  uint64_t revision = 0;
  SessionPhase phase = SessionPhase::Starting;
  std::vector<FortressSave> saves;
  std::string activeSaveId;
  std::string savedSaveId;
  uint64_t requestSeq = 0;
  LoadRequestStatus requestStatus = LoadRequestStatus::None;
  std::string message;
  SessionAction requestAction = SessionAction::LoadFortress;
  bool fortressValid = false, paused = false, canSave = false, canSaveReturn = false;
  int32_t year = 0, yearTick = 0;
  std::string fortName, fortOriginalName;
  int16_t fortressRank = -1;
  bool fortressCapital = false;
  int8_t moonPhase = -1;
  uint64_t fortressEpoch=0;
  uint64_t requestFortressEpoch=0;
  SaveDestinationCatalog saveDestinations;
  InterruptionState interruption;
  PetitionReviewState petition;
  FortressSummary fortressSummary;
  std::vector<ActiveNotificationGroup> activeNotifications;
  bool activeNotificationsComplete=true;
  std::vector<int32_t> alertButtonReportIds; uint32_t alertButtonReportCount=0; bool alertButtonComplete=true;
};
// Process-lifetime semantic channel; independent of a loaded map and simulation ticks.
// Each connection has one outstanding request and a private durable receipt.
// Other clients cannot replace it. Reconnect starts a new identity (no replay).
// Global session state remains shared. poll() must run before choosing a save.
class SessionClient {
 public:
  static std::unique_ptr<SessionClient> open(std::string& error, const std::string& regionName = {});
  ~SessionClient();
  bool poll();
  const SessionState& state() const { return state_; }
  uint64_t sendLoadSave(const std::string& id);
  uint64_t sendSave(bool returnToMenu = false, const std::string& checkpointName = {});
  uint64_t sendReadSaveDestinations(uint64_t fortressEpoch);
  uint64_t sendQuitWithoutSaving(uint64_t fortressEpoch);
  uint64_t sendSaveReturn(uint64_t fortressEpoch, uint64_t catalogReceipt, SaveReturnMode mode,
                          const std::string& destinationId={}, const std::vector<uint8_t>& timelineName={});
  uint64_t sendAcknowledgeAnnouncement(uint64_t fortressEpoch, uint64_t receipt);
  uint64_t sendReviewPetition(uint64_t fortressEpoch,int32_t id);
  uint64_t sendPetitionResponse(uint64_t fortressEpoch,int32_t id,uint64_t receipt,bool approve);
  uint64_t sendClosePetition(uint64_t fortressEpoch,int32_t id,uint64_t receipt);
  const std::string& lastError() const { return error_; }
 private:
  SessionClient();
  uint64_t send(SessionAction action, const std::string& id = {}, const std::string& checkpointName = {}, uint64_t fortressEpoch=0, uint64_t receipt=0,int32_t petitionId=-1,uint64_t petitionReceipt=0,
                uint64_t catalogReceipt=0, SaveReturnMode mode=SaveReturnMode::None,
                const std::string& destinationId={}, const std::vector<uint8_t>& timelineName={});
  struct Impl;
  std::unique_ptr<Impl> impl_;
  SessionState state_;
  std::string error_;
  uint64_t seq_ = 0;
  uint64_t pendingSeq_ = 0;
};
}
