#pragma once
#include "residents_activity_native.h"
#include "residents_happiness_native.h"
#include "zone_native.h"

namespace df3d_residents {
struct RowText {
    df3d_area::ZoneOwnerDisplayText name;
    df3d_area::ZoneOwnerNameColor nameColor;
    ActivityText activity;
    uint8_t happiness=0;
};

// Safe-point semantic content for a Residents row. Native row builder142a7ab
// supplies its gender flag to widget factory142efd0, enables profession and
// two-line output, and caps text at30 columns (142a7cb). Layout can further
// reduce that width. Never call the widget renderer: it writes shared strings
// and drawing globals. These readers own every returned string instead.
inline std::optional<RowText> rowText(df::unit* unit,int32_t columns,bool showGender) {
    if(!unit || columns<3 || columns>30)return std::nullopt;
    const auto name=df3d_area::nativeZoneOwnerDisplayText(*unit,columns,showGender);
    const auto color=df3d_area::nativeZoneOwnerNameColor(*unit);
    const auto activity=activityText(unit);
    const auto happiness=happinessTier(unit);
    if(!name || !color || !activity || !happiness)return std::nullopt;
    return RowText{*name,*color,*activity,*happiness};
}
}
