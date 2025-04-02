#!/bin/bash
# restore.sh V3 - Restore environment and re-enable services on the SMB server

# Constants
LOG_FILE="/var/log/restore.log"
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

log_info "Starting restore process."

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

# Function to recreate sensitive directory
recreate_sensitive_dir() {
    if [ ! -d "$SENSITIVE_DIR" ]; then
        if mkdir -p "$SENSITIVE_DIR"; then
            log_info "Recreated sensitive directory $SENSITIVE_DIR"
        else
            log_warn "Failed to recreate directory $SENSITIVE_DIR"
        fi
    else
        log_info "Sensitive directory $SENSITIVE_DIR already exists"
    fi
}

# Main execution
log_info "Starting restore process"

# Enable and start SMB service
enable_and_start_service "smbd"

# Recreate sensitive directory
recreate_sensitive_dir

# Enable and start Syncthing
enable_and_start_service "syncthing"

# Enable and start Tailscale
enable_and_start_service "tailscaled"

# Enable and start SSH
enable_and_start_service "sshd"

# Enable and start Cloudflared
enable_and_start_service "cloudflared"

# Enable and start Cockpit
enable_and_start_service "cockpit"
enable_and_start_service "cockpit.socket"

# Start CasaOS services
for service in "${CASA_SERVICES[@]}"; do
    enable_and_start_service "$service"
done

log_info "Restore process completed."