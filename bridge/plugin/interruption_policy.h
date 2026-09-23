#pragma once
#include <cstdint>
#include <string>
#include <vector>
namespace df3d_session {
// Opaque process-local identities are compared only; never dereferenced or serialized.
struct PopupIdentity {
  std::vector<uintptr_t> queue;
  std::string text;
  int32_t portrait=-1;
  int16_t color=0;bool bright=false;
  bool complete=true;
  bool operator==(const PopupIdentity& o)const{return queue==o.queue&&text==o.text&&portrait==o.portrait&&color==o.color&&bright==o.bright&&complete==o.complete;}
};
class InterruptionReceipt {
 public:
  uint64_t observe(uint64_t epoch,const PopupIdentity& current,bool allowed) {
    allowed=allowed&&current.complete&&!current.queue.empty();
    if(epoch!=epoch_ || !(current==current_) || allowed!=allowed_) {
      epoch_=epoch;current_=current;allowed_=allowed;receipt_=allowed&&epoch?++counter_:0;
    }
    return pending_?0:receipt_;
  }
  bool consume(uint64_t epoch,uint64_t receipt) {
    if(pending_||!allowed_||!receipt||receipt!=receipt_||epoch!=epoch_)return false;
    before_=current_.queue;consumedEpoch_=epoch;pending_=true;receipt_=0;allowed_=false;return true;
  }
  bool transitioned(uint64_t epoch,const PopupIdentity& current)const {
    return pending_&&current.complete&&epoch==consumedEpoch_&&before_.size()==current.queue.size()+1&&
      std::vector<uintptr_t>(before_.begin()+1,before_.end())==current.queue;
  }
  void finish(){pending_=false;allowed_=false;receipt_=0;current_={};}
  bool pending()const{return pending_;}
 private:
  uint64_t epoch_=0,counter_=0,receipt_=0,consumedEpoch_=0;
  bool allowed_=false,pending_=false;
  PopupIdentity current_;
  std::vector<uintptr_t> before_;
};
}
