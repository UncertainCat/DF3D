// Bounded-work and cursor policies of the bridge (bug-fix regressions):
// glyph delta cursor, retry backoff, appearance eviction, job list stamp,
// resumable rectangle cursor, rescan scheduling.
#include "doctest.h"
#include "../bridge/plugin/appearance_eviction.h"
#include "../bridge/plugin/glyph_cursor.h"
#include "../bridge/plugin/job_list_stamp.h"
#include "../bridge/plugin/rect_cursor.h"
#include "../bridge/plugin/retry_backoff.h"
#include "../bridge/plugin/scan_schedule.h"
#include <unordered_map>
#include "../bridge/plugin/builder_schedule.h"

TEST_CASE("synchronous write counts preserve read budgets without narrowing or underflow") {
    for(uint32_t remaining:{0u,1u,512u,1536u,2048u}) {
        for(uint64_t measured:{uint64_t(0),uint64_t(1),uint64_t(1537),uint64_t(9000),uint64_t(INT64_MAX)}) {
            const auto writeCharge=df3d_builder::readCharge(remaining,measured,true);
            CHECK(writeCharge==0);CHECK(remaining-writeCharge==remaining);
            const auto readCharge=df3d_builder::readCharge(remaining,measured,false);
            CHECK(readCharge<=remaining);
            CHECK(remaining-readCharge==(measured>=remaining?0:remaining-measured));
        }
    }
}
#include "../bridge/plugin/management_helper_owners.h"
#include <array>
#include <vector>

TEST_CASE("glyph cursor advances only after an acknowledged ring publication") {
    namespace gc = df3d_glyph_cursor;
    size_t sent = 3;
    // Attempt 1 builds rows [3,7) and the publication fails: the mark must
    // stay so the retry re-serializes the same rows.
    auto r = gc::rowsToBuild(sent, 7, false);
    CHECK((r.from == 3 && r.to == 7));
    // (failed publish: no afterPublish call)
    r = gc::rowsToBuild(sent, 7, false);
    CHECK_MESSAGE(r.from == 3, "retry after a failed publish must not skip delta rows");
    sent = gc::afterPublish(sent, r.to, true);
    CHECK(sent == 7);
    CHECK_MESSAGE(gc::rowsToBuild(sent, 7, false).from == 7, "nothing left after acknowledgement");
    CHECK_MESSAGE(gc::afterPublish(sent, 9, false) == 7, "a recording Full never advances the ring mark");
    CHECK_MESSAGE(gc::rowsToBuild(sent, 9, true).from == 0, "a Full serializes every material");
    CHECK_MESSAGE(gc::afterPublish(7, 5, true) == 7, "the mark never moves backwards");
}

TEST_CASE("retry backoff attempts once per interval, not once per tick") {
    df3d_retry_backoff::Backoff b;
    CHECK(b.due());
    b.failed(3);
    int attempts = 0;
    for (int tick = 0; tick < 10; ++tick) if (b.due()) { ++attempts; b.failed(3); }
    CHECK_MESSAGE(attempts == 2, "10 ticks with interval 3 after a failure: attempts at ticks 3 and 7");
    b.reset();
    CHECK(b.due());
}

TEST_CASE("appearance eviction is bounded per call and keeps recently seen units") {
    namespace ev = df3d_appearance_eviction;
    struct Entry { int32_t lastSeenFrame = 0; };
    std::unordered_map<int32_t, Entry> units;
    ev::Ring ring;
    for (int32_t id = 0; id < 200; ++id) { units[id].lastSeenFrame = id < 100 ? 0 : 5000; ring.push_back(id); }
    // Frame 5000: ids < 100 are 5000 frames stale, ids >= 100 are current.
    size_t evicted = ev::evict(ring, units, 5000, ev::kTtlFrames, 64);
    CHECK_MESSAGE(evicted == 64, "one call inspects at most 64 entries");
    CHECK(units.size() == 136);
    evicted += ev::evict(ring, units, 5000, ev::kTtlFrames, 64);
    CHECK_MESSAGE(evicted == 100, "the second call finishes the stale ones and starts the fresh ones");
    for (int i = 0; i < 10; ++i) ev::evict(ring, units, 5000, ev::kTtlFrames, 64);
    CHECK_MESSAGE(units.size() == 100, "fresh entries survive any number of rounds");
    CHECK_MESSAGE(ring.size() == 100, "the ring retains exactly the live ids");
    units[120].lastSeenFrame = 9000;  // seen after a rewind: negative age is fresh
    for (int i = 0; i < 4; ++i) ev::evict(ring, units, 5000, ev::kTtlFrames, 64);
    CHECK(units.count(120) == 1);
    units.erase(150);  // externally reset entry: ring tolerates it
    for (int i = 0; i < 4; ++i) ev::evict(ring, units, 5000, ev::kTtlFrames, 64);
    CHECK(ring.size() == 99);
    CHECK_MESSAGE(ev::evict(ring, units, 5000, 0, 64) == 0, "age 0 is not stale (ttl is exclusive)");
    CHECK_MESSAGE(ev::evict(ring, units, 5001, 0, 500) == 98, "ttl 0 evicts every entry one frame old; the rewound one is fresh");
    CHECK((units.size() == 1 && units.count(120) == 1));
}

