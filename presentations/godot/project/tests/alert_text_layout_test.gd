extends SceneTree
const Layout=preload("res://scripts/alert_text_layout.gd")
const TEXT_BYTES=33554432-512-65536*16 # Exact group accounted-payload bound with65536 duplicates.
const Reports=preload("res://scripts/reports_view.gd")
func _initialize() -> void:
 var rows:Array=[];var expected:Array=[]
 var random:=RandomNumberGenerator.new();random.seed=719
 for id in 70:
  var text:=""
  for i in random.randi_range(0,4096):text+=["a","b"," ","☺","\n"][random.randi_range(0,4)]
  var repeat:int=id%3
  rows.append({"kind":"report","data":{"id":id%7,"text":text,"repeat_count":repeat}})
  var wrapped:PackedStringArray=Reports.wrap_report(text+(" x%d"%(repeat+1) if repeat>0 else ""),80)
  var height:int=maxi(3,wrapped.size());var pad:int=(height-wrapped.size())/2
  for i in height:expected.append({"text":wrapped[i-pad] if i>=pad and i<pad+wrapped.size() else "","start":i==0,"row":rows.back().data})
 var layout=Layout.new();layout.build(rows)
 assert(layout.size()==expected.size())
 for i in expected.size():
  var actual:Dictionary=layout.at(i)
  assert(actual.text==expected[i].text and actual.start==expected[i].start and actual.row==expected[i].row)
 # Valid repeated identities can span more than2^31 logical lines without
 # expanding line strings/dictionaries or wrapping the same text per occurrence.
 rows=[]
 var entry:Dictionary={"kind":"report","data":{"id":17,"text":"x".repeat(TEXT_BYTES)}}
 for i in 65536:rows.append(entry)
 layout.build(rows)
 var per_entry:int=(TEXT_BYTES+79)/80
 assert(layout.unique_wraps==1 and layout.span_count==per_entry)
 assert(layout.entries.size()==65536 and layout.ends.size()==65536)
 assert(layout.size()==per_entry*65536 and layout.size()>2147483647)
 assert(layout.characters_scanned<TEXT_BYTES)
 for i in [0,per_entry-1,per_entry,layout.size()-1]:
  var line:Dictionary=layout.at(i)
  assert(line.text==("x".repeat(TEXT_BYTES%80 if TEXT_BYTES%80 else 80) if i%per_entry==per_entry-1 else "x".repeat(80)))
  assert(line.start==(i%per_entry==0))
 layout.clear();assert(layout.size()==0 and layout.entries.is_empty() and layout.span_count==0)
 layout.build([{"kind":"unit","data":{"unit_id":17,"category":1,"profession":"Fixture","name":"Unit"}}])
 assert(layout.has_units and layout.size()==3 and layout.at(1).text=="The Fixture Unit is sparring.")
 print("ALERT_TEXT_LAYOUT_PASS");quit()
