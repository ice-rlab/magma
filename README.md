# Selected ASan PoVs for MAGMA v1.4

This branch is based on `origin/v1.3` and keeps a focused PoV set for two
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
- `libtiff_tiff_read_rgba_fuzzer/AAH016`: `11`
- `poppler_pdf_fuzzer/JCH201`: `2`

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
  selected-povs/asan_detected/poppler_pdf_fuzzer/JCH201/honggfuzz_poppler_pdf_fuzzer_JCH201.Wxd
```

## 5. MTE and NanoTag Evaluation

This branch also includes a local evaluation workflow under
[`mte-eval/`](mte-eval/) for testing the selected PoVs on a Pixel-class MTE
environment with three runtime modes:

- `none`: plain execution
- `baseline`: baseline MTE-enabled Scudo via `LD_PRELOAD`
- `nanotag`: NanoTag handler plus NanoTag Scudo via `LD_PRELOAD`

Build the local target runners:

```bash
cd /root/magma/mte-eval
INSTALL_DEPS=1 ./build_targets.sh
```

Run the full comparison:

```bash
cd /root/magma/mte-eval
./run_all_runtimes.sh
```

Reference material committed in this branch:

- [`mte-eval/README.md`](mte-eval/README.md)
- [`mte-eval/results/reference/none_summary.csv`](mte-eval/results/reference/none_summary.csv)
- [`mte-eval/results/reference/baseline_summary.csv`](mte-eval/results/reference/baseline_summary.csv)
- [`mte-eval/results/reference/nanotag_summary.csv`](mte-eval/results/reference/nanotag_summary.csv)
- [`mte-eval/results/reference/AAH010.x6L.nanotag.stdout`](mte-eval/results/reference/AAH010.x6L.nanotag.stdout)

Current reference summary:

- `none`: `56` total, `31` signal, `25` clean
- `baseline`: `56` total, `51` signal, `5` clean
- `nanotag`: `56` total, `53` detected, `3` clean

The strongest demonstration case in this branch is:

- `selected-povs/asan_detected/libtiff_tiff_read_rgba_fuzzer/AAH010/moptafl_libtiff_tiff_read_rgba_fuzzer_AAH010.x6L`

Observed behavior for `AAH010.x6L`:

- `none = clean`
- `baseline = clean`
- `nanotag = detected`

This is the clearest project-internal example of a baseline miss that NanoTag
reports.

## 6. Notes

- This branch intentionally does not include the broader MAGMA workflow. It is
  reduced to the two binaries and the PoVs that were confirmed to trip ASan.
- The build scripts under `targets/` only produce `tiff_read_rgba_fuzzer` and
  `pdf_fuzzer`.
- The `mte-eval/` directory contains a separate local workflow for runtime
  comparison on MTE-capable hardware; it is not part of upstream MAGMA.
