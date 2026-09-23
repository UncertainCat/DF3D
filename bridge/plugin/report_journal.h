#pragma once
// Pure bounded source journal. Native lookup is kept in simulation_events.cpp.
#include <cstdint>
#include <deque>
#include <string>

namespace df3d_events {
struct ReportObservation {
    uint64_t id=0, tick=0;
    int32_t reportId=-1;
    std::string type;
    int32_t x=-1,y=-1,z=-1,x2=-1,y2=-1,z2=-1;
    bool hasPosition=false, hasSecondary=false;
    uint32_t repeatCount=0;
    int32_t speakerId=-1;
};
struct ReportJournal {
    static constexpr size_t capacity=512;
    static constexpr uint64_t retention=600;
    std::deque<ReportObservation> records;
    uint64_t nextId=1, dropped=0, duplicates=0, continuations=0;
    int32_t lastReport=-1;
    void reset(int32_t baseline=-1) { *this=ReportJournal{}; lastReport=baseline; }
    void expire(uint64_t tick) {
        while (!records.empty() && tick>records.front().tick && tick-records.front().tick>retention)
            records.pop_front();
    }
    bool observe(ReportObservation event, bool continuation) {
        if(event.reportId<=lastReport) { ++duplicates; return false; }
        lastReport=event.reportId;
        if(continuation) { ++continuations; return false; }
        if(event.type.empty()) return false;
        expire(event.tick);
        event.id=nextId++;
        records.push_back(std::move(event));
        if(records.size()>capacity) { records.pop_front(); ++dropped; }
        return true;
    }
};
}
