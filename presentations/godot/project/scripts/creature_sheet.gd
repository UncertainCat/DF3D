extends RefCounted
const NativeText = preload("res://scripts/native_creature_text.gd")
const Style = preload("res://scripts/creature_sheet_style.gd")
const Thoughts = preload("res://scripts/creature_thought_text.gd")
const Personality = preload("res://scripts/creature_personality_text.gd")
# Presentation grouping is derived from the native creature-sheet reference.
# Transport, semantic collection and cache ownership remain below this control.
var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://panels/creature_sheet.json"))
var skill_styles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://panels/creature_skills.json")).skills
var tab := "Overview"
var subtabs := {}
var scrolls := {}
var unit_id := -1
var scroll: ScrollContainer
var owner
var sections := {}

func reset(id: int):
 if unit_id == id: return
 unit_id=id;tab="Overview";subtabs.clear();scrolls.clear();scroll=null

func location() -> String: return tab+"/"+str(subtabs.get(tab,""))

func remember_scroll():
 if is_instance_valid(scroll): scrolls[location()]=scroll.scroll_vertical

func change_tab(value: String, nested := false):
 remember_scroll()
 if nested: subtabs[tab]=value
 else: tab=value
 owner.redraw()

func text(parent: Node, value: String, color := Color.WHITE) -> Label:
 var label := Label.new()
 label.text=value
 label.add_theme_font_size_override("font_size",12)
 label.add_theme_constant_override("line_spacing",0)
 label.add_theme_color_override("font_color",color)
 label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 parent.add_child(label)
 return label

func paragraph(parent: Node, spans: Array, spacing := 12, wrap := true) -> RichTextLabel:
 if spans.is_empty(): return null
 var value := RichTextLabel.new()
 value.add_theme_font_override("normal_font",owner.body.get_theme_font("font","Label"))
 value.add_theme_font_size_override("normal_font_size",12)
 value.add_theme_constant_override("line_separation",0)
 value.fit_content=wrap;value.scroll_active=false
 if not wrap: value.custom_minimum_size.y=12
 value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
 value.clip_contents=true
 value.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 parent.add_child(value)
 for span in spans:
  value.push_color(span.color);value.add_text(span.text);value.pop()
 if spacing>0:
  var gap := Control.new();gap.custom_minimum_size.y=spacing;parent.add_child(gap)
 return value

func tabs_at(names: Array, y: float, nested := false) -> float:
 var x := 0.0
 for title in names:
  var selected: bool = str(subtabs.get(tab,""))==title if nested else tab==title
  var button := Button.new()
  button.text=title
  button.alignment=HORIZONTAL_ALIGNMENT_LEFT
  var width := minf(str(title).length()*8+24,owner.body.size.x)
  if nested:
   width=minf(float(recipe.get("subtab_widths",{}).get(tab,{}).get(title,width)),owner.body.size.x)
  if x>0 and x+width>owner.body.size.x:
   x=0; y+=24
  # Native tabs occupy 20 pixels within a 24-pixel row pitch.
  button.position=Vector2(x,y-2)
  button.size=Vector2(width,20)
  button.clip_text=true
  button.tooltip_text=title
  button.add_theme_font_size_override("font_size",12)
  var style := StyleBoxTexture.new()
  var selector := "SHORT_SUBTAB" if nested else "SHORT_TAB"
  style.texture=owner.world.ui_texture(selector+("_SELECTED" if selected else ""))
  style.set_texture_margin(SIDE_LEFT,16);style.set_texture_margin(SIDE_RIGHT,16)
  style.set_content_margin(SIDE_LEFT,15);style.set_content_margin(SIDE_RIGHT,9)
  style.set_content_margin(SIDE_TOP,0);style.set_content_margin(SIDE_BOTTOM,4)
  for state in ["normal","hover","pressed","focus"]: button.add_theme_stylebox_override(state,style)
  for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
   button.add_theme_color_override(state,Color.BLACK if selected else Color.WHITE)
  button.pressed.connect(func(): change_tab(title,nested))
  owner.body.add_child(button)
  x+=button.size.x
 return y+24

func fact_value(record: Dictionary,key: String, fallback = ""):
 for fact in record.get("facts",[]):
  if fact.key==key: return fact.number if fact.get("has_number",false) else fact.get("text","")
 return fallback

func display_word(value) -> String:
 return str(value).replace("_"," ").capitalize()

