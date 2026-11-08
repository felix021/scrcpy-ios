#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"
platform="${1:-macosx}"
case "$platform" in macosx|iphoneos|iphonesimulator) ;; *) echo 'Usage: scripts/build-crypto.sh [macosx|iphoneos|iphonesimulator]' >&2; exit 2 ;; esac
source_dir=$(python3 scripts/prepare-crypto.py)
output="build/boringssl/$platform"
revision="$(basename "$source_dir")-$(shasum -a 256 scripts/build-crypto.sh | cut -d ' ' -f 1)-$(xcrun --sdk "$platform" --show-sdk-version)"
if [ -f "$output/.complete" ] && [ "$(cat "$output/.complete")" = "$revision" ]; then exit 0; fi
args=("-DCMAKE_C_FLAGS=-ffile-prefix-map=$PWD=." "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=$PWD=." -DCMAKE_BUILD_TYPE=Release -DCMAKE_MACOSX_BUNDLE=OFF -DBUILD_TESTING=OFF -DCMAKE_OSX_SYSROOT="$platform" -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY)
if [ "$platform" = macosx ]; then
    args+=(-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DCMAKE_OSX_ARCHITECTURES="$(uname -m)")
else
    args+=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 -DCMAKE_OSX_ARCHITECTURES=arm64)
fi
cmake -S "$source_dir" -B "$output/objects" "${args[@]}"
cmake --build "$output/objects" --target crypto ssl --parallel 8
mkdir -p "$output/lib" build/boringssl/include
cp "$output/objects/libcrypto.a" "$output/objects/libssl.a" "$output/lib/"
cp -R "$source_dir/include/openssl" build/boringssl/include/
printf '%s\n' "$revision" > "$output/.complete"
