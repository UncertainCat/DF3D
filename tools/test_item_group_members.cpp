#include "doctest.h"
#include "../presentations/godot/extension/src/item_group_members.h"
#include <random>
#include <set>
#include <vector>
using df3d_godot::ItemGroupMembers;
namespace {
std::vector<int> values(const ItemGroupMembers& members) { return {members.begin(), members.end()}; }
}

TEST_CASE("item group members compact in place and preserve membership") {
    ItemGroupMembers members;
    for (int i=0; i<34000; ++i) members.insert(i);
    members.erase(4);
    auto rows=values(members);
    REQUIRE_MESSAGE((rows.size()==33999 && rows[4]==33999), "removal fills one hole with tail");
    for (int i=0; i<33999; ++i) if (i!=4) CHECK_MESSAGE(rows[i]==i, "survivor ordinals unchanged");
    members.rename(33999,4);
    rows=values(members);
    for (int i=0; i<33999; ++i) CHECK_MESSAGE(rows[i]==i, "compaction renames in place");
    members.insert(50000);
    CHECK_MESSAGE(values(members).back()==50000, "new membership appends");
    members.insert(50000);
    CHECK_MESSAGE(members.size()==34000, "repeated payload edits preserve membership");
    std::set<int> reference(members.begin(),members.end());
    std::mt19937 rng(42);
    for (int step=0;step<10000;++step) {
        const int id=int(rng()%35000);
        if (rng()%2) { members.insert(id); reference.insert(id); }
        else { members.erase(id); reference.erase(id); }
        CHECK_MESSAGE(members.size()==reference.size(), "member count matches reference");
    }
    CHECK_MESSAGE(std::set<int>(members.begin(),members.end())==reference, "exact final partition");
    ItemGroupMembers other;
    other.insert(99); other.insert(33999); other.insert(101);
    other.rename(33999,4);
    CHECK_MESSAGE((values(other)==std::vector<int>({99,4,101})), "cross-group rename preserves ordinal");
    for (int value : values(other)) other.erase(value);
    CHECK_MESSAGE(other.empty(), "complete removal");
    other.insert(4);
    CHECK_MESSAGE((values(other)==std::vector<int>({4})), "reappearance starts compact");
}
