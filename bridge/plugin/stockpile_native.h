#pragma once
#include "df/stockpile_settings.h"
#include <optional>
#include <array>
#include <string>
#include <vector>
namespace df {struct building_stockpilest;}

namespace df3d_area {
// Safe-point diagnostic/service building block. The caller bounds raw counts.
// Returns independently owned settings; never edits the source or native UI.
std::optional<df::stockpile_settings> nativeStockpilePreset(
    const df::stockpile_settings& source, int preset);
std::optional<std::array<int16_t,3>> nativeStockpilePresetContainers(
    df::building_stockpilest& pile, int preset);
// New unpublished pile: constructor defaults followed by native category setup.
std::optional<df::stockpile_settings> nativeStockpileInitialSettings(uint32_t categories);
// Read-only preparation for selecting one category. A disabled category gets
// native-sized empty filters; an already enabled category keeps its settings.
std::optional<df::stockpile_settings> nativeStockpileCategory(
    const df::stockpile_settings& source,uint32_t category);
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
std::optional<std::vector<NativeStockpileRow>> nativeStockpileRows(
    df::stockpile_settings& owned,int mode,const std::string& filter,
    const std::vector<NativeStockpileSettingRange>& ranges);
// Read-only Wood-list probe. Caller bounds settings before copying. Filter bytes
// use DF's encoding. Selection activation is deliberately not part of this query.
std::optional<std::vector<NativeStockpileRow>> nativeStockpileWoodRows(
    const df::stockpile_settings& source,const std::string& filter);
}
