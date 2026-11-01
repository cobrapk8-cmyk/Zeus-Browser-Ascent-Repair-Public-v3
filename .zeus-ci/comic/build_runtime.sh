#!/usr/bin/env bash
set -euo pipefail
sdk=${1:-iphonesimulator}
root=$(cd "$(dirname "$0")/../.." && pwd)
root=$(cd "$root" && pwd)
output="$root/.zeus-ci/comic/build/$sdk"
mkdir -p "$output"
if [ ! -d "$root/.zeus-ci/comic/build/llama/.git" ]; then
  git clone --depth 1 --branch b5046 https://github.com/ggml-org/llama.cpp.git "$root/.zeus-ci/comic/build/llama"
fi
src="$root/.zeus-ci/comic/build/llama"
test "$(git -C "$src" rev-parse HEAD)" = 74d4f5b041ad837153b0e90fc864b8290e01d8d5
cmake -S "$src" -B "$output/cmake" -G Ninja \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=18.1 \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF \
  -DGGML_METAL=OFF -DGGML_OPENMP=OFF -DLLAMA_CURL=OFF -DGGML_NATIVE=OFF -DGGML_ACCELERATE=ON
cmake --build "$output/cmake" --target llama -j 3
if [ "$sdk" = iphonesimulator ]; then minimum=-mios-simulator-version-min=18.1; else minimum=-mios-version-min=18.1; fi
xcrun --sdk "$sdk" clang++ -std=c++17 -arch arm64 -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" \
  "$minimum" -I"$src/include" -I"$src/ggml/include" \
  -c "$root/Native/ComicRuntime/ZeusComicRuntime.cpp" -o "$output/wrapper.o"
common=(-G Ninja -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=18.1 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF)
for spec in "jpeg https://github.com/libjpeg-turbo/libjpeg-turbo.git 3.1.0" "png https://github.com/pnggroup/libpng.git v1.6.47" "webp https://github.com/webmproject/libwebp.git v1.5.0"; do
  read -r name repository version <<< "$spec"
  source_path="$root/.zeus-ci/comic/build/$name"
  if [ ! -d "$source_path/.git" ]; then git clone --depth 1 --branch "$version" "$repository" "$source_path"; fi
  case "$name" in
    jpeg) flags=(-DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF -DWITH_SIMD=OFF) ;;
    png) flags=(-DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DZLIB_LIBRARY="$(xcrun --sdk "$sdk" --show-sdk-path)/usr/lib/libz.tbd" -DZLIB_INCLUDE_DIR="$(xcrun --sdk "$sdk" --show-sdk-path)/usr/include") ;;
    webp) flags=(-DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF) ;;
  esac
  cmake -S "$source_path" -B "$output/$name" "${common[@]}" "${flags[@]}"
  cmake --build "$output/$name" -j 3
 done
xcrun --sdk "$sdk" clang++ -std=c++17 -arch arm64 -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" "$minimum" \
  -I"$root/.zeus-ci/comic/build/jpeg/src" -I"$root/.zeus-ci/comic/build/jpeg" -I"$output/jpeg" -I"$root/.zeus-ci/comic/build/png" -I"$output/png" -I"$root/.zeus-ci/comic/build/webp/src" \
  -c "$root/Native/ComicRuntime/ComicRegionDecoder.cpp" -o "$output/decoder.o"
python3 - "$output" <<'PY'
import pathlib,subprocess,sys
out=pathlib.Path(sys.argv[1]); libraries=sorted(out.joinpath('cmake').rglob('*.a'))
for folder in ['jpeg','png','webp']: libraries += sorted(out.joinpath(folder).rglob('*.a'))
assert libraries
subprocess.run(['xcrun','libtool','-static','-o',str(out/'libzeuscomic.a'),str(out/'wrapper.o'),str(out/'decoder.o'),*map(str,libraries)],check=True)
PY
