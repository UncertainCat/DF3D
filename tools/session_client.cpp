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
  const bool quit = argc > 1 && std::string(argv[1]) == "quit-without-saving";
  const bool destinationsOnly=argc>1 && std::string(argv[1])=="destinations";
  uint64_t catalogSeq=0;
  if(returnToMenu && (argc<3 || (std::string(argv[2])!="existing" && std::string(argv[2])!="new-folder" && std::string(argv[2])!="new-timeline") ||
      (std::string(argv[2])!="new-folder" && argc<4))) {
    std::cerr<<"save-return requires existing <folder>, new-folder, or new-timeline <name>"<<std::endl;return 2;
  }
  while (std::chrono::steady_clock::now() < end) {
    if (!c) c = wm::SessionClient::open(error);
    if (c && c->poll()) {
      const auto& s = c->state();
      if(quit) {
        if(!sent && s.phase==wm::SessionPhase::Ready) {
          sent=c->sendQuitWithoutSaving(s.fortressEpoch);
          if(!sent){std::cerr<<c->lastError()<<std::endl;return 2;}
        } else if(sent && s.requestSeq==sent) {
          if(s.requestStatus==wm::LoadRequestStatus::Rejected || s.requestStatus==wm::LoadRequestStatus::UnknownOutcome) {
            std::cerr<<s.message<<std::endl;return s.requestStatus==wm::LoadRequestStatus::UnknownOutcome?5:3;
          }
          if(s.requestStatus==wm::LoadRequestStatus::Ok && s.phase==wm::SessionPhase::Menu && !s.fortressEpoch && s.savedSaveId.empty()) {
            std::cout<<"QUIT seq="<<sent<<" epoch="<<s.requestFortressEpoch<<std::endl;return 0;
          }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(50));continue;
      }
      if(destinationsOnly || returnToMenu) {
        if(!catalogSeq && s.phase==wm::SessionPhase::Ready) {
          catalogSeq=c->sendReadSaveDestinations(s.fortressEpoch);
          if(!catalogSeq){std::cerr<<c->lastError()<<std::endl;return 2;}
        } else if(!sent && catalogSeq && s.requestSeq==catalogSeq && s.requestStatus==wm::LoadRequestStatus::Ok) {
          const auto& catalog=s.saveDestinations;
          std::cout<<"DESTINATIONS receipt="<<catalog.receipt<<" epoch="<<catalog.fortressEpoch<<" count="<<catalog.destinations.size()<<std::endl;
          for(const auto& destination:catalog.destinations)std::cout<<destination.id<<" | "<<destination.folder<<std::endl;
          if(destinationsOnly)return 0;
          const std::string mode=argv[2];std::string id;std::vector<uint8_t> name;
          if(mode=="existing") {
            for(const auto& destination:catalog.destinations)if(destination.folder==argv[3]){if(!id.empty()){std::cerr<<"Ambiguous folder"<<std::endl;return 2;}id=destination.id;}
            if(id.empty()){std::cerr<<"Folder not in current catalog"<<std::endl;return 2;}
          } else if(mode=="new-timeline") {const std::string text=argv[3];name.assign(text.begin(),text.end());}
          sent=c->sendSaveReturn(s.fortressEpoch,catalog.receipt,mode=="existing"?wm::SaveReturnMode::ExistingDestination:mode=="new-folder"?wm::SaveReturnMode::NewFolder:wm::SaveReturnMode::NewTimeline,id,name);
          if(!sent){std::cerr<<c->lastError()<<std::endl;return 2;}
        } else if((s.requestSeq==catalogSeq || (sent && s.requestSeq==sent)) && (s.requestStatus==wm::LoadRequestStatus::Rejected || s.requestStatus==wm::LoadRequestStatus::UnknownOutcome)) {
          std::cerr<<s.message<<std::endl;return s.requestStatus==wm::LoadRequestStatus::UnknownOutcome?5:3;
        } else if(sent && s.requestSeq==sent && s.requestStatus==wm::LoadRequestStatus::Ok && s.phase==wm::SessionPhase::Menu) {
          std::cout<<"SAVED id="<<s.savedSaveId<<std::endl;return 0;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(50));continue;
      }
      if (save || statusOnly) {
        std::cout << "SESSION phase=" << int(s.phase) << " seq=" << s.requestSeq << " result=" << int(s.requestStatus)
                  << " paused=" << s.paused << " year=" << s.year << " year_tick=" << s.yearTick
                  << " fort=" << s.fortName << " id=" << s.activeSaveId << " message=" << s.message
                  << " epoch=" << s.fortressEpoch << std::endl;
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
      if (sent && s.requestSeq == sent && (s.requestStatus == wm::LoadRequestStatus::Rejected || s.requestStatus == wm::LoadRequestStatus::UnknownOutcome)) {
        std::cerr << s.message << std::endl; return s.requestStatus==wm::LoadRequestStatus::UnknownOutcome?5:3;
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
