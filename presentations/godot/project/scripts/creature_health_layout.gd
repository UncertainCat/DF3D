extends RefCounted
# Native858550/8599f0 text presentation. [P] indentation affects wrapping,
# then8598a0 trims it from emitted lines. Source words/colors remain native.
var lines: Array=[]
var current: Array=[]
var word: Array=[]
var color:=7
var width:=53
func emit_line() -> void:
 while not current.is_empty() and current[0][0]==" ":current.pop_front()
 while not current.is_empty() and current[-1][0]==" ":current.pop_back()
 if not current.is_empty():
  var text:="";var colors:=PackedInt32Array()
  for cell in current:text+=cell[0];colors.append(cell[1])
  lines.append({"text":text,"colors":colors})
 current=[]
func flush_word() -> void:
 if word.is_empty():return
 while current.size()+word.size()>width and not current.is_empty():
  var combined:=current.duplicate();combined.append([" ",color]);combined.append_array(word)
  var split:=mini(width,combined.size()-1)
  while split>=0 and combined[split][0]!=" ":split-=1
  if split<0:emit_line();break
  current=combined.slice(0,split);word=combined.slice(split+1);emit_line()
 if not current.is_empty():current.append([" ",color])
 current.append_array(word);word=[]
func build(source: String, columns: int) -> Array:
 lines=[];current=[];word=[];color=7;width=maxi(1,columns)
 var index:=0
 while index<source.length():
  var ch:=source[index]
  if ch=="[":
   var end:=source.find("]",index+1)
   if end>=0:
    var tag:=source.substr(index+1,end-index-1)
    if tag.begins_with("C:"):
     var values:=tag.split(":")
     if values.size()>=4:color=int(values[1])+8*int(values[2])+64*int(values[3])
     index=end+1;continue
    if tag in ["B","P","R"]:
     flush_word();emit_line()
     if tag=="B":lines.append({"text":"","colors":PackedInt32Array()})
     elif tag=="P":
      for _i in 4:current.append([" ",color])
     index=end+1;continue
  if ch==" ":flush_word()
  else:word.append([ch,color])
  index+=1
 flush_word();emit_line()
 if source.is_empty():lines.append({"text":"","colors":PackedInt32Array()})
 return lines
