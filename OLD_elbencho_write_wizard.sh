#!/usr/bin/env bash

################################################################################
# Print usage/help information
################################################################################
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
  This script runs the Elbencho Write Test Wizard, prompting the user for test
  parameters (threads, block sizes, IO depth, etc.), optionally posting start/end
  annotations to Grafana.

Options:
  --dryrun         Run in dry-run mode (no actual write or annotation).
  -h, --help       Show this help message and exit.

Environment Variables:
  GRAFANA_API_KEY  Grafana API key used for annotations. If unset, you will be
                   prompted for it.

Examples:
  # Example 1: Provide API key via environment variable, then run in dry-run mode:
  export GRAFANA_API_KEY="my-secret-key"
  ./${0##*/} --dryrun

  # Example 2: Run normally, prompt for Grafana key if it's not set:
  ./${0##*/}

EOF
}

echo "Welcome to the Elbencho Write Test Wizard"
echo ""

###############################################################################
# ARGUMENT PARSING
###############################################################################
DRYRUN=false

for arg in "$@"; do
  case "$arg" in
    --dryrun)
      DRYRUN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      # Unrecognized arguments can be handled here if needed
      ;;
  esac
done

###############################################################################
# PROMPTS & DEFAULTS
###############################################################################
read -e -p "Enter thread values (default: 8 16 32 64 128 224 256): " input_threads
THREAD_LIST=(${input_threads:-8 16 32 64 128 224 256})

read -e -p "Enter block sizes (default: 4m): " input_blocks
BLOCK_LIST=(${input_blocks:-"4m"})

read -e -p "Enter IO depth values (default: 1): " input_iodepth
IODEPTH_LIST=(${input_iodepth:-1})

read -e -p "Enter run tag (default: $(hostname)): " input_runtag
RUNTAG=${input_runtag:-$(hostname)}

# Prompt for time limit. Leave blank to run until complete.
read -e -p "Enter time limit in seconds (leave blank for run to complete after writing the files): " input_timelimit
if [[ -n "$input_timelimit" ]]; then
    TIMELIMIT="$input_timelimit"
    TIME_OPTS="--infloop --timelimit $TIMELIMIT"
else
    TIME_OPTS=""
fi

read -e -p "Enter size (default: 1276m): " input_size
SIZE=${input_size:-1276m}

read -e -p "Enter volume path (default: /lustre/exafs/client/perfvolumes/perfvolume{1..1024}): " input_volume
VOLUME_PATH=${input_volume:-'/lustre/exafs/client/perfvolumes/perfvolume{1..1024}'}

read -e -p "Enter sleep time between runs in seconds (default: 120): " input_sleeptime
SLEEP_TIME=${input_sleeptime:-120}

read -e -p "Enter hosts (comma-separated e.g. dgx11380.atcai.local,dgx11381.atcai.local, default: blank): " input_hosts
HOSTS=$(echo "$input_hosts" | tr ' ' ',')

# New prompt for --delfiles option
read -e -p "Delete files after writing? (y/n, default: n): " input_delfiles
if [[ "$input_delfiles" == "y" || "$input_delfiles" == "Y" ]]; then
    DELFILES="--delfiles"
else
    DELFILES=""
fi

###############################################################################
# CONFIGURATION
###############################################################################
GRAPHITE_SERVER="graphite-main.pg.wwtatc.ai"
GRAFANA_SERVER="https://main-grafana-route-ai-grafana-main.apps.ocp01.pg.wwtatc.ai"
DASHBOARD_IDS=(70 68 69 57)  # Elbencho-Peroutka, DGX-11380, DGX-11381, DDN-AI400

# Check if GRAFANA_API_KEY is set; if not, prompt for it
if [[ -z "$GRAFANA_API_KEY" ]]; then
  read -sp "Enter your Grafana API key to add annotations to Grafana: " input_key
  echo
  GRAFANA_API_KEY="$input_key"
fi

################################################################################
# BUILD & DISPLAY EXAMPLE COMMAND
################################################################################
EXAMPLE_CMD="elbencho $VOLUME_PATH \
--livecsv stdout \
--liveint 1000 \
--lat \
--cpu \
--write \
--direct \
--block ${BLOCK_LIST[0]} \
--size $SIZE \
--threads ${THREAD_LIST[0]} \
--iodepth ${IODEPTH_LIST[0]}"

# Append time options if a time limit was provided
if [[ -n "$TIME_OPTS" ]]; then
    EXAMPLE_CMD+=" $TIME_OPTS"
fi

# Append delfiles option if chosen
if [[ -n "$DELFILES" ]]; then
    EXAMPLE_CMD+=" $DELFILES"
fi

if [[ -n "$HOSTS" ]]; then
    EXAMPLE_CMD+=" --hosts $HOSTS"
