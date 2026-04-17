# Magma MTE Evaluation

This directory contains local scripts and experiment outputs for running the
selected MAGMA PoVs on this Pixel G3 environment under three runtime modes:

- `none`: plain execution
- `baseline`: baseline MTE-enabled Scudo via `LD_PRELOAD`
- `nanotag`: NanoTag handler plus NanoTag Scudo via `LD_PRELOAD`

The goal is not just to ask whether a PoV crashes, but to separate three
different situations:

1. PoVs that already crash in plain execution
2. PoVs that only change behavior once the baseline MTE runtime is injected
3. PoVs that the baseline runtime misses but NanoTag reports explicitly

## Purpose

This branch of MAGMA contains PoVs that were previously confirmed to trigger an
ASan-detectable bug under the selected target binary. That does not mean the
same PoV is silent in normal execution. Some PoVs still crash without any
sanitizer, while others only become observable with an MTE-aware allocator or
with NanoTag.

For this reason, the experiment here uses three-way comparison instead of
looking only at one runtime.

## Repository Layout

- `src/file_driver.cc`: standalone file-based entrypoint for the fuzz targets
- `src/check_mte_mode.c`: helper used to inspect process-level MTE state
- `src/launch_with_mte.c`: helper used to test explicit `prctl()`-based MTE enablement
- `build_targets.sh`: fetch, patch, and build local target runners
- `run_selected_povs.sh`: run a batch of PoVs under a single runtime
- `run_all_runtimes.sh`: run `none`, `baseline`, and `nanotag` in sequence
- `work/`: cloned and patched source trees
- `out/`: locally built binaries
- `results/`: saved logs and CSV summaries
- `results/reference/`: minimal committed summaries and showcase NanoTag logs

## Build

Build both targets and install dependencies if needed:

```bash
cd /root/magma/mte-eval
INSTALL_DEPS=1 ./build_targets.sh
```

This produces:

- `out/libtiff/tiff_read_rgba_fuzzer`
- `out/poppler/pdf_fuzzer`

## Run

Run one runtime:

```bash
cd /root/magma/mte-eval
RUNTIME=none ./run_selected_povs.sh
RUNTIME=baseline ./run_selected_povs.sh
RUNTIME=nanotag ./run_selected_povs.sh
```

Run all runtimes:

```bash
cd /root/magma/mte-eval
./run_all_runtimes.sh
```

Limit to one target:

```bash
cd /root/magma/mte-eval
TARGETS=libtiff ./run_all_runtimes.sh
```

## Runtime Definitions

`run_selected_povs.sh` maps each mode to the following execution setup:

- `none`: no preload
- `baseline`: `LD_PRELOAD=/root/baseline-runtime/libscudo.so`
- `nanotag`: `LD_PRELOAD=/root/mte-sanitizer-runtime/handler.so:/root/mte-sanitizer-runtime/libscudo.so`

## Important Notes

### 1. `none` Is Not "MTE Fully Active"

This machine has MTE-capable hardware, but a plain user process does not
automatically run with an MTE-aware allocation path. A helper probe in this
directory showed:

- hardware support is present
- plain processes do not start with tagged-address checking enabled by default

So `none` should be interpreted as plain execution on MTE-capable hardware, not
as "baseline MTE is already active".

### 2. "ASan-Detected" Does Not Mean "Plain Execution Must Be Clean"

The selected MAGMA PoVs were chosen because they reproduce and are observable
under an ASan build. That does not imply they are silent without ASan. Some of
them still trigger a plain crash (`SIGABRT`, `SIGSEGV`, `SIGBUS`) without any
debug allocator.

This is why the `none` run is necessary: it tells us which PoVs are already
unstable in plain execution and which ones are better candidates for comparing
runtime-assisted detection.

### 3. NanoTag Logging Requires a PTY

NanoTag's handler prints its fault report with `printf(...)` and then exits via
`_exit(...)`. If stdout is redirected to a regular file, the report can be lost
because stdio buffers are not flushed.

To avoid this, `run_selected_povs.sh` runs `nanotag` cases through
`script -qefc`, which gives NanoTag a PTY and preserves lines such as:

- `Tag Mismatch Fault (SYNC)`
- `Short Granule ...`

The saved NanoTag report therefore appears in the `.stdout` file for each case.

