# Selected ASan PoVs for MAGMA v1.2

This branch is based on `origin/v1.2` and only keeps a focused PoV set for two
executables:

- `libtiff`: `tiff_read_rgba_fuzzer`
- `poppler`: `pdf_fuzzer`

The selected PoVs are stored under:

- `selected-povs/asan_detected/libtiff_tiff_read_rgba_fuzzer`
- `selected-povs/asan_detected/poppler_pdf_fuzzer`

PoV counts in this branch:

- `libtiff_tiff_read_rgba_fuzzer`: `54`
- `poppler_pdf_fuzzer`: `2`

Breakdown by directory:

- `libtiff_tiff_read_rgba_fuzzer/AAH009`: `6`
- `libtiff_tiff_read_rgba_fuzzer/AAH010`: `37`
- `libtiff_tiff_read_rgba_fuzzer/AAH016`: `5`
- `libtiff_tiff_read_rgba_fuzzer/New-pocs`: `6`
- `poppler_pdf_fuzzer/New-pocs`: `2`

These samples were filtered to satisfy both conditions:

- they reproduce under the target executable
- they trigger an ASan-detectable failure under that executable

![MAGMA PoC overview](magma_poc.png)

## 1. Dependencies

Install the target-specific packages:

```bash
bash targets/libtiff/preinstall.sh
bash targets/poppler/preinstall.sh
```

You also need AFL++ available in `PATH`, including:

- `afl-clang-fast`
- `afl-clang-fast++`

## 2. Fetch and patch sources

```bash
export MAGMA_ROOT=/path/to/magma
cd "$MAGMA_ROOT"
```

Fetch `libtiff`:

```bash
export TARGET="$MAGMA_ROOT/targets/libtiff"
bash "$TARGET/fetch.sh"
bash "$MAGMA_ROOT/magma/apply_patches.sh"
```

Fetch `poppler`:

```bash
export TARGET="$MAGMA_ROOT/targets/poppler"
bash "$TARGET/fetch.sh"
bash "$MAGMA_ROOT/magma/apply_patches.sh"
```

## 3. Build `tiff_read_rgba_fuzzer` with AFL++ and ASan

```bash
export TARGET="$MAGMA_ROOT/targets/libtiff"
mkdir -p "$TARGET/out_fuzz_asan"
OUT="$TARGET/out_fuzz_asan" TARGET="$TARGET" \
  bash "$TARGET/build_tiff_read_rgba_fuzzer_asan.sh"
```

Output:

- `targets/libtiff/out_fuzz_asan/tiff_read_rgba_fuzzer`

Run one selected PoV:

```bash
ASAN_OPTIONS='abort_on_error=1:symbolize=1:detect_leaks=0' \
  targets/libtiff/out_fuzz_asan/tiff_read_rgba_fuzzer \
  selected-povs/asan_detected/libtiff_tiff_read_rgba_fuzzer/AAH010/moptafl_libtiff_tiff_read_rgba_fuzzer_AAH010.x6L
```

## 4. Build `pdf_fuzzer` with AFL++ and ASan

```bash
export TARGET="$MAGMA_ROOT/targets/poppler"
mkdir -p "$TARGET/out_fuzz_asan"
OUT="$TARGET/out_fuzz_asan" TARGET="$TARGET" \
  bash "$TARGET/build_pdf_fuzzer_asan.sh"
```

Output:

- `targets/poppler/out_fuzz_asan/pdf_fuzzer`

Run one selected PoV:

```bash
ASAN_OPTIONS='abort_on_error=1:symbolize=1:detect_leaks=0' \
  targets/poppler/out_fuzz_asan/pdf_fuzzer \
  selected-povs/asan_detected/poppler_pdf_fuzzer/New-pocs/JCH201/honggfuzz_poppler_pdf_fuzzer_JCH201.Wxd
```

## 5. Notes

- This branch intentionally does not include the broader MAGMA workflow. It is
  reduced to the two binaries and the PoVs that were confirmed to trip ASan.
- The build scripts only produce `tiff_read_rgba_fuzzer` and `pdf_fuzzer`.
