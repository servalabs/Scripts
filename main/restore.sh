#!/bin/bash
# restore.sh V3.1 - Optimized restore environment and re-enable services

# Constants
LOG_FILE="/var/log/restore.log"
FILES_DIR="/files"
SHARED_GROUP="fileshare"

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

# Function to setup shared group and permissions
setup_shared_access() {
    log_info "Setting up shared group access"
    
    # Create shared group if it doesn't exist
    if ! getent group "$SHARED_GROUP" >/dev/null; then
        groupadd "$SHARED_GROUP"
    fi
    
    # Add all necessary users to shared group
    local users=(
        "admin"         # Syncthing user
        "www-data"      # Web server user
    )
    
    for user in "${users[@]}"; do
        if id "$user" >/dev/null 2>&1 && ! groups "$user" | grep -q "$SHARED_GROUP"; then
            usermod -aG "$SHARED_GROUP" "$user"
        fi
    done
    
    # Set ownership and permissions for /files
    chown -R admin:"$SHARED_GROUP" "$FILES_DIR"
    
    # Set base permissions (more restrictive for Syncthing)
    find "$FILES_DIR" -type d -exec chmod 775 {} \;  # rwxrwxr-x
    find "$FILES_DIR" -type f -exec chmod 664 {} \;  # rw-rw-r--
    
    # Ensure Syncthing config has proper permissions
    if [ -d "/home/admin/.config/syncthing" ]; then
        chown -R admin:"$SHARED_GROUP" "/home/admin/.config/syncthing"
        chmod -R 770 "/home/admin/.config/syncthing"
    fi
    
    # Create common directories if they don't exist
    local common_dirs=(
        "$FILES_DIR/10 Files"
        "$FILES_DIR/20 Docs"
        "$FILES_DIR/30 Gallery"
        "$FILES_DIR/Downloads"
        "$FILES_DIR/.backups"
        "$FILES_DIR/.apps"
        "$FILES_DIR/.assets"
    )
    
    for dir in "${common_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            chown admin:"$SHARED_GROUP" "$dir"
            chmod 775 "$dir"  # rwxrwxr-x
        fi
    done
    
    # Set ACLs for container access without affecting Syncthing
    setfacl -R -m g:"$SHARED_GROUP":rwx "$FILES_DIR"
    setfacl -R -d -m g:"$SHARED_GROUP":rwx "$FILES_DIR"
    
    # Ensure Syncthing can monitor files
    chattr -R -i "$FILES_DIR" 2>/dev/null || true  # Remove immutable flag if set
}

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

# Main execution
log_info "Starting restore process"

# Setup shared access first
setup_shared_access

# Define all services to enable and start
ALL_SERVICES=(
    "syncthing"
    "tailscaled"
    "casaos-gateway.service"
)

# Enable and start all services in parallel
enable_and_start_services "${ALL_SERVICES[@]}"

log_info "Restore process completed."