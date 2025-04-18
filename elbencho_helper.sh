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
echo "Enter your elbencho command."
echo "Example: elbencho /path/to/test --block 4k --threads 8 --write"
read -e -p "Command: " custom_command

# Prompt for run tag
read -e -p "Enter run tag (default: $(hostname)): " input_runtag
RUNTAG=${input_runtag:-$(hostname)}

# Add run description prompt
read -e -p "Enter a description for this run (optional): " run_description

# Add prompt for Grafana panel capture
read -e -p "Do you want to capture Grafana panels? (y/n, default: y): " capture_panels
capture_panels=${capture_panels:-y}

read -e -p "Ready to Run? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Aborting."
    exit 1
fi

# Initialize global variables for timing only if capturing panels
if [[ "$capture_panels" == "y" ]]; then
    ELBENCHO_START_TIME=""
    ELBENCHO_END_TIME=""
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
          "$GRAFANA_SERVER/api/annotations" >/dev/null
    done
}

# Function to capture Grafana panels
capture_grafana_panels() {
    local dir="$1"
    local start_time="$2"
    local end_time="$3"

    # Base URL for Grafana rendering
    local base_url="https://main-grafana-route-ai-grafana-main.apps.ocp01.pg.wwtatc.ai/render/d-solo"
    local auth_header="Authorization: Bearer $GRAFANA_API_KEY"
    local common_params="orgId=1&width=1000&height=750"

    # Panel configurations: dashboard UID, panel id, name, variables (optional)
    local panels=(
        "b0b3d0e4-081b-44e7-8571-9e2fba555655:5:elbencho_read_iops"
        "b0b3d0e4-081b-44e7-8571-9e2fba555655:7:elbencho_read_throughput"
        "b0b3d0e4-081b-44e7-8571-9e2fba555655:8:elbencho_read_latency"
        "b0b3d0e4-081b-44e7-8571-9e2fba555655:22:elbencho_write_iops"
        "b0b3d0e4-081b-44e7-8571-9e2fba555655:24:elbencho_write_throughput"
        "b0b3d0e4-081b-44e7-8571-9e2fba555655:23:elbencho_write_latency"
        "d0d26a47-41af-4d12-9e82-a939639239ee:2:ddn_power_metrics"
        "95:2:dgx11380_cpu_load"
        "95:10:dgx11380_ram_usage"
        "95:1193:dgx11380_infiniband_Gbps:var-infiniband=mlx5_8&var-infiniband=mlx5_2"
        "95:1195:dgx11380_infiniband_GBps:var-infiniband=mlx5_8&var-infiniband=mlx5_2"
        "95:1183:dgx11380_gpu_power_draw"
        "95:1184:dgx11380_gpu_utilization"
        "95:1185:dgx11380_gpu_mem_utilization"
        "96:2:dgx11381_cpu_load"
        "96:10:dgx11381_ram_usage"
        "96:1193:dgx11381_infiniband_Gbps:var-infiniband=mlx5_8&var-infiniband=mlx5_2"
        "96:1195:dgx11381_infiniband_GBps:var-infiniband=mlx5_8&var-infiniband=mlx5_2"
        "96:1183:dgx11381_gpu_power_draw"
        "96:1184:dgx11381_gpu_utilization"
        "96:1185:dgx11381_gpu_mem_utilization")
    {
        echo "----------------------------------------"
        echo "Capturing Grafana panel screenshots..."
        echo "Time window: from=$start_time to=$end_time"
        echo ""

        for panel in "${panels[@]}"; do
            IFS=: read -r dashboard_uid panel_id name variables <<< "$panel"
            local output_file="$dir/${name}.png"

            # Build the full URL for the panel, including variables if they exist
            local panel_url="$base_url/$dashboard_uid?panelId=$panel_id&$common_params&from=$start_time&to=$end_time"
            if [ -n "$variables" ]; then
                panel_url="$panel_url&$variables"
            fi

            echo "Panel: $name"
            echo "Command: curl -H \"$auth_header\" \"$panel_url\" > \"$output_file\""
            echo ""

            # Execute the curl command directly without eval
            curl -s -H "$auth_header" "$panel_url" > "$output_file"
        done

        echo "Screenshot capture complete"
        echo "----------------------------------------"
    } | tee -a "$dir/elbencho.log"
}

# Function to check if a directory is an NFS mount
is_nfs_mount() {
    local dir="$1"
    # Reverting to use mount command with grep
    mount | grep -q "on $dir type nfs"
}

# Determine the base directory for run_dir
base_dir="/mnt/aipg_elbencho_results"
if [[ -d "$base_dir" && $(is_nfs_mount "$base_dir") ]]; then
    echo "$base_dir is an NFS mount. Using it for run_dir."
else
    echo "$base_dir is not available or not an NFS mount. Falling back to /tmp."
    base_dir="/tmp"
fi

# Run directory setup
run_timestamp=$(date +"%Y%m%d%H%M%S")
run_dir="$base_dir/$run_timestamp"
log_file="$run_dir/elbencho.log"
mkdir -p "$run_dir"

# Save run description if provided
if [ -n "$run_description" ]; then
    echo "$run_description" > "${run_dir}/run_description.txt"
fi

# Start annotation and capture start time only if panels are being captured
if [[ "$DRYRUN" != true ]]; then
    send_grafana_annotation "run_start" "Custom command execution started"
    if [[ "$capture_panels" == "y" ]]; then
        precise_start=$(date +%s%N)
        ELBENCHO_START_TIME=$(( (precise_start / 1000000000 - 5) * 1000 ))
    fi
fi

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

# Capture end time and panels only if requested
if [[ "$DRYRUN" != true ]]; then
    if [[ "$capture_panels" == "y" ]]; then
        precise_end=$(date +%s%N)
        ELBENCHO_END_TIME=$(( (precise_end / 1000000000 + 5) * 1000 ))
        
        # Log timing information
        echo "End Time (epoch): $precise_end" >> "$log_file"
        echo "Duration (seconds): $(( (precise_end - precise_start) / 1000000000 ))" >> "$log_file"
        
        # Capture the panels
        capture_grafana_panels "$run_dir" "$ELBENCHO_START_TIME" "$ELBENCHO_END_TIME"
    fi
    send_grafana_annotation "run_complete" "Custom command execution completed"
fi

echo "Results Directory: $run_dir"