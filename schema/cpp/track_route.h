#pragma once
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <unordered_map>
#include <vector>
#include <type_traits>

// DF 53.16 track search, traced offline from RVA 0x269b00, 0xda9d30,
// 0xda9c70, 0x256ce0 and 0x10a850. No game pointers or native UI state.
// The backward search and unusual heap indexing/tie behavior are deliberate:
// substituting std::priority_queue changes native equal-cost routes.
namespace df3d::track {
struct Point { int32_t x=0,y=0,z=0; friend bool operator==(Point,Point)=default; };
struct PointHash { size_t operator()(Point p) const {
    size_t h=uint32_t(p.x); h=(h*0x9e3779b1u)^uint32_t(p.y); return (h*0x9e3779b1u)^uint32_t(p.z);
}};
struct Tile { Point point; uint8_t mask=0; };
inline int distance(Point a,Point b) { return std::abs(a.x-b.x)+std::abs(a.y-b.y)+std::abs(a.z-b.z); }
inline int heuristic(Point a,Point b) {
    const int x=std::abs(a.x-b.x),y=std::abs(a.y-b.y),z=std::abs(a.z-b.z);
    return 256*std::max({x,y,z})+106*std::min({x,y,z});
}
// Compact semantic inputs shared by authoritative DF data and resident tiles.
struct Terrain {
    bool eligible=false;
    bool ramp=false;
    bool rampTop=false;
    bool open=false; // native OpenSpace, Chasm or EeriePit
    bool support=false; // wall or fortification (any material)
    bool clearanceBlocked=false;
    bool horizontalBlocked=false;
};
template<class Lookup>
bool connected(Point from,Point to,Lookup lookup) {
    if(from.z==to.z) return true;
    if(to.z==from.z+1) {
        const auto above=lookup({from.x,from.y,from.z+1});
        return lookup(from).ramp && (above.rampTop || above.open) && !above.clearanceBlocked &&
            lookup({to.x,to.y,from.z}).support;
    }
    if(to.z==from.z-1) {
        const auto above=lookup({to.x,to.y,from.z});
        return lookup(to).ramp && above.rampTop && !above.clearanceBlocked &&
            lookup({from.x,from.y,to.z}).support;
    }
    return false;
}
namespace detail {
struct Node { Point point; int score; };
class NativeHeap {
    std::vector<Node> nodes_;
public:
    bool empty() const { return nodes_.empty(); }
    Node top() const { return nodes_.front(); }
    void push(Node n) {
        nodes_.push_back(n);
        for(size_t i=nodes_.size()-1;i && nodes_[i/2].score>nodes_[i].score;i/=2)
            std::swap(nodes_[i/2],nodes_[i]);
    }
    void erase(size_t i) {
        const Node last=nodes_.back(); nodes_.pop_back();
        if(i>=nodes_.size()) return;
        nodes_[i]=last;
        while(2*i<nodes_.size()) {
            const size_t left=2*i,right=left+1;
            size_t child;
            if(nodes_[left].score<nodes_[i].score)
                child=right<nodes_.size() && nodes_[right].score<nodes_[left].score?right:left;
            else if(right<nodes_.size()) child=right;
            else break;
            std::swap(nodes_[i],nodes_[child]); i=child;
        }
    }
    void erase(Point point) {
        for(size_t i=nodes_.size();i>0;--i) if(nodes_[i-1].point==point) { erase(i-1);return; }
    }
};
}
// eligible answers whether a tile can carry carved track. connected(from,to)
// answers the native directed movement edge, including ramp/support/clearance.
// Search budget is a guard against pathological user selections, never a
// partial route: exhaustion returns no placement.
template<class Eligible,class Connected>
requires std::is_invocable_r_v<bool, Connected, Point, Point>
std::vector<Tile> route(Point start,Point end,Eligible eligible,Connected connected,size_t budget=4096) {
    if(start==end || !eligible(start) || !eligible(end)) return {};
    struct Seen { int cost; Point parent; bool closed=false; };
    std::unordered_map<Point,Seen,PointHash> seen;
    detail::NativeHeap open;
    seen.emplace(end,Seen{0,end}); open.push({end,heuristic(end,start)});
    while(!open.empty() && budget--) {
        const Point current=open.top().point; open.erase(size_t(0));
        seen.at(current).closed=true;
        if(current==start) {
            std::vector<Tile> path;
            for(Point p=start;;p=seen.at(p).parent) { path.push_back({p}); if(p==end) break; }
            for(size_t i=1;i<path.size();++i) {
                auto &a=path[i-1],&b=path[i];
                if(b.point.x>a.point.x) { a.mask|=4;b.mask|=8; }
                if(b.point.x<a.point.x) { a.mask|=8;b.mask|=4; }
                if(b.point.y>a.point.y) { a.mask|=2;b.mask|=1; }
                if(b.point.y<a.point.y) { a.mask|=1;b.mask|=2; }
            }
            return path;
        }
        const int cost=seen.at(current).cost;
        // Native loops x, then y, then z and excludes horizontal diagonals
        // and purely vertical steps. This order participates in heap ties.
        for(int dx=-1;dx<=1;++dx) for(int dy=-1;dy<=1;++dy) {
            if((dx==0)==(dy==0)) continue;
            for(int dz=-1;dz<=1;++dz) {
                const Point next{current.x+dx,current.y+dy,current.z+dz};
                auto it=seen.find(next);
                if((it!=seen.end() && it->second.closed) || !eligible(next) || !connected(next,current)) continue;
                const int nextCost=cost+256;
                if(it!=seen.end()) {
                    if(it->second.cost<=nextCost) continue;
                    open.erase(next);
                }
                seen.insert_or_assign(next,Seen{nextCost,current});
                open.push({next,nextCost+heuristic(next,start)});
            }
        }
    }
    return {};
}
// Flat-only convenience for tests and non-terrain clients.
template<class Eligible>
std::vector<Tile> route(Point start,Point end,Eligible eligible,size_t budget=4096) {
    return route(start,end,eligible,[](Point a,Point b){return a.z==b.z;},budget);
}
} // namespace df3d::track
