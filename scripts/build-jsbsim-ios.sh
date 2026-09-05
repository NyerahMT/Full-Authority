#!/usr/bin/env bash
set -euo pipefail

SDK="${1:-iphonesimulator}"
case "$SDK" in
  iphoneos|iphonesimulator) ;;
  *) echo "usage: $0 [iphoneos|iphonesimulator]" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/ThirdParty/jsbsim"
BUILD="$ROOT/Build/JSBSim/$SDK/build"
OUT="$ROOT/Build/JSBSim/$SDK"

if [[ ! -f "$SOURCE/CMakeLists.txt" ]]; then
  echo "JSBSim submodule is missing. Run: git submodule update --init --recursive" >&2
  exit 1
fi

ARCH="arm64"
DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-18.0}"

cmake -S "$SOURCE" -B "$BUILD" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT="$SDK" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SKIP_INSTALL_RULES=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_DOCS=OFF \
  -DBUILD_PYTHON_MODULE=OFF \
  -DBUILD_JULIA_PACKAGE=OFF \
  -DBUILD_MATLAB_SFUNCTION=OFF \
  -DSYSTEM_EXPAT=OFF

cmake --build "$BUILD" --target libJSBSim --parallel "$(sysctl -n hw.logicalcpu)"

mkdir -p "$OUT/lib"
cp "$BUILD/src/libJSBSim.a" "$OUT/lib/libJSBSim.a"

echo "JSBSim ready: $OUT/lib/libJSBSim.a"
