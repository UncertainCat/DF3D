#include "fixture_io.h"

#include <cstring>
#include <fstream>

namespace df3d::mirror {

bool parseFixture(std::vector<uint8_t> bytes, FixtureStream& out, std::string& error) {
  out.data = std::move(bytes);
  out.snapshots.clear();
  const auto& d = out.data;

  if (d.size() < sizeof(kFixtureMagic) ||
      std::memcmp(d.data(), kFixtureMagic, sizeof(kFixtureMagic)) != 0) {
    error = "not a DF3D fixture: bad magic";
    return false;
  }

  size_t off = sizeof(kFixtureMagic);
  while (off < d.size()) {
    if (d.size() - off < sizeof(uint32_t)) {
      error = "truncated fixture: dangling bytes after snapshot " +
              std::to_string(out.snapshots.size());
      return false;
    }
    uint32_t len = 0;
    std::memcpy(&len, d.data() + off, sizeof(len));
    if (d.size() - off - sizeof(uint32_t) < len) {
      error = "truncated fixture: snapshot " + std::to_string(out.snapshots.size()) +
              " claims " + std::to_string(len) + " bytes past end of file";
      return false;
    }
    flatbuffers::Verifier v(d.data() + off, sizeof(uint32_t) + len);
    if (!VerifySizePrefixedSnapshotBuffer(v)) {
      error = "snapshot " + std::to_string(out.snapshots.size()) +
              " failed FlatBuffers verification";
      return false;
    }
    out.snapshots.push_back(GetSizePrefixedSnapshot(d.data() + off));
    off += sizeof(uint32_t) + len;
  }
  return true;
}

bool loadFixtureFile(const std::string& path, FixtureStream& out, std::string& error) {
  std::ifstream f(path, std::ios::binary);
  if (!f) {
    error = "cannot open fixture file: " + path;
    return false;
  }
  std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(f)),
                             std::istreambuf_iterator<char>());
  return parseFixture(std::move(bytes), out, error);
}

std::vector<uint8_t> assembleFixture(const std::vector<std::vector<uint8_t>>& snapshotBuffers) {
  std::vector<uint8_t> out(kFixtureMagic, kFixtureMagic + sizeof(kFixtureMagic));
  for (const auto& buf : snapshotBuffers) out.insert(out.end(), buf.begin(), buf.end());
  return out;
}

bool writeFixtureFile(const std::string& path, const std::vector<uint8_t>& fixtureBytes,
                      std::string& error) {
  std::ofstream f(path, std::ios::binary | std::ios::trunc);
  if (!f) {
    error = "cannot open fixture file for writing: " + path;
    return false;
  }
  f.write(reinterpret_cast<const char*>(fixtureBytes.data()),
          static_cast<std::streamsize>(fixtureBytes.size()));
  if (!f) {
    error = "write failed: " + path;
    return false;
  }
  return true;
}

}  // namespace df3d::mirror
