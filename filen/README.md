# Filen CLI Automated Backup System

An automated, configuration-driven backup script for [Filen Cloud](https://filen.io/) utilizing the official Filen CLI. It supports multi-folder sync pairs, custom ignore rules, dry-run testing, automated daily cron scheduling, and Discord webhook notifications.

---

## Features

- **Automated Installation & Setup**: Fetches the latest Filen CLI release for your platform (Linux/macOS) and links it globally.
- **Credential Management**: Securely prompts for credentials and a 2FA recovery key, saving them in the format required by the CLI.
- **Dynamic Sync Pairs**: Define multiple local-to-cloud directories using a clean pipe-delimited configuration file (`sync_pairs.conf`).
- **Custom Ignore Support**: Parses dedicated ignore pattern files per sync pair using `jq`.
- **Dry-Run Mode**: Test your configuration safely before committing changes.
- **Cron Automation**: Automatically registers a daily backup task at 2:00 AM.
- **Discord Webhook Alerts**: Sends instant status updates (Success/Failure embeds) directly to a Discord channel.

---

## File Structure

```text
├── bootstrap.sh            # Initial installation and configuration script
├── backup.sh           # Core backup synchronization engine
├── sync_pairs.conf     # Configuration file for your sync folders
├── ignores/            # Directory containing custom ignore pattern files
└── .filen-cli-credentials # Hidden credential file generated during setup
```

## Prerequisites

Ensure the following tools are installed on your system before running the scripts:

  - ``curl``
  -  ``jq`` (required for generating dynamic JSON configurations for ignore lists)
  - ``cron`` (for automated scheduling)

## Install & Setup

1. Place ``bootstrap.sh`` and ``backup.sh`` into your chosen working directory.
2. Make both scripts executable:

```bash
chmod +x bootstrap.sh backup.sh
```
3. Run the booststrap:

```bash
./bootstrap.sh
```

(Note: If you run the script with sudo, it will automatically detect your user account and ensure all local configuration and data files remain owned by you rather than root).

The bootstrap script will:

  - Install or update the Filen CLI.
  - Prompt you for your Filen credentials and 2FA recovery key (if enabled).
  - Create an ``ignores/`` folder if it doesn't already exist.
  - Generate a ``sync_pairs.conf`` template if one is missing.
  - Give you options to run a dry-run test or set up a daily 2:00 AM cron job.

## Configuration

1. Defining Sync Pairs (``sync_pairs.conf``)

Open ``sync_pairs.conf`` and configure your directories using the following pipe-delimited format:

```text
# Format: LOCAL_PATH | REMOTE_PATH | IGNORE_FILE | SYNC_MODE
/srv/samba/media | /Backup/Media | ignores/media.filenignore | localToCloud
```

  - ``LOCAL_PATH``: Absolute path to the folder on your local machine.
  - ``REMOTE_PATH``: Destination path within your Filen cloud storage.
  - ``IGNORE_FILE``: Path to a custom ignore file (relative to the script directory). Leave blank or omit if not needed.
  - ``SYNC_MODE``: Synchronization mode determining the direction of the transfer. Valid options include:
    - `twoWay`: Mirrors changes in both directions between local and cloud storage.
    - `localToCloud`: Uploads files from local storage to the remote cloud (default if left blank).
    - `cloudToLocal`: Downloads files from the remote cloud to local storage.
    - `localBackup`: Uploads files to the cloud without deleting cloud files on local deletions.
    - `cloudBackup`: Downloads files locally without deleting local files on cloud deletions.

2. Setting Ignore Rules
Place any ignore files inside the ``ignores/`` directory (matching what you define in ``sync_pairs.conf``, e.g., ``ignores/media.filenignore``). Each line represents a pattern to exclude:
```text
# Ignore temp files and thumbnails
*.tmp
.DS_Store
Thumbs.db
```

3. Configuring Discord Notifications

Open ``backup.sh`` and paste your Discord Webhook URL into the configuration block near the top:
```bash
# --- CONFIGURATION ---
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/your_webhook_id/your_webhook_token"
# ---------------------
```

If left blank or set to ``"YOUR_WEBHOOK_URL_HERE"``, webhook notifications will be skipped silently.

## Usage
Running a Manual Backup

To run the backup immediately on demand:
```bash
./backup.sh
```

## Running a Dry Run
To test your sync configuration and inspect the generated JSON mapping without actually uploading or transferring files:
```bash
./backup.sh --dry-run
```

