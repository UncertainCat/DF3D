#pragma once
#include "residents_activity_native.h"
#include "residents_happiness_native.h"
#include "zone_native.h"

namespace df3d_residents {
struct RowText {
    df3d_area::ZoneOwnerDisplayText name;
    df3d_area::ZoneOwnerNameColor nameColor;
    ActivityText activity;
    int8_t happiness=-1;
};

// Safe-point semantic content for a Residents row. Native row builder142a7ab
// supplies its gender flag to widget factory142efd0, enables profession and
// two-line output, and caps text at30 columns (142a7cb). Layout can further
// reduce that width. Never call the widget renderer: it writes shared strings
// and drawing globals. These readers own every returned string instead.
// Work Details requests only shared identity text; activity/happiness remain
// explicitly unobserved there rather than invoking unrelated activity readers.
inline std::optional<RowText> rowText(df::unit* unit,int32_t columns,bool showGender,bool includeActivity=true) {
    if(!unit || columns<3 || columns>30)return std::nullopt;
    const auto name=df3d_area::nativeZoneOwnerDisplayText(*unit,columns,showGender);
    const auto color=df3d_area::nativeZoneOwnerNameColor(*unit);
    if(!name || !color)return std::nullopt;
    if(!includeActivity)return RowText{*name,*color,{},-1};
    const auto activity=activityText(unit);
    const auto happiness=happinessTier(unit);
    if(!name || !color || !activity || !happiness)return std::nullopt;
    return RowText{*name,*color,*activity,int8_t(*happiness)};
}
// Pets, Other and Dead/Missing use NAME_PROF/CUR_JOB without the Residents
// happiness indicator or activity-details actions. Gender is a Pets option.
inline std::optional<RowText> creatureUnitRowText(df::unit* unit,int32_t columns,bool showGender) {
    auto result=rowText(unit,columns,showGender,false);if(!result)return std::nullopt;
    const auto activity=activityText(unit,false);if(!activity)return std::nullopt;
    result->activity=*activity;return result;
}
}
