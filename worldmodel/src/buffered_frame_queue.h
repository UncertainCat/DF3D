#pragma once
#include <cassert>
#include <deque>
#include "wm/buffered_world_client.h"

namespace wm::detail {
// Caller owns synchronization. Snapshot count is bounded; each event bundle
// enforces ModelEvents' retention budget. Reliable notifications survive
// coalescing until consumed; overload faults explicitly instead of truncating.
class BufferedFrameQueue {
 public:
  explicit BufferedFrameQueue(size_t capacity) : capacity_(std::max(size_t(2), capacity)) {}
  uint64_t push(std::unique_ptr<BufferedWorldFrame> frame) {
    if (!frames_.empty() && frames_.back()->generation != frame->generation) clear();
    frames_.push_back(std::move(frame));
    uint64_t merged = 0;
    while (frames_.size() > capacity_) { mergeFront(); ++merged; }
    return merged;
  }
  std::unique_ptr<BufferedWorldFrame> take(double now, uint64_t* coalesced = nullptr) {
    if (frames_.empty() || frames_.front()->releaseAt > now) return {};
    while (frames_.size() > 1 && frames_[1]->releaseAt <= now) {
      mergeFront();
      if (coalesced) ++*coalesced;
    }
    auto result = std::move(frames_.front());
    frames_.pop_front();
    return result;
  }
  void clear() {
    for (auto& frame : frames_) retire(std::move(frame->model));
    frames_.clear();
  }
  void retire(std::unique_ptr<WorldModel> model) {
    if (model) retired_.push_back(std::move(model));
  }
  std::vector<std::unique_ptr<WorldModel>> takeRetired() {
    std::vector<std::unique_ptr<WorldModel>> result;
    result.swap(retired_);
    return result;
  }
  size_t size() const { return frames_.size(); }
  size_t retiredCount() const { return retired_.size(); }
  // Ownership transfers only: no model drains, event folds or model destruction.
  // The producer detaches the queue while preparing a publication; consumers
  // observe an empty queue until it returns, rather than waiting on event work.
  BufferedFrameQueue detachFrames() {
    BufferedFrameQueue result(capacity_);
    result.frames_.swap(frames_);
    return result;
  }
  void restoreFrames(BufferedFrameQueue prepared) {
    assert(frames_.empty()); // Only the single producer adds published frames.
    frames_.swap(prepared.frames_);
    collectRetired(prepared);
  }
  // Extract eligible frames under the owner's lock, then call take() on the
  // returned private queue outside that lock to fold skipped notifications.
  BufferedFrameQueue extractReady(double now) {
    BufferedFrameQueue result(capacity_);
    while (!frames_.empty() && frames_.front()->releaseAt <= now) {
      result.frames_.push_back(std::move(frames_.front()));
      frames_.pop_front();
    }
    return result;
  }
  void collectRetired(BufferedFrameQueue& other) {
    for (auto& model : other.retired_) retired_.push_back(std::move(model));
    other.retired_.clear();
  }
 private:
  void mergeFront() {
    auto events = frames_[0]->model->drainAllEvents();
    events.append(frames_[1]->model->drainAllEvents());
    frames_[1]->model->restoreEvents(std::move(events));
    retire(std::move(frames_[0]->model));
    frames_.pop_front();
  }
  std::vector<std::unique_ptr<WorldModel>> retired_;
  size_t capacity_;
  std::deque<std::unique_ptr<BufferedWorldFrame>> frames_;
};
} // namespace wm::detail
