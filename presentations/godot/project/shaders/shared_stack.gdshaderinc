// Local ordinals are stable within each category. Tile records alone resolve
// structures -> objects -> creatures and compress their shared vertical space.
uniform sampler2DArray shared_stack_texture : filter_nearest, repeat_disable;
uniform vec4 shared_stack_shape = vec4(32.0, 1.0, 1.0, 0.0);
uniform bool shared_stack_enabled = false;
vec4 shared_tile_record(vec3 tile) {
    if (!shared_stack_enabled) return vec4(0.0);
    ivec3 cell = ivec3(floor(tile)); // Godot x,y,z = DF x,z,y.
    int side = int(shared_stack_shape.x);
    int columns = int(shared_stack_shape.y);
    int rows = int(shared_stack_shape.z);
    int level = cell.y - int(shared_stack_shape.w);
    ivec3 dimensions = textureSize(shared_stack_texture, 0);
    int layer = level * columns * rows + (cell.z / side) * columns + cell.x / side;
    if (cell.x < 0 || cell.z < 0 || cell.x >= columns * side || cell.z >= rows * side || level < 0 || layer >= dimensions.z)
        return vec4(0.0);
    return texelFetch(shared_stack_texture, ivec3(cell.x % side, cell.z % side, layer), 0);
}
// x/z are plane gradients, y is height above the ordinary .1 floor.
vec3 shared_ground_support(vec3 position) {
    int code = int(shared_tile_record(position).a + 0.5);
    vec2 p = fract(position.xz);
    if (code == 1) return vec3(0.0, 0.9*(1.0-p.y), -0.9);
    if (code == 2) return vec3(0.9, 0.9*p.x, 0.0);
    if (code == 3) return vec3(0.0, 0.9*p.y, 0.9);
    if (code == 4) return vec3(-0.9, 0.9*(1.0-p.x), 0.0);
    if (code == 5) return vec3(0.0, 0.4, 0.0);
    return vec3(0.0);
}
vec2 shared_stack_interval(vec3 tile, float ordinal, int category) {
    if (!shared_stack_enabled) return vec2(0.005, 0.12);
    vec4 record = shared_tile_record(tile);
    float low = record.r + 0.005;
    // Match kPieceCeiling = 1 - kFloorHeight - .005; kFloorHeight = .1.
    float step = min(0.13, max(0.0, 0.895 - low) / max(1.0, record.g + record.b));
    return vec2(low + (ordinal + (category == 3 ? record.g : 0.0)) * step, step * (0.12 / 0.13));
}
