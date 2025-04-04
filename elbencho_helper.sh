#!/usr/bin/env bash

################################################################################
# Print usage/help information
################################################################################
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
  This script runs a custom Elbencho command with Grafana annotations support.
  It allows you to input your own elbencho command while maintaining the 
  Grafana integration functionality.

Options:
  --dryrun         Run in dry-run mode (no real writes or Grafana annotations).
  -h, --help       Show this help message and exit.

Environment Variables:
  GRAFANA_API_KEY  Grafana API key used for annotations. If unset, you will be 
                   prompted for it.

Example:
  # Example 1: Run with API key
  export GRAFANA_API_KEY="my-secret-key"
  ./$(basename "$0")

  # Example 2: Run without setting GRAFANA_API_KEY
  ./$(basename "$0")
EOF
}

echo "Welcome to the Elbencho Custom Command Wizard"
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

# Prompt for custom elbencho command
echo ""
echo "Enter your custom elbencho command."
echo "Example: elbencho /path/to/test --block 4k --threads 8 --write"
read -e -p "Command: " custom_command

# Prompt for run tag
read -e -p "Enter run tag (default: $(hostname)): " input_runtag
RUNTAG=${input_runtag:-$(hostname)}

# Add run description prompt
read -e -p "Enter a description for this run (optional): " run_description

read -e -p "Ready to Run? (y/n): " confirm
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

# Function to capture Grafana panels
capture_grafana_panels() {
    local dir="$1"
    local start_time="$2"
    local end_time="$3"

    local base_url="https://main-grafana-route-ai-grafana-main.apps.ocp01.pg.wwtatc.ai/render/d-solo"
    local auth_header="Authorization: Bearer $GRAFANA_API_KEY"
    local common_params="orgId=1&width=1000&height=500"

    echo "Debug: capture_grafana_panels received start_time=$start_time end_time=$end_time" > "$dir/debug.log"

    local panels=(
        "b0b3d0e4-081b-44e7-8571-9e2fba555655:5:read_iops"
        "b0b3d0e4-081b-44e7-8571-9e2fba555655:7:read_throughput"
        "b0b3d0e4-081b-44e7-8571-9e2fba555655:8:read_latency"
        "b0b3d0e4-081b-44e7-8571-9e2fba555655:22:write_iops"
        "b0b3d0e4-081b-44e7-8571-9e2fba555655:24:write_throughput"
        "b0b3d0e4-081b-44e7-8571-9e2fba555655:23:write_latency"
        "d0d26a47-41af-4d12-9e82-a939639239ee:4:total_max_power"
        "d0d26a47-41af-4d12-9e82-a939639239ee:2:power_metrics"
    )

    {
        echo "Capturing Grafana panel screenshots..."
        echo "Time window: from=$start_time to=$end_time"
        echo ""

        for panel in "${panels[@]}"; do
            IFS=: read -r dashboard_uid panel_id name <<< "$panel"
            local output_file="$dir/elbencho_${name}.png"
            local panel_url="$base_url/$dashboard_uid?panelId=$panel_id&$common_params&from=$start_time&to=$end_time"
            
            curl -s -H "$auth_header" "$panel_url" > "$output_file"
            echo "Captured $name panel"
        done

        echo "Screenshot capture complete"
    } | tee -a "$dir/elbencho.log"
}

# Run the test
run_timestamp=$(date +"%Y%m%d%H%M%S")
run_dir="${run_timestamp}"
log_file="${run_dir}/elbencho.log"
mkdir -p "$run_dir"

# Save run description if provided
if [ -n "$run_description" ]; then
    echo "$run_description" > "${run_dir}/run_description.txt"
fi

# Start annotation
if [[ "$DRYRUN" != true ]]; then
    send_grafana_annotation "run_start" "Custom command execution started"
fi

# Capture start time
precise_start=$(date +%s%N)
ELBENCHO_START_TIME=$(( (precise_start / 1000000000 - 5) * 1000 ))

{
    echo "=========================================="
    echo "Running custom command:"
    echo "$custom_command"
    echo "Start Time: $run_timestamp"
    echo "=========================================="

    # Add live CSV output options if not present
    if [[ ! "$custom_command" =~ "--livecsv" ]]; then
        custom_command="$custom_command --livecsv stdout --liveint 1000"
    fi

    # Execute command
    if [[ "$DRYRUN" == true ]]; then
        eval "$custom_command" 2>&1
    else
        eval "$custom_command | ~/elbencho_graphite/elbencho_graphite.sh -s \"$GRAPHITE_SERVER\" -t \"$RUNTAG\"" 2>&1
    fi

    echo ""
    echo "Test Completed"
    echo "----------------------------------------"
} | tee "$log_file"

# Capture end time
precise_end=$(date +%s%N)
ELBENCHO_END_TIME=$(( (precise_end / 1000000000 + 5) * 1000 ))

# Log timing information
echo "End Time (epoch): $precise_end" >> "$log_file"
echo "Duration (seconds): $(( (precise_end - precise_start) / 1000000000 ))" >> "$log_file"

if [[ "$DRYRUN" != true ]]; then
    capture_grafana_panels "$run_dir" "$ELBENCHO_START_TIME" "$ELBENCHO_END_TIME"
    send_grafana_annotation "run_complete" "Custom command execution completed"
fi

echo "Log file created: $log_file"