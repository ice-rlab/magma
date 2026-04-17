#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MAGMA_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
WORK_ROOT="$SCRIPT_DIR/work"
OUT_ROOT="$SCRIPT_DIR/out"
LOG_ROOT="$SCRIPT_DIR/logs"
TARGETS="${TARGETS:-libtiff poppler}"
INSTALL_DEPS="${INSTALL_DEPS:-0}"
CC_BIN="${CC_BIN:-clang}"
CXX_BIN="${CXX_BIN:-clang++}"
COMMON_FLAGS="${COMMON_FLAGS:--O1 -g -fno-omit-frame-pointer -march=armv8.5-a+memtag}"
JOBS="${JOBS:-$(nproc)}"

mkdir -p "$WORK_ROOT" "$OUT_ROOT" "$LOG_ROOT"

install_deps() {
  apt-get update
  apt-get install -y \
    git make autoconf automake libtool pkg-config cmake nasm patch wget \
    zlib1g-dev liblzma-dev libjpeg-turbo8-dev libjpeg-dev \
    libopenjp2-7-dev libpng-dev libcairo2-dev libtiff-dev liblcms2-dev \
    libboost-dev
}

clone_if_missing() {
  local url="$1"
  local rev="$2"
  local dst="$3"

  if [ ! -d "$dst/.git" ]; then
    git clone --no-checkout "$url" "$dst"
  fi
  git -C "$dst" fetch --all --tags
  git -C "$dst" checkout -f "$rev"
  git -C "$dst" clean -fdx
}

