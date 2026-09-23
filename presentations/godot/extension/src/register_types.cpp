// GDExtension entry point for the DF3D Godot presentation.
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

#include "df3d_world.h"
#include "item_payload_kernel.h"

using namespace godot;

namespace {

void initialize_df3d_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
    ClassDB::register_class<df3d_godot::Df3dWorld>();
    ClassDB::register_class<df3d_godot::ItemPayloadKernel>();
}

void uninitialize_df3d_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
}

}  // namespace

extern "C" {

GDExtensionBool GDE_EXPORT df3d_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
                                             const GDExtensionClassLibraryPtr p_library,
                                             GDExtensionInitialization* r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library,
                                                   r_initialization);
    init_obj.register_initializer(initialize_df3d_module);
    init_obj.register_terminator(uninitialize_df3d_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}

}  // extern "C"
