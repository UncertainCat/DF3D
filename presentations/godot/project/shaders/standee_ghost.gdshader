shader_type spatial;
render_mode cull_back, unshaded, depth_prepass_alpha;
#define STANDEE_GHOST
#include "standee.gdshaderinc"
void vertex() {
    sprite_tile_center = CUSTOM2.xy;
    // Preserve native foreground ordering only in the straight-down view.
    // Angled views keep the artwork rows on their shared physical base.
    if (INV_VIEW_MATRIX[2].y > 0.9999) {
        VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(0.0, CUSTOM2.z, 0.0);
    }
}
