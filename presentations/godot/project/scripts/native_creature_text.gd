extends RefCounted
# Finite rules recovered from DF53.16; text stays in the user's installation.
# No native function calls, viewsheet cache reads, or generated narrative.
static var cache := {}
static var attempted := false
static var colors: Array[Color]=[Color.BLACK,Color(0,0,.5),Color.DARK_GREEN,Color.TEAL,Color.MAROON,Color.PURPLE,Color(.5,.5,0),Color(.75,.75,.75),Color.GRAY,Color.BLUE,Color.GREEN,Color.CYAN,Color.RED,Color.MAGENTA,Color.YELLOW,Color.WHITE]

static func load_text(world) -> Dictionary:
 if attempted: return cache
 attempted=true
 if not world.has_method("assets_root"): return cache
 var root: String=world.assets_root()
 var recipe: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://panels/native_creature_text.json"))
 var path := root.path_join("Dwarf Fortress.exe")
 if FileAccess.get_sha256(path)!=recipe.executable_sha256: return cache
 var file := FileAccess.open(path,FileAccess.READ)
 if file==null: return cache
 hydrate(recipe,file)
 cache=recipe
 var palette := FileAccess.get_file_as_string(root.path_join("data/init/colors.txt"))
 var names := ["BLACK","BLUE","GREEN","CYAN","RED","MAGENTA","BROWN","LGRAY","DGRAY","LBLUE","LGREEN","LCYAN","LRED","LMAGENTA","YELLOW","WHITE"]
 for i in names.size():
  var channels := []
  for channel in ["R","G","B"]:
   var pattern: String = "["+names[i]+"_"+channel+":"
   var start := palette.find(pattern)
   if start>=0: channels.append(float(palette.substr(start+pattern.length()).get_slice("]",0))/255.0)
  if channels.size()==3: colors[i]=Color(channels[0],channels[1],channels[2])
 return cache

static func hydrate(value, file: FileAccess):
 if value is Dictionary:
  if value.has("offset"):
   file.seek(int(value.offset));value["text"]=file.get_buffer(int(value.length)).get_string_from_ascii()
  for child in value.values(): hydrate(child,file)
 elif value is Array:
  for child in value: hydrate(child,file)

static func focus_tier(focus: int) -> int:
 if focus>=300: return 3
 if focus>=200: return 2
 if focus>=100: return 1
 if focus<=-100000: return -3
 if focus<=-10000: return -2
 if focus<=-1000: return -1
 return 0

static func need(sheet, record: Dictionary, sex: int) -> Dictionary:
 var data := load_text(sheet.owner.world)
 if data.is_empty(): return {}
 var id := int(sheet.fact_value(record,"need_id",-1))
 if id<0 or id>=data.needs.size(): return {}
 var tier := focus_tier(int(sheet.fact_value(record,"focus",0)))
 var level: Dictionary=data.tiers[3-tier]
 var rule: Dictionary=data.needs[id]
 var clause: String
 if id==2:
  var deity := int(sheet.fact_value(record,"deity_id",-1))
  var name := str(sheet.fact_value(record,"deity_name",""))
  if deity>=0 and name.is_empty(): return {}
  if tier>0: clause=rule.positive_no_deity.text if deity<0 else rule.positive_deity.text+name
  else: clause=rule.negative.text+(rule.negative_deity_connector.text+name if deity>=0 else "")
 else: clause=rule.positive.text if tier>0 else rule.negative.text
 var pronoun: String={0:"She",1:"He"}.get(sex,"It")
 return {"text":pronoun+data.sentence_joiner.text+level.text+" "+clause+data.sentence_suffix.text,"color":colors[int(level.color[0])+int(level.color[2])*8]}

