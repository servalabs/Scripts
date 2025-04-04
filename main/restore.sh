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

# Function to get Samba username from configuration
get_samba_username() {
    local smb_conf="/etc/samba/smb.conf"
    local share_name="files"
    
    # Extract the valid users from the share configuration
    local smb_user=$(grep -A 10 "\[$share_name\]" "$smb_conf" | grep "valid users" | awk '{print $3}')
    
    if [ -z "$smb_user" ]; then
        log_warn "Could not find Samba username in configuration, using default 'admin'"
        echo "admin"
    else
        echo "$smb_user"
    fi
}

# Function to recreate sensitive directory with syncthing compatibility
recreate_sensitive_dir() {
    if [ ! -d "$SENSITIVE_DIR" ]; then
        mkdir -p "$SENSITIVE_DIR"
    fi
    # Ensure Samba and Docker can access the directory
    chown -R admin:docker "$SENSITIVE_DIR"
    chmod 770 "$SENSITIVE_DIR"
}

# Main execution
log_info "Starting restore process"

# Define all services to enable and start
ALL_SERVICES=(
    "smbd"
    "syncthing"
    "tailscaled"
    "casaos-gateway.service"
)

# Enable and start all services in parallel
enable_and_start_services "${ALL_SERVICES[@]}"

# Fix base permissions for docker and samba access
chown -R admin:docker /files && chmod -R 770 /files

# Recreate sensitive directory
recreate_sensitive_dir

log_info "Restore process completed."