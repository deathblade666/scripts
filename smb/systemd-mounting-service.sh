#!/bin/bash

sudo -v

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ALL_PHASES=()
PHASE_STATUS=()

phase_spinner() {
    local message=$1
    shift
    local cmd=("$@")

    echo -n "$message... "
    "${cmd[@]}" &> /dev/null & local pid=$!

    local spinstr='|/-\\'
    local i=0

    while kill -0 $pid 2>/dev/null; do
        printf "\r%s... [%c]  " "$message" "${spinstr:i++%${#spinstr}:1}"
        sleep 0.1
    done

    wait $pid
    local exit_code=$?
    local status="$( [ $exit_code -eq 0 ] && echo 'Done.' || echo 'FAILED.')"
    printf "\r%s... %s\n" "$message" "$status"

    ALL_PHASES+=("$message")
    PHASE_STATUS+=("$status")

    return $exit_code
}

create_mounting_service() {
    local c_user="$1"
    local c_pass="$2"
    local c_ip="$3"
    local c_base_path="$4"

    local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
    local xdg_bin="${XDG_DATA_HOME:-$HOME/.local/bin}"

    local config_dir="$xdg_config/nas-mount"
    local config_file="$config_dir/config"
    local cred_file="$config_dir/.smbcreds"
    local script_path="$xdg_bin/mount-nas.sh"
    local service_path="$xdg_config/systemd/user/nas-mount.service"

    mkdir -p "$config_dir" "$xdg_bin" "$(dirname "$service_path")"

    cat > "$config_file" <<CONF
NAS_IP="$c_ip"
NAS_BASE="$c_base_path"

# Source_on_SMB Home_Folder_Name
Documents Documents
Pictures Pictures
Videos Videos
CONF

    echo -e "username=$c_user\npassword=$c_pass" > "$cred_file"
    chmod 600 "$cred_file"

    cat > "$script_path" <<'EOF'
#!/bin/bash
CONF_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/nas-mount"
CONFIG_FILE="$CONF_ROOT/config"
CRED_FILE="$CONF_ROOT/.smbcreds"

# Only source lines that are actual variable assignments to avoid errors
if [ -f "$CONFIG_FILE" ]; then
    eval "$(grep '=' "$CONFIG_FILE")"
fi

OPTS="credentials=$CRED_FILE,uid=$(id -u),gid=$(id -g),iocharset=utf8,sec=ntlmssp,soft,vers=3.0"

mount_share() {
    local remote="$1"
    local local_dir="$2"
    local target="$HOME/$local_dir"
    if ping -c 1 -W 2 "$NAS_IP" > /dev/null 2>&1; then
        [ ! -d "$target" ] && mkdir -p "$target"
        mountpoint -q "$target" || sudo mount -t cifs "//$NAS_IP/$NAS_BASE/$remote" "$target" -o "$OPTS"
    fi
}

unmount_all() {
    findmnt -t cifs -o TARGET -n | while read -r mnt; do
        sudo umount -l -f "$mnt"
    done
}

case "$1" in
    --stop|-S|stop) unmount_all ;;
    *)
        FILE_TO_READ="$CONFIG_FILE"
        [[ ("$1" == "--file" || "$1" == "-F") && -f "$2" ]] && FILE_TO_READ="$2"

        if [ -f "$FILE_TO_READ" ]; then
            while read -r line || [[ -n "$line" ]]; do
                # Strip comments and trim whitespace
                clean_line=$(echo "$line" | sed 's/#.*//' | xargs)
                # Skip if empty or contains an equals sign (variable)
                [[ -z "$clean_line" || "$clean_line" == *"="* ]] && continue

                read -r remote local <<< "$clean_line"
                [ -z "$local" ] && local="$remote"
                mount_share "$remote" "$local"
            done < "$FILE_TO_READ"
        else
            echo "Usage: $0 [stop | -S | -F file.txt]"
            exit 1
        fi
        ;;
esac
EOF

    chmod +x "$script_path"

    cat > "$service_path" <<EOF
[Unit]
Description=Post-Login NAS Mount (Homed Compatible)
After=network-online.target
Wants=network-online.target
Before=exit.target

[Service]
Type=oneshot
ExecStart=$script_path
ExecStop=$script_path stop
RemainAfterExit=yes
Restart=on-failure
RestartSec=30

[Install]
WantedBy=default.target
EOF

    local current_user=$(whoami)
    local sudo_file="/etc/sudoers.d/10-nas_mount_$current_user"

    if ! sudo grep -q "^@includedir /etc/sudoers.d" /etc/sudoers; then
        echo "@includedir /etc/sudoers.d" | sudo tee -a /etc/sudoers > /dev/null
    fi

    echo "$current_user ALL=(ALL) NOPASSWD: /usr/bin/mount, /usr/bin/umount" | sudo tee "$sudo_file" > /dev/null
    sudo chmod 440 "$sudo_file"
    sudo -K
    systemctl --user daemon-reload
    systemctl --user enable --now nas-mount.service
}

while true; do
    echo -e "\n${GREEN}Select an option:${NC}"
    echo "1) Create mounting service"
    echo "0) Exit"
    read -p "Enter your choice [0-8]: " choice

    case $choice in
        1)
           # Reset variable for fresh run
           EXISTING_CONFIG=false
           CONF_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/nas-mount"
           CONF_FILE="$CONF_ROOT/config"
           CRED_FILE="$CONF_ROOT/.smbcreds"

           if [ -f "$CONF_FILE" ] && [ -f "$CRED_FILE" ]; then
               tmp_ip=$(grep '^NAS_IP=' "$CONF_FILE" | cut -d'"' -f2)
               tmp_base=$(grep '^NAS_BASE=' "$CONF_FILE" | cut -d'"' -f2)

               echo "Existing NAS configuration found: $tmp_ip ($tmp_base)"
               read -p "Use existing settings? (Y/n): " use_existing
               if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
                   EXISTING_CONFIG=true
                   smb_ip="$tmp_ip"
                   smb_path="$tmp_base"
                   cifs_user=$(grep 'username=' "$CRED_FILE" | cut -d= -f2)
                   cifs_pass=$(grep 'password=' "$CRED_FILE" | cut -d= -f2)
               fi
           fi

           if [ "$EXISTING_CONFIG" != true ]; then
               read -p "Enter CIFS username: " cifs_user
               read -s -p "Enter CIFS password: " cifs_pass; echo
               read -p "Enter CIFS Share IP: " smb_ip
               read -p "Enter Base Path: " smb_path; echo
           fi
           phase_spinner "Setting up Mounting Service" create_mounting_service "$cifs_user" "$cifs_pass" "$smb_ip" "$smb_path"
           ;;
        0) break ;;
    esac
done
