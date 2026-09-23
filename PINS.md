# Version pins

Supported build baseline. Exact dependency revisions are the committed Git submodule pointers.

## Game

| What | Value |
|---|---|
| Dwarf Fortress version | 53.16 |
| Steam app ID | 975370 |
| Steam build ID | 24557528 (PE timestamp 0x6A70A6D9) |
| Install discovery | `libraryfolders.vdf` → app 975370 (explicit path override supported) |

## Bridge stack

| What | Value |
|---|---|
| DFHack | 53.16-r1 + df3d patches (branch `df3d/53.16`, head `39b289bb0891b3d96f56a34defe6a6f5552f89aa`), fork: github.com/UncertainCat/dfhack |
| df-structures | 53.16-r1 + codegen teardown fix (`27097fdca2f4ab81492d0543b45518039d0a7fef`, branch `df3d/53.16`), fork: github.com/UncertainCat/df-structures |
| dfhooks | upstream + C4455 fix (`2a43bca84ccfbe3ad6605eb47a5afcdd348cd673`, branch `df3d/fixes`), fork: github.com/UncertainCat/dfhooks |
| Working tree | `external/dfhack` (pinned submodule; its own repository) |

## Viewer host

| What | Value |
|---|---|
| Godot | 4.7.2 stable, Steam install (`godot.windows.opt.tools.64.exe`, `4.7.2.stable.steam.ed1daf0bf`) |
| godot-cpp | commit `7e18e40d7591429f915035a7de7cf79457d555cc` at `external/godot-cpp` (bundled extension API: 4.7-stable) |

godot-cpp is pinned to a master commit whose bundled extension API matches Godot 4.7, not to a release tag.

## Tooling (vendored under `third_party/`)

| What | Value |
|---|---|
| FlatBuffers | v25.12.19 (release tag `v25.12.19-2026-02-06-03fffb2`) |
| flatc | Windows release binary from that tag, `third_party/flatbuffers/bin/flatc.exe` |
| doctest | pinned single header, see `third_party/doctest/VERSION` |

## Toolchain (machine-provided, recorded for reproducibility)

| What | Value |
|---|---|
| Compiler | MinGW-w64 g++ 15.1.0 (MSYS2), C++20 |
| CMake | 3.30.5 |
| Generator | MinGW Makefiles (`mingw32-make`) |