func record_text(record: Dictionary, section_key := "") -> String:
 if section_key=="inventory":
  var where := str(fact_value(record,"body_part",""))
  var mode := str(fact_value(record,"mode",""))
  var count := int(fact_value(record,"stack",1))
  return (where.left(1).to_upper()+where.substr(1) if not where.is_empty() else "")+("   Quantity: "+str(count) if count>1 else "")
 if section_key=="skills":
  return "Rating: %s   Experience: %s" % [fact_value(record,"rating",0),fact_value(record,"experience",0)] + ("   Rust: %s" % fact_value(record,"rusty",0) if int(fact_value(record,"rusty",0))>0 else "")
 var lines: PackedStringArray = []
 for fact in record.get("facts",[]):
  var key := str(fact.key)
  if key in ["item_type","subtype_raw","material_token","color","color_token","translated_name","record_type","skill_class","civilization_id","historical_figure_id","birth_time","body_part_id","subthought_id","material_type","material_index","squad_id","unit_id","profession_id","personality_summary_eligible","value_id","cultural_strength","temporary_change","effective_value","soft_demotion","caste_median","body_caste_median"]: continue
  var value = fact.number if fact.get("has_number",false) else fact.get("text","")
  if str(value).is_empty(): continue
  if key=="squad_position" and int(value)<0: continue
  if key=="sex": value = {0:"Female",1:"Male",-1:"Unspecified"}.get(int(value),"Unspecified")
  lines.append(display_word(key)+": "+str(value).replace("_"," "))
 return "   ".join(lines)

func filtered_records(key: String, records: Array) -> Array:
 if key=="relationships":
  var sorted := records.duplicate()
  var rank := {"spouse":0,"lover":1,"deity":2,"child":3,"mother":4,"father":4,"kindred spirit":5,"close friend":6,"friend":7,"acquaintance":8}
  sorted.sort_custom(func(a,b):
   var ar: int=rank.get(str(fact_value(a,"relationship")).to_lower(),9)
   var br: int=rank.get(str(fact_value(b,"relationship")).to_lower(),9)
   return ar<br if ar!=br else int(a.id)<int(b.id))
  return sorted
 if tab=="Health" and key=="health":
  var wanted: String = {"Wounds":"wound","Description":"body_part"}.get(subtabs.get(tab,"Status"),"status")
  return records.filter(func(row): return str(fact_value(row,"record_type"))==wanted and (wanted!="wound" or fact_value(row,"diagnosed")=="yes"))
 if tab=="Health" and key=="treatment":
  return records.filter(func(row): return fact_value(row,"native_treatment")=="yes")
 if tab=="Overview" and key=="health": return records.filter(func(row): return str(fact_value(row,"record_type"))=="status")
 if tab=="Skills" and key=="skills":
  var sub := str(subtabs.get(tab,"Labor"))
  var found: Array = []
  for row in records:
   var category := skill_category(row)
   if sub==category: found.append(row)
  found.sort_custom(func(a,b):
   var ar := int(fact_value(a,"rating",0))
   var br := int(fact_value(b,"rating",0))
   if ar!=br: return ar>br
   return int(a.get("id",0))<int(b.get("id",0))
  )
  return found
 return records

