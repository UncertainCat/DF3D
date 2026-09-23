// The asset provider: locate + verify the install, build or load the
// parsed index, and hand presentations the lookups. Shared
// layer-4 infrastructure: no engine types; textures are loaded by the
// presentation from the PNG paths the index names.
#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "df3d_assets/asset_index.h"
#include "df3d_assets/classic_glyphs.h"
#include "df3d_assets/steam_install.h"

namespace df3d::assets {

// Pinned Steam build (PINS.md). Bumping it is its own change.
inline constexpr const char* kPinnedSteamBuildId = "24557528";
inline constexpr const char* kPinnedDfVersion = "53.16";
inline constexpr uint32_t kPinnedPeTimestamp = 0x6A70A6D9u;

struct ProviderOptions {
  std::string installOverride;  // DF directory; "" = Steam discovery (or DF3D_DF_PATH)
  std::string steamRoot;        // "" = discover
  std::string cacheDir;         // "" = <LOCALAPPDATA>/df3d/assets (or DF3D_CACHE_DIR)
  bool useCache = true;
  bool allowBuildMismatch = false;  // diagnostics only (assets_probe)
  // Ignore the (size, mtime) manifest and hash every raw file's contents
  // (also DF3D_ASSETS_REHASH=1). The manifest cannot see an edit that
  // keeps a file's size and mtime.
  bool rehash = false;
};

struct Provider {
  InstallInfo install;
  AssetIndex index;
  std::string cacheDir, cachePath;
  bool cacheHit = false;
  bool manifestHit = false;  // content hash taken from the (size, mtime) manifest
  bool buildMismatch = false;  // only when allowBuildMismatch let it through
  std::vector<std::string> rawFiles;  // relative raw files that fed the hash
  std::vector<std::string> diagnostics;
  double indexMs = 0.0;  // parse or cache-load time (includes hashMs)
  double hashMs = 0.0;   // stamping the raws + (manifest check or content hash)
  // Classic-mode fallback inputs: the curses tileset the install's
  // init names (absPath empty when none exists; the presentation decodes
  // the PNG) and data/init/colors.txt (DF's defaults when unreadable).
  ClassicTileset classicTileset;
  ClassicPalette classicPalette;
  bool classicPaletteFromInstall = false;
};

// Hard failure: nullptr + a clear, multi-line explanation in err.
std::unique_ptr<Provider> openProvider(const ProviderOptions& opts, std::string& err);

// Building blocks (also used by tests).
// Enumerates the raw text files under <root>/data/vanilla that feed the
// index, sorted, as paths relative to root.
std::vector<std::string> listRawFiles(const std::string& root);
// FNV-1a over (relative path, contents) of every listed file.
uint64_t contentHashOf(const std::string& root, const std::vector<std::string>& relFiles);
// Parses every listed file into a fresh index.
bool buildIndex(const std::string& root, const std::vector<std::string>& relFiles,
                AssetIndex& out, std::vector<std::string>* diagnostics, std::string& err);
std::string defaultCacheDir();
std::string cacheFileName(std::string_view buildId, uint64_t hash);

// The startup manifest: per raw file its size and last-write time, plus
// the content hash they were measured with. When every stamp matches the
// stored one the hash is trusted without reading a byte of the raws.
struct RawFileStamp {
  std::string rel;
  uint64_t size = 0;
  int64_t mtime = 0;  // filesystem clock ticks since its epoch
  friend bool operator==(const RawFileStamp&, const RawFileStamp&) = default;
};
// Stats the listed files (tests); openProvider takes the stamps from the
// directory walk itself (listRawFileStamps) to avoid a second pass.
std::vector<RawFileStamp> stampRawFiles(const std::string& root,
                                        const std::vector<std::string>& relFiles);
std::vector<RawFileStamp> listRawFileStamps(const std::string& root);
std::string manifestFileName(std::string_view buildId);
std::string serializeManifest(std::string_view buildId, uint64_t hash,
                              const std::vector<RawFileStamp>& stamps);
// True (and `hash` set) only when the manifest names the same build and
// exactly the same files with the same sizes and mtimes, in order.
bool manifestMatches(std::string_view text, std::string_view buildId,
                     const std::vector<RawFileStamp>& stamps, uint64_t& hash);

}  // namespace df3d::assets