fi

if [[ "$DRYRUN" == true ]]; then
    EXAMPLE_CMD+=" --dryrun"
fi

FULL_CMD="$EXAMPLE_CMD | ~/elbencho_graphite/elbencho_graphite.sh -s \"$GRAPHITE_SERVER\" -t \"$RUNTAG\""

echo ""
echo "Please review the parameters for the first run cycle"
echo ""
echo "=========================================="
echo "Run Parameters:"
echo "  Threads:     ${THREAD_LIST[@]}"
echo "  Block Sizes: ${BLOCK_LIST[@]}"
echo "  IOdepth:     ${IODEPTH_LIST[@]}"
echo "  Runtag:      $RUNTAG"
echo "  Time Limit:  ${TIMELIMIT:-none}"
echo "  Size:        $SIZE"
echo "  Volume Path: $VOLUME_PATH"
echo "  Sleep Time:  $SLEEP_TIME seconds"
echo "  Hosts:       ${HOSTS:-None}"
echo "  Delfiles:    $([[ -n "$DELFILES" ]] && echo "Yes" || echo "No")"
echo "  Dry Run:     $DRYRUN"
echo ""
echo "Example Command:"
echo "  $FULL_CMD"
echo "=========================================="
echo ""
read -e -p "Does this look correct? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Aborting."
    exit 1
fi

################################################################################
# GRAFANA ANNOTATIONS
################################################################################
send_grafana_annotation() {
    local tag="$1"
    local text="$2"
    local timestamp=$(($(date +%s) * 1000))
    
    for DASHBOARD_ID in "${DASHBOARD_IDS[@]}"; do
        curl -s -X POST \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $GRAFANA_API_KEY" \
          -d "{\"dashboardId\": $DASHBOARD_ID, \"time\": $timestamp, \"isRegion\": false, \"tags\": [\"$tag\"], \"text\": \"$text\"}" \
          "$GRAFANA_SERVER/api/annotations"
    done
}

################################################################################
# MAIN TEST LOOP
################################################################################
for THREADS in "${THREAD_LIST[@]}"; do
  for BLOCK_SIZE in "${BLOCK_LIST[@]}"; do
    for IODEPTH in "${IODEPTH_LIST[@]}"; do
    
      # Start annotation (skip if dryrun)
      if [[ "$DRYRUN" != true ]]; then
          send_grafana_annotation "run_start" "Threads: $THREADS Block: $BLOCK_SIZE IOdepth: $IODEPTH"
      fi
    
      # Display run details
      echo "=========================================="
      echo "Running test with:"
      echo "  Threads:    $THREADS"
      echo "  Block Size: $BLOCK_SIZE"
      echo "  IOdepth:    $IODEPTH"
      echo "  Start Time: $(date +"%Y%m%d%H%M%S")"
      echo "=========================================="

      # Build actual elbencho command
      ELBENCHO_CMD="elbencho $VOLUME_PATH \
--livecsv stdout \
--liveint 1000 \
--lat \
--cpu \
--write \
--direct \
--block $BLOCK_SIZE \
--size $SIZE \
--threads $THREADS \
--iodepth $IODEPTH"

      # Add time limit options if present
      if [[ -n "$TIME_OPTS" ]]; then
        ELBENCHO_CMD+=" $TIME_OPTS"
      fi

      # Add delfiles if chosen
      if [[ -n "$DELFILES" ]]; then
        ELBENCHO_CMD+=" $DELFILES"
      fi

      # Append hosts if provided
      if [[ -n "$HOSTS" ]]; then
          ELBENCHO_CMD+=" --hosts $HOSTS"
      fi

      # Append dryrun if specified
      if [[ "$DRYRUN" == true ]]; then
          ELBENCHO_CMD+=" --dryrun"
      fi

      echo "Executing: $ELBENCHO_CMD"
      echo "Full Command: $ELBENCHO_CMD | ~/elbencho_graphite/elbencho_graphite.sh -s \"$GRAPHITE_SERVER\" -t \"$RUNTAG\""

      # Execute command
      if [[ "$DRYRUN" == true ]]; then
          eval "$ELBENCHO_CMD"
      else
          eval "$ELBENCHO_CMD" | ~/elbencho_graphite/elbencho_graphite.sh -s "$GRAPHITE_SERVER" -t "$RUNTAG"
      fi
    
      # Completion annotation
      if [[ "$DRYRUN" != true ]]; then
          send_grafana_annotation "run_complete" "Threads: $THREADS Block: $BLOCK_SIZE IOdepth: $IODEPTH"
      fi
    
      # Optional delay between runs
      if [[ "$DRYRUN" != true ]]; then
          sleep "$SLEEP_TIME"
      fi
    done
  done
done
