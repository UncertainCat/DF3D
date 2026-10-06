#pragma once
#include <chrono>
#include <string>
#include <vector>

namespace df3d_session {
// Native title groups distinguish timelines within the same world. World IDs
// alone select the first timeline and can hide the requested save at the next
// navigation step. Names are native identity bytes, not case-folded UI labels.
template<class Header>
bool sameSaveTimeline(const Header& candidate, const Header& target) {
    return candidate.id1 == target.id1 && candidate.id2 == target.id2 &&
           candidate.timeline_name == target.timeline_name;
}

enum class LoadStep { Loading, Navigate, VerifyLoaded, NeedsAttention, TimedOut };

// Called for an issued, pending LoadFortress request. Time is injected so the
// session's monotonic deadlines can be tested without DF or wall-clock waits.
inline LoadStep loadStep(std::chrono::steady_clock::duration elapsed,
                         bool title, bool loading, bool dwarfmode,
                         bool mapLoaded, int navigationStage) {
    // Completion is checked before deadlines by the session; save identity must
    // still match before the request succeeds and the loaded fortress is paused.
    if (mapLoaded) return LoadStep::VerifyLoaded;
    if (elapsed > std::chrono::minutes(5)) return LoadStep::TimedOut;
    if (title) return LoadStep::Navigate;
    // DF 53.16 can enter viewscreen_dwarfmodest before its map is loaded.
    // Title gone + navigationStage == 3 (load issued) + dwarfmode + !mapLoaded
    // is still loading, even without viewscreen_loadgamest. Only other screens
    // with !title && !loading && !mapLoaded get the 15-second attention cutoff.
    if (!loading && !(navigationStage == 3 && dwarfmode) &&
        elapsed > std::chrono::seconds(15)) return LoadStep::NeedsAttention;
    return LoadStep::Loading;
}

inline std::string loadFailureMessage(LoadStep step, const std::vector<std::string>& focus = {}) {
    if (step == LoadStep::TimedOut)
        return "DF did not finish loading within five minutes; inspect the DF window";
    if (step == LoadStep::NeedsAttention)
        return "DF load needs attention: " + (focus.empty() ? std::string("unknown state") : focus.front());
    return {};
}
}
