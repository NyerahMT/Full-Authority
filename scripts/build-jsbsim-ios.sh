#!/usr/bin/env bash
set -euo pipefail

SDK="${1:-iphonesimulator}"
case "$SDK" in
  iphoneos|iphonesimulator) ;;
  *) echo "usage: $0 [iphoneos|iphonesimulator]" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="$ROOT/ThirdParty/jsbsim"
OUT="$ROOT/Build/JSBSim/$SDK"
SOURCE="$OUT/source"
BUILD="$OUT/build"

if [[ ! -f "$UPSTREAM/CMakeLists.txt" ]]; then
  echo "JSBSim submodule is missing. Run: git submodule update --init --recursive" >&2
  exit 1
fi

ARCH="arm64"
DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-18.0}"

# Keep the pinned upstream submodule pristine. CMake treats every executable as
# an app bundle when cross-compiling to iOS, so JSBSim's desktop CLI install rule
# needs a harmless BUNDLE destination even though we only build libJSBSim.
rm -rf "$SOURCE" "$BUILD"
mkdir -p "$SOURCE"
rsync -a --exclude='.git' "$UPSTREAM/" "$SOURCE/"
python3 - "$SOURCE/src/CMakeLists.txt" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = "install(TARGETS JSBSim RUNTIME DESTINATION bin COMPONENT runtime)"
new = "install(TARGETS JSBSim RUNTIME DESTINATION bin BUNDLE DESTINATION bin COMPONENT runtime)"
if old not in text:
    raise SystemExit("Expected JSBSim CLI install rule was not found")
path.write_text(text.replace(old, new, 1))
PY

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
  -DSYSTEM_EXPAT=OFF \
  -DSKBUILD=ON

cmake --build "$BUILD" --target libJSBSim --parallel "$(sysctl -n hw.logicalcpu)"

mkdir -p "$OUT/lib"
cp "$BUILD/src/libJSBSim.a" "$OUT/lib/libJSBSim.a"

echo "JSBSim ready: $OUT/lib/libJSBSim.a"
