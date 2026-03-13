# Selected PoVs

This directory contains only PoVs that satisfy both conditions below:

- they reproduce under the target executable of interest
- they trigger an ASan-detectable failure in that executable

Selection in this branch:

- `asan_detected/libtiff_tiff_read_rgba_fuzzer`: 54 PoVs
- `asan_detected/poppler_pdf_fuzzer`: 2 PoVs

The files are copied from the larger PoC collections into a dedicated folder to
avoid mixing them with the original corpus layout.
