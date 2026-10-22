#!/usr/bin/env bash
#
# build-android.sh — compile Raku++ into librakuengine.so for the app.
#
# The Android sibling of build-ios.sh: the same pinned engine source (taken
# from the Raku++ git repository with `git archive`, then patched with
# engine/patches/*.patch) and the same shim, built with the NDK for the three
# ABIs a phone, a tablet or an emulator can be. The libraries land in
# packages/raku_engine/android/src/main/jniLibs/<abi>/, which the plugin's
# Gradle module packages into the app.
#
# Usage:
#   engine/build-android.sh             # RAKUPP_REPO=~/raku++ RAKUPP_REF=v5.4.1
#   JOBS=4 engine/build-android.sh      # fewer parallel compiles (RAM)
#   ANDROID_NDK=/path/to/ndk engine/build-android.sh
#
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$ENGINE_DIR/.." && pwd)"
REPO="${RAKUPP_REPO:-$HOME/raku++}"
REF="${RAKUPP_REF:-v5.4.1}"
JOBS="${JOBS:-6}"
# The app's minSdk. Nothing below Android 9 is needed by the engine itself
# once iconv is left out (Bionic has it only from API 28).
API=24
NDK="${ANDROID_NDK:-$(ls -d "$HOME/Library/Android/sdk/ndk/"* 2>/dev/null | sort -V | tail -1)}"
BUILD="$ENGINE_DIR/build"
SRC="$BUILD/src-$REF"
OUT="$APP_DIR/packages/raku_engine/android/src/main/jniLibs"

command -v ninja >/dev/null || { echo "needs ninja (brew install ninja)"; exit 1; }
[[ -d "$NDK" ]] || { echo "no Android NDK found; set ANDROID_NDK"; exit 1; }
TOOLS="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"

# --- sources (shared with build-ios.sh) ---------------------------------------
if [[ ! -f "$SRC/.complete" ]]; then
  echo "==> exporting $REF from $REPO"
  rm -rf "$SRC"; mkdir -p "$SRC"
  git -C "$REPO" archive "$REF" src include rakujs/cnp_none.cpp CMakeLists.txt | tar -x -C "$SRC"
  for p in "$ENGINE_DIR"/patches/*.patch; do
    echo "==> applying $(basename "$p")"
    patch -d "$SRC" -p1 --quiet < "$p"
  done
  touch "$SRC/.complete"
fi
VERSION="$(grep -oE 'VERSION[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+' "$SRC/CMakeLists.txt" | head -1 | awk '{print $2}')"
echo "==> Raku++ $VERSION ($REF), NDK $(basename "$NDK"), API $API"

SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(
  cd "$SRC" && find src -name '*.cpp' \
    ! -path 'src/stubs/*' ! -name main.cpp ! -name Repl.cpp ! -name Codegen.cpp \
    ! -name JsRuntimeSrc.cpp ! -path 'src/codegen/Js.cpp' | sort)
SOURCES+=("rakujs/cnp_none.cpp")

build_abi() {   # abi clang-target
  local abi="$1" target="$2"
  local dir="$BUILD/android-$abi"
  mkdir -p "$dir"
  cp "$ENGINE_DIR/rakupp_mobile.cpp" "$ENGINE_DIR/rakupp_mobile.h" "$dir/"

  local flags="--target=$target$API -std=c++17 -O2 -fPIC -fexceptions -frtti"
  flags+=" -ffunction-sections -fdata-sections"
  flags+=" -fvisibility=hidden -fvisibility-inlines-hidden -w"
  flags+=" -DRAKUPP_BUILDING -DRAKUPP_VERSION=\\\"$VERSION\\\""
  flags+=" -I$SRC/src -I$SRC/include -I$SRC/include/rakupp"

  {
    echo "cxx = $TOOLS/clang++"
    echo "flags = $flags"
    echo "rule cc"
    echo "  command = \$cxx \$flags -MMD -MF \$out.d -c \$in -o \$out"
    echo "  depfile = \$out.d"
    echo "  deps = gcc"
    echo "  description = [$abi] \$in"
    # Static libc++, so the app ships one library per ABI and no
    # libc++_shared.so; 16 KB pages, which Google Play requires of native
    # code; and no undefined symbols, so a missing Bionic API fails the
    # build here rather than the app at run time.
    echo "rule link"
    echo "  command = \$cxx --target=$target$API -shared \$in -o \$out" \
         "-Wl,-soname,librakuengine.so -static-libstdc++ -Wl,--no-undefined" \
         "-Wl,--gc-sections -Wl,-z,max-page-size=16384 -ldl -lm"
    echo "  description = [$abi] link"
    local objs=()
    for s in "${SOURCES[@]}"; do
      local o="obj/${s//\//_}.o"
      echo "build $o: cc $SRC/$s"
      objs+=("$o")
    done
    echo "build obj/rakupp_mobile.o: cc $dir/rakupp_mobile.cpp"
    objs+=("obj/rakupp_mobile.o")
    echo "build librakuengine.so: link ${objs[*]}"
    echo "default librakuengine.so"
  } > "$dir/build.ninja"

  echo "==> compiling $abi (${#SOURCES[@]} units, $JOBS at a time)"
  ninja -C "$dir" -j "$JOBS"
  mkdir -p "$OUT/$abi"
  "$TOOLS/llvm-strip" --strip-unneeded -o "$OUT/$abi/librakuengine.so" "$dir/librakuengine.so"
}

build_abi arm64-v8a   aarch64-linux-android
build_abi armeabi-v7a armv7a-linux-androideabi
build_abi x86_64      x86_64-linux-android

echo "$REF" > "$OUT/../../../RakuEngine.version"
ls -lh "$OUT"/*/librakuengine.so
echo "==> done: $OUT"
