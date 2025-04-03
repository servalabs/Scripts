#!/bin/bash
# init-backup.sh - Initialize CT Backup Manager
# Version: 2.0

set -euo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# === Constants ===
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="ct_backup_manager.sh"
LOG_FILE="/var/log/ct.log"
STATE_DIR="/etc/ct"
STATE_FILE="$STATE_DIR/state.json"
SERVICE_NAME="ct_backup_manager"
SCRIPT_URL="https://raw.githubusercontent.com/servalabs/scripts/refs/heads/main/backup/ct_backup_manager.sh"

# === Logging Functions ===
log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# === Root Check ===
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# === Directory Setup ===
setup_directories() {
    log_info "Creating required directories..."
    mkdir -p "$STATE_DIR" "$INSTALL_DIR"
    chmod 755 "$STATE_DIR" "$INSTALL_DIR"
}

# === Script Installation ===
install_script() {
    log_info "Installing $SCRIPT_NAME..."
    
    if curl -fsSL -o "$INSTALL_DIR/$SCRIPT_NAME" "$SCRIPT_URL"; then
        chmod 755 "$INSTALL_DIR/$SCRIPT_NAME"
        log_info "Script installed successfully"
    else
        log_error "Failed to download script from $SCRIPT_URL"
        exit 1
    fi
}

# === Log File Setup ===
setup_logging() {
    log_info "Setting up logging..."
    touch "$LOG_FILE"
    chmod 664 "$LOG_FILE"
}

# === State File Setup ===
setup_state_file() {
    log_info "Setting up state file..."
    if [ ! -f "$STATE_FILE" ]; then
        cat <<EOF > "$STATE_FILE"
{
  "startup_time": "",
  "syncthing_status": "off",
  "cloudflare_status": "off",
  "cockpit_status": "off",
  "last_transition": ""
}
EOF
        chmod 644 "$STATE_FILE"
        log_info "State file initialized"
    else
        log_info "State file already exists"
    fi
}

# === Service Setup ===
setup_service() {
    log_info "Setting up systemd service..."
    
    # Create main service file
    cat <<EOF > "/etc/systemd/system/$SERVICE_NAME.service"
[Unit]
Description=CT Backup Manager Service
After=network.target

[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/$SCRIPT_NAME
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF

    # Create timer file
    cat <<EOF > "/etc/systemd/system/$SERVICE_NAME.timer"
[Unit]
Description=Runs CT Backup Manager every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=$SERVICE_NAME.service

[Install]
WantedBy=timers.target
EOF

    # Create watchdog service to ensure timer is running
    cat <<EOF > "/etc/systemd/system/${SERVICE_NAME}-watchdog.service"
[Unit]
Description=CT Backup Manager Timer Watchdog
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'if ! systemctl is-active --quiet ${SERVICE_NAME}.timer; then systemctl start ${SERVICE_NAME}.timer; fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Set permissions
    chmod 644 "/etc/systemd/system/$SERVICE_NAME.service"
    chmod 644 "/etc/systemd/system/$SERVICE_NAME.timer"
    chmod 644 "/etc/systemd/system/${SERVICE_NAME}-watchdog.service"

    # Reload and enable
    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME.timer"
    systemctl enable --now "${SERVICE_NAME}-watchdog.service"
    
    log_info "Service, timer, and watchdog installed and enabled"
}

# === Main Execution ===
main() {
    log_info "Starting CT Backup Manager installation..."
    
    check_root
    setup_directories
    install_script
    setup_logging
    setup_state_file
    setup_service
    
    log_info "CT Backup Manager installation completed successfully"
}

# Run main function
main
