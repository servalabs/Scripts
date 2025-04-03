#!/bin/bash
# support.sh - Optimized script for enabling remote access services

# Constants
LOG_FILE="/var/log/support.log"

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

log_info "Starting optimized support mode enable process."

# Function to enable and start services in parallel
enable_and_start_services() {
    local services=("$@")
    local pids=()
    
    # Process services in parallel without temporary scripts
    for service in "${services[@]}"; do
        (
            systemctl enable "$service" 2>/dev/null || true
            systemctl start "$service" 2>/dev/null || true
            echo "Processed: $service"
        ) &
        pids+=($!)
    done

    # Wait for all processes to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
}

# Define services to enable
SUPPORT_SERVICES=(
    "cloudflared"
    "cockpit"
    "cockpit.socket"
)

# Enable and start all support services in parallel
enable_and_start_services "${SUPPORT_SERVICES[@]}"

log_info "Support mode enable process completed."