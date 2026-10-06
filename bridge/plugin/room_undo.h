#pragma once
#include <cstddef>
#include <cstdint>
#include <climits>
#include <utility>
#include <vector>

namespace df3d_area {
struct RoomUndoScope {uint64_t epoch=0,client=0,interaction=0;};
struct RoomUndoTarget {int32_t id=-1;uint64_t revision=0;};
struct RoomUndoInstall {bool accepted=false;uint64_t token=0;};
enum class RoomUndoStatus : uint8_t { Rejected, Stale, Completed, Unknown };
struct RoomUndoResult {RoomUndoStatus status=RoomUndoStatus::Rejected;size_t removed=0;};

class RoomUndoReceipt {
  RoomUndoScope scope_;
  uint64_t token_=0,next_=1;
  std::vector<RoomUndoTarget> targets_;
public:
  RoomUndoReceipt()=default;
  // Authority belongs to one manager instance. Copying would duplicate deletion
  // permission; default moving would leave the source token live.
  RoomUndoReceipt(const RoomUndoReceipt&)=delete;
  RoomUndoReceipt& operator=(const RoomUndoReceipt&)=delete;
  RoomUndoReceipt(RoomUndoReceipt&&)=delete;
  RoomUndoReceipt& operator=(RoomUndoReceipt&&)=delete;
  void clear() noexcept {token_=0;scope_={};targets_.clear();}
  void finish(RoomUndoScope scope) noexcept {
    if(scope.epoch==scope_.epoch && scope.client==scope_.client && scope.interaction==scope_.interaction)clear();
  }
  // Completed empty/rejected selections replace older history too. IDs arrive
  // in monotonically allocated native creation order. Moving preallocated
  // storage into the receipt requires no post-publication allocation.
  RoomUndoInstall replace(RoomUndoScope scope,std::vector<RoomUndoTarget>&& targets) noexcept {
    clear();
    if(!scope.epoch || !scope.client || !scope.interaction)return {};
    int32_t previous=-1;
    for(const auto& target:targets) {
      if(target.id<=previous || !target.revision || target.revision>uint64_t(INT64_MAX))return {};
      previous=target.id;
    }
    if(targets.empty())return {true,0};
    if(next_>uint64_t(INT64_MAX))return {};
    targets_=std::move(targets);scope_=scope;token_=next_++;
    return {true,token_};
  }
  bool matches(RoomUndoScope scope,uint64_t token) const noexcept {
    return token && token==token_ && scope.epoch==scope_.epoch &&
      scope.client==scope_.client && scope.interaction==scope_.interaction;
  }
  // Caller holds one safe point across observation and removal. No pointers
  // persist in the receipt. Validate the entire set before the first deletion.
  template<class Observe,class Remove>
  RoomUndoResult undo(RoomUndoScope scope,uint64_t token,Observe observe,Remove remove) {
    if(!matches(scope,token))return {};
    try {
      for(const auto& target:targets_)if(observe(target.id)!=target.revision) {
        clear();return {RoomUndoStatus::Stale,0};
      }
    } catch(...) {clear();return {RoomUndoStatus::Stale,0};}
    auto targets=std::move(targets_);
    clear(); // consume authority before any deletion, including uncertain failures
    size_t removed=0;
    for(const auto& target:targets) {
      try {if(!remove(target.id))return {RoomUndoStatus::Unknown,removed};}
      catch(...) {return {RoomUndoStatus::Unknown,removed};}
      ++removed;
    }
    return {RoomUndoStatus::Completed,removed};
  }
};
}