TEST_CASE("job list stamp changes with any job identity, type, position or flags") {
    using df3d_job_list_stamp::Stamp;
    Stamp a, b;
    a.add(1, 10, 5, 6, 7, 0); a.add(2, 11, 8, 9, 1, 3);
    b.add(1, 10, 5, 6, 7, 0); b.add(2, 11, 8, 9, 1, 3);
    CHECK_MESSAGE(a == b, "identical walks agree");
    Stamp c; c.add(1, 10, 5, 6, 7, 0);
    CHECK_MESSAGE(a != c, "a removed job changes the stamp");
    Stamp d; d.add(1, 10, 5, 6, 7, 0); d.add(2, 12, 8, 9, 1, 3);
    CHECK_MESSAGE(a != d, "a changed job type changes the stamp");
    Stamp e; e.add(1, 10, 5, 6, 7, 0); e.add(2, 11, 8, 9, 1, 7);
    CHECK_MESSAGE(a != e, "changed track flags change the stamp");
    Stamp f; f.add(1, 10, 5, 6, 7, 0); f.add(3, 11, 8, 9, 1, 3);
    CHECK_MESSAGE(a != f, "a replaced job id changes the stamp at equal count");
    Stamp g; g.add(2, 11, 8, 9, 1, 3); g.add(1, 10, 5, 6, 7, 0);
    CHECK_MESSAGE(a != g, "order is part of identity (DF keeps a linked list)");
}

TEST_CASE("rect cursor resumes exactly where a slice stopped") {
    df3d_rect_cursor::Cursor c;
    c.begin(2, 3, 4, 4, 1, 2);
    CHECK(c.total() == 3 * 2 * 2);
    int visited = 0;
    int firstSlice[6][3] = {};
    for (; visited < 6; ++visited) {
        REQUIRE(!c.done);
        firstSlice[visited][0] = c.x; firstSlice[visited][1] = c.y; firstSlice[visited][2] = c.z;
        c.next();
    }
    CHECK((firstSlice[0][0] == 2 && firstSlice[0][1] == 3 && firstSlice[0][2] == 1));
    CHECK((firstSlice[2][0] == 4 && firstSlice[2][1] == 3 && firstSlice[2][2] == 1));
    CHECK((firstSlice[3][0] == 2 && firstSlice[3][1] == 4 && firstSlice[3][2] == 1));
    CHECK_MESSAGE(!c.done, "budget exhausted mid-rect: the command stays pending");
    CHECK((c.x == 2 && c.y == 3 && c.z == 2));
    for (; !c.done; c.next()) ++visited;
    CHECK_MESSAGE(visited == 12, "resuming visits the remainder exactly once");
    df3d_rect_cursor::Cursor empty;
    empty.begin(5, 5, 4, 5, 0, 0);
    CHECK((empty.done && empty.total() == 0));
    df3d_rect_cursor::Cursor one;
    one.begin(5, 5, 5, 5, 3, 3);
    CHECK((!one.done && one.total() == 1));
    one.next();
    CHECK(one.done);
}

TEST_CASE("rescan schedule clamps the slice and spreads a full rescan across updates") {
    namespace ss = df3d_scan_schedule;
    CHECK(ss::clampSlice(0) == 1);
    CHECK(ss::clampSlice(256) == 256);
    CHECK_MESSAGE(ss::clampSlice(1000000) == ss::kMaxSliceBlocks, "`df3d scan <n>` is bounded");
    const uint32_t blocks = 30000;
    CHECK(ss::sliceThisUpdate(256, 0, blocks) == 256);
    CHECK_MESSAGE(ss::sliceThisUpdate(256, 100, blocks) == 100, "the last rescan slice is the remainder");
    uint32_t remaining = blocks, updates = 0, scanned = 0;
    while (remaining) {
        const uint32_t n = ss::sliceThisUpdate(256, remaining, blocks);
        CHECK(n <= ss::kRescanSliceBlocks);
        CHECK(n <= remaining);
        remaining -= n; scanned += n; ++updates;
    }
    CHECK_MESSAGE((scanned == blocks && updates == 30), "a rescan of 30 000 blocks takes 30 updates of 1024");
    CHECK_MESSAGE(ss::sliceThisUpdate(4096, 30000, blocks) == 4096, "a larger configured slice is honoured during a rescan");
    CHECK_MESSAGE(ss::sliceThisUpdate(256, 30000, 100) == 100, "never more than the map has");
}

