extends RefCounted
# Native personality composition consumes resident facts and shared text recipes.
const Native = preload("res://scripts/native_creature_text.gd")
const Thoughts = preload("res://scripts/creature_thought_text.gd")

static func append_spans(result: Array, text: String, color: Color):
 # DF lays out words with a single separator, including around color commands.
 while text.contains("  "): text=text.replace("  "," ")
 Thoughts.append_source(result,text,color)

static func cause_inputs(sheet) -> Dictionary:
 var memories := {};var result := {"facet":{},"value":{}}
 for row in sheet.records_for("memories"):
  if sheet.fact_value(row,"memory_category")=="core": memories[int(row.id)]=row
 for row in sheet.records_for("memories"):
  if sheet.fact_value(row,"record_type")!="memory_effect" or not memories.has(int(row.related_id)): continue
  for kind in ["facet","value"]:
   var id := int(sheet.fact_value(row,"changed_"+kind,-1))
   if id>=0: result[kind][id]={"effect":row,"memory":memories[int(row.related_id)]}
 return result

static func cause(sheet, id: int, kind: String, inputs: Dictionary, data: Dictionary) -> String:
 if not data.has("personality_cause_joiners") or not inputs[kind].has(id): return ""
 var input: Dictionary=inputs[kind][id]
 var circumstance := Thoughts.circumstance(sheet,input.memory,true)
 if circumstance.is_empty(): return ""
 var old_value := int(sheet.fact_value(input.effect,kind+"_old",0))
 var new_value := int(sheet.fact_value(input.effect,kind+"_new",0))
 var old_tier := Native.facet_tier(old_value) if kind=="facet" else 4-Native.value_bucket(old_value)
 var new_tier := Native.facet_tier(new_value) if kind=="facet" else 4-Native.value_bucket(new_value)
 var direction := ""
 if old_tier*new_tier<0: direction="turn"
 elif old_tier*new_tier>0 and absi(new_tier)>absi(old_tier): direction="strengthen"
 elif old_tier!=0 and absi(new_tier)<absi(old_tier): direction="moderate"
 var join: Dictionary=data.personality_cause_joiners[kind]
 var text: String=join.prefix.text+join.color.text
 if kind=="value": text+=join.open.text+join[direction if not direction.is_empty() else "due"].text
 else: text+=(join[direction].text if not direction.is_empty() else "")+join.after.text
 text+=circumstance+join.year.text+str(int(sheet.fact_value(input.memory,"year",0)))
 if kind=="value": text+=join.close.text
 return text+join.restore.text

static func effective_values(sheet) -> Dictionary:
 var values := {}
 for cultural in [true,false]:
  for row in sheet.records_for("values"):
   if (sheet.fact_value(row,"record_type")=="cultural_value")!=cultural: continue
   values[int(sheet.fact_value(row,"value_id",-1))]=int(sheet.fact_value(row,"strength",0))
 return values

static func conflict(id: int, base: int, values: Dictionary, pronouns: Dictionary, data: Dictionary) -> String:
 var text := ""
 for rule in data.get("facet_value_conflicts",[]):
  if int(rule.facet_id)!=id: continue
  if base<int(rule.get("facet_min",0)) or base>int(rule.get("facet_max",100)): continue
  var matches := true
  for predicate in rule.get("values",[]):
   var value := int(values.get(int(predicate.value_id),0))
   if value<int(predicate.get("min",-100)) or value>int(predicate.get("max",100)): matches=false;break
  if not matches: continue
  for part in rule.parts: text+=str(pronouns.get(part.pronoun,"")) if part.has("pronoun") else str(part.text)
 return text

static func temporary(sheet, row: Dictionary, base: int, pronouns: Dictionary, data: Dictionary) -> String:
 var change := int(sheet.fact_value(row,"temporary_change",0))
 if Native.facet_tier(base)==Native.facet_tier(base+change): return ""
 for rule in data.get("facet_temporary_descriptions",[]):
  if int(rule.id)!=int(row.id): continue
  var join: Dictionary=data.facet_temporary_joiners
  return join.color.text+str(pronouns.subject).capitalize()+join.currently.text+rule["increase" if change>0 else "decrease"].text+join.suffix.text+join.restore.text
 return ""

static func facet_description(sheet, sex: int) -> Array:
 var data := Thoughts.prepare(sheet.owner.world)
 if not data.has("facet_base_descriptions"): return []
 var pronouns := Native.sex_pronouns(sex)
 var causes := cause_inputs(sheet)
 var values := effective_values(sheet)
 var rows := []
 for record in sheet.records_for("personality"):
  if not str(sheet.fact_value(record,"record_type","")).is_empty(): continue
  var base := int(sheet.fact_value(record,"value",50))
  var tier := Native.facet_tier(base)
  if tier==0:
   var modifier := temporary(sheet,record,base,pronouns,data)
   if not modifier.is_empty(): rows.append({"id":int(record.id),"score":0,"text":modifier})
   continue
  for rule in data.facet_base_descriptions:
   if int(rule.id)!=int(record.id): continue
   for band in rule.bands:
    if int(band.tier)!=tier: continue
    var sentence: String=pronouns.subject.capitalize()+" "
    for part in band.parts: sentence+=str(pronouns.get(part.get("pronoun",""),"")) if part.has("pronoun") else str(part.text)
    sentence+=cause(sheet,int(record.id),"facet",causes,data)+conflict(int(record.id),base,values,pronouns,data)
    rows.append({"id":int(record.id),"score":absi(base-50),"text":sentence+". "+temporary(sheet,record,base,pronouns,data)})
 rows.sort_custom(func(a,b): return a.score>b.score if a.score!=b.score else a.id<b.id)
 var result: Array=[]
 for row in rows: append_spans(result,row.text,Native.colors[15])
 return result

