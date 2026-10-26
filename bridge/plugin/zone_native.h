#pragma once
namespace df { struct building_civzonest; }
namespace df3d_area {
// Defaults only: caller owns the new, unpublished zone and its selected type.
// This does not allocate, publish, assign occupants or infer range direction.
bool nativeZoneDefaultsReady();
bool nativeZoneDefaults(df::building_civzonest& zone);
}
