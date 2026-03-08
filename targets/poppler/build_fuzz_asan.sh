#!/bin/bash
set -euo pipefail

##
# Build poppler target for AFL++ fuzzing with ASan enabled.
#
# Pre-requirements:
# - env TARGET: path to target work dir
# - env OUT: path to directory where artifacts are stored
# Optional:
# - env FUZZER: fuzzer directory (default: /users/hz3078/magma/fuzzers/afl)
# - env CC, CXX, AR, RANLIB
##

if [ ! -d "${TARGET:-}" ] || [ ! -d "$TARGET/repo" ]; then
    echo "TARGET/repo not found. Run fetch + patch first."
    exit 1
fi

export WORK="$TARGET/work"
rm -rf "$WORK"
mkdir -p "$WORK" "$WORK/lib" "$WORK/include"
mkdir -p "${OUT:?OUT is required}"

export FUZZER="${FUZZER:-/users/hz3078/magma/fuzzers/afl}"
export AFL_USE_ASAN="${AFL_USE_ASAN:-1}"
# Force AFL++ compiler wrappers to avoid inheriting stale gcc/g++ env vars.
export CC="afl-clang-fast"
export CXX="afl-clang-fast++"
export AR="${AR:-/usr/bin/ar}"
export RANLIB="${RANLIB:-/usr/bin/ranlib}"
ASAN_FLAGS="-fsanitize=address -fno-omit-frame-pointer"
export CFLAGS="${CFLAGS:-} -O1 -g ${ASAN_FLAGS}"
export CXXFLAGS="${CXXFLAGS:-} -O1 -g ${ASAN_FLAGS}"
export LDFLAGS="${LDFLAGS:-} ${ASAN_FLAGS}"
export LIBS="${LIBS:-} ${ASAN_FLAGS}"
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

pushd "$TARGET/freetype2"
./autogen.sh
./configure --prefix="$WORK" --disable-shared --with-brotli=no \
    PKG_CONFIG_PATH="$WORK/lib/pkgconfig"
make -j"$(nproc)" clean
make -j"$(nproc)"
make install
popd

mkdir -p "$WORK/poppler"
cd "$WORK/poppler"
rm -rf ./*

ICONV_LIB="/usr/lib/$(gcc -print-multiarch)/libc.so"
if [ ! -f "$ICONV_LIB" ]; then
    ICONV_LIB="/usr/lib/aarch64-linux-gnu/libc.so"
fi

cmake "$TARGET/repo" \
  -DCMAKE_AR="$AR" \
  -DCMAKE_RANLIB="$RANLIB" \
  -DCMAKE_BUILD_TYPE=debug \
  -DBUILD_SHARED_LIBS=OFF \
  -DFONT_CONFIGURATION=generic \
  -DBUILD_GTK_TESTS=OFF \
  -DBUILD_QT5_TESTS=OFF \
  -DBUILD_CPP_TESTS=OFF \
  -DENABLE_LIBPNG=ON \
  -DENABLE_LIBTIFF=ON \
  -DENABLE_LIBJPEG=ON \
  -DENABLE_SPLASH=ON \
  -DENABLE_UTILS=ON \
  -DWITH_Cairo=ON \
  -DENABLE_CMS=none \
  -DENABLE_LIBCURL=OFF \
  -DENABLE_GLIB=OFF \
  -DENABLE_GOBJECT_INTROSPECTION=OFF \
  -DENABLE_QT5=OFF \
  -DWITH_NSS3=OFF \
  -DFREETYPE_INCLUDE_DIRS="$WORK/include/freetype2" \
  -DFREETYPE_LIBRARY="$WORK/lib/libfreetype.a" \
  -DICONV_LIBRARIES="$ICONV_LIB"

make -j"$(nproc)" poppler poppler-cpp pdfimages pdftoppm
cp "$WORK/poppler/utils/"{pdfimages,pdftoppm} "$OUT/"

if [ ! -f "$FUZZER/src/afl_driver.o" ]; then
    "$CXX" $CXXFLAGS -std=c++11 -include cstdarg \
        -c "$FUZZER/src/afl_driver.cpp" -o "$FUZZER/src/afl_driver.o"
fi

AFL_RT="${AFL_RT:-/usr/local/lib/afl/afl-compiler-rt.o}"
if [ ! -f "$AFL_RT" ]; then
    AFL_RT="/usr/lib/afl/afl-compiler-rt.o"
fi
if [ ! -f "$AFL_RT" ]; then
    echo "AFL runtime object not found (afl-compiler-rt.o)."
    exit 1
fi

"$CXX" $CXXFLAGS -std=c++11 -I"$WORK/poppler/cpp" -I"$TARGET/repo/cpp" \
    "$TARGET/src/pdf_fuzzer.cc" -o "$OUT/pdf_fuzzer" \
    "$WORK/poppler/cpp/libpoppler-cpp.a" "$WORK/poppler/libpoppler.a" \
    "$WORK/lib/libfreetype.a" "$FUZZER/src/afl_driver.o" "$AFL_RT" $LDFLAGS $LIBS \
    -ljpeg -lz -lopenjp2 -lpng -ltiff -llcms2 -lm -lpthread -pthread

echo "Built:"
echo "  $OUT/pdf_fuzzer"
echo "  $OUT/pdfimages"
echo "  $OUT/pdftoppm"
