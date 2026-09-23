// World art only. Derivatives come from original UVs, never the snapped coordinates.
// Isolated resources use hardware mip/anisotropic filtering. Atlas regions clamp
// both mip level and sample footprint before any neighboring cell can contribute.
vec2 sharp_world_uv(vec2 pixel) {
    vec2 width = clamp(fwidth(pixel), vec2(.0001), vec2(1.0));
    vec2 f = fract(pixel);
    return floor(pixel) + .5 + min(f / width - .5, vec2(0.0))
        + max((f - 1.0) / width + .5, vec2(0.0));
}
vec4 sample_world_region(sampler2D tex, vec2 uv, vec4 region) {
    vec2 size = vec2(textureSize(tex, 0));
    vec2 dx = dFdx(uv), dy = dFdy(uv);
    vec2 snapped = sharp_world_uv(uv * size) / size;
    if (region == vec4(0.0, 0.0, 1.0, 1.0)) {
        return textureGrad(tex, snapped, dx, dy);
    }
    vec2 lo = round(region.xy * size);
    vec2 extent = round(region.zw * size);
    // Only descend through levels with integer-aligned region and page edges.
    float max_lod = floor(log2(max(min(extent.x, extent.y), 1.0)));
    float scale = exp2(max_lod);
    // Unusual non-aligned regions conservatively stay at level zero.
    if (any(greaterThan(abs(mod(lo, scale)), vec2(.001))) ||
        any(greaterThan(abs(mod(extent, scale)), vec2(.001))) ||
        any(greaterThan(abs(mod(size, scale)), vec2(.001)))) max_lod = 0.0;
    float footprint = max(length(dx * size), length(dy * size));
    float lod = clamp(log2(max(footprint, 1.0)), 0.0, max_lod);
    vec2 inset = vec2(.5 * exp2(ceil(lod)));
    snapped = clamp(snapped * size, lo + inset, lo + extent - inset) / size;
    return textureLod(tex, snapped, lod);
}
vec4 sample_world_grid(sampler2D tex, vec2 uv, vec2 cell) {
    vec2 size = vec2(textureSize(tex, 0));
    if (cell.x <= 0.0 || cell.y <= 0.0) return sample_world_region(tex, uv, vec4(0.0,0.0,1.0,1.0));
    vec2 index = clamp(floor(uv * size / cell), vec2(0.0), size / cell - 1.0);
    return sample_world_region(tex, uv, vec4(index * cell / size, cell / size));
}
