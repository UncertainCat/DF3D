#include "item_payload_kernel.h"
#include "df3d_world.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <algorithm>
#include <cmath>
#include <limits>

namespace df3d_godot {
using namespace godot;
namespace {
void add(Dictionary& counters, const char* key, int64_t value) {
    counters[key] = int64_t(counters.get(key, 0)) + value;
}
AABB envelope(Vector3 extent, Vector2 size, Vector3 position) {
    const real_t radius = Vector3(extent.x * size.x, extent.y * real_t(0.045 / 0.12),
        extent.z * size.y).length() + size.y * real_t(0.5);
    const Vector3 margin(radius, radius, radius);
    auto result=AABB(position - margin, margin * 2);
    result.size.y += .9; // Any ramp support; terrain changes never rewrite items.
    return result;
}
}
void ItemPayloadKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("prepare", "group", "record", "source", "dependencies", "world", "sparse", "force", "counters"), &ItemPayloadKernel::prepare);
    ClassDB::bind_method(D_METHOD("write", "mesh", "group", "patch", "full", "counters"), &ItemPayloadKernel::write);
}
Dictionary ItemPayloadKernel::prepare(Object* group, const Dictionary& record,
    const Dictionary& source, const Array& dependencies, Object* world,
    bool sparse, bool force, Dictionary counters) {
    auto* native_world=Object::cast_to<Df3dWorld>(world);
    const PackedInt32Array indices = record["indices"], changes = record["changed_indices"];
    const PackedVector3Array positions = source["positions"];
    const PackedVector2Array sizes = source["sizes"];
    const PackedFloat32Array thicknesses = source["thicknesses"];
    const PackedFloat32Array stack_ordinals = source.get("stack_ordinals", PackedFloat32Array());
    const PackedColorArray source_colors = source["colors"];
    const PackedByteArray ground = source["ground"];
    Array transforms = group->get("transforms");
    PackedColorArray custom = group->get("custom"), colors = group->get("colors");
    const int old_count = transforms.size(), count = indices.size();
    const bool marker = group->get("marker"), oriented = !marker && int64_t(dependencies[0]) != 0;
    const Color region = record["region"];
    const AABB mesh_bounds = group->get("mesh_bounds");
    const Vector3 extent = mesh_bounds.position.abs().max(mesh_bounds.get_end().abs());
    transforms.resize(count); custom.resize(count); colors.resize(count);
    PackedInt32Array moved, recustom, recolor;
    bool bounds_changed = !sparse || count != old_count;
    bool clipping_changed = false;
    int64_t queries = 0, hits = 0;
    const int candidates = sparse ? changes.size() : count;
    for (int offset = 0; offset < candidates; ++offset) {
        const int ordinal = sparse ? changes[offset] : offset;
        const int index = indices[ordinal];
        const Vector3 position = positions[index];
        const Vector2 size = sizes[index];
        const double thickness = thicknesses[index];
        const Transform3D transform(Basis().scaled(marker ? Vector3(1, thickness / .3, 1)
            : Vector3(size.x, thickness / .12, size.y)),
            marker ? position + Vector3(0, thickness * real_t(.5), 0) : position);
        const Transform3D previous = ordinal < old_count ? Transform3D(transforms[ordinal]) : Transform3D();
        if (!bounds_changed)
            bounds_changed = previous.origin.x != position.x || previous.origin.z != position.z ||
                std::floor(previous.origin.y) != std::floor(position.y) ||
                previous.basis.get_column(0) != transform.basis.get_column(0) ||
                previous.basis.get_column(2) != transform.basis.get_column(2);
        if (force || ordinal >= old_count || previous != transform) {
            transforms[ordinal] = transform; moved.push_back(ordinal);
        }
        Color value = region;
        if (oriented) {
            const auto box = envelope(extent, size, position);
            const int floor_z = int(std::floor(position.y));
            double ceiling;
            if(native_world) {
                const auto before=native_world->spriteCeilingBlockSamples();
                ceiling=native_world->sprite_ceiling(box,floor_z);
                if(native_world->spriteCeilingBlockSamples()!=before)++queries;else ++hits;
            } else {
                // Test/source adapters own the same clipping-query contract.
                // No second global cache can conceal their source changes.
                ceiling = world->call("sprite_ceiling", box, floor_z); ++queries;
            }
            value = Color(ceiling, 0, 0, 0);
        }
        value.g = ground[index] ? 1 : 0;
        if (index < stack_ordinals.size()) value.b = stack_ordinals[index];
        if (oriented && (ordinal >= old_count || custom[ordinal].r != value.r)) clipping_changed = true;
        if (force || ordinal >= old_count || custom[ordinal] != value) {
            custom.set(ordinal, value); recustom.push_back(ordinal);
        }
        if (marker && (force || ordinal >= old_count || colors[ordinal] != source_colors[index])) {
            colors.set(ordinal, source_colors[index]); recolor.push_back(ordinal);
        }
    }
    if (bounds_changed || clipping_changed) {
        AABB bounds;
        AABB render_bounds;
        bool first = true;
        int clip_floor=std::numeric_limits<int>::max();
        for (int i = 0; i < count; ++i) {
            const int index = indices[i];
            clip_floor=std::min(clip_floor,int(std::floor(positions[index].y)));
            Vector3 anchor = positions[index]; anchor.y = std::floor(anchor.y) + real_t(.5);
            auto box = oriented ? envelope(extent, sizes[index], anchor)
                : Transform3D(transforms[i]).xform(mesh_bounds);
            if(oriented)box.position.y -= real_t(.5);
            box.size.y += 1.9;
            if(!oriented) { const real_t slope=.9*std::max(extent.x*sizes[index].x,extent.z*sizes[index].y);box.position.y-=slope;box.size.y+=2*slope; }
            bounds = first ? box : bounds.merge(box); first = false;
            // fragment() discards all billboard pixels at/above this ceiling.
            // Retain the unclipped box above for source dependency tracking.
            if (oriented) {
                const real_t top = std::min(box.get_end().y, real_t(custom[i].r));
                box.position.y = std::min(box.position.y, top);
                box.size.y = std::max(real_t(.001), top - box.position.y);
            }
            render_bounds = i == 0 ? box : render_bounds.merge(box);
        }
        group->set("bounds", bounds);
        group->set("render_bounds", render_bounds);
        group->set("clip_floor_z",count ? clip_floor : 0);
    }
    group->set("transforms", transforms); group->set("custom", custom); group->set("colors", colors);
    add(counters, "instances_considered", candidates);
    add(counters, "ceiling_evaluations", queries); add(counters, "ceiling_cache_hits", hits);
    Dictionary result;
    result["transforms"] = moved; result["custom"] = recustom; result["colors"] = recolor;
    return result;
}
void ItemPayloadKernel::write(const Ref<MultiMesh>& mesh, Object* group, Object* patch,
    bool full, Dictionary counters) {
    const Array transforms = group->get("transforms");
    const PackedColorArray custom = group->get("custom"), colors = group->get("colors");
    const bool marker = group->get("marker");
    const PackedInt32Array moved = patch->get("transforms"), changed = patch->get("custom"), recolored=patch->get("colors");
    const int transform_count = full ? transforms.size() : moved.size();
    const int data_count = full ? transforms.size() : changed.size();
    for (int i = 0; i < transform_count; ++i) {
        const int ordinal = full ? i : moved[i]; mesh->set_instance_transform(ordinal, transforms[ordinal]);
    }
    for (int i = 0; i < data_count; ++i) {
        const int ordinal = full ? i : changed[i];
        mesh->set_instance_custom_data(ordinal, custom[ordinal]);
    }
    const int color_count=marker?(full?transforms.size():recolored.size()):0;
    for(int i=0;i<color_count;++i) {
        const int ordinal=full?i:recolored[i];mesh->set_instance_color(ordinal,colors[ordinal]);
    }
    add(counters, "transforms_written", transform_count);
    add(counters, "custom_written", data_count);
    add(counters, "colors_written", color_count);
}
}
