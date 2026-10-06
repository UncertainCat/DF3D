// Global session lifecycle retains the verified native menu initialization.
// Load/save are documented global exceptions; ordinary panels never use them.
#include "session.h"
#include "session_load_policy.h"
#include "session_save_file.h"
#include "interruption.h"
#include "petition.h"
#include "fortress_population.h"
#include "notification_groups.h"
#include "df/announcement_alertst.h"
#include "df/popup_message.h"
#include "Core.h"
#include "modules/Gui.h"
#include "modules/Screen.h"
#include "modules/World.h"
#include "modules/Units.h"
#include "modules/Translation.h"
#include <array>
#include "df/plotinfost.h"
#include "df/world_site.h"
#include "df/gamest.h"
#include "df/viewscreen_dwarfmodest.h"
#include "df/viewscreen_savegamest.h"
#include "df/viewscreen_titlest.h"
#include "df/viewscreen_loadgamest.h"
#include "df/savegame_headerst.h"
#include "df/graphic.h"
#include "df/enabler.h"
#include "df/world.h"
#include "df/world_data.h"
#include "df/global_objects.h"
#include "session_util.h"
#include "shm_layout.h"
#include <chrono>
#include <filesystem>
#include <algorithm>
#include <set>
// Same Windows prelude as df3d.cpp. The shared-memory transport (named
// kernel objects) has no POSIX path yet; say so instead of failing on HANDLE.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifdef _WIN32
#include <windows.h>
#else
#error "df3d session channel: shared memory transport is Windows-only"
#endif
#include "client_mailbox.h"
namespace df3d_session {
// Saver stage and changed in-memory identity alone can report a false success
// when initialization skipped the compressor. A new checkpoint also needs an
// actual nonempty world file. The live lane additionally reloads the result.
static bool hasSavedWorld(const std::filesystem::path& directory) {
    return savedWorldStamp(directory).has_value();
}

namespace m = df3d::mirror;
namespace sh = df3d::shm;
using namespace DFHack;
namespace {
HANDLE mapping = nullptr;
sh::RegionHeader* region = nullptr;
uint64_t revision = 0, requestSeq = 0, requestClient = 0;
std::unique_ptr<sh::ClientMailbox> reply;
m::SessionPhase phase = m::SessionPhase::Starting;
m::LoadRequestStatus status = m::LoadRequestStatus::None;
m::SessionAction action = m::SessionAction::LoadFortress;
bool fortressValid = false, paused = false, canSave = false, canSaveReturn = false;
uint64_t fortressEpoch=0, pendingSaveEpoch=0;
uint64_t requestEpoch=0, catalogCounter=0, catalogReceipt=0, catalogEpoch=0, catalogClient=0;
std::vector<std::string> catalogFolders;
std::string destinationId(size_t index) { return std::to_string(catalogReceipt)+":"+std::to_string(index); }
m::SaveReturnMode returnMode=m::SaveReturnMode::None;
std::string timelineName, pendingTimeline;
InterruptionInfo interruption;
PetitionInfo petition;
NotificationGroups notificationGroups;
AlertButtonReports alertButtonReports;
int32_t year = 0, yearTick = 0;
std::string fortName, fortOriginalName;
int16_t fortressRank=-1;
bool fortressCapital=false;
int8_t moonPhase=-1;
bool summaryAvailable=false, stressAvailable=false, resourcesAvailable=false;
int32_t population=0,elevationOffset=0;
uint32_t levelCount=0;
std::array<uint32_t,7> stressCounts{};
std::array<int32_t,7> resourceCounts{};
int32_t bookkeeperPrecision=-1;
uint64_t summaryEpoch=0;
std::chrono::steady_clock::time_point lastHeader;
void refreshPopulation() {
  // DFHack's living, active fortress census includes residents and insane
  // citizens. Read current semantics instead of the native HUD's cached text.
  const auto census=fortressPopulation(
      Units::citizensRange(df::global::world->units.active, false, true),
      [](df::unit* unit) { return Units::getStressCategory(unit); });
  stressAvailable=census.has_value();
  population=census ? census->population : 0;
  stressCounts=census ? census->stress : std::array<uint32_t,7>{};
}
std::string summaryKey() {
  std::string key=std::to_string(summaryAvailable)+":"+std::to_string(population)+":"+std::to_string(elevationOffset)+":"+std::to_string(levelCount)+":"+std::to_string(stressAvailable);
  for(auto value:stressCounts)key+=":"+std::to_string(value);
  key+=":"+std::to_string(resourcesAvailable);
  key+=":"+std::to_string(bookkeeperPrecision);
  for(auto value:resourceCounts)key+=":"+std::to_string(value);
  return key;
}
std::string checkpointName;
bool saveSawProgress = false;
bool saveIssued = false;
bool quitIssued = false;
std::string pendingExistingPath;
std::optional<SavedWorldStamp> existingWorldBefore;
std::set<std::string> previousSaveIds;
std::set<std::string> observedSaveIds;
bool cleanupRequested = false;
bool cleanupQuitConfirmation = false;
int cleanupFrames = 0;
std::chrono::steady_clock::time_point lastStatus;
std::string message, activeId, pendingId, pendingFilename, savedId;
uint32_t pendingWorld1 = 0, pendingWorld2 = 0;
std::string lastPublished;
uint64_t saveRevision = 0;
std::chrono::steady_clock::time_point lastDiscovery;
struct Save { std::string id, fort, world; int32_t year; };
std::vector<Save> saves;
std::chrono::steady_clock::time_point requestedAt;
int navigationStage = 0;
std::string idOf(df::savegame_headerst* h) { return h->full_path.generic_string(); }
std::string lowerAscii(std::string value) {
  for (char& c : value) if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
  return value;
}
bool checkpointExists(const std::string& name) {
  const auto target = lowerAscii(name);
  for (const auto& id : observedSaveIds)
    if (lowerAscii(std::filesystem::path(id).filename().string()) == target) return true;
  for (const auto& save : saves)
    if (lowerAscii(std::filesystem::path(save.id).filename().string()) == target) return true;
  return false;
}
bool isFort(df::savegame_headerst* h) { return h && h->gametype == df::game_type::DWARF_MAIN; }
void reject(const std::string& reason) {
  const bool uncertain=(saveIssued && (action==m::SessionAction::SaveContinue || action==m::SessionAction::SaveReturn)) || (quitIssued && action==m::SessionAction::QuitWithoutSaving);
  if ((action == m::SessionAction::SaveContinue || action == m::SessionAction::SaveReturn || action==m::SessionAction::ReadSaveDestinations || action==m::SessionAction::QuitWithoutSaving) && navigationStage > 0 && !uncertain) {
    cleanupRequested = true; cleanupFrames = 0;cleanupQuitConfirmation=action==m::SessionAction::QuitWithoutSaving;
  }
  status = uncertain?m::LoadRequestStatus::UnknownOutcome:m::LoadRequestStatus::Rejected;
  message = reason; pendingId.clear(); navigationStage = 0;
}
void publish(bool broadcast=true) {
  const std::string key = std::to_string(int(phase)) + ":" + std::to_string(int(status)) + ":" +
      std::to_string(requestSeq) + ":" + std::to_string(saveRevision) + ":" + activeId + ":" + message + ":" +
      std::to_string(int(action)) + ":" + std::to_string(fortressValid) + ":" + std::to_string(paused) + ":" +
      std::to_string(year) + ":" + std::to_string(yearTick) + ":" + fortName + ":" + fortOriginalName + ":" +
      std::to_string(fortressRank) + ":" + std::to_string(fortressCapital) + ":" + std::to_string(moonPhase) + ":" +
      std::to_string(canSave) + ":" + std::to_string(canSaveReturn) + ":" + savedId + ":" + std::to_string(fortressEpoch) + ":" + std::to_string(interruption.kind) + ":" + std::to_string(interruption.receipt) + ":" + interruption.text + ":" + interruption.reason + ":" + std::to_string(interruption.popupCount) + ":" + std::to_string(interruption.canAcknowledge) + ":" + std::to_string(petition.revision);
  if (broadcast && key + summaryKey() + notificationGroups.key + alertButtonReports.key + ":" + std::to_string(requestClient) == lastPublished) return;
  if(broadcast)lastPublished = key + summaryKey() + notificationGroups.key + alertButtonReports.key + ":" + std::to_string(requestClient);
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<m::FortressSave>> ss;
  for (const auto& s : saves) ss.push_back(m::CreateFortressSave(b, b.CreateString(s.id), b.CreateString(s.fort), b.CreateString(s.world), s.year));
  flatbuffers::Offset<m::SaveDestinationCatalog> catalog;
  if(action==m::SessionAction::ReadSaveDestinations && status==m::LoadRequestStatus::Ok && catalogClient==requestClient && catalogReceipt) {
    std::vector<flatbuffers::Offset<m::SaveDestination>> destinations;
    for(size_t i=0;i<catalogFolders.size();++i)destinations.push_back(m::CreateSaveDestination(b,b.CreateString(destinationId(i)),b.CreateString(DF2UTF(catalogFolders[i]))));
    catalog=m::CreateSaveDestinationCatalog(b,catalogReceipt,catalogEpoch,b.CreateVector(destinations));
  }
  auto state = m::CreateSessionState(b, m::kSessionVersion, ++revision, phase, b.CreateVector(ss), b.CreateString(activeId),
      requestSeq, status, b.CreateString(message), action, fortressValid, paused, year, yearTick,
      b.CreateString(fortName), canSave, canSaveReturn, b.CreateString(savedId),fortressEpoch,
      m::CreateInterruptionState(b,m::InterruptionKind(interruption.kind),interruption.receipt,b.CreateString(interruption.text),b.CreateString(interruption.reason),interruption.popupCount,interruption.canAcknowledge),serializePetition(b,petition), summaryAvailable ? m::CreateFortressSummary(b,population,b.CreateVector(stressCounts.data(),stressCounts.size()),stressAvailable,elevationOffset,levelCount,resourcesAvailable ? b.CreateVector(resourceCounts.data(),resourceCounts.size()) : 0,resourcesAvailable,bookkeeperPrecision) : 0,serializeNotificationGroups(b,notificationGroups),notificationGroups.complete,requestClient,requestEpoch,catalog,b.CreateVector(alertButtonReports.ids),alertButtonReports.count,alertButtonReports.complete,b.CreateString(fortOriginalName),fortressRank,fortressCapital,moonPhase);
  b.Finish(state);
  if(broadcast)sh::publishSnapshot(region, b.GetBufferPointer(), b.GetSize(), revision);
  if(reply)sh::publishSnapshot(reply->region(),b.GetBufferPointer(),b.GetSize(),revision);
  if(status!=m::LoadRequestStatus::Pending)reply.reset();
}
// Same title-row geometry as the pinned DFHack CI harness. Restore mouse state
// immediately: this is a targeted feed into the observed title screen only.
void clickTop(df::viewscreen_titlest* t) {
  auto* g = df::global::gps;
  if (!g) { reject("DF title input is unavailable"); return; }
  auto size = Screen::getWindowSize();
  int x = g->mouse_x, y = g->mouse_y, px = g->precise_mouse_x, py = g->precise_mouse_y;
  g->mouse_x = size.x / 2; g->mouse_y = size.y < 60 ? 25 : size.y / 2 + 3;
  g->precise_mouse_x = g->mouse_x * g->tile_pixel_x;
  g->precise_mouse_y = g->mouse_y * g->tile_pixel_y;
  auto* e = df::global::enabler;
  const auto oldButton = e->mouse_lbut, oldTracking = e->tracking_on;
  e->mouse_lbut = 1; e->tracking_on = 1;
  std::set<df::interface_key> keys; t->feed(&keys);
  e->mouse_lbut = oldButton; e->tracking_on = oldTracking;
  g->mouse_x = x; g->mouse_y = y; g->precise_mouse_x = px; g->precise_mouse_y = py;
}
void discover(df::viewscreen_titlest* t) {
  const auto now = std::chrono::steady_clock::now();
  if (now - lastDiscovery < std::chrono::milliseconds(250)) return;
  lastDiscovery = now;
  auto previous = saves;
  saves.clear(); std::set<std::string> ids;
  for (auto* h : t->savegame_header) if (isFort(h)) {
    auto id = idOf(h);
    if (m::validSaveId(id) && ids.insert(id).second && saves.size() < 2048)
      saves.push_back({id, DF2UTF(h->fort_name), DF2UTF(h->world_name), std::max(0, h->year)});
  }
  if (previous.size() != saves.size() || !std::equal(previous.begin(), previous.end(), saves.begin(), [](const Save& a, const Save& b) {
      return a.id == b.id && a.fort == b.fort && a.world == b.world && a.year == b.year;
    })) ++saveRevision;
}
void navigate(df::viewscreen_titlest* t) {
  auto target = std::find_if(t->savegame_header.begin(), t->savegame_header.end(), [](auto* h) { return isFort(h) && idOf(h) == pendingId; });
  if (target == t->savegame_header.end()) { reject("Selected fortress save is no longer available"); return; }
  if (navigationStage == 0 && t->mode == df::title_mode_type::MAIN_MENU) {
    clickTop(t); navigationStage = 1; return;
  }
  if (navigationStage == 1 && t->mode == df::title_mode_type::CONTINUE_ACTIVE_WORLD) {
    auto* chosen = *target;
    auto it = std::find_if(t->savegame_header_world.begin(), t->savegame_header_world.end(), [&](auto* h) {
      return h && sameSaveTimeline(h->world_header, chosen->world_header);
    });
    if (it == t->savegame_header_world.end()) { reject("Selected fortress world is unavailable"); return; }
    t->scroll_position_world_choice = static_cast<int32_t>(it - t->savegame_header_world.begin());
    clickTop(t); navigationStage = 2; return;
  }
  if (navigationStage == 2 && t->mode == df::title_mode_type::CONTINUE_ACTIVE) {
    auto it = std::find_if(t->savegame_header_game.begin(), t->savegame_header_game.end(), [](auto* h) { return h && idOf(h) == pendingId; });
    if (it == t->savegame_header_game.end()) { reject("Selected fortress is unavailable in this world"); return; }
    t->scroll_position_game_choice = static_cast<int32_t>(it - t->savegame_header_game.begin());
    clickTop(t); navigationStage = 3; return;
  }
}
bool autoSaving() {
  return df::global::plotinfo && df::global::plotinfo->main.autosave_request;
}
bool nativeSaveBusy(df::viewscreen* view) {
  return autoSaving() || virtual_cast<df::viewscreen_savegamest>(view) ||
      (df::global::game && df::global::game->main_interface.options.open &&
       df::global::game->main_interface.options.do_manual_save);
}
bool saveContext(df::viewscreen* view) {
  if (!virtual_cast<df::viewscreen_dwarfmodest>(view) || !df::global::game ||
      df::global::game->main_interface.options.open) return false;
  const auto focus = Gui::getFocusStrings(view);
  return focus.size() == 1 && focus.front() == "dwarfmode/Default";
}
// Pinned native options adapter. Both semantic enum identity and rendered row
// text must agree before feeding a click; unfamiliar layouts fail closed.
bool clickLabel(df::viewscreen_dwarfmodest* view, const std::string& label,
                const std::string& requiredText = {}) {
  auto* gps = df::global::gps;
  const auto size = Screen::getWindowSize();
  if (!gps) return false;
  int y = -1, clickX = -1;
  bool contextRendered = requiredText.empty();
  for (int rowY = 0; rowY < size.y; ++rowY) {
    std::string row;
    for (int x = 0; x < size.x; ++x) row += Screen::readTile(x, rowY).ch;
    if (!requiredText.empty() && row.find(requiredText) != std::string::npos) contextRendered = true;
    const auto at = row.find(label);
    if (at == std::string::npos) continue;
    const auto end = at + label.size();
    if (end < row.size() && row[end] != ' ' && row[end] != '\0') continue;
    if (y >= 0) return false; // Duplicate text cannot identify an input target.
    y = rowY; clickX = int(at + label.size() / 2);
  }
  if (y < 0 || !contextRendered) return false;
  const int x = gps->mouse_x, oldY = gps->mouse_y, px = gps->precise_mouse_x, py = gps->precise_mouse_y;
  gps->mouse_x = clickX; gps->mouse_y = y;
  gps->precise_mouse_x = gps->mouse_x * gps->tile_pixel_x;
  gps->precise_mouse_y = y * gps->tile_pixel_y;
  auto* enabler = df::global::enabler;
  const auto oldButton = enabler->mouse_lbut, oldTracking = enabler->tracking_on;
  enabler->mouse_lbut = 1; enabler->tracking_on = 1;
  std::set<df::interface_key> keys;
  view->feed(&keys);
  enabler->mouse_lbut = oldButton; enabler->tracking_on = oldTracking;
  gps->mouse_x = x; gps->mouse_y = oldY; gps->precise_mouse_x = px; gps->precise_mouse_y = py;
  return true;
}
bool clickOption(df::viewscreen_dwarfmodest* view, size_t index, const std::string& label) {
  return index < df::global::game->main_interface.options.option.size() && clickLabel(view, label);
}
void cleanupOwnedMenus(df::viewscreen* current) {
  if (!cleanupRequested) return;
  auto* view = virtual_cast<df::viewscreen_dwarfmodest>(current);
  if (!view || !df::global::game || !df::global::world || ++cleanupFrames > 120) { cleanupRequested = false; return; }
  const auto& header = df::global::world->cur_savegame.world_header;
  if (header.id1 != pendingWorld1 || header.id2 != pendingWorld2) { cleanupRequested = false; return; }
  auto& opts = df::global::game->main_interface.options;
  if (!opts.open) { cleanupRequested = false; return; }
  // Never dismiss a writer, including a concurrently started native autosave.
  if (autoSaving() || saveSawProgress || opts.manual_save_timer > 0) return;
  if (opts.entering_manual_folder || opts.confirm_manual_overwrite || opts.entering_timeline ||
      (cleanupQuitConfirmation && opts.fort_quit_without_saving_confirm)) {
    clickLabel(view, "Cancel"); return;
  }
  if (opts.context != df::options_context_type::MAIN_DWARF &&
      opts.context != df::options_context_type::MAIN_DWARF_SAVE_AND_EXIT_CHOICES) { cleanupRequested = false; return; }
  auto it = std::find(opts.option.begin(), opts.option.end(), df::main_menu_option_type::RETURN);
  if (it != opts.option.end()) clickOption(view, size_t(it-opts.option.begin()),
      "Return to game");
}
bool readDestinationFolders(std::vector<std::string>& folders) {
  const auto& opts=df::global::game->main_interface.options;
  std::set<std::string> unique;
  size_t bytes=0;
  for(size_t i=0;i<opts.option.size();++i) {
    if(opts.option[i]!=df::main_menu_option_type::SAVE_TO_EXISTING_FOLDER)continue;
    if(i>=opts.option_index.size())return false;
    const auto index=opts.option_index[i];
    if(index<0 || size_t(index)>=opts.overwrite_save_folder.size() || !opts.overwrite_save_folder[index])return false;
    const auto& folder=*opts.overwrite_save_folder[index];
    if(!m::validSaveId(folder) || !unique.insert(folder).second || unique.size()>m::kMaxSaveDestinations)return false;
    // Native commands address a folder basename. Refuse ambiguous basenames
    // across discovered roots rather than inventing which path native will use.
    size_t matches=0;
    for(const auto& save:saves)if(lowerAscii(std::filesystem::path(save.id).filename().string())==lowerAscii(folder))++matches;
    if(matches!=1)return false;
    bytes+=folder.size()+DF2UTF(folder).size();
    if(bytes>m::kSessionCapacity/4)return false;
    folders.push_back(folder);
  }
  return true;
}
void navigateQuit(df::viewscreen* current) {
  auto* view=virtual_cast<df::viewscreen_dwarfmodest>(current);
  if(!view || !df::global::game)return;
  auto& opts=df::global::game->main_interface.options;
  if(autoSaving() || opts.manual_save_timer>0 || (opts.do_manual_save && opts.saver.stage<51)) {
    reject("Native session operation is busy");return;
  }
  if(navigationStage==0) {
    std::set<df::interface_key> keys{df::interface_key::OPTIONS};view->feed(&keys);
    navigationStage=1;return;
  }
  if(navigationStage==1 && opts.open && opts.context==df::options_context_type::MAIN_DWARF) {
    auto it=std::find(opts.option.begin(),opts.option.end(),df::main_menu_option_type::QUIT_WITHOUT_SAVING);
    if(it==opts.option.end()){reject("Native quit option is unavailable");return;}
    if(clickOption(view,size_t(it-opts.option.begin()),"Quit without saving"))navigationStage=2;
  } else if(navigationStage==2 && opts.open && opts.fort_quit_without_saving_confirm) {
    // The options flag changes before the new screen is rendered. Do not
    // mistake the preceding "Quit without saving" row for the confirm button.
    // Both strings come from the pinned native confirmation fixture.
    if(clickLabel(view,"Quit","Really quit without saving?")){quitIssued=true;navigationStage=3;}
  }
}
void navigateReturn(df::viewscreen* current) {
  auto* view = virtual_cast<df::viewscreen_dwarfmodest>(current);
  if (!view || !df::global::game) return;
  auto& opts = df::global::game->main_interface.options;
  if(action==m::SessionAction::ReadSaveDestinations && navigationStage==5) {
    if(!opts.open) {status=m::LoadRequestStatus::Ok;phase=m::SessionPhase::Ready;pendingId.clear();navigationStage=0;message.clear();}
    else clickLabel(view,"Return to game");
    return;
  }
  if(action==m::SessionAction::SaveReturn && navigationStage==5 && opts.entering_timeline) {
    opts.entering_timeline_str=timelineName;
    saveIssued=true;
    std::set<df::interface_key> keys{df::interface_key::SELECT};view->feed(&keys);
    navigationStage=4;return;
  }
  if (navigationStage == 0) {
    std::set<df::interface_key> keys{df::interface_key::OPTIONS}; view->feed(&keys);
    navigationStage = 1; return;
  }
  if (navigationStage == 1 && opts.open && opts.context == df::options_context_type::MAIN_DWARF) {
    const bool staying = action == m::SessionAction::SaveContinue;
    auto it = std::find(opts.option.begin(), opts.option.end(), staying ? df::main_menu_option_type::SAVE_AND_CONTINUE : df::main_menu_option_type::SAVE_AND_QUIT);
    if (it == opts.option.end()) { reject("Native save-and-return option is unavailable"); return; }
    if (clickOption(view, size_t(it-opts.option.begin()), staying ? "Save and continue playing" : "Save and return to title menu")) navigationStage = 2;
  } else if (navigationStage == 2 && action == m::SessionAction::SaveContinue && opts.open && opts.entering_manual_folder) {
    opts.entering_manual_str = checkpointName;
    saveIssued=true;
    std::set<df::interface_key> keys{df::interface_key::SELECT}; view->feed(&keys);
    navigationStage = 3;
  } else if (navigationStage == 3 && action == m::SessionAction::SaveContinue && opts.confirm_manual_overwrite) {
    // The native confirmation proves the writer has not been started.
    saveIssued=false;
    reject("Checkpoint name already exists; choose a new name. No overwrite was confirmed.");
  } else if (navigationStage == 2 && opts.open && opts.context == df::options_context_type::MAIN_DWARF_SAVE_AND_EXIT_CHOICES) {
    std::vector<std::string> folders;
    if(!readDestinationFolders(folders)) {reject("Save destination catalog is incomplete or ambiguous");return;}
    if(action==m::SessionAction::ReadSaveDestinations) {
      catalogFolders=std::move(folders);catalogEpoch=pendingSaveEpoch;catalogClient=requestClient;catalogReceipt=++catalogCounter;
      navigationStage=5;return;
    }
    if(folders!=catalogFolders) {reject("Save destinations changed before selection");return;}
    if(returnMode==m::SaveReturnMode::NewFolder || returnMode==m::SaveReturnMode::NewTimeline) {
      const bool newTimeline=returnMode==m::SaveReturnMode::NewTimeline;
      auto it=std::find(opts.option.begin(),opts.option.end(),newTimeline?df::main_menu_option_type::SAVE_TO_NEW_FOLDER_NEW_TIMELINE:df::main_menu_option_type::SAVE_TO_NEW_FOLDER_EXISTING_TIMELINE);
      if(it==opts.option.end()) {reject("Requested native destination action is unavailable");return;}
      if(clickOption(view,size_t(it-opts.option.begin()),newTimeline?"Save to new timeline":"Save to new folder (same timeline)")) {
        navigationStage=newTimeline?5:4;saveIssued=!newTimeline;
      }
      return;
    }
    int chosen = -1;
    for (size_t i = 0; i < opts.option.size(); ++i) {
      if (opts.option[i] != df::main_menu_option_type::SAVE_TO_EXISTING_FOLDER || i >= opts.option_index.size()) continue;
      const auto ix = opts.option_index[i];
      if (ix < 0 || size_t(ix) >= opts.overwrite_save_folder.size() || !opts.overwrite_save_folder[ix]) continue;
      if (*opts.overwrite_save_folder[ix] != pendingFilename) continue;
      if (chosen >= 0) { reject("Native save destination is ambiguous; choose it in Dwarf Fortress"); return; }
      chosen = int(i);
    }
    if (chosen < 0) {
      reject("Selected save destination is no longer available");return;
    }
    pendingExistingPath.clear();
    for(const auto& save:saves)if(lowerAscii(std::filesystem::path(save.id).filename().string())==lowerAscii(pendingFilename)) {
      if(!pendingExistingPath.empty()){reject("Save destination catalog is incomplete or ambiguous");return;}
      pendingExistingPath=save.id;
    }
    existingWorldBefore=pendingExistingPath.empty()?std::nullopt:savedWorldStamp(pendingExistingPath);
    if(!existingWorldBefore){reject("Selected save destination is no longer available");return;}
    if (clickOption(view, size_t(chosen), folders.size()==1?"Save to this timeline":"Save to timeline folder: " + pendingFilename)) {navigationStage = 3;saveIssued=true;}
  }
}
}
bool start(color_ostream& out) {
  resetInterruption();resetPetition();fortressEpoch=0;interruption={};petition={};notificationGroups={};alertButtonReports={};
  if (region) return true;
  const size_t size = sh::regionSize(m::kSessionCapacity, m::kSessionCommandCapacity);
  mapping = CreateFileMappingA(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, static_cast<DWORD>(size), m::kSessionRegionName);
  if (!mapping) {
    out.printerr("df3d: cannot create exclusive session channel\n"); return false;
  }
  region = static_cast<sh::RegionHeader*>(MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, size));
  if (!region) { CloseHandle(mapping); mapping = nullptr; return false; }
  // A held client mapping can survive the producer. Reclaim only a dead owner.
  auto* old = m::sessionOwner(region);
  const auto oldPid = sh::atomicLoadAcquire(&old->pid), oldCreated = sh::atomicLoadAcquire(&old->created);
  if (oldPid) {
    HANDLE proc = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, static_cast<DWORD>(oldPid));
    FILETIME ct{}, et{}, kt{}, ut{};
    bool alive = proc && GetProcessTimes(proc, &ct, &et, &kt, &ut) &&
        ((uint64_t(ct.dwHighDateTime) << 32) | ct.dwLowDateTime) == oldCreated && WaitForSingleObject(proc, 0) == WAIT_TIMEOUT;
    if (proc) CloseHandle(proc);
    if (alive) { UnmapViewOfFile(region); CloseHandle(mapping); region = nullptr; mapping = nullptr; out.printerr("df3d: another session bridge owns this channel\n"); return false; }
  }
  sh::initRegion(region, m::kSessionVersion, m::kSessionCapacity, m::kSessionCommandCapacity);
  FILETIME ct{}, et{}, kt{}, ut{}; GetProcessTimes(GetCurrentProcess(), &ct, &et, &kt, &ut);
  auto* owner = m::sessionOwner(region);
  FILETIME now{}; GetSystemTimeAsFileTime(&now);
  sh::atomicStoreRelease(&owner->generation, (uint64_t(now.dwHighDateTime) << 32) | now.dwLowDateTime);
  sh::atomicStoreRelease(&owner->created, (uint64_t(ct.dwHighDateTime) << 32) | ct.dwLowDateTime);
  sh::atomicStoreRelease(&owner->pid, GetCurrentProcessId());
  lastPublished.clear(); saveRevision = 0; lastDiscovery = {};
  reply.reset(); requestClient=0;
  requestEpoch=catalogCounter=catalogReceipt=catalogEpoch=catalogClient=0;catalogFolders.clear();
  returnMode=m::SaveReturnMode::None;timelineName.clear();pendingTimeline.clear();
  revision = requestSeq = 0; phase = m::SessionPhase::Starting; status = m::LoadRequestStatus::None;
  message.clear(); activeId.clear(); pendingId.clear(); savedId.clear(); saves.clear(); navigationStage = 0;
  action = m::SessionAction::LoadFortress; fortressValid = paused = canSave = canSaveReturn = false;
  year = yearTick = 0; fortName.clear(); fortOriginalName.clear(); fortressRank=-1; fortressCapital=false; moonPhase=-1; lastStatus = {}; saveSawProgress = saveIssued = quitIssued = false;
  observedSaveIds.clear(); previousSaveIds.clear();
  cleanupRequested = cleanupQuitConfirmation = false; cleanupFrames = 0;
  publish(); return true;
}
void stop() {
  resetInterruption();resetPetition();fortressEpoch=0;interruption={};petition={};notificationGroups={};alertButtonReports={};
  canSave = canSaveReturn = false;
  if (region) { sh::atomicStoreRelease(&m::sessionOwner(region)->pid, 0); phase = m::SessionPhase::Unavailable; message = "DF session bridge stopped"; publish(); reply.reset(); UnmapViewOfFile(region); }
  if (mapping) CloseHandle(mapping);
  mapping = nullptr; region = nullptr;
}
bool saving() { return region && (phase == m::SessionPhase::Saving || phase == m::SessionPhase::Unloading); }
void update(bool mapLoaded,uint64_t epoch) {
  if (!region) return;
  auto* view = Gui::getCurViewscreen(true);
  cleanupOwnedMenus(view);
  auto* title = virtual_cast<df::viewscreen_titlest>(view);
  bool loading = virtual_cast<df::viewscreen_loadgamest>(view) != nullptr;
  if (mapLoaded) {
    if (phase != m::SessionPhase::Error) phase = m::SessionPhase::Ready;
    if (status == m::LoadRequestStatus::Pending && action == m::SessionAction::LoadFortress) {
      auto& current = df::global::world->cur_savegame;
      if (current.world_header.id1 != pendingWorld1 || current.world_header.id2 != pendingWorld2 ||
          current.save_dir != pendingFilename || df::global::world->loaded_save_path.generic_string() != pendingId) {
        reject("DF loaded a different save than requested; inspect the DF window"); phase = m::SessionPhase::Error;
      } else {
        World::SetPauseState(true);
        activeId = df::global::world->loaded_save_path.generic_string(); pendingId.clear(); navigationStage=0; status = m::LoadRequestStatus::Ok; message = "Fortress loaded";
      }
    }
  } else if (!pendingId.empty() || loading) phase = m::SessionPhase::Loading;
  else if (title && title->mode == df::title_mode_type::MAIN_MENU) { phase = m::SessionPhase::Menu; discover(title); }
  else { if (phase != m::SessionPhase::Error) phase = m::SessionPhase::Unavailable; if (status != m::LoadRequestStatus::Rejected && status != m::LoadRequestStatus::UnknownOutcome) message = "Return Dwarf Fortress to its main menu to load a fortress"; }
  fortressValid = mapLoaded && df::global::plotinfo && df::global::world && World::isFortressMode();
  // Pause belongs to the loaded simulation, including object-testing maps;
  // observing it must not grant fortress menus, save eligibility or an epoch.
  paused = mapLoaded && df::global::world && World::ReadPauseState();
  fortressEpoch=fortressValid?epoch:0;
  if(!fortressValid){notificationGroups={};alertButtonReports={};}
  const auto now = std::chrono::steady_clock::now();
  if (fortressValid) {
    activeId = df::global::world->loaded_save_path.generic_string();
    if (!activeId.empty()) observedSaveIds.insert(activeId);
    if(summaryEpoch!=fortressEpoch) {summaryEpoch=fortressEpoch;lastStatus={};lastHeader={};population=0;stressCounts={};stressAvailable=false;resourceCounts={};resourcesAvailable=false;bookkeeperPrecision=-1;}
    if(now-lastHeader>=std::chrono::milliseconds(250)) {
      lastHeader=now;
      refreshPopulation();
    }
    if (now - lastStatus >= std::chrono::milliseconds(250)) {
      lastStatus = now;
      notificationGroups=readNotificationGroups(df::global::world->status.announcement_alert);
      alertButtonReports=readAlertButton(df::global::world->status.alert_button_announcement_id);
      year = df::global::cur_year ? std::max(0, *df::global::cur_year) : 0;
      yearTick = df::global::cur_year_tick ? std::clamp(*df::global::cur_year_tick, 0, 403199) : 0;
      const auto& map=df::global::world->map;
      const auto& food=df::global::plotinfo->tasks.food;
      resourceCounts={food.total,food.drink,food.seeds,food.meat,food.fish,food.plant,food.other};
      bookkeeperPrecision=std::max(0,df::global::plotinfo->nobles.bookkeeper_precision);
      resourcesAvailable=std::all_of(resourceCounts.begin(),resourceCounts.end(),[](int32_t value){return value>=0;});
      if(!resourcesAvailable)resourceCounts={};
      elevationOffset=map.region_z-100;levelCount=uint32_t(std::max(0,map.z_count));
      summaryAvailable=stressAvailable && population>=0 && levelCount>0 && levelCount<=65536 && elevationOffset>=-65536 && elevationOffset<=65536;
      auto* site = df::global::plotinfo->main.fortress_site;
      fortName = site ? DF2UTF(Translation::translateName(&site->name, true)) : "";
      fortOriginalName = site ? DF2UTF(Translation::translateName(&site->name, false)) : "";
      const auto rank=df::global::plotinfo->fortress_rank;
      fortressRank=site && rank>=0 && rank<=5 ? rank : -1;
      fortressCapital=site && df::global::plotinfo->king_arrived;
      const auto* worldData=df::global::world->world_data;
      moonPhase=worldData && worldData->moon_phase>=0 && worldData->moon_phase<=27 ? int8_t(worldData->moon_phase) : -1;
    }
  } else { activeId.clear(); fortName.clear(); fortOriginalName.clear(); fortressRank=-1; fortressCapital=false; moonPhase=-1; year = yearTick = 0; summaryAvailable=stressAvailable=resourcesAvailable=false;summaryEpoch=0;population=elevationOffset=0;levelCount=0;stressCounts={};resourceCounts={};bookkeeperPrecision=-1; }
  if (status == m::LoadRequestStatus::Pending && (action == m::SessionAction::SaveContinue || action == m::SessionAction::SaveReturn || action==m::SessionAction::ReadSaveDestinations || action==m::SessionAction::QuitWithoutSaving) && fortressValid && !m::sessionEpochMatches(pendingSaveEpoch,fortressEpoch)) {
    reject("Fortress changed before save completed"); cleanupRequested=false;
  }
  if (status == m::LoadRequestStatus::Pending && (action == m::SessionAction::SaveContinue || action == m::SessionAction::SaveReturn || action==m::SessionAction::ReadSaveDestinations)) {
    phase = m::SessionPhase::Saving;
    if(action==m::SessionAction::ReadSaveDestinations)navigateReturn(view);
    if (action == m::SessionAction::SaveReturn) {
      if (virtual_cast<df::viewscreen_savegamest>(view)) saveSawProgress = true;
      if (title && (navigationStage == 3 || navigationStage == 4)) {
        auto found = std::find_if(title->savegame_header.begin(), title->savegame_header.end(), [](auto* h) {
          return isFort(h) && (navigationStage == 4 ? !previousSaveIds.count(idOf(h)) : h->filename_noext == pendingFilename) &&
              h->world_header.id1 == pendingWorld1 && h->world_header.id2 == pendingWorld2 &&
              h->world_header.timeline_name==pendingTimeline;
        });
        if (found != title->savegame_header.end() && navigationStage == 4) {
          const auto count = std::count_if(title->savegame_header.begin(), title->savegame_header.end(), [](auto* h) {
            return isFort(h) && !previousSaveIds.count(idOf(h)) && h->world_header.id1 == pendingWorld1 && h->world_header.id2 == pendingWorld2 && h->world_header.timeline_name==pendingTimeline;
          });
          if (count != 1) { reject("New save identity is ambiguous; inspect Dwarf Fortress"); found = title->savegame_header.end(); }
        }
        if (found != title->savegame_header.end() && saveSawProgress && !mapLoaded && hasSavedWorld((*found)->full_path)) {
          if(navigationStage==3 && (idOf(*found)!=pendingExistingPath || !savedWorldChanged(existingWorldBefore,savedWorldStamp((*found)->full_path)))) {
            reject("DF save identity or world file could not be verified; save was not confirmed");
          } else {
            status = m::LoadRequestStatus::Ok; phase = m::SessionPhase::Menu;
            savedId = idOf(*found);
            message = "Fortress saved to " + (*found)->filename_noext + "; returned to menu"; pendingId.clear(); navigationStage = 0;
            lastDiscovery = {}; discover(title);
          }
        }
      } else navigateReturn(view);
    }
    if (action == m::SessionAction::SaveContinue) {
      navigateReturn(view);
      if (df::global::game && navigationStage == 3) {
        const auto& opts = df::global::game->main_interface.options;
        if (opts.do_manual_save && (opts.manual_save_timer > 0 || opts.saver.stage < 51)) saveSawProgress = true;
        // DF retains do_manual_save and entering_manual_folder after completion.
        // Only the native finished saver + closed options + exact new identity
        // establish success, never those sticky booleans turning false.
        if (saveSawProgress && fortressValid && !opts.open && opts.manual_save_timer == 0 &&
            opts.saver.stage == 51 && opts.saver.substage == df::save_substage::Finishing) {
          const auto& current = df::global::world->cur_savegame;
          if (current.save_dir == checkpointName && current.world_header.id1 == pendingWorld1 &&
              current.world_header.id2 == pendingWorld2 &&
              df::global::world->loaded_save_path.filename().string() == checkpointName &&
              hasSavedWorld(df::global::world->loaded_save_path)) {
            status = m::LoadRequestStatus::Ok; phase = m::SessionPhase::Ready;
            savedId = activeId;
            message = "Checkpoint saved: " + checkpointName; pendingId.clear(); navigationStage = 0;
          } else reject("DF save identity or world file could not be verified; save was not confirmed");
        }
      }
    }
    if (status == m::LoadRequestStatus::Pending && (navigationStage < 3 || navigationStage==5) &&
        now - requestedAt > std::chrono::seconds(15)) {
      reject("Native save dialog was not recognized; save was not started");
    } else if (status == m::LoadRequestStatus::Pending && now - requestedAt > std::chrono::minutes(5)) {
      reject("Save completion is unverified; inspect Dwarf Fortress before closing it");
    }
  } else if (fortressValid && (nativeSaveBusy(view) || cleanupRequested))
    phase = cleanupRequested && cleanupQuitConfirmation && !nativeSaveBusy(view)?m::SessionPhase::Unloading:m::SessionPhase::Saving;
  if(status==m::LoadRequestStatus::Pending && action==m::SessionAction::QuitWithoutSaving) {
    phase=m::SessionPhase::Unloading;
    if(quitIssued && title && title->mode==df::title_mode_type::MAIN_MENU && !mapLoaded) {
      status=m::LoadRequestStatus::Ok;phase=m::SessionPhase::Menu;
      pendingId.clear();navigationStage=0;message.clear();savedId.clear();
      lastDiscovery={};discover(title);
    } else {
      if(!quitIssued)navigateQuit(view);
      if(status==m::LoadRequestStatus::Pending && now-requestedAt>(quitIssued?std::chrono::seconds(300):std::chrono::seconds(15)))
        reject("Native quit completion could not be verified");
    }
  }
  canSave = fortressValid && phase == m::SessionPhase::Ready && !cleanupRequested && status != m::LoadRequestStatus::Pending && saveContext(view);
  canSaveReturn = canSave;
  // Passive status reads simulation popup data, never native panel/focus state.
  // Acknowledgment and petition navigation remain retired until semantic APIs exist.
  interruption={};petition={};
  if(fortressValid) {
    interruption.kind=paused?uint8_t(m::InterruptionKind::ManualPause):uint8_t(m::InterruptionKind::None);
    const auto& popups=df::global::world->status.popups;
    interruption.popupCount=static_cast<uint32_t>(popups.size());
    if(!popups.empty()) {
      interruption.kind=uint8_t(m::InterruptionKind::PassiveAnnouncement);
      if(popups.front())interruption.text=DF2UTF(popups.front()->text).substr(0,32768);
      interruption.reason="Announcement acknowledgment requires a semantic replacement";
    }
  }
  canSave=canSaveReturn=canSave&&interruption.popupCount==0;
  uint8_t bytes[m::kSessionCommandCapacity];
  for (int n = 0; n < 16; ++n) {
    size_t len = sh::popCommand(region, bytes, sizeof(bytes));
    if (!len) break;
    if (len == static_cast<size_t>(-1)) { sh::atomicStoreRelease(&region->cmdTail, sh::atomicLoadAcquire(&region->cmdHead)); break; }
    flatbuffers::Verifier v(bytes, len);
    if (!v.VerifyBuffer<m::SessionCommand>(nullptr)) continue;
    auto* c = flatbuffers::GetRoot<m::SessionCommand>(bytes);
    if (m::validateSessionCommand(*c)) continue;
    // Commit the previous outcome before this tick can accept another client.
    publish();
    auto nextReply=sh::ClientMailbox::open(m::kSessionRegionName,
        sh::atomicLoadAcquire(&m::sessionOwner(region)->generation),c->client_id(),m::kSessionVersion,m::kSessionCapacity);
    if(!nextReply || !nextReply->accept(c->seq()))continue;
    if(status==m::LoadRequestStatus::Pending) {
      // A busy response belongs only to the competing client. Preserve the
      // active lifecycle operation and its receipt unchanged.
      auto activeReply=std::move(reply);reply=std::move(nextReply);
      const auto oldSeq=requestSeq,oldClient=requestClient,oldEpoch=requestEpoch;const auto oldAction=action;const auto oldStatus=status;
      const auto oldMessage=message,oldSaved=savedId;
      requestSeq=c->seq();requestClient=c->client_id();action=c->action();requestEpoch=c->fortress_epoch();
      status=m::LoadRequestStatus::Rejected;message="Another client has a session operation in progress";savedId.clear();
      publish(false);
      requestSeq=oldSeq;requestClient=oldClient;requestEpoch=oldEpoch;action=oldAction;status=oldStatus;message=oldMessage;savedId=oldSaved;
      reply=std::move(activeReply);continue;
    }
    reply=std::move(nextReply);requestClient=c->client_id();requestSeq=c->seq();
    requestEpoch=c->fortress_epoch();
    saveIssued=saveSawProgress=quitIssued=false;
    pendingExistingPath.clear();existingWorldBefore.reset();
    savedId.clear();
    action = c->action();
    if(!m::runtimeSessionAction(action)) {
      reject("Native announcement and petition adapters are retired; semantic replacement unfinished");continue;
    }
    if (action != m::SessionAction::LoadFortress) {
      if(!m::sessionEpochMatches(c->fortress_epoch(),fortressEpoch)) { reject("Fortress changed; save was not started"); continue; }
      pendingSaveEpoch=c->fortress_epoch();
      if (!(action == m::SessionAction::SaveReturn ? canSaveReturn : canSave) || nativeSaveBusy(view)) { reject("Close native DF panels and wait for any current save before saving"); continue; }
      if(action==m::SessionAction::QuitWithoutSaving) {
        const auto& header=df::global::world->cur_savegame.world_header;
        pendingWorld1=header.id1;pendingWorld2=header.id2;pendingId=activeId;
        requestedAt=now;navigationStage=0;status=m::LoadRequestStatus::Pending;
        phase=m::SessionPhase::Unloading;message.clear();canSave=canSaveReturn=false;
        continue;
      }
      {
        returnMode=c->save_return_mode();timelineName.clear();
        if(c->timeline_name())timelineName.assign(c->timeline_name()->begin(),c->timeline_name()->end());
        if(action==m::SessionAction::SaveReturn &&
           (!catalogReceipt || c->save_catalog_receipt()!=catalogReceipt || catalogClient!=requestClient || catalogEpoch!=pendingSaveEpoch)) {
          reject("Save destination catalog is no longer owned by this request");continue;
        }
        size_t chosen=catalogFolders.size();
        if(c->save_destination_id())for(size_t i=0;i<catalogFolders.size();++i)if(destinationId(i)==c->save_destination_id()->str())chosen=i;
        if(action==m::SessionAction::SaveReturn && returnMode==m::SaveReturnMode::ExistingDestination && chosen==catalogFolders.size()) {
          reject("Requested destination is not in the save catalog");continue;
        }
        checkpointName = c->checkpoint_name() ? c->checkpoint_name()->str() : "";
        if (action == m::SessionAction::SaveContinue && checkpointExists(checkpointName)) {
          reject("Checkpoint name already exists; choose a new name"); continue;
        }
        pendingId = activeId;
        previousSaveIds = observedSaveIds; previousSaveIds.insert(activeId);
        for (const auto& save : saves) previousSaveIds.insert(save.id);
        auto& current = df::global::world->cur_savegame;
        pendingFilename = current.save_dir; pendingWorld1 = current.world_header.id1; pendingWorld2 = current.world_header.id2;
        pendingTimeline=current.world_header.timeline_name;
        if(action==m::SessionAction::SaveReturn) {
          if(returnMode==m::SaveReturnMode::ExistingDestination)pendingFilename=catalogFolders[chosen];
          if(returnMode==m::SaveReturnMode::NewTimeline)pendingTimeline=timelineName;
        }
        saveSawProgress = false; navigationStage = 0; requestedAt = now;
        status = m::LoadRequestStatus::Pending; phase = m::SessionPhase::Saving;
        message = action == m::SessionAction::SaveContinue ? "Saving manual checkpoint" : "Saving fortress and returning to menu";
      }
      canSave = canSaveReturn = false; continue;
    }
    if (phase != m::SessionPhase::Menu || !title) { reject("DF is not at the fortress loading menu"); continue; }
    auto id = c->save_id()->str();
    if (std::none_of(saves.begin(), saves.end(), [&](const Save& s) { return s.id == id; })) { reject("Selected fortress save is no longer available"); continue; }
    auto header = std::find_if(title->savegame_header.begin(), title->savegame_header.end(), [&](auto* h) { return isFort(h) && idOf(h) == id; });
    if (header == title->savegame_header.end()) { reject("Selected fortress save is no longer available"); continue; }
    pendingFilename = (*header)->filename_noext;
    pendingWorld1 = (*header)->world_header.id1; pendingWorld2 = (*header)->world_header.id2;
    pendingId = id; status = m::LoadRequestStatus::Pending; phase = m::SessionPhase::Loading;
    message = "Loading fortress"; requestedAt = std::chrono::steady_clock::now(); navigationStage = 0;
  }
  if (!pendingId.empty() && action == m::SessionAction::LoadFortress) {
    const auto step = loadStep(std::chrono::steady_clock::now() - requestedAt,
        title != nullptr, loading, virtual_cast<df::viewscreen_dwarfmodest>(view) != nullptr,
        mapLoaded, navigationStage);
    if (step == LoadStep::Navigate) navigate(title);
    else if (step == LoadStep::TimedOut || step == LoadStep::NeedsAttention) {
      reject(step == LoadStep::NeedsAttention ? loadFailureMessage(step, Gui::getFocusStrings(view)) : loadFailureMessage(step));
      phase = m::SessionPhase::Error;
    }
  }
  if(phase!=m::SessionPhase::Ready){interruption.canAcknowledge=false;interruption.receipt=0;}
  publish();
}
}
