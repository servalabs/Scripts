#!/bin/bash
# ct_manager.sh - Consolidated Control Manager with Enhanced Logging

# Constants & Files
STATE_FILE="/etc/ct/state.json"
LOG_FILE="/var/log/ct.log"
FLAG_URL="https://ping.servalabs.com/flags/"
SENSITIVE_DIR="/files/20 Docs"

# Logging Functions with Levels
log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" >> "${LOG_FILE}"
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

# Update the JSON state file (using jq) for a given key.
update_state() {
    local key="$1"
    local value="$2"
    if jq --arg key "$key" --arg value "$value" '.[$key]=$value' "${STATE_FILE}" > "${STATE_FILE}.tmp"; then
        mv "${STATE_FILE}.tmp" "${STATE_FILE}"
        log_info "State updated: ${key} set to ${value}"
    else
        log_error "Failed to update state for key ${key}"
        exit 1
    fi
}

# Retrieve the flags from the remote dashboard
flag_polling() {
    local flags
    flags=$(curl -fsSL "${FLAG_URL}")
    if [ -z "${flags}" ]; then
        log_error "Failed to retrieve flags from ${FLAG_URL}"
    else
        log_info "Flags retrieved successfully"
    fi
    echo "${flags}"
}

# Fetch and execute the mode-specific script from GitHub
execute_script() {
    local mode="$1"  # Expected values: "destroy", "restore", or "support"
    log_info "Fetching script for mode: ${mode}"
    local sha
    sha=$(curl -fsSL https://api.github.com/repos/servalabs/scripts/commits/main | jq -r '.sha')
    if [ -z "$sha" ]; then
        log_error "Unable to fetch commit SHA for ${mode} script."
        exit 1
    fi

    local script_url="https://raw.githubusercontent.com/servalabs/scripts/${sha}/main/${mode}.sh"
    log_info "Executing ${mode} script from ${script_url}"
    if output=$(bash <(curl -fsSL "${script_url}") 2>&1); then
        log_info "${mode^} script executed successfully. Output: ${output}"
    else
        log_error "${mode^} script execution failed. Output: ${output}"
        exit 1
    fi
}

# Check if sensitive files exist
sensitive_files_exist() {
    if [ -d "${SENSITIVE_DIR}" ] && [ "$(ls -A "${SENSITIVE_DIR}")" ]; then
        log_info "Sensitive files found in ${SENSITIVE_DIR}"
        return 0  # Sensitive files exist
    else
        log_info "No sensitive files found in ${SENSITIVE_DIR}"
        return 1
    fi
}

# Check if services are running
services_running() {
    local services=("tailscale" "syncthing" "casaos")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_info "Service $service is running"
            return 0  # At least one service is running
        fi
    done
    return 1  # No services are running
}

# Initialize the state file if it does not exist.
init_state() {
    if [ ! -f "${STATE_FILE}" ]; then
        echo '{"deleted_flag": "no", "last_transition": ""}' > "${STATE_FILE}"
        log_info "Initialized state file at ${STATE_FILE}"
    else
        log_info "State file ${STATE_FILE} already exists"
    fi
}

# ----- Main Execution Flow -----
init_state

# Get flags JSON from dashboard
FLAGS_JSON=$(flag_polling)
if [ -z "${FLAGS_JSON}" ]; then
    log_error "Error: Could not retrieve flags."
    exit 1
fi

# Parse the flags (F1, F2, F3) from the JSON response.
F1=$(echo "${FLAGS_JSON}" | jq -r '.[] | select(.name=="F1") | .enabled')
F2=$(echo "${FLAGS_JSON}" | jq -r '.[] | select(.name=="F2") | .enabled')
F3=$(echo "${FLAGS_JSON}" | jq -r '.[] | select(.name=="F3") | .enabled')
log_info "Parsed flags: F1=${F1}, F2=${F2}, F3=${F3}"

# Read current state from the local JSON state file.
DELETED_FLAG=$(jq -r '.deleted_flag' "${STATE_FILE}")
log_info "Current state: deleted_flag=${DELETED_FLAG}"

# ----- Mode Decisions -----
if [ "${F1}" == "true" ]; then
    # Destroy Mode (F1 active)
    if sensitive_files_exist; then
        log_info "F1 active: Files exist, deleting them"
        execute_script destroy
    fi
    
    if services_running; then
        log_info "F1 active: Services are running, stopping them"
        execute_script destroy
    fi
    
    if ! sensitive_files_exist && ! services_running; then
        log_info "F1 active: Files deleted and services stopped, updating state"
        update_state "deleted_flag" "yes"
        update_state "last_transition" "$(date '+%Y-%m-%dT%H:%M:%S')"
        /usr/sbin/shutdown
    fi

elif [ "${F2}" == "true" ]; then
    # Restore Mode (F2 active)
    if [ "${DELETED_FLAG}" == "yes" ] && ! sensitive_files_exist; then
        log_info "F2 active: Files are deleted, restoring them"
        execute_script restore
        update_state "deleted_flag" "no"
        update_state "last_transition" "$(date '+%Y-%m-%dT%H:%M:%S')"
    else
        log_warn "F2 active: No restore needed - files exist or not in deleted state"
    fi

elif [ "${F3}" == "true" ]; then
    # Support Mode (F3 active)
    log_info "F3 active: Enabling remote access"
    execute_script support
    update_state "last_transition" "$(date '+%Y-%m-%dT%H:%M:%S')"
else
    # Support Mode inactive
    log_info "Support mode inactive: Disabling remote access"
    execute_script support-disable
    update_state "last_transition" "$(date '+%Y-%m-%dT%H:%M:%S')"
fi

log_info "Execution completed."