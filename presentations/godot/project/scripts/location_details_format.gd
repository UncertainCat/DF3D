extends RefCounted
# Native Details captures: fixtures/areas/native_location_{value,details}.json.
# location_value_view inserts the installed currency glyph between these parts.
const VALUE_LIMITS := [0,10,25,50,100,200,500,1000,1500,2000,2500,3000,4000,5000,10000]
const SUPPLY_UNITS := [1,1,1,1,15000,10000,1,150,1,150]

static func int32_value(value: Variant) -> bool:
	return typeof(value)==TYPE_INT and value>=-2147483648 and value<=2147483647

static func appraised_value(raw: Variant, appraisal: Variant) -> Dictionary:
	# Null/unobserved is distinct from native -1 (no assigned appraiser).
	if not int32_value(raw) or not int32_value(appraisal) or appraisal < -1: return {}
	if appraisal == -1: return {"text":"?","after_currency":""}
	if appraisal >= 15: return {"text":str(raw),"after_currency":""}
	var limit: int=VALUE_LIMITS[appraisal]
	# Native signed abs preserves INT32_MIN. The exact low-value branch also
	# omits a negative sign; preserve the captured behavior, not a correction.
	var magnitude: int=raw if raw==-2147483648 else absi(raw)
	if magnitude<=limit: return {"text":str(magnitude),"after_currency":""}
	var sign_text := "-" if raw<0 else ""
	if magnitude>(limit+50)*30:
		return {"text":sign_text+str((limit+50)*30+500),"after_currency":"?"}
	var unit := 10 if magnitude<=limit+50 else (100 if magnitude<=(limit+50)*3 else 1000)
	@warning_ignore("integer_division")
	var rounded: int=((magnitude+unit/2)/unit)*unit
	return {"text":"~"+sign_text+str(maxi(unit,rounded)),"after_currency":""}

static func supply_quantity(raw: Variant, kind: int, desired: bool) -> Variant:
	if not int32_value(raw) or kind<0 or kind>=SUPPLY_UNITS.size(): return null
	var unit: int=SUPPLY_UNITS[kind]
	var numerator: int=raw
	if not desired:
		# Native stored quantities add in signed int32 before dividing.
		numerator=((numerator+unit-1+2147483648)&0xffffffff)-2147483648
	@warning_ignore("integer_division")
	return numerator/unit

# Verbatim native labels, including scrolled hospital rows. Evidence:
# fixtures/areas/native_location_staff_labels.json; unknown roles stay unknown.
const OCCUPATION_LABELS := {0:"Tavern Keeper",1:"Performer",2:"Scholar",5:"Scribe",
	7:"Doctor",8:"Diagnostician",9:"Surgeon",10:"Bone Doctor"}
static func occupation_label(role: Variant) -> Variant:
	if not int32_value(role): return null
	return OCCUPATION_LABELS.get(role,null)

# Native staff capture221147: holder fields fit exactly, then reserve three
# cells for verbatim ellipsis. The view supplies its measured field width;
# hospital-with-scrollbar and fitting lists differ (12 versus14 cells).
static func staff_holder_name(value: Variant, cells: int) -> Variant:
	if typeof(value)!=TYPE_STRING or cells<3: return null
	return value if value.length()<=cells else value.left(cells-3)+"..."

# Capture221753 varies row count within each kind. The scrollbar consumes two
# holder-name cells; hospital is not inherently a narrower field.
static func staff_layout(kind: int, count: int) -> Dictionary:
	var first_y: int={1:26,2:29,3:29,5:41}.get(kind,-1)
	if first_y<0 or count<0: return {}
	@warning_ignore("integer_division")
	var capacity: int=(53-first_y)/3+1
	return {"first_y":first_y,"capacity":capacity,"width":12 if count>capacity else 14,
		"visible_count":mini(count,capacity),"max_scroll":maxi(0,count-capacity)}
