#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>
#include "../src/quiet_sources.h"

using df3d_godot::QuietSources;

TEST_CASE("ordinary sources are immediate; replacements wait for quiet") {
    QuietSources q(3);
    CHECK_FALSE(q.inserted(1));
    q.removed(1);
    CHECK(q.inserted(1));
    CHECK(q.pending()==1);
    q.advance();q.advance();
    CHECK_FALSE(q.ready());
    q.advance();
    REQUIRE(q.ready());
    CHECK(q.pop()==1);
    CHECK(q.size()==0);
}
TEST_CASE("repeated edits renew one entry and removal prevents stale rejoin") {
    QuietSources q(3);
    for(int i=0;i<10000;++i) {
        q.removed(7);CHECK(q.inserted(7));q.advance();
        CHECK(q.size()==1);CHECK(q.pending()==1);CHECK_FALSE(q.ready());
    }
    q.removed(7);
    CHECK(q.pending()==0);
    q.advance();q.advance();q.advance();
    REQUIRE(q.ready());CHECK_FALSE(q.pop().has_value());
    CHECK(q.size()==0);
    CHECK_FALSE(q.inserted(7));
}
TEST_CASE("matching deadlines preserve all IDs and clear resets history") {
    QuietSources q(2);
    for(uint64_t id=0;id<5000;++id) { q.removed(id);CHECK(q.inserted(id)); }
    q.advance();q.advance();
    for(uint64_t id=0;id<5000;++id) { REQUIRE(q.ready());CHECK(q.pop()==id); }
    CHECK(q.size()==0);CHECK(q.pending()==0);
    q.removed(1);q.inserted(1);q.clear();
    CHECK(q.size()==0);CHECK(q.pending()==0);CHECK_FALSE(q.ready());
    CHECK_FALSE(q.inserted(1));
}
TEST_CASE("default policy never delays terrain") {
    QuietSources q;
    q.removed(2);CHECK_FALSE(q.inserted(2));
    q.advance();CHECK_FALSE(q.ready());CHECK(q.size()==0);
}