static func value_description(sheet, sex: int) -> Array:
 var data := Thoughts.prepare(sheet.owner.world)
 if not data.has("value_base_descriptions"): return []
 var pronouns := Native.sex_pronouns(sex)
 var causes := cause_inputs(sheet)
 var personal := {};var cultural := {};var shared := {}
 var groups := [[],[]]
 for record in sheet.records_for("values"):
  var id := int(sheet.fact_value(record,"value_id",-1))
  if id<0: continue
  if sheet.fact_value(record,"record_type")=="cultural_value": cultural[id]=record
  else: personal[id]=record
 for id in cultural:
  var strength := int(sheet.fact_value(cultural[id],"strength",0))
  if absi(strength)<=10: continue
  if not personal.has(id) or Native.value_bucket(strength)==Native.value_bucket(int(sheet.fact_value(personal[id],"strength",0))):
   shared[id]=true;groups[0].append(cultural[id])
 for id in personal:
  if shared.has(id): continue
  var strength := int(sheet.fact_value(personal[id],"strength",0))
  if absi(strength)<=10 and (not cultural.has(id) or absi(int(sheet.fact_value(cultural[id],"strength",0)))<=10): continue
  groups[1].append(personal[id])
 var result := []
 var join: Dictionary=data.value_base_joiners
 for group_index in 2:
  var clauses := []
  for record in groups[group_index]:
   var strength := int(sheet.fact_value(record,"strength",0))
   var tier := 4-Native.value_bucket(strength)
   for rule in data.value_base_descriptions:
    if int(rule.id)!=int(sheet.fact_value(record,"value_id",-1)): continue
    for band in rule.bands:
     if int(band.tier)!=tier: continue
     var clause := ""
     for part in band.parts:
      if part.has("pronoun"): clause+=str(pronouns[part.pronoun])
      elif part.has("field"):
       var term := str(sheet.fact_value(record,part.field,""))
       clause+=str(data.craftsman_fallback.text) if term.is_empty() else term
      else: clause+=str(part.text)
     if group_index==1: clause+=cause(sheet,int(rule.id),"value",causes,data)
     clauses.append({"score":2*absi(strength)+(1 if strength>0 else 0),"text":clause})
  Native.stable_magnitude_sort(clauses)
  if clauses.is_empty(): continue
  var sentence: String=join.culture_prefix.text+pronouns.possessive+join.culture_connector.text+pronouns.subject+join.subject_separator.text if group_index==0 else pronouns.subject.capitalize()+join.subject_separator.text+join.personally.text
  for i in clauses.size():
   if i>0: sentence+=join["and"].text if i==clauses.size()-1 else join.comma.text
   sentence+=str(clauses[i].text)
  append_spans(result,sentence+join.suffix.text,Native.colors[7] if group_index==0 else Native.colors[11])
 for record in sheet.records_for("dreams"):
  for rule in data.get("dream_descriptions",[]):
   if int(rule.id)!=int(sheet.fact_value(record,"goal_type",-1)): continue
   var sentence: String=pronouns.subject.capitalize()+" "+rule.text
   if sheet.fact_value(record,"accomplished")=="yes": sentence+=data.dream_joiners.accomplished.text
   result.append({"text":sentence+data.dream_joiners.suffix.text,"color":Native.colors[14]})
 return result

static func mannerisms(sheet, sex: int) -> Array:
 var data := Native.load_text(sheet.owner.world)
 var pronouns := Native.sex_pronouns(sex)
 pronouns.subject_capitalized=str(pronouns.subject).capitalize()
 var result: Array=[]
 for row in sheet.records_for("personality"):
  if sheet.fact_value(row,"record_type")!="mannerism": continue
  for rule in data.get("mannerism_descriptions",[]):
   if int(rule.id)!=int(sheet.fact_value(row,"mannerism_type",-1)) or int(rule.situation)!=int(sheet.fact_value(row,"situation",-1)): continue
   var text := ""
   for part in rule.parts: text+=str(pronouns.get(part.pronoun,"")) if part.has("pronoun") else str(part.text)
   append_spans(result,text+data.mannerism_suffix.text,Native.colors[7])
 return result

static func conditions(sheet, sex: int) -> Array:
 var data := Native.load_text(sheet.owner.world)
 if not data.has("personality_condition_joiners"): return []
 var join: Dictionary=data.personality_condition_joiners
 var pronouns := Native.sex_pronouns(sex)
 var subject: String=str(pronouns.subject).capitalize()
 var result: Array=[]
 for row in sheet.records_for("personality"):
  if sheet.fact_value(row,"record_type")!="personality_context": continue
  var text: String=join.color.text
  var timer = sheet.fact_value(row,"alcohol_timer",null)
  if timer!=null:
   text+=subject+join.alcohol.text
   if int(timer)>=403200: text+=join.alcohol_forgot_before.text+str(pronouns.subject)+join.alcohol_forgot_after.text
   elif int(timer)>=302400: text+=join.alcohol_far.text
   elif int(timer)>=201600: text+=join.alcohol_wants.text
   elif int(timer)>=100800: text+=join.alcohol_slow.text
   text+=join.suffix.text
  var outdoors := int(sheet.fact_value(row,"likes_outdoors",0))
  if outdoors in [1,2]: text+=subject+join["outdoors"+str(outdoors)].text
  var hardened := int(sheet.fact_value(row,"combat_hardened",0))
  if hardened==100: text+=subject+join.hardened100.text
  elif hardened>=67: text+=subject+join.hardened67.text
  elif hardened>=33: text+=subject+join.hardened33.text
  append_spans(result,text,Native.colors[15])
 return result