static func overall(sheet, sex: int) -> Dictionary:
 var data := load_text(sheet.owner.world)
 if data.is_empty(): return {}
 for record in sheet.records_for("identity"):
  if sheet.fact_value(record,"record_type")!="focus": continue
  var current := int(sheet.fact_value(record,"current_focus",0))
  var baseline := int(sheet.fact_value(record,"undistracted_focus",0))
  var percent := int(float(current)*100/baseline) if baseline>0 else 100
  var index := 6
  var tier := 0
  if percent>=140: index=0;tier=3
  elif percent>=120: index=1;tier=2
  elif current>baseline: index=2;tier=1
  elif percent<=60: index=3;tier=-3
  elif percent<=80: index=4;tier=-2
  elif current!=baseline and baseline>0: index=5;tier=-1
  if current==baseline or baseline<=0: tier=0
  var level: Dictionary=data.tiers[3-tier]
  return {"text":data.overall_prefix.text+{0:"she",1:"he"}.get(sex,"it")+data.sentence_joiner.text+data.overall[index].text+data.sentence_suffix.text,"color":colors[int(level.color[0])+int(level.color[2])*8]}
 return {}


static func attributes(sheet) -> Array:
 var data := load_text(sheet.owner.world)
 if data.is_empty() or not data.has("overview_attribute_labels"): return []
 var candidates := []
 for record in sheet.records_for("attributes"):
  var effective = sheet.fact_value(record,"effective_value",null)
  var median = sheet.fact_value(record,"caste_median",null)
  if effective==null or median==null: continue
  var score := int(float(int(effective)-int(median))/20)
  if absi(score)<25: continue
  var id := int(record.get("id",-1))
  var category := str(sheet.fact_value(record,"category"))
  var local_id := id-100 if category=="mental" else id
  for rule in data.overview_attribute_labels:
   if rule.category!=category or int(rule.id)!=local_id: continue
   candidates.append({"id":id,"score":score,"text":rule.positive.text if score>0 else rule.negative.text,"color":colors[10] if score>0 else colors[12]})
   break
 # Native pre-sorts the two attribute groups by signed score, then merges
 # groups by magnitude without displacing earlier ties.
 candidates.sort_custom(func(a,b):
  if (a.id<100)!=(b.id<100): return a.id<100
  return a.score>b.score if a.score!=b.score else a.id>b.id)
 var eligible := false
 for record in sheet.records_for("identity"):
  if sheet.fact_value(record,"personality_summary_eligible")=="yes": eligible=true
 if eligible:
  var values := []
  for record in sheet.records_for("values"):
   if sheet.fact_value(record,"record_type")=="cultural_value": continue
   var strength := int(sheet.fact_value(record,"strength",0))
   var culture = sheet.fact_value(record,"cultural_strength",null)
   if absi(strength)<=10 and (culture==null or absi(int(culture))<=10): continue
   if culture!=null and absi(int(culture))>10:
    if not ((strength>10 and value_bucket(strength)<value_bucket(int(culture))) or (strength>=-40 and strength<=10 and value_bucket(strength)>value_bucket(int(culture)))): continue
   add_personality(data,values,"value",int(sheet.fact_value(record,"value_id",-1)),strength>=0,2*absi(strength)+(1 if strength>0 else 0))
  stable_magnitude_sort(values)
  candidates.append_array(values)
  var facets := []
  for record in sheet.records_for("personality"):
   var base := int(sheet.fact_value(record,"value",50))
   var change := int(sheet.fact_value(record,"temporary_change",0))
   var score := absi(base-50)
   if base>=40 and base<=60:
    if change==0 or facet_tier(base)==facet_tier(base+change): continue
    base=0;score=0
   add_personality(data,facets,"facet",int(record.id),base>=50,score)
  stable_magnitude_sort(facets)
  candidates.append_array(facets)
 stable_magnitude_sort(candidates)
 return candidates.slice(0,6)

static func stable_magnitude_sort(values: Array):
 # Godot sort is not stable; retain the native insertion priority explicitly.
 for i in values.size(): values[i]["order"]=i
 values.sort_custom(func(a,b): return absi(a.score)>absi(b.score) if absi(a.score)!=absi(b.score) else a.order<b.order)

