#pragma once
// Opt-in diagnostic history. No rendering decisions depend on this data.
#include <algorithm>
#include <array>
#include <cstdint>
#include <map>
#include <tuple>
#include <vector>

namespace df3d_godot {
struct LayoutCausalProbe {
    using Tile = std::tuple<int,int,int>; // z,x,y
    struct Causes { int itemUpdates=0, unitArrivals=0, unitDepartures=0; };
    struct TileRow {
        Tile tile;
        Causes causes;
        int itemPieces=0, unitPieces=0, changedItems=0;
    };
    struct Row {
        uint64_t timestampUs=0, tick=0;
        bool scopeReset=false, viewDirty=false;
        int changedItems=0, tilesApplied=0;
        std::vector<TileRow> tiles;
    };
    static constexpr size_t Limit=32, TileLimit=8;
    bool active=false;
    Row current;
    std::map<Tile,Causes> causes;
    std::vector<Row> rows;

    void begin(bool enabled,uint64_t timestamp,uint64_t tick,bool scope,bool view) {
        active=enabled;
        if(!active)return;
        current={timestamp,tick,scope,view}; causes.clear();
    }
    void item(Tile tile) { if(active)++causes[tile].itemUpdates; }
    void arrival(Tile tile) { if(active)++causes[tile].unitArrivals; }
    void departure(Tile tile) { if(active)++causes[tile].unitDepartures; }
    void applied(Tile tile,int items,int units,int changed) {
        if(!active)return;
        ++current.tilesApplied; current.changedItems+=changed;
        if(!changed)return;
        const auto found=causes.find(tile);
        current.tiles.push_back({tile,found==causes.end()?Causes{}:found->second,items,units,changed});
        std::stable_sort(current.tiles.begin(),current.tiles.end(),[](auto& a,auto& b){return a.changedItems>b.changedItems;});
        if(current.tiles.size()>TileLimit)current.tiles.resize(TileLimit);
    }
    void finish() {
        if(!active || !current.changedItems)return;
        rows.push_back(current);
        std::stable_sort(rows.begin(),rows.end(),[](auto& a,auto& b){return a.changedItems>b.changedItems;});
        if(rows.size()>Limit)rows.resize(Limit);
    }
};
}
