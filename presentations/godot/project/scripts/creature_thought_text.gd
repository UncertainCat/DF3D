extends RefCounted
# Native emotion grammar, evaluated only when a resident creature sheet changes.
# Untraced circumstance clauses are omitted, never replaced with enum captions.
const Native = preload("res://scripts/native_creature_text.gd")
static var emotions := {}
static var circumstances := {}
static var subthoughts := {}
static var skills := {}
static var skill_labels := {}
static var qualities := {}

static func prepare(world) -> Dictionary:
 var data := Native.load_text(world)
 if emotions.is_empty():
  for rule in data.get("emotion_descriptions",[]): emotions[int(rule.id)]=rule
  for rule in data.get("thought_static_descriptions",[]): circumstances[int(rule.id)]=rule
  for rule in data.get("thought_subthought_descriptions",[]): subthoughts[Vector2i(int(rule.id),int(rule.subthought))]=rule
  for rule in data.get("thought_skill_descriptions",[]): skills[int(rule.id)]=rule
  for rule in data.get("thought_skill_labels",[]): skill_labels[int(rule.id)]=source_text(rule).to_lower()
  for rule in data.get("thought_quality_descriptions",[]): qualities[Vector2i(int(rule.id),int(rule.severity) if rule.severity!=null else -1)]=rule
 return data

static func source_text(value) -> String:
 return str(value.get("text","")) if value is Dictionary else ""

static func append_source(spans: Array, text: String, color: Color) -> Color:
 # DF's embedded palette commands are source formatting, not visible text.
 while not text.is_empty():
  var start := text.find("[C:")
  if start<0:
   spans.append({"text":text,"color":color});break
  if start>0: spans.append({"text":text.left(start),"color":color})
  var end := text.find("]",start)
  if end<0: break
  var parts := text.substr(start+3,end-start-3).split(":")
  if parts.size()==3: color=Native.colors[clampi(int(parts[0])+8*int(parts[2]),0,15)]
  text=text.substr(end+1)
 return color

static func parts_text(rule: Dictionary, recalled: bool) -> String:
 return literal_parts(rule.get("recalled" if recalled else "normal",[]))

static func literal_parts(parts: Array) -> String:
 var text := ""
 for part in parts: text+=source_text(part)
 return text

