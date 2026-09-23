#include <doctest.h>
#include "buffered_frame_queue.h"

namespace {
std::unique_ptr<wm::BufferedWorldFrame> frame(uint64_t sequence, double release,
    uint64_t generation = 0) {
  auto f = std::make_unique<wm::BufferedWorldFrame>();
  f->sequence = sequence; f->releaseAt = release; f->generation = generation;
  f->model = std::make_unique<wm::WorldModel>();
  wm::ModelEvents events;
  events.commands.push_back({sequence, wm::CommandStatus::Ok, "complete", sequence});
  events.lifecycle.push_back({wm::LifecycleEvent::Kind::Appeared, uint32_t(sequence), sequence});
  f->model->restoreEvents(std::move(events));
  return f;
}
}
TEST_CASE("buffered queue delays complete frames and preserves notifications when skipping") {
  wm::detail::BufferedFrameQueue q(4);
  q.push(frame(1, 0.1)); q.push(frame(2, 0.2)); q.push(frame(3, 0.3));
  CHECK_FALSE(q.take(0.099));
  uint64_t coalesced=0;
  auto f = q.take(0.25,&coalesced);
  CHECK(coalesced==1);
  REQUIRE(f); CHECK(f->sequence == 2);
  auto results = f->model->drainCommandResults();
  REQUIRE(results.size() == 2); CHECK(results[0].seq == 1); CHECK(results[1].seq == 2);
  CHECK(f->model->drainCommandResults().empty());
  CHECK(f->model->drainEvents().size() == 2);
  CHECK_FALSE(q.take(0.29));
  f = q.take(0.3); REQUIRE(f); CHECK(f->sequence == 3);
  CHECK(f->model->drainCommandResults().size() == 1);
}
TEST_CASE("buffered queue bounds snapshots without losing reliable results") {
  wm::detail::BufferedFrameQueue q(2);
  q.push(frame(1, 0.1)); q.push(frame(2, 0.2));
  CHECK(q.push(frame(3, 0.3)) == 1); CHECK(q.size() == 2);
  CHECK(q.push(frame(4, 0.4)) == 1); CHECK(q.size() == 2);
  auto f = q.take(1); REQUIRE(f); CHECK(f->sequence == 4);
  auto results = f->model->drainCommandResults(); REQUIRE(results.size() == 4);
  for (size_t i = 0; i < results.size(); ++i) CHECK(results[i].seq == i+1);
}
TEST_CASE("new session flushes delayed state and stale outcomes") {
  wm::detail::BufferedFrameQueue q(4);
  q.push(frame(1, 10, 0)); q.push(frame(2, 0.1, 1));
  auto f = q.take(0.1); REQUIRE(f); CHECK(f->generation == 1);
  auto results = f->model->drainCommandResults(); REQUIRE(results.size() == 1);
  CHECK(results[0].seq == 2);
}

TEST_CASE("coalesced and invalidated model ownership is deferred to worker collection") {
  wm::detail::BufferedFrameQueue q(2);
  auto first = frame(1, 0.1);
  auto* firstModel = first->model.get();
  q.push(std::move(first)); q.push(frame(2, 0.2));
  auto adopted = q.take(1);
  REQUIRE(adopted);
  auto retired = q.takeRetired();
  REQUIRE(retired.size() == 1);
  CHECK(retired[0].get() == firstModel);
  CHECK(q.takeRetired().empty());
  auto* adoptedModel = adopted->model.get();
  q.retire(std::move(adopted->model));
  retired = q.takeRetired();
  REQUIRE(retired.size() == 1); CHECK(retired[0].get() == adoptedModel);
  q.push(frame(3, 10)); q.push(frame(4, 11));
  q.clear(); CHECK(q.size() == 0);
  CHECK(q.takeRetired().size() == 2);
}