TEST_CASE("management builders share the request remainder by rotating job kind") {
    struct Entry { bool enabled; };
    const std::array<Entry,5> table{{{true},{true},{true},{false},{false}}};
    uint32_t active=7,start=0;
    std::vector<size_t> order;
    std::array<uint32_t,3> shares{};
    // A request consumed 512 of the global 2048. Every active kind gets 512.
    auto step=[&](size_t kind,uint32_t share) {order.push_back(kind);shares[kind]=share;return share;};
    CHECK(df3d_builder::advance(table,active,start,2048-512,step)==1536);
    CHECK(order==std::vector<size_t>{0,1,2});
    CHECK(shares==std::array<uint32_t,3>{512,512,512});
    order.clear();
    CHECK(df3d_builder::advance(table,active,start,2,step)==2);
    CHECK(order==std::vector<size_t>{1,2});
    order.clear();
    CHECK(df3d_builder::advance(table,active,start,0,step)==0);
    CHECK(order.empty());
    // Reserved/inactive slots must not give kind 0 extra turns at the front.
    start=0;
    for(size_t expected:{0,1,2,0,1,2}) {
        order.clear();df3d_builder::advance(table,active,start,1,step);
        REQUIRE(order.size()==1);CHECK(order.front()==expected);
    }
    // A short job passes all unused steps to the remaining entries.
    start=0;
    CHECK(df3d_builder::advance(table,active,start,2048,[&](size_t kind,uint32_t share) {
        shares[kind]=share;return kind==0 ? 2u : share;
    })==2048);
    CHECK(shares==std::array<uint32_t,3>{683,1023,1023});
    // Failure can clear a whole Lua's bits; later callbacks must not run.
    unsigned calls=0;start=0;
    CHECK(df3d_builder::advance(table,active,start,2048,[&](size_t,uint32_t) {
        ++calls;active=0;return 0u;
    })==0);
    CHECK(calls==1);
}

TEST_CASE("request builder masks follow enabled helper ownership") {
    struct Entry { unsigned action; uint32_t domainMask; bool enabled; };
    std::array<Entry,5> table{{{20,7,true},{20,7,true},{20,7,true},
                             {0,8,false},{28,16,false}}};
    const df3d_management::ManagementHelperOwners helpers;
    using Action=df3d::mirror::ManagementAction;
    auto mask=[&](unsigned action) {
        return df3d_builder::requestMask(table,[&](unsigned owner) {
            return helpers.sameOwner(Action(action),Action(owner));
        });
    };
    CHECK(mask(26)==7);
    CHECK(mask(0)==0);
    CHECK(mask(28)==0);
    table[3].enabled=table[4].enabled=true;
    CHECK(mask(0)==8);
    CHECK(mask(28)==16);
    CHECK(mask(99)==0);
    const uint32_t active=31,reported=8|16;
    CHECK(((active & ~mask(0)) | (reported & mask(0)))==31);
    CHECK(((active & ~mask(26)) | (reported & mask(26)))==24);
}

TEST_CASE("real helper ownership includes endpoints and excludes adjacent domains") {
    const df3d_management::ManagementHelperOwners helpers;
    using A=df3d::mirror::ManagementAction;
    const std::array<std::pair<A,A>,9> ranges{{
        {A::Catalog,A::RemoveConstruction}, {A::AreaCatalog,A::AreaCandidates},
        {A::ProductionList,A::FarmSetCrop}, {A::WorkOrderList,A::WorkOrderCatalog},
        {A::CitizenList,A::WorkDetailMode}, {A::ReportList,A::ReportInspect},
        {A::AgreementList,A::AgreementInspect}, {A::TradeList,A::TradeBring},
        {A::CreatureInspect,A::CreatureInspect}
    }};
    for(const auto& range:ranges) {
        for(int a=int(range.first);a<=int(range.second);++a) {
            CHECK(helpers.sameOwner(A(a),range.first));
            CHECK(helpers.sameOwner(A(a),range.second));
            CHECK_FALSE(helpers.sameOwner(A(a),A(int(range.first)-1)));
            CHECK_FALSE(helpers.sameOwner(A(a),A(int(range.second)+1)));
        }
    }
    CHECK_FALSE(helpers.sameOwner(A(255),A::Catalog));
}