static func circumstance(sheet, row: Dictionary, recalled: bool, sex := -1) -> String:
 var id := int(sheet.fact_value(row,"thought_id",-1))
 var sub := int(sheet.fact_value(row,"subthought_id",-1))
 var severity := int(sheet.fact_value(row,"severity",-1))
 var data := Native.load_text(sheet.owner.world)
 if id==12 and data.has("thought_romance"):
  var rule: Dictionary=data.thought_romance
  if recalled: return literal_parts(rule.recalled)
  return literal_parts(rule.normal_before_pronoun)+str(Native.sex_pronouns(sex).subject)+literal_parts(rule.normal_after_pronoun)
 if id in [188,189]:
  var event = sheet.fact_value(row,"performance_event",null)
  if event==null: return ""
  for rule in data.get("thought_performance",[]):
   if int(rule.id)==id:
    return ("" if recalled else literal_parts(rule.normal_prefix))+source_text(rule.sermon if int(event) in [4,5,6,7] else rule.ordinary)
 if id==40 and data.has("thought_ghost"):
  var rule: Dictionary=data.thought_ghost
  var verb := ""
  for value in rule.verbs:
   if int(value.severity)==severity: verb=source_text(value);break
  if verb.is_empty() or sub in [2,3,12]: return ""
  var tail := source_text(rule.default_tail)
  for value in rule.relations:
   if int(value.subthought)==sub: tail=source_text(value);break
  return parts_text(rule,recalled)+verb+tail
 if id==180 and sub==2 and data.has("thought_prayer"):
  var rule: Dictionary=data.thought_prayer
  var subject := str(sheet.fact_value(row,"thought_subject",""))
  if severity!=-1 and subject.is_empty(): return ""
  return parts_text(rule,recalled)+(source_text(rule.subject_connector)+subject if severity!=-1 else "")+source_text(rule.suffix)
 if id==240 and data.has("thought_dead_body"):
  var rule: Dictionary=data.thought_dead_body
  var kind := str(sheet.fact_value(row,"thought_subject_kind",""))
  var subject := str(sheet.fact_value(row,"thought_subject",""))
  if kind=="anonymous_species" and not subject.is_empty(): subject=source_text(rule.anonymous_prefix)+subject+source_text(rule.possessive)
  elif kind=="named_same_species" and not subject.is_empty(): subject+=source_text(rule.possessive)
  elif kind=="unknown": subject=source_text(rule.unknown)
  else: return ""
  return parts_text(rule,recalled)+subject+source_text(rule.suffix)
 if id==187 and data.has("thought_syndrome"):
  var subject := str(sheet.fact_value(row,"thought_subject",""))
  return parts_text(data.thought_syndrome,recalled)+subject if not subject.is_empty() else ""
 if id==280 and data.has("thought_victory"):
  var subject := str(sheet.fact_value(row,"thought_subject",""))
  var location := str(sheet.fact_value(row,"thought_location",""))
  if subject.is_empty() or location.is_empty(): return ""
  return parts_text(data.thought_victory,recalled)+subject+source_text(data.thought_victory.location_connector)+location
 if id==27 and data.has("thought_building"):
  var title := ""
  for label in data.thought_building_labels:
   if int(label.id)==sub: title=source_text(label);break
  if title.is_empty(): return ""
  var quality := ""
  for level in data.thought_building.quality:
   if severity>=int(level.minimum): quality=source_text(level)
  return parts_text(data.thought_building,recalled)+quality+source_text(data.thought_building.space)+title
 if subthoughts.has(Vector2i(id,sub)): return parts_text(subthoughts[Vector2i(id,sub)],recalled)
 if skills.has(id):
  if not skill_labels.has(sub): return ""
  return parts_text(skills[id],recalled)+skill_labels[sub]
 if qualities.has(Vector2i(id,severity)): return parts_text(qualities[Vector2i(id,severity)],recalled)
 if qualities.has(Vector2i(id,-1)): return parts_text(qualities[Vector2i(id,-1)],recalled)
 return parts_text(circumstances[id],recalled) if circumstances.has(id) else ""

static func sentence(sheet, row: Dictionary, sex: int, data: Dictionary) -> Array:
 var id := int(sheet.fact_value(row,"emotion_id",-2))
 var flags := int(sheet.fact_value(row,"mood_flags",0))
 if not emotions.has(id): return []
 var recalled := (flags&0x70)!=0
 var clause := circumstance(sheet,row,recalled,sex)
 if clause.is_empty(): return []
 var past := int(sheet.fact_value(row,"strength",0))<=0 and int(sheet.fact_value(row,"relative_strength",0))<=0
 var effective := -1 if int(sheet.fact_value(row,"relative_strength",0))==0 and (flags&8)!=0 else id
 var rule: Dictionary=emotions[effective]
 var joins: Dictionary=data.emotion_joiners
 var tense := "past" if past else "present"
 var pronoun: String=Native.sex_pronouns(sex).subject.capitalize()
 var text := source_text(joins[tense+"_color"])+pronoun+source_text(joins.space)
 text+=source_text(rule[tense+"_verb"])+source_text(rule.color)+source_text(rule[tense])
 if recalled: text+=source_text(joins[tense+"_recall_color"])+source_text(emotions[id].recall).trim_suffix(" ")
 text+=source_text(joins[tense+"_circumstance_color"])+clause+source_text(joins.suffix)
 var spans: Array=[]
 append_source(spans,text,Native.colors[15])
 return spans

static func recent(sheet, sex: int) -> Array:
 var data := prepare(sheet.owner.world)
 if not data.has("emotion_joiners"): return []
 var rows: Array=sheet.records_for("emotions").filter(func(row):
  return int(sheet.fact_value(row,"thought_id",-1)) not in [-1,6] and int(sheet.fact_value(row,"emotion_id",-2)) not in [165,166])
 rows.sort_custom(func(a,b):
  var active_a := int(sheet.fact_value(a,"strength",0))>0 or int(sheet.fact_value(a,"relative_strength",0))>0
  var active_b := int(sheet.fact_value(b,"strength",0))>0 or int(sheet.fact_value(b,"relative_strength",0))>0
  if active_a!=active_b: return active_a
  for field in ["year","year_tick"]:
   var av := int(sheet.fact_value(a,field,0));var bv := int(sheet.fact_value(b,field,0))
   if av!=bv: return av>bv
  return int(a.id)<int(b.id))
 var result: Array=[]
 for row in rows:
  var spans := sentence(sheet,row,sex,data)
  if not spans.is_empty(): result.append(spans)
 return result

