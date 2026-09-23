#pragma once
// Native persistent contamination. Shares the terrain scan's bounded rotating
// schedule; wounded-unit and cleaning-job blocks get additional hints.
#include <algorithm>
#include <array>
#include <map>
#include <vector>
#include "df/block_square_event_material_spatterst.h"
#include "df/block_square_event_type.h"
#include "df/map_block.h"
#include "mirror_generated.h"

namespace df3d_ground_spatters {
namespace mir = df3d::mirror;
using Entry = std::array<uint16_t,4>; // tile, material, matter state, amount
struct Block { int32_t x=0,y=0,z=0; std::vector<Entry> entries; };
inline std::map<uint32_t,Block> blocks;
inline std::map<uint32_t,uint64_t> pending; // resend until this simulation tick
inline void reset() { blocks.clear(); pending.clear(); }
template<class Material>
void scan(uint32_t index,int32_t x,int32_t y,int32_t z,const df::map_block* native,
          uint64_t tick,Material material) {
  std::vector<Entry> entries;
  if(native) for(auto* base : native->block_events) {
    if(!base || base->getType()!=df::block_square_event_type::material_spatter) continue;
    const auto* event=static_cast<const df::block_square_event_material_spatterst*>(base);
    const int state=static_cast<int>(event->mat_state);
    if(state<0 || state>5) continue;
    const uint16_t mat=material(event->mat_type,event->mat_index);
    if(mat==65535) continue;
    for(int ly=0;ly<16;++ly) for(int lx=0;lx<16;++lx)
      if(const auto amount=event->amount[lx][ly]) entries.push_back({uint16_t(ly*16+lx),mat,uint16_t(state),amount});
  }
  std::sort(entries.begin(),entries.end());
  size_t count=0;
  for(const auto& entry:entries) {
    if(count && std::equal(entry.begin(),entry.begin()+3,entries[count-1].begin()))
      entries[count-1][3]=std::min(255,int(entries[count-1][3])+entry[3]);
    else entries[count++]=entry;
  }
  entries.resize(count);
  const auto old=blocks.find(index);
  if(old==blocks.end() && entries.empty()) return;
  if(old!=blocks.end() && old->second.entries==entries) return;
  blocks[index]={x,y,z,std::move(entries)};
  pending[index]=tick+120;
}
template<class Material>
auto build(flatbuffers::FlatBufferBuilder& f,bool full,uint64_t tick,Material material) {
  std::vector<flatbuffers::Offset<mir::SpatterBlock>> result;
  const auto add=[&](const Block& b) {
    std::vector<mir::GroundSpatter> entries;
    for(const auto& e:b.entries) entries.emplace_back(uint8_t(e[0]),uint8_t(e[3]),material(f,e[1]),static_cast<mir::MatterState>(e[2]));
    const auto data=f.CreateVectorOfStructs(entries);
    result.push_back(mir::CreateSpatterBlock(f,b.x,b.y,b.z,data));
  };
  if(full) { for(const auto& [id,b]:blocks) if(!b.entries.empty()) add(b); }
  else for(const auto& [id,until]:pending) { (void)until; add(blocks.at(id)); }
  return f.CreateVector(result);
}
// Only acknowledge after a successful publish. Empty removal records disappear
// after the repeat window; unchanged contaminated blocks remain cached.
inline void published(uint64_t tick) {
  for(auto it=pending.begin();it!=pending.end();) {
    if(it->second<tick) {
      const auto block=blocks.find(it->first);
      if(block!=blocks.end() && block->second.entries.empty()) blocks.erase(block);
      it=pending.erase(it);
    } else ++it;
  }
}
}
