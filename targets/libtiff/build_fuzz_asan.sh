#!/bin/bash
set -euo pipefail

##
# Build libtiff target for AFL++ fuzzing with ASan enabled.
#
# Pre-requirements:
# - env TARGET: path to target work dir
# - env OUT: path to directory where artifacts are stored
# Optional:
# - env FUZZER: fuzzer directory (default: /users/hz3078/magma/fuzzers/afl)
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

cd "$TARGET/repo"
if [ -x ./autogen.sh ]; then
    set +e
    ./autogen.sh
    autogen_rc=$?
    set -e
    if [ $autogen_rc -ne 0 ]; then
        echo "autogen.sh failed (likely due offline config.guess fetch), falling back to existing configure."
    fi
fi
if [ ! -x ./configure ]; then
    echo "configure script missing."
    exit 1
fi
./configure --disable-shared --prefix="$WORK"
make -j"$(nproc)" clean
make -j"$(nproc)"
make install

cp "$WORK/bin/tiffcp" "$OUT/"

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

"$CXX" $CXXFLAGS -std=c++11 -I"$WORK/include" \
    "$TARGET/repo/contrib/oss-fuzz/tiff_read_rgba_fuzzer.cc" \
    -o "$OUT/tiff_read_rgba_fuzzer" \
    "$WORK/lib/libtiffxx.a" "$WORK/lib/libtiff.a" \
    "$FUZZER/src/afl_driver.o" "$AFL_RT" \
    -lz -ljpeg -ljbig -ldeflate -Wl,-Bstatic -llzma -Wl,-Bdynamic \
    $LDFLAGS $LIBS

echo "Built:"
echo "  $OUT/tiff_read_rgba_fuzzer"
echo "  $OUT/tiffcp"
