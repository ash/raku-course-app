#!/usr/bin/env bash
#
# build-ios.sh — compile Raku++ into RakuEngine.xcframework for the app.
#
# The engine is taken from the Raku++ git repository at a pinned release tag
# with `git archive`, so whatever is uncommitted in that checkout never leaks
# into the app, then patched with engine/patches/*.patch, compiled for the iOS
# device and the Apple-silicon simulator, and wrapped as a dynamic framework.
# The result lands in packages/raku_engine/ios/, where the plugin's podspec
# vendors it.
#
# Usage:
#   engine/build-ios.sh                 # RAKUPP_REPO=~/raku++ RAKUPP_REF=v5.4.1
#   RAKUPP_REF=v5.5.0 engine/build-ios.sh
#   JOBS=4 engine/build-ios.sh          # fewer parallel compiles (RAM)
#
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$ENGINE_DIR/.." && pwd)"
REPO="${RAKUPP_REPO:-$HOME/raku++}"
REF="${RAKUPP_REF:-v5.4.1}"
JOBS="${JOBS:-6}"
MIN_IOS=13.0
BUILD="$ENGINE_DIR/build"
SRC="$BUILD/src-$REF"
OUT="$APP_DIR/packages/raku_engine/ios/RakuEngine.xcframework"

command -v ninja >/dev/null || { echo "needs ninja (brew install ninja)"; exit 1; }

# --- sources ----------------------------------------------------------------
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
echo "==> Raku++ $VERSION ($REF)"

# Everything the CMake runtime library takes: all of src/ but the CLI entry
# point, the REPL, the C++ and JS backends and the slim-build stubs. The
# copy-and-patch JIT gets the empty stencil table, as in the WebAssembly
# build: an iOS app may not map executable memory, so there is no JIT here.
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(
  cd "$SRC" && find src -name '*.cpp' \
    ! -path 'src/stubs/*' ! -name main.cpp ! -name Repl.cpp ! -name Codegen.cpp \
    ! -name JsRuntimeSrc.cpp ! -path 'src/codegen/Js.cpp' | sort)
SOURCES+=("rakujs/cnp_none.cpp")

# --- one slice ----------------------------------------------------------------
build_slice() {   # name sdk target platform-name
  local name="$1" sdk="$2" target="$3" platform="$4"
  local dir="$BUILD/$name"
  local sysroot; sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  local cxx; cxx="$(xcrun --sdk "$sdk" -f clang++)"
  mkdir -p "$dir"
  cp "$ENGINE_DIR/rakupp_mobile.cpp" "$ENGINE_DIR/rakupp_mobile.h" "$dir/"

  local flags="-target $target -isysroot $sysroot -std=c++17 -O2 -fPIC -fexceptions -frtti"
  # The device slice carries debug info, from which its dSYM is made: App
  # Store Connect wants one per framework in the archive, and it is what turns
  # a crash inside the engine into function names. The simulator needs none.
  [[ "$sdk" == iphoneos ]] && flags+=" -g"
  flags+=" -fvisibility=hidden -fvisibility-inlines-hidden -w"
  flags+=" -DRAKUPP_BUILDING -DRAKUPP_HAVE_ICONV -DRAKUPP_VERSION=\\\"$VERSION\\\""
  flags+=" -I$SRC/src -I$SRC/include -I$SRC/include/rakupp"

  {
    echo "cxx = $cxx"
    echo "flags = $flags"
    echo "rule cc"
    echo "  command = \$cxx \$flags -MMD -MF \$out.d -c \$in -o \$out"
    echo "  depfile = \$out.d"
    echo "  deps = gcc"
    echo "  description = [$name] \$in"
    echo "rule link"
    echo "  command = \$cxx -target $target -isysroot $sysroot -dynamiclib \$in -o \$out" \
         "-install_name @rpath/RakuEngine.framework/RakuEngine -liconv -Wl,-dead_strip" \
         "-compatibility_version 1 -current_version 1"
    echo "  description = [$name] link"
    local objs=()
    for s in "${SOURCES[@]}"; do
      local o="obj/${s//\//_}.o"
      echo "build $o: cc $SRC/$s"
      objs+=("$o")
    done
    echo "build obj/rakupp_mobile.o: cc $dir/rakupp_mobile.cpp"
    objs+=("obj/rakupp_mobile.o")
    echo "build RakuEngine: link ${objs[*]}"
    echo "default RakuEngine"
  } > "$dir/build.ninja"

  echo "==> compiling $name (${#SOURCES[@]} units, $JOBS at a time)"
  ninja -C "$dir" -j "$JOBS"

  # Wrap the dylib as a framework: an app may embed dynamic libraries only in
  # that form, and App Store validation reads MinimumOSVersion from it.
  local fw="$dir/RakuEngine.framework"
  rm -rf "$fw"; mkdir -p "$fw/Headers"
  cp "$dir/RakuEngine" "$fw/RakuEngine"
  if [[ "$sdk" == iphoneos ]]; then
    rm -rf "$dir/RakuEngine.framework.dSYM"
    dsymutil "$dir/RakuEngine" -o "$dir/RakuEngine.framework.dSYM"
  fi
  strip -x "$fw/RakuEngine"
  cp "$ENGINE_DIR/rakupp_mobile.h" "$fw/Headers/"
  cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>RakuEngine</string>
  <key>CFBundleIdentifier</key><string>online.deepsoft.RakuEngine</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>RakuEngine</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
  <key>MinimumOSVersion</key><string>$MIN_IOS</string>
</dict>
</plist>
PLIST
}

build_slice ios-arm64            iphoneos        "arm64-apple-ios$MIN_IOS"            iPhoneOS
build_slice ios-arm64-simulator  iphonesimulator "arm64-apple-ios$MIN_IOS-simulator"  iPhoneSimulator
build_slice ios-x86_64-simulator iphonesimulator "x86_64-apple-ios$MIN_IOS-simulator" iPhoneSimulator

# One simulator framework holding both Mac architectures: a generic simulator
# build (flutter build ios --simulator) links x86_64 as well as arm64.
SIM="$BUILD/simulator/RakuEngine.framework"
rm -rf "$BUILD/simulator"; mkdir -p "$BUILD/simulator"
cp -R "$BUILD/ios-arm64-simulator/RakuEngine.framework" "$SIM"
lipo -create "$BUILD/ios-arm64-simulator/RakuEngine.framework/RakuEngine" \
             "$BUILD/ios-x86_64-simulator/RakuEngine.framework/RakuEngine" \
     -output "$SIM/RakuEngine"

echo "==> assembling $(basename "$OUT")"
rm -rf "$OUT"
xcodebuild -create-xcframework \
  -framework "$BUILD/ios-arm64/RakuEngine.framework" \
  -debug-symbols "$BUILD/ios-arm64/RakuEngine.framework.dSYM" \
  -framework "$SIM" \
  -output "$OUT" >/dev/null
echo "$REF" > "$OUT/../RakuEngine.version"
ls -lh "$BUILD"/ios-arm64/RakuEngine.framework/RakuEngine "$SIM/RakuEngine"
echo "==> done: $OUT"
