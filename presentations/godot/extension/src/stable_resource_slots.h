#pragma once
#include <limits>
#include <map>
#include <stdexcept>

namespace df3d_godot {
// Handles never alias an older resource, including after clear(). Physical
// storage contains live resources only, not historical vector tombstones.
template<class Resource>
class StableResourceSlots {
    std::map<int, Resource> live_;
    int next_ = 0;
public:
    int nextId() const { return next_; }
    int add(Resource resource) {
        if (next_ == std::numeric_limits<int>::max())
            throw std::length_error("sprite resource handle space exhausted");
        const int id = next_++;
        live_.emplace(id, std::move(resource));
        return id;
    }
    bool contains(int id) const { return live_.contains(id); }
    Resource& operator[](int id) { return live_.at(id); }
    const Resource& operator[](int id) const { return live_.at(id); }
    bool erase(int id) { return live_.erase(id) != 0; }
    void clear() { live_.clear(); }
    size_t size() const { return live_.size(); }
};
}
