#!/usr/bin/env bash

################################################################################
# Print usage/help information
################################################################################
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
  This script runs the Elbencho Read Test Wizard, prompting the user for test
  parameters (threads, block sizes, etc.), optionally posting start/end 
  annotations to Grafana.

Options:
  --dryrun         Run in dry-run mode (no real writes or Grafana annotations).
  -h, --help       Show this help message and exit.

Environment Variables:
  GRAFANA_API_KEY  Grafana API key used for annotations. If unset, you will be 
                   prompted for it.

Example:
  # Example 1: Provide API key via environment variable, then run
  export GRAFANA_API_KEY="my-secret-key"
  ./$(basename "$0") --dryrun

  # Example 2: Run without setting GRAFANA_API_KEY, then script will prompt
  ./$(basename "$0") 
EOF
}

echo "Welcome to the Elbencho Read Test Wizard"
echo ""

# Check for --dryrun flag
DRYRUN=false
for arg in "$@"; do
  if [[ "$arg" == "--dryrun" ]]; then
    DRYRUN=true
  fi
done

# Prompt user for test parameters with default values
read -e -p "Enter thread values can be one value or multiples separated by a space (default: 8 16): " input_threads
THREAD_LIST=(${input_threads:-8 16})

read -e -p "Enter block sizes (default: 4k): " input_blocks
BLOCK_LIST=(${input_blocks:-"4k"})

read -e -p "Enter IO depth values (default: 1): " input_iodepth
IODEPTH_LIST=(${input_iodepth:-1})

read -e -p "Enter run tag (default: $(hostname)): " input_runtag
RUNTAG=${input_runtag:-$(hostname)}

read -e -p "Enter time limit in seconds (default: 120): " input_timelimit
TIMELIMIT=${input_timelimit:-120}

read -e -p "Enter size (default: 1276m): " input_size
SIZE=${input_size:-1276m}

read -e -p "Enter volume path (default: /lustre/exafs/client/perfvolumes/perfvolume{1..1024}): " input_volume
VOLUME_PATH="${input_volume:-/lustre/exafs/client/perfvolumes/perfvolume{1..1024}}"

read -e -p "Enter sleep time between runs in seconds (default: 120): " input_sleeptime
SLEEP_TIME=${input_sleeptime:-120}

read -e -p "Enter hosts (comma-separated e.g. dgx11380.atcai.local,dgx11381.atcai.local, default: blank): " input_hosts
HOSTS=$(echo "$input_hosts" | tr ' ' ',')

# Configuration
GRAPHITE_SERVER="graphite-main.pg.wwtatc.ai"

# Grafana annotation settings
GRAFANA_SERVER="https://main-grafana-route-ai-grafana-main.apps.ocp01.pg.wwtatc.ai"
DASHBOARD_IDS=(70 68 69 57)  # Elbencho-Peroutka, DGX-11380, DGX-11381, DDN-AI400

# Check if GRAFANA_API_KEY is set; if not, prompt for it
# Example to set before running the script: export GRAFANA_API_KEY='your-secret-key'
if [[ -z "$GRAFANA_API_KEY" ]]; then
  read -sp "Enter your Grafana API key to add annotations to Grafana: " input_key
  echo
  GRAFANA_API_KEY="$input_key"
fi

# Construct and display the full command for confirmation
EXAMPLE_CMD="elbencho \"$VOLUME_PATH\" \
--livecsv stdout \
--liveint 1000 \
--read \
--rand \
--direct \
--block ${BLOCK_LIST[0]} \
--size $SIZE \
--threads ${THREAD_LIST[0]} \
--iodepth ${IODEPTH_LIST[0]} \
--infloop \
--timelimit $TIMELIMIT"

if [[ -n "$HOSTS" ]]; then
    EXAMPLE_CMD+=" \
--hosts $HOSTS"
fi

if [[ "$DRYRUN" == true ]]; then
    EXAMPLE_CMD+=" \
--dryrun"
fi

FULL_CMD="$EXAMPLE_CMD | ~/elbencho_graphite/elbencho_graphite.sh -s \"$GRAPHITE_SERVER\" -t \"$RUNTAG\""

echo ""
echo "Please review the parameters for the first run cycle"
echo ""
echo "=========================================="
echo "Run Parameters:"
echo "  Threads:    ${THREAD_LIST[@]}"
echo "  Block Sizes: ${BLOCK_LIST[@]}"
echo "  IOdepth:    ${IODEPTH_LIST[@]}"
echo "  Runtag:     $RUNTAG"
echo "  Time Limit: $TIMELIMIT seconds"
echo "  Size:       $SIZE"
echo "  Volume Path: $VOLUME_PATH"
echo "  Sleep Time: $SLEEP_TIME seconds"
echo "  Hosts:      ${HOSTS:-None}"
echo "  Dry Run:    $DRYRUN"
echo ""
echo "  Example Command:"
echo "  $FULL_CMD"
echo "=========================================="
echo ""
read -e -p "Does this look correct? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Aborting."
    exit 1
fi

# Function to send Grafana annotations
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

for THREADS in "${THREAD_LIST[@]}"; do
  for BLOCK_SIZE in "${BLOCK_LIST[@]}"; do
    for IODEPTH in "${IODEPTH_LIST[@]}"; do
    
      # Start annotation
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

      # Construct and execute elbencho command
      ELBENCHO_CMD="elbencho \"$VOLUME_PATH\" \
--livecsv stdout \
--liveint 1000 \
--read \
--rand \
--direct \
--block $BLOCK_SIZE \
--size $SIZE \
--threads $THREADS \
--iodepth $IODEPTH \
--infloop \
--timelimit $TIMELIMIT"

      if [[ -n "$HOSTS" ]]; then
          ELBENCHO_CMD+=" \
--hosts $HOSTS"
      fi

      if [[ "$DRYRUN" == true ]]; then
          ELBENCHO_CMD+=" \
--dryrun"
      fi

      echo "Executing: $ELBENCHO_CMD"
      echo "Full Command: $ELBENCHO_CMD | ~/elbencho_graphite/elbencho_graphite.sh -s \"$GRAPHITE_SERVER\" -t \"$RUNTAG\""
    
      if [[ "$DRYRUN" == true ]]; then
          eval $ELBENCHO_CMD
      else
          eval $ELBENCHO_CMD | ~/elbencho_graphite/elbencho_graphite.sh -s "$GRAPHITE_SERVER" -t "$RUNTAG"
      fi
    
      # Completion annotation
      if [[ "$DRYRUN" != true ]]; then
          send_grafana_annotation "run_complete" "Threads: $THREADS Block: $BLOCK_SIZE IOdepth: $IODEPTH"
      fi
    
      # Optional delay between runs
      if [[ "$DRYRUN" != true ]]; then
          sleep $SLEEP_TIME
      fi
    done
  done
done
