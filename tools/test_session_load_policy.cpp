#include "doctest.h"
#include "../bridge/plugin/session_load_policy.h"

using namespace df3d_session;
using namespace std::chrono_literals;

namespace {
struct LoadFixture {
    std::chrono::steady_clock::time_point requestedAt{123s}, now = requestedAt;
    bool title = true, loading = false, dwarfmode = false, mapLoaded = false;
    int navigationStage = 0;
    std::vector<std::string> focus{"title"};
    LoadStep poll() const {
        return loadStep(now - requestedAt, title, loading, dwarfmode, mapLoaded, navigationStage);
    }
    void at(std::chrono::steady_clock::duration elapsed) { now = requestedAt + elapsed; }
    void issue() {
        navigationStage = 3; title = false; loading = true; focus = {"loadgame"};
    }
    void enterDwarfmode() {
        loading = false; dwarfmode = true; focus = {"dwarfmode/Default"};
    }
};
}

TEST_CASE("session fast and slow loads reach identity verification without rejection") {
    for (const auto completion : {5s, 20s}) {
        CAPTURE(completion.count());
        LoadFixture f;
        CHECK(f.poll() == LoadStep::Navigate);
        f.issue(); f.at(1s);
        CHECK(f.poll() == LoadStep::Loading);
        f.enterDwarfmode(); f.at(completion - 1ms);
        CHECK(f.poll() == LoadStep::Loading);
        CHECK(loadFailureMessage(f.poll(), f.focus).empty());
        f.mapLoaded = true; f.at(completion);
        CHECK(f.poll() == LoadStep::VerifyLoaded);
        CHECK(loadFailureMessage(f.poll(), f.focus).empty());
    }
}

TEST_CASE("session unexpected screen keeps the strict 15 second cutoff and exact reason") {
    LoadFixture f; f.issue(); f.loading = false; f.focus = {"unexpected/screen"};
    f.at(15s);
    CHECK(f.poll() == LoadStep::Loading);
    f.at(15s + 1ms);
    CHECK(f.poll() == LoadStep::NeedsAttention);
    CHECK(loadFailureMessage(f.poll(), f.focus) == "DF load needs attention: unexpected/screen");
    CHECK(loadFailureMessage(f.poll(), {}) == "DF load needs attention: unknown state");
    CHECK(loadFailureMessage(f.poll(), {""}) == "DF load needs attention: ");
    // Focus text is diagnostic only: it cannot substitute for the view type.
    f.focus = {"dwarfmode/Default"};
    CHECK(f.poll() == LoadStep::NeedsAttention);
    CHECK(loadFailureMessage(f.poll(), f.focus) == "DF load needs attention: dwarfmode/Default");
    f.enterDwarfmode();
    for (const auto stage : {-1, 0, 1, 2, 4}) {
        f.navigationStage = stage;
        CHECK(f.poll() == LoadStep::NeedsAttention);
    }
    f.navigationStage = 3;
    CHECK(f.poll() == LoadStep::Loading);
    f.title = true;
    CHECK(f.poll() == LoadStep::Navigate);
    f.title = false; f.dwarfmode = false; f.loading = true;
    CHECK(f.poll() == LoadStep::Loading);
}

TEST_CASE("session five minute cap governs all unfinished load paths") {
    for (const auto screen : {LoadStep::Loading, LoadStep::Navigate}) {
        LoadFixture f; f.issue(); f.enterDwarfmode();
        f.title = screen == LoadStep::Navigate;
        f.at(5min);
        CHECK(f.poll() == screen);
        f.at(5min + 1ms);
        CHECK(f.poll() == LoadStep::TimedOut);
        CHECK(loadFailureMessage(f.poll(), f.focus) ==
              "DF did not finish loading within five minutes; inspect the DF window");
        f.dwarfmode = false; f.title = false; f.loading = true;
        CHECK(f.poll() == LoadStep::TimedOut);
        f.loading = false;
        CHECK(f.poll() == LoadStep::TimedOut); // cap takes priority over attention
        // Existing completion-before-timeout ordering remains intact.
        f.mapLoaded = true;
        CHECK(f.poll() == LoadStep::VerifyLoaded);
    }
}
