#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>

#include <chrono>
#include <filesystem>

#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"

using namespace df3d::mirror;

namespace {

FixtureStream mustParse(const SyntheticFort& fort) {
  FixtureStream fs;
  std::string err;
  REQUIRE_MESSAGE(parseFixture(fort.serialize(), fs, err), err);
  return fs;
}

SyntheticFort walkingDwarfFort() {
  SyntheticFort fort(48, 48, 10);
  fort.addUnit(1, "DWARF", 10, 10, 5, JobKind::Mine);
  fort.snapshot(100);
  fort.moveUnit(1, 11, 10, 5);
  fort.snapshot(101);
  return fort;
}

}  // namespace

TEST_CASE("round-trip: synthetic fixture parses and validates") {
  auto fs = mustParse(walkingDwarfFort());
  CHECK(fs.snapshots.size() == 2);
  CHECK(fs.snapshots[0]->tick() == 100);
  CHECK(fs.snapshots[0]->units()->size() == 1);
  CHECK(fs.snapshots[1]->units()->Get(0)->pos()->x() == 11);
  CHECK(fs.snapshots[0]->units()->Get(0)->job() == JobKind::Mine);
  CHECK(std::string(fs.snapshots[0]->units()->Get(0)->species()->c_str()) == "DWARF");
  CHECK(!validateStream(fs));
}

TEST_CASE("parse rejects bad magic") {
  std::vector<uint8_t> junk = {'N', 'O', 'P', 'E', 0, 0, 0, 0};
  FixtureStream fs;
  std::string err;
  CHECK(!parseFixture(junk, fs, err));
  CHECK(err.find("magic") != std::string::npos);
}

TEST_CASE("parse rejects truncated stream") {
  auto bytes = walkingDwarfFort().serialize();
  bytes.resize(bytes.size() - 3);
  FixtureStream fs;
  std::string err;
  CHECK(!parseFixture(bytes, fs, err));
  CHECK(err.find("truncated") != std::string::npos);
}

TEST_CASE("validator rejects schema version mismatch") {
  SyntheticFort fort(8, 8, 2);
  fort.addUnit(1, "DWARF", 0, 0, 0);
  fort.forgeSchemaVersion(9999);
  fort.snapshot(1);
  auto fs = mustParse(fort);
  auto err = validateStream(fs);
  REQUIRE(err);
  CHECK(err->find("schema version mismatch") != std::string::npos);
}

TEST_CASE("validator rejects out-of-bounds position") {
  SyntheticFort fort(8, 8, 2);
  fort.addUnit(1, "DWARF", 7, 7, 1);
  fort.snapshot(1);
  fort.moveUnit(1, 8, 7, 1);  // == sizeX, exclusive bound
  fort.snapshot(2);
  auto fs = mustParse(fort);
  auto err = validateStream(fs);
  REQUIRE(err);
  CHECK(err->find("outside map") != std::string::npos);
}

TEST_CASE("validator rejects negative position") {
  SyntheticFort fort(8, 8, 2);
  fort.addUnit(1, "DWARF", -1, 0, 0);
  fort.snapshot(1);
  auto err = validateStream(mustParse(fort));
  REQUIRE(err);
  CHECK(err->find("outside map") != std::string::npos);
}

TEST_CASE("validator rejects empty species") {
  SyntheticFort fort(8, 8, 2);
  fort.addUnit(1, "", 0, 0, 0);
  fort.snapshot(1);
  auto err = validateStream(mustParse(fort));
  REQUIRE(err);
  CHECK(err->find("species") != std::string::npos);
}

TEST_CASE("validator accepts paused publications but rejects backwards ticks") {
  SyntheticFort fort(8, 8, 2);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.snapshot(5);
  fort.snapshot(5);  // A paused command can publish another snapshot.
  CHECK_FALSE(validateStream(mustParse(fort)));
  fort.snapshot(4);
  auto err = validateStream(mustParse(fort));
  REQUIRE(err);
  CHECK(err->find("tick") != std::string::npos);
}

TEST_CASE("validator accepts empty unit list") {
  SyntheticFort fort(8, 8, 2);
  fort.snapshot(1);
  CHECK(!validateStream(mustParse(fort)));
}

namespace {
// A private scratch directory removed on every exit path, so a failing
// assertion never leaves files behind in the working directory.
struct TempDir {
  std::filesystem::path path;
  TempDir() {
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    path = std::filesystem::temp_directory_path() /
           ("df3d_validate_tests_" + std::to_string(static_cast<long long>(stamp)));
    std::filesystem::create_directories(path);
  }
  ~TempDir() {
    std::error_code ec;
    std::filesystem::remove_all(path, ec);
  }
};
}  // namespace

TEST_CASE("fixture file round-trip via disk") {
  TempDir dir;
  auto bytes = walkingDwarfFort().serialize();
  const std::string path = (dir.path / "validate_tests_roundtrip.df3dfix").string();
  std::string err;
  REQUIRE_MESSAGE(writeFixtureFile(path, bytes, err), err);
  FixtureStream fs;
  REQUIRE_MESSAGE(loadFixtureFile(path, fs, err), err);
  CHECK(fs.snapshots.size() == 2);
}
