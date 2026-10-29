extends SceneTree
const Entry=preload("res://scripts/farm_name_entry.gd")
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func key(entry,code: int,unicode:=0,pressed:=true,control:=false) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.unicode=unicode;event.pressed=pressed;event.ctrl_pressed=control
	entry.feed_key(event)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var entry:=Entry.new();root.add_child(entry);entry.set_process(false)
	var edits: Array=[];var submits: Array=[]
	entry.edited.connect(func(value):edits.append(value))
	entry.submitted.connect(func():submits.append(true))
	entry.begin("");entry.cursor_visible=true;entry._refresh()
	check(entry.text=="_","empty editing caption must not show default Farm Plot")
	for byte in "lower farm".to_utf8_buffer():key(entry,0,byte)
	check(entry.value=="lower farm" and entry.text=="Lower farm_" and edits.size()==10,"typing retains raw name and formats only display")
	entry.cursor_visible=false;entry._refresh();check(entry.text=="Lower farm","cursor off changes display only")
	key(entry,KEY_LEFT);key(entry,KEY_DELETE);key(entry,KEY_A,97,false);key(entry,KEY_A,97,true,true)
	check(edits.size()==10 and entry.value=="lower farm","navigation/release/control shortcut must not change draft")
	key(entry,KEY_BACKSPACE);check(entry.value=="lower far","backspace removes final byte")
	key(entry,KEY_ENTER);key(entry,KEY_KP_ENTER);check(submits.size()==2,"both Enter forms submit")
	entry.finish();key(entry,0,120);check(entry.value=="lower far","closed entry ignores keys")
	entry.begin("");entry.cursor_visible=true
	for index in 80:key(entry,0,120)
	check(entry.value=="x".repeat(30) and entry.text=="X"+"x".repeat(29)+"_","native thirty-byte limit")
	for index in 40:key(entry,KEY_BACKSPACE)
	check(entry.value.is_empty() and entry.text=="_","backspace clears without default caption")
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json"))
	for sample in fixture.rename_caption_reference.cases:
		entry.finish();entry.begin(sample.draft);entry.cursor_visible=sample.cursor_visible;entry._refresh()
		check(entry.text==sample.caption,"native caption reference "+sample.name)
	# Existing zone/stockpile behavior must retain its own twenty-byte limit.
	var area=preload("res://scripts/area_name_entry.gd").new();root.add_child(area);area.set_process(false);area.begin("")
	for index in 30:key(area,0,120)
	check(area.value.length()==20,"area editor limit changed")
	entry.queue_free();area.queue_free();await process_frame
	if failures==0:print("FARM_NAME_ENTRY_PASS")
	quit(0 if failures==0 else 1)
