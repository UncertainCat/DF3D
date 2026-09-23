#pragma once
// Conservative rectangle simplification of ALREADY opaque, axis-aligned faces.
// Never infers solidity from tile types or fills a hole between source faces.
#include "df3d_mesher/block_mesher.h"
#include <algorithm>
#include <map>
#include <tuple>
namespace df3d::mesher {
struct OcclusionRect {
    int axis = 0;
    float plane = 0, u0 = 0, u1 = 0, v0 = 0, v1 = 0;
};
inline std::vector<OcclusionRect> opaqueOccluders(const std::vector<Face>& faces) {
    std::map<std::pair<int,float>,std::vector<OcclusionRect>> planes;
    for (const auto& face : faces) {
        const auto coord=[](const Vec3& p,int a){return a==0?p.x:a==1?p.y:p.z;};
        for (int a=0;a<3;++a) {
            const int u=(a+1)%3,v=(a+2)%3;
            const float plane=coord(face.v[0],a);
            bool flat=true;
            OcclusionRect r{a,plane,coord(face.v[0],u),coord(face.v[0],u),coord(face.v[0],v),coord(face.v[0],v)};
            for (const auto& p:face.v) {
                flat &= coord(p,a)==plane;
                r.u0=std::min(r.u0,coord(p,u));r.u1=std::max(r.u1,coord(p,u));
                r.v0=std::min(r.v0,coord(p,v));r.v1=std::max(r.v1,coord(p,v));
            }
            if (!flat || r.u1<=r.u0 || r.v1<=r.v0) continue;
            unsigned corners=0;
            for (const auto& p:face.v) {
                const float pu=coord(p,u),pv=coord(p,v);
                if ((pu!=r.u0 && pu!=r.u1) || (pv!=r.v0 && pv!=r.v1)) continue;
                corners |= 1u << ((pu==r.u1?1:0)+(pv==r.v1?2:0));
            }
            if (corners==15) planes[{a,plane}].push_back(r);
            break;
        }
    }
    std::vector<OcclusionRect> out;
    for (auto& [key,rects]:planes) {
        std::sort(rects.begin(),rects.end(),[](const auto& a,const auto& b){return std::tie(a.v0,a.v1,a.u0,a.u1)<std::tie(b.v0,b.v1,b.u0,b.u1);});
        std::vector<OcclusionRect> rows;
        for (const auto& r:rects) {
            if (!rows.empty() && rows.back().v0==r.v0 && rows.back().v1==r.v1 && r.u0<=rows.back().u1)
                rows.back().u1=std::max(rows.back().u1,r.u1);
            else rows.push_back(r);
        }
        std::sort(rows.begin(),rows.end(),[](const auto& a,const auto& b){return std::tie(a.u0,a.u1,a.v0,a.v1)<std::tie(b.u0,b.u1,b.v0,b.v1);});
        std::vector<OcclusionRect> merged;
        for (const auto& r:rows) {
            if (!merged.empty() && merged.back().u0==r.u0 && merged.back().u1==r.u1 && r.v0<=merged.back().v1)
                merged.back().v1=std::max(merged.back().v1,r.v1);
            else merged.push_back(r);
        }
        out.insert(out.end(),merged.begin(),merged.end());
    }
    return out;
}
}