apply_magma_patches() {
  local target_name="$1"
  local target_root="$MAGMA_ROOT/targets/$target_name"
  local repo_root="$WORK_ROOT/$target_name/repo"
  local patch

  while IFS= read -r patch; do
    echo "Applying $patch"
    local name=${patch##*/}
    name=${name%.patch}
    sed "s/%MAGMA_BUG%/$name/g" "$patch" | patch -p1 -d "$repo_root"
  done < <(find "$target_root/patches/setup" "$target_root/patches/bugs" -name "*.patch" | sort)
}

fetch_libtiff() {
  local dst="$WORK_ROOT/libtiff/repo"
  clone_if_missing "https://gitlab.com/libtiff/libtiff.git" \
    "c145a6c14978f73bb484c955eb9f84203efcb12e" "$dst"

  cp "$MAGMA_ROOT/targets/libtiff/src/tiff_read_rgba_fuzzer.cc" \
    "$dst/contrib/oss-fuzz/tiff_read_rgba_fuzzer.cc"
  apply_magma_patches "libtiff"
}

fetch_poppler() {
  local repo_dst="$WORK_ROOT/poppler/repo"
  local ft_dst="$WORK_ROOT/poppler/freetype2"

  clone_if_missing "https://gitlab.freedesktop.org/poppler/poppler.git" \
    "1d23101ccebe14261c6afc024ea14f29d209e760" "$repo_dst"
  clone_if_missing "https://gitlab.freedesktop.org/freetype/freetype.git" \
    "50d0033f7ee600c5f5831b28877353769d1f7d48" "$ft_dst"

  apply_magma_patches "poppler"
}

build_libtiff() {
  local target_root="$WORK_ROOT/libtiff"
  local repo_root="$target_root/repo"
  local work_dir="$target_root/work"
  local out_dir="$OUT_ROOT/libtiff"

  rm -rf "$work_dir" "$out_dir"
  mkdir -p "$work_dir/lib" "$work_dir/include" "$out_dir"

  pushd "$repo_root" >/dev/null
  if [ -x ./autogen.sh ]; then
    ./autogen.sh
  fi
  CC="$CC_BIN" CXX="$CXX_BIN" \
    CFLAGS="$COMMON_FLAGS" CXXFLAGS="$COMMON_FLAGS" LDFLAGS="$COMMON_FLAGS" \
    ./configure --disable-shared --prefix="$work_dir"
  make -j"$JOBS" clean
  make -j"$JOBS"
  make install

  "$CXX_BIN" $COMMON_FLAGS -std=c++17 -DSTANDALONE \
    -I"$work_dir/include" \
    "$SCRIPT_DIR/src/file_driver.cc" \
    contrib/oss-fuzz/tiff_read_rgba_fuzzer.cc \
    -o "$out_dir/tiff_read_rgba_fuzzer" \
    "$work_dir/lib/libtiffxx.a" "$work_dir/lib/libtiff.a" \
    -lz -ljpeg -ljbig -ldeflate -Wl,-Bstatic -llzma -Wl,-Bdynamic
  popd >/dev/null
}

build_poppler() {
  local target_root="$WORK_ROOT/poppler"
  local repo_root="$target_root/repo"
  local ft_root="$target_root/freetype2"
  local work_dir="$target_root/work"
  local poppler_build="$work_dir/poppler"
  local out_dir="$OUT_ROOT/poppler"
  local iconv_lib="/usr/lib/aarch64-linux-gnu/libc.so"

  rm -rf "$work_dir" "$out_dir"
  mkdir -p "$work_dir/lib" "$work_dir/include" "$poppler_build" "$out_dir"

  pushd "$ft_root" >/dev/null
  ./autogen.sh
  CC="$CC_BIN" CXX="$CXX_BIN" \
    CFLAGS="$COMMON_FLAGS" CXXFLAGS="$COMMON_FLAGS" LDFLAGS="$COMMON_FLAGS" \
    ./configure --prefix="$work_dir" --disable-shared --with-brotli=no \
      PKG_CONFIG_PATH="$work_dir/lib/pkgconfig"
  make -j"$JOBS" clean
  make -j"$JOBS"
  make install
  popd >/dev/null

  if [ ! -f "$iconv_lib" ]; then
    iconv_lib="/usr/lib/$(gcc -print-multiarch)/libc.so"
  fi

  pushd "$poppler_build" >/dev/null
  CC="$CC_BIN" CXX="$CXX_BIN" cmake "$repo_root" \
    -DCMAKE_C_COMPILER="$CC_BIN" \
    -DCMAKE_CXX_COMPILER="$CXX_BIN" \
    -DCMAKE_BUILD_TYPE=debug \
    -DCMAKE_C_FLAGS="$COMMON_FLAGS" \
    -DCMAKE_CXX_FLAGS="$COMMON_FLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$COMMON_FLAGS" \
    -DBUILD_SHARED_LIBS=OFF \
    -DFONT_CONFIGURATION=generic \
    -DBUILD_GTK_TESTS=OFF \
    -DBUILD_QT5_TESTS=OFF \
    -DBUILD_CPP_TESTS=OFF \
    -DENABLE_LIBPNG=ON \
    -DENABLE_LIBTIFF=ON \
    -DENABLE_LIBJPEG=ON \
    -DENABLE_SPLASH=ON \
    -DENABLE_UTILS=OFF \
    -DWITH_Cairo=ON \
    -DENABLE_CMS=none \
    -DENABLE_LIBCURL=OFF \
    -DENABLE_GLIB=OFF \
    -DENABLE_GOBJECT_INTROSPECTION=OFF \
    -DENABLE_QT5=OFF \
    -DWITH_NSS3=OFF \
    -DFREETYPE_INCLUDE_DIRS="$work_dir/include/freetype2" \
    -DFREETYPE_LIBRARY="$work_dir/lib/libfreetype.a" \
    -DICONV_LIBRARIES="$iconv_lib"
  make -j"$JOBS" poppler poppler-cpp

  "$CXX_BIN" $COMMON_FLAGS -std=c++17 \
    -I"$poppler_build/cpp" -I"$repo_root/cpp" \
    "$SCRIPT_DIR/src/file_driver.cc" \
    "$MAGMA_ROOT/targets/poppler/src/pdf_fuzzer.cc" \
    -o "$out_dir/pdf_fuzzer" \
    "$poppler_build/cpp/libpoppler-cpp.a" "$poppler_build/libpoppler.a" \
    "$work_dir/lib/libfreetype.a" \
    -ljpeg -lz -lopenjp2 -lpng -ltiff -llcms2 -lcairo -lfontconfig \
    -lexpat -lm -lpthread -pthread
  popd >/dev/null
}

main() {
  if [ "$INSTALL_DEPS" = "1" ]; then
    install_deps
  fi

  for target in $TARGETS; do
    case "$target" in
      libtiff)
        fetch_libtiff
        build_libtiff
        ;;
      poppler)
        fetch_poppler
        build_poppler
        ;;
      *)
        echo "unknown target: $target" >&2
        exit 1
        ;;
    esac
  done

  echo "Built binaries:"
  for target in $TARGETS; do
    find "$OUT_ROOT/$target" -maxdepth 1 -type f -print
  done
}

main "$@"