func section(parent: Node, key: String, heading := true, limit := 10000):
 var data: Dictionary = sections.get(key,{})
 if heading: text(parent,display_word(key),Color(1,.85,.25))
 if data.is_empty(): return
 if not data.get("available",false): return
 var records: Array = filtered_records(key,data.get("records",[]))
 if tab=="Health" and records.is_empty() and not data.get("truncated",false):
  var native := NativeText.load_text(owner.world)
  var empty: Dictionary=native.get("health_empty_labels",{}).get(str(subtabs.get(tab,"")),{})
  if not empty.is_empty(): text(parent,str(empty.text).trim_prefix("[C:7:0:0]"),NativeText.colors[7])
 for i in mini(limit,records.size()):
  var record: Dictionary=records[i]
  if tab=="Health" and key=="identity" and subtabs.get(tab,"")=="Description":
   var description := str(fact_value(record,"caste_description",""))
   if not description.is_empty(): text(parent,description)
   continue
  var row_parent: Node=parent
  if key in ["inventory","skills","relationships","groups","labors","rooms","military","knowledge"]:
   row_parent=Style.row(parent,owner.world,36)
   if key=="inventory": Style.icon(row_parent,owner.world.selection_icon(2,int(record.get("id",-1))))
   elif key=="relationships" and int(fact_value(record,"unit_id",-1))>=0: Style.icon(row_parent,owner.world.selection_icon(1,int(fact_value(record,"unit_id",-1))))
  var row := VBoxContainer.new()
  row.add_theme_constant_override("separation",2)
  row.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  row_parent.add_child(row)
  var title := str(record.get("name",""))
  if key=="skills": title=skill_title(record)
  elif key not in ["inventory","uniform"]: title=title.left(1).to_upper()+title.substr(1)
  var caption: Control
  if key=="skills": caption=paragraph(row,skill_spans(record),0)
  else: caption=text(row,title,Color(0,1,1) if key=="groups" else Color(1,.85,.25) if key=="inventory" else Color.WHITE)
  var facts := record_text(record,key)
  if key=="groups": facts=display_word(fact_value(record,"position",fact_value(record,"membership")))
  elif key=="relationships": facts=display_word(fact_value(record,"relationship"))
  elif key in ["labors","military","rooms"]: facts=""
  elif key=="knowledge": facts=display_word(fact_value(record,"category"))
  caption.tooltip_text=facts
  caption.mouse_filter=Control.MOUSE_FILTER_PASS
  if key!="skills" and not facts.is_empty():
   text(row,facts,Color(0,1,1) if key in ["inventory","knowledge"] else Color(.7,.7,.7))
  if key=="groups":
   var kind := str(fact_value(record,"entity_type"))
   var category_name := kind.left(1).to_upper()+kind.substr(1)
   if kind=="guild" and str(fact_value(record,"guild_profession_name")).to_lower()=="farmer": category_name="Farmers guild"
   var category := text(row_parent,category_name,Color(1,1,0))
   category.custom_minimum_size.x=144
   category.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
   category.size_flags_horizontal=Control.SIZE_SHRINK_END
  elif key=="labors":
   var assigned: bool = fact_value(record,"assigned")=="yes"
   Style.icon(row_parent,owner.world.ui_texture("LABOR_WORKER_ASSIGNED" if assigned else "LABOR_WORKER_UNASSIGNED"))


func skill_title(record: Dictionary) -> String:
 var style: Dictionary=skill_styles.get(str(record.get("id",-1)),{})
 var noun := str(fact_value(record,"profession_name",style.get("name",record.get("name",""))))
 noun=noun.left(1).to_upper()+noun.substr(1)
 return (str(fact_value(record,"rank",""))+" "+noun).strip_edges()

func skill_spans(record: Dictionary) -> Array:
 var result: Array=[{"text":skill_title(record),"color":skill_color(record)}]
 var rust := NativeText.skill_rust(self,record)
 if not rust.is_empty(): result.append(rust)
 return result

func skill_category(record: Dictionary) -> String:
 var style: Dictionary=skill_styles.get(str(record.get("id",-1)),{})
 if style.has("category"): return style.category
 var cls := str(fact_value(record,"skill_class")).to_lower()
 if cls.contains("military") or cls.contains("combat"): return "Combat"
 if cls.contains("social"): return "Social"
 if cls.contains("normal") or cls.contains("medical"): return "Labor"
 return "Other skills"

func skill_color(record: Dictionary) -> Color:
 var style: Dictionary=skill_styles.get(str(record.get("id",-1)),{})
 var color := int(style.get("color",7))
 return NativeText.colors[color] if color>=0 and color<16 else Color.WHITE

func records_for(key: String) -> Array:
 return sections.get(key,{}).get("records",[])

func summary_line(cell: Control, value: String, color := Color.WHITE):
 var label := text(cell,value,color)
 label.autowrap_mode=TextServer.AUTOWRAP_OFF
 label.clip_text=true
 label.tooltip_text=value
 label.mouse_filter=Control.MOUSE_FILTER_PASS

