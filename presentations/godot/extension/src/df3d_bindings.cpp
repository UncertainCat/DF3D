#include "df3d_world.h"
#include <godot_cpp/core/class_db.hpp>
namespace df3d_godot {
using namespace godot;
void Df3dWorld::_bind_methods() {
    using godot::ClassDB;
    ClassDB::bind_method(D_METHOD("spatter_revision"), &Df3dWorld::spatter_revision);
    ClassDB::bind_method(D_METHOD("tile_spatters", "tile"), &Df3dWorld::tile_spatters);
    ClassDB::bind_method(D_METHOD("set_mesh_batching_enabled", "enabled"), &Df3dWorld::set_mesh_batching_enabled);
    ClassDB::bind_method(D_METHOD("mesh_batch_stats"), &Df3dWorld::mesh_batch_stats);
    ClassDB::bind_method(D_METHOD("load_assets", "override_path"), &Df3dWorld::load_assets);
    ClassDB::bind_method(D_METHOD("assets_loaded"), &Df3dWorld::assets_loaded);
    ClassDB::bind_method(D_METHOD("assets_error"), &Df3dWorld::assets_error);
    ClassDB::bind_method(D_METHOD("assets_root"), &Df3dWorld::assets_root);
    ClassDB::bind_method(D_METHOD("assets_summary"), &Df3dWorld::assets_summary);
    ClassDB::bind_method(D_METHOD("unresolved_face_count"), &Df3dWorld::unresolved_face_count);
    ClassDB::bind_method(D_METHOD("textured_face_count"), &Df3dWorld::textured_face_count);
    ClassDB::bind_method(D_METHOD("hidden_face_count"), &Df3dWorld::hidden_face_count);
    ClassDB::bind_method(D_METHOD("rock_backing_color"), &Df3dWorld::rock_backing_color);
    ClassDB::bind_method(D_METHOD("tile_summary", "tile"), &Df3dWorld::tile_summary);
    ClassDB::bind_method(D_METHOD("tile_hover_info", "tile"), &Df3dWorld::tile_hover_info);
    ClassDB::bind_method(D_METHOD("terrain_revision"), &Df3dWorld::terrain_revision);
    ClassDB::bind_method(D_METHOD("items_at_tile", "tile"), &Df3dWorld::items_at_tile);
    ClassDB::bind_method(D_METHOD("buildings_at_tile", "tile"), &Df3dWorld::buildings_at_tile);
    ClassDB::bind_method(D_METHOD("unit_tile", "id"), &Df3dWorld::unit_tile);
    ClassDB::bind_method(D_METHOD("inspect_tile", "tile"), &Df3dWorld::inspect_tile);
    ClassDB::bind_method(D_METHOD("inspect_entity", "kind", "id"), &Df3dWorld::inspect_entity);
    ClassDB::bind_method(D_METHOD("pick_building", "origin", "direction", "z"), &Df3dWorld::pick_building);
    ClassDB::bind_method(D_METHOD("ui_texture", "name", "variant"), &Df3dWorld::ui_texture, DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("ui_font_path"), &Df3dWorld::ui_font_path);
    ClassDB::bind_method(D_METHOD("item_tile", "id"), &Df3dWorld::item_tile);
    ClassDB::bind_method(D_METHOD("selection_height", "tile"), &Df3dWorld::selection_height);
    ClassDB::bind_method(D_METHOD("pick_tile", "origin", "direction", "z"), &Df3dWorld::pick_tile);
    ClassDB::bind_method(D_METHOD("designation_tiles", "z"), &Df3dWorld::designation_tiles);
    ClassDB::bind_method(D_METHOD("sprite_resource_revision"), &Df3dWorld::sprite_resource_revision);
    ClassDB::bind_method(D_METHOD("sprite_slot_valid", "slot"), &Df3dWorld::sprite_slot_valid);
    ClassDB::bind_method(D_METHOD("sprite_resource_stats"), &Df3dWorld::sprite_resource_stats);
    ClassDB::bind_method(D_METHOD("sprite_texture", "slot"), &Df3dWorld::sprite_texture);
    ClassDB::bind_method(D_METHOD("composited_unit_count"), &Df3dWorld::composited_unit_count);
    ClassDB::bind_method(D_METHOD("simple_sprite_unit_count"),
                         &Df3dWorld::simple_sprite_unit_count);
    ClassDB::bind_method(D_METHOD("cube_unit_count"), &Df3dWorld::cube_unit_count);
    ClassDB::bind_method(D_METHOD("composite_pending_count"),
                         &Df3dWorld::composite_pending_count);
    ClassDB::bind_method(D_METHOD("composite_cache_size"), &Df3dWorld::composite_cache_size);
    ClassDB::bind_method(D_METHOD("composite_failed_count"), &Df3dWorld::composite_failed_count);
    ClassDB::bind_method(D_METHOD("composite_build_count"), &Df3dWorld::composite_build_count);
    ClassDB::bind_method(D_METHOD("composite_last_ms"), &Df3dWorld::composite_last_ms);
    ClassDB::bind_method(D_METHOD("composite_total_ms"), &Df3dWorld::composite_total_ms);
    ClassDB::bind_method(D_METHOD("set_composite_budget_ms", "ms"),
                         &Df3dWorld::set_composite_budget_ms);
    ClassDB::bind_method(D_METHOD("appearance_event_count"), &Df3dWorld::appearance_event_count);
    ClassDB::bind_method(D_METHOD("dump_unit_composites", "dir", "ids", "max_units"),
                         &Df3dWorld::dump_unit_composites);

    ClassDB::bind_method(D_METHOD("attach"), &Df3dWorld::attach);
    ClassDB::bind_method(D_METHOD("detach_live"), &Df3dWorld::detach_live);
    ClassDB::bind_method(D_METHOD("live_synchronized"), &Df3dWorld::live_synchronized);
    ClassDB::bind_method(D_METHOD("poll_session"), &Df3dWorld::poll_session);
    ClassDB::bind_method(D_METHOD("poll_management"), &Df3dWorld::poll_management);
    ClassDB::bind_method(D_METHOD("update_resident_info"), &Df3dWorld::update_resident_info);
    ClassDB::bind_method(D_METHOD("demand_resident_info", "demand"), &Df3dWorld::demand_resident_info);
    ClassDB::bind_method(D_METHOD("refresh_resident_info"), &Df3dWorld::refresh_resident_info);
    ClassDB::bind_method(D_METHOD("resident_info_state"), &Df3dWorld::resident_info_state);
    ClassDB::bind_method(D_METHOD("demand_creature_info", "id"), &Df3dWorld::demand_creature_info);
    ClassDB::bind_method(D_METHOD("creature_info_state", "id"), &Df3dWorld::creature_info_state);
    ClassDB::bind_method(D_METHOD("creature_portrait", "id"), &Df3dWorld::creature_portrait);
    ClassDB::bind_method(D_METHOD("resident_icon", "id"), &Df3dWorld::resident_icon);
    ClassDB::bind_method(D_METHOD("selection_icon", "kind", "id"), &Df3dWorld::selection_icon);
    ClassDB::bind_method(D_METHOD("management_request", "domain", "request"), &Df3dWorld::management_request);
    ClassDB::bind_method(D_METHOD("report_request", "data"), &Df3dWorld::report_request);
    ClassDB::bind_method(D_METHOD("work_order_request", "data"), &Df3dWorld::work_order_request);
    ClassDB::bind_method(D_METHOD("area_request", "data"), &Df3dWorld::area_request);
    ClassDB::bind_method(D_METHOD("construction_request", "request"), &Df3dWorld::construction_request);
    ClassDB::bind_method(D_METHOD("reconnect_management"), &Df3dWorld::reconnect_management);
    ClassDB::bind_method(D_METHOD("load_fortress", "id"), &Df3dWorld::load_fortress);
    ClassDB::bind_method(D_METHOD("save_fortress", "return_to_menu", "checkpoint_name"), &Df3dWorld::save_fortress, DEFVAL(""));
    ClassDB::bind_method(D_METHOD("load_fixture", "path"), &Df3dWorld::load_fixture);
    ClassDB::bind_method(D_METHOD("set_replay_speed", "speed"), &Df3dWorld::set_replay_speed);
    ClassDB::bind_method(D_METHOD("set_replay_elapsed", "seconds"), &Df3dWorld::set_replay_elapsed);
    ClassDB::bind_method(D_METHOD("set_fixed_render_tick", "tick"),
                         &Df3dWorld::set_fixed_render_tick);
    ClassDB::bind_method(D_METHOD("is_attached"), &Df3dWorld::is_attached);
    ClassDB::bind_method(D_METHOD("is_live"), &Df3dWorld::is_live);
    ClassDB::bind_method(D_METHOD("source_name"), &Df3dWorld::source_name);
    ClassDB::bind_method(D_METHOD("last_error"), &Df3dWorld::last_error);
    ClassDB::bind_method(D_METHOD("session_generation"), &Df3dWorld::session_generation);
    ClassDB::bind_method(D_METHOD("unit_render_revision"), &Df3dWorld::unit_render_revision);
    ClassDB::bind_method(D_METHOD("item_render_revision"), &Df3dWorld::item_render_revision);
    ClassDB::bind_method(D_METHOD("item_render_groups"), &Df3dWorld::item_render_groups);
    ClassDB::bind_method(D_METHOD("item_render_group_delta", "since"), &Df3dWorld::item_render_group_delta);
    ClassDB::bind_method(D_METHOD("sprite_ceiling", "bounds", "floor_z"), &Df3dWorld::sprite_ceiling);
    ClassDB::bind_method(D_METHOD("sprite_ceiling_source_revision", "bounds", "floor_z"), &Df3dWorld::sprite_ceiling_source_revision);
    ClassDB::bind_method(D_METHOD("sprite_ceiling_cache_stats"), &Df3dWorld::sprite_ceiling_cache_stats);
    ClassDB::bind_method(D_METHOD("door_orientation_revision"), &Df3dWorld::door_orientation_revision);
    ClassDB::bind_method(D_METHOD("door_orientation", "tile"), &Df3dWorld::door_orientation);
    ClassDB::bind_method(D_METHOD("configure_sprite_batches", "enabled", "cell_xy", "cell_z"), &Df3dWorld::configure_sprite_batches);
    ClassDB::bind_method(D_METHOD("presentation_perf_stats"), &Df3dWorld::presentation_perf_stats);
    ClassDB::bind_method(D_METHOD("profiling_trace"), &Df3dWorld::profiling_trace);
    ClassDB::bind_method(D_METHOD("engine_submission_stats"), &Df3dWorld::engine_submission_stats);
    ClassDB::bind_method(D_METHOD("engine_submission_details"), &Df3dWorld::engine_submission_details);
    ClassDB::bind_method(D_METHOD("profiling_render_sync"), &Df3dWorld::profiling_render_sync);
    ClassDB::bind_method(D_METHOD("profiling_cpu_clock"), &Df3dWorld::profiling_cpu_clock);
    ClassDB::bind_method(D_METHOD("profiling_render_boundary", "enqueue"), &Df3dWorld::profiling_render_boundary);
    ClassDB::bind_method(D_METHOD("profiling_clock_usec"), &Df3dWorld::profiling_clock_usec);
    ClassDB::bind_method(D_METHOD("wall_top_cache_stats"), &Df3dWorld::wall_top_cache_stats);
    ClassDB::bind_method(D_METHOD("buffered_state"), &Df3dWorld::buffered_state);
    ClassDB::bind_method(D_METHOD("layout_matches_reference"), &Df3dWorld::layout_matches_reference);
    ClassDB::bind_method(D_METHOD("set_presentation_region", "region"), &Df3dWorld::set_presentation_region);
    ClassDB::bind_method(D_METHOD("presentation_art_margin"), &Df3dWorld::presentation_art_margin);
    ClassDB::bind_method(D_METHOD("clear_layout_cache"), &Df3dWorld::clear_layout_cache);
    ClassDB::bind_method(D_METHOD("poll"), &Df3dWorld::poll);
    ClassDB::bind_method(D_METHOD("sprite_cutout_mesh", "slot", "region"), &Df3dWorld::sprite_cutout_mesh);
    ClassDB::bind_method(D_METHOD("unit_positions"), &Df3dWorld::unit_positions);
    ClassDB::bind_method(D_METHOD("unit_jobs"), &Df3dWorld::unit_jobs);
    ClassDB::bind_method(D_METHOD("unit_status_flags"), &Df3dWorld::unit_status_flags);
    ClassDB::bind_method(D_METHOD("unit_motion_from"), &Df3dWorld::unit_motion_from);
    ClassDB::bind_method(D_METHOD("unit_motion_to"), &Df3dWorld::unit_motion_to);
    ClassDB::bind_method(D_METHOD("unit_motion_epochs"), &Df3dWorld::unit_motion_epochs);
    ClassDB::bind_method(D_METHOD("unit_render_delta", "since"), &Df3dWorld::unit_render_delta);
    ClassDB::bind_method(D_METHOD("stack_atlas_revision"), &Df3dWorld::stack_atlas_revision);
    ClassDB::bind_method(D_METHOD("ground_support", "position"), &Df3dWorld::ground_support);
    ClassDB::bind_method(D_METHOD("unit_ground_support", "index"), &Df3dWorld::unit_ground_support);
    ClassDB::bind_method(D_METHOD("item_physical_layout"), &Df3dWorld::item_physical_layout);
    ClassDB::bind_method(D_METHOD("item_stack_ordinals"), &Df3dWorld::item_stack_ordinals);
    ClassDB::bind_method(D_METHOD("unit_stack_ordinals"), &Df3dWorld::unit_stack_ordinals);
    ClassDB::bind_method(D_METHOD("unit_stack_tiles"), &Df3dWorld::unit_stack_tiles);
    ClassDB::bind_method(D_METHOD("configure_stack_material", "material"), &Df3dWorld::configure_stack_material);
    ClassDB::bind_method(D_METHOD("unit_motion_segments"), &Df3dWorld::unit_motion_segments);
    ClassDB::bind_method(D_METHOD("corpse_item_changes"), &Df3dWorld::corpse_item_changes);
    ClassDB::bind_method(D_METHOD("projectile_combat_events", "after_id"), &Df3dWorld::projectile_combat_events);
    ClassDB::bind_method(D_METHOD("projectile_combat_stats"), &Df3dWorld::projectile_combat_stats);
    ClassDB::bind_method(D_METHOD("resolved_attack_events", "after_id"), &Df3dWorld::resolved_attack_events);
    ClassDB::bind_method(D_METHOD("resolved_attack_stats"), &Df3dWorld::resolved_attack_stats);
    ClassDB::bind_method(D_METHOD("item_contact_events", "after_id"), &Df3dWorld::item_contact_events);
    ClassDB::bind_method(D_METHOD("item_contact_stats"), &Df3dWorld::item_contact_stats);
    ClassDB::bind_method(D_METHOD("set_hidden_corpses", "ids"), &Df3dWorld::set_hidden_corpses);
    ClassDB::bind_method(D_METHOD("unit_combat_events", "after_id"), &Df3dWorld::unit_combat_events, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("effect_events", "after_id"), &Df3dWorld::effect_events, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("effect_event_stats"), &Df3dWorld::effect_event_stats);
    ClassDB::bind_method(D_METHOD("projectile_ids"), &Df3dWorld::projectile_ids);
    ClassDB::bind_method(D_METHOD("projectile_positions"), &Df3dWorld::projectile_positions);
    ClassDB::bind_method(D_METHOD("projectile_directions"), &Df3dWorld::projectile_directions);
    ClassDB::bind_method(D_METHOD("projectile_release_events", "after_id"), &Df3dWorld::projectile_release_events, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("unit_attack_ids"), &Df3dWorld::unit_attack_ids);
    ClassDB::bind_method(D_METHOD("unit_attack_targets"), &Df3dWorld::unit_attack_targets);
    ClassDB::bind_method(D_METHOD("unit_cutout_positions"), &Df3dWorld::unit_cutout_positions);
    ClassDB::bind_method(D_METHOD("unit_thicknesses"), &Df3dWorld::unit_thicknesses);
    ClassDB::bind_method(D_METHOD("unit_colors"), &Df3dWorld::unit_colors);
    ClassDB::bind_method(D_METHOD("unit_ids"), &Df3dWorld::unit_ids);
    ClassDB::bind_method(D_METHOD("unit_count"), &Df3dWorld::unit_count);
    ClassDB::bind_method(D_METHOD("unit_species", "unit_id"), &Df3dWorld::unit_species);
    ClassDB::bind_method(D_METHOD("unit_sprite_slots"), &Df3dWorld::unit_sprite_slots);
    ClassDB::bind_method(D_METHOD("unit_sprite_regions"), &Df3dWorld::unit_sprite_regions);
    ClassDB::bind_method(D_METHOD("unit_sprite_sizes"), &Df3dWorld::unit_sprite_sizes);
    ClassDB::bind_method(D_METHOD("unit_scale_params"), &Df3dWorld::unit_scale_params);
    ClassDB::bind_method(D_METHOD("unit_sprite_kinds"), &Df3dWorld::unit_sprite_kinds);
    ClassDB::bind_method(D_METHOD("map_size"), &Df3dWorld::map_size);
    ClassDB::bind_method(D_METHOD("minimap_data", "z", "resolution"), &Df3dWorld::minimap_data, 256);
    ClassDB::bind_method(D_METHOD("auxiliary_cache_stats"), &Df3dWorld::auxiliary_cache_stats);
    ClassDB::bind_method(D_METHOD("elevation_overview", "x", "y"), &Df3dWorld::elevation_overview);
    ClassDB::bind_method(D_METHOD("bridge_tick"), &Df3dWorld::bridge_tick);
    ClassDB::bind_method(D_METHOD("render_tick"), &Df3dWorld::render_tick);
    ClassDB::bind_method(D_METHOD("send_set_pause", "paused"), &Df3dWorld::send_set_pause);
    ClassDB::bind_method(D_METHOD("designate_dig", "rect", "z", "kind", "priority", "marker", "mining_mode", "max_z"),
                         &Df3dWorld::designate_dig, DEFVAL(4), DEFVAL(false), DEFVAL(0), DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("designate_stairs", "rect", "z1", "z2", "priority", "marker"), &Df3dWorld::designate_stairs, DEFVAL(4), DEFVAL(false));
    ClassDB::bind_method(D_METHOD("preview_track", "rect", "z", "from_east", "from_south", "end_z"), &Df3dWorld::preview_track, DEFVAL(false), DEFVAL(false), DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("designate_track", "rect", "z", "from_east", "from_south", "priority", "marker", "end_z"), &Df3dWorld::designate_track, DEFVAL(false), DEFVAL(false), DEFVAL(4), DEFVAL(false), DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("designate_smooth", "rect", "z", "kind", "priority", "marker", "max_z"), &Df3dWorld::designate_smooth, DEFVAL(4), DEFVAL(false), DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("designate_chop", "rect", "z", "enable", "priority", "marker", "max_z"), &Df3dWorld::designate_chop, DEFVAL(4), DEFVAL(false), DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("designate_gather", "rect", "z", "enable", "priority", "marker", "max_z"), &Df3dWorld::designate_gather, DEFVAL(4), DEFVAL(false), DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("set_item_flags", "item", "forbidden", "dump", "melt"),
                         &Df3dWorld::set_item_flags);
    ClassDB::bind_method(D_METHOD("set_building_flags", "building", "forbidden"),
                         &Df3dWorld::set_building_flags);
    ClassDB::bind_method(D_METHOD("drain_command_results"), &Df3dWorld::drain_command_results);
    // Command vocabulary (values mirror wm:: / the schema, append-only).
    const StringName cls = get_class_static();
    ClassDB::bind_integer_constant(cls, "", "DIG_DIG", static_cast<int64_t>(wm::DigKind::Dig));
    ClassDB::bind_integer_constant(cls, "", "DIG_CHANNEL", static_cast<int64_t>(wm::DigKind::Channel));
    ClassDB::bind_integer_constant(cls, "", "DIG_RAMP_UP", static_cast<int64_t>(wm::DigKind::RampUp));
    ClassDB::bind_integer_constant(cls, "", "DIG_STAIRS_UP", static_cast<int64_t>(wm::DigKind::StairsUp));
    ClassDB::bind_integer_constant(cls, "", "DIG_STAIRS_DOWN", static_cast<int64_t>(wm::DigKind::StairsDown));
    ClassDB::bind_integer_constant(cls, "", "DIG_STAIRS_UP_DOWN", static_cast<int64_t>(wm::DigKind::StairsUpDown));
    ClassDB::bind_integer_constant(cls, "", "DIG_REMOVE", static_cast<int64_t>(wm::DigKind::Remove));
    ClassDB::bind_integer_constant(cls, "", "DIG_REMOVE_STAIRS_RAMPS", 7);
    ClassDB::bind_integer_constant(cls, "", "DIG_ACTIVATE", 8);
    ClassDB::bind_integer_constant(cls, "", "DIG_MARK", 9);
    ClassDB::bind_integer_constant(cls, "", "SMOOTH_FORTIFY", 3);

    ClassDB::bind_integer_constant(cls, "", "SMOOTH_SMOOTH", static_cast<int64_t>(wm::SmoothKind::Smooth));
    ClassDB::bind_integer_constant(cls, "", "SMOOTH_ENGRAVE", static_cast<int64_t>(wm::SmoothKind::Engrave));
    ClassDB::bind_integer_constant(cls, "", "SMOOTH_REMOVE", static_cast<int64_t>(wm::SmoothKind::Remove));
    ClassDB::bind_integer_constant(cls, "", "FLAG_UNCHANGED", static_cast<int64_t>(wm::OptionalBool::Unchanged));
    ClassDB::bind_integer_constant(cls, "", "FLAG_SET", static_cast<int64_t>(wm::OptionalBool::Set));
    ClassDB::bind_integer_constant(cls, "", "FLAG_CLEAR", static_cast<int64_t>(wm::OptionalBool::Clear));

    ClassDB::bind_method(D_METHOD("terrain_loaded"), &Df3dWorld::terrain_loaded);
    ClassDB::bind_method(D_METHOD("known_block_count"), &Df3dWorld::known_block_count);
    ClassDB::bind_method(D_METHOD("map_block_count"), &Df3dWorld::map_block_count);
    ClassDB::bind_method(D_METHOD("built_block_count"), &Df3dWorld::built_block_count);
    ClassDB::bind_method(D_METHOD("pending_block_count"), &Df3dWorld::pending_block_count);
    ClassDB::bind_method(D_METHOD("face_count"), &Df3dWorld::face_count);
    ClassDB::bind_method(D_METHOD("last_build_ms"), &Df3dWorld::last_build_ms);
    ClassDB::bind_method(D_METHOD("total_build_ms"), &Df3dWorld::total_build_ms);
    ClassDB::bind_method(D_METHOD("set_top_z", "z"), &Df3dWorld::set_top_z);
    ClassDB::bind_method(D_METHOD("get_top_z"), &Df3dWorld::get_top_z);
    ClassDB::bind_method(D_METHOD("set_window_depth", "levels"), &Df3dWorld::set_window_depth);
    ClassDB::bind_method(D_METHOD("get_window_depth"), &Df3dWorld::get_window_depth);
    ClassDB::bind_method(D_METHOD("set_reveal_hidden", "reveal"), &Df3dWorld::set_reveal_hidden);
    ClassDB::bind_method(D_METHOD("get_reveal_hidden"), &Df3dWorld::get_reveal_hidden);
    ClassDB::bind_method(D_METHOD("set_slice_units", "enabled"), &Df3dWorld::set_slice_units);
    ClassDB::bind_method(D_METHOD("set_terrain_root", "root"), &Df3dWorld::set_terrain_root);
    ClassDB::bind_method(D_METHOD("get_terrain_root"), &Df3dWorld::get_terrain_root);
    ClassDB::bind_static_method("Df3dWorld", D_METHOD("floor_height"), &Df3dWorld::floor_height);

    ClassDB::bind_method(D_METHOD("set_building_root", "root"), &Df3dWorld::set_building_root);
    ClassDB::bind_method(D_METHOD("get_building_root"), &Df3dWorld::get_building_root);
    ClassDB::bind_method(D_METHOD("set_zone_overlays_visible", "visible"), &Df3dWorld::set_zone_overlays_visible);
    ClassDB::bind_method(D_METHOD("building_drawn_count"), &Df3dWorld::building_drawn_count);
    ClassDB::bind_method(D_METHOD("building_unresolved_count"),
                         &Df3dWorld::building_unresolved_count);
    ClassDB::bind_method(D_METHOD("building_pending_count"), &Df3dWorld::building_pending_count);
    ClassDB::bind_method(D_METHOD("building_last_ms"), &Df3dWorld::building_last_ms);
    ClassDB::bind_method(D_METHOD("building_total_ms"), &Df3dWorld::building_total_ms);
    ClassDB::bind_method(D_METHOD("item_drawn_count"), &Df3dWorld::item_drawn_count);
    ClassDB::bind_method(D_METHOD("item_unresolved_count"), &Df3dWorld::item_unresolved_count);
    ClassDB::bind_method(D_METHOD("item_last_ms"), &Df3dWorld::item_last_ms);
    ClassDB::bind_method(D_METHOD("building_event_count"), &Df3dWorld::building_event_count);
    ClassDB::bind_method(D_METHOD("item_event_count"), &Df3dWorld::item_event_count);
    ClassDB::bind_method(D_METHOD("set_entity_budget_ms", "ms"), &Df3dWorld::set_entity_budget_ms);
    ClassDB::bind_method(D_METHOD("entity_unresolved_summary"),
                         &Df3dWorld::entity_unresolved_summary);
    ClassDB::bind_method(D_METHOD("item_positions"), &Df3dWorld::item_positions);
    ClassDB::bind_method(D_METHOD("item_thicknesses"), &Df3dWorld::item_thicknesses);
    ClassDB::bind_method(D_METHOD("item_ids"), &Df3dWorld::item_ids);
    ClassDB::bind_method(D_METHOD("item_sprite_slots"), &Df3dWorld::item_sprite_slots);
    ClassDB::bind_method(D_METHOD("item_sprite_regions"), &Df3dWorld::item_sprite_regions);
    ClassDB::bind_method(D_METHOD("item_sprite_sizes"), &Df3dWorld::item_sprite_sizes);
    ClassDB::bind_method(D_METHOD("item_colors"), &Df3dWorld::item_colors);
    ClassDB::bind_method(D_METHOD("item_ground_flags"), &Df3dWorld::item_ground_flags);

    ClassDB::bind_method(D_METHOD("unit_glyph_count"), &Df3dWorld::unit_glyph_count);
    ClassDB::bind_method(D_METHOD("item_composited_count"), &Df3dWorld::item_composited_count);
    ClassDB::bind_method(D_METHOD("item_piece_count"), &Df3dWorld::item_piece_count);
    ClassDB::bind_method(D_METHOD("item_web_count"), &Df3dWorld::item_web_count);
    ClassDB::bind_method(D_METHOD("item_glyph_count"), &Df3dWorld::item_glyph_count);
    ClassDB::bind_method(D_METHOD("item_composite_pending_count"),
                         &Df3dWorld::item_composite_pending_count);
    ClassDB::bind_method(D_METHOD("building_glyph_count"), &Df3dWorld::building_glyph_count);
    ClassDB::bind_method(D_METHOD("item_appearance_event_count"),
                         &Df3dWorld::item_appearance_event_count);
    ClassDB::bind_method(D_METHOD("glyph_summary"), &Df3dWorld::glyph_summary);
}

}
