#!/bin/bash
# restore.sh - Service restoration script

# Constants
LOG_FILE="/var/log/restore.log"
FILES_DIR="/files"
SHARED_GROUP="fileshare"

# Directory structure to maintain
DIRECTORIES=(
    ".apps"
    ".assets"
    ".backups"
    "10 Files"
    "20 Docs"
    "30 Gallery"
    "Downloads"
)

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

# Function to ensure directory structure
ensure_directory_structure() {
    log_info "Ensuring directory structure"
    
    # Create base directory if missing
    if [ ! -d "$FILES_DIR" ]; then
        log_info "Creating base directory: $FILES_DIR"
        mkdir -p "$FILES_DIR"
    fi
    
    # Create all required directories
    for dir in "${DIRECTORIES[@]}"; do
        local full_path="${FILES_DIR}/${dir}"
        if [ ! -d "$full_path" ]; then
            log_info "Creating directory: $full_path"
            mkdir -p "$full_path"
        fi
    done
}

# Function to ensure proper permissions
ensure_permissions() {
    log_info "Ensuring proper permissions"
    
    # Create shared group if needed
    if ! getent group "$SHARED_GROUP" >/dev/null; then
        groupadd "$SHARED_GROUP"
    fi
    
    # Add necessary users to shared group
    local users=("admin" "www-data")
    for user in "${users[@]}"; do
        if id "$user" >/dev/null 2>&1 && ! groups "$user" | grep -q "$SHARED_GROUP"; then
            usermod -aG "$SHARED_GROUP" "$user"
        fi
    done
    
    # Set ownership and base permissions
    chown -R www-data:"$SHARED_GROUP" "$FILES_DIR"
    find "$FILES_DIR" -type d -exec chmod 775 {} \;
    find "$FILES_DIR" -type f -exec chmod 664 {} \;
    
    # Ensure Syncthing config has proper permissions
    if [ -d "/home/admin/.config/syncthing" ]; then
        chown -R admin:"$SHARED_GROUP" "/home/admin/.config/syncthing"
        chmod -R 770 "/home/admin/.config/syncthing"
    fi
    
    # Remove any immutable flags
    chattr -R -i "$FILES_DIR" 2>/dev/null || true
}

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

# Ensure directory structure exists
ensure_directory_structure

# Ensure permissions are correct
ensure_permissions

# Restore services
restore_services

log_info "Restore process completed"