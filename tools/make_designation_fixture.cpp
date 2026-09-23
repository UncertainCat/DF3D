// Generates the synthetic before/after recordings fixture_evidence replays:
// a paused fortress with a marked Dig designation at (127,61,165) whose
// priority changes across a save/reload (2 before, 3 after), unit 988
// present in both, each recording a terrain Full followed by a Delta.
// Usage: make_designation_fixture <before.df3dfix> <after.df3dfix>
#include <cstdio>
#include <string>

#include "fixture_io.h"
#include "synthetic_builder.h"
#include "terrain_util.h"

using namespace df3d::mirror;

namespace {

bool writeRecording(const char* path, uint8_t priority) {
  SyntheticFort fort(128, 64, 166);
  const uint16_t granite = fort.material("GRANITE");
  const TileState wall(TileShape::Wall, MaterialKind::Stone, granite, 0, LiquidKind::None,
                       TileFlags::Hidden, DesignationKind::None);
  const TileState marked(TileShape::Wall, MaterialKind::Stone, granite, 0, LiquidKind::None,
                         TileFlags::DigDesignated, DesignationKind::Dig);
  fort.fillBox(TilePos(120, 56, 165), TilePos(127, 63, 165), wall);
  fort.setTile(127, 61, 165, marked);
  fort.setDesignationDetail(127, 61, 165, priority, true);
  fort.addUnit(988, "DWARF", 126, 61, 165, JobKind::Idle);
  fort.snapshot(1000);  // Full
  fort.setTile(120, 56, 165, TileState(TileShape::Floor, MaterialKind::Stone, granite, 0,
                                       LiquidKind::None, TileFlags::NONE, DesignationKind::None));
  fort.snapshot(1001);  // Delta re-sends the block carrying the designation
  std::string error;
  if (writeFixtureFile(path, fort.serialize(), error)) return true;
  std::fprintf(stderr, "%s: %s\n", path, error.c_str());
  return false;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 3) {
    std::fprintf(stderr, "usage: make_designation_fixture <before.df3dfix> <after.df3dfix>\n");
    return 2;
  }
  return writeRecording(argv[1], 2) && writeRecording(argv[2], 3) ? 0 : 1;
}
