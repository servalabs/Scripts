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
    
    # Create admin user if it doesn't exist
    if ! id admin >/dev/null 2>&1; then
        log_info "Creating admin user..."
        useradd -m -s /sbin/nologin admin
    fi
    
    # Create syncthing user if it doesn't exist
    if ! id syncthing >/dev/null 2>&1; then
        log_info "Creating syncthing user..."
        useradd -m -s /sbin/nologin syncthing
    fi
    
    # Add users to fileshare group
    log_info "Adding users to fileshare group..."
    usermod -aG "$SHARED_GROUP" www-data
    usermod -aG "$SHARED_GROUP" syncthing
    usermod -aG "$SHARED_GROUP" admin
    
    # Set ownership and permissions
    if ! chown -R admin:"$SHARED_GROUP" "$FILES_DIR"; then
        log_error "Failed to set ownership on $FILES_DIR"
        return 1
    fi
    
    if ! chmod -R 2770 "$FILES_DIR"; then
        log_error "Failed to set permissions on $FILES_DIR"
        return 1
    fi
    
    # Set ACL to ensure new files inherit group ownership
    setfacl -R -d -m g::rwx "$FILES_DIR"
    
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