static func add_personality(data: Dictionary, target: Array, category: String, id: int, positive: bool, score: int):
 for rule in data.get("overview_personality_labels",[]):
  if rule.category==category and int(rule.id)==id:
   target.append({"score":score,"text":rule.positive.text if positive else rule.negative.text,"color":colors[11]})
   return

static func value_bucket(value: int) -> int:
 if value>40: return 1
 if value>25: return 2
 if value>10: return 3
 if value>=-10: return 4
 if value>=-25: return 5
 if value>=-40: return 6
 return 7

static func skill_rust(sheet, record: Dictionary) -> Dictionary:
 var data := load_text(sheet.owner.world)
 if not data.has("skill_rust_labels"): return {}
 var nominal := int(sheet.fact_value(record,"rating",0))
 var remaining := maxi(0,nominal-int(sheet.fact_value(record,"rusty",0)))
 if nominal<=0 or remaining>=nominal: return {}
 if nominal>=4 and remaining<=int(nominal/4): return {"text":data.skill_rust_labels.very_rusty.text,"color":colors[12]}
 if remaining<=int(nominal/2): return {"text":data.skill_rust_labels.rusty.text,"color":colors[14]}
 return {}

static func overview_needs(sheet) -> Array:
 var data := load_text(sheet.owner.world)
 var section: Dictionary=sheet.sections.get("needs",{})
 if not data.has("overview_need_labels") or not section.get("available",false) or section.get("truncated",false): return []
 var rows: Array=[]
 for index in sheet.records_for("needs").size():
  var record: Dictionary=sheet.records_for("needs")[index]
  var focus := int(sheet.fact_value(record,"focus",0))
  if focus>-1000: continue
  rows.append({"record":record,"index":index,"severity":-3 if focus<=-100000 else -2 if focus<=-10000 else -1})
 rows.sort_custom(func(a,b): return a.severity<b.severity if a.severity!=b.severity else a.index<b.index)
 var join: Dictionary=data.overview_need_joiners
 if rows.is_empty(): return [[{"text":join.none.text,"color":colors[7]}]]
 var result: Array=[]
 for row in rows.slice(0,30):
  var id := int(sheet.fact_value(row.record,"need_id",-1))
  if id<0 or id>=data.overview_need_labels.size(): continue
  var title: String=data.overview_need_labels[id].text
  if id==2:
   var deity := int(sheet.fact_value(row.record,"deity_id",-1))
   var name := str(sheet.fact_value(row.record,"deity_name",""))
   if deity>=0 and name.is_empty(): continue
   title=join.meditate.text if deity<0 else join.prayer_deity.text+name
  result.append([{"text":join.prefix.text,"color":colors[15]},{"text":title,"color":colors[12 if row.severity==-3 else 14 if row.severity==-2 else 15]}])
 return result

static func facet_tier(value: int) -> int:
 if value>90: return 3
 if value>75: return 2
 if value>60: return 1
 if value>=40: return 0
 if value>=25: return -1
 if value>=10: return -2
 return -3

