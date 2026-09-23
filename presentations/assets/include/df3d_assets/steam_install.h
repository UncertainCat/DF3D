// Locating and verifying the Dwarf Fortress Steam install.
//
// Discovery: Steam root (explicit, env DF3D_STEAM_ROOT, the Windows
// registry, then the default Program Files path) -> steamapps/
// libraryfolders.vdf -> the library whose `apps` block lists app 975370 ->
// appmanifest_975370.acf -> `installdir` + `buildid`. An explicit install
// path override skips the library walk; its build is then verified from
// the manifest next to it when one exists, otherwise from the PE link
// timestamp of `Dwarf Fortress.exe` (PINS.md records both). No Classic or
// itch.io layouts. Every failure is a hard, explained error.
#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace df3d::assets {

inline constexpr const char* kDfSteamAppId = "975370";

// Minimal Valve KeyValues (VDF) tree: quoted keys with quoted values or
// brace-delimited children.
struct VdfNode {
  std::map<std::string, std::string> values;
  std::map<std::string, std::unique_ptr<VdfNode>> children;

  const VdfNode* child(std::string_view key) const;
  std::string value(std::string_view key, std::string fallback = {}) const;
};

// Parses VDF text; returns the (unnamed) root holding the top-level key.
// False with err on malformed input.
bool parseVdf(std::string_view text, VdfNode& root, std::string& err);

// Library folder paths from libraryfolders.vdf, in file order, with the
// set of app ids each lists.
struct SteamLibrary {
  std::string path;
  std::vector<std::string> apps;
};
std::vector<SteamLibrary> parseLibraryFolders(const VdfNode& root);

struct AppManifest {
  std::string appId, name, installDir, buildId;
};
// From an appmanifest_<id>.acf tree.
std::optional<AppManifest> parseAppManifest(const VdfNode& root);

// PE header TimeDateStamp of an executable (0 when unreadable / not PE).
uint32_t readPeTimestamp(const std::string& exePath);
// Same over in-memory bytes (tier-0 testable).
uint32_t peTimestampOf(std::string_view bytes);

struct InstallInfo {
  std::string root;       // absolute install directory
  std::string buildId;    // Steam manifest buildid ("" when no manifest)
  uint32_t peTimestamp = 0;
  std::string via;        // how it was found (for logs)
};

struct LocateOptions {
  std::string installOverride;  // explicit DF directory (skips Steam)
  std::string steamRoot;        // explicit Steam root (skips discovery)
};

// Locates the install. On failure returns nullopt and a multi-line
// explanation in err (what was searched, what to do).
std::optional<InstallInfo> locateInstall(const LocateOptions& opts, std::string& err);

// Verification against the pinned build (PINS.md). `pinnedBuildId` must
// match the manifest when a manifest is present; `pinnedPeTimestamp` is
// used when no manifest could be read. Returns false with an explanation.
bool verifyInstallBuild(const InstallInfo& info, std::string_view pinnedBuildId,
                        uint32_t pinnedPeTimestamp, std::string& err);

// Path helpers (forward slashes normalised; no filesystem access).
std::string joinPath(std::string_view a, std::string_view b);
std::string parentPath(std::string_view p);
bool fileExists(const std::string& path);
bool dirExists(const std::string& path);

}  // namespace df3d::assets
