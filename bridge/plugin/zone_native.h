#pragma once
namespace df { struct building_civzonest; }
namespace df3d_area {
// Defaults only: caller owns the new, unpublished zone and its selected type.
// Includes native initial range direction from supplied extents and target
// centers. Does not allocate, publish or assign occupants.
bool nativeZoneDefaultsReady();
bool nativeZoneDefaults(df::building_civzonest& zone);
}
