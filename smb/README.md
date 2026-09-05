# NAS Mounting Automation & User Service

A robust Bash automation script designed to set up, configure, and manage automatic CIFS (SMB) Network Attached Storage (NAS) mounts for user sessions using **systemd user services** and **XDG base directories**.

---

## Features

- **XDG Compliant:** Places configuration files under `$XDG_CONFIG_HOME` (defaulting to `~/.config/nas-mount`) and helper scripts under `$XDG_DATA_HOME` (defaulting to `~/.local/bin`).
- **Systemd User Integration:** Automatically configures a per-user background systemd service (`nas-mount.service`) that mounts configured shares on login/network availability and unmounts them cleanly on logout.
- **Smart Configuration Detection:** Detects existing configuration files and prompts whether you want to reuse previous credentials and IP settings or re-enter them.
- **Password Safety:** Uses a secure, quoted heredoc to generate the Samba credentials file with correct file permissions (`600`).
- **Sudoers Automation:** Securely provisions NOPASSWD permissions exclusively for `/usr/bin/mount` and `/usr/bin/umount` via `/etc/sudoers.d/`.
- **Interactive TUI:** Simple menu-driven interface to guide you through setup.

---

## Prerequisites

Ensure the following standard utilities are available on your system (usually installed by default on mainstream distributions):
- Bash (v4+)
- `systemd` (with user session support enabled)
- `mount`, `umount`, `findmnt`, `mountpoint` (`util-linux`)
- `ping` (`iputils`)
- `grep`, `sed`, `xargs`

---

## Installation & Usage

1. Save your main script (e.g., `setup-nas.sh`).
2. Make the script executable:
```
chmod +x setup-nas.sh
```
3. Run the script:
```
./setup-nas.sh
```
4. Select option **1** to create and configure the mounting service. You will be prompted for:
   - CIFS Username
   - CIFS Password
   - NAS IP Address
   - NAS Base Share Path

---

## Manual Configuration (Without Prompts)

If you prefer not to use the interactive wizard, you can set up the configuration files manually. 

### 1. Create the Config Directory
```
mkdir -p ~/.config/nas-mount
```

### 2. Create the Credentials File (`.smbcreds`)
Create a file named `~/.config/nas-mount/.smbcreds` containing your SMB user credentials:
```
username=your_username
password=your_password
```
```
*Crucial:* Set strict file permissions so other users cannot read your password:
```
chmod 600 ~/.config/nas-mount/.smbcreds
```

### 3. Create the Main Config File (`config`)
Create a file named `~/.config/nas-mount/config` defining your NAS IP, base path, and the shares you want to map. 

The format maps remote shares to local folders under your home directory (`~/<Home_Folder_Name>`):
```
NAS_IP="192.168.1.100"
NAS_BASE="SharedFolder"

# Source_on_SMB Home_Folder_Name
Documents Documents
Pictures Media/Pictures
Videos Videos
Backup BackupFolder
```

---

## File Structure

Once configured, the script creates (or expects) the following layout on your system:

- **Configuration File:** `~/.config/nas-mount/config`
- **Credentials File:** `~/.config/nas-mount/.smbcreds` (Strict permissions: `600`)
- **Mount Script:** `~/.local/bin/mount-nas.sh`
- **Systemd Service:** `~/.config/systemd/user/nas-mount.service`
- **Sudoers Drop-in:** `/etc/sudoers.d/10-nas_mount_<username>`

---

## Managing the Service

You can control the mount status manually using standard `systemctl` commands (without needing `sudo`):

- **Check status:**
```
systemctl --user status nas-mount.service
```
- **Unmount shares manually:**
```
systemctl --user stop nas-mount.service
```
- **Remount/Start shares manually:**
```
systemctl --user start nas-mount.service
```

Alternatively, you can call the underlying manager script directly:
```
~/.local/bin/mount-nas.sh          # Mount all shares defined in config
~/.local/bin/mount-nas.sh stop     # Unmount all shares
```
