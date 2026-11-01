extends RefCounted
# Copy source: pinned df-structures skill_rating.caption / job_skill.caption_noun.
# Native evidence: fixtures/areas/native_location_staff_selector_ui.json.
# These literal labels are mappings, not newly authored visible prose.
const RANKS := ["Dabbling", "Novice", "Adequate", "Competent", "Skilled", "Proficient", "Talented", "Adept", "Expert", "Professional", "Accomplished", "Great", "Master", "High Master", "Grand Master", "Legendary"]
const NOUNS := {
	0:"Miner",
	1:"Woodcutter",
	2:"Carpenter",
	3:"Engraver",
	4:"Mason",
	5:"Animal Trainer",
	6:"Animal Caretaker",
	7:"Fish Dissector",
	8:"Animal Dissector",
	9:"Fish Cleaner",
	10:"Butcher",
	11:"Trapper",
	12:"Tanner",
	13:"Weaver",
	14:"Brewer",
	15:"Clothier",
	16:"Miller",
	17:"Thresher",
	18:"Cheese Maker",
	19:"Milker",
	20:"Cook",
	21:"Planter",
	22:"Herbalist",
	23:"Fisherman",
	24:"Furnace Operator",
	25:"Strand Extractor",
	26:"Weaponsmith",
	27:"Armorsmith",
	28:"Metalsmith",
	29:"Gem Cutter",
	30:"Gem Setter",
	31:"Wood Crafter",
	32:"Stone Crafter",
	33:"Metal Crafter",
	34:"Glassmaker",
	35:"Leatherworker",
	36:"Bone Carver",
	37:"Axeman",
	38:"Swordsman",
	39:"Knife User",
	40:"Maceman",
	41:"Hammerman",
	42:"Spearman",
	43:"Crossbowman",
	44:"Shield User",
	45:"Armor User",
	46:"Siege Engineer",
	47:"Siege Operator",
	48:"Bowyer",
	49:"Pikeman",
	50:"Lasher",
	51:"Bowman",
	52:"Blowgunner",
	53:"Thrower",
	54:"Mechanic",
	55:"Druid",
	56:"Ambusher",
	57:"Wound Dresser",
	58:"Diagnostician",
	59:"Surgeon",
	60:"Bone Doctor",
	61:"Suturer",
	62:"Crutch-walker",
	63:"Wood Burner",
	64:"Lye Maker",
	65:"Soaper",
	66:"Potash Maker",
	67:"Dyer",
	68:"Pump Operator",
	69:"Swimmer",
	70:"Persuader",
	71:"Negotiator",
	72:"Judge of Intent",
	73:"Appraiser",
	74:"Organizer",
	75:"Record Keeper",
	76:"Liar",
	77:"Intimidator",
	78:"Conversationalist",
	79:"Comedian",
	80:"Flatterer",
	81:"Consoler",
	82:"Pacifier",
	83:"Tracker",
	84:"Student",
	85:"Concentration",
	86:"Discipline",
	87:"Observer",
	88:"Wordsmith",
	89:"Writer",
	90:"Poet",
	91:"Reader",
	92:"Speaker",
	93:"Coordination",
	94:"Balance",
	95:"Leader",
	96:"Teacher",
	97:"Fighter",
	98:"Archer",
	99:"Wrestler",
	100:"Biter",
	101:"Striker",
	102:"Kicker",
	103:"Dodger",
	104:"Misc. Object User",
	105:"Knapper",
	106:"Tactician",
	107:"Shearer",
	108:"Spinner",
	109:"Potter",
	110:"Glazer",
	111:"Presser",
	112:"Beekeeper",
	113:"Wax Worker",
	114:"Climber",
	115:"Gelder",
	116:"Dancer",
	117:"Musician",
	118:"Singer",
	119:"Keyboardist",
	120:"Stringed Instrumentalist",
	121:"Wind Instrumentalist",
	122:"Percussionist",
	123:"Critical Thinker",
	124:"Logician",
	125:"Mathematician",
	126:"Astronomer",
	127:"Chemist",
	128:"Geographer",
	129:"Optics Engineer",
	130:"Fluid Engineer",
	131:"Papermaker",
	132:"Bookbinder",
	133:"Schemer",
	134:"Rider",
	135:"Stonecutter",
	136:"Stonecarver",
	137:"Mod Skill 1",
	138:"Mod Skill 2",
	139:"Mod Skill 3",
	140:"Mod Skill 4",
	141:"Mod Skill 5",
	142:"Mod Skill 6",
	143:"Mod Skill 7",
	144:"Mod Skill 8",
	145:"Mod Skill 9",
	146:"Mod Skill 10",
	147:"UNUSED_01",
	148:"UNUSED_02",
}

