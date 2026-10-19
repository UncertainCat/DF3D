// CUSTOM1 stores source level * 3 + alternative: common, covered-only, cut-only.
// Source meshes use their level parents; only vertical batches enable this path.
uniform bool terrain_batch_clip = false;
uniform vec2 terrain_batch_slice = vec2(0.0, -1.0);
bool terrain_batch_visible(float part) {
    if (!terrain_batch_clip) { return true; }
    float level = floor(part / 3.0);
    float alternative = part - level * 3.0;
    return level >= terrain_batch_slice.x && level <= terrain_batch_slice.y
        && (alternative < 0.5 || (alternative < 1.5
            ? level < terrain_batch_slice.y : level == terrain_batch_slice.y));
}
