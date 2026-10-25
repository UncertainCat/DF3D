#pragma once
#include "df/stockpile_settings.h"
#include <optional>

namespace df3d_area {
// Safe-point diagnostic/service building block. The caller bounds raw counts.
// Returns independently owned settings; never edits the source or native UI.
std::optional<df::stockpile_settings> nativeStockpilePreset(
    const df::stockpile_settings& source, int preset);
}
