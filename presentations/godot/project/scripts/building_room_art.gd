extends RefCounted
# Native cage room switch19fc18 and location branch18f418. Values are semantic
# building/abstract-building kinds; installed artwork stays in the presentation.
const ZONES=["ZONE_DORMITORY","ZONE_DINING_HALL","","ZONE_WATER_SOURCE","ZONE_DUMP","ZONE_SAND","ZONE_FISHING","ZONE_PIT","ZONE_MEETING","ZONE_PEN","ZONE_CLAY","ZONE_ANIMAL_TRAINING","ZONE_GATHER","ZONE_BEDROOM","ZONE_OFFICE","ZONE_ARCHERY_RANGE","ZONE_BARRACKS","ZONE_DUNGEON","ZONE_TOMB"]
static func token(room: Dictionary) -> String:
	var kind: int=room.get("room_type",-1)
	if kind<79 or kind>97:return ""
	if kind!=87:return ZONES[kind-79]
	match int(room.get("location_type",-1)):
		2:
			if not room.get("location_has_contents",false):return ""
			match int(room.location_tier):
				1:return "ZONE_TEMPLE"
				2:return "ZONE_TEMPLE_COMPLEX"
			return "ZONE_SHRINE"
		8:return "ZONE_TAVERN"
		9:return "ZONE_LIBRARY"
		11:
			if not room.get("location_has_contents",false):return ""
			return "ZONE_GRAND_GUILDHALL" if room.location_tier==2 else "ZONE_GUILDHALL"
		13:return "ZONE_HOSPITAL"
	return "ZONE_MEETING"
