#include <doctest.h>
#include "buffered_frame_queue.h"

namespace {
std::unique_ptr<wm::BufferedWorldFrame> queuedFrame(uint64_t sequence, double release) {
  auto frame = std::make_unique<wm::BufferedWorldFrame>();
  frame->sequence = sequence;
  frame->releaseAt = release;
  frame->model = std::make_unique<wm::WorldModel>();
  wm::ModelEvents events;
  events.commands.push_back({sequence, wm::CommandStatus::Ok, "complete", sequence});
  frame->model->restoreEvents(std::move(events));
  return frame;
}
}

TEST_CASE("producer folds detached state without retaining published queue ownership") {
  wm::detail::BufferedFrameQueue published(2);
  published.push(queuedFrame(1, 0.1));
  published.push(queuedFrame(2, 0.2));
  auto prepared = published.detachFrames();
  CHECK(published.size() == 0);
  CHECK_FALSE(published.take(1));
  CHECK(prepared.size() == 2);
  CHECK(prepared.push(queuedFrame(3, 0.3)) == 1);
  CHECK(prepared.retiredCount() == 1);
  published.restoreFrames(std::move(prepared));
  CHECK(published.size() == 2);
  CHECK(published.retiredCount() == 1);
  auto result = published.take(1);
  REQUIRE(result);
  const auto receipts = result->model->drainCommandResults();
  REQUIRE(receipts.size() == 3);
  for (size_t i = 0; i < receipts.size(); ++i) CHECK(receipts[i].seq == i + 1);
}

TEST_CASE("ready extraction transfers handles and delays folding until privately owned") {
  wm::detail::BufferedFrameQueue published(4);
  published.push(queuedFrame(1, 0.1));
  published.push(queuedFrame(2, 0.2));
  published.push(queuedFrame(3, 0.3));
  auto ready = published.extractReady(0.25);
  CHECK(ready.size() == 2);
  CHECK(ready.retiredCount() == 0);
  CHECK(published.size() == 1);
  CHECK_FALSE(published.take(0.25));
  uint64_t coalesced = 0;
  auto result = ready.take(0.25, &coalesced);
  REQUIRE(result);
  CHECK(result->sequence == 2);
  CHECK(coalesced == 1);
  CHECK(ready.retiredCount() == 1);
  CHECK(result->model->drainCommandResults().size() == 2);
  published.collectRetired(ready);
  CHECK(ready.retiredCount() == 0);
  CHECK(published.takeRetired().size() == 1);
  result = published.take(0.3);
  REQUIRE(result);
  const auto receipts = result->model->drainCommandResults();
  REQUIRE(receipts.size() == 1);
  CHECK(receipts[0].seq == 3);
}
