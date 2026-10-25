#pragma once
#include <cstdint>
#include <string>
#include <vector>
struct lua_State;
namespace df3d_construction {
// Safe-point native support check, not full placement. -1 unknown, otherwise
// build_square_type: support codes, or diagnostic farm/road terrain codes
// 6 (blocked),19 (existing construction),20 (soil/mud),21 (soil). Surface, FloorTerrain,
// OpenTerrain, SinglePerimeter and BridgePerimeter are separate stages, not complete placement.
int siteSupport(const std::string& family,int32_t x,int32_t y,int32_t z,bool* randomAdvanced=nullptr,int32_t width=1,int32_t height=1);
// Diagnostic construction terrain/liquid stage with explicit selection bounds; not complete placement.
int constructionTerrain(int32_t x,int32_t y,int32_t z,int32_t subtype,int32_t x1=-1,int32_t y1=-1,int32_t width=1,int32_t height=1);
// Track routing's modes0/1/4; hidden-endpoint policy belongs to the route caller.
int trackTerrain(int32_t x,int32_t y,int32_t z);
// Protected capture only: requires paused native Track menu; no runtime callers.
int trackTerrainOracle(int32_t x,int32_t y,int32_t z);
// Owned-request native farm/road connectivity with the outer terrain precondition.
// 22 means Disconnected; 0 can also mean no qualifying terrain (validated separately).
int areaConnectivity(const std::string& family,int32_t x,int32_t y,int32_t z,int32_t width,int32_t height);
// Diagnostic Bridge tile, with caller-owned raising-edge membership.
int bridgeTile(int32_t x,int32_t y,int32_t z,bool anchor);
// Diagnostic machinery/magma tile stage with owned native mode selection.
int specialTile(const std::string& key,int32_t x,int32_t y,int32_t z,bool openTerrain);
// Diagnostic mode0/mode1 tile stage; AnimalTrap perimeter is separate.
int openingTile(const std::string& family,int32_t x,int32_t y,int32_t z);
// Verified mode0 furniture tile check; no native menu inputs.
int furnitureTile(const std::string& family,int32_t x,int32_t y,int32_t z);
// Verified explicitly admitted ordinary floor recipe tile stage.
int ordinaryTile(const std::string& key,int32_t x,int32_t y,int32_t z);
// Full farm/road tile stage, retaining the separate raw terrain result for SKIP.
int extentTile(const std::string& family,int32_t x,int32_t y,int32_t z,int* rawTerrain=nullptr);
// Native farm warning over caller-owned validated tiles (x-major/y-minor).
// 1 warns, 0 does not, -1 unknown. Eligibility is a separate placement result.
int farmWarning(int32_t x,int32_t y,int32_t z,int32_t width,int32_t height,const std::vector<uint8_t>& eligible);
// Native inline TEST mask against owned flags:0 accepted,1 missing trigger,-1 unknown.
int pressureTrigger(uint32_t flags);
// Native vertical-bar adjacency: N=1,S=2,W=4,E=8; -1 unsupported.
// Caller owns a safe point. No menu, draw routine or graphics-cache access.
int verticalBarsConnections(int32_t x,int32_t y,int32_t z);
int nativeSiteSupport(lua_State* L);
}
