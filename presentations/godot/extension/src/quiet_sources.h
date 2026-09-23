#pragma once
#include <cstdint>
#include <map>
#include <optional>
#include <set>

namespace df3d_godot {
// ID-only scheduler: replacing a source renews one deadline, never appends
// stale jobs. Removed IDs expire too; no node survives here after deletion.
class QuietSources {
public:
    explicit QuietSources(uint64_t frames = 0) : frames_(frames) {}
    bool contains(uint64_t id) const { return entries_.contains(id); }
    void removed(uint64_t id) { if(frames_) schedule(id, false); }
    bool inserted(uint64_t id) {
        if(!contains(id)) return false;
        schedule(id, true);
        return true;
    }
    void advance() { ++frame_; }
    bool ready() const { return !deadlines_.empty() && deadlines_.begin()->first<=frame_; }
    // A missing value is an expired removal tombstone; callers still budget it.
    std::optional<uint64_t> pop() {
        const auto id=deadlines_.begin()->second;
        const bool present=entries_.at(id).present;
        if(present) --pending_;
        entries_.erase(id);
        deadlines_.erase(deadlines_.begin());
        return present ? std::optional<uint64_t>(id) : std::nullopt;
    }
    size_t pending() const { return pending_; }
    size_t size() const { return entries_.size(); }
    void clear() { entries_.clear(); deadlines_.clear(); pending_=0; frame_=0; }
private:
    struct Entry { uint64_t deadline; bool present; };
    void schedule(uint64_t id, bool present) {
        if(auto it=entries_.find(id);it!=entries_.end()) {
            deadlines_.erase({it->second.deadline,id});
            if(it->second.present) --pending_;
        }
        entries_[id]={frame_+frames_,present};
        deadlines_.insert({frame_+frames_,id});
        if(present) ++pending_;
    }
    uint64_t frames_,frame_=0;
    size_t pending_=0;
    std::map<uint64_t,Entry> entries_;
    std::set<std::pair<uint64_t,uint64_t>> deadlines_;
};
}
