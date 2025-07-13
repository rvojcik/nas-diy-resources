#!/bin/bash

# RAID Status Monitor Script for InfluxDB
# Monitors MDADM and ZFS RAID arrays and outputs status in InfluxDB line protocol format

check_mdadm() {
    if [ ! -f /proc/mdstat ]; then
        return
    fi
    
    # Parse /proc/mdstat for active arrays
    while IFS= read -r line; do
        if [[ $line =~ ^md[0-9]+ ]]; then
            array_name=$(echo "$line" | awk '{print $1}')
            status="HEALTHY"
            
            # Check for degraded arrays or failed drives
            if [[ $line =~ \[.*_.*\] ]] || [[ $line =~ degraded ]]; then
                status="PROBLEM"
            fi
            
            status_code=1
            if [ "$status" = "PROBLEM" ]; then
                status_code=0
            fi
            
            echo "raid_status,device=$array_name,type=mdadm status=\"$status\",status_code=$status_code"
        fi
    done < /proc/mdstat
}

check_zfs() {
    # Check if zpool command is available
    if ! command -v zpool >/dev/null 2>&1; then
        return
    fi
    
    # Get pool list
    pools=$(zpool list -H 2>/dev/null | awk '{print $1,$10}')
    
    if [ -z "$pools" ]; then
        return
    fi
    
    echo "$pools" | while read -r pool_name health; do
        if [ -n "$pool_name" ] && [ -n "$health" ]; then
            status="HEALTHY"
            if [ "$health" != "ONLINE" ]; then
                status="PROBLEM"
            fi
            
            status_code=1
            if [ "$status" = "PROBLEM" ]; then
                status_code=0
            fi
            
            echo "raid_status,device=$pool_name,type=zfs status=\"$status\",status_code=$status_code,health=\"$health\""
        fi
    done
}

main() {
    arrays_found=false
    
    # Check MDADM arrays
    mdadm_output=$(check_mdadm)
    if [ -n "$mdadm_output" ]; then
        echo "$mdadm_output"
        arrays_found=true
    fi
    
    # Check ZFS pools
    zfs_output=$(check_zfs)
    if [ -n "$zfs_output" ]; then
        echo "$zfs_output"
        arrays_found=true
    fi
    
    # If no arrays found, output general status
    if [ "$arrays_found" = false ]; then
        echo "raid_status,device=none,type=general status=\"HEALTHY\",status_code=1,message=\"No RAID arrays detected\""
    fi
}

main