static func attribute_description(sheet, sex: int, mental := false) -> Array:
 var data := load_text(sheet.owner.world)
 var category := "mental" if mental else "physical"
 if not data.has(category+"_long_joiners"): return []
 var entries := []
 for record in sheet.records_for("attributes"):
  if sheet.fact_value(record,"category")!=category: continue
  var effective = sheet.fact_value(record,"effective_value",null)
  var median = sheet.fact_value(record,"caste_median" if mental else "body_caste_median",null)
  if effective==null or median==null: continue
  var score := int(float(int(effective)-int(median))/10)
  if absi(score)<25: continue
  for rule in data[category+"_long_attribute_labels"]:
   if int(rule.id)!=int(record.id)-(100 if mental else 0): continue
   for band in rule.bands:
    var threshold := int(band.threshold)
    if (threshold>0 and score>=threshold) or (threshold<0 and score<=threshold):
     var descriptor: String=band.text
     if band.get("append_possessive",false): descriptor+={0:"her",1:"his"}.get(sex,"its")+band.suffix.text
     entries.append({"score":score,"id":int(record.id),"text":descriptor});break
 entries.sort_custom(func(a,b): return a.score>b.score if a.score!=b.score else a.id>b.id)
 var result := []
 var join: Dictionary=data[category+"_long_joiners"]
 var verb: String=join["has" if mental else "is"].text
 var pronoun: String={0:"she",1:"he"}.get(sex,"it")
 for i in entries.size():
  var entry: Dictionary=entries[i]
  var prefix := ""
  if i==0: prefix=pronoun.capitalize()+verb
  elif entries[i-1].score>0 and entry.score<0:
   result.append({"text":join.sign_change_prefix.text,"color":colors[2]})
   prefix=join["but"].text+pronoun+verb
  else:
   prefix=join["and"].text if i==entries.size()-1 or (entry.score>0 and entries[i+1].score<0) else join.comma.text
  result.append({"text":prefix+join.space.text+entry.text+(join.suffix.text if i==entries.size()-1 else ""),"color":colors[2] if entry.score>0 else colors[4]})
 return result

static func sex_pronouns(sex: int) -> Dictionary:
 if sex==0: return {"subject":"she","object":"her","possessive":"her","reflexive":"herself"}
 if sex==1: return {"subject":"he","object":"him","possessive":"his","reflexive":"himself"}
 return {"subject":"it","object":"it","possessive":"its","reflexive":"itself"}

static func preference_description(sheet, sex: int) -> Array:
 var data := load_text(sheet.owner.world)
 if not data.has("preference_joiners"): return []
 var join: Dictionary=data.preference_joiners
 var groups := [[],[],[]]
 var name := ""
 for record in sheet.records_for("preferences"):
  if sheet.fact_value(record,"visible")!="yes": continue
  if name.is_empty(): name=str(sheet.fact_value(record,"creature_name",""))
  var kind := int(sheet.fact_value(record,"preference_type",-1))
  var subject := str(sheet.fact_value(record,"subject",""))
  var complete: bool=sheet.fact_value(record,"native_subject_complete")=="yes"
  if kind==4 and not complete:
   for rule in data.get("preference_item_subjects",[]):
    if int(rule.item_type)!=int(sheet.fact_value(record,"item_type",-1)): continue
    subject=""
    for part in rule.parts: subject+=str(part.text)
    if rule.has("suffix_codepoint"): subject+=String.chr(int(rule.suffix_codepoint))
    complete=true;break
  if not complete or subject.is_empty(): continue
  var prefix_key: String={7:"color_prefix",9:"poetic_prefix",10:"musical_prefix",11:"dance_prefix"}.get(kind,"")
  if not prefix_key.is_empty(): subject=str(join[prefix_key].text)+subject
  var suffix := str(sheet.fact_value(record,"material_suffix",""))
  if suffix in ["wood","fabric"]: subject+=str(join[suffix].text)
  var reason := str(sheet.fact_value(record,"reason",""))
  if kind in [1,5,6] and not reason.is_empty(): subject+=str(join.reason.text)+reason
  groups[1 if kind==2 else 2 if kind==3 else 0].append(subject)
 var result := []
 var pronoun: String=sex_pronouns(sex).subject
 for group in 3:
  if groups[group].is_empty() or (group==0 and name.is_empty()): continue
  var sentence: String=name+join.likes.text if group==0 else join.food_prefix.text+pronoun+join.food_connector.text if group==1 else pronoun.capitalize()+join.hate_connector.text
  for i in groups[group].size():
   if i>0: sentence+=join["and"].text if i==groups[group].size()-1 else join.comma.text
   sentence+=str(groups[group][i])
  result.append({"text":sentence+join.suffix.text,"color":colors[15]})
 return result
