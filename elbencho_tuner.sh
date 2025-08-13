#!/usr/bin/env bash

# Simple elbencho parameter tuner wrapper
# - Sweeps threads, iodepth, and block size combinations
# - Calls your interactive elbencho_helper.sh non-interactively via here-doc
# - Encodes parameters into the run tag so you can compare in Grafana
#
# Usage:
#   chmod +x ./elbencho_tuner.sh
#   ./elbencho_tuner.sh
#
# Notes:
# - Requires elbencho_helper.sh in the same directory (or adjust HELPER path)
# - Set GRAFANA_API_KEY in the environment if you want annotations/panels
# - Set LOG_GRAFANA_TOKEN=true if you temporarily need the token printed in logs
# - To do a dry-run (no graphite/panels): set DRYRUN=true below

set -euo pipefail

# ----------- Configuration -----------
# Path or mount to test (edit this!)
TARGET_PATH="/mnt/your/volume/path"

# Operation mode
#   MODE: read|write
#   RANDOM_OPTS: optional elbencho randomization flags (leave empty if unsure)
#                 examples: "--random" or "--rand"
MODE="read"
RANDOM_OPTS=""

# Test duration per run (seconds)
DURATION=60

# Parameter grids
BLOCK_SIZES=(4k 16k 64k 1M)
THREADS=(4 8 16 32)
IODEPTHS=(1 2 4 8)

# Whether to capture Grafana panels for each run (y/n)
CAPTURE_PANELS="y"

# Optional: dry-run the helper (no graphite/panels) by passing --dryrun
DRYRUN=false

# Extra elbencho arguments (e.g., numfiles per thread, direct IO, etc.)
EXTRA_ARGS=""

# Path to helper
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER="$SCRIPT_DIR/elbencho_helper.sh"

# Validate helper exists
if [[ ! -x "$HELPER" ]]; then
  echo "ERROR: elbencho_helper.sh not found or not executable at: $HELPER" >&2
  exit 1
fi

# Resolve operation flags
op_flag="--read"
case "$MODE" in
  read)  op_flag="--read" ;;
  write) op_flag="--write" ;;
  *) echo "ERROR: MODE must be 'read' or 'write' (got '$MODE')" >&2; exit 1 ;;
 esac

# Show plan
echo "Running tuner with:" \
     "\n  TARGET_PATH=$TARGET_PATH" \
     "\n  MODE=$MODE  RANDOM_OPTS='$RANDOM_OPTS'  DURATION=${DURATION}s" \
     "\n  BLOCK_SIZES=${BLOCK_SIZES[*]}" \
     "\n  THREADS=${THREADS[*]}" \
     "\n  IODEPTHS=${IODEPTHS[*]}" \
     "\n  CAPTURE_PANELS=$CAPTURE_PANELS  DRYRUN=$DRYRUN" \
     "\n  EXTRA_ARGS='$EXTRA_ARGS'" | sed 's/^/  /'

# Host tag base
HOST_TAG=$(hostname)

# Loop over combinations
for bs in "${BLOCK_SIZES[@]}"; do
  for thr in "${THREADS[@]}"; do
    for qd in "${IODEPTHS[@]}"; do
      # Build elbencho command
      cmd=("elbencho" "$TARGET_PATH" "$op_flag" "--block" "$bs" "--threads" "$thr" "--iodepth" "$qd" "--time" "${DURATION}s")
      # Randomization (optional)
      if [[ -n "$RANDOM_OPTS" ]]; then
        # shellcheck disable=SC2206
        cmd=("${cmd[@]}" $RANDOM_OPTS)
      fi
      # Extra args (optional)
      if [[ -n "$EXTRA_ARGS" ]]; then
        # shellcheck disable=SC2206
        cmd=("${cmd[@]}" $EXTRA_ARGS)
      fi

      cmd_str="${cmd[*]}"
      run_tag="${HOST_TAG}-${MODE}${RANDOM_OPTS:+-rand}-bs${bs}_t${thr}_qd${qd}"
      run_desc="tuner sweep: mode=$MODE bs=$bs threads=$thr iodepth=$qd duration=${DURATION}s extra='$EXTRA_ARGS'"

      echo "\n========================================"
      echo "Launching: $cmd_str"
      echo "RunTag:   $run_tag"
      echo "Panels:   $CAPTURE_PANELS"
      echo "========================================\n"

      # Drive the interactive helper via here-doc
      if [[ "$DRYRUN" == true ]]; then
        "$HELPER" --dryrun <<EOF
$cmd_str
$run_tag
$run_desc
$CAPTURE_PANELS
y
EOF
      else
        "$HELPER" <<EOF
$cmd_str
$run_tag
$run_desc
$CAPTURE_PANELS
y
EOF
      fi

    done
  done
done

echo "\nTuner complete. Review run directories and Grafana panels."
