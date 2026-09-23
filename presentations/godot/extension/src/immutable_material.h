#pragma once
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/dictionary.hpp>
namespace df3d_godot {
// Explicit immutable material inputs, also used as the batch compatibility key.
// Do not discover defaults through the RenderingServer during mesh preparation.
inline void configureImmutableMaterial(const godot::Ref<godot::ShaderMaterial>& material,const godot::Dictionary& parameters) {
    const auto keys=parameters.keys();
    for(int i=0;i<keys.size();++i)material->set_shader_parameter(keys[i],parameters[keys[i]]);
    material->set_meta("df3d_batch_parameters",parameters);
}
}
