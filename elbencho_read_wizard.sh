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
VOLUME_PATH="${VOLUME_PATH%\}}"  # Remove any trailing brace if present

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

# Build initial command options for example
cmd_options=(
    --livecsv stdout
    --liveint 1000
    --read
    --rand
    --direct
    --block "${BLOCK_LIST[0]}"
    --size "$SIZE"
    --threads "${THREAD_LIST[0]}"
    --iodepth "${IODEPTH_LIST[0]}"
    --infloop
    --timelimit "$TIMELIMIT"
)

[[ -n "$HOSTS" ]] && cmd_options+=(--hosts "$HOSTS")
[[ "$DRYRUN" == true ]] && cmd_options+=(--dryrun)

# Construct example commands
EXAMPLE_CMD="elbencho $VOLUME_PATH ${cmd_options[*]}"
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
echo "  Volume Path: ${VOLUME_PATH}"
echo "  Sleep Time: $SLEEP_TIME seconds"
echo "  Hosts:      ${HOSTS:-None}"
echo "  Dry Run:    $DRYRUN"
echo ""
echo "  Example Command for first run cycle:"
echo "  $FULL_CMD"
echo "=========================================="
echo ""
read -e -p "Does this look correct? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Aborting."
    exit 1
fi

# Initialize global variables for timing
ELBENCHO_START_TIME=""
ELBENCHO_END_TIME=""

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
          "$GRAFANA_SERVER/api/annotations" >/dev/null
    done
}

# Function to capture Grafana panel screenshots
capture_grafana_panels() {
    local dir="$1"
    local start_time="$2"
    local end_time="$3"
    local base_url="https://main-grafana-route-ai-grafana-main.apps.ocp01.pg.wwtatc.ai/render/d-solo/b0b3d0e4-081b-44e7-8571-9e2fba555655"
    local auth_header="Authorization: Bearer $GRAFANA_API_KEY"
    local common_params="orgId=1&width=1000&height=500"

    # Debug time parameters - write to a separate debug file
    echo "Debug: capture_grafana_panels received start_time=$start_time end_time=$end_time" > "$dir/debug.log"
    echo "Debug: ELBENCHO_START_TIME=$ELBENCHO_START_TIME ELBENCHO_END_TIME=$ELBENCHO_END_TIME" >> "$dir/debug.log"

    # Panel configurations: id, name
    local panels=(
        "5:read_iops"
        "7:read_throughput"
        "8:read_latency"
        "22:write_iops"
        "24:write_throughput"
        "23:write_latency"
    )

    {
        echo "----------------------------------------"
        echo "Capturing Grafana panel screenshots..."
        echo "Time window: from=$start_time to=$end_time"
        echo ""
        
        for panel in "${panels[@]}"; do
            IFS=: read -r panel_id name <<< "$panel"
            local output_file="$dir/elbencho_${name}.png"
            
            # Explicitly build the curl command with the time parameters hardcoded
            echo "Panel: $name"
            echo "Command: curl -H \"$auth_header\" \"$base_url?panelId=$panel_id&$common_params&from=$start_time&to=$end_time\" > \"$output_file\""
            echo ""
            
            # Execute the curl command directly without eval
            curl -s -H "$auth_header" "$base_url?panelId=$panel_id&$common_params&from=$start_time&to=$end_time" > "$output_file"
        done
        
        echo "Screenshot capture complete"
        echo "----------------------------------------"
    } | tee -a "$dir/elbencho.log"
}

