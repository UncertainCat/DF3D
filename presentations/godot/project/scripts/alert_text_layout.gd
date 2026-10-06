extends RefCounted
# Index logical lines without materializing one Dictionary/String per occurrence.
# Duplicate immutable rows share wrap offsets; only visible lines create strings.
var entries:Array=[]
var ends:=PackedInt64Array()
var unique_wraps:=0
var span_count:=0
var characters_scanned:=0
var has_units:=false

func clear() -> void:
 entries=[];ends=PackedInt64Array();unique_wraps=0;span_count=0;characters_scanned=0;has_units=false

func build(rows:Array) -> void:
 clear()
 var cache:Dictionary={}
 for entry in rows:
  var row:Dictionary=entry.data
  var report:bool=entry.kind=="report"
  if not report and (int(row.get("category",-1))<0 or int(row.get("category",-1))>2):continue
  var source:String=str(row.get("text","")) if report else "The %s%s %s" % [row.get("profession",""),(" "+str(row.get("name",""))) if not str(row.get("name","")).is_empty() else "",["is fighting!","is sparring.","is hunting."][int(row.category)]]
  var repeat:int=int(row.get("repeat_count",0)) if report else 0
  var key:String=str(entry.kind)+":"+str(row.get("id",-1) if report else row.get("unit_id",-1))
  var layout:Dictionary={}
  for candidate in cache.get(key,[]):
   if is_same(candidate.row,row) or (candidate.source==source and candidate.repeat==repeat):layout=candidate;break
  if layout.is_empty():
   var text:String=source+(" x%d" % (repeat+1) if repeat>0 else "")
   var spans:=PackedInt32Array();var offset:=0;var length:=text.length()
   while length-offset>80:
    var split:int=text.substr(offset,80).rfind(" ")
    if split<=0:split=80
    spans.append(offset);spans.append(split+1 if split<80 else split)
    characters_scanned+=80;offset+=split
    if offset<length and text.unicode_at(offset)==32:offset+=1
   spans.append(offset);spans.append(length-offset)
   layout={"row":row,"source":source,"repeat":repeat,"text":text,"spans":spans}
   if not cache.has(key):cache[key]=[]
   cache[key].append(layout);unique_wraps+=1;span_count+=spans.size()/2
  var count:int=layout.spans.size()/2;var height:int=maxi(3,count)
  entries.append({"kind":entry.kind,"row":row,"layout":layout,"pad":(height-count)/2,"first":size()})
  ends.append(size()+height);has_units=has_units or not report

func size() -> int:
 return int(ends[ends.size()-1]) if not ends.is_empty() else 0

func at(index:int) -> Dictionary:
 assert(index>=0 and index<size())
 var low:=0;var high:=ends.size()
 while low<high:
  var middle:int=(low+high)/2
  if ends[middle]<=index:low=middle+1
  else:high=middle
 var entry:Dictionary=entries[low];var local:int=index-int(entry.first)
 var line:int=local-int(entry.pad);var spans:PackedInt32Array=entry.layout.spans
 return {"text":str(entry.layout.text).substr(spans[line*2],spans[line*2+1]) if line>=0 and line<spans.size()/2 else "","kind":entry.kind,"row":entry.row,"start":local==0}
