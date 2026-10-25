#pragma once
#include "df/stockpile_settings.h"
#include <optional>
#include <array>
#include <string>
#include <vector>
namespace df {struct building;struct building_stockpilest;}

namespace df3d_area {
// Prepares owned endpoint vectors with native sorted insert/erase routines, then
// publishes both ends together. nullopt rejects without mutation; false is the
// native duplicate no-op. No native link interface or menu state is consulted.
std::optional<bool> nativeStockpileLink(df::building& source,
    df::building_stockpilest& target,bool give,bool unlink);
// Scalar native placement predicates; no map, UI or mutable scratch inputs.
std::optional<bool> nativeStockpileTileType(uint16_t tile);
// Safe-point diagnostic/service building block. The caller bounds raw counts.
// Returns independently owned settings; never edits the source or native UI.
std::optional<df::stockpile_settings> nativeStockpilePreset(
    const df::stockpile_settings& source, int preset);
// Native coordinate/extent predicate shared by preset and storage bounds.
std::optional<int32_t> nativeStockpileTileCount(df::building_stockpilest& pile);
// Validate before publishing a new footprint. Cleanup uses DF's coordinate
// predicate and native item assignment method; no UI state is accessed.
bool nativeStockpileRepaintReady(df::building_stockpilest& pile);
bool nativeStockpileRepaintCleanup(df::building_stockpilest& pile);
// Native ownership lookup and immediate removal used by paint transfers.
// nullopt means unsupported; an engaged null pointer means no stockpile owner.
std::optional<df::building_stockpilest*> nativeStockpileAt(int16_t x,int16_t y,int16_t z);
bool nativeStockpileTransferReady();
// Requires an already empty donor. Destroys the object on success.
bool nativeStockpileRemoveEmpty(df::building_stockpilest& pile);
bool nativeStockpileCreateReady();
// The native constructor allocates an ID and registers in world.buildings.all.
// Caller prepares all inputs before this call, then supplies bounds/settings and
// the owned extent allocation before completing publication at the safe point.
df::building_stockpilest* nativeStockpileAllocate();
bool nativeStockpileComplete(df::building_stockpilest& pile);
std::optional<std::array<int16_t,3>> nativeStockpilePresetContainers(
    df::building_stockpilest& pile, int preset);
// New unpublished pile: constructor defaults followed by native category setup.
std::optional<df::stockpile_settings> nativeStockpileInitialSettings(uint32_t categories);
// Read-only preparation for selecting one category. A disabled category gets
// native-sized empty filters; an already enabled category keeps its settings.
std::optional<df::stockpile_settings> nativeStockpileCategory(
    const df::stockpile_settings& source,uint32_t category);
// Category header All/None, or global header when category is zero. These are
// distinct from presets and activation: category headers preserve vector sizes
// and flags; global None also preserves misc allowances.
std::optional<df::stockpile_settings> nativeStockpileHeader(
    const df::stockpile_settings& source,uint32_t category,bool enabled);
struct NativeStockpileSummaries {
    std::array<uint8_t,109> states{}; // Indexed by stockpile_list; parent slots unused.
    std::array<uint8_t,17> categories{}; // Wire category-bit order.
};
// Query only the requested category bits. Disabled root indicators stay none;
// their unrequested storage is neither interpreted nor required to be populated.
std::optional<NativeStockpileSummaries> nativeStockpileSummaries(
    const df::stockpile_settings& source,uint32_t categories=0x1ffff);
struct NativeStockpileRow {
    size_t index;
    std::string name;
    bool enabled, visible;
    std::string field;
};
struct NativeStockpileSettingRange {
    std::string field;
    const void* begin;
    size_t count;
};
// Caller-owned settings and address ranges remain local to this safe-point call.
// Only verified list modes are accepted; output contains no native pointers.
// Verified parent modes return initial leaf rows in category-opening order.
std::optional<std::vector<NativeStockpileRow>> nativeStockpileRows(
    df::stockpile_settings& owned,int mode,const std::string& filter,
    const std::vector<NativeStockpileSettingRange>& ranges);
// Read-only Wood-list probe. Caller bounds settings before copying. Filter bytes
// use DF's encoding. Selection activation is deliberately not part of this query.
std::optional<std::vector<NativeStockpileRow>> nativeStockpileWoodRows(
    const df::stockpile_settings& source,const std::string& filter);
}
