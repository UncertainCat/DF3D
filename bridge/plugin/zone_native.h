#pragma once
namespace df { struct building_civzonest; }
namespace df3d_area {
// Caller supplies a newly allocated zone and its selected type, at one safe point.
// Includes native initial range direction from supplied extents and target
// centers. Does not allocate, publish or assign occupants.
bool nativeZoneDefaultsReady();
bool nativeZoneDefaults(df::building_civzonest& zone);
bool nativeZoneCreateReady();
// The factory publishes an ID immediately. DF owns the returned pointer;
// callers must prepare all local allocations before entering and never delete it.
df::building_civzonest* nativeZoneAllocate();
bool nativeZoneComplete(df::building_civzonest& zone);
}
