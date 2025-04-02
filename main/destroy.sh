#!/bin/bash
# destroy.sh V3 - Securely erase sensitive data and disable services on the SMB server

# Constants
LOG_FILE="/var/log/destroy.log"
SENSITIVE_DIR="/files/20 Docs"

# CasaOS services array:
CASA_SERVICES=(
  "casaos-app-management.service"
  "casaos-gateway.service"
  "casaos-local-storage.service"
  "casaos-message-bus.service"
  "casaos-user-service.service"
  "casaos.service"
)

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

log_info "Starting destroy process."

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

# Function to shred and remove sensitive files
handle_sensitive_files() {
    if [ -d "$SENSITIVE_DIR" ]; then
        if find "$SENSITIVE_DIR" -type f -exec shred -u -v {} \;; then
            log_info "Sensitive files shredded in $SENSITIVE_DIR"
        else
            log_warn "Error shredding files in $SENSITIVE_DIR"
        fi

        if rm -rf "$SENSITIVE_DIR"; then
            log_info "Removed sensitive directory $SENSITIVE_DIR"
        else
            log_warn "Failed to remove directory $SENSITIVE_DIR"
        fi
    else
        log_info "Target directory $SENSITIVE_DIR does not exist"
    fi
}

# Main execution
log_info "Starting destroy process"

# Stop and disable SMB service
stop_and_disable_service "smbd"

# Stop and disable Syncthing
stop_and_disable_service "syncthing"

# Handle sensitive files
handle_sensitive_files

# Stop and disable Tailscale
stop_and_disable_service "tailscaled"

# Stop and disable Cloudflared
stop_and_disable_service "cloudflared"

# Stop and disable Cockpit
stop_and_disable_service "cockpit"
stop_and_disable_service "cockpit.socket"

# Stop CasaOS services
for service in "${CASA_SERVICES[@]}"; do
    stop_and_disable_service "$service"
done

log_info "Destroy process completed."