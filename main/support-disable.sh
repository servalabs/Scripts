#!/bin/bash
# support-disable.sh - Optimized script for disabling remote access services

# Constants
LOG_FILE="/var/log/support-disable.log"

# Logging functions:
log() {
    local level="$1"; shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" >> "$LOG_FILE"
}
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# Ensure the script is run as root:
if [ "$(id -u)" -ne 0 ]; then
    log_error "Script must be run as root."
    exit 1
fi

log_info "Starting optimized support mode disable process."

# Function to stop and disable services in parallel
stop_and_disable_services() {
    local services=("$@")
    local pids=()
    
    # Process services in parallel without temporary scripts
    for service in "${services[@]}"; do
        (
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
            echo "Processed: $service"
        ) &
        pids+=($!)
    done

    # Wait for all processes to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
}

# Define services to disable
SUPPORT_SERVICES=(
    "cloudflared"
    "cockpit"
    "cockpit.socket"
)

# Stop and disable all support services in parallel
stop_and_disable_services "${SUPPORT_SERVICES[@]}"

log_info "Support mode disable process completed."