extends SceneTree
const View=preload("res://scripts/reports_view.gd")
# Compatibility oracle for existing wrapping; native visual evidence is separate.
func previous(text:String,columns:int) -> PackedStringArray:
 var lines:PackedStringArray=[]
 while text.length()>columns:
  var split:=text.rfind(" ",columns-1)
  if split<=0:split=columns
  lines.append(text.substr(0,split+1 if split<columns else split))
  text=text.substr(split).trim_prefix(" ")
 lines.append(text);return lines
func _initialize():call_deferred("run")
func run():
 var rng:=RandomNumberGenerator.new();rng.seed=74131
 var samples:Array=[""," ","  ","a ","☺ words  here", "line\nbreak", "界".repeat(500),"a".repeat(500)]
 for i in 100:
  var text:=""
  for j in rng.randi_range(1,1000):text += ["a","b"," "," ","☺","界","\n"][rng.randi_range(0,6)]
  samples.append(text)
 for text in samples:
  for columns in [1,2,7,80,108,110,112]:
   var expected:PackedStringArray=previous(text,columns)
   assert(View.wrap_report(text,columns)==expected)
   for limit in [0,1,2,29,55]:assert(View.wrap_report(text,columns,limit)==expected.slice(0,mini(limit,expected.size())))
 # Large text does not change output work for a bounded viewport request.
 var large:String="Native fixture words. ".repeat(50000)
 var work:Dictionary={"scanned":0}
 var bounded:PackedStringArray=View.wrap_report(large,112,55,work)
 assert(int(work.scanned)==55*112 and int(work.copied)<=2*55*112)
 var prefix_work:Dictionary={"scanned":0}
 View.wrap_report(large.substr(0,10000),112,55,prefix_work)
 assert(work==prefix_work)
 assert(bounded.size()==55 and bounded==View.wrap_report(large.substr(0,10000),112,55))
 var full:PackedStringArray=View.wrap_report(large,80)
 assert(full.size()>10000 and "".join(full)==large)
 var view=View.new();root.add_child(view);root.size=Vector2i(1200,800);view.position=Vector2(32,52)
 assert(view.visible_text_lines(96)==55)
 assert(view.visible_text_lines(748)==0)
 view.queue_free()
 print("REPORTS_WRAP_PASS");quit()
