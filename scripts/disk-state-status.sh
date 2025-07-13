#!/bin/bash

# Telegraf input.exec script to check disk power states
# This script checks all /dev/sd* devices using hdparm -C
# and outputs metrics in InfluxDB line protocol format

# Function to convert power state text to numeric value
get_power_state_value() {
    local state="$1"
    case "$state" in
        "active/idle") echo "1" ;;
        "standby") echo "0" ;;
        "sleeping") echo "2" ;;
        "unknown") echo "-1" ;;
        *) echo "-2" ;; # error state
    esac
}

# Function to check if device exists and is accessible
is_device_accessible() {
    local device="$1"
    [[ -b "$device" ]] && [[ -r "$device" ]]
}

# Get current timestamp in nanoseconds
timestamp=$(date +%s%N)

# Find all /dev/sd* devices
for device in /dev/sd*; do
    # Skip if device doesn't exist or is a partition (contains digits)
    if [[ ! -b "$device" ]] || [[ "$device" =~ [0-9]$ ]]; then
        continue
    fi
    
    # Extract device name (e.g., sda from /dev/sda)
    device_name=$(basename "$device")
    
    # Check if device is accessible
    if ! is_device_accessible "$device"; then
        # Output error state for inaccessible devices
        echo "disk_power_state,device=$device_name state_value=-3i,state=\"inaccessible\" $timestamp"
        continue
    fi
    
    # Get power state using hdparm
    power_output=$(hdparm -C "$device" 2>/dev/null)
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        # Extract power state from hdparm output
        power_state=$(echo "$power_output" | grep -oE "(active/idle|standby|sleeping|unknown)" | head -1)
        
        if [[ -n "$power_state" ]]; then
            # Convert state to numeric value
            state_value=$(get_power_state_value "$power_state")
            
            # Output metric in InfluxDB line protocol format
            echo "disk_power_state,device=$device_name state_value=${state_value}i,state=\"$power_state\" $timestamp"
        else
            # Could not parse power state
            echo "disk_power_state,device=$device_name state_value=-2i,state=\"parse_error\" $timestamp"
        fi
    else
        # hdparm command failed
        echo "disk_power_state,device=$device_name state_value=-2i,state=\"hdparm_error\" $timestamp"
    fi
done

# Also output a summary metric with total number of devices checked
device_count=$(ls /dev/sd* 2>/dev/null | grep -v '[0-9]$' | wc -l)
echo "disk_power_summary devices_total=${device_count}i $timestamp"
