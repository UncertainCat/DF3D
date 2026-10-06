#include "doctest.h"
#include "../bridge/plugin/session_load_policy.h"
#include "../bridge/plugin/session_save_file.h"
#include <algorithm>
#include <cstdint>
#include <fstream>

TEST_CASE("overwrite completion requires changed nonempty destination file evidence") {
    namespace fs=std::filesystem;
    const auto root=fs::temp_directory_path()/("df3d-save-stamp-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    REQUIRE(fs::create_directory(root));
    struct Cleanup {fs::path root;~Cleanup(){std::error_code e;fs::remove(root/"world.sav",e);fs::remove(root,e);}} cleanup{root};
    CHECK_FALSE(df3d_session::savedWorldStamp(root));
    {std::ofstream out(root/"world.sav",std::ios::binary);out<<"first snapshot";}
    auto before=df3d_session::savedWorldStamp(root);REQUIRE(before);
    CHECK_FALSE(df3d_session::savedWorldChanged(before,df3d_session::savedWorldStamp(root)));
    // Rewriting the same-length payload still needs observable write evidence.
    fs::last_write_time(root/"world.sav",before->modified+std::chrono::seconds(2));
    CHECK(df3d_session::savedWorldChanged(before,df3d_session::savedWorldStamp(root)));
    {std::ofstream out(root/"world.sav",std::ios::binary|std::ios::trunc);out<<"different-length snapshot";}
    fs::last_write_time(root/"world.sav",before->modified);
    CHECK(df3d_session::savedWorldChanged(before,df3d_session::savedWorldStamp(root)));
    {std::ofstream out(root/"world.sav",std::ios::binary|std::ios::trunc);}
    CHECK_FALSE(df3d_session::savedWorldChanged(before,df3d_session::savedWorldStamp(root)));
    fs::remove(root/"world.sav");fs::create_directory(root/"world.sav");
    CHECK_FALSE(df3d_session::savedWorldStamp(root));
    CHECK_FALSE(df3d_session::savedWorldChanged(std::nullopt,before));
}

TEST_CASE("load selects requested timeline among groups sharing world identity") {
    struct Header { uint32_t id1, id2; std::string timeline_name, manual_name; };
    const Header target{2004778519,1401278833,"df3d.timeline-20260930103712xxxxxxxxxxxx",""};
    const std::vector<Header> groups{
        {target.id1,target.id2,"",""},
        {target.id1,target.id2,target.timeline_name,""},
        {target.id1+1,target.id2,target.timeline_name,""},
    };
    auto selected=std::find_if(groups.begin(),groups.end(),[&](const auto& header){
        return df3d_session::sameSaveTimeline(header,target);
    });
    REQUIRE(selected!=groups.end());
    CHECK(selected-groups.begin()==1);
    auto checkpoint=target;checkpoint.manual_name="different manual checkpoint";
    CHECK(df3d_session::sameSaveTimeline(checkpoint,target));
    auto different=target;different.id2++;
    CHECK_FALSE(df3d_session::sameSaveTimeline(different,target));
    different=target;different.timeline_name="DF3D.timeline-20260930103712xxxxxxxxxxxx";
    CHECK_FALSE(df3d_session::sameSaveTimeline(different,target));
}

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
