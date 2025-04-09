#!/bin/bash

NICS=("enp41s0f1np1" "enp170s0f1np1")

echo "=== RoCEv2 Tuning Verification ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo "----------------------------------"

for nic in "${NICS[@]}"; do
  dev=$(ibdev2netdev | grep -w "$nic" | awk '{print $1}')
  echo "NIC: $nic"
  echo "Device: ${dev:-Unknown}"

  # RoCE Mode
  roce_mode=$(cma_roce_mode -d "$dev" 2>/dev/null | head -n 1)
  echo "RoCE Mode: ${roce_mode:-Not available}"

  # ToS
  tos=$(cma_roce_tos -d "$dev" 2>/dev/null | head -n 1)
  echo "ToS: ${tos:-Not available}"

  # Trust DSCP
  trust=$(mlnx_qos -i "$nic" 2>/dev/null | grep -i "Trust state")
  echo "Trust: ${trust:-Not available}"

  # PFC Enabled Priorities from normal output
  pfc_enabled=$(mlnx_qos -i "$nic" 2>/dev/null | awk '/PFC configuration/,/buffer/' | grep "enabled")
  echo "PFC Enabled Priorities: ${pfc_enabled:-Not available}"

  # Data Center Quantized Congestion Notification AKA DCQCN
  rp=$(cat /sys/class/net/"$nic"/ecn/roce_rp/enable/3 2>/dev/null)
  np=$(cat /sys/class/net/"$nic"/ecn/roce_np/enable/3 2>/dev/null)
  echo "DCQCN ECN RP enabled (TC3): ${rp:-Not available}"
  echo "DCQCN ECN NP enabled (TC3): ${np:-Not available}"

  # Pause
  pause=$(ethtool -a "$nic" 2>/dev/null | grep -E "Auto|RX|TX")
  echo -e "Global Pause Settings:\n${pause:-Not available}"

  echo "----------------------------------"
done