# Function to run elbencho test
run_elbencho_test() {
    local THREADS="$1"
    local BLOCK_SIZE="$2"
    local IODEPTH="$3"

    # Start annotation
    if [[ "$DRYRUN" != true ]]; then
        send_grafana_annotation "run_start" "Threads: $THREADS Block: $BLOCK_SIZE IOdepth: $IODEPTH"
    fi
    
    # Display run details
    local run_timestamp=$(date +"%Y%m%d%H%M%S")
    local run_dir="${run_timestamp}"
    local log_file="${run_dir}/elbencho.log"
    
    # Create directory for this run
    mkdir -p "$run_dir"
    
    # Start logging
    {
        echo "=========================================="
        echo "Running test with:"
        echo "  Threads:    $THREADS"
        echo "  Block Size: $BLOCK_SIZE"
        echo "  IOdepth:    $IODEPTH"
        echo "  Start Time: $run_timestamp"
        echo "=========================================="

        # Build command options
        local cmd_options=(
            --livecsv stdout
            --liveint 1000
            --read
            --rand
            --direct
            --block "$BLOCK_SIZE"
            --size "$SIZE"
            --threads "$THREADS"
            --iodepth "$IODEPTH"
            --infloop
            --timelimit "$TIMELIMIT"
        )

        [[ -n "$HOSTS" ]] && cmd_options+=(--hosts "$HOSTS")
        [[ "$DRYRUN" == true ]] && cmd_options+=(--dryrun)

        # Construct the commands
        local elbencho_cmd="elbencho $VOLUME_PATH ${cmd_options[*]}"
        local graphite_cmd="~/elbencho_graphite/elbencho_graphite.sh -s \"$GRAPHITE_SERVER\" -t \"$RUNTAG\""
        local full_cmd="$elbencho_cmd | $graphite_cmd"

        echo "Full Command With Graphite Output: $full_cmd"
        echo "----------------------------------------"
        
        # Capture start time with nanosecond precision and add a 5-second buffer before
        precise_start=$(date +%s%N)
        ELBENCHO_START_TIME=$(( (precise_start / 1000000000 - 5) * 1000 ))
        echo "----------------------------------------"
        echo "Start Time (epoch): $ELBENCHO_START_TIME"
        echo "----------------------------------------"
        echo "Test Output:"
        echo ""
        
        # Execute command and capture output
        if [[ "$DRYRUN" == true ]]; then
            eval "$elbencho_cmd" 2>&1
        else
            eval "$elbencho_cmd | $graphite_cmd" 2>&1
        fi
        
        echo ""
        echo "----------------------------------------"
        # Capture end time with nanosecond precision and add a 5-second buffer after
        precise_end=$(date +%s%N)
        ELBENCHO_END_TIME=$(( (precise_end / 1000000000 + 5) * 1000 ))
        echo "End Time (epoch): $ELBENCHO_END_TIME"
        echo "Duration (seconds): $(( (precise_end - precise_start) / 1000000000 ))"
        echo "Test Completed"
        echo "----------------------------------------"
    } | tee "$log_file"
    
    echo "Log file created: $log_file"
    
    # Handle post-run tasks only for non-dry runs
    if [[ "$DRYRUN" != true ]]; then
        # Capture Grafana panel screenshots with the buffered time window
        echo "Debug: About to call capture_grafana_panels with $ELBENCHO_START_TIME and $ELBENCHO_END_TIME" >> "$log_file"
        # Store the times in local variables to ensure they're passed correctly
        local grafana_start="$ELBENCHO_START_TIME"
        local grafana_end="$ELBENCHO_END_TIME"
        echo "Debug: Local variables: grafana_start=$grafana_start grafana_end=$grafana_end" >> "$log_file"
        # Call the function with the explicit parameters
        capture_grafana_panels "$run_dir" "$grafana_start" "$grafana_end"
        
        send_grafana_annotation "run_complete" "Threads: $THREADS Block: $BLOCK_SIZE IOdepth: $IODEPTH"
        sleep "$SLEEP_TIME"
    fi
}

# Main execution loop
for THREADS in "${THREAD_LIST[@]}"; do
    for BLOCK_SIZE in "${BLOCK_LIST[@]}"; do
        for IODEPTH in "${IODEPTH_LIST[@]}"; do
            run_elbencho_test "$THREADS" "$BLOCK_SIZE" "$IODEPTH"
        done
    done
done
