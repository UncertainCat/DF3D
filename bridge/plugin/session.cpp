// Global session lifecycle retains the verified native menu initialization.
// Load/save are documented global exceptions; ordinary panels never use them.
#include "session.h"
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
#include "df/global_objects.h"
#include "session_util.h"
#include "shm_layout.h"
#include <chrono>
#include <filesystem>
#include <algorithm>
#include <set>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include "client_mailbox.h"
namespace df3d_session {
// Saver stage and changed in-memory identity alone can report a false success
// when initialization skipped the compressor. A new checkpoint also needs an
// actual nonempty world file. The live lane additionally reloads the result.
static bool hasSavedWorld(const std::filesystem::path& directory) {
    std::error_code error;
    const auto file=directory/"world.sav";
    if(!std::filesystem::is_regular_file(file,error)||error)return false;
    const auto size=std::filesystem::file_size(file,error);
    return !error && size>0;
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
InterruptionInfo interruption;
PetitionInfo petition;
NotificationGroups notificationGroups;
int32_t year = 0, yearTick = 0;
std::string fortName;
bool summaryAvailable=false, stressAvailable=false, resourcesAvailable=false;
int32_t population=0,elevationOffset=0;
uint32_t levelCount=0;
std::array<uint32_t,7> stressCounts{};
std::array<int32_t,7> resourceCounts{};
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
  for(auto value:resourceCounts)key+=":"+std::to_string(value);
  return key;
}
std::string checkpointName;
bool saveSawProgress = false;
std::set<std::string> previousSaveIds;
std::set<std::string> observedSaveIds;
bool cleanupRequested = false;
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
  if ((action == m::SessionAction::SaveContinue || action == m::SessionAction::SaveReturn) && navigationStage > 0 && !saveSawProgress) {
    cleanupRequested = true; cleanupFrames = 0;
  }
  status = m::LoadRequestStatus::Rejected; message = reason; pendingId.clear(); navigationStage = 0;
}
void publish(bool broadcast=true) {
  const std::string key = std::to_string(int(phase)) + ":" + std::to_string(int(status)) + ":" +
      std::to_string(requestSeq) + ":" + std::to_string(saveRevision) + ":" + activeId + ":" + message + ":" +
      std::to_string(int(action)) + ":" + std::to_string(fortressValid) + ":" + std::to_string(paused) + ":" +
      std::to_string(year) + ":" + std::to_string(yearTick) + ":" + fortName + ":" +
      std::to_string(canSave) + ":" + std::to_string(canSaveReturn) + ":" + savedId + ":" + std::to_string(fortressEpoch) + ":" + std::to_string(interruption.kind) + ":" + std::to_string(interruption.receipt) + ":" + interruption.text + ":" + interruption.reason + ":" + std::to_string(interruption.popupCount) + ":" + std::to_string(interruption.canAcknowledge) + ":" + std::to_string(petition.revision);
  if (broadcast && key + summaryKey() + notificationGroups.key + ":" + std::to_string(requestClient) == lastPublished) return;
  if(broadcast)lastPublished = key + summaryKey() + notificationGroups.key + ":" + std::to_string(requestClient);
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<m::FortressSave>> ss;
  for (const auto& s : saves) ss.push_back(m::CreateFortressSave(b, b.CreateString(s.id), b.CreateString(s.fort), b.CreateString(s.world), s.year));
  auto state = m::CreateSessionState(b, m::kSessionVersion, ++revision, phase, b.CreateVector(ss), b.CreateString(activeId),
      requestSeq, status, b.CreateString(message), action, fortressValid, paused, year, yearTick,
      b.CreateString(fortName), canSave, canSaveReturn, b.CreateString(savedId),fortressEpoch,
      m::CreateInterruptionState(b,m::InterruptionKind(interruption.kind),interruption.receipt,b.CreateString(interruption.text),b.CreateString(interruption.reason),interruption.popupCount,interruption.canAcknowledge),serializePetition(b,petition), summaryAvailable ? m::CreateFortressSummary(b,population,b.CreateVector(stressCounts.data(),stressCounts.size()),stressAvailable,elevationOffset,levelCount,resourcesAvailable ? b.CreateVector(resourceCounts.data(),resourceCounts.size()) : 0,resourcesAvailable) : 0,serializeNotificationGroups(b,notificationGroups),notificationGroups.complete,requestClient);
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
      return h && h->world_header.id1 == chosen->world_header.id1 && h->world_header.id2 == chosen->world_header.id2;
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
bool clickLabel(df::viewscreen_dwarfmodest* view, const std::string& label) {
  auto* gps = df::global::gps;
  const auto size = Screen::getWindowSize();
  if (!gps) return false;
  int y = -1, clickX = -1;
  for (int rowY = 0; rowY < size.y; ++rowY) {
    std::string row;
    for (int x = 0; x < size.x; ++x) row += Screen::readTile(x, rowY).ch;
    const auto at = row.find(label);
    if (at == std::string::npos) continue;
    const auto end = at + label.size();
    if (end < row.size() && row[end] != ' ' && row[end] != '\0') continue;
    if (y >= 0) return false; // Duplicate text cannot identify an input target.
    y = rowY; clickX = int(at + label.size() / 2);
  }
  if (y < 0) return false;
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
  if (opts.entering_manual_folder || opts.confirm_manual_overwrite) {
    clickLabel(view, "Cancel"); return;
  }
  if (opts.context != df::options_context_type::MAIN_DWARF &&
      opts.context != df::options_context_type::MAIN_DWARF_SAVE_AND_EXIT_CHOICES) { cleanupRequested = false; return; }
  auto it = std::find(opts.option.begin(), opts.option.end(), df::main_menu_option_type::RETURN);
  if (it != opts.option.end()) clickOption(view, size_t(it-opts.option.begin()),
      opts.context == df::options_context_type::MAIN_DWARF ? "Return to game" : "Return");
}
void navigateReturn(df::viewscreen* current) {
  auto* view = virtual_cast<df::viewscreen_dwarfmodest>(current);
  if (!view || !df::global::game) return;
  auto& opts = df::global::game->main_interface.options;
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
    std::set<df::interface_key> keys{df::interface_key::SELECT}; view->feed(&keys);
    navigationStage = 3;
  } else if (navigationStage == 3 && action == m::SessionAction::SaveContinue && opts.confirm_manual_overwrite) {
    reject("Checkpoint name already exists; choose a new name. No overwrite was confirmed.");
  } else if (navigationStage == 2 && opts.open && opts.context == df::options_context_type::MAIN_DWARF_SAVE_AND_EXIT_CHOICES) {
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
      auto it = std::find(opts.option.begin(), opts.option.end(), df::main_menu_option_type::SAVE_TO_NEW_FOLDER_EXISTING_TIMELINE);
      if (it == opts.option.end()) { reject("Native new-timeline-folder option is unavailable"); return; }
      if (clickOption(view, size_t(it-opts.option.begin()), "Save to new folder (same timeline)")) navigationStage = 4;
      return;
    }
    if (clickOption(view, size_t(chosen), "Save to timeline folder: " + pendingFilename)) navigationStage = 3;
  }
}
}
bool start(color_ostream& out) {
  resetInterruption();resetPetition();fortressEpoch=0;interruption={};petition={};notificationGroups={};
  if (region) return true;
  const size_t size = sh::regionSize(m::kSessionCapacity, m::kSessionCommandCapacity);
  mapping = CreateFileMappingA(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, static_cast<DWORD>(size), m::kSessionRegionName);
  if (!mapping) {
    if (mapping) CloseHandle(mapping); mapping = nullptr;
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
  revision = requestSeq = 0; phase = m::SessionPhase::Starting; status = m::LoadRequestStatus::None;
  message.clear(); activeId.clear(); pendingId.clear(); savedId.clear(); saves.clear(); navigationStage = 0;
  action = m::SessionAction::LoadFortress; fortressValid = paused = canSave = canSaveReturn = false;
  year = yearTick = 0; fortName.clear(); lastStatus = {}; saveSawProgress = false;
  observedSaveIds.clear(); previousSaveIds.clear();
  cleanupRequested = false; cleanupFrames = 0;
  publish(); return true;
}
void stop() {
  resetInterruption();resetPetition();fortressEpoch=0;interruption={};petition={};notificationGroups={};
  canSave = canSaveReturn = false;
  if (region) { sh::atomicStoreRelease(&m::sessionOwner(region)->pid, 0); phase = m::SessionPhase::Unavailable; message = "DF session bridge stopped"; publish(); reply.reset(); UnmapViewOfFile(region); }
  if (mapping) CloseHandle(mapping);
  mapping = nullptr; region = nullptr;
}
bool saving() { return region && phase == m::SessionPhase::Saving; }
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
  else { if (phase != m::SessionPhase::Error) phase = m::SessionPhase::Unavailable; if (status != m::LoadRequestStatus::Rejected) message = "Return Dwarf Fortress to its main menu to load a fortress"; }
  fortressValid = mapLoaded && df::global::plotinfo && df::global::world && World::isFortressMode();
  // Pause belongs to the loaded simulation, including object-testing maps;
  // observing it must not grant fortress menus, save eligibility or an epoch.
  paused = mapLoaded && df::global::world && World::ReadPauseState();
  fortressEpoch=fortressValid?epoch:0;
  if(!fortressValid)notificationGroups={};
  const auto now = std::chrono::steady_clock::now();
  if (fortressValid) {
    activeId = df::global::world->loaded_save_path.generic_string();
    if (!activeId.empty()) observedSaveIds.insert(activeId);
    if(summaryEpoch!=fortressEpoch) {summaryEpoch=fortressEpoch;lastStatus={};lastHeader={};population=0;stressCounts={};stressAvailable=false;resourceCounts={};resourcesAvailable=false;}
    if(now-lastHeader>=std::chrono::milliseconds(250)) {
      lastHeader=now;
      refreshPopulation();
    }
    if (now - lastStatus >= std::chrono::milliseconds(250)) {
      lastStatus = now;
      notificationGroups=readNotificationGroups(df::global::world->status.announcement_alert);
      year = df::global::cur_year ? std::max(0, *df::global::cur_year) : 0;
      yearTick = df::global::cur_year_tick ? std::clamp(*df::global::cur_year_tick, 0, 403199) : 0;
      const auto& map=df::global::world->map;
      const auto& food=df::global::plotinfo->tasks.food;
      resourceCounts={food.total,food.drink,food.seeds,food.meat,food.fish,food.plant,food.other};
      resourcesAvailable=std::all_of(resourceCounts.begin(),resourceCounts.end(),[](int32_t value){return value>=0;});
      if(!resourcesAvailable)resourceCounts={};
      elevationOffset=map.region_z-100;levelCount=uint32_t(std::max(0,map.z_count));
      summaryAvailable=stressAvailable && population>=0 && levelCount>0 && levelCount<=65536 && elevationOffset>=-65536 && elevationOffset<=65536;
      auto* site = df::global::plotinfo->main.fortress_site;
      fortName = site ? DF2UTF(Translation::translateName(&site->name, true)) : "";
    }
  } else { activeId.clear(); fortName.clear(); year = yearTick = 0; summaryAvailable=stressAvailable=resourcesAvailable=false;summaryEpoch=0;population=elevationOffset=0;levelCount=0;stressCounts={};resourceCounts={}; }
  if (status == m::LoadRequestStatus::Pending && (action == m::SessionAction::SaveContinue || action == m::SessionAction::SaveReturn) && fortressValid && !m::sessionEpochMatches(pendingSaveEpoch,fortressEpoch)) {
    reject("Fortress changed before save completed"); cleanupRequested=false;
  }
  if (status == m::LoadRequestStatus::Pending && (action == m::SessionAction::SaveContinue || action == m::SessionAction::SaveReturn)) {
    phase = m::SessionPhase::Saving;
    if (action == m::SessionAction::SaveReturn) {
      if (virtual_cast<df::viewscreen_savegamest>(view)) saveSawProgress = true;
      if (title && (navigationStage == 3 || navigationStage == 4)) {
        auto found = std::find_if(title->savegame_header.begin(), title->savegame_header.end(), [](auto* h) {
          return isFort(h) && (navigationStage == 4 ? !previousSaveIds.count(idOf(h)) : h->filename_noext == pendingFilename) &&
              h->world_header.id1 == pendingWorld1 && h->world_header.id2 == pendingWorld2;
        });
        if (found != title->savegame_header.end() && navigationStage == 4) {
          const auto count = std::count_if(title->savegame_header.begin(), title->savegame_header.end(), [](auto* h) {
            return isFort(h) && !previousSaveIds.count(idOf(h)) && h->world_header.id1 == pendingWorld1 && h->world_header.id2 == pendingWorld2;
          });
          if (count != 1) { reject("New save identity is ambiguous; inspect Dwarf Fortress"); found = title->savegame_header.end(); }
        }
        if (found != title->savegame_header.end() && saveSawProgress && !mapLoaded) {
          status = m::LoadRequestStatus::Ok; phase = m::SessionPhase::Menu;
          savedId = idOf(*found);
          message = "Fortress saved to " + (*found)->filename_noext + "; returned to menu"; pendingId.clear(); navigationStage = 0;
          lastDiscovery = {}; discover(title);
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
    if (status == m::LoadRequestStatus::Pending && navigationStage < 3 &&
        now - requestedAt > std::chrono::seconds(15)) {
      reject("Native save dialog was not recognized; save was not started");
    } else if (status == m::LoadRequestStatus::Pending && now - requestedAt > std::chrono::minutes(5)) {
      reject("Save completion is unverified; inspect Dwarf Fortress before closing it");
    }
  } else if (fortressValid && (nativeSaveBusy(view) || cleanupRequested)) phase = m::SessionPhase::Saving;
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
      const auto oldSeq=requestSeq,oldClient=requestClient;const auto oldAction=action;const auto oldStatus=status;
      const auto oldMessage=message,oldSaved=savedId;
      requestSeq=c->seq();requestClient=c->client_id();action=c->action();
      status=m::LoadRequestStatus::Rejected;message="Another client has a session operation in progress";savedId.clear();
      publish(false);
      requestSeq=oldSeq;requestClient=oldClient;action=oldAction;status=oldStatus;message=oldMessage;savedId=oldSaved;
      reply=std::move(activeReply);continue;
    }
    reply=std::move(nextReply);requestClient=c->client_id();requestSeq=c->seq();
    savedId.clear();
    action = c->action();
    if(!m::runtimeSessionAction(action)) {
      reject("Native announcement and petition adapters are retired; semantic replacement unfinished");continue;
    }
    if (action != m::SessionAction::LoadFortress) {
      if(!m::sessionEpochMatches(c->fortress_epoch(),fortressEpoch)) { reject("Fortress changed; save was not started"); continue; }
      pendingSaveEpoch=c->fortress_epoch();
      if (!(action == m::SessionAction::SaveReturn ? canSaveReturn : canSave) || nativeSaveBusy(view)) { reject("Close native DF panels and wait for any current save before saving"); continue; }
      {
        checkpointName = c->checkpoint_name() ? c->checkpoint_name()->str() : "";
        if (action == m::SessionAction::SaveContinue && checkpointExists(checkpointName)) {
          reject("Checkpoint name already exists; choose a new name"); continue;
        }
        pendingId = activeId;
        previousSaveIds = observedSaveIds; previousSaveIds.insert(activeId);
        for (const auto& save : saves) previousSaveIds.insert(save.id);
        auto& current = df::global::world->cur_savegame;
        pendingFilename = current.save_dir; pendingWorld1 = current.world_header.id1; pendingWorld2 = current.world_header.id2;
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
    if (std::chrono::steady_clock::now() - requestedAt > std::chrono::minutes(5)) {
      reject("DF did not finish loading within five minutes; inspect the DF window"); phase = m::SessionPhase::Error;
    } else if (title) navigate(title);
    else if (!loading && !mapLoaded && std::chrono::steady_clock::now() - requestedAt > std::chrono::seconds(15)) {
      auto focus = Gui::getFocusStrings(view);
      reject("DF load needs attention: " + (focus.empty() ? std::string("unknown state") : focus.front())); phase = m::SessionPhase::Error;
    }
  }
  if(phase!=m::SessionPhase::Ready){interruption.canAcknowledge=false;interruption.receipt=0;}
  publish();
}
}