# Native CP437 uppercase pairs, also documented by DFHack toupper_cp437.
# Unicode to_upper() would incorrectly change characters DF leaves alone.
const UPPER_CP437 := {"ü":"Ü","ñ":"Ñ","ä":"Ä","å":"Å","é":"É","ö":"Ö","ç":"Ç","æ":"Æ"}

static func capitalize_name(value: String) -> String:
	# Protected013629/013931: capitalize words outside bracketed segments;
	# a leading single quote differs from a double quote. This matches the
	# native rule documented by DFHack MiscUtils::capitalize_string_words.
	var result := ""
	var brackets := 0
	var first := true
	for index in value.length():
		var character := value[index]
		if character=="[":brackets+=1
		elif character=="]":brackets-=1
		elif brackets<=0:
			var start_word := first or (index>0 and value[index-1] in [" ","\""])
			if index>=2 and value[index-1]=="'" and value[index-2] in [" ",","]:start_word=true
			if start_word:
				var code := character.unicode_at(0)
				character=String.chr(code-32) if code>=97 and code<=122 else str(UPPER_CP437.get(character,character))
				first=false
		result+=character
	return result

static func abbreviate_name(value: String, cells: int) -> String:
	# Native removes ASCII vowels from right to left, preserving the first
	# character of each space-delimited word. Y and accented vowels stay.
	var result := value
	for index in range(value.length()-1,0,-1):
		if result.length()<=cells:break
		if result[index] in "aeiouAEIOU" and result[index-1]!=" ":
			result=result.left(index)+result.substr(index+1)
	return result.left(cells)

static func name_lines(name: Variant, profession: Variant, cells := 30) -> Variant:
	if typeof(name)!=TYPE_STRING or typeof(profession)!=TYPE_STRING or profession.is_empty() or cells<1:return null
	var capitalized := capitalize_name(name)
	var joined: String=capitalized+", "+profession
	if joined.length()<=cells:return [joined,""]
	return [abbreviate_name(capitalized,cells),abbreviate_name(profession,cells)]

# Native color-phase capture20260930-012915: all16 base colors, rating14/15,
# 1024 observations spanning3.2 seconds. Timing evidence has one16ms Windows
# tick of uncertainty at transitions; it does not establish sub-frame edges.
static func name_color_index(base_color: Variant, legendary: bool, ticks_ms: int) -> int:
	if typeof(base_color)!=TYPE_INT or base_color<0 or base_color>15 or ticks_ms<0:return -1
	# Native keeps black names visible as dark gray. The alternate dark-gray
	# shade is light gray, not black. Other colors toggle the brightness bit.
	var color: int=8 if base_color==0 else base_color
	if legendary and ticks_ms%1000<333:
		return 7 if color==8 else color^8
	return color

static func skill_lines(observed: Array) -> Variant:
	var selected: Array = []
	var seen: Dictionary = {}
	for skill in observed:
		if typeof(skill) != TYPE_DICTIONARY: return null
		for key in ["id","rating","weight"]:
			if typeof(skill.get(key)) != TYPE_INT: return null
		if not NOUNS.has(skill.id) or seen.has(skill.id) or skill.rating < 0 or skill.rating > 2147483647 or skill.weight < 1 or skill.weight > 5: return null
		seen[skill.id] = true
		if skill.rating > 0: selected.append(skill)
	selected.sort_custom(func(a,b):
		var first: int = a.rating*a.weight
		var second: int = b.rating*b.weight
		return first > second if first != second else a.id < b.id)
	var lines: Array = []
	for skill in selected:
		# Native rank text caps at Legendary even above15. Experience does not
		# break display ties; zero ratings are absent, not "Dabbling" rows.
		lines.append(RANKS[mini(15,skill.rating)]+" "+NOUNS[skill.id])
	return lines
