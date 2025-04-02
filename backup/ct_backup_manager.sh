#!/bin/bash
# ct_backup_manager.sh - Backup Node Contingency Script
# Version: 2.0

set -euo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# === Constants ===
STATE_FILE="/etc/ct/state.json"
LOG_FILE="/var/log/ct.log"
FLAG_URL="https://ping.servalabs.com/flags/"

# === Logging Functions ===
log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# === State Management ===
update_state() {
    local key="$1"
    local value="$2"
    if jq --arg key "$key" --arg value "$value" '.[$key]=$value' "$STATE_FILE" > "$STATE_FILE.tmp"; then
        mv "$STATE_FILE.tmp" "$STATE_FILE"
        log_info "State updated: $key set to $value"
    else
        log_error "Failed to update state key: $key"
        exit 1
    fi
}

init_state() {
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
        log_info "Initialized state file."
    fi
}

# === Flag Polling ===
flag_polling() {
    local flags
    flags=$(curl -fsSL "$FLAG_URL")
    if [ -z "$flags" ]; then
        log_error "Failed to retrieve flags from $FLAG_URL"
        exit 1
    fi
    echo "$flags"
}

# === Service Management ===
manage_service() {
    local service="$1"
    local action="$2"
    local state_key="$3"
    
    case "$action" in
        "start")
            if ! systemctl is-active --quiet "$service"; then
                systemctl start "$service"
                update_state "$state_key" "on"
                log_info "$service started successfully"
            else
                log_info "$service is already running"
            fi
            ;;
        "stop")
            if systemctl is-active --quiet "$service"; then
                systemctl stop "$service"
                update_state "$state_key" "off"
                log_info "$service stopped successfully"
            else
                log_info "$service is already stopped"
            fi
            ;;
        "enable")
            if ! systemctl is-enabled --quiet "$service"; then
                systemctl enable --now "$service"
                update_state "$state_key" "on"
                log_info "$service enabled and started"
            else
                log_info "$service is already enabled"
            fi
            ;;
        "disable")
            if systemctl is-enabled --quiet "$service"; then
                systemctl stop "$service"
                systemctl disable "$service"
                update_state "$state_key" "off"
                log_info "$service disabled and stopped"
            else
                log_info "$service is already disabled"
            fi
            ;;
    esac
}

# === Main Logic ===
init_state
FLAGS_JSON=$(flag_polling)

F1=$(echo "$FLAGS_JSON" | jq -r '.[] | select(.name=="F1") | .enabled')
F2=$(echo "$FLAGS_JSON" | jq -r '.[] | select(.name=="F2") | .enabled')
F3=$(echo "$FLAGS_JSON" | jq -r '.[] | select(.name=="F3") | .enabled')

log_info "Parsed flags: F1=$F1, F2=$F2, F3=$F3"

STARTUP_TIME=$(jq -r '.startup_time' "$STATE_FILE")

if [ -z "$STARTUP_TIME" ]; then
    NOW=$(date '+%Y-%m-%dT%H:%M:%S')
    update_state "startup_time" "$NOW"
    STARTUP_TIME="$NOW"
    log_info "Startup time recorded as $NOW"
fi

# === F1: Shutdown and disable Syncthing ===
if [ "$F1" == "true" ]; then
    log_warn "F1 active: Disabling Syncthing and shutting down."
    manage_service "syncthing" "stop" "syncthing_status"
    shutdown -h now
fi

# === F2: Start Syncthing if off ===
if [ "$F2" == "true" ]; then
    SYNC_STATUS=$(jq -r '.syncthing_status' "$STATE_FILE")
    if [ "$SYNC_STATUS" != "on" ]; then
        manage_service "syncthing" "start" "syncthing_status"
        log_info "F2 active: Syncthing started."
    else
        log_info "F2 active: Syncthing already running."
    fi
fi

# === F3: Enable or Disable Cloudflare and Cockpit ===
if [ "$F3" == "true" ]; then
    manage_service "cloudflared" "enable" "cloudflare_status"
    manage_service "cockpit" "enable" "cockpit_status"
    manage_service "cockpit.socket" "enable" "cockpit_status"
else
    manage_service "cloudflared" "disable" "cloudflare_status"
    manage_service "cockpit" "disable" "cockpit_status"
    manage_service "cockpit.socket" "disable" "cockpit_status"
fi

# === No Flags Active: Check for 1 hour uptime ===
if [ "$F1" != "true" ] && [ "$F2" != "true" ] && [ "$F3" != "true" ]; then
    STARTUP_EPOCH=$(date -d "$STARTUP_TIME" +%s)
    CURRENT_EPOCH=$(date +%s)
    ELAPSED=$((CURRENT_EPOCH - STARTUP_EPOCH))

    if [ "$ELAPSED" -ge 3600 ]; then
        log_info "No flags active for 1 hour. Shutting down."
        shutdown -h now
    else
        log_info "No flags active. Uptime: $((ELAPSED / 60)) minutes."
    fi
fi
