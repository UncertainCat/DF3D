#pragma once
#include <algorithm>
#include <cstdint>
#include <map>
#include <optional>
#include <utility>
#include <vector>

namespace df3d::stocks_pages {
// Bounds retained serialization independently of the 512 KiB mailbox. Pages
// leave room for their typed envelope. No game objects or native UI are retained.
inline constexpr uint32_t pageBytes = 256 * 1024;
inline constexpr uint32_t retainedBytes = 64 * 1024 * 1024;
struct Identity {
    uint64_t epoch=0, client=0, request=0;
    bool valid() const { return epoch && client && request; }
    bool operator==(const Identity& b) const {
        return epoch==b.epoch && client==b.client && request==b.request;
    }
};
struct Page {
    Identity identity;
    uint32_t total=0, offset=0;
    std::vector<uint8_t> bytes;
};
inline bool valid(const Page& page) {
    return page.identity.valid() && page.total && page.total<=retainedBytes &&
        page.offset<page.total && page.offset%pageBytes==0 &&
        page.bytes.size()==std::min(pageBytes,page.total-page.offset);
}

// One capture per client; oldest captures are evicted under the global byte
// budget. A missing capture is a failed read, never permission to run it again.
class Store {
    struct Entry { Identity identity;uint64_t age;std::vector<uint8_t> bytes; };
    std::map<uint64_t,Entry> entries_;
    size_t bytes_=0;
    uint64_t epoch_=0, age_=0;
    void erase(std::map<uint64_t,Entry>::iterator it) {
        bytes_-=it->second.bytes.size();entries_.erase(it);
    }
public:
    void clear() { entries_.clear();bytes_=0;epoch_=0;age_=0; }
    void world(uint64_t epoch) { if(epoch_!=epoch){clear();epoch_=epoch;} }
    void retire(uint64_t client) {
        const auto it=entries_.find(client);if(it!=entries_.end())erase(it);
    }
    bool capture(Identity identity,std::vector<uint8_t> bytes) {
        if(!identity.valid() || bytes.empty() || bytes.size()>retainedBytes)return false;
        world(identity.epoch);
        const auto previous=entries_.find(identity.client);
        if(previous!=entries_.end() && previous->second.identity.request>=identity.request)return false;
        retire(identity.client);
        while(bytes_+bytes.size()>retainedBytes) {
            auto oldest=std::min_element(entries_.begin(),entries_.end(),
                [](const auto& a,const auto& b){return a.second.age<b.second.age;});
            erase(oldest);
        }
        bytes_+=bytes.size();entries_.emplace(identity.client,Entry{identity,++age_,std::move(bytes)});
        return true;
    }
    std::optional<Page> read(Identity identity,uint32_t offset) const {
        const auto it=entries_.find(identity.client);
        if(it==entries_.end() || !(it->second.identity==identity))return std::nullopt;
        const auto& bytes=it->second.bytes;
        if(offset>=bytes.size() || offset%pageBytes)return std::nullopt;
        const auto end=std::min(bytes.size(),size_t(offset)+pageBytes);
        return Page{identity,uint32_t(bytes.size()),offset,{bytes.begin()+offset,bytes.begin()+end}};
    }
    size_t retained() const { return bytes_; }
};

// Only a complete capture can leave this assembler. The caller still verifies
// the full FlatBuffer and its original request/action/epoch before decoding it.
class Assembly {
    Identity expected_;
    uint32_t total_=0;
    std::vector<uint8_t> bytes_;
public:
    void reset() { expected_={};total_=0;bytes_.clear(); }
    void begin(Identity expected) { reset();expected_=expected; }
    bool append(const Page& page) {
        if(!valid(page) || !(page.identity==expected_) || page.offset!=bytes_.size() ||
            (total_ && page.total!=total_)) { reset();return false; }
        total_=page.total;
        bytes_.insert(bytes_.end(),page.bytes.begin(),page.bytes.end());
        return true;
    }
    uint32_t nextOffset() const { return uint32_t(bytes_.size()); }
    bool complete() const { return total_ && bytes_.size()==total_; }
    std::optional<std::vector<uint8_t>> take() {
        if(!complete())return std::nullopt;
        auto result=std::move(bytes_);reset();return result;
    }
};
} // namespace df3d::stocks_pages
