# FuckerToolkit

Local Zig toolkit skeleton for a cross-platform runtime.

This repository currently implements:

- platform entry points for Windows, Android, Apple, and generic POSIX
- PAL path resolution and page-protection helpers
- VFS sandboxing under a private local root
- Lua 5.4 runtime execution of `local://init.lua`
- file logging to `local://toolkit.log`
- hook-engine adapters that compile or link real MinHook, ShadowHook, and Dobby backends into the platform artifact

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

The default artifact is a shared library for the selected target. Backend source paths are required so the real platform hook library is compiled into the artifact:

```bash
zig build -Dtarget=x86_64-windows-msvc -Dminhook-root=deps/minhook
zig build -Dtarget=aarch64-linux-android -Dshadowhook-root=deps/shadowhook
zig build -Dtarget=aarch64-ios -Ddobby-root=deps/dobby -Ddobby-lib=deps/dobby-build/libdobby.a
```

All builds also require Lua 5.4 source files:

```bash
zig build -Dlua-root=deps/lua -Dtarget=x86_64-windows-msvc -Dminhook-root=deps/minhook
```

## Script Location

At startup the bootstrapper resolves a private root and looks for:

```text
local://init.lua
```

The VFS rejects path traversal and keeps file access under the resolved private root.

On iOS/LiveContainer the private root is:

```text
Documents/FuckerToolkit
```

Use:

```text
Documents/FuckerToolkit/init.lua
Documents/FuckerToolkit/toolkit.log
```

## Exported C ABI

- `ftk_bootstrap_run_once`
- `ftk_log_write`
- `ftk_hook_attach`
- `ftk_hook_detach`
- `ftk_memory_protect`

## Lua API

```lua
Toolkit.Log.info("message")
Toolkit.Log.warn("message")
Toolkit.Log.error("message")
print("also goes to toolkit.log")
```

Safe hook backend smoke test:

```lua
Toolkit.Hook.SelfTest()
```

To run the verbose sample, copy `examples/init_hook_selftest.lua` to
`Documents/FuckerToolkit/init.lua`. On Windows and Android it hooks an internal
native test function, checks the detour result, detaches it, and writes detailed
status lines to `toolkit.log`. On iOS/LiveContainer the self-hook is skipped
because patching the injected dylib text page can terminate the host before the
backend returns.

Image/RVA diagnostics for iOS:

```lua
local base = Toolkit.Image.Base("UnityFramework")
local address = Toolkit.Image.Address("UnityFramework", 0x1234)
local ok, resolved, bytes = Toolkit.Image.DiagnoseRva("UnityFramework", 0x1234, 16)
local bytes2 = Toolkit.Memory.ReadBytes(resolved, 16)
```

To run the diagnostic sample, copy `examples/init_image_diagnose.lua` to
`Documents/FuckerToolkit/init.lua`, set `image_name` and `rva`, then check
`toolkit.log`.

iOS automatic smoke test:

```lua
Toolkit.Hook.AutoSmokeTest()
```

The sample `examples/init_auto_smoke.lua` records the discovered
`UnityFramework`/`libil2cpp` images, then uses Dobby to detour
`il2cpp_domain_get` when that IL2CPP reflection export is available. The detour
only increments a counter and forwards to the original implementation. If
`il2cpp_domain_get` is not exported, the smoke test logs the first available
basic IL2CPP reflection export from a conservative candidate list.
