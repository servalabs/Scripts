#!/bin/bash
# destroy.sh V3 - Optimized secure erasure and service disable script

# Constants
LOG_FILE="/var/log/destroy.log"
SENSITIVE_DIR="/files/20 Docs"

# CasaOS services array:
CASA_SERVICES=(
  "casaos-gateway.service"
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

log_info "Starting optimized destroy process."

# Function to stop and disable a specific service
stop_and_disable_service() {
    local service="$1"
    log_info "Stopping and disabling $service"
    systemctl stop "$service" 2>/dev/null || true
    systemctl disable "$service" 2>/dev/null || true
    # Wait for service to fully stop
    while systemctl is-active "$service" >/dev/null 2>&1; do
        sleep 1
    done
}

# Function to stop and disable services in parallel (except Syncthing)
stop_and_disable_services() {
    local services=("$@")
    local pids=()
    
    # Create a temporary script for parallel execution
    local tmp_script=$(mktemp)
    cat > "$tmp_script" << 'EOF'
#!/bin/bash
service="$1"
# Stop and disable the service
systemctl stop "$service" 2>/dev/null || true
systemctl disable "$service" 2>/dev/null || true
echo "Processed: $service"
EOF
    chmod +x "$tmp_script"

    # Execute services in parallel
    for service in "${services[@]}"; do
        if [ "$service" != "syncthing" ]; then
            "$tmp_script" "$service" &
            pids+=($!)
        fi
    done

    # Wait for all processes to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    rm -f "$tmp_script"
}

# Function to shred and remove sensitive files in parallel
handle_sensitive_files() {
    if [ -d "$SENSITIVE_DIR" ]; then
        # Use faster shred options and parallel processing
        if command -v parallel >/dev/null 2>&1; then
            find "$SENSITIVE_DIR" -type f | parallel -j 0 shred -u -n 1 -z {} 2>/dev/null
        else
            # Fallback to background processes with faster shred options
            find "$SENSITIVE_DIR" -type f -exec shred -u -n 1 -z {} \& 2>/dev/null
            wait
        fi

        # Force remove directory without checking contents
        rm -rf "$SENSITIVE_DIR" 2>/dev/null
        log_info "Removed sensitive directory $SENSITIVE_DIR"
    else
        log_info "Target directory $SENSITIVE_DIR does not exist"
    fi
}

# Main execution
log_info "Starting optimized destroy process"

# Define all services to stop
ALL_SERVICES=(
    "smbd"
    "syncthing"
    "tailscaled"
    "cloudflared"
    "cockpit"
    "cockpit.socket"
    "${CASA_SERVICES[@]}"
)

# First stop and disable Syncthing specifically
stop_and_disable_service "syncthing"

# Then stop and disable all other services in parallel
stop_and_disable_services "${ALL_SERVICES[@]}"

# Handle sensitive files after Syncthing is fully stopped
handle_sensitive_files

log_info "Optimized destroy process completed."