#pragma once
#include "df3d_mesher/opaque_occluders.h"
#include <godot_cpp/classes/array_occluder3d.hpp>
#include <godot_cpp/classes/occluder_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <array>
#include <map>
namespace df3d_godot {
// Immutable, block-local occlusion shapes are shared across positions, cut
// alternatives and sessions. Nodes own placement/visibility; the bounded cache
// owns reusable geometry, independent of map IDs, materials and source epochs.
class TerrainOccluders {
    using Key = std::vector<std::array<float,6>>;
    std::map<Key,godot::Ref<godot::ArrayOccluder3D>> shapes_;
public:
    void attach(godot::Node3D* parent,const std::vector<df3d::mesher::Face>& faces,wm::BlockPos block) {
        const auto rects=df3d::mesher::opaqueOccluders(faces);
        const float origin[]={float(block.bx*16),float(block.by*16),float(block.bz)};
        Key key;
        for(auto r:rects) {
            // Local coordinates also keep the conservative inset independent of
            // floating-point precision at the far side of a large map.
            constexpr float inset=.003f;
            if(r.u1-r.u0<=inset*2 || r.v1-r.v0<=inset*2)continue;
            key.push_back({float(r.axis),r.plane-origin[r.axis],
                r.u0-origin[(r.axis+1)%3]+inset,r.u1-origin[(r.axis+1)%3]-inset,
                r.v0-origin[(r.axis+2)%3]+inset,r.v1-origin[(r.axis+2)%3]-inset});
        }
        auto* node=godot::Object::cast_to<godot::OccluderInstance3D>(
            parent->get_node_or_null(godot::NodePath("OpaqueOccluder")));
        // Hold the old resource until set_occluder has queued the new binding.
        // Godot assigns its Ref before set_base; dropping the final reference
        // inside that setter otherwise queues RID free before instance detach.
        const godot::Ref<godot::Occluder3D> previous=node?node->get_occluder():godot::Ref<godot::Occluder3D>();
        if(key.empty()) {
            if(node) {
                node->hide();node->set_occluder(godot::Ref<godot::Occluder3D>());
            }
            parent->set_meta("df3d_occluder_rects",int64_t(0));
            return;
        }
        godot::PackedFloat32Array packedKey;
        packedKey.resize(key.size()*6);
        for(size_t i=0;i<key.size();++i)for(int j=0;j<6;++j)packedKey.set(i*6+j,key[i][j]);
        // An instance can outlive its cache entry. Compare exact geometry before
        // cache lookup so eviction never forces an unchanged occluder to rebind.
        if(node && node->get_occluder().is_valid()) {
            const godot::PackedFloat32Array prior=node->get_occluder()->get_meta("df3d_occlusion_key",godot::PackedFloat32Array());
            if(prior==packedKey)return;
        }
        auto found=shapes_.find(key);
        if(found==shapes_.end()) {
            godot::PackedVector3Array vertices;
            godot::PackedInt32Array indices;
            for(const auto& r:key) {
                const int axis=int(r[0]),base=vertices.size();
                for(int i=0;i<4;++i) {
                    float p[3];p[axis]=r[1];
                    p[(axis+1)%3]=(i==1 || i==2)?r[3]:r[2];
                    p[(axis+2)%3]=(i>=2)?r[5]:r[4];
                    vertices.push_back(godot::Vector3(p[0],p[2],p[1]));
                }
                for(int i:{0,2,1,0,3,2})indices.push_back(base+i);
            }
            godot::Ref<godot::ArrayOccluder3D> data;data.instantiate();
            data->set_arrays(vertices,indices);
            data->set_meta("df3d_occlusion_key",packedKey);
            // Eviction drops only this owner's reference; existing instances
            // keep their immutable shape alive until their own retirement.
            if(shapes_.size()>=4096)shapes_.erase(shapes_.begin());
            found=shapes_.emplace(key,data).first;
        }
        if(!node) {
            node=memnew(godot::OccluderInstance3D);
            node->set_name("OpaqueOccluder");
        }
        if(node->get_occluder()!=found->second)node->set_occluder(found->second);
        node->set_position(godot::Vector3(origin[0],origin[2],origin[1]));
        if(!node->get_parent())parent->add_child(node);
        node->show();
        parent->set_meta("df3d_occluder_rects",int64_t(key.size()));
    }
};
}