TEST_CASE("notification compaction follows latest arrival and net entity membership") {
  wm::ModelEvents events;
  for (int i = 0; i < 1000; ++i) {
    wm::ModelEvents next;
    next.terrain.push_back({{1,2,3}, uint64_t(1000-i), uint64_t(i)});
    next.spatters.push_back({1,2,3});
    next.appearances.push_back({7, uint32_t(1000-i), uint64_t(i)});
    next.itemAppearances.push_back({8, uint32_t(1000-i), uint64_t(i)});
    events.append(std::move(next));
  }
  REQUIRE(events.terrain.size() == 1); CHECK(events.terrain[0].version == 1);
  CHECK(events.spatters.size() == 1);
  REQUIRE(events.appearances.size() == 1); CHECK(events.appearances[0].version == 1);
  CHECK(events.itemAppearances.size() == 1);
  using C = wm::EntityChange;
  for (const auto first : {C::Added, C::Changed, C::Removed}) {
    for (const auto second : {C::Added, C::Changed, C::Removed}) {
      wm::ModelEvents old, next;
      old.items.push_back({first, 9, 99, 1}); old.buildings.push_back({first, 9, 99, 1});
      next.items.push_back({second, 9, 1, 2}); next.buildings.push_back({second, 9, 1, 2});
      old.append(std::move(next));
      if (first == C::Added && second == C::Removed) {
        CHECK(old.items.empty()); CHECK(old.buildings.empty());
      } else {
        const auto expected = second == C::Removed ? C::Removed : first == C::Added ? C::Added : C::Changed;
        REQUIRE(old.items.size() == 1); REQUIRE(old.buildings.size() == 1);
        CHECK(old.items[0].change == expected); CHECK(old.buildings[0].change == expected);
        CHECK(old.items[0].version == 1);
      }
    }
  }
}

TEST_CASE("ordered receipt overload faults explicitly without truncating retained receipts") {
  wm::ModelEvents events;
  events.commands.push_back({1, wm::CommandStatus::Ok, "retained", 1});
  wm::ModelEvents large;
  large.commands.push_back({2, wm::CommandStatus::Ok, std::string(wm::ModelEvents::kMaxRetainedBytes, 'x'), 2});
  CHECK_THROWS_AS(events.append(std::move(large)), std::length_error);
  REQUIRE(events.commands.size() == 1); CHECK(events.commands[0].seq == 1);
}

TEST_CASE("state-only model subscriptions do not retain lifecycle history") {
  wm::WorldModelConfig config; config.collectLifecycleEvents = false;
  wm::WorldModel stateOnly(config), subscribed;
  for (uint64_t tick = 1; tick <= 1000; ++tick) {
    wm::SnapshotData snap; snap.tick = tick; snap.mapSize = {16,16,1};
    if (tick % 2) { wm::UnitObservation unit; unit.id = 7; snap.units.push_back(unit); }
    stateOnly.ingest(snap, double(tick)); subscribed.ingest(snap, double(tick));
  }
  CHECK(stateOnly.drainEvents().empty());
  CHECK(subscribed.drainEvents().size() == 1000);
  stateOnly.resetSession(); CHECK_FALSE(stateOnly.config().collectLifecycleEvents);
}

TEST_CASE("restored notifications compose with subsequently ingested local changes") {
  wm::WorldModel model;
  wm::SnapshotData snap; snap.tick=1; snap.mapSize={16,16,1};
  snap.itemScope=wm::ChangeScope::Full;
  wm::ItemObservation item; item.id=42; snap.items.push_back(item);
  model.ingest(snap,1.0);
  model.restoreEvents(model.drainAllEvents()); // Added is not yet consumed.
  snap.tick=2; snap.items[0].stack=2;
  model.ingest(snap,2.0);
  auto changed=model.drainItemEvents();
  REQUIRE(changed.size()==1); CHECK(changed[0].change==wm::EntityChange::Added);
  CHECK(changed[0].version==2);
  wm::ModelEvents retained; retained.items=std::move(changed);
  model.restoreEvents(std::move(retained));
  snap.tick=3; snap.items.clear(); model.ingest(snap,3.0);
  CHECK(model.drainItemEvents().empty()); // Added then removed before observation.
}
