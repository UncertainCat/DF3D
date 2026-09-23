// Helpers for building/parsing mirror-layer Command messages (used by
// clients to produce and the bridge to consume), plus the command-path
// constants shared by both sides (schema v6). Header-only,
// C++17-compatible (the MSVC-built bridge includes it).
#pragma once

#include <cstdint>
#include <vector>

#include "mirror_generated.h"

namespace df3d::mirror {

// A request for world-owned state must name the currently loaded world.
// Zero is absence, never a wildcard. Each domain keeps its own explicit
// exceptions (for example management Catalog) and availability rules.
inline bool requestEpochMatches(uint64_t requested, uint64_t current) {
  return current != 0 && requested == current;
}

// DF work priorities: 1 (highest) .. 7 (lowest); DF's default is 4.
inline constexpr uint8_t kMinDigPriority = 1;
inline constexpr uint8_t kMaxDigPriority = 7;
inline constexpr uint8_t kDefaultDigPriority = 4;
// Frames the bridge re-sends a CommandResult (the ring is latest-only, so
// a client polling slower than the bridge publishes would miss a result
// sent once). Consumers keep the first arrival per seq.
inline constexpr uint32_t kCommandResultRepeatFrames = 8;

inline constexpr uint32_t kMaxCommandsPerUpdate = 16;
inline constexpr uint64_t kMaxDesignationTiles = 65536;
inline bool commandEpochMatches(const Command& command, uint64_t epoch) {
  return requestEpochMatches(command.world_epoch(), epoch);
}

namespace detail {
inline std::vector<uint8_t> finishCommand(flatbuffers::FlatBufferBuilder& fbb, uint64_t seq,
                                          CommandPayload type, flatbuffers::Offset<void> payload, uint64_t world_epoch) {
  auto cmd = CreateCommand(fbb, seq, type, payload, world_epoch);
  fbb.Finish(cmd);
  return std::vector<uint8_t>(fbb.GetBufferPointer(), fbb.GetBufferPointer() + fbb.GetSize());
}
}  // namespace detail

inline std::vector<uint8_t> buildSetPauseCommand(uint64_t seq, bool paused, uint64_t world_epoch = 0) {
  flatbuffers::FlatBufferBuilder fbb;
  auto payload = CreateSetPause(fbb, paused);
  return detail::finishCommand(fbb, seq, CommandPayload::SetPause, payload.Union(), world_epoch);
}

inline std::vector<uint8_t> buildDesignateDigCommand(uint64_t seq, const TileRect& rect,
                                                     DigKind kind,
                                                     uint8_t priority = kDefaultDigPriority, bool marker = false, uint8_t mining_mode = 0, int32_t max_z = -1, uint64_t world_epoch = 0) {
  flatbuffers::FlatBufferBuilder fbb;
  auto payload = CreateDesignateDig(fbb, &rect, kind, priority, marker, mining_mode, max_z);
  return detail::finishCommand(fbb, seq, CommandPayload::DesignateDig, payload.Union(), world_epoch);
}

inline std::vector<uint8_t> buildDesignateSmoothCommand(uint64_t seq, const TileRect& rect,
                                                        SmoothKind kind, uint8_t priority = kDefaultDigPriority, bool marker = false, bool from_east = false, bool from_south = false, int32_t max_z = -1, int32_t track_end_z = -1, uint64_t world_epoch = 0) {
  flatbuffers::FlatBufferBuilder fbb;
  auto payload = CreateDesignateSmooth(fbb, &rect, kind, priority, marker, from_east, from_south, max_z, track_end_z);
  return detail::finishCommand(fbb, seq, CommandPayload::DesignateSmooth, payload.Union(), world_epoch);
}

inline std::vector<uint8_t> buildDesignateChopCommand(uint64_t seq, const TileRect& rect,
                                                      bool enable, uint8_t priority = kDefaultDigPriority, bool marker = false, int32_t max_z = -1, uint64_t world_epoch = 0) {
  flatbuffers::FlatBufferBuilder fbb;
  auto payload = CreateDesignateChop(fbb, &rect, enable, priority, marker, max_z);
  return detail::finishCommand(fbb, seq, CommandPayload::DesignateChop, payload.Union(), world_epoch);
}

inline std::vector<uint8_t> buildDesignateGatherCommand(uint64_t seq, const TileRect& rect,
                                                        bool enable, uint8_t priority = kDefaultDigPriority, bool marker = false, int32_t max_z = -1, uint64_t world_epoch = 0) {
  flatbuffers::FlatBufferBuilder fbb;
  auto payload = CreateDesignateGather(fbb, &rect, enable, priority, marker, max_z);
  return detail::finishCommand(fbb, seq, CommandPayload::DesignateGather, payload.Union(), world_epoch);
}

inline std::vector<uint8_t> buildSetItemFlagsCommand(uint64_t seq, uint32_t item,
                                                     OptionalBool forbidden, OptionalBool dump,
                                                     OptionalBool melt, uint64_t world_epoch = 0) {
  flatbuffers::FlatBufferBuilder fbb;
  auto payload = CreateSetItemFlags(fbb, item, forbidden, dump, melt);
  return detail::finishCommand(fbb, seq, CommandPayload::SetItemFlags, payload.Union(), world_epoch);
}

inline std::vector<uint8_t> buildSetBuildingFlagsCommand(uint64_t seq, uint32_t building,
                                                         OptionalBool forbidden, uint64_t world_epoch = 0) {
  flatbuffers::FlatBufferBuilder fbb;
  auto payload = CreateSetBuildingFlags(fbb, building, forbidden);
  return detail::finishCommand(fbb, seq, CommandPayload::SetBuildingFlags, payload.Union(), world_epoch);
}

// Verifies and returns the Command in `bytes`, or nullptr if malformed.
inline const Command* parseCommand(const uint8_t* bytes, size_t len) {
  flatbuffers::Verifier v(bytes, len);
  if (!v.VerifyBuffer<Command>(nullptr)) return nullptr;
  const auto* command = flatbuffers::GetRoot<Command>(bytes);
  if (!command->payload()) return nullptr;
  return command;
}

}  // namespace df3d::mirror