func overview(parent: Node, detail: Dictionary):
 # Native summaries use equal columns and clipped single-line entries.
 var grid := GridContainer.new()
 grid.columns=2
 grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 grid.add_theme_constant_override("h_separation",0)
 grid.add_theme_constant_override("v_separation",0)
 parent.add_child(grid)
 var cells: Array=[]
 var source: Texture2D=owner.world.ui_texture("HOVER_RECTANGLE")
 for i in 8:
  var panel := PanelContainer.new()
  panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  panel.custom_minimum_size=Vector2(120,84)
  var insets := StyleBoxEmpty.new()
  insets.content_margin_left=0 if i%2==0 else 4
  insets.content_margin_right=6
  insets.content_margin_top=6
  insets.content_margin_bottom=6
  panel.add_theme_stylebox_override("panel",insets)
  grid.add_child(panel)
  var cell := VBoxContainer.new()
  cell.add_theme_constant_override("separation",0)
  panel.add_child(cell)
  cells.append(cell)
  if source!=null:
   # A plain Control keeps decorative lines out of container measurement.
   var borders := Control.new()
   borders.mouse_filter=Control.MOUSE_FILTER_IGNORE
   panel.add_child(borders)
   for vertical in [false,true]:
    if vertical and i%2==1: continue
    var atlas := AtlasTexture.new()
    atlas.atlas=source
    atlas.region=Rect2(2,12,2,12) if vertical else Rect2(8,2,8,2)
    var line := TextureRect.new()
    line.texture=atlas
    line.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
    line.mouse_filter=Control.MOUSE_FILTER_IGNORE
    borders.add_child(line)
    line.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE if vertical else Control.PRESET_BOTTOM_WIDE)
    # PanelContainer gives the overlay the same inset rectangle as text.
    # Extend decoration back to the cell edges so adjacent rules join.
    if vertical:
     line.offset_left=4; line.offset_right=6
     line.offset_top=-4; line.offset_bottom=6
    else:
     line.offset_left=-4; line.offset_right=6
     line.offset_top=4; line.offset_bottom=6
 var age := int(detail.get("age",-1))
 var sex_symbol: String={0:String.chr(0x2640),1:String.chr(0x2642)}.get(int(detail.get("sex",-1)),"")
 if age>=0: summary_line(cells[0],str(age)+" Years Old"+(", "+sex_symbol if not sex_symbol.is_empty() else ""))
 for row in records_for("relationships"):
  var relation := str(fact_value(row,"relationship")).to_lower()
  if relation in ["lover","spouse"]: summary_line(cells[0],relation.capitalize()+" "+str(fact_value(row,"translated_name",row.name)),Color(1,0,1))
 for row in records_for("identity"):
  var children := int(fact_value(row,"children_count",0))
  if children>0: summary_line(cells[0],"%d children" % children)
  var pet_owner := str(fact_value(row,"pet_owner",""))
  if not pet_owner.is_empty(): summary_line(cells[0],"Pet of "+pet_owner,Color(1,0,1))
  if fact_value(row,"citizen")=="yes": summary_line(cells[3],"Citizen",Color(0,1,1))
 for descriptor in NativeText.attributes(self):
  summary_line(cells[1],descriptor.text,descriptor.color)
 for row in records_for("health"):
  if fact_value(row,"record_type")=="status":
   summary_line(cells[2],"Blood: %s / %s" % [fact_value(row,"blood"),fact_value(row,"blood_maximum")])
   if int(fact_value(row,"infection",0))>0: summary_line(cells[2],"Infection: %s" % fact_value(row,"infection"),Color(1,.6,0))
 for row in records_for("military"):
  if int(fact_value(row,"squad_id",-1))>=0: summary_line(cells[5],"Squad: "+str(row.name),Color(0,1,1))
 var skills: Array=records_for("skills").duplicate()
 skills.sort_custom(func(a,b):
  var ar := int(fact_value(a,"rating",0));var br := int(fact_value(b,"rating",0))
  if ar!=br: return ar>br
  return int(a.get("id",0))<int(b.get("id",0)))
 var counts := [0,0]
 for row in skills:
  var category := skill_category(row)
  var combat := category=="Combat"
  if not combat and category!="Labor": continue
  var group := 1 if combat else 0
  if counts[group]>=(5 if combat else 6): continue
  counts[group]+=1
  paragraph(cells[5 if combat else 6],skill_spans(row),0,false)
 for spans in NativeText.overview_needs(self).slice(0,6): paragraph(cells[7],spans,0,false)
 for spans in Thoughts.recent(self,int(detail.get("sex",-1))).slice(0,8): paragraph(parent,spans,0)

func room_summary(parent: Node):
 var data: Dictionary=sections.get("rooms",{})
 if not data.get("available",false) or data.get("truncated",false): return
 var native := NativeText.load_text(owner.world)
 # Per-value labels are native; multiple-room aggregation is not yet traced.
 for spec in [["office","No Study","NOBLES_OFFICE_NA"],["bedroom","No Quarters","NOBLES_BEDROOM_NA"],["dining hall","No Dining Room","NOBLES_DINING_NA"],["tomb","No Tomb","NOBLES_TOMB_NA"]]:
  var row := Style.row(parent,owner.world)
  Style.icon(row,owner.world.ui_texture(spec[2]))
  var title: String=spec[1]
  var value := 0
  var known_value := true
  for record in records_for("rooms"):
   if str(fact_value(record,"zone_type")).to_lower()==spec[0]:
    var observed = fact_value(record,"room_value",null)
    known_value=observed!=null
    if known_value: value=int(observed)
    else: title=record.name
    break
  var kind: String={"office":"Office","bedroom":"Bedroom","dining hall":"DiningHall","tomb":"Tomb"}[spec[0]]
  if known_value:
   for rule in native.get("room_quality_labels",{}).get(kind,[]):
    if value>=int(rule.minimum): title=rule.text;break
  text(row,title)

