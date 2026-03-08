#!/bin/bash
set -euo pipefail

# Batch-run tiff_read_rgba_fuzzer against all files in a PoC directory.
# Produces:
# 1) per-file raw logs
# 2) one TSV summary with ASan hit + inferred OOB bytes
# 3) grouped summaries by PoC bug-group folder and ASan bug type
#
# Usage:
#   ./run_poc_batch_rgba.sh [POC_DIR] [LOG_DIR]
#
# Examples:
#   ./run_poc_batch_rgba.sh ~/tiff_poc
#   BIN=/abs/path/tiff_read_rgba_fuzzer ./run_poc_batch_rgba.sh ~/tiff_poc /tmp/tiff_rgba_logs

POC_DIR="${1:-$HOME/tiff_poc}"
LOG_DIR="${2:-/tmp/tiff_poc_rgba_logs}"
BIN="${BIN:-/users/hz3078/magma/targets/libtiff/out_fuzz_asan/tiff_read_rgba_fuzzer}"

if [ ! -x "$BIN" ]; then
  echo "[-] fuzzer binary not found or not executable: $BIN"
  exit 1
fi

if [ ! -d "$POC_DIR" ]; then
  echo "[-] PoC directory not found: $POC_DIR"
  exit 1
fi

mkdir -p "$LOG_DIR"
SUMMARY="$LOG_DIR/summary.tsv"
GROUP_ROOT="$LOG_DIR/groups"
BY_POC_GROUP="$GROUP_ROOT/by_poc_group"
BY_ASAN_TYPE="$GROUP_ROOT/by_asan_type"
mkdir -p "$BY_POC_GROUP" "$BY_ASAN_TYPE"

printf "id\tpoc_group\tfile\trc\tasan_hit\tbug_type\taccess\taccess_size\tbad_addr\tregion_start\tregion_end\tboundary_distance\toverflow_side\toob_bytes\tsummary\tlog\n" > "$SUMMARY"

count=0
hits=0

while IFS= read -r -d '' f; do
  count=$((count + 1))
  log="$LOG_DIR/case_$(printf '%05d' "$count").log"
  rel="${f#"$POC_DIR"/}"
  poc_group="${rel%%/*}"
  if [ "$rel" = "$poc_group" ]; then
    poc_group="ROOT"
  fi

  set +e
  ASAN_OPTIONS='abort_on_error=1:symbolize=1:detect_leaks=0' \
    "$BIN" "$f" >"$log" 2>&1
  rc=$?
  set -e

  asan_hit="NO"
  bug_type="-"
  access="-"
  access_size="-"
  bad_addr="-"
  region_start="-"
  region_end="-"
  boundary_distance="-"
  overflow_side="-"
  oob_bytes="-"
  summary_line="-"

  if grep -q "ERROR: AddressSanitizer" "$log"; then
    asan_hit="YES"
    hits=$((hits + 1))

    bug_type="$(grep -m1 "ERROR: AddressSanitizer:" "$log" | sed -E 's/.*AddressSanitizer: ([^ ]+).*/\1/' || true)"
    access="$(grep -m1 -E "READ of size|WRITE of size" "$log" | xargs || true)"
    summary_line="$(grep -m1 "SUMMARY: AddressSanitizer" "$log" | xargs || true)"

    if [ -n "$access" ]; then
      access_size="$(echo "$access" | sed -nE 's/.*(READ|WRITE) of size ([0-9]+) at (0x[0-9a-fA-F]+).*/\2/p')"
      bad_addr="$(echo "$access" | sed -nE 's/.*(READ|WRITE) of size ([0-9]+) at (0x[0-9a-fA-F]+).*/\3/p')"
      [ -z "$access_size" ] && access_size="-"
      [ -z "$bad_addr" ] && bad_addr="-"
    fi

    loc_line="$(grep -m1 -E "is located [0-9]+ bytes to the (left|right) of [0-9]+-byte region \[0x[0-9a-fA-F]+,0x[0-9a-fA-F]+\)" "$log" || true)"
    if [ -n "$loc_line" ]; then
      boundary_distance="$(echo "$loc_line" | sed -E 's/.*is located ([0-9]+) bytes to the (left|right) of.*/\1/')"
      overflow_side="$(echo "$loc_line" | sed -E 's/.*is located ([0-9]+) bytes to the (left|right) of.*/\2/')"
      region_start="$(echo "$loc_line" | sed -nE 's/.*region \[(0x[0-9a-fA-F]+),(0x[0-9a-fA-F]+)\).*/\1/p')"
      region_end="$(echo "$loc_line" | sed -nE 's/.*region \[(0x[0-9a-fA-F]+),(0x[0-9a-fA-F]+)\).*/\2/p')"

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
    fi
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$count" "$poc_group" "$f" "$rc" "$asan_hit" "$bug_type" "$access" \
    "$access_size" "$bad_addr" "$region_start" "$region_end" "$boundary_distance" \
    "$overflow_side" "$oob_bytes" "$summary_line" "$log" >> "$SUMMARY"
done < <(find "$POC_DIR" -type f -print0)

# Split summary by PoC group (e.g. AAH009/AAH010/...)
{
  IFS= read -r header
  printf "%s\n" "$header"
  awk -F '\t' 'NR>1{print $2}' "$SUMMARY" | sort -u | while IFS= read -r g; do
    [ -z "$g" ] && continue
    out="$BY_POC_GROUP/${g}.tsv"
    printf "%s\n" "$header" > "$out"
    awk -F '\t' -v grp="$g" 'NR>1 && $2==grp{print}' "$SUMMARY" >> "$out"
  done
} < "$SUMMARY"

# Split summary by ASan bug type (heap-buffer-overflow/use-after-free/NO_ASAN/...)
{
  IFS= read -r header
  printf "%s\n" "$header"
  awk -F '\t' 'NR>1{print ($5=="YES" ? $6 : "NO_ASAN")}' "$SUMMARY" | sort -u | while IFS= read -r t; do
    [ -z "$t" ] && continue
    safe_t="$(echo "$t" | tr '/[:space:]' '__')"
    out="$BY_ASAN_TYPE/${safe_t}.tsv"
    printf "%s\n" "$header" > "$out"
    awk -F '\t' -v typ="$t" 'NR>1{k=($5=="YES" ? $6 : "NO_ASAN"); if(k==typ) print}' "$SUMMARY" >> "$out"
  done
} < "$SUMMARY"

# One compact stats file by PoC group.
STATS="$GROUP_ROOT/stats_by_poc_group.tsv"
printf "poc_group\ttotal\tasan_hits\n" > "$STATS"
awk -F '\t' 'NR>1{total[$2]++; if($5=="YES") hit[$2]++} END{for (g in total) printf "%s\t%d\t%d\n", g, total[g], hit[g]+0}' \
  "$SUMMARY" | sort >> "$STATS"

echo "[+] Done. total=$count, asan_hits=$hits"
echo "[+] Summary: $SUMMARY"
echo "[+] Grouped summaries:"
echo "    - $BY_POC_GROUP"
echo "    - $BY_ASAN_TYPE"
echo "[+] Group stats: $STATS"
echo "[+] Quick view:"
column -ts $'\t' "$SUMMARY" | sed -n '1,40p'
