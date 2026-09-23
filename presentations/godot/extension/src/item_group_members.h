#pragma once
#include <cassert>
#include <cstddef>
#include <unordered_map>
#include <vector>

namespace df3d_godot {
// Local GPU ordinals must not follow sorted packed-array indices. Removing one
// item moves only the final member; compaction of the global payload array only
// renames its index and leaves the group's resident ordinal unchanged.
class ItemGroupMembers {
    std::vector<int> values_;
    std::unordered_map<int, std::size_t> ordinals_;
public:
    auto begin() const { return values_.begin(); }
    auto end() const { return values_.end(); }
    std::size_t size() const { return values_.size(); }
    bool empty() const { return values_.empty(); }
    void insert(int value) {
        if (ordinals_.emplace(value, values_.size()).second) values_.push_back(value);
    }
    void erase(int value) {
        const auto found = ordinals_.find(value);
        if (found == ordinals_.end()) return;
        const auto ordinal = found->second;
        const int last = values_.back();
        values_[ordinal] = last;
        ordinals_.at(last) = ordinal;
        values_.pop_back();
        ordinals_.erase(found);
    }
    void rename(int before, int after) {
        if (before == after) return;
        const auto found = ordinals_.find(before);
        assert(found != ordinals_.end() && !ordinals_.count(after));
        const auto ordinal = found->second;
        ordinals_.erase(found);
        ordinals_.emplace(after, ordinal);
        values_[ordinal] = after;
    }
};
}
