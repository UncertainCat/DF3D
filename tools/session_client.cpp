#include "wm/session_client.h"
#include <chrono>
#include <iostream>
#include <thread>
int main(int argc, char** argv) {
  std::string error;
  std::unique_ptr<wm::SessionClient> c;
  auto end = std::chrono::steady_clock::now() + std::chrono::minutes(5);
  uint64_t sent = 0; bool listed = false;
  const bool load = argc > 1 && std::string(argv[1]) == "load";
  const bool save = argc > 1 && (std::string(argv[1]) == "save" || std::string(argv[1]) == "save-return");
  const bool returnToMenu = save && std::string(argv[1]) == "save-return";
  const bool statusOnly = argc > 1 && std::string(argv[1]) == "status";
  while (std::chrono::steady_clock::now() < end) {
    if (!c) c = wm::SessionClient::open(error);
    if (c && c->poll()) {
      const auto& s = c->state();
      if (save || statusOnly) {
        std::cout << "SESSION phase=" << int(s.phase) << " seq=" << s.requestSeq << " result=" << int(s.requestStatus)
                  << " paused=" << s.paused << " year=" << s.year << " year_tick=" << s.yearTick
                  << " fort=" << s.fortName << " id=" << s.activeSaveId << " message=" << s.message << std::endl;
        if (statusOnly) return 0;
        if (!sent && s.phase == wm::SessionPhase::Ready) {
          sent = c->sendSave(returnToMenu, !returnToMenu && argc > 2 ? argv[2] : "");
          if (!sent) { std::cerr << c->lastError() << std::endl; return 2; }
          std::cout << "SAVE seq=" << sent << std::endl;
        }
      }
      if (!save && !statusOnly && !listed && s.phase == wm::SessionPhase::Menu) {
        std::cout << "MENU saves=" << s.saves.size() << std::endl;
        for (const auto& save : s.saves) std::cout << save.id << " | " << save.fortName << " | " << save.worldName << " | " << save.year << std::endl;
        listed = true;
        if (!load && !save) return 0;
        if (s.saves.empty()) { std::cerr << "No fort saves"; return 1; }
        // Default last entry deliberately exercises a non-first selection.
        std::string id = argc > 2 ? argv[2] : s.saves.back().id;
        sent = c->sendLoadSave(id);
        if (!sent) { std::cerr << c->lastError(); return 2; }
        std::cout << "LOAD seq=" << sent << " id=" << id << std::endl;
      }
      if (sent && s.requestSeq == sent && s.requestStatus == wm::LoadRequestStatus::Rejected) {
        std::cerr << s.message << std::endl; return 3;
      }
      if (sent && s.requestSeq == sent && s.requestStatus == wm::LoadRequestStatus::Ok &&
          s.phase == (returnToMenu ? wm::SessionPhase::Menu : wm::SessionPhase::Ready)) {
        std::cout << "READY id=" << s.activeSaveId << std::endl; return 0;
      }
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }
  std::cerr << "Timed out: " << (c ? c->lastError() : error) << std::endl; return 4;
}
