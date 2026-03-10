#!/bin/bash
set -euo pipefail

# Run all PoC files with both libtiff programs:
#   1) tiff_read_rgba_fuzzer
#   2) tiffcp
#
# Save per-case logs + TSV summaries that include:
# - ASan detected or not
# - bug type
# - READ/WRITE line
# - boundary distance (ASan "is located N bytes ...")
# - inferred OOB bytes (calculated from access size + bad addr + region)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="${1:-$SCRIPT_DIR/poc}"
LOG_DIR="${2:-/tmp/tiff_poc_both_logs}"

BIN_RGBA="${BIN_RGBA:-/users/hz3078/magma/targets/libtiff/out_fuzz_asan/tiff_read_rgba_fuzzer}"
BIN_TIFFCP="${BIN_TIFFCP:-/users/hz3078/magma/targets/libtiff/out_fuzz_asan/tiffcp}"

if [ ! -d "$POC_DIR" ]; then
  echo "[-] PoC directory not found: $POC_DIR"
  exit 1
fi
if [ ! -x "$BIN_RGBA" ]; then
  echo "[-] binary not executable: $BIN_RGBA"
  exit 1
fi
if [ ! -x "$BIN_TIFFCP" ]; then
  echo "[-] binary not executable: $BIN_TIFFCP"
  exit 1
fi

mkdir -p "$LOG_DIR"/{logs_rgba,logs_tiffcp,tmpout}

SUMMARY_LONG="$LOG_DIR/summary_long.tsv"
SUMMARY_WIDE="$LOG_DIR/summary_wide.tsv"

printf "id\tpoc_group\tfile\tprogram\trc\tasan_hit\tbug_type\taccess\taccess_size\tbad_addr\tregion_start\tregion_end\tboundary_distance\tside\toob_bytes\tsummary\tlog\n" > "$SUMMARY_LONG"
printf "id\tpoc_group\tfile\trgba_rc\trgba_asan\trgba_type\trgba_access\trgba_access_size\trgba_bad_addr\trgba_region_start\trgba_region_end\trgba_boundary_distance\trgba_side\trgba_oob_bytes\ttiffcp_rc\ttiffcp_asan\ttiffcp_type\ttiffcp_access\ttiffcp_access_size\ttiffcp_bad_addr\ttiffcp_region_start\ttiffcp_region_end\ttiffcp_boundary_distance\ttiffcp_side\ttiffcp_oob_bytes\n" > "$SUMMARY_WIDE"

extract_report() {
  local log="$1"
  local asan_hit="NO"
  local bug_type="-"
  local access="-"
  local access_size="-"
  local bad_addr="-"
  local region_start="-"
  local region_end="-"
  local boundary_distance="-"
  local side="-"
  local oob_bytes="-"
  local summary="-"

  if grep -q "ERROR: AddressSanitizer" "$log"; then
    asan_hit="YES"
    bug_type="$(grep -m1 "ERROR: AddressSanitizer:" "$log" | sed -E 's/.*AddressSanitizer: ([^ ]+).*/\1/' || true)"
    access="$(grep -m1 -E "READ of size|WRITE of size" "$log" | xargs || true)"
    summary="$(grep -m1 "SUMMARY: AddressSanitizer" "$log" | xargs || true)"

    if [ -n "$access" ]; then
      access_size="$(echo "$access" | sed -nE 's/.*(READ|WRITE) of size ([0-9]+) at (0x[0-9a-fA-F]+).*/\2/p')"
      bad_addr="$(echo "$access" | sed -nE 's/.*(READ|WRITE) of size ([0-9]+) at (0x[0-9a-fA-F]+).*/\3/p')"
      [ -z "$access_size" ] && access_size="-"
      [ -z "$bad_addr" ] && bad_addr="-"
    fi

    local loc_line
    loc_line="$(grep -m1 -E "is located [0-9]+ bytes to the (left|right) of [0-9]+-byte region \[0x[0-9a-fA-F]+,0x[0-9a-fA-F]+\)" "$log" || true)"
    if [ -n "$loc_line" ]; then
      boundary_distance="$(echo "$loc_line" | sed -nE 's/.*is located ([0-9]+) bytes to the (left|right) of.*/\1/p')"
      side="$(echo "$loc_line" | sed -nE 's/.*is located ([0-9]+) bytes to the (left|right) of.*/\2/p')"
      region_start="$(echo "$loc_line" | sed -nE 's/.*region \[(0x[0-9a-fA-F]+),(0x[0-9a-fA-F]+)\).*/\1/p')"
      region_end="$(echo "$loc_line" | sed -nE 's/.*region \[(0x[0-9a-fA-F]+),(0x[0-9a-fA-F]+)\).*/\2/p')"

      # infer OOB bytes for heap-buffer-overflow when fields are complete
      if [ "$bug_type" = "heap-buffer-overflow" ] && [ "$access_size" != "-" ] && [ "$bad_addr" != "-" ] \
         && [ "$region_start" != "-" ] && [ "$region_end" != "-" ]; then
        oob_bytes="$(python3 - <<PY
A=int("$bad_addr",16)
L=int("$region_start",16)
R=int("$region_end",16)
S=int("$access_size")
end=A+S
ov=max(0, min(end,R)-max(A,L))
print(S-ov)
PY
)"
      fi

      [ -z "$boundary_distance" ] && boundary_distance="-"
      [ -z "$side" ] && side="-"
      [ -z "$region_start" ] && region_start="-"
      [ -z "$region_end" ] && region_end="-"
      [ -z "$oob_bytes" ] && oob_bytes="-"
    fi
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$asan_hit" "$bug_type" "$access" "$access_size" "$bad_addr" "$region_start" "$region_end" "$boundary_distance" "$side" "$oob_bytes" "$summary"
}

