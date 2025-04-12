#!/bin/bash
# restore.sh - Service restoration script

# Constants
LOG_FILE="/var/log/restore.log"

# Logging functions
log() {
    local level="$1"; shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" >> "$LOG_FILE"
}
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# Verify root execution
if [ "$(id -u)" -ne 0 ]; then
    log_error "Script must be run as root"
    exit 1
fi

# Function to restore services
restore_services() {
    log_info "Restoring services"
    
    local services=(
        "tailscaled"           # Network first
        "syncthing"            # File sync
        "casaos-gateway.service"
    )
    
    for service in "${services[@]}"; do
        log_info "Processing service: $service"
        systemctl enable "$service" 2>/dev/null || log_warn "Failed to enable $service"
        systemctl start "$service" 2>/dev/null || log_error "Failed to start $service"
    done
}

# Main execution
log_info "Starting restore process"

# Restore services
restore_services

log_info "Restore process completed"