#include "wm/world_model.h"
#include "event_coalescing.h"
#include <stdexcept>

namespace wm {
size_t ModelEvents::retainedBytes() const {
  size_t bytes = lifecycle.size()*sizeof(LifecycleEvent) + terrain.size()*sizeof(TerrainBlockEvent)
      + spatters.size()*sizeof(BlockPos) + appearances.size()*sizeof(AppearanceEvent)
      + buildings.size()*sizeof(BuildingEvent) + items.size()*sizeof(ItemEvent)
      + itemAppearances.size()*sizeof(ItemAppearanceEvent) + commands.size()*sizeof(CommandResult);
  for (const auto& command : commands) bytes += command.message.size();
  return bytes;
}

void ModelEvents::append(ModelEvents newer) {
  // A stalled consumer cannot retain unlimited ordered receipts. Explicitly
  // fault the connection rather than silently truncate or replay a command.
  auto reliableBytes = [](const ModelEvents& events) {
    size_t bytes = events.lifecycle.size()*sizeof(LifecycleEvent) + events.commands.size()*sizeof(CommandResult);
    for (const auto& command : events.commands) bytes += command.message.size();
    return bytes;
  };
  if (reliableBytes(*this) + reliableBytes(newer) > kMaxRetainedBytes)
    throw std::length_error("event backlog exceeded 32 MiB; command outcomes may be unknown; reconnect without replay");
  detail::mergeLatest(terrain, std::move(newer.terrain), [](const auto& e) { return e.pos; });
  detail::mergeLatest(spatters, std::move(newer.spatters), [](const auto& e) { return e; });
  detail::mergeLatest(appearances, std::move(newer.appearances), [](const auto& e) { return e.id; });
  detail::mergeLatest(itemAppearances, std::move(newer.itemAppearances), [](const auto& e) { return e.id; });
  detail::mergeEntities(buildings, std::move(newer.buildings));
  detail::mergeEntities(items, std::move(newer.items));
  auto appendOrdered = [](auto& to, auto& from) {
    if (to.empty()) to = std::move(from);
    else to.insert(to.end(), std::make_move_iterator(from.begin()), std::make_move_iterator(from.end()));
  };
  appendOrdered(lifecycle, newer.lifecycle);
  appendOrdered(commands, newer.commands);
  if (retainedBytes() > kMaxRetainedBytes)
    throw std::length_error("event backlog exceeded 32 MiB; refresh complete state before continuing");
}
} // namespace wm