func render(controller, state: Dictionary):
 owner=controller
 remember_scroll()
 sections={}
 var detail: Dictionary=state.get("detail",{})
 for value in detail.get("sections",[]): sections[str(value.key)]=value
 if recipe.subtabs.has(tab) and not subtabs.has(tab): subtabs[tab]=recipe.subtabs[tab].keys()[0]
 var y:=96.0
 for names in recipe.rows: y=tabs_at(names,y)
 if recipe.subtabs.has(tab): y=tabs_at(recipe.subtabs[tab].keys(),y,true)
 y+=4
 if tab=="Overview": y-=10
 var native_prose_layout := tab in ["Thoughts","Personality"]
 scroll=ScrollContainer.new()
 scroll.position=Vector2(0,y+(6 if native_prose_layout else 0))
 scroll.size=Vector2(owner.body.size.x-(8 if native_prose_layout else 0),owner.body.size.y-y-(18 if native_prose_layout else 0))
 scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
 scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_RESERVE if native_prose_layout else ScrollContainer.SCROLL_MODE_AUTO
 owner.body.add_child(scroll)
 Style.scrollbar(scroll,owner.world)
 var content:=VBoxContainer.new()
 content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 content.add_theme_constant_override("separation",0)
 var inset := MarginContainer.new()
 inset.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 if tab!="Overview":
  inset.add_theme_constant_override("margin_left",8)
  inset.add_theme_constant_override("margin_right",8 if native_prose_layout else 24)
  inset.add_theme_constant_override("margin_top",2 if native_prose_layout else 8)
 scroll.add_child(inset)
 inset.add_child(content)
 if detail.is_empty(): return
 if tab=="Overview": overview(content,detail)
 elif tab=="Thoughts" and subtabs.get(tab)=="Recent thoughts":
  for spans in Thoughts.recent(self,int(detail.get("sex",-1))): paragraph(content,spans,0)
 elif tab=="Thoughts" and subtabs.get(tab)=="Memories":
  var first := true
  for entry in Thoughts.memories(self):
   if entry.heading and not first:
    var gap := Control.new();gap.custom_minimum_size.y=24;content.add_child(gap)
   paragraph(content,entry.spans,12 if entry.heading else 0)
   first=false
 elif tab=="Rooms": room_summary(content)
 elif tab=="Personality" and subtabs.get(tab)=="Traits":
  paragraph(content,NativeText.attribute_description(self,int(detail.get("sex",-1)),true))
  paragraph(content,Personality.facet_description(self,int(detail.get("sex",-1))))
  paragraph(content,Personality.mannerisms(self,int(detail.get("sex",-1))))
  paragraph(content,Personality.conditions(self,int(detail.get("sex",-1))))
 elif tab=="Personality" and subtabs.get(tab)=="Values":
  paragraph(content,Personality.value_description(self,int(detail.get("sex",-1))))
 elif tab=="Personality" and subtabs.get(tab)=="Preferences":
  paragraph(content,NativeText.preference_description(self,int(detail.get("sex",-1))))
 elif tab=="Personality" and subtabs.get(tab)=="Needs":
  var summary := NativeText.overall(self,int(detail.get("sex",-1)))
  if not summary.is_empty():
   text(content,summary.text,summary.color)
   var gap := Control.new();gap.custom_minimum_size.y=12;content.add_child(gap)
  for record in records_for("needs"):
   var line := NativeText.need(self,record,int(detail.get("sex",-1)))
   if line.is_empty(): continue
   text(content,line.text,line.color)
   var gap := Control.new();gap.custom_minimum_size.y=12;content.add_child(gap)
 else:
  var keys: Array=recipe.subtabs[tab][subtabs[tab]] if recipe.subtabs.has(tab) else recipe.sections.get(tab,[])
  if tab=="Health" and subtabs.get(tab)=="Description": keys=["identity"]
  for key in keys: section(content,key,keys.size()>1)
  if tab=="Health" and subtabs.get(tab)=="Description":
   var gap := Control.new();gap.custom_minimum_size.y=12;content.add_child(gap)
   paragraph(content,NativeText.attribute_description(self,int(detail.get("sex",-1))))
 scroll.set_deferred("scroll_vertical",int(scrolls.get(location(),0)))
