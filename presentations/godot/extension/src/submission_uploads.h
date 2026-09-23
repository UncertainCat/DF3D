#pragma once
#include "profiling.h"
#include "submission_metrics.h"
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace df3d_godot::submission {
// All instrumented upload sites and stats reads run on the presentation thread.
inline Counters& counters() {
    static Counters value(df3d::profiling::global().mode() == df3d::profiling::Mode::Deep);
    return value;
}
inline godot::Ref<godot::ArrayMesh> createMesh(MeshSite site) {
    godot::Ref<godot::ArrayMesh> mesh;
    mesh.instantiate();
    counters().resource(site);
    return mesh;
}
inline void meshSurface(const godot::Ref<godot::ArrayMesh>& mesh, const godot::Array& arrays, MeshSite site, uint64_t flags=0) {
    auto& stats = counters();
    if (stats.enabled()) {
        uint64_t bytes = 0, vertices = 0, indices = 0, unknown = 0;
        for (int i = 0; i < arrays.size(); ++i) {
            const godot::Variant value = arrays[i];
            switch (value.get_type()) {
                case godot::Variant::NIL: break;
                case godot::Variant::PACKED_VECTOR3_ARRAY: {
                    const godot::PackedVector3Array values = value;
                    bytes += uint64_t(values.size()) * sizeof(godot::Vector3);
                    if (i == godot::Mesh::ARRAY_VERTEX) vertices = values.size();
                    break;
                }
                case godot::Variant::PACKED_VECTOR2_ARRAY: {
                    const godot::PackedVector2Array values = value;
                    bytes += uint64_t(values.size()) * sizeof(godot::Vector2);
                    if (i == godot::Mesh::ARRAY_VERTEX) vertices = values.size();
                    break;
                }
                case godot::Variant::PACKED_COLOR_ARRAY:
                    bytes += uint64_t(godot::PackedColorArray(value).size()) * sizeof(godot::Color); break;
                case godot::Variant::PACKED_FLOAT32_ARRAY:
                    bytes += uint64_t(godot::PackedFloat32Array(value).size()) * sizeof(float); break;
                case godot::Variant::PACKED_FLOAT64_ARRAY:
                    bytes += uint64_t(godot::PackedFloat64Array(value).size()) * sizeof(double); break;
                case godot::Variant::PACKED_INT32_ARRAY: {
                    const godot::PackedInt32Array values = value;
                    bytes += uint64_t(values.size()) * sizeof(int32_t);
                    if (i == godot::Mesh::ARRAY_INDEX) indices = values.size();
                    break;
                }
                case godot::Variant::PACKED_INT64_ARRAY:
                    bytes += uint64_t(godot::PackedInt64Array(value).size()) * sizeof(int64_t); break;
                case godot::Variant::PACKED_BYTE_ARRAY:
                    bytes += uint64_t(godot::PackedByteArray(value).size()); break;
                default: ++unknown; break;
            }
        }
        stats.mesh(site, vertices, indices, bytes, unknown);
    }
    mesh->add_surface_from_arrays(godot::Mesh::PRIMITIVE_TRIANGLES, arrays, godot::Array(), godot::Dictionary(), flags);
}
inline godot::Ref<godot::ImageTexture> texture(const godot::Ref<godot::Image>& image, TextureSite site, bool immutable_art=false) {
    auto& stats = counters();
    if (stats.enabled()) stats.texture(site, image.is_valid() ? uint64_t(image->get_data_size()) : 0);
    auto texture=godot::ImageTexture::create_from_image(image);
    // Immutable artwork pools can reuse the source without a renderer readback.
    if(immutable_art)texture->set_meta("df3d_immutable_image",image);
    return texture;
}
}
