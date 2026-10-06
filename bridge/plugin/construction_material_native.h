#pragma once
struct lua_State;
namespace df3d_construction {
// Synchronous safe-point callback; returns only owned scalar results.
int nativeMaterialDistances(lua_State* L);
}
