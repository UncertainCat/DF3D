#include "mesh_batches.h"
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace df3d_godot {
using namespace godot;
// Friend access only starts/steps the real scheduler deterministically. This
// class is registered exclusively by the optional test extension.
class MeshBatchesTest : public RefCounted {
    GDCLASS(MeshBatchesTest,RefCounted)
protected:
    static void _bind_methods() {ClassDB::bind_method(D_METHOD("run","parent"),&MeshBatchesTest::run);}
public:
    PackedStringArray run(Node* parent) {
        PackedStringArray failures;
        auto check=[&](bool ok,const char* message){if(!ok)failures.append(message);};
        Ref<StandardMaterial3D> material;material.instantiate();
        auto make=[&](float x) {
            auto* node=memnew(MeshInstance3D);
            Ref<ArrayMesh> mesh;mesh.instantiate();
            Array a;a.resize(Mesh::ARRAY_MAX);
            PackedVector3Array v,n;PackedColorArray c;
            v.append(Vector3(x,0,0));v.append(Vector3(x+1,0,0));v.append(Vector3(x,1,0));
            for(int i=0;i<3;++i){n.append(Vector3(0,0,1));c.append(Color(1,1,1));}
            a[Mesh::ARRAY_VERTEX]=v;a[Mesh::ARRAY_NORMAL]=n;a[Mesh::ARRAY_COLOR]=c;
            mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,a);
            mesh->surface_set_material(0,material);
            Array arrays;arrays.append(a);mesh->set_meta("df3d_batch_arrays",arrays);
            node->set_mesh(mesh);parent->add_child(node);return node;
        };
        auto destroy=[](MeshInstance3D* node){node->get_parent()->remove_child(node);memdelete(node);};
        auto live=[](MeshInstance3D* node){return node->get_mesh()->get_surface_count();};
        const Vector3i cell;
        const MeshBatches::Key key{0,0,0};
        MeshBatches batches(0,"test",true);
        auto* a=make(0);auto* b=make(10);
        batches.put(1,a,cell);batches.put(2,b,cell);batches.flush(1000);
        check(live(a)==0 && live(b)==0,"publication retires source surfaces");
        check(a->is_visible() && b->is_visible() && a->get_layer_mask()==0,"source semantic visibility survives render hiding");
        auto old=batches.groups_.at(key).nodes.front()->get_instance_id();
        const auto restores=batches.restoreChecks_;
        batches.erase(1,false);destroy(a);
        check(batches.groups_.at(key).nodes.front()->get_instance_id()==old,"invalidate retains old published nodes");
        check(live(b)==0 && batches.restoreChecks_==restores,"invalidate never restores unchanged source GPU surfaces");
        auto* c=make(20);batches.put(3,c,cell);
        check(c->get_layer_mask()==0,"replacement source stays hidden behind published snapshot");
        batches.begin_work();check(!batches.step(),"gather retired source from retained CPU arrays");
        check(live(b)==0,"gather does not reupload retired source");
        batches.erase(3,false);destroy(c);
        check(batches.cancellations_==1,"edit cancels partial work");
        check(batches.groups_.at(key).nodes.front()->get_instance_id()==old,"cancel retains old snapshot");
        batches.flush(1000);
        auto mesh=batches.groups_.at(key).nodes.front()->get_mesh();
        const Array output=mesh->surface_get_arrays(0);
        const PackedVector3Array vertices=output[Mesh::ARRAY_VERTEX];
        check(vertices.size()==3 && vertices[0].x==10,"publish removes deleted geometry and preserves retired source data");
        check(live(b)==0 && batches.restoreChecks_==restores,"successful rebuild has no source restoration");
        batches.erase(2);
        check(live(b)==1 && b->get_layer_mask()==1,"source leaving batching restores rendering");
        check(batches.groups_.empty() && batches.pending()==0,"last source removal drops stale batch immediately");
        batches.put(2,b,cell);batches.flush(1000);
        a=make(30);batches.put(1,a,cell);batches.begin_work();batches.step();
        batches.set_enabled(false);
        check(live(a)==1 && live(b)==1 && a->get_layer_mask()==1 && b->get_layer_mask()==1,"disable during rebuild restores all sources");
        check(batches.groups_.at(key).nodes.empty() && batches.pending()==0,"disable removes old and partial batches");
        batches.set_enabled(true);batches.flush(1000);
        batches.erase(1,false);destroy(a);
        b->set_position(Vector3(1,0,0));batches.flush(1000);
        check(live(b)==1 && b->get_layer_mask()==1 && batches.groups_.at(key).nodes.empty(),"failed gather restores sources and removes obsolete snapshot");
        b->set_position(Vector3());batches.invalidate(key);batches.flush(1000);
        batches.clear();
        check(live(b)==1 && b->get_layer_mask()==1 && batches.pending()==0,"clear restores sources and cancels work");
        batches.put(2,b,cell);batches.flush(1000);
        batches.erase(2,false);
        Ref<ArrayMesh> empty;empty.instantiate();b->set_mesh(empty);b->set_layer_mask(1);
        batches.put(2,b,cell);batches.flush(1000);
        check(batches.groups_.at(key).nodes.empty() && batches.pending()==0,"empty geometry publishes no stale batch");
        batches.clear(false);destroy(b);
        b=make(40);batches.put(2,b,cell);batches.flush(1000);batches.clear(false);
        check(live(b)==0,"destructive clear never restores retired surfaces");destroy(b);
        b=make(50);batches.put(2,b,cell);batches.flush(1000);
        old=batches.groups_.at(key).nodes.front()->get_instance_id();
        a=make(60);batches.put(1,a,Vector3i(-1,0,0));
        c=make(70);batches.put(3,c,cell);
        batches.begin_work();
        bool complete=false;
        for(int i=0;i<20 && !complete;++i)complete=batches.step();
        check(complete && batches.groups_.at(key).nodes.front()->get_instance_id()!=old &&
            batches.groups_.at(MeshBatches::Key{-1,0,0}).nodes.empty(),
            "edited snapshot publishes ahead of lower-key initial construction");
        batches.clear();destroy(a);destroy(b);destroy(c);
        return failures;
    }
};
}
static void initialize_test(godot::ModuleInitializationLevel level) {
    if(level==godot::MODULE_INITIALIZATION_LEVEL_SCENE)godot::ClassDB::register_class<df3d_godot::MeshBatchesTest>();
}
extern "C" GDExtensionBool GDE_EXPORT mesh_batches_test_init(GDExtensionInterfaceGetProcAddress address,
    GDExtensionClassLibraryPtr library,GDExtensionInitialization* initialization) {
    godot::GDExtensionBinding::InitObject object(address,library,initialization);
    object.register_initializer(initialize_test);object.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return object.init();
}
