// Texture-array layers preserve the source page dimensions and mip chain.
uniform bool batch_texture_enabled = false;
uniform sampler2DArray batch_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying flat float batch_layer;
vec4 sample_batch_grid(vec2 uv, vec2 cell) {
    vec2 size = vec2(textureSize(batch_texture, 0).xy);
    vec2 dx = dFdx(uv), dy = dFdy(uv);
    vec2 snapped = sharp_world_uv(uv * size) / size;
    if (cell.x <= 0.0 || cell.y <= 0.0 || cell == size) {
        return textureGrad(batch_texture, vec3(snapped, batch_layer), dx, dy);
    }
    vec2 index = clamp(floor(uv * size / cell), vec2(0.0), size / cell - 1.0);
    vec2 lo = round(index * cell), extent = round(cell);
    float max_lod = floor(log2(max(min(extent.x, extent.y), 1.0)));
    float scale = exp2(max_lod);
    if (any(greaterThan(abs(mod(lo, scale)), vec2(.001))) ||
        any(greaterThan(abs(mod(extent, scale)), vec2(.001))) ||
        any(greaterThan(abs(mod(size, scale)), vec2(.001)))) max_lod = 0.0;
    float footprint = max(length(dx * size), length(dy * size));
    float lod = clamp(log2(max(footprint, 1.0)), 0.0, max_lod);
    vec2 inset = vec2(.5 * exp2(ceil(lod)));
    snapped = clamp(snapped * size, lo + inset, lo + extent - inset) / size;
    return textureLod(batch_texture, vec3(snapped, batch_layer), lod);
}
