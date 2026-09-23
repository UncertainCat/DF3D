#pragma once
#include "shm_layout.h"
#include <string>
#include <memory>
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <atomic>

namespace df3d::shm {
// A client owns its private reply mapping. The bridge opens it before accepting
// a request and holds it until completion. No shared result can steal a reply.
struct MailboxOwner {
    volatile uint64_t pid, created, generation, acceptedSeq, clientId;
};
static_assert(sizeof(MailboxOwner) <= sizeof(RegionHeader::reserved), "reply owner must fit reserved header space");
inline MailboxOwner* mailboxOwner(RegionHeader* r) {
    return reinterpret_cast<MailboxOwner*>(r->reserved);
}
inline std::string mailboxName(const std::string& channel, uint64_t generation, uint64_t id) {
    return channel+"_reply_"+std::to_string(generation)+"_"+std::to_string(id);
}
inline uint64_t processCreated(HANDLE process) {
    FILETIME c{},e{},k{},u{};
    return GetProcessTimes(process,&c,&e,&k,&u) ? (uint64_t(c.dwHighDateTime)<<32)|c.dwLowDateTime : 0;
}
class ClientMailbox {
    HANDLE mapping_=nullptr, process_=nullptr;
    RegionHeader* region_=nullptr;
    bool creator_=false;
public:
    ClientMailbox()=default;
    ClientMailbox(const ClientMailbox&)=delete;
    ClientMailbox& operator=(const ClientMailbox&)=delete;
    ~ClientMailbox() { if(creator_ && region_)atomicStoreRelease(&mailboxOwner(region_)->pid,0);if(region_)UnmapViewOfFile(region_);if(mapping_)CloseHandle(mapping_);if(process_)CloseHandle(process_); }
    RegionHeader* region() const { return region_; }
    uint64_t id() const { return atomicLoadAcquire(&mailboxOwner(region_)->clientId); }
    bool accept(uint64_t seq) {
        auto* owner=mailboxOwner(region_);
        if(!seq || seq<=atomicLoadAcquire(&owner->acceptedSeq))return false;
        atomicStoreRelease(&owner->acceptedSeq,seq);return true;
    }
    static std::unique_ptr<ClientMailbox> create(const std::string& channel,uint64_t generation,uint32_t version,uint32_t capacity) {
        static std::atomic<uint64_t> counter{0};
        for(int attempt=0;attempt<16;++attempt) {
            LARGE_INTEGER ticks{};QueryPerformanceCounter(&ticks);
            const uint64_t id=(uint64_t(ticks.QuadPart) ^ (uint64_t(GetCurrentProcessId())<<32) ^ ++counter)&INT64_MAX;
            if(!id)continue;
            auto result=std::make_unique<ClientMailbox>();
            const auto name=mailboxName(channel,generation,id);
            result->mapping_=CreateFileMappingA(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,DWORD(regionSize(capacity,8)),name.c_str());
            if(!result->mapping_)return {};
            if(GetLastError()==ERROR_ALREADY_EXISTS)continue;
            result->region_=static_cast<RegionHeader*>(MapViewOfFile(result->mapping_,FILE_MAP_ALL_ACCESS,0,0,regionSize(capacity,8)));
            if(!result->region_)return {};
            initRegion(result->region_,version,capacity,8);
            result->creator_=true;
            auto* owner=mailboxOwner(result->region_);
            owner->created=processCreated(GetCurrentProcess());owner->generation=generation;owner->clientId=id;
            atomicStoreRelease(&owner->pid,GetCurrentProcessId());return result;
        }
        return {};
    }
    static std::unique_ptr<ClientMailbox> open(const std::string& channel,uint64_t generation,uint64_t id,uint32_t version,uint32_t capacity) {
        if(!id)return {};
        auto result=std::make_unique<ClientMailbox>();
        result->mapping_=OpenFileMappingA(FILE_MAP_ALL_ACCESS,FALSE,mailboxName(channel,generation,id).c_str());
        if(!result->mapping_)return {};
        result->region_=static_cast<RegionHeader*>(MapViewOfFile(result->mapping_,FILE_MAP_ALL_ACCESS,0,0,regionSize(capacity,8)));
        if(!result->region_ || checkRegion(result->region_,version) || result->region_->snapshotCapacity!=capacity || result->region_->commandCapacity!=8)return {};
        auto* owner=mailboxOwner(result->region_);
        if(atomicLoadAcquire(&owner->generation)!=generation || atomicLoadAcquire(&owner->clientId)!=id)return {};
        result->process_=OpenProcess(SYNCHRONIZE|PROCESS_QUERY_LIMITED_INFORMATION,FALSE,DWORD(atomicLoadAcquire(&owner->pid)));
        if(!result->process_ || WaitForSingleObject(result->process_,0)!=WAIT_TIMEOUT ||
           processCreated(result->process_)!=atomicLoadAcquire(&owner->created))return {};
        return result;
    }
};

// Writers serialize only the ring copy/commit. A crashed writer cannot expose
// its partial bytes because pushCommand commits cmdHead last. Consumers never
// acquire this mutex and therefore never wait for a client.
class CommandWriter {
    HANDLE mutex_=nullptr;
public:
    CommandWriter()=default;
    CommandWriter(const CommandWriter&)=delete;
    ~CommandWriter(){if(mutex_)CloseHandle(mutex_);}
    bool open(const std::string& channel,uint64_t generation=0) {
        mutex_=CreateMutexA(nullptr,FALSE,(channel+"_writers_v4_"+std::to_string(generation)).c_str());
        return mutex_!=nullptr;
    }
    bool push(RegionHeader* region,const uint8_t* data,uint32_t size) {
        if(!mutex_)return false;
        const auto acquired=WaitForSingleObject(mutex_,0);
        if(acquired!=WAIT_OBJECT_0 && acquired!=WAIT_ABANDONED)return false;
        const bool result=pushCommand(region,data,size);
        ReleaseMutex(mutex_);return result;
    }
};
}
#endif
