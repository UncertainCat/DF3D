#include "df3d_assets/provider.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>

#include "df3d_assets/raw_tokens.h"

namespace fs = std::filesystem;

namespace df3d::assets {

// The walk is the whole per-start cost of the manifest path, so it stays
// syscall-light: relative paths are built lexically (fs::relative would
// canonicalise every path, ~250 ms over the 322 files) and size / mtime
// come from the directory entry the iterator already holds.
std::vector<RawFileStamp> listRawFileStamps(const std::string& root) {
  std::vector<RawFileStamp> out;
  const fs::path vanilla = fs::path(root) / "data" / "vanilla";
  std::error_code ec;
  if (!fs::is_directory(vanilla, ec)) return out;
  for (const auto& mod : fs::directory_iterator(vanilla, ec)) {
    if (!mod.is_directory()) continue;
    const std::string modName = mod.path().filename().generic_string();
    for (const char* sub : {"graphics", "objects"}) {
      const fs::path dir = mod.path() / sub;
      if (!fs::is_directory(dir, ec)) continue;
      for (const auto& f : fs::directory_iterator(dir, ec)) {
        if (!f.is_regular_file()) continue;
        if (f.path().extension() != ".txt") continue;
        RawFileStamp s;
        s.rel = "data/vanilla/" + modName + "/" + sub + "/" + f.path().filename().generic_string();
        std::error_code sec;
        const auto size = f.file_size(sec);
        s.size = sec ? 0 : static_cast<uint64_t>(size);
        const auto t = f.last_write_time(sec);
        s.mtime = sec ? 0 : static_cast<int64_t>(t.time_since_epoch().count());
        out.push_back(std::move(s));
      }
    }
  }
  std::sort(out.begin(), out.end(),
            [](const RawFileStamp& a, const RawFileStamp& b) { return a.rel < b.rel; });
  return out;
}

std::vector<std::string> listRawFiles(const std::string& root) {
  std::vector<std::string> out;
  for (RawFileStamp& s : listRawFileStamps(root)) out.push_back(std::move(s.rel));
  return out;
}

uint64_t contentHashOf(const std::string& root, const std::vector<std::string>& relFiles) {
  uint64_t h = fnv1a64("df3d-assets-v1");
  for (const std::string& rel : relFiles) {
    std::string text, err;
    h = fnv1a64(rel, h);
    h = fnv1a64(std::string_view("\0", 1), h);
    if (readTextFile(joinPath(root, rel), text, err)) h = fnv1a64(text, h);
    h = fnv1a64(std::string_view("\0", 1), h);
  }
  return h;
}

bool buildIndex(const std::string& root, const std::vector<std::string>& relFiles,
                AssetIndex& out, std::vector<std::string>* diagnostics, std::string& err) {
  AssetIndex idx;
  // Material templates and colour descriptors must precede the materials
  // that reference them: parse by object type in dependency order.
  std::vector<std::pair<std::string, std::string>> texts;  // rel, text
  texts.reserve(relFiles.size());
  for (const std::string& rel : relFiles) {
    std::string text;
    if (!readTextFile(joinPath(root, rel), text, err)) return false;
    texts.emplace_back(rel, std::move(text));
  }
  auto pass = [&](auto keep) {
    for (auto& [rel, text] : texts) {
      const std::string obj = rawObjectType(tokenizeRaw(text));
      if (!keep(obj)) continue;
      const std::string dir = parentPath(joinPath(root, rel));
      ingestRawText(idx, text, dir, rel, diagnostics);
    }
  };
  pass([](const std::string& o) { return o == "TILE_PAGE" || o == "DESCRIPTOR_COLOR" ||
                                          o == "MATERIAL_TEMPLATE" || o == "PALETTE"; });
  pass([](const std::string& o) { return o == "GRAPHICS" || o == "INORGANIC" || o == "PLANT" || o == "CREATURE"; });
  finalizeIndex(idx);
  out = std::move(idx);
  return true;
}

std::string defaultCacheDir() {
  if (const char* e = std::getenv("DF3D_CACHE_DIR"); e && *e) return e;
#ifdef _WIN32
  if (const char* e = std::getenv("LOCALAPPDATA"); e && *e) return joinPath(e, "df3d/assets");
#else
  if (const char* e = std::getenv("XDG_CACHE_HOME"); e && *e) return joinPath(e, "df3d/assets");
  if (const char* e = std::getenv("HOME"); e && *e) return joinPath(e, ".cache/df3d/assets");
#endif
  return "cache/assets";
}

std::string cacheFileName(std::string_view buildId, uint64_t hash) {
  char buf[64];
  std::snprintf(buf, sizeof buf, "index_%s_%016llx.txt", std::string(buildId).c_str(),
                static_cast<unsigned long long>(hash));
  return buf;
}

std::vector<RawFileStamp> stampRawFiles(const std::string& root,
                                        const std::vector<std::string>& relFiles) {
  std::vector<RawFileStamp> out;
  out.reserve(relFiles.size());
  for (const std::string& rel : relFiles) {
    RawFileStamp s;
    s.rel = rel;
    std::error_code ec;
    const fs::path p = fs::path(root) / rel;
    const auto size = fs::file_size(p, ec);
    s.size = ec ? 0 : static_cast<uint64_t>(size);
    const auto t = fs::last_write_time(p, ec);
    s.mtime = ec ? 0 : static_cast<int64_t>(t.time_since_epoch().count());
    out.push_back(std::move(s));
  }
  return out;
}

namespace {
constexpr const char* kManifestMagic = "DF3DAMF";
constexpr int kManifestFormat = 1;
}  // namespace

std::string manifestFileName(std::string_view buildId) {
  return "manifest_" + std::string(buildId) + ".txt";
}

std::string serializeManifest(std::string_view buildId, uint64_t hash,
                              const std::vector<RawFileStamp>& stamps) {
  char head[96];
  std::snprintf(head, sizeof head, "%s %d %s %016llx %zu\n", kManifestMagic, kManifestFormat,
                std::string(buildId).c_str(), static_cast<unsigned long long>(hash),
                stamps.size());
  std::string out = head;
  for (const RawFileStamp& s : stamps) {
    out += s.rel;
    out += '\t';
    out += std::to_string(s.size);
    out += '\t';
    out += std::to_string(s.mtime);
    out += '\n';
  }
  return out;
}

bool manifestMatches(std::string_view text, std::string_view buildId,
                     const std::vector<RawFileStamp>& stamps, uint64_t& hash) {
  size_t pos = text.find('\n');
  if (pos == std::string_view::npos) return false;
  {
    std::istringstream head{std::string(text.substr(0, pos))};
    std::string magic, build, hashHex;
    int format = 0;
    size_t count = 0;
    if (!(head >> magic >> format >> build >> hashHex >> count)) return false;
    if (magic != kManifestMagic || format != kManifestFormat || build != buildId) return false;
    if (count != stamps.size()) return false;
    try {
      hash = std::stoull(hashHex, nullptr, 16);
    } catch (...) {
      return false;
    }
  }
  ++pos;
  for (const RawFileStamp& s : stamps) {
    size_t nl = text.find('\n', pos);
    if (nl == std::string_view::npos) return false;
    const std::string_view line = text.substr(pos, nl - pos);
    pos = nl + 1;
    const size_t t1 = line.find('\t');
    const size_t t2 = t1 == std::string_view::npos ? t1 : line.find('\t', t1 + 1);
    if (t2 == std::string_view::npos) return false;
    if (line.substr(0, t1) != s.rel) return false;
    if (line.substr(t1 + 1, t2 - t1 - 1) != std::to_string(s.size)) return false;
    if (line.substr(t2 + 1) != std::to_string(s.mtime)) return false;
  }
  return pos >= text.size();  // no trailing entries
}

std::unique_ptr<Provider> openProvider(const ProviderOptions& opts, std::string& err) {
  auto p = std::make_unique<Provider>();
  LocateOptions lo;
  lo.installOverride = opts.installOverride;
  lo.steamRoot = opts.steamRoot;
  auto found = locateInstall(lo, err);
  if (!found) return nullptr;
  p->install = *found;

  std::string verr;
  if (!verifyInstallBuild(p->install, kPinnedSteamBuildId, kPinnedPeTimestamp, verr)) {
    if (!opts.allowBuildMismatch) {
      err = verr;
      return nullptr;
    }
    p->buildMismatch = true;
    p->diagnostics.push_back("build mismatch tolerated: " + verr);
  }

  const auto t0 = std::chrono::steady_clock::now();
  const std::vector<RawFileStamp> stamps = listRawFileStamps(p->install.root);
  for (const RawFileStamp& s : stamps) p->rawFiles.push_back(s.rel);
  if (p->rawFiles.empty()) {
    err = "No raw files found under " + p->install.root +
          "/data/vanilla/*/{graphics,objects}; the install is not a recognizable DF " +
          kPinnedDfVersion + " layout.";
    return nullptr;
  }
  const std::string buildId = p->install.buildId.empty() ? "nomanifest" : p->install.buildId;
  p->cacheDir = opts.cacheDir.empty() ? defaultCacheDir() : opts.cacheDir;

  // The content hash keys the cache. Hashing reads every raw (~0.4 s on
  // the pinned install); the manifest written with the last index
  // lets a start whose raw files have the same (size, mtime) stamps take
  // the hash without reading them. Anything different -- a file added,
  // removed, resized or touched, a missing or malformed manifest, or an
  // explicit rehash -- falls back to hashing the contents.
  const std::string manifestPath = joinPath(p->cacheDir, manifestFileName(buildId));
  bool rehash = opts.rehash;
  if (const char* e = std::getenv("DF3D_ASSETS_REHASH"); e && *e && *e != '0') rehash = true;
  uint64_t hash = 0;
  if (opts.useCache && !rehash) {
    std::string text, rerr;
    if (readTextFile(manifestPath, text, rerr) && manifestMatches(text, buildId, stamps, hash)) {
      p->manifestHit = true;
    }
  }
  if (!p->manifestHit) hash = contentHashOf(p->install.root, p->rawFiles);
  p->hashMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0)
                  .count();
  p->cachePath = joinPath(p->cacheDir, cacheFileName(buildId, hash));

