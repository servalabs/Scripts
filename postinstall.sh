#!/bin/bash

# AtomOS Install Script v3.1
# Combined Main and Backup Server Installation

# run bash <(curl -sL "$(curl -s https://api.github.com/repos/servalabs/scripts/contents/postinstall.sh?ref=main | jq -r '.download_url')")


set -euo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

# === Constants ===
LOG_FILE="/var/log/setup.log"
ERROR_LOG_FILE="/var/log/setup.err.log"
FILES_DIR="/files"
COCKPIT_ASSETS_DIR="${FILES_DIR}/.assets"
COCKPIT_CONF="/etc/cockpit/cockpit.conf"
SYNCTHING_SERVICE="/etc/systemd/system/syncthing.service"
EMERGENCY_SERVICE="/etc/systemd/system/emergency.service"
KERNEL_CMDLINE="/etc/kernel/cmdline"
JOURNALD_CONF="/etc/systemd/journald.conf.d/no-console.conf"
GETTY_OVERRIDE="/etc/systemd/system/getty@tty1.service.d/override.conf"
HIDEFB_CONF="/etc/modprobe.d/hidefb.conf"
SSH_CONFIG="/etc/ssh/sshd_config"
INSTALL_MARKER="/var/lib/atomos/install_marker"

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
        log_error "Please run as root"
        return 1
    fi
    return 0
}

# === Initialize Logging ===
init_logging() {
    touch "$LOG_FILE" || { log_error "Cannot write to $LOG_FILE"; return 1; }
    exec > >(tee -a "$LOG_FILE") \
        2> >(tee -a "$ERROR_LOG_FILE" >&2)
}

# === Operation Tracking Functions ===
check_operation() {
    local operation="$1"
    if [ -f "$INSTALL_MARKER" ] && grep -q "^$operation$" "$INSTALL_MARKER"; then
        log_info "Operation '$operation' was already performed. Skipping..."
        return 1
    fi
    return 0
}

mark_operation() {
    local operation="$1"
    mkdir -p "$(dirname "$INSTALL_MARKER")"
    echo "$operation" >> "$INSTALL_MARKER"
}

# === Backup Function ===
backup_file() {
    local file="$1"
    [ -f "$file" ] && cp "$file" "${file}.bak"
}

# === Common Functions ===
update_system() {
    if ! check_operation "system_update"; then
        return
    fi
    
    log_info "Updating system packages..."
    apt-get update
    apt-get remove -y intel-microcode
    apt-get autoremove -y
    apt-get install -y jq libpam-modules cockpit samba ssh tree wget syncthing
    apt-get upgrade --with-new-pkgs -y
    log_info "Turning on Tailscale..."
    tailscale up --ssh
    
    mark_operation "system_update"
}

create_directories() {
    if ! check_operation "create_directories"; then
        return
    fi
    
    log_info "Creating directory structure..."
    local folders=(
        "10 Files" "20 Docs" "30 Gallery" 
        "40 Entertainment/41 Movies"
        "40 Entertainment/42 Shows"
        "40 Entertainment/43 Music"
        "Downloads" ".backups" ".apps" ".assets"
    )
    
    for folder in "${folders[@]}"; do
        if ! mkdir -p "${FILES_DIR}/${folder}"; then
            log_error "Failed to create directory: ${FILES_DIR}/${folder}"
            return 1
        fi
    done
    
    # Create docker group if it doesn't exist
    if ! getent group docker >/dev/null; then
        log_info "Creating docker group..."
        groupadd docker
    fi
    
    # Create admin user if it doesn't exist
    if ! id admin >/dev/null 2>&1; then
        log_info "Creating admin user..."
        useradd -m -s /sbin/nologin admin
        usermod -aG docker admin
    fi
    
    if ! chown -R admin:docker "$FILES_DIR"; then
        log_error "Failed to set ownership on $FILES_DIR"
        return 1
    fi
    
    if ! chmod -R 777 "$FILES_DIR"; then
        log_error "Failed to set permissions on $FILES_DIR"
        return 1
    fi
    
    log_info "Directory structure created successfully"
    mark_operation "create_directories"
}

