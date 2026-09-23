#pragma once
#include "wm/types.h"
#include <cmath>
#include <array>
#include <map>
#include <tuple>
#include <bitset>

namespace df3d::mesher {
inline uint8_t supportShape(const wm::TileState& t,bool reveal) {
    if(!reveal && (t.flags & wm::kTileHidden) && !(t.flags & wm::kTileDigDesignated))return 2;
    if(t.shape==wm::TileShape::Ramp)return 1;
    if(t.shape==wm::TileShape::Wall || t.shape==wm::TileShape::Fortification ||
        t.shape==wm::TileShape::TreeTrunk || t.shape==wm::TileShape::Unknown)return 2;
    return 0;
}
// Shape-only gate: liquid/material/designation art must not touch support pages.
class TerrainSupportDependencies {
    std::map<std::tuple<int,int,int>,std::array<uint8_t,wm::kTilesPerBlock>> observed_;
public:
    void clear() { observed_.clear(); }
    std::bitset<wm::kTilesPerBlock> observe(wm::BlockPos p,const wm::TileState* tiles,bool reveal) {
        std::array<uint8_t,wm::kTilesPerBlock> next{};
        for(size_t i=0;i<next.size();++i)if(tiles)next[i]=supportShape(tiles[i],reveal);
        const auto key=std::tuple{p.bx,p.by,p.bz};
        auto old=observed_.find(key);
        std::bitset<wm::kTilesPerBlock> changed;
        for(size_t i=0;i<next.size();++i)changed.set(i,old==observed_.end() || old->second[i]!=next[i]);
        observed_[key]=next;return changed;
    }
};
// Presentation ramp codes: flat, north, east, south, west, isolated platform.
// Matches block_mesher's cube classification and N/E/S/W high-side priority.
template<class Read> int rampSupportCode(wm::TilePos p, Read read, bool reveal) {
    const auto tile=read(p);
    if(!tile || supportShape(*tile,reveal)!=1)return 0;
    constexpr int dx[]={0,1,0,-1},dy[]={-1,0,1,0};
    for(int i=0;i<4;++i) {
        const auto t=read(wm::TilePos{p.x+dx[i],p.y+dy[i],p.z});
        if(t && supportShape(*t,reveal)==2)return i+1;
    }
    return 5;
}
struct GroundSupport { float dx, lift, dy; };
inline GroundSupport rampSupport(int code,float x,float y) {
    switch(code) {
        case 1:return {0,.9f*(1-y),-.9f};
        case 2:return {.9f,.9f*x,0};
        case 3:return {0,.9f*y,.9f};
        case 4:return {-.9f,.9f*(1-x),0};
        case 5:return {0,.4f,0};
        default:return {0,0,0};
    }
}
}