## Reference Results

The committed reference comparison is stored in:

- `results/reference/none_summary.csv`
- `results/reference/baseline_summary.csv`
- `results/reference/nanotag_summary.csv`

Summary:

- `none`: `56` total, `31` signal, `25` clean
- `baseline`: `56` total, `51` signal, `5` clean
- `nanotag`: `56` total, `53` detected, `3` clean

## Result Categories

### A. PoVs That Already Crash In `none`

There are `31` PoVs in this category.

These are not useful as the strongest baseline-vs-NanoTag demonstrations,
because plain execution is already unstable. They still matter operationally,
but they do not isolate the contribution of the runtime as cleanly.

### B. PoVs That Are Clean In `none`, Signal In `baseline`, And Are Reported By `nanotag`

There are `21` PoVs in this category.

Representative examples:

- `selected-povs/asan_detected/libtiff_tiff_read_rgba_fuzzer/AAH009/moptafl_libtiff_tiff_read_rgba_fuzzer_AAH009.Paf`
- `selected-povs/asan_detected/libtiff_tiff_read_rgba_fuzzer/AAH010/moptafl_libtiff_tiff_read_rgba_fuzzer_AAH010.5Aw`
- `selected-povs/asan_detected/libtiff_tiff_read_rgba_fuzzer/AAH010/moptafl_libtiff_tiff_read_rgba_fuzzer_AAH010.6xl`
- `selected-povs/asan_detected/libtiff_tiff_read_rgba_fuzzer/AAH016/moptafl_libtiff_tiff_read_rgba_fuzzer_AAH016.vqi`
- `selected-povs/asan_detected/poppler_pdf_fuzzer/JCH201/honggfuzz_poppler_pdf_fuzzer_JCH201.Wxd`

These are good candidates when the goal is to show that injecting an MTE-aware
runtime changes the behavior compared with plain execution.

### C. PoVs Missed By `baseline` But Detected By `nanotag`

There are `2` PoVs in this category:

1. `selected-povs/asan_detected/libtiff_tiff_read_rgba_fuzzer/AAH010/moptafl_libtiff_tiff_read_rgba_fuzzer_AAH010.kh9`
2. `selected-povs/asan_detected/libtiff_tiff_read_rgba_fuzzer/AAH010/moptafl_libtiff_tiff_read_rgba_fuzzer_AAH010.x6L`

This is the most important category for demonstrating NanoTag's added value
over the baseline MTE runtime.

## Recommended Showcase Case

The best single demonstration case in the current dataset is:

- `selected-povs/asan_detected/libtiff_tiff_read_rgba_fuzzer/AAH010/moptafl_libtiff_tiff_read_rgba_fuzzer_AAH010.x6L`

Observed behavior:

- `none = clean`
- `baseline = clean`
- `nanotag = detected`

This is the cleanest project-internal example of:

`baseline miss` + `nanotag hit`

Relevant files:

- `results/reference/nanotag_summary.csv`
- `results/reference/AAH010.x6L.nanotag.stdout`

The NanoTag output contains:

```text
Tag Mismatch Fault (SYNC)...
Short Granule. Permitted Bytes: 8, Short Granule Start Byte: 8
```

The other baseline miss, `AAH010.kh9`, is still useful, but it is weaker as a
headline example because:

- `none = SIGABRT`
- `baseline = clean`
- `nanotag = detected`

Its committed NanoTag log is:

- `results/reference/AAH010.kh9.nanotag.stdout`

## How To Read The Logs

For `none` and `baseline`, the most useful fields are:

- summary status
- summary signal
- saved `.stderr`

For `nanotag`, the most useful file is the saved `.stdout`, because the PTY
capture keeps the full handler report there.

Typical NanoTag evidence looks like:

```text
Tag Mismatch Fault (SYNC)...
Short Granule ...
```

## Current Takeaway

The current dataset does not support the statement "all baseline crashes are
definitely MTE detections", because many PoVs are already unstable in `none`.

It does support the stronger and cleaner project claim that:

- NanoTag reports the vast majority of the selected PoVs in this environment
- At least one PoV (`AAH010.x6L`) is clean in both `none` and `baseline`, but
  is explicitly reported by NanoTag

For project documentation and demos, `AAH010.x6L` should be the first case to
show.
