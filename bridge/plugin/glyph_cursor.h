#pragma once
#include <cstddef>

// Classic glyph delta cursor: which grid materials still need a glyph row.
// A ring snapshot is built up to four times before it publishes (the terrain
// delta shrinks on each failed attempt), so the published-materials mark may
// only advance once the publication succeeded; otherwise the retry skips the
// rows the failed attempt carried.
namespace df3d_glyph_cursor {
struct Range { size_t from, to; };
// Rows to serialize this attempt: everything for a Full, else the materials
// interned since the last acknowledged publication.
inline Range rowsToBuild(size_t materialsSent, size_t materialCount, bool full) {
    return {full ? 0 : materialsSent, materialCount};
}
// The mark after a snapshot carrying rows up to `builtTo` was acknowledged.
// Only ring snapshots advance it; a recording Full leaves it alone.
inline size_t afterPublish(size_t materialsSent, size_t builtTo, bool ring) {
    return ring && builtTo > materialsSent ? builtTo : materialsSent;
}
}  // namespace df3d_glyph_cursor
