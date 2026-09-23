#pragma once
#include <algorithm>
#include "df3d_mesher/block_mesher.h"
#include <cmath>
#include <unordered_map>
#include <tuple>
#include <vector>

namespace df3d::mesher {
inline constexpr float kPieceCeiling = 1.0f-kFloorHeight-.005f;
struct DepthFootprint {
    float x, y, halfX, halfY;
    int z;
    // Input is ordered: furniture, then the item hierarchy/quantity layers, then units.
    int category = 1;
};
struct DepthInterval { float bottom = 0, thickness = 0; };
// Category-local ordinals remain resident; only these shared tile inputs vary.
inline DepthInterval sharedStackInterval(float support,int objects,int creatures,int category,int ordinal) {
    const float low=std::clamp(support,0.0f,kPieceCeiling-.01f)+.005f;
    const float step=std::min(.13f,(kPieceCeiling-low)/std::max(1,objects+creatures));
    return {low+(ordinal+(category==3?objects:0))*step,step*(.12f/.13f)};
}
// Furniture owns a persistent band. Moving occupants only divide the space above.
inline constexpr float kBuildingBottom=.005f, kBuildingThickness=.12f;
inline constexpr float kBuildingSpillBias=.004f;
// Reserve all fixed decal priorities below the furniture base.
inline constexpr float kInstallationBottom=.004f;
inline DepthInterval buildingDepth(int originY,int drawY,bool furniture=true) {
    if(!furniture)return {kInstallationBottom,0};
    const float north=float(std::max(0,originY-drawY));
    return {kBuildingBottom,kBuildingThickness+kBuildingSpillBias*north/(north+1)};
}
using DepthTile = std::tuple<int,int,int>;
struct DepthTileHash {
    size_t operator()(const DepthTile& tile) const noexcept {
        size_t seed=std::hash<int>{}(std::get<0>(tile));
        for(const int value : {std::get<1>(tile),std::get<2>(tile)})
            seed ^= std::hash<int>{}(value)+size_t(0x9e3779b9)+(seed<<6)+(seed>>2);
        return seed;
    }
};
inline DepthTile depthTile(const DepthFootprint& p) {
    return {p.z,int(std::floor(p.x)),int(std::floor(p.y))};
}
// A stack belongs to one DF tile. Artwork touching or extending into another
// tile does not turn its neighbour into a supporting platform.
inline std::vector<DepthInterval> depthLayout(const std::vector<DepthFootprint>& p,
                                             float ceiling = kPieceCeiling,
                                             const std::vector<float>& supports = {}) {
    ceiling=std::clamp(ceiling,.01f,kPieceCeiling);
    struct Pile { int count=0, next=0; float support=0; };
    // Lookup only: input order, never table iteration, owns pile ordering.
    std::unordered_map<DepthTile,Pile,DepthTileHash> piles;
    piles.reserve(p.size());
    for(int i=0;i<int(p.size());++i) {
        auto& pile=piles[depthTile(p[i])]; ++pile.count;
        if(i<int(supports.size()))pile.support=std::max(pile.support,supports[i]);
    }
    std::vector<DepthInterval> out(p.size());
    for(int i=0;i<int(p.size());++i) {
        auto& pile=piles[depthTile(p[i])];
        const float low=std::clamp(pile.support,0.0f,ceiling-.01f)+.005f;
        const float step=std::min(.13f,(ceiling-low)/pile.count);
        out[i]={low+pile.next++*step,step*(.12f/.13f)};
    }
    return out;
}

// Foreground is part of its owner's fixed artwork, never a second physical
// platform. Installation art does not move when contents enter or leave a tile.
inline std::vector<DepthInterval> drawDepthLayout(
    const std::vector<DepthFootprint>& p, const std::vector<int>& parent,
    const std::vector<float>& supports = {}) {
    std::unordered_map<DepthTile,float,DepthTileHash> support;
    for(int i=0;i<int(p.size());++i) {
        auto& top=support[depthTile(p[i])];
        if(i<int(supports.size()))top=std::max(top,supports[i]);
        if(p[i].category==1)top=std::max(top,kBuildingBottom+kBuildingThickness+kBuildingSpillBias);
        if(p[i].category==0)top=std::max(top,kInstallationBottom);
    }
    std::vector<DepthFootprint> moving;
    std::vector<float> movingSupports;
    std::vector<int> indices(p.size(),-1);
    for(int i=0;i<int(p.size());++i)if(p[i].category==2 || p[i].category==3) {
        indices[i]=int(moving.size());moving.push_back(p[i]);
        movingSupports.push_back(support[depthTile(p[i])]);
    }
    const auto allocated=depthLayout(moving,kPieceCeiling,movingSupports);
    std::vector<DepthInterval> result(p.size());
    for(int i=0;i<int(p.size());++i) {
        if(indices[i]>=0)result[i]=allocated[indices[i]];
        else if(p[i].category==4) {
            const int owner=i<int(parent.size())?parent[i]:-1;
            result[i]=owner>=0 && owner<i && depthTile(p[owner])==depthTile(p[i])
                ?result[owner]:buildingDepth(0,0);
        } else result[i]=buildingDepth(0,0,p[i].category==1);
    }
    return result;
}
}