install_cockpit_plugins() {
    if ! check_operation "install_cockpit_plugins"; then
        return
    fi
    
    log_info "Installing Cockpit plugins..."
    local plugins=(
        "https://github.com/45Drives/cockpit-identities/releases/download/v0.1.12/cockpit-identities_0.1.12-1focal_all.deb"
        "https://github.com/45Drives/cockpit-navigator/releases/download/v0.5.10/cockpit-navigator_0.5.10-1focal_all.deb"
        "https://github.com/45Drives/cockpit-file-sharing/releases/download/v4.2.9-8/cockpit-file-sharing_4.2.9-8focal_all.deb"
    )
    
    for plugin in "${plugins[@]}"; do
        wget -q "$plugin"
    done
    
    apt-get install -y ./*deb
    rm -f ./*.deb
    mark_operation "install_cockpit_plugins"
}

configure_cockpit() {
    if ! check_operation "configure_cockpit"; then
        return
    fi
    
    log_info "Configuring Cockpit..."
    sed -i '/^root$/d' /etc/cockpit/disallowed-users
    
    # Branding
    touch "$COCKPIT_CONF"
    echo -e "[WebService]\nLoginTitle=Atom Admin Panel" | tee "$COCKPIT_CONF"
    
    # Download assets
    mkdir -p "$COCKPIT_ASSETS_DIR"
    wget -O "${COCKPIT_ASSETS_DIR}/full-logo.png" https://server-assets.b-cdn.net/s/l/full.png
    wget -O "${COCKPIT_ASSETS_DIR}/logo-100x100.png" https://server-assets.b-cdn.net/s/l/logo-100x100.png
    wget -O "${COCKPIT_ASSETS_DIR}/logo.ico" https://server-assets.b-cdn.net/s/l/servalabs.ico
    
    # System messages
    echo "Welcome to AtomOS v1" | tee /etc/issue /etc/issue.net
    echo -e "\nWelcome to AtomOS v1" > /etc/motd
    
    mark_operation "configure_cockpit"
}

install_cloudflared() {
    if ! check_operation "install_cloudflared"; then
        return
    fi
    
    log_info "Installing Cloudflared..."
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i cloudflared.deb
    rm -f cloudflared.deb
    
    mark_operation "install_cloudflared"
}

configure_ssh() {
    if ! check_operation "configure_ssh"; then
        return
    fi
    
    log_info "Configuring SSH..."
    
    # Backup existing config
    backup_file "$SSH_CONFIG"
    
    # Download and apply new config
    wget -O "$SSH_CONFIG" https://raw.githubusercontent.com/servalabs/scripts/refs/heads/main/general/sshd_config

    # Configure networkadmin user and SSH key
    log_info "Configuring networkadmin user and SSH key..."
    
    # Ensure networkadmin exists
    if ! id "networkadmin" &>/dev/null; then
        log_info "Creating networkadmin user..."
        useradd -m -s /bin/bash -G sudo networkadmin
    fi
    
    # Create SSH directory with correct permissions
    install -d -m 700 -o networkadmin -g networkadmin /home/networkadmin/.ssh
    
    # Write authorized_keys atomically
    cat <<'EOF' > /home/networkadmin/.ssh/authorized_keys
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINx7g1o13c+ki6+zJqzZaR1x+d+sxSBHxeRrfYzXct4W eddsa-key-20250329
EOF
    
    # Set file permissions
    chown networkadmin:networkadmin /home/networkadmin/.ssh/authorized_keys
    chmod 600 /home/networkadmin/.ssh/authorized_keys
    
    # Restart SSH to ensure config reload
    systemctl restart sshd
    
    mark_operation "configure_ssh"
}

configure_syncthing() {
    if ! check_operation "configure_syncthing"; then
        return
    fi
    
    log_info "Configuring Syncthing..."
    cat <<EOF | tee "$SYNCTHING_SERVICE" > /dev/null
[Unit]
Description=Syncthing - Open Source Continuous File Synchronization
After=network.target

[Service]
User=admin
Group=docker
ExecStart=/usr/bin/syncthing -no-browser -logflags=0
Restart=on-failure
SuccessExitStatus=3 4

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable syncthing
    systemctl start syncthing
    sleep 3
    sed -i 's/127\.0\.0\.1/0.0.0.0/g' /home/admin/.config/syncthing/config.xml
    
    # Set default folder path to /files
    sed -i 's|<folder id="default" path=".*"|& path="/files"|' /home/admin/.config/syncthing/config.xml
    systemctl restart syncthing

    mark_operation "configure_syncthing"
}

configure_samba() {
    if ! check_operation "configure_samba"; then
        return
    fi
    
    log_info "Configuring Samba..."
    
    # Backup existing config
    backup_file /etc/samba/smb.conf
    
    # Create new Samba configuration
    cat <<EOF | tee /etc/samba/smb.conf > /dev/null
[global]
   ; Bind Samba exclusively to the Tailscale interface
   interfaces = tailscale0
   bind interfaces only = yes

   ; Allow connections only from Tailscale IPs (default range)
   hosts allow = 100.64.0.0/10
   hosts deny = 0.0.0.0/0

   ; Basic Samba settings
   workgroup = WORKGROUP
   server string = AtomOS Server
   security = user
   map to guest = bad user
   unix charset = UTF-8
   dos charset = CP932
   read raw = yes
   write raw = yes
   oplocks = yes
   max xmit = 65535
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   dns proxy = no
   usershare allow guests = no
   create mask = 0777
   directory mask = 0777
   force user = admin
   force group = docker
   valid users = admin

[Files]
   path = /files
   browseable = yes
   read only = no
   guest ok = no
   create mask = 0777
   directory mask = 0777
   force user = admin
   force group = docker
EOF

    # Restart Samba service
    systemctl restart smbd
    systemctl restart nmbd
    
    mark_operation "configure_samba"
}

configure_security() {
    if ! check_operation "configure_security"; then
        return
    fi
    
    log_info "Configuring system security..."
    
    # Backup and configure PAM
    backup_file /etc/pam.d/common-auth
    if ! grep -q "pam_faillock.so" /etc/pam.d/common-auth; then
        echo "auth required pam_faillock.so preauth silent audit deny=3 unlock_time=6000" >> /etc/pam.d/common-auth
    fi
    
    # Configure emergency shell
    touch "$EMERGENCY_SERVICE"
    echo -e "[Service]\nExecStart=-/bin/sh -c \"/sbin/sulogin\"" | tee "$EMERGENCY_SERVICE" > /dev/null
    
    mark_operation "configure_security"
}

cleanup_system() {
    if ! check_operation "cleanup_system"; then
        return
    fi
    
    log_info "Cleaning up system..."
    apt-get clean
    apt-get autoremove -y
    
    mark_operation "cleanup_system"
}

# === Main Server Specific Functions ===
install_casaos() {
    if ! check_operation "install_casaos"; then
        return
    fi
    
    log_info "Installing CasaOS..."
    curl -fsSL get.icewhale.io/v0.4.4 | bash
    
    mark_operation "install_casaos"
}

# === Backup Server Specific Functions ===
setup_backup_system() {
    if ! check_operation "setup_backup_system"; then
        return
    fi
    
    log_info "Setting up backup system..."
    # Add any backup-specific setup here
    
    mark_operation "setup_backup_system"
}

# === System Lockdown Configuration ===
configure_lockdown() {
    if ! check_operation "configure_lockdown"; then
        return
    fi
    
    log_info "Configuring system lockdown..."
    
    # Backup and configure kernel parameters
    backup_file "$KERNEL_CMDLINE"
    tee "$KERNEL_CMDLINE" > /dev/null <<EOF
quiet loglevel=0 rd.systemd.show_status=0 vt.global_cursor_default=0 console=ttyS0 panic=0 rd.shell=0 fbcon=map:99
EOF

    # Configure journald
    mkdir -p /etc/systemd/journald.conf.d
    tee "$JOURNALD_CONF" > /dev/null <<EOF
[Journal]
ForwardToConsole=no
EOF
    systemctl restart systemd-journald

    # Mask services
    systemctl mask serial-getty@ttyS0.service getty@tty1.service getty@tty3.service getty.target systemd-networkd-wait-online
    systemctl disable systemd-networkd-wait-online

    # Configure getty
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    backup_file "$GETTY_OVERRIDE"
    tee "$GETTY_OVERRIDE" > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear --skip-login --nonewline --noissue --skip-chdir --autologin root ttyS0 linux
EOF

    # Configure framebuffer
    tee "$HIDEFB_CONF" > /dev/null <<EOF
blacklist simplefb
blacklist efifb
EOF

    # Update system
    systemctl daemon-reexec
    kernel-install add "$(uname -r)" /lib/modules/"$(uname -r)"/vmlinuz
    bootctl update || true
    dracut --force --regenerate-all
    
    mark_operation "configure_lockdown"
}

# === Main Execution ===
main() {
    # Get user preferences first
    read -r -p "Is this a central/main server? [y/N]: " is_main_server
    read -r -p "Do you want to run the initialization script? [y/N]: " run_init
    read -r -p "Do you want to suppress HDMI logs (Part 2)? [y/N]: " run_part2
    
    # Initialize
    check_root
    init_logging
    log_info "Starting AtomOS installation..."
    
    # Run common functions
    update_system
    create_directories
    install_cockpit_plugins
    configure_cockpit
    install_cloudflared
    configure_ssh
    configure_syncthing
    configure_samba
    configure_security
    cleanup_system
    
    # Run server-specific functions
    if [[ "$is_main_server" =~ ^[Yy]$ ]]; then
        log_info "Running main server specific setup..."
        install_casaos
        
        if [[ "$run_init" =~ ^[Yy]$ ]]; then
            log_info "Downloading and running init-main.sh..."
            wget -O /tmp/init-main.sh https://raw.githubusercontent.com/servalabs/scripts/refs/heads/main/main/init-main.sh
            chmod +x /tmp/init-main.sh
            /tmp/init-main.sh
            rm -f /tmp/init-main.sh
        else
            log_info "Skipped main initialization script."
        fi
    else
        log_info "Running backup server specific setup..."
        setup_backup_system
        
        if [[ "$run_init" =~ ^[Yy]$ ]]; then
            log_info "Downloading and running init-backup.sh..."
            wget -O /tmp/init-backup.sh https://raw.githubusercontent.com/servalabs/scripts/refs/heads/main/backup/init-backup.sh
            chmod +x /tmp/init-backup.sh
            /tmp/init-backup.sh
            rm -f /tmp/init-backup.sh
        else
            log_info "Skipped backup initialization script."
        fi
    fi
    
    # Run Part 2 if requested
    if [[ "$run_part2" =~ ^[Yy]$ ]]; then
        log_info "Running Part 2 (system lockdown)..."
        configure_lockdown
        log_info "Rebooting in 5 seconds..."
        sleep 5
        reboot
    else
        log_info "Skipped Part 2."
    fi
    
    log_info "Installation completed successfully."
}

# Run main function
main 