#pragma once
#include <map>
#include "wm/world_model.h"

namespace wm::detail {
// Arrival order is authoritative. Revisions can restart after replacement.
template<class Event, class Key>
void mergeLatest(std::vector<Event>& older, std::vector<Event> newer, Key key) {
  std::map<decltype(key(std::declval<Event>())), size_t> slots;
  std::vector<Event> result;
  auto add = [&](auto& events) {
    for (auto& event : events) {
      auto [it, inserted] = slots.emplace(key(event), result.size());
      if (inserted) result.push_back(std::move(event));
      else result[it->second] = std::move(event);
    }
  };
  add(older); add(newer); older = std::move(result);
}

template<class Event>
void mergeEntities(std::vector<Event>& older, std::vector<Event> newer) {
  struct Change { bool existed, exists; Event latest; };
  std::map<decltype(Event{}.id), Change> changes;
  auto add = [&](const auto& events) {
    for (const auto& event : events) {
      auto [it, inserted] = changes.try_emplace(event.id,
          Change{event.change != EntityChange::Added, event.change != EntityChange::Removed, event});
      if (!inserted) {
        it->second.exists = event.change != EntityChange::Removed;
        it->second.latest = event;
      }
    }
  };
  add(older); add(newer); older.clear();
  for (auto& [id, change] : changes) {
    if (!change.existed && !change.exists) continue;
    change.latest.change = !change.exists ? EntityChange::Removed
        : change.existed ? EntityChange::Changed : EntityChange::Added;
    older.push_back(std::move(change.latest));
  }
}
} // namespace wm::detail
