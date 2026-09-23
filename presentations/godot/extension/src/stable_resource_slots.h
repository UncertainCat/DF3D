#pragma once
#include <cstddef>
#include <limits>
#include <map>

namespace df3d_godot {
// Handles never alias an older resource, including after clear(). Physical
// storage contains live resources only, not historical vector tombstones.
// Lookups by handle never throw: a stale or foreign id yields nullptr so
// callers reached through Godot's C ABI can report it instead of aborting.
template<class Resource>
class StableResourceSlots {
    std::map<int, Resource> live_;
    int next_ = 0;
public:
    static constexpr int kInvalid = -1;
    int nextId() const { return next_; }
    // Returns the new handle, or kInvalid once the handle space is exhausted.
    int add(Resource resource) {
        if (next_ == std::numeric_limits<int>::max()) return kInvalid;
        const int id = next_++;
        live_.emplace(id, std::move(resource));
        return id;
    }
    bool contains(int id) const { return live_.contains(id); }
    Resource* find(int id) {
        auto it = live_.find(id);
        return it == live_.end() ? nullptr : &it->second;
    }
    const Resource* find(int id) const {
        auto it = live_.find(id);
        return it == live_.end() ? nullptr : &it->second;
    }
    bool erase(int id) { return live_.erase(id) != 0; }
    void clear() { live_.clear(); }
    size_t size() const { return live_.size(); }
};
}
