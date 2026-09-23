extends SceneTree
const Thoughts = preload("res://scripts/creature_thought_text.gd")
const Sheet = preload("res://scripts/creature_sheet.gd")
const Personality = preload("res://scripts/creature_personality_text.gd")
const Native = preload("res://scripts/native_creature_text.gd")
class Source extends RefCounted:
 func assets_root():
  var env := OS.get_environment("DF3D_DF_PATH")
  return env if env != "" else "C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress"
var failures := 0
func check(condition: bool, message: String):
 if not condition: failures+=1;push_error(message)
func row(id: int, values: Dictionary) -> Dictionary:
 var facts: Array=[]
 for key in values: facts.append({"key":key,"has_number":values[key] is int,"number":values[key] if values[key] is int else 0,"text":str(values[key])})
 return {"id":id,"facts":facts}
func plain(spans: Array) -> String:
 var text := ""
 for span in spans: text+=span.text
 return text
func _initialize():
 var sheet := Sheet.new()
 sheet.owner={"world":Source.new()}
 var data := Thoughts.prepare(sheet.owner.world)
 check(not data.is_empty(),"Version-matched original text available")
 if data.is_empty(): quit(1);return
 var need := row(2,{"emotion_id":26,"thought_id":180,"subthought_id":13,"strength":1,"relative_strength":1,"year":337,"year_tick":0})
 # Reference-native wording is independently recorded in the screenshot JSON.
 var clothing := row(3,{"emotion_id":123,"thought_id":216,"severity":4,"strength":0,"relative_strength":0,"mood_flags":16,"year":336})
 check(plain(Thoughts.sentence(sheet,clothing,1,data))=="He felt pleasure remembering putting on an exceptional item.","Native remembered clothing sentence and whitespace")
 var neutral := row(4,{"emotion_id":-1,"thought_id":240,"thought_subject_kind":"anonymous_species","thought_subject":"donkey","strength":0,"relative_strength":0})
 check(plain(Thoughts.sentence(sheet,neutral,1,data))=="He didn't feel anything after seeing a donkey's dead body.","Neutral emotions must remain visible")
 var unknown := row(5,{"emotion_id":26,"thought_id":99999,"strength":1})
 check(Thoughts.sentence(sheet,unknown,1,data).is_empty(),"Untraced clauses do not generate prose")
 sheet.sections={"emotions":{"available":true,"truncated":false,"records":[clothing,neutral,need,unknown]}}
 var recent := Thoughts.recent(sheet,1)
 check(recent.size()==3,"Known semantic events retain coverage")
 check(plain(recent[0]).begins_with("He is bored"),"Active emotions precede remembered past emotions")
 check(not plain(recent[1]).contains("[C:"),"Native color commands are parsed")
 var memory := row(16,{"emotion_id":123,"thought_id":216,"severity":4,"created_year":333,"created_tick":0,"memory_category":"core","has_remembered":"yes"})
 var effect := row(100000,{"record_type":"memory_effect","changed_facet":3,"facet_old":40,"facet_new":60,"changed_value":-1})
 effect.related_id=16
 sheet.sections.memories={"available":true,"truncated":false,"records":[effect,memory,row(17,{"has_remembered":"no"})]}
 var memories := Thoughts.memories(sheet)
 check(memories.size()==2,"Only remembered entries and their date heading are displayed")
 check(plain(memories[0].spans)=="Spring 333","Memory grouping uses creation date")
 check(plain(memories[1].spans)=="Pleasure remembering putting on an exceptional item. Became more cheerful.","Native causal memory effect links to its source memory")
 var cause_memory := row(16,{"memory_category":"core","has_remembered":"no","thought_id":12,"year":333})
 var cause_effect := row(100000,{"record_type":"memory_effect","changed_facet":3,"facet_old":50,"facet_new":75,"changed_value":-1})
 cause_effect.related_id=16
 sheet.sections.memories.records=[cause_memory,cause_effect]
 var causal: Array=[]
 Thoughts.append_source(causal,Personality.cause(sheet,3,"facet",Personality.cause_inputs(sheet),data),Color.WHITE)
 check(plain(causal)==", after a new romance in 333","Unremembered core memory still explains personality; neutral origins are not strengthening")
 var later := row(17,{"memory_category":"core","has_remembered":"no","thought_id":112,"subthought_id":11,"year":331})
 var later_effect := row(100001,{"record_type":"memory_effect","changed_facet":3,"facet_old":65,"facet_new":95,"changed_value":-1})
 later_effect.related_id=17
 sheet.sections.memories.records.append_array([later,later_effect])
 causal=[]
 Thoughts.append_source(causal,Personality.cause(sheet,3,"facet",Personality.cause_inputs(sheet),data),Color.WHITE)
 check(plain(causal)==", a strengthening after felling a tree in 331","Causal selection follows source core order, not memory date sorting")
 sheet.sections.personality={"available":true,"truncated":false,"records":[row(1000,{"record_type":"personality_context","alcohol_timer":403200})]}
 check(plain(Personality.conditions(sheet,0))=="She needs alcohol to get through the working day and can't even remember the last time she had some. ","Native alcohol boundary and embedded pronoun")
 sheet.sections.personality.records=[row(3,{"value":50,"temporary_change":30})]
 check(not Personality.facet_description(sheet,1).is_empty(),"A neutral base does not hide a temporary trait change")
 var conflicted := Personality.conflict(0,20,{29:30},{"subject":"he","object":"him","possessive":"his","reflexive":"himself"},data)
 check(conflicted==", and he is troubled by this because he values romance","Native trait/value conflict predicates")
 check(Native.skill_rust(sheet,row(0,{"rating":8,"rusty":1})).is_empty(),"Small rust loss does not imply a native Rusty label")
 check(Native.skill_rust(sheet,row(0,{"rating":4,"rusty":2})).get("text")==" (Rusty)","Half nominal skill gets native Rusty suffix")
 check(Native.skill_rust(sheet,row(0,{"rating":4,"rusty":3})).get("text")==" (V Rusty)","Quarter nominal skill gets native Very Rusty suffix")
 sheet.sections.needs={"available":true,"truncated":false,"records":[row(0,{"need_id":0,"focus":-100000}),row(1,{"need_id":1,"focus":-999999}),row(2,{"need_id":2,"focus":-999})]}
 var needs := Native.overview_needs(sheet)
 check(needs.size()==2 and needs[0][1].text=="Socialize","Unmet needs use native threshold and source-order ties within a severity band")
 if failures==0: print("CREATURE_THOUGHT_TEXT_PASS")
 quit(1 if failures else 0)
