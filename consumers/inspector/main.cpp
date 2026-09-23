// inspector — text query tool over a mirror fixture.
// Usage: inspector <fixture-file> [--tick <renderTick>] [--z <level>] [--list]
// Without --tick, reports at the latest snapshot tick; without --z, draws
// the level holding the most units. --list also prints every building and
// item of the drawn level, one line each.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <optional>
#include <string>

#include "inspect.h"
#include "wm/world_model.h"

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <fixture-file> [--tick <renderTick>] [--z <level>] [--list]\n",
                 argv[0]);
    return 2;
  }
  const std::string path = argv[1];
  double renderTick = -1.0;
  std::optional<int> z;
  inspector::ReportOptions options;
  for (int i = 2; i < argc; ++i) {
    if (std::strcmp(argv[i], "--list") == 0) options.listEntities = true;
    if (i == argc - 1) break;
    if (std::strcmp(argv[i], "--tick") == 0) renderTick = std::atof(argv[i + 1]);
    if (std::strcmp(argv[i], "--z") == 0) z = std::atoi(argv[i + 1]);
  }

  wm::WorldModel model;
  std::string err;
  if (!wm::loadFixtureFile(model, path, err)) {
    std::fprintf(stderr, "error: %s\n", err.c_str());
    return 1;
  }
  if (renderTick < 0.0) renderTick = static_cast<double>(model.latestTick());

  std::fputs(inspector::report(model, renderTick, z, options).c_str(), stdout);
  return 0;
}
