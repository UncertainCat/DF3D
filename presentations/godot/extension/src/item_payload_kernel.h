#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>

namespace df3d_godot {
// Layer-4 arithmetic/submission kernel. GDScript retains logical ownership,
// revision acceptance, capacity policy and patch ordering.
class ItemPayloadKernel : public godot::RefCounted {
    GDCLASS(ItemPayloadKernel, godot::RefCounted)
protected:
    static void _bind_methods();
public:
    godot::Dictionary prepare(godot::Object* group, const godot::Dictionary& record,
        const godot::Dictionary& source, const godot::Array& dependencies,
        godot::Object* world, bool sparse, bool force, godot::Dictionary counters);
    void write(const godot::Ref<godot::MultiMesh>& mesh, godot::Object* group,
        godot::Object* patch, bool full, godot::Dictionary counters);
};
}
