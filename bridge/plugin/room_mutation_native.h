#pragma once
#include "room_discovery_native.h"
#include "room_publication.h"
#include "room_undo.h"

namespace df3d_area {
enum class RoomCreationError : uint8_t { None, InvalidPlan, IdsExhausted, Preparation, Publication, Observation };
struct NativeRoomCreation {
  RoomCreationStatus status=RoomCreationStatus::NotStarted;
  RoomCreationError error=RoomCreationError::None;
  RoomPlan plan;
  // Committed: every ID is owned by DF. Unknown: IDs are observation hints only,
  // never permission to replay creation or blindly remove buildings.
  std::vector<int32_t> createdIds;
  std::vector<RoomUndoTarget> undoTargets;
};
// Caller holds one safe point and validates the request epoch before entering.
// Plans from current state, prepares all unpublished owners, then publishes.
// This primitive has no persistent receipt or Undo authority of its own.
// Optional presentation invalidation preparation. Called before any publication
// or deletion; a throwing callback prevents that mutation from starting.
using RoomEffectObserver=void (*)(const Bounds&,int32_t);
NativeRoomCreation createNativeRooms(RoomFurniture kind,const Bounds& selection,int32_t z,RoomEffectObserver effects=nullptr);
// Zero means missing, unsupported or unobservable. Uses semantic fields only.
uint64_t observeNativeRoomRevision(int32_t id);
RoomUndoResult undoNativeRooms(RoomUndoReceipt& receipt,RoomUndoScope scope,uint64_t token,RoomEffectObserver effects=nullptr);
}
