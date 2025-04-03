#!/bin/bash

# Fail2ban Configuration Script
# This script sets up fail2ban with custom jails and filters

set -euo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# Constants
FAIL2BAN_JAIL="/etc/fail2ban/jail.local"
LOG_FILE="/var/log/fail2ban_setup.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log "Please run as root"
    exit 1
fi

# Install fail2ban if not already installed
if ! command -v fail2ban-server &> /dev/null; then
    log "Installing fail2ban..."
    apt-get update
    apt-get install -y fail2ban
fi

# Check if Samba is installed
if command -v smbd &> /dev/null; then
    log "Samba is installed, configuring Samba filter..."
    # Create Samba filter
    cat <<EOF | tee /etc/fail2ban/filter.d/samba > /dev/null
[Definition]
failregex = .*%\(<F-CONTENT>.+</F-CONTENT>\)s
ignoreregex =
EOF
    SAMBA_JAIL="
[samba]
enabled = true
port = 445,139
filter = samba
logpath = /var/log/samba/log.smbd
maxretry = 3"
else
    log "Samba is not installed, skipping Samba configuration"
    SAMBA_JAIL=""
fi

# Configure fail2ban jails
log "Configuring fail2ban jails..."
cat <<EOF | tee "$FAIL2BAN_JAIL" > /dev/null
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
banaction = nftables-multiport
backend = auto

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
$SAMBA_JAIL
EOF

# Restart fail2ban
log "Restarting fail2ban service..."
systemctl daemon-reload
systemctl enable --now fail2ban

# Verify fail2ban status
if ! systemctl is-active --quiet fail2ban; then
    log "Failed to start fail2ban"
    exit 1
fi

log "Fail2ban is active and configured successfully"
log "Configuration complete. Check $LOG_FILE for details." 