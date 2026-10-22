# The Raku++ engine in the app

The app runs Raku with [Raku++](https://raku.online), compiled from source into
`RakuEngine.xcframework` and called from Dart through `dart:ffi`
(`packages/raku_engine`).

```
~/raku++ (git, tag v5.4.1)
   │  git archive — never the working tree, so uncommitted engine work stays out
   ▼
engine/build/src-v5.4.1  +  engine/patches/*.patch  +  engine/rakupp_mobile.cpp
   │  engine/build-ios.sh  (clang + ninja, three slices)
   ▼
packages/raku_engine/ios/RakuEngine.xcframework  →  vendored by the plugin's podspec
```

## Rebuilding

```sh
engine/build-ios.sh                       # RAKUPP_REF=v5.4.1 by default
RAKUPP_REF=v5.5.0 engine/build-ios.sh     # a newer release
cd ios && pod install                     # only if the slices changed
```

About three minutes on an 8-core Mac (`JOBS=` sets the parallelism). The
slices are iOS device arm64, and one simulator framework with arm64 and x86_64.
Each is ~16 MB per architecture. The device slice is compiled with `-g` and
ships `RakuEngine.framework.dSYM` inside the xcframework (`-debug-symbols`), so
every archive carries it: App Store Connect asks for a dSYM per framework, and
it is what turns a crash inside the engine into function names. `engine/build/` is a scratch tree and can be
deleted.

When moving to a new tag, also regenerate the playground examples from the
same tag: `raku tool/examples.raku --ref=<tag> > assets/data/examples.json`.

## The shim — `rakupp_mobile.cpp`

`rk_run` is synchronous, and an output callback cannot cross into Dart safely
(the buffer is gone by the time Dart reads it). So the shim runs each program
on a 512 MB-stack thread of its own with a fresh interpreter, buffers the
output (capped at 1 MB, after which the run is stopped), and the Dart side
polls `rkm_take_output` / `rkm_state` every 40 ms. `rkm_highlight` exposes the
engine's own tokenizer for syntax colouring.

Input can be interactive: with `interactive` set, the shim installs its own
buffer as `std::cin`, so a `prompt` or `get` that has run out of input blocks
until the app sends a line (`rkm_send_input`) or ends the input
(`rkm_end_input`, the app's "End" button). `rkm_waiting_input` tells the app
when to show the input line, and Stop also releases a waiting read.

## The patches

All three are small and written so they could go upstream as they are.

- **`rk-interrupt.patch`** adds `rk_interrupt()` to the embedding API — the
  Stop button. A process-wide flag is checked at each statement, block entry
  and Int-kernel loop iteration; a raised flag throws `X::AdHoc "Interrupted"`
  and stays raised until the next run, so a `try` cannot swallow it. Raku++
  itself notes this as missing ("an rk_interrupt is future ABI work" in
  `McpServer.cpp`); once upstream has it, drop this patch.
- **`android-compat.patch`** keeps `statx` out of builds for Android below API 30
  (see below).
- **`ios-compat.patch`** lets three files compile for iOS: no `system()` in
  the opt-in JIT, no `MAP_JIT` fallback (an app may not map executable
  memory), and `arc4random_buf` instead of `getentropy`, which iOS's SDK lacks.

## Checking it

`integration_test/engine_test.dart` runs the engine on a simulator or device:
output, errors, stdin, Stop (including native loop kernels), the output cap,
deep recursion, threads, file IO, grammars and highlighting.

```sh
flutter test integration_test/engine_test.dart -d <device>
```

## Android

`engine/build-android.sh` builds the same pinned source, patches and shim with
the NDK into `librakuengine.so` for arm64-v8a, armeabi-v7a and x86_64, into
`packages/raku_engine/android/src/main/jniLibs/`. The libraries link libc++
statically, are 16 KB-page aligned (Google Play requires it), and are linked
with `--no-undefined` against Android 7 (API 24), so a Bionic call that a
device might lack fails the build rather than the app. `iconv` is left out —
Bionic has it only from Android 9 — which costs only the gb2312, gb18030 and
windows-932 encodings. `android-compat.patch` keeps `statx` (Bionic API 30)
out of older targets; `IO::Path.created` answers 0 below Android 11.

```sh
engine/build-android.sh     # about three minutes for the three ABIs
```
