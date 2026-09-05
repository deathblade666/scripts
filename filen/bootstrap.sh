#!/bin/bash
set -e
cd "$(dirname "$0")"

INSTALL_DIR="$(pwd)"

# Determine the actual calling user if run with sudo
REAL_USER="${SUDO_USER:-$(whoami)}"

# Set a dynamic sudo prefix for commands that require root (like writing to /usr/local/bin)
if [ "$EUID" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

mkdir -p "$INSTALL_DIR"

ignores_created=false
if [ ! -d "$INSTALL_DIR/ignores" ]; then
  mkdir -p "$INSTALL_DIR/ignores"
  ignores_created=true
fi

# determine platform as "linux" or "macos"
if [[ "$(uname -s)" == "Linux" ]] ; then
  platform=linux
elif [[ "$(uname -s)" == "Darwin" ]] ; then
  platform=macos
fi

# determine architecture as "x64" or "arm64"
if [[ "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ]] ; then
  arch=arm64
else
  arch=x64
fi

# fetch release info
latest_release=$(curl -s https://api.github.com/repos/FilenCloudDienste/filen-cli/releases/latest)
version=$(echo "$latest_release" | grep "tag_name" | cut -d \" -f 4)
download_url=$(echo "$latest_release" | grep "browser_download_url.*$platform-$arch" | cut -d \" -f 4)

$SUDO curl -sL "$download_url" -o "$INSTALL_DIR/filen"
$SUDO chmod +x "$INSTALL_DIR/filen"
$SUDO ln -sf "$INSTALL_DIR/filen" /usr/local/bin/filen

if [ ! -f "$INSTALL_DIR/.filen-cli-credentials" ]; then
  echo "--- Credential Setup ---"
  read -p "Enter username/email: " filen_username
  read -s -p "Enter password: " filen_password
  echo
  read -p "Is 2FA enabled? (y/n): " filen_2fa

  filen_recovery=""
  if [[ "$filen_2fa" =~ ^[Yy]$ ]]; then
    read -p "Enter 2FA recovery key: " filen_recovery
  fi

  {
    echo "$filen_username"
    echo "$filen_password"
    echo "$filen_recovery"
  } > "$INSTALL_DIR/.filen-cli-credentials"
  chmod 600 "$INSTALL_DIR/.filen-cli-credentials"
else
  echo "Credentials file already exists. Skipping credential setup."
fi

conf_created=false
if [ ! -f "$INSTALL_DIR/sync_pairs.conf" ]; then
  cat << 'EOF' > "$INSTALL_DIR/sync_pairs.conf"
# Format: LOCAL_PATH | REMOTE_PATH | IGNORE_FILE | SYNC_MODE
#/srv/samba/media | /Backup/Media | ignores/media.filenignore | localToCloud
EOF
  conf_created=true
fi

# If we ran as root/sudo, ensure the local installation files belong to the real user
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
  chown -R "$REAL_USER:$REAL_USER" "$INSTALL_DIR"
fi

cron_configured=false
setup_cronjob() {
  echo "Setting up automated daily cron job..."
  CRON_JOB="0 2 * * * /bin/bash $(pwd)/backup.sh"
  (crontab -l 2>/dev/null | grep -Fv "backup.sh"; echo "$CRON_JOB") | crontab -
  cron_configured=true
  echo "Cron job configured to run daily at 2:00 AM."
}

dry_run_executed=false
if [ "$ignores_created" = false ] && [ "$conf_created" = false ]; then
  echo
  read -p "Existing configuration detected. Would you like to run a dry run of backup.sh now to validate? (y/n): " run_dry
  if [[ "$run_dry" =~ ^[Yy]$ ]]; then
    if [ -f "$INSTALL_DIR/backup.sh" ]; then
      echo "Running backup.sh dry run..."
      ./backup.sh --dry-run
      dry_run_executed=true
    else
      echo "Notice: backup.sh not found in this directory."
    fi
  fi
  echo
  read -p "Would you like to set up the automated daily cron job now? (y/n): " setup_cron_choice
  if [[ "$setup_cron_choice" =~ ^[Yy]$ ]]; then
    setup_cronjob
  fi
else
  echo
  read -p "Would you like to set up the automated daily cron job to run automatically? (y/n): " setup_cron_choice
  if [[ "$setup_cron_choice" =~ ^[Yy]$ ]]; then
    setup_cronjob
  fi
fi

echo
echo "--- Setup Summary ---"
echo "• Installation Directory: $INSTALL_DIR"
echo "• Ignores folder: $( [ "$ignores_created" = true ] && echo "Created" || echo "Already existed" )"
echo "• Filen CLI: Installed and linked to /usr/local/bin/filen"
echo "• Credentials: Saved to .filen-cli-credentials"
echo "• Sync pairs config: $( [ "$conf_created" = true ] && echo "Generated template" || echo "Already existed" )"
if [ "$ignores_created" = false ] && [ "$conf_created" = false ]; then
  echo "• Dry run executed: $( [ "$dry_run_executed" = true ] && echo "Yes" || echo "No" )"
fi
echo "• Cron job configured: $( [ "$cron_configured" = true ] && echo "Yes" || echo "No" )"
echo
echo "Setup complete!"
