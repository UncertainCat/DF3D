// Owned benchmark companion: production buffered reader without Godot/rendering.
#include "wm/buffered_world_client.h"
#include <chrono>
#include <fstream>
#include <thread>
#include <iterator>
#include <iostream>
static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
static void write(const std::string& path,const std::string& json){std::ofstream(path)<<json;}
int main(int argc,char** argv){
 if(argc!=2) return 2;
 const std::string prefix=argv[1];
 std::string error;
 wm::BufferedWorldConfig cfg;cfg.clock=now;cfg.collectTimings=true;
 auto c=wm::BufferedWorldClient::open(cfg,error);if(!c){std::cerr<<error;return 1;}
 const double deadline=now()+300;double next=0;bool ready=false;std::string active;wm::BufferedWorldStats before;
 while(now()<deadline){
  if(auto frame=c->takeReady(now()))c->retire(std::move(frame->model));
  if(now()>=next){next=now()+.1;
   if(!ready && c->stats().published){write(prefix+"-ready.json","{\"ready\":true}");ready=true;}
   std::ifstream in(prefix+"-control.json");std::string value((std::istreambuf_iterator<char>(in)),{});
   auto key=value.find("\"phase\"");if(key!=std::string::npos){
    auto colon=value.find(':',key),begin=value.find('"',colon+1),end=value.find('"',begin+1);
    if(begin!=std::string::npos && end!=std::string::npos){const auto phase=value.substr(begin+1,end-begin-1);
     if(phase!=active){
      if(!active.empty()){
       const auto after=c->stats();const auto& a=after.sourcePublications;const auto& b=before.sourcePublications;
       std::ofstream out(prefix+"-"+active+"-reader.json");
       out<<"{\"accepted\":"<<a.accepted-b.accepted<<",\"missed\":"<<a.missed-b.missed
        <<",\"read_failures\":"<<a.readFailures-b.readFailures<<",\"rejected\":"<<a.rejected-b.rejected
        <<",\"published\":"<<after.published-before.published
        <<",\"gap_events\":"<<a.gapEvents-b.gapEvents<<",\"largest_gap_lifetime\":"<<a.largestGap
        <<",\"coalesced\":"<<after.coalesced-before.coalesced<<",\"ingest_ms\":"<<after.pollMilliseconds-before.pollMilliseconds
        <<",\"capture_accepted\":"<<after.capturedPublications.accepted-before.capturedPublications.accepted
        <<",\"capture_missed\":"<<after.capturedPublications.missed-before.capturedPublications.missed
        <<",\"capture_read_failures\":"<<after.capturedPublications.readFailures-before.capturedPublications.readFailures
        <<",\"capture_rejected\":"<<after.capturedPublications.rejected-before.capturedPublications.rejected
        <<",\"queue_drops\":"<<after.captureQueueDrops-before.captureQueueDrops
        <<",\"peak_pending_snapshots\":"<<after.peakPendingSnapshots
        <<",\"peak_pending_bytes\":"<<after.peakPendingBytes
        <<",\"capture_ms\":"<<after.captureMilliseconds-before.captureMilliseconds
        <<",\"capture_poll_interval_max_ms\":"<<after.capturePollIntervalMaxMs
        <<",\"capture_miss_poll_interval_max_ms\":"<<after.captureMissPollIntervalMaxMs
        <<",\"retirement_ms\":"<<after.retirementMilliseconds-before.retirementMilliseconds
        <<",\"publication_backpressure\":"<<after.publicationBackpressure-before.publicationBackpressure
        <<",\"copy_ms\":"<<after.publicationMilliseconds-before.publicationMilliseconds<<"}";
      }
      active=phase;before=c->stats();write(prefix+"-ack.json","{\"phase\":\""+phase+"\"}");
      if(phase=="quit"){c->stop();return 0;}
     }
    }
   }
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(16));
 }
 return 1;
}
