# FuckerToolkit

Local C++17 toolkit skeleton for a Lua-driven, cross-platform runtime.

This repository currently implements the safe project foundation:

- platform entry points for Windows, Android, Apple, and generic POSIX
- PAL path resolution and page-protection helpers
- VFS sandboxing under a private local root
- Lua context abstraction with optional system Lua 5.4 integration
- high-level API bridge shape
- hook-engine interface backed by MinHook on Windows, ShadowHook on Android, and tinyhook on Apple platforms

Stealth, anti-detection, and unauthorized third-party process tampering are intentionally not part of this repository. The hook layer is a native in-process detour adapter around established platform libraries.

## Build

```powershell
cmake -S . -B build
cmake --build build
.\build\Debug\ftk_smoke_test.exe
```

On Windows, MinHook is fetched automatically by default. To use a packaged MinHook instead:

```powershell
cmake -S . -B build -DFTK_FETCH_MINHOOK=OFF -Dminhook_DIR=<path-to-minhook-config>
```

On Android, add ShadowHook through the official Prefab package and build with an Android toolchain so `find_package(shadowhook REQUIRED CONFIG)` resolves.

On Apple/iOS, build or install tinyhook first and pass:

```bash
cmake -S . -B build -DFTK_TINYHOOK_ROOT=/path/to/tinyhook
```

Enable Lua only when Lua 5.4 development files are installed:

```powershell
cmake -S . -B build -DFTK_WITH_LUA=ON
```

## Script Location

At startup the bootstrapper resolves a private root and looks for:

```text
local://init.lua
```

The VFS rejects path traversal and keeps file access under the resolved private root.