  if (opts.useCache) {
    std::string text, rerr;
    if (readTextFile(p->cachePath, text, rerr)) {
      std::string cb;
      uint64_t ch = 0;
      AssetIndex cached;
      if (peekIndexKey(text, cb, ch) && cb == buildId && ch == hash &&
          deserializeIndex(text, cached, rerr)) {
        p->index = std::move(cached);
        p->cacheHit = true;
      } else {
        p->diagnostics.push_back("cache rejected (" + (rerr.empty() ? "key mismatch" : rerr) +
                                 "): " + p->cachePath);
      }
    }
  }
  if (!p->cacheHit) {
    if (!buildIndex(p->install.root, p->rawFiles, p->index, &p->diagnostics, err)) return nullptr;
    p->index.buildId = buildId;
    p->index.contentHash = hash;
    if (opts.useCache) {
      std::error_code ec;
      fs::create_directories(fs::path(p->cacheDir), ec);
      const std::string tmp = p->cachePath + ".tmp";
      std::ofstream out(tmp, std::ios::binary);
      if (out) {
        out << serializeIndex(p->index);
        out.close();
        fs::rename(fs::path(tmp), fs::path(p->cachePath), ec);
        if (ec) p->diagnostics.push_back("cache write failed: " + ec.message());
      } else {
        p->diagnostics.push_back("cache write failed: cannot open " + tmp);
      }
    }
  }
  if (opts.useCache && !p->manifestHit) {
    // (Re)write the manifest for the stamps measured above. A raw edited
    // between stamping and hashing would be caught by the next start's
    // stamps.
    std::error_code ec;
    fs::create_directories(fs::path(p->cacheDir), ec);
    const std::string tmp = manifestPath + ".tmp";
    std::ofstream out(tmp, std::ios::binary);
    if (out) {
      out << serializeManifest(buildId, hash, stamps);
      out.close();
      fs::rename(fs::path(tmp), fs::path(manifestPath), ec);
      if (ec) p->diagnostics.push_back("manifest write failed: " + ec.message());
    } else {
      p->diagnostics.push_back("manifest write failed: cannot open " + tmp);
    }
  }
  p->indexMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0)
                   .count();

  // Classic fallback inputs: not fatal -- an install without a
  // curses tileset only loses the glyph fallback (markers remain).
  p->classicTileset = resolveClassicTileset(p->install.root);
  if (p->classicTileset.absPath.empty()) {
    p->diagnostics.push_back("no classic tileset under data/art (glyph fallback disabled)");
  }
  p->classicPalette = defaultClassicPalette();
  {
    std::string text, cerr;
    const std::string colors =
        (std::filesystem::path(p->install.root) / "data" / "init" / "colors.txt").string();
    if (readTextFile(colors, text, cerr)) {
      ClassicPalette parsed;
      if (parseClassicColors(text, parsed) == 48) {
        p->classicPalette = parsed;
        p->classicPaletteFromInstall = true;
      } else {
        p->diagnostics.push_back("data/init/colors.txt incomplete: using DF's default colours");
      }
    } else {
      p->diagnostics.push_back("data/init/colors.txt unreadable: using DF's default colours");
    }
  }

  // Sanity: the environment tile vocabulary this presentation depends on.
  for (const char* must : {"STONE_WALL_N_S_W_E_1", "STONE_FLOOR_5", "GRASS_5", "WATER"}) {
    if (!p->index.tile(must)) {
      err = "The install at " + p->install.root + " lacks the terrain tile graphic '" + must +
            "' (expected in data/vanilla/vanilla_environment/graphics/graphics_tiles.txt). The "
            "asset layout is not the pinned DF " +
            kPinnedDfVersion + " layout; refusing to start.";
      return nullptr;
    }
  }
  return p;
}

}  // namespace df3d::assets
