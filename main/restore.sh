#!/bin/bash
# restore.sh V3 - Optimized restore environment and re-enable services

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

log_info "Starting optimized restore process."

# Function to enable and start services in parallel
enable_and_start_services() {
    local services=("$@")
    local pids=()
    
    # Create a temporary script for parallel execution
    local tmp_script=$(mktemp)
    cat > "$tmp_script" << 'EOF'
#!/bin/bash
service="$1"
# Enable and start the service
systemctl enable "$service" 2>/dev/null || true
systemctl start "$service" 2>/dev/null || true
echo "Processed: $service"
EOF
    chmod +x "$tmp_script"

    # Execute services in parallel
    for service in "${services[@]}"; do
        "$tmp_script" "$service" &
        pids+=($!)
    done

    # Wait for all processes to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    rm -f "$tmp_script"
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

# Function to recreate sensitive directory
recreate_sensitive_dir() {
    local smb_user=$(get_samba_username)
    
    if [ ! -d "$SENSITIVE_DIR" ]; then
        mkdir -p "$SENSITIVE_DIR" 2>/dev/null || true
        # Set permissions to match Samba configuration (770)
        chmod 770 "$SENSITIVE_DIR" 2>/dev/null || true
        # Set ownership to match Samba configuration (user:user)
        chown "$smb_user:$smb_user" "$SENSITIVE_DIR" 2>/dev/null || true
        log_info "Recreated sensitive directory $SENSITIVE_DIR with Samba permissions for user $smb_user"
    else
        # Ensure existing directory has correct permissions
        chmod 770 "$SENSITIVE_DIR" 2>/dev/null || true
        chown "$smb_user:$smb_user" "$SENSITIVE_DIR" 2>/dev/null || true
        log_info "Updated permissions for existing sensitive directory $SENSITIVE_DIR for user $smb_user"
    fi
}

# Main execution
log_info "Starting restore process"

# Define all services to enable and start
ALL_SERVICES=(
    "smbd"
    "syncthing"
    "tailscaled"
    "${CASA_SERVICES[@]}"
)

# Enable and start all services in parallel
enable_and_start_services "${ALL_SERVICES[@]}"

# Fix share permissions
chown -R :docker /files && chmod -R 770 /files

# Recreate sensitive directory
recreate_sensitive_dir

log_info "Restore process completed."