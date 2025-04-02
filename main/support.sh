#!/bin/bash
# support.sh V4 - Enable remote access by re-enabling and starting Cloudflared, Cockpit, and Cockpit.socket

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

log_info "Starting support process: Enabling remote access services."

# Function to enable and start a service
enable_and_start_service() {
    local service="$1"
    if ! systemctl is-enabled --quiet "$service"; then
        if systemctl enable "$service"; then
            log_info "Enabled service: $service"
        else
            log_warn "Failed to enable service: $service"
        fi
    else
        log_info "Service $service is already enabled"
    fi

    if ! systemctl is-active --quiet "$service"; then
        if systemctl start "$service"; then
            log_info "Started service: $service"
        else
            log_warn "Failed to start service: $service"
        fi
    else
        log_info "Service $service is already running"
    fi
}

# Main execution
log_info "Starting support process"

# Enable and start Cloudflared
enable_and_start_service "cloudflared"

# Enable and start Cockpit
enable_and_start_service "cockpit"
enable_and_start_service "cockpit.socket"

log_info "Support process completed: Remote access enabled."