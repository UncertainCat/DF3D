#pragma once

#include <array>
#include <cstdint>
#include <map>
#include <set>
#include <utility>

// Native designation bits may become jobs before the operation completes.
// Keep that semantic pending-work index independent of DF pointers and drawing.
namespace df3d_pending_work {
enum class Kind : uint8_t { None=0, Dig=1, Smooth=2, Engrave=4, Chop=8, Gather=16 };
using Tile = std::array<int32_t,3>;
using Tiles = std::map<Tile,uint8_t>;
using Blocks = std::set<Tile>;

// Preserve the exact operation separately from cancellation/flag families.
template<class Operation,class JobType> Operation operation(JobType type) {
    switch(type) {
    case JobType::Dig: return Operation::Dig;
    case JobType::DigChannel: return Operation::Channel;
    case JobType::CarveUpwardStaircase: return Operation::StairUp;
    case JobType::CarveDownwardStaircase: return Operation::StairDown;
    case JobType::CarveUpDownStaircase: return Operation::StairUpDown;
    case JobType::CarveRamp: return Operation::Ramp;
    case JobType::RemoveConstruction: return Operation::RemoveConstruction;
    case JobType::CarveFortification: return Operation::Fortify;
    case JobType::FellTree: return Operation::Chop;
    case JobType::GatherPlants: return Operation::Gather;
    case JobType::SmoothWall:
    case JobType::SmoothFloor: return Operation::Smooth;
    case JobType::DetailWall:
    case JobType::DetailFloor: return Operation::Engrave;
    default: return Operation::None;
    }
}

template<class JobType> Kind classify(JobType type) {
    switch(type) {
    case JobType::Dig:
    case JobType::CarveUpwardStaircase:
    case JobType::CarveDownwardStaircase:
    case JobType::CarveUpDownStaircase:
    case JobType::CarveRamp:
    case JobType::RemoveConstruction:
    case JobType::DigChannel: return Kind::Dig;
    case JobType::SmoothWall:
    case JobType::SmoothFloor:
    case JobType::CarveFortification: return Kind::Smooth;
    case JobType::DetailWall:
    case JobType::DetailFloor: return Kind::Engrave;
    case JobType::FellTree: return Kind::Chop;
    case JobType::GatherPlants: return Kind::Gather;
    default: return Kind::None;
    }
}
inline bool valid(Tile tile, Tile size) {
    for(int i=0;i<3;++i) if(tile[i]<0 || tile[i]>=size[i]) return false;
    return true;
}
inline Tile blockOf(Tile tile) { return {tile[0]/16,tile[1]/16,tile[2]}; }
inline void add(Tiles& tiles, Tile tile, Kind kind, Tile size) {
    if(kind!=Kind::None && valid(tile,size)) tiles[tile] |= uint8_t(kind);
}
inline bool matchesRemoval(Kind kind, bool detail) {
    return detail ? kind==Kind::Smooth || kind==Kind::Engrave : kind==Kind::Dig;
}
inline bool inRect(Tile tile, int x1, int y1, int x2, int y2, int z) {
    return tile[2]==z && tile[0]>=x1 && tile[0]<=x2 && tile[1]>=y1 && tile[1]<=y2;
}
class Index {
    Tiles tiles_;
public:
    uint8_t at(Tile tile) const {
        const auto found=tiles_.find(tile);
        return found==tiles_.end()?0:found->second;
    }
    Blocks replace(Tiles next) {
        Blocks changed;
        for(const auto& [tile,flags]:next) if(at(tile)!=flags) changed.insert(blockOf(tile));
        for(const auto& [tile,flags]:tiles_) if(!next.count(tile)) changed.insert(blockOf(tile));
        tiles_=std::move(next);
        return changed;
    }
};
} // namespace df3d_pending_work