static func memory_effect(sheet, row: Dictionary, data: Dictionary) -> String:
 var joins: Dictionary=data.memory_joiners
 var facet := int(sheet.fact_value(row,"changed_facet",-1))
 var value := int(sheet.fact_value(row,"changed_value",-1))
 var text := ""
 for rule in data.memory_facet_changes:
  if int(rule.id)==facet:
   var direction := "increase" if int(sheet.fact_value(row,"facet_new",0))>int(sheet.fact_value(row,"facet_old",0)) else "decrease"
   text=source_text(joins.became)+source_text(rule[direction]);break
 for rule in data.memory_value_labels:
  if int(rule.id)==value:
   var direction := "value" if int(sheet.fact_value(row,"value_new",0))>int(sheet.fact_value(row,"value_old",0)) else "disdain"
   text+=source_text(joins.learned if text.is_empty() else joins.and_learned)+source_text(joins[direction])+source_text(rule);break
 # Native word layout folds the source's two separator spaces to one.
 return " "+source_text(joins.effect_color).strip_edges()+text+source_text(joins.effect_suffix) if not text.is_empty() else ""

static func memories(sheet) -> Array:
 var data := prepare(sheet.owner.world)
 if not data.has("memory_descriptions"): return []
 var descriptions := {}
 for rule in data.memory_descriptions: descriptions[int(rule.id)]=rule
 var rows: Array=[]
 var effects := {}
 for row in sheet.records_for("memories"):
  if sheet.fact_value(row,"record_type")=="memory_effect": effects[int(row.related_id)]=row
  elif sheet.fact_value(row,"has_remembered")=="yes": rows.append(row)
 rows.sort_custom(func(a,b):
  for field in ["created_year","created_tick"]:
   var av := int(sheet.fact_value(a,field,0));var bv := int(sheet.fact_value(b,field,0))
   if av!=bv: return av<bv
  var categories := {"core":0,"long term":1,"short term":2}
  var ac: int=categories.get(sheet.fact_value(a,"memory_category"),3)
  var bc: int=categories.get(sheet.fact_value(b,"memory_category"),3)
  return ac<bc if ac!=bc else int(a.id)<int(b.id))
 var result: Array=[]
 var previous := Vector2i(-999,-999)
 var joins: Dictionary=data.memory_joiners
 for row in rows:
  var id := int(sheet.fact_value(row,"emotion_id",-2))
  if not descriptions.has(id): continue
  var clause := circumstance(sheet,row,true)
  if clause.is_empty(): continue
  var year := int(sheet.fact_value(row,"created_year",0))
  var season := clampi(int(int(sheet.fact_value(row,"created_tick",0))/100800),0,3)
  var group := Vector2i(year,season) if year>=1 else Vector2i(0,0)
  if group!=previous:
   var heading := source_text(joins.before_time) if year<1 else source_text(data.memory_seasons[season])+source_text(joins.year_separator)+str(year)
   var spans: Array=[];append_source(spans,heading,Native.colors[15])
   result.append({"heading":true,"spans":spans});previous=group
  var rule: Dictionary=descriptions[id]
  var text := source_text(rule.color)
  for part in rule.parts: text+=source_text(part)
  text=text.trim_suffix(" ")+source_text(joins.circumstance_color)+clause+source_text(joins.suffix)
  if effects.has(int(row.id)): text+=memory_effect(sheet,effects[int(row.id)],data)
  var spans: Array=[];append_source(spans,text,Native.colors[15])
  if not spans.is_empty(): spans[0].text=spans[0].text.left(1).to_upper()+spans[0].text.substr(1)
  result.append({"heading":false,"spans":spans})
 return result
