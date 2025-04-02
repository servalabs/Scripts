#!/bin/bash
# support-disable.sh V4 - Disable remote access by stopping and disabling Cloudflared, Cockpit, and Cockpit.socket

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

log_info "Starting support-disable process: Disabling remote access services."

# Function to stop and disable a service
stop_and_disable_service() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        if systemctl stop "$service"; then
            log_info "Stopped service: $service"
        else
            log_warn "Failed to stop service: $service"
        fi
    else
        log_info "Service $service is already stopped"
    fi

    if systemctl is-enabled --quiet "$service"; then
        if systemctl disable "$service"; then
            log_info "Disabled service: $service"
        else
            log_warn "Failed to disable service: $service"
        fi
    else
        log_info "Service $service is already disabled"
    fi
}

# Main execution
log_info "Starting support-disable process"

# Stop and disable Cloudflared
stop_and_disable_service "cloudflared"

# Stop and disable Cockpit
stop_and_disable_service "cockpit"
stop_and_disable_service "cockpit.socket"

log_info "Support-disable process completed: Remote access disabled."