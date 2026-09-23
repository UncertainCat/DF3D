#include "doctest.h"
#include "../schema/cpp/client_mailbox.h"
#include <cstdlib>
#include <iostream>
#include <set>
#include <string>
#include <vector>

#ifdef _WIN32
namespace {
namespace sh=df3d::shm;
void fail(bool ok,const char* message){if(!ok){std::cerr<<message<<'\n';std::exit(1);}}
struct Message {uint64_t seq;uint64_t check;};
constexpr uint32_t version=918,capacity=512;
}
// Producer / crash child launched by the test below (outside doctest).
int clientMailboxChild(int argc,char** argv) {
    const std::string name=argv[1];
    HANDLE mapping=OpenFileMappingA(FILE_MAP_ALL_ACCESS,FALSE,name.c_str());fail(mapping,"child mapping");
    auto* region=static_cast<sh::RegionHeader*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,0));fail(region,"child view");
    if(argc>2) {
        HANDLE mutex=CreateMutexA(nullptr,FALSE,(name+"_writers_v4_0").c_str());
        fail(WaitForSingleObject(mutex,1000)==WAIT_OBJECT_0,"abandoned writer owns mutex");
        const uint32_t partial=64;std::memcpy(sh::ringData(region),&partial,4);
        // Crash with uncommitted data and held mutex. Windows releases the
        // mutex as abandoned; cmdHead still says no data was published.
        ExitProcess(0);
    }
    sh::CommandWriter writer;fail(writer.open(name),"child writer");
    const auto deadline=GetTickCount64()+10000;
    for(int i=0;i<200;++i) {
        Message value{sh::nextCommandSequence(region),0};value.check=value.seq^0xDEADBEEF;
        while(!writer.push(region,reinterpret_cast<uint8_t*>(&value),sizeof(value))) {
            fail(GetTickCount64()<deadline,"producer deadline");Sleep(0);
        }
        sh::requestEntityFull(region);
    }
    UnmapViewOfFile(region);CloseHandle(mapping);return 0;
}
TEST_CASE("client mailbox: concurrent writers, abandoned mutex, per-client replies") {
    const std::string name="Local\\df3d_multiclient_test_"+std::to_string(GetCurrentProcessId());
    HANDLE mapping=CreateFileMappingA(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,DWORD(sh::regionSize(capacity,capacity)),name.c_str());REQUIRE_MESSAGE(mapping,"mapping");
    auto* region=static_cast<sh::RegionHeader*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,0));REQUIRE_MESSAGE(region,"view");sh::initRegion(region,version,capacity,capacity);
    char exe[MAX_PATH];REQUIRE_MESSAGE(GetModuleFileNameA(nullptr,exe,MAX_PATH)!=0,"executable");
    auto launch=[&](bool abandon) {
        std::string command=std::string("\"")+exe+"\" "+name+(abandon?" abandon":"");
        STARTUPINFOA startup{};startup.cb=sizeof(startup);startup.dwFlags=STARTF_USESHOWWINDOW;startup.wShowWindow=SW_HIDE;
        PROCESS_INFORMATION process{};REQUIRE_MESSAGE(CreateProcessA(nullptr,command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&startup,&process),"child process");
        CloseHandle(process.hThread);return process.hProcess;
    };
    // Keep the kernel mutex alive while its first owner crashes.
    sh::CommandWriter keeper;REQUIRE_MESSAGE(keeper.open(name),"parent writer");
    HANDLE crash=launch(true);REQUIRE_MESSAGE(WaitForSingleObject(crash,5000)==WAIT_OBJECT_0,"crash child completed");CloseHandle(crash);
    CHECK_MESSAGE(sh::atomicLoadAcquire(&region->cmdHead)==0,"partial writer did not commit");
    std::vector<HANDLE> children;for(int i=0;i<4;++i)children.push_back(launch(false));
    std::set<uint64_t> ids;const auto deadline=GetTickCount64()+15000;
    while(ids.size()<800) {
        Message message{};const auto len=sh::popCommand(region,reinterpret_cast<uint8_t*>(&message),sizeof(message));
        REQUIRE_MESSAGE(len!=SIZE_MAX,"ring entry not torn across concurrent writers/wrap");
        if(len){REQUIRE_MESSAGE((len==sizeof(message)&&message.check==(message.seq^0xDEADBEEF)),"payload integrity");REQUIRE_MESSAGE(ids.insert(message.seq).second,"globally unique sequence");}
        else Sleep(0);
        REQUIRE_MESSAGE(GetTickCount64()<deadline,"consumer deadline");
    }
    for(auto child:children){REQUIRE_MESSAGE(WaitForSingleObject(child,5000)==WAIT_OBJECT_0,"producer completed");DWORD code=1;GetExitCodeProcess(child,&code);CHECK_MESSAGE(code==0,"producer passed");CloseHandle(child);}
    CHECK_MESSAGE(sh::atomicLoadAcquire(&region->entityFullRequest)==800,"atomic full requests not lost");
    auto a=sh::ClientMailbox::create(name,99,version,capacity),b=sh::ClientMailbox::create(name,99,version,capacity);
    REQUIRE_MESSAGE((a&&b&&a->id()!=b->id()),"distinct same-process clients");
    auto serverA=sh::ClientMailbox::open(name,99,a->id(),version,capacity);
    auto serverB=sh::ClientMailbox::open(name,99,b->id(),version,capacity);
    REQUIRE_MESSAGE((serverA&&serverB),"validated reply endpoints");
    CHECK_MESSAGE((serverA->accept(1)&&!serverA->accept(1)&&serverB->accept(1)),"dedup is per client");
    CHECK_MESSAGE(!sh::ClientMailbox::open(name,98,a->id(),version,capacity),"old generation cannot attach");
    CHECK_MESSAGE(!sh::ClientMailbox::open(name,99,a->id(),version+1,capacity),"version mismatch rejected");
    const Message answerA{1,11},answerB{1,22};
    CHECK_MESSAGE(sh::publishSnapshot(serverA->region(),reinterpret_cast<const uint8_t*>(&answerA),sizeof(answerA),1),"answer A");
    for(int i=0;i<100;++i)CHECK_MESSAGE(sh::publishSnapshot(serverB->region(),reinterpret_cast<const uint8_t*>(&answerB),sizeof(answerB),i),"answer B");
    Message answer{};CHECK_MESSAGE((sh::readLatestSnapshot(a->region(),reinterpret_cast<uint8_t*>(&answer),sizeof(answer))==sizeof(answer)&&answer.check==11),"A reply survives B publications");
    const auto closedId=b->id();serverB.reset();b.reset();
    CHECK_MESSAGE(!sh::ClientMailbox::open(name,99,closedId,version,capacity),"disconnected client cannot accept work");
    sh::mailboxOwner(a->region())->created=0;
    CHECK_MESSAGE(!sh::ClientMailbox::open(name,99,a->id(),version,capacity),"wrong process creation identity rejected");
    UnmapViewOfFile(region);CloseHandle(mapping);
}
#else
int clientMailboxChild(int,char**){return 0;}
TEST_CASE("client mailbox: Windows IPC test unavailable on this platform"){}
#endif
