#pragma once
struct lua_State;
namespace df3d_construction {
// Internal Lua callback: (semantic_reader, start, destination, map_maximum).
// Called synchronously by the construction adapter at the bridge safe point.
int routeTrack(lua_State* state);
// Internal callback: (semantic_reader, validated_ordered_path). Copies current
// job/terrain facts and produces a pure plan; does not reserve or mutate.
int planTrack(lua_State* state);
}
