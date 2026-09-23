// Sprite resource handles: a stale, erased or foreign id must be a null
// lookup, never an exception. The extension's bound methods run under
// Godot's C ABI, where an escaping exception terminates the process.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>
#include "../src/stable_resource_slots.h"

#include <string>

using df3d_godot::StableResourceSlots;

TEST_CASE("live handles resolve; stale, erased and foreign handles are null") {
    StableResourceSlots<std::string> slots;
    const int a = slots.add("a");
    const int b = slots.add("b");
    CHECK(a != b);
    REQUIRE(slots.find(a) != nullptr);
    CHECK(*slots.find(a) == "a");
    CHECK(*slots.find(b) == "b");
    CHECK(slots.size() == 2);

    // Never issued.
    CHECK(slots.find(-1) == nullptr);
    CHECK(slots.find(slots.nextId()) == nullptr);
    CHECK(slots.find(1 << 30) == nullptr);
    CHECK_FALSE(slots.contains(-1));

    // Erased: false the second time, and the handle stays dead.
    CHECK(slots.erase(a));
    CHECK_FALSE(slots.erase(a));
    CHECK(slots.find(a) == nullptr);
    CHECK_FALSE(slots.contains(a));
    CHECK(slots.find(b) != nullptr);
    CHECK(slots.size() == 1);

    // A new resource never reuses the erased handle.
    const int c = slots.add("c");
    CHECK(c != a);
    CHECK(c > b);
    CHECK(slots.find(a) == nullptr);
    CHECK(*slots.find(c) == "c");

    // clear() retires every handle; later handles keep counting up.
    slots.clear();
    CHECK(slots.size() == 0);
    CHECK(slots.find(b) == nullptr);
    CHECK(slots.find(c) == nullptr);
    const int d = slots.add("d");
    CHECK(d > c);
    CHECK(slots.find(c) == nullptr);
    CHECK(*slots.find(d) == "d");
}

TEST_CASE("const lookups match mutable lookups") {
    StableResourceSlots<int> slots;
    const int id = slots.add(7);
    const auto& view = slots;
    REQUIRE(view.find(id) != nullptr);
    CHECK(*view.find(id) == 7);
    CHECK(view.find(id + 1) == nullptr);
    *slots.find(id) = 9;
    CHECK(*view.find(id) == 9);
}
