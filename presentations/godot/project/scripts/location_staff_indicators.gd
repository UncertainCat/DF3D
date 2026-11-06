extends RefCounted
# Native renderer3b867d..3b8ea8; dispatch_reference in native_location_details.json.
const OCCUPATIONS={0:"TAVERN_KEEPER",1:"PERFORMER",2:"SCHOLAR",3:"MERCENARY",4:"MONSTER_SLAYER",5:"SCRIBE",7:"DOCTOR",8:"DOCTOR",9:"DOCTOR",10:"DOCTOR"}
const WORK_DETAILS=["MINERS","WOODCUTTERS","HUNTERS","PLANTERS","FISHERMEN","STONECUTTERS","ENGRAVERS","PLANT_GATHERERS","HAULERS","ORDERLIES","CUSTOM_1","CUSTOM_2","CUSTOM_3","CUSTOM_4","CUSTOM_5","CUSTOM_6","CUSTOM_7","CUSTOM_8","SIEGE_OPERATORS"]
const WORKSHOPS={"0": "BUILDING_ICON_WORKSHOP_CARPENTER", "1": "BUILDING_ICON_WORKSHOP_FARMER", "2": "BUILDING_ICON_WORKSHOP_MASON", "3": "BUILDING_ICON_WORKSHOP_CRAFTS", "4": "BUILDING_ICON_WORKSHOP_JEWELER", "5": "BUILDING_ICON_WORKSHOP_METALSMITH", "6": "BUILDING_ICON_WORKSHOP_METALSMITH", "7": "BUILDING_ICON_WORKSHOP_BOWYER", "8": "BUILDING_ICON_WORKSHOP_MECHANIC", "9": "BUILDING_ICON_WORKSHOP_SIEGE", "10": "BUILDING_ICON_WORKSHOP_BUTCHER", "11": "BUILDING_ICON_WORKSHOP_LEATHER", "12": "BUILDING_ICON_WORKSHOP_TANNER", "13": "BUILDING_ICON_WORKSHOP_CLOTHES", "14": "BUILDING_ICON_WORKSHOP_FISHERY", "15": "BUILDING_ICON_WORKSHOP_STILL", "16": "BUILDING_ICON_WORKSHOP_LOOM", "17": "BUILDING_ICON_WORKSHOP_QUERN", "18": "BUILDING_ICON_WORKSHOP_KENNEL", "19": "BUILDING_ICON_WORKSHOP_KITCHEN", "20": "BUILDING_ICON_WORKSHOP_ASHERY", "21": "BUILDING_ICON_WORKSHOP_DYER", "22": "BUILDING_ICON_WORKSHOP_MILLSTONE", "23": "BUILDING_ICON_WORKSHOPS", "24": "BUILDING_ICON_WORKSHOPS"}
const FURNACES={"0": "BUILDING_ICON_FURNACE_WOOD", "1": "BUILDING_ICON_FURNACE_SMELTER", "2": "BUILDING_ICON_FURNACE_GLASS", "3": "BUILDING_ICON_FURNACE_KILN", "4": "BUILDING_ICON_FURNACE_SMELTER", "5": "BUILDING_ICON_FURNACE_GLASS", "6": "BUILDING_ICON_FURNACE_KILN", "7": "BUILDING_ICON_WORKSHOPS_FURNACES"}

# Shared artwork mapping; each screen retains its native placement rules.
static func art_for(entry: Dictionary) -> Dictionary:
	var token: String=""
	var fallback: String=""
	var help: String=""
	var building: bool=entry.kind in [1,2]
	if entry.kind==0:
		if not OCCUPATIONS.has(entry.type):return {}
		token="LOCATION_OCCUPATION_"+OCCUPATIONS[entry.type]
		help=OCCUPATIONS[entry.type].to_lower()
	elif building:
		var table: Dictionary=WORKSHOPS if entry.kind==1 else FURNACES
		token=table.get(str(entry.subtype),"")
		if not token.is_empty():help="workshop"
		if (entry.kind==1 and entry.subtype==23) or (entry.kind==2 and entry.subtype==7):
			fallback=token;token="CUSTOM_WORKSHOP_LIST_ICON:"+entry.custom_code
	elif entry.kind==3 and entry.type>=0 and entry.type<WORK_DETAILS.size():
		token="WORK_DETAIL_"+WORK_DETAILS[entry.type];help="work_detail"
	return {"token":token,"fallback":fallback,"building":building,"help":help}

static func slots(entries: Array, columns: int) -> Array:
	var result: Array=[]
	var column:=columns-20
	for entry in entries:
		if column>=columns-7:break
		var slot:=art_for(entry)
		if slot.is_empty():continue
		slot.column=column;result.append(slot);column+=4
	return result
