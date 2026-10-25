#pragma once
struct lua_State;
namespace df3d_construction {
// Synchronous safe-point callback; returns only owned scalar results.
int nativeMaterialDistances(lua_State* L);
// Owned native recipes/candidates; optional cold-cache mode is diagnostic only.
int nativeMaterialRecipe(lua_State* L);
int nativeMaterialCandidates(lua_State* L);
int nativeMaterialRequirements(lua_State* L);
}
