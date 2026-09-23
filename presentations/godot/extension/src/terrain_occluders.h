#pragma once
#include "df3d_mesher/opaque_occluders.h"
#include <godot_cpp/classes/array_occluder3d.hpp>
#include <godot_cpp/classes/occluder_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
namespace df3d_godot {
inline void attachTerrainOccluder(godot::Node3D* parent,const std::vector<df3d::mesher::Face>& faces) {
    const auto rects=df3d::mesher::opaqueOccluders(faces);
    godot::PackedVector3Array vertices;
    godot::PackedInt32Array indices;
    for (auto r:rects) {
        // Inset in-plane to fail open along silhouettes/rasterization boundaries.
        constexpr float inset=.003f;
        if (r.u1-r.u0<=inset*2 || r.v1-r.v0<=inset*2) continue;
        r.u0+=inset;r.u1-=inset;r.v0+=inset;r.v1-=inset;
        const int base=vertices.size();
        for (int i=0;i<4;++i) {
            float p[3];p[r.axis]=r.plane;
            p[(r.axis+1)%3]=(i==1 || i==2)?r.u1:r.u0;
            p[(r.axis+2)%3]=(i>=2)?r.v1:r.v0;
            vertices.push_back(godot::Vector3(p[0],p[2],p[1]));
        }
        for (int i:{0,2,1,0,3,2}) indices.push_back(base+i);
    }
    if (vertices.is_empty()) return;
    godot::Ref<godot::ArrayOccluder3D> data;data.instantiate();
    data->set_arrays(vertices,indices);
    auto* node=memnew(godot::OccluderInstance3D);
    node->set_name("OpaqueOccluder");node->set_occluder(data);
    parent->add_child(node);
    parent->set_meta("df3d_occluder_rects",int64_t(vertices.size()/4));
}
}
