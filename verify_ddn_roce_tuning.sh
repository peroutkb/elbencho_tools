#!/bin/bash

# List your interfaces here
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
  roce_mode=$(cma_roce_mode -d "$dev" 2>/dev/null | grep -i "RoCE mode")
  echo "RoCE Mode: ${roce_mode:-Not available}"

  # ToS
  tos=$(cma_roce_tos -d "$dev" 2>/dev/null | grep -i "TOS")
  echo "ToS: ${tos:-Not available}"

  # Trust DSCP
  trust=$(mlnx_qos -i "$nic" 2>/dev/null | grep -i "Trust state")
  echo "Trust: ${trust:-Not available}"

  # PFC Config
  pfc_config=$(mlnx_qos -i "$nic" --show-pfc 2>/dev/null | grep -i "Priority Flow Control Configuration")
  pfc_priorities=$(mlnx_qos -i "$nic" --show-pfc 2>/dev/null | grep -i "PFC enabled priorities")
  echo "PFC: ${pfc_config:-Not available} | ${pfc_priorities:-Not available}"

  # DCQCN RP/NP
  rp=$(cat /sys/class/net/"$nic"/ecn/roce_rp/enable/3 2>/dev/null)
  np=$(cat /sys/class/net/"$nic"/ecn/roce_np/enable/3 2>/dev/null)
  echo "DCQCN RP enabled (TC3): ${rp:-Not available}"
  echo "DCQCN NP enabled (TC3): ${np:-Not available}"

  # Pause settings
  pause=$(ethtool -a "$nic" 2>/dev/null | grep -E "Auto|RX|TX")
  echo -e "Pause:\n${pause:-Not available}"

  echo "----------------------------------"
done