count=0

while IFS= read -r -d '' f; do
  count=$((count + 1))
  rel="${f#"$POC_DIR"/}"
  poc_group="${rel%%/*}"
  if [ "$rel" = "$poc_group" ]; then
    poc_group="ROOT"
  fi

  base="$(basename "$f")"
  rid="$(printf '%06d' "$count")"

  log_rgba="$LOG_DIR/logs_rgba/${rid}_${base}.log"
  log_tiffcp="$LOG_DIR/logs_tiffcp/${rid}_${base}.log"
  out_tiffcp="$LOG_DIR/tmpout/${rid}_${base}.out"

  set +e
  ASAN_OPTIONS='abort_on_error=1:symbolize=1:detect_leaks=0' \
    "$BIN_RGBA" "$f" >"$log_rgba" 2>&1
  rc_rgba=$?
  set -e
  IFS=$'\t' read -r rgba_asan rgba_type rgba_access rgba_access_size rgba_bad_addr rgba_region_start rgba_region_end rgba_boundary_distance rgba_side rgba_oob rgba_summary < <(extract_report "$log_rgba")

  set +e
  ASAN_OPTIONS='abort_on_error=1:symbolize=1:detect_leaks=0' \
    "$BIN_TIFFCP" -M "$f" "$out_tiffcp" >"$log_tiffcp" 2>&1
  rc_tiffcp=$?
  set -e
  IFS=$'\t' read -r tiffcp_asan tiffcp_type tiffcp_access tiffcp_access_size tiffcp_bad_addr tiffcp_region_start tiffcp_region_end tiffcp_boundary_distance tiffcp_side tiffcp_oob tiffcp_summary < <(extract_report "$log_tiffcp")

  printf "%s\t%s\t%s\trgba\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$rid" "$poc_group" "$f" "$rc_rgba" "$rgba_asan" "$rgba_type" "$rgba_access" "$rgba_access_size" "$rgba_bad_addr" "$rgba_region_start" "$rgba_region_end" "$rgba_boundary_distance" "$rgba_side" "$rgba_oob" "$rgba_summary" "$log_rgba" >> "$SUMMARY_LONG"
  printf "%s\t%s\t%s\ttiffcp\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$rid" "$poc_group" "$f" "$rc_tiffcp" "$tiffcp_asan" "$tiffcp_type" "$tiffcp_access" "$tiffcp_access_size" "$tiffcp_bad_addr" "$tiffcp_region_start" "$tiffcp_region_end" "$tiffcp_boundary_distance" "$tiffcp_side" "$tiffcp_oob" "$tiffcp_summary" "$log_tiffcp" >> "$SUMMARY_LONG"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$rid" "$poc_group" "$f" \
    "$rc_rgba" "$rgba_asan" "$rgba_type" "$rgba_access" "$rgba_access_size" "$rgba_bad_addr" "$rgba_region_start" "$rgba_region_end" "$rgba_boundary_distance" "$rgba_side" "$rgba_oob" \
    "$rc_tiffcp" "$tiffcp_asan" "$tiffcp_type" "$tiffcp_access" "$tiffcp_access_size" "$tiffcp_bad_addr" "$tiffcp_region_start" "$tiffcp_region_end" "$tiffcp_boundary_distance" "$tiffcp_side" "$tiffcp_oob" >> "$SUMMARY_WIDE"
done < <(find "$POC_DIR" -type f -print0)

echo "[+] Done: $count files"
echo "[+] summary_long: $SUMMARY_LONG"
echo "[+] summary_wide: $SUMMARY_WIDE"
