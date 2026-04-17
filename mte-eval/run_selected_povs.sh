#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MAGMA_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
OUT_ROOT="$SCRIPT_DIR/out"
RESULT_ROOT="$SCRIPT_DIR/results"
TARGETS="${TARGETS:-libtiff poppler}"
RUNTIME="${RUNTIME:-baseline}"
TIMEOUT_SEC="${TIMEOUT_SEC:-20}"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RUN_DIR="$RESULT_ROOT/${RUNTIME}_${STAMP}"

mkdir -p "$RUN_DIR"

runtime_env() {
  case "$RUNTIME" in
    none)
      echo ""
      ;;
    baseline)
      echo "LD_PRELOAD=/root/baseline-runtime/libscudo.so"
      ;;
    nanotag)
      echo "LD_PRELOAD=/root/mte-sanitizer-runtime/handler.so:/root/mte-sanitizer-runtime/libscudo.so"
      ;;
    *)
      echo "unknown runtime: $RUNTIME" >&2
      exit 1
      ;;
  esac
}

binary_for_target() {
  case "$1" in
    libtiff) echo "$OUT_ROOT/libtiff/tiff_read_rgba_fuzzer" ;;
    poppler) echo "$OUT_ROOT/poppler/pdf_fuzzer" ;;
    *)
      echo "unknown target: $1" >&2
      exit 1
      ;;
  esac
}

pov_dir_for_target() {
  case "$1" in
    libtiff) echo "$MAGMA_ROOT/selected-povs/asan_detected/libtiff_tiff_read_rgba_fuzzer" ;;
    poppler) echo "$MAGMA_ROOT/selected-povs/asan_detected/poppler_pdf_fuzzer" ;;
    *)
      echo "unknown target: $1" >&2
      exit 1
      ;;
  esac
}

detect_outcome() {
  local status="$1"
  local stdout_file="$2"
  local stderr_file="$3"

  if grep -Eq "Tag Mismatch Fault|Short Granule|Segmentation fault|core dumped" \
    "$stdout_file" "$stderr_file"; then
    echo "detected"
    return
  fi

  if [ "$status" -ge 128 ]; then
    echo "signal"
    return
  fi

  if [ "$status" -ne 0 ]; then
    echo "nonzero"
    return
  fi

  echo "clean"
}

run_case() {
  local env_prefix="$1"
  local bin="$2"
  local pov="$3"
  local stdout_file="$4"
  local stderr_file="$5"
  local quoted_bin
  local quoted_pov
  local cmd

  if [ "$RUNTIME" = "nanotag" ]; then
    printf -v quoted_bin '%q' "$bin"
    printf -v quoted_pov '%q' "$pov"
    if [ -n "$env_prefix" ]; then
      cmd="$env_prefix timeout $TIMEOUT_SEC $quoted_bin $quoted_pov"
    else
      cmd="timeout $TIMEOUT_SEC $quoted_bin $quoted_pov"
    fi
    script -qefc "$cmd" "$stdout_file" </dev/null >/dev/null 2>"$stderr_file"
  else
    if [ -n "$env_prefix" ]; then
      (
        env $env_prefix timeout "$TIMEOUT_SEC" "$bin" "$pov"
      ) >"$stdout_file" 2>"$stderr_file"
    else
      (
        timeout "$TIMEOUT_SEC" "$bin" "$pov"
      ) >"$stdout_file" 2>"$stderr_file"
    fi
  fi
}

signal_name() {
  local status="$1"

  if [ "$status" -lt 128 ]; then
    echo ""
    return
  fi

  case $((status - 128)) in
    1) echo "SIGHUP" ;;
    2) echo "SIGINT" ;;
    3) echo "SIGQUIT" ;;
    4) echo "SIGILL" ;;
    5) echo "SIGTRAP" ;;
    6) echo "SIGABRT" ;;
    7) echo "SIGBUS" ;;
    8) echo "SIGFPE" ;;
    9) echo "SIGKILL" ;;
    10) echo "SIGUSR1" ;;
    11) echo "SIGSEGV" ;;
    12) echo "SIGUSR2" ;;
    13) echo "SIGPIPE" ;;
    14) echo "SIGALRM" ;;
    15) echo "SIGTERM" ;;
    16) echo "SIGSTKFLT" ;;
    17) echo "SIGCHLD" ;;
    18) echo "SIGCONT" ;;
    19) echo "SIGSTOP" ;;
    20) echo "SIGTSTP" ;;
    21) echo "SIGTTIN" ;;
    22) echo "SIGTTOU" ;;
    23) echo "SIGURG" ;;
    24) echo "SIGXCPU" ;;
    25) echo "SIGXFSZ" ;;
    26) echo "SIGVTALRM" ;;
    27) echo "SIGPROF" ;;
    28) echo "SIGWINCH" ;;
    29) echo "SIGIO" ;;
    30) echo "SIGPWR" ;;
    31) echo "SIGSYS" ;;
    *) echo "SIG$((status - 128))" ;;
  esac
}

main() {
  local env_prefix
  env_prefix=$(runtime_env)
  local summary="$RUN_DIR/summary.csv"
  printf "target,pov,status,signal,outcome,stdout,stderr\n" >"$summary"

  for target in $TARGETS; do
    local bin
    local pov_dir
    bin=$(binary_for_target "$target")
    pov_dir=$(pov_dir_for_target "$target")

    if [ ! -x "$bin" ]; then
      echo "missing binary: $bin" >&2
      exit 1
    fi

    while IFS= read -r pov; do
      local rel
      local safe_name
      local stdout_file
      local stderr_file
      local status
      local sig_name
      local outcome

      rel=${pov#"$MAGMA_ROOT"/}
      safe_name=$(echo "$rel" | tr '/ ' '__')
      stdout_file="$RUN_DIR/${safe_name}.stdout"
      stderr_file="$RUN_DIR/${safe_name}.stderr"

      set +e
      run_case "$env_prefix" "$bin" "$pov" "$stdout_file" "$stderr_file"
      status=$?
      set -e

      sig_name=$(signal_name "$status")
      outcome=$(detect_outcome "$status" "$stdout_file" "$stderr_file")
      printf "%s,%s,%s,%s,%s,%s,%s\n" \
        "$target" "$rel" "$status" "$sig_name" "$outcome" "$stdout_file" "$stderr_file" \
        >>"$summary"
      printf "[%s][%s] %s -> status=%s signal=%s outcome=%s\n" \
        "$RUNTIME" "$target" "$rel" "$status" "${sig_name:-none}" "$outcome"
    done < <(find "$pov_dir" -type f | sort)
  done

  echo
  echo "Summary saved to: $summary"
}

main "$@"
