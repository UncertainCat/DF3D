#pragma once
#include <algorithm>
#include <cstdint>
#include <deque>
#include <map>
#include <utility>
#include <string>
#include <vector>
namespace df3d_contact {
// Pointer-free assembler shared by the bridge and portable regression tests.
// Occurrences are native invocation identities, never action or animation IDs.
// Nested invocations may finish in reverse order; publication remains ID-ordered.
template<class Item> class AttackAssembler {
public:
    struct Position {int32_t x=0,y=0,z=0;};
    struct Contact {Item first,second;};
    struct WoundPart {
        int32_t body_part_id=-1,layer_id=-1;
        std::string token,category;
        uint32_t damage=0,anatomy=0;
    };
    struct Wound {
        int32_t id=-1,victim=-1;
        bool severed=false,popped=false,parts_complete=true;
        std::vector<WoundPart> parts;
    };
    struct Record {
        uint64_t id=0,tick=0;
        int32_t attacker=-1,defender=-1,action=-1;
        Item weapon;
        Position pos;
        std::vector<Contact> contacts;
        bool complete=true;
        uint32_t native_events=0;
        int32_t timer1=0,timer2=0;
        std::vector<Wound> wounds;
        bool wounds_complete=true;
        uint8_t outcome=0;
        bool outcome_complete=false,weapon_context_complete=false;
    };
    static constexpr size_t MaxPending=32,MaxContacts=100,MaxRecords=512;
    static constexpr uint64_t MaxAge=600;
    bool begin(Record record) {
        if(!record.id || pending_.count(record.id))return false;
        if(pending_.size()>=MaxPending){++dropped_;return false;}
        pending_.emplace(record.id,std::move(record));return true;
    }
    void contact(uint64_t id,Item first,Item second) {
        auto found=pending_.find(id);if(found==pending_.end())return;
        auto& record=found->second;
        if(first.id<0 || second.id<0 || first.id==second.id){record.complete=false;return;}
        if(std::any_of(record.contacts.begin(),record.contacts.end(),[&](const Contact& c){return c.first.id==first.id && c.second.id==second.id;}))return;
        if(record.contacts.size()==MaxContacts){record.complete=false;return;}
        record.contacts.push_back({std::move(first),std::move(second)});
    }
    void wound(uint64_t id,Wound wound) {
        auto found=pending_.find(id);if(found==pending_.end())return;
        auto& record=found->second;
        if(wound.id<0 || wound.victim!=record.defender){record.wounds_complete=false;return;}
        if(std::any_of(record.wounds.begin(),record.wounds.end(),[&](const Wound& w){return w.id==wound.id && w.victim==wound.victim;}))return;
        if(record.wounds.size()>=128){record.wounds_complete=false;return;}
        size_t used=0;for(const auto& w:record.wounds)used+=w.parts.size();
        if(wound.parts.size()>128-used){wound.parts.resize(128-used);wound.parts_complete=false;}
        record.wounds.push_back(std::move(wound));
    }
    bool end(uint64_t id,bool complete,uint32_t nativeEvents=0,bool woundsComplete=false,uint8_t outcome=0,bool outcomeComplete=false) {
        auto found=pending_.find(id);if(found==pending_.end())return false;
        Record record=std::move(found->second);pending_.erase(found);
        record.complete=record.complete && complete;record.native_events=nativeEvents;
        record.wounds_complete=record.wounds_complete && woundsComplete;
        record.outcome=outcome;record.outcome_complete=outcomeComplete;
        auto at=std::lower_bound(records_.begin(),records_.end(),id,[](const Record& r,uint64_t value){return r.id<value;});
        if(at!=records_.end() && at->id==id)return false;
        records_.insert(at,std::move(record));
        while(records_.size()>MaxRecords){records_.pop_front();++dropped_;}
        return true;
    }
    void prune(uint64_t tick){while(!records_.empty() && tick>records_.front().tick && tick-records_.front().tick>MaxAge)records_.pop_front();}
    void cancelPending(){dropped_+=pending_.size();pending_.clear();}
    void reset(){pending_.clear();records_.clear();dropped_=0;}
    const std::deque<Record>& records() const{return records_;}
    uint64_t dropped() const{return dropped_;}
    size_t pending() const{return pending_.size();}
private:
    std::map<uint64_t,Record> pending_;
    std::deque<Record> records_;
    uint64_t dropped_=0;
};
}
