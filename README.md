# FuckerToolkit

Local Zig toolkit skeleton for a cross-platform runtime.

This repository currently implements:

- platform entry points for Windows, Android, Apple, and generic POSIX
- PAL path resolution and page-protection helpers
- VFS sandboxing under a private local root
- hook-engine ABI bindings for MinHook on Windows, ShadowHook on Android, and tinyhook on Apple platforms

Stealth, anti-detection, and unauthorized third-party process tampering are intentionally not part of this repository. The hook layer is a native in-process detour adapter around established platform libraries.

## Build

```bash
zig build -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseSafe
zig build -Dtarget=aarch64-linux-android -Doptimize=ReleaseSafe
zig build -Dtarget=aarch64-ios -Doptimize=ReleaseSafe
```

Run host tests:

```bash
zig build test
```

The default artifact is a static library under `zig-out/lib`. The library binds to the real platform hook backends by C ABI; final application linkage must provide MinHook, ShadowHook, or tinyhook on the corresponding platform.

## Script Location

At startup the bootstrapper resolves a private root and looks for:

```text
local://init.lua
```

The VFS rejects path traversal and keeps file access under the resolved private root.

## Exported C ABI

- `ftk_bootstrap_run_once`
- `ftk_hook_attach`
- `ftk_hook_detach`
- `ftk_memory_protect`
