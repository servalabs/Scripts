#!/bin/bash
# restore.sh V3.1 - Optimized restore environment and re-enable services

# Constants
LOG_FILE="/var/log/restore.log"
SENSITIVE_DIR="/files/20 Docs"

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

# Function to recreate sensitive directory with syncthing compatibility
recreate_sensitive_dir() {
    if [ ! -d "$SENSITIVE_DIR" ]; then
        mkdir -p "$SENSITIVE_DIR"
    fi
    # Ensure Samba and Docker can access the directory
    chown -R www-data:www-data "$SENSITIVE_DIR"
    chmod 755 "$SENSITIVE_DIR"
}

# Main execution
log_info "Starting restore process"

# Define all services to enable and start
ALL_SERVICES=(
    "syncthing"
    "tailscaled"
    "casaos-gateway.service"
)

# Enable and start all services in parallel
enable_and_start_services "${ALL_SERVICES[@]}"

# Fix base permissions for docker access
chown -R www-data:www-data /files
chmod -R 755 /files

# Recreate sensitive directory
recreate_sensitive_dir

log_info "Restore process completed."