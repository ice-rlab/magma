#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RUNTIMES="${RUNTIMES:-none baseline nanotag}"
TARGETS="${TARGETS:-libtiff poppler}"
TIMEOUT_SEC="${TIMEOUT_SEC:-20}"

for runtime in $RUNTIMES; do
  echo "============================================================"
  echo "Running runtime=$runtime targets=$TARGETS timeout=${TIMEOUT_SEC}s"
  echo "============================================================"
  RUNTIME="$runtime" TARGETS="$TARGETS" TIMEOUT_SEC="$TIMEOUT_SEC" \
    "$SCRIPT_DIR/run_selected_povs.sh"
  echo
done
