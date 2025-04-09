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

  # PFC: Set known-safe config to reveal current state
  pfc_enabled=$(mlnx_qos -i "$nic" --pfc 0,0,0,1,0,0,0,0 2>/dev/null | grep -A1 "PFC configuration" | grep "enabled")
  echo "PFC Enabled Priorities: ${pfc_enabled:-Not available}"

  # DCQCN
  rp=$(cat /sys/class/net/"$nic"/ecn/roce_rp/enable/3 2>/dev/null)
  np=$(cat /sys/class/net/"$nic"/ecn/roce_np/enable/3 2>/dev/null)
  echo "DCQCN RP enabled (TC3): ${rp:-Not available}"
  echo "DCQCN NP enabled (TC3): ${np:-Not available}"

  # Pause
  pause=$(ethtool -a "$nic" 2>/dev/null | grep -E "Auto|RX|TX")
  echo -e "Global Pause Settings:\n${pause:-Not available}"

  echo "----------------------------------"
done
