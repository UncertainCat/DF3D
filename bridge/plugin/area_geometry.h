#pragma once
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <type_traits>
#include <utility>
#include <vector>

namespace df3d_area {
// One semantic paint can cover the complete supported footprint. A maximally
// fragmented request has one span per cell; limits bound allocation/payload,
// rather than requiring presentation-side partial commits.
constexpr uint32_t kMaxSide=256,kMaxCells=32768,kMaxSpans=kMaxCells,kMaxPaintTiles=kMaxCells,kMaxRaws=65536;
constexpr uint32_t bulkSteps(size_t count) { return uint32_t((count+255)/256); }
constexpr uint32_t assignmentPreparationSteps(size_t refs,size_t targetUnits,size_t oldUnits,
                                             size_t cagesChanged,size_t cageEntries) {
  return 5+uint32_t(cagesChanged)+bulkSteps(cageEntries)+bulkSteps(refs+1)+bulkSteps(targetUnits+oldUnits+1);
}
template<class T> std::vector<T> withoutValue(const std::vector<T>& source,T ignored,size_t extra=0) {
  std::vector<T> values;values.reserve(source.size()+extra);
  for(auto value:source)if(value!=ignored)values.push_back(value);
  return values;
}
// These scans are shared with the native unit-assignment producer. Returned
// pointers are request-local; no mutation or allocation ownership is transferred.
enum class AssignmentScanError { None, Limit, Budget, Invalid, Multiple };
template<class Reference> struct ZoneReferenceScan {
  AssignmentScanError error=AssignmentScanError::None;
  uint32_t steps=0;Reference* previous=nullptr;
};
template<class Reference,class IsZone>
ZoneReferenceScan<Reference> scanZoneReferences(const std::vector<Reference*>& references,IsZone isZone,uint32_t budget) {
  ZoneReferenceScan<Reference> result;
  if(references.size()>256){result.error=AssignmentScanError::Limit;return result;}
  for(auto* reference:references) {
    if(result.steps==budget){result.error=AssignmentScanError::Budget;return result;}
    ++result.steps;
    if(!reference){result.error=AssignmentScanError::Invalid;return result;}
    if(isZone(reference)) {
      if(result.previous){result.error=AssignmentScanError::Multiple;return result;}
      result.previous=reference;
    }
  }
  return result;
}
template<class Cage> struct CageAssignmentScan {
  AssignmentScanError error=AssignmentScanError::None;
  uint32_t steps=0;size_t entries=0;
  std::vector<Cage*> affected;
};
template<class Cage>
CageAssignmentScan<Cage> scanAssignedCages(const std::vector<Cage*>& cages,int32_t unit,uint32_t budget) {
  CageAssignmentScan<Cage> result;
  if(cages.size()>256){result.error=AssignmentScanError::Limit;return result;}
  for(auto* cage:cages) {
    if(result.steps==budget){result.error=AssignmentScanError::Budget;return result;}
    ++result.steps;
    if(!cage){result.error=AssignmentScanError::Invalid;return result;}
    if(cage->assigned_units.size()>256-result.entries){result.error=AssignmentScanError::Limit;return result;}
    result.entries+=cage->assigned_units.size();bool found=false;
    for(auto id:cage->assigned_units) {
      if(result.steps==budget){result.error=AssignmentScanError::Budget;return result;}
      ++result.steps;found=found || id==unit;
    }
    if(found)result.affected.push_back(cage);
  }
  return result;
}
template<class Cage>
auto prepareCageAssignments(const std::vector<Cage*>& affected,int32_t unit) {
  std::vector<std::pair<Cage*,std::vector<int32_t>>> plans;plans.reserve(affected.size());
  for(auto* cage:affected)plans.emplace_back(cage,withoutValue(cage->assigned_units,unit));
  return plans;
}
struct LocationMembership {
  std::vector<int32_t> previous,next;
  bool removePrevious=false,assignNext=false;
};
inline LocationMembership prepareLocationMembership(const std::vector<int32_t>* previous,
                                                    const std::vector<int32_t>* next,int32_t zone) {
  LocationMembership result;
  result.removePrevious=previous && previous!=next;result.assignNext=next!=nullptr;
  if(result.removePrevious) {
    result.previous=withoutValue(*previous,zone);
    std::sort(result.previous.begin(),result.previous.end());
  }
  if(next) {
    result.next=withoutValue(*next,zone,1);result.next.push_back(zone);
    std::sort(result.next.begin(),result.next.end());
  }
  return result;
}

enum class LinkError { None, Budget, Limit, Invalid };
struct LinkResult { LinkError error=LinkError::None; uint32_t steps=0; };
// Prepare both sorted endpoints before changing either native vector. The four
// bulk passes cover validation, copying, insertion/erase shifts and reallocation.
// Binary searches are charged individually (at most 11 comparisons per end).
template<class A,class B,class Left,class Right>
LinkResult editLinks(A& first,B& second,Left left,Right right,bool unlink,uint32_t budget) {
  if(!budget)return {LinkError::Budget,0};
  if(first.size()>1024 || second.size()>1024)return {LinkError::Limit,1};
  const uint32_t cost=23+4*bulkSteps(first.size()+1)+4*bulkSteps(second.size()+1);
  if(cost>budget)return {LinkError::Budget,1};
  const auto valid=[](const auto& v) {
    int32_t last=-1;
    for(const auto* item:v){if(!item || item->id<0 || item->id<=last)return false;last=item->id;}
    return true;
  };
  if(!left || !right || !valid(first) || !valid(second))return {LinkError::Invalid,cost};
  const auto position=[](const auto& v,int32_t id) {
    return size_t(std::lower_bound(v.begin(),v.end(),id,[](const auto* p,int32_t key){return p->id<key;})-v.begin());
  };
  const auto a=position(first,left->id),b=position(second,right->id);
  const bool hasA=a<first.size() && first[a]->id==left->id;
  const bool hasB=b<second.size() && second[b]->id==right->id;
  if(!unlink && ((!hasA && first.size()==1024) || (!hasB && second.size()==1024)))return {LinkError::Limit,cost};
  A preparedA=first;B preparedB=second;
  if(unlink){if(hasA)preparedA.erase(preparedA.begin()+a);if(hasB)preparedB.erase(preparedB.begin()+b);}
  else {if(!hasA)preparedA.insert(preparedA.begin()+a,left);if(!hasB)preparedB.insert(preparedB.begin()+b,right);}
  first.swap(preparedA);second.swap(preparedB);
  return {LinkError::None,cost};
}

// Hash signed/unsigned integers as eight little-endian bytes. Never route a
// native revision through Lua's floating-point arithmetic or a renderer type.
struct Revision {
  uint64_t bits=14695981039346656037ULL;
  template<class Integer> void add(Integer value) {
    static_assert(std::is_integral_v<Integer> || std::is_enum_v<Integer>);
    uint64_t n=static_cast<uint64_t>(value);
    for(unsigned i=0;i<8;++i){bits^=n&0xff;bits*=1099511628211ULL;n>>=8;}
  }
  static constexpr uint64_t normalize(uint64_t value) {
    value&=0x7fffffffffffffffULL;return value ? value : 1;
  }
  uint64_t finish() const { return normalize(bits); }
};

enum class Error { None, InvalidExtent, InvalidSpan, TooManySpans, TooManyTiles,
                   TooLarge, Empty, InvalidMode, Budget, TooManyRaws, InvalidMask, InvalidSite };
struct FillResult { Error error=Error::None; uint32_t steps=0; bool resized=false; };
// Private settings partitions. Zero from a classifier means ineligible; a
// zero selection means all eligible members, not every raw entry.
enum SettingPartition : uint16_t { Any=1, Metal=2, Stone=4, Gem=8,
                                  MetalOres=16, Economic=32, Clay=64, OtherStone=128 };

// Preset SET imports clear each active vector before populating it. Keep the
// original buffers by swapping them out, not by copying possibly oversized
// stored tails. Rollback is noexcept and restores the exact original buffers.
// Null slots represent native fields the importer never touches (ore.mats).
template<class Vector,size_t Count> class PresetVectors {
  std::array<Vector*,Count> targets_;
  std::array<Vector,Count> saved_{};
  bool active_=true;
public:
  explicit PresetVectors(const std::array<Vector*,Count>& targets) noexcept : targets_(targets) {
    static_assert(noexcept(std::declval<Vector&>().swap(std::declval<Vector&>())));
    for(size_t i=0;i<Count;++i)if(targets_[i])targets_[i]->swap(saved_[i]);
  }
  PresetVectors(const PresetVectors&)=delete;
  PresetVectors& operator=(const PresetVectors&)=delete;
  ~PresetVectors() { if(active_)for(size_t i=0;i<Count;++i)if(targets_[i])targets_[i]->swap(saved_[i]); }
  void commit() noexcept {active_=false;}
};

struct SettingsRawTotal {bool valid=true;uint32_t count=0;};
template<class Counts> SettingsRawTotal settingsRawTotal(const Counts& counts) {
  SettingsRawTotal total;
  for(const auto count:counts) {
    // Subtraction avoids overflow even when a native vector length is corrupt.
    if(count>kMaxRaws-total.count)return {false,total.count};
    total.count+=uint32_t(count);
  }
  return total;
}

// Quality arrays and scalar switches have fixed native storage. Require a mask
// for the complete field before writing: accepting a short or oversized mask
// would silently drop a requested member or reach a different native field.
template<class Value,class Members,class Allowed>
FillResult fillFixedSettings(Value* values,size_t count,const Members& members,const Allowed& allowed,
                             bool enabled,uint32_t budget) {
  if(!budget)return {Error::Budget,0,false};
  if(count>kMaxRaws)return {Error::TooManyRaws,1,false};
  if((count && !values) || members.size()!=count || allowed.size()!=count)
    return {Error::InvalidMask,1,false};
  const uint32_t steps=1+bulkSteps(count);
  if(steps>budget)return {Error::Budget,1,false};
  for(size_t i=0;i<count;++i)if(members[i] && allowed[i])values[i]=enabled;
  return {Error::None,steps,false};
}

// Masks are indexed by raw id, allowing one counted pass across each vector.
// On resize the serializer's rule covers ALL disallowed entries, not just the
// appended tail. Without resize only allowed members change. Never shrink.
template<class Vector,class Members,class Allowed>
FillResult fillSettings(Vector& values,size_t raws,const Members& members,const Allowed& allowed,
                        bool enabled,uint32_t budget) {
  if(!budget)return {Error::Budget,0,false};
  if(raws>kMaxRaws)return {Error::TooManyRaws,1,false};
  if(members.size()!=raws || allowed.size()!=raws)return {Error::InvalidMask,1,false};
  const uint32_t steps=1+bulkSteps(raws);
  if(steps>budget)return {Error::Budget,1,false};
  const bool resize=values.size()<raws;
  if(resize)values.resize(raws,0);
  for(size_t i=0;i<raws;++i) {
    if(resize && !allowed[i])values[i]=1;
    else if(members[i] && allowed[i])values[i]=enabled?1:0;
  }
  return {Error::None,steps,resize};
}

// Build eligibility from current raws inside this update; never require a
// warmed label cache. One counted classification pass precedes the existing
// fill pass. All masks and row validity are ready before touching native data.
template<class Vector,class Classify>
FillResult fillClassifiedSettings(Vector& values,size_t raws,uint16_t selection,int32_t row,
                                 Classify classify,bool enabled,uint32_t budget) {
  if(!budget)return {Error::Budget,0,false};
  if(raws>kMaxRaws)return {Error::TooManyRaws,1,false};
  if(row< -1 || (row>=0 && size_t(row)>=raws))return {Error::InvalidMask,1,false};
  const auto scan=bulkSteps(raws),cost=1+2*scan;
  if(cost>budget)return {Error::Budget,1,false};
  std::vector<uint8_t> members(raws),allowed(raws);
  for(size_t i=0;i<raws;++i) {
    const uint16_t partition=classify(i);
    allowed[i]=partition!=0;
    members[i]=partition && (!selection || (partition&selection)) && (row<0 || size_t(row)==i);
  }
  if(row>=0 && !members[size_t(row)])return {Error::InvalidMask,1+scan,false};
  auto result=fillSettings(values,raws,members,allowed,enabled,budget-scan);
  result.steps+=scan;return result;
}

struct Span { int32_t y=0,x=0,length=0; };
struct Bounds { int32_t x=0,y=0,width=0,height=0; };
// Native extents must transfer their original allocation to DF. A vector cannot
// release its storage; copying it into a second allocation would add a full
// extent pass to the mutation budget. This buffer is move-only until commit.
template<class T> class NativeExtents {
  std::unique_ptr<T[]> data_;
  size_t count_=0;
public:
  using value_type=T;
  NativeExtents()=default;
  NativeExtents(NativeExtents&& other) noexcept
      :data_(std::move(other.data_)),count_(std::exchange(other.count_,0)){}
  NativeExtents& operator=(NativeExtents&& other) noexcept {
    if(this!=&other){data_=std::move(other.data_);count_=std::exchange(other.count_,0);}
    return *this;
  }
  size_t size() const {return count_;}
  T& operator[](size_t i){return data_[i];}
  const T& operator[](size_t i)const{return data_[i];}
  void resize(size_t count,int value) {
    auto next=std::make_unique<T[]>(count);
    if(value)std::fill_n(next.get(),count,static_cast<T>(value));
    data_=std::move(next);count_=count;
  }
  T* data() const {return data_.get();}
  T* release(){count_=0;return data_.release();}
};
template<class Storage> struct BasicPaintPlan {
  Error error=Error::None;
  Bounds bounds;
  Storage extents;
  uint32_t tiles=0,added=0,erased=0,requested=0,steps=0;
};
using PaintPlan=BasicPaintPlan<std::vector<uint8_t>>;
inline bool validBounds(const Bounds& b,bool empty=false) {
  if(empty && !b.width && !b.height)return true;
  return b.x>=0 && b.y>=0 && b.width>0 && b.height>0 &&
      b.width<=int32_t(kMaxSide) && b.height<=int32_t(kMaxSide) &&
      uint64_t(b.width)*b.height<=kMaxCells &&
      int64_t(b.x)+b.width-1<=32767 && int64_t(b.y)+b.height-1<=32767;
}

// Plans in private storage; no native mutation occurs on any refusal. Add grows
// the existing rectangle; erase keeps it and changes occupied cells, preserving
// the coordinate basis of retained extents. A caller validates visibility/site,
// container limits, revision and retire capacity before committing this plan.
struct AllowPaintTile {
  bool operator()(int32_t,int32_t,int64_t,int64_t)const{return true;}
};
template<class Storage=std::vector<uint8_t>,class Extents,class Spans,class CheckTile=AllowPaintTile>
BasicPaintPlan<Storage> paint(const Bounds& before,const Extents& existing,const Spans& spans,
                uint8_t mode,uint32_t budget=UINT32_MAX,CheckTile checkTile={},bool allowEmpty=false) {
  BasicPaintPlan<Storage> out;out.bounds=before;
  using Value=typename Storage::value_type;
  const auto fail=[&](Error error){out.error=error;return std::move(out);};
  if(!budget)return fail(Error::Budget);
  out.steps=1;
  if(mode!=1 && mode!=2 && mode!=3)return fail(Error::InvalidMode);
  const bool empty=before.width==0 && before.height==0;
  if(!validBounds(before,true) || existing.size()!=size_t(before.width)*before.height)
    return fail(Error::InvalidExtent);
  if(mode==3) {
    // Replacement describes the desired footprint, including holes. Build it
    // privately, then preflight removals and retained/new cells before commit.
    auto next=paint<Storage>(Bounds{},std::vector<uint8_t>{},spans,1,budget);
    if(next.error!=Error::None)return next;
    const uint64_t visits=existing.size()+next.extents.size();
    if(uint64_t(next.steps)+visits>budget)return fail(Error::Budget);
    next.added=0;next.erased=0;
    for(int32_t y=0;y<before.height;++y)for(int32_t x=0;x<before.width;++x) {
      ++next.steps;
      const auto raw=static_cast<int64_t>(existing[size_t(y)*before.width+x]);
      if(raw<0 || raw>(std::is_enum_v<Value>?4:1))return fail(Error::InvalidExtent);
      const int32_t wx=before.x+x,wy=before.y+y;
      const int32_t nx=wx-next.bounds.x,ny=wy-next.bounds.y;
      const bool kept=nx>=0 && ny>=0 && nx<next.bounds.width && ny<next.bounds.height &&
          next.extents[size_t(ny)*next.bounds.width+nx]!=Value{};
      if(raw && !kept) {
        if(!checkTile(wx,wy,raw,0))return fail(Error::InvalidSite);
        ++next.erased;
      }
    }
    for(int32_t y=0;y<next.bounds.height;++y)for(int32_t x=0;x<next.bounds.width;++x) {
      ++next.steps;
      auto& value=next.extents[size_t(y)*next.bounds.width+x];
      if(value==Value{})continue;
      const int32_t wx=next.bounds.x+x,wy=next.bounds.y+y;
      const int32_t ox=wx-before.x,oy=wy-before.y;
      const auto raw=ox>=0 && oy>=0 && ox<before.width && oy<before.height ?
          static_cast<int64_t>(existing[size_t(oy)*before.width+ox]):0;
      if(!checkTile(wx,wy,raw,raw?raw:1))return fail(Error::InvalidSite);
      if(raw)value=static_cast<Value>(raw);else ++next.added;
    }
    return next;
  }
  if(spans.empty())return fail(Error::InvalidSpan);
  if(spans.size()>kMaxSpans)return fail(Error::TooManySpans);
  if(1+spans.size()>budget)return fail(Error::Budget);
  int64_t left=empty?32768:before.x,top=empty?32768:before.y;
  int64_t right=empty?-1:int64_t(before.x)+before.width-1,bottom=empty?-1:int64_t(before.y)+before.height-1;
  for(const auto& span:spans) {
    ++out.steps;
    if(span.x<0 || span.y<0 || span.y>32767 || span.length<1 ||
        int64_t(span.x)+span.length-1>32767)return fail(Error::InvalidSpan);
    if(uint64_t(out.requested)+uint64_t(span.length)>kMaxPaintTiles)return fail(Error::TooManyTiles);
    out.requested+=uint32_t(span.length);
    if(mode==1) {
      left=std::min(left,int64_t(span.x));top=std::min(top,int64_t(span.y));
      right=std::max(right,int64_t(span.x)+span.length-1);bottom=std::max(bottom,int64_t(span.y));
    }
  }
  if(mode==2 && empty)return fail(Error::Empty);
  const Bounds next{int32_t(left),int32_t(top),int32_t(right-left+1),int32_t(bottom-top+1)};
  if(!validBounds(next))return fail(Error::TooLarge);
  const size_t cells=size_t(next.width)*next.height;
  const uint32_t copySteps=bulkSteps(cells);
  if(out.steps+copySteps+out.requested>budget)return fail(Error::Budget);
  out.bounds=next;out.extents.resize(cells,0);out.steps+=copySteps;
  for(int32_t y=0;y<before.height;++y)for(int32_t x=0;x<before.width;++x) {
    const auto value=existing[size_t(y)*before.width+x];
    // Native enums retain wall/interior/distance-boundary bytes (2..4).
    // Wire-normalized byte vectors still accept only occupancy bits 0 and 1.
    const auto raw=static_cast<int64_t>(value);
    if(raw<0 || raw>(std::is_enum_v<Value>?4:1))return fail(Error::InvalidExtent);
    const size_t index=size_t(before.y+y-next.y)*next.width+before.x+x-next.x;
    out.extents[index]=static_cast<Value>(raw);out.tiles+=raw!=0;
  }
  for(const auto& span:spans)for(int32_t x=span.x;x<span.x+span.length;++x) {
    ++out.steps;
    const bool inside=x>=next.x && x<next.x+next.width && span.y>=next.y && span.y<next.y+next.height;
    const size_t index=inside?size_t(span.y-next.y)*next.width+x-next.x:0;
    const auto raw=inside?static_cast<int64_t>(out.extents[index]):0;
    const auto after=mode==1?(raw?raw:1):0;
    // Site validation and private edit planning share the counted tile visit.
    // The callback may collect a commit list, but must not mutate native state.
    if(!checkTile(x,span.y,raw,after))return fail(Error::InvalidSite);
    if(!inside)continue;
    auto& value=out.extents[index];
    if(mode==1 && value==Value{}){value=static_cast<Value>(1);++out.tiles;++out.added;}
    else if(mode==2 && value!=Value{}){value=Value{};--out.tiles;++out.erased;}
  }
  // Native zone Paint keeps the allocated footprint and identity after erasing
  // its last cell. Exit handles deletion separately; adding can reuse the mask.
  // Other callers retain their existing policy until independently verified.
  if(!out.tiles && !allowEmpty)return fail(Error::Empty);
  return out;
}
} // namespace df3d_area
