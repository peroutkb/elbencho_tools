#!/usr/bin/env bash

################################################################################
# Print usage/help information
################################################################################
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
  This script runs the Elbencho Test Wizard, allowing the user to perform
  both read and write tests, prompting for test parameters (threads, block sizes, etc.),
  and optionally posting start/end annotations to Grafana.

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

echo "Welcome to the Elbencho Test Wizard"
echo ""

# Check for --dryrun flag or --help flag
DRYRUN=false
for arg in "$@"; do
  if [[ "$arg" == "--dryrun" ]]; then
    DRYRUN=true
  elif [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    usage
    exit 0  
  fi

done

# Prompt user for test type
read -e -p "Select test type (read/write), default: read): " test_type
test_type=${test_type:-read}

# Prompt user for test parameters with default values
read -e -p "Enter thread values can be one value or multiples separated by a space (default: 224): " input_threads
THREAD_LIST=(${input_threads:-224})

read -e -p "Enter block sizes, can be one value or multiples separated by a space (default: 4k): " input_blocks
BLOCK_LIST=(${input_blocks:-"4k"})

read -e -p "Enter IO depth values (default: 1): " input_iodepth
IODEPTH_LIST=(${input_iodepth:-1})

read -e -p "Enter run tag (default: $(hostname)): " input_runtag
RUNTAG=${input_runtag:-$(hostname)}

read -e -p "Enter time limit in seconds (default: 120): " input_timelimit
TIMELIMIT=${input_timelimit:-120}

read -e -p "Enter size (default: 1276m): " input_size
SIZE=${input_size:-1276m}

read -e -p "Enable Random Offsets? (Default: yes): " enable_rand
enable_rand=${enable_rand:-yes}

read -e -p "Enter volume path (default: /lustre/exafs/client/perfvolumes/perfvolume{1..1024}): " input_volume
VOLUME_PATH=${input_volume:-'/lustre/exafs/client/perfvolumes/perfvolume{1..1024}'}

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
if [[ -z "$GRAFANA_API_KEY" ]]; then
  read -sp "Enter your Grafana API key to add annotations to Grafana: " input_key
  echo
  GRAFANA_API_KEY="$input_key"
fi

# Build command options function - can be reused
build_cmd_options() {
    local threads="$1"
    local block_size="$2"
    local iodepth="$3"
    local mode="$4"  # read or write

    local options=(
        --livecsv stdout
        --liveint 1000
        --$mode
        --direct
        --block "$block_size"
        --size "$SIZE"
        --threads "$threads"
        --iodepth "$iodepth"
        --infloop
        --timelimit "$TIMELIMIT"
    )

    # Add or remove the --rand option based on the user's input
    if [[ "$enable_rand" == "yes" ]]; then
        options+=(--rand)
    fi

    # Add hosts if specified
    [[ -n "$HOSTS" ]] && options+=(--hosts "$HOSTS")

    # Add dryrun if enabled
    [[ "$DRYRUN" == true ]] && options+=(--dryrun)

    echo "${options[*]}"
}

# Function to run elbencho test
run_elbencho_test() {
    local THREADS="$1"
    local BLOCK_SIZE="$2"
    local IODEPTH="$3"
    local MODE="$4"  # read or write

    # Build command options
    local cmd_options=$(build_cmd_options "$THREADS" "$BLOCK_SIZE" "$IODEPTH" "$MODE")

    # Construct the commands
    local elbencho_cmd="elbencho $VOLUME_PATH $cmd_options"
    local graphite_cmd="~/elbencho_graphite/elbencho_graphite.sh -s \"$GRAPHITE_SERVER\" -t \"$RUNTAG\""
    local full_cmd="$elbencho_cmd | $graphite_cmd"

    echo "Running $MODE test with the following command:"
    echo "$full_cmd"

    # Execute command and capture output
    if [[ "$DRYRUN" == true ]]; then
        eval "$elbencho_cmd" 2>&1
    else
        eval "$elbencho_cmd | $graphite_cmd" 2>&1
    fi
}

# Main execution loop
for THREADS in "${THREAD_LIST[@]}"; do
    for BLOCK_SIZE in "${BLOCK_LIST[@]}"; do
        for IODEPTH in "${IODEPTH_LIST[@]}"; do
            if [[ "$test_type" == "read" || "$test_type" == "both" ]]; then
                run_elbencho_test "$THREADS" "$BLOCK_SIZE" "$IODEPTH" "read"
            fi
            if [[ "$test_type" == "write" || "$test_type" == "both" ]]; then
                run_elbencho_test "$THREADS" "$BLOCK_SIZE" "$IODEPTH" "write"
            fi
        done
    done

done