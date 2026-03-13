#!/bin/bash
set -euo pipefail

##
# Build only libtiff's tiff_read_rgba_fuzzer with AFL++ and ASan.
#
# Pre-requirements:
# - env TARGET: path to target work dir
# - env OUT: path to directory where artifacts are stored
##

if [ ! -d "${TARGET:-}" ] || [ ! -d "$TARGET/repo" ]; then
    echo "TARGET/repo not found. Run fetch.sh first."
    exit 1
fi

export FUZZER="${FUZZER:-/users/hz3078/magma/fuzzers/afl}"
export WORK="$TARGET/work"
export AFL_USE_ASAN="${AFL_USE_ASAN:-1}"
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

rm -rf "$WORK"
mkdir -p "$WORK" "$WORK/lib" "$WORK/include"
mkdir -p "${OUT:?OUT is required}"

cd "$TARGET/repo"
if [ -x ./autogen.sh ]; then
    ./autogen.sh
fi
./configure --disable-shared --prefix="$WORK"
make -j"$(nproc)" clean
make -j"$(nproc)"
make install

"$CXX" $CXXFLAGS -std=c++11 -I"$WORK/include" \
    contrib/oss-fuzz/tiff_read_rgba_fuzzer.cc -o "$OUT/tiff_read_rgba_fuzzer" \
    "$WORK/lib/libtiffxx.a" "$WORK/lib/libtiff.a" \
    -lz -ljpeg -ljbig -ldeflate -Wl,-Bstatic -llzma -Wl,-Bdynamic \
    $LDFLAGS $LIBS

echo "Built:"
echo "  $OUT/tiff_read_rgba_fuzzer"
