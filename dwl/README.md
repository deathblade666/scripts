# dwl Update Staging Workflow Script

A Bash automation script designed to safely stage, patch, configure, and compile updates for **dwl** (a Wayland compositor based on wlroots). It clones upstream sources, targets versioned Arch Linux wlroots slots, carries over custom configurations, applies patches automatically, and performs a dry-run build check.

---

## Features

- **Automated Staging:** Cleans up previous staging attempts and performs a shallow git clone of the target upstream version (`main` or custom branches) from Codeberg.
- **Wlroots Version Slotting:** Automatically patches `config.mk` to target versioned wlroots packages (e.g., Arch Linux's `wlroots0.18`).
- **Configuration Preservation:** Automatically carries over your existing `config.h` from your working source directory, falling back to `config.def.h` if none exists.
- **Batch Patching:** Iterates through a dedicated patch directory and applies version-compatible `.patch` files using standard Unix `patch`, halting safely if any patch conflicts.
- **Dry-Run Compilation:** Compiles the staged build immediately to guarantee that everything builds cleanly before you decide to deploy.

---

## Prerequisites

Ensure the following tools and libraries are installed on your system:
- Bash (v4+)
- `git`
- `make`
- `gcc` or a compatible C compiler
- `patch` (GNU patch utility)
- Versioned `wlroots` development packages (e.g., `wlroots0.18` and its corresponding pkg-config files)

---

## Configuration Variables

At the top of the script, you can adjust the following variables to match your directory layout and version requirements:
- `TARGET_VER="main"`: The git branch or tag of dwl to fetch.
- `WLR_SLOT="wlroots0.18"`: The pkg-config package name for your installed wlroots slot.
- `SRC_DIR`: The path to your current working dwl source directory (where your active `config.h` lives).
- `STAGING_DIR`: The path where the script checks out and builds the new dwl version.
- `PATCH_DIR`: The path to your local patch folder.

---

## Installation & Usage

1. Save the script to a file (e.g., `stage-dwl.sh`).
2. Make the script executable:
```
chmod +x stage-dwl.sh
```
3. Run the script:
```
./stage-dwl.sh
```

---

## Manual Directory Setup (Optional)

If you prefer to configure your environment structure manually before running the script, ensure your paths match the script's expectations:
```
mkdir -p ~/Developement/dwl/current
mkdir -p ~/Developement/dwl/dwl-patches
```

---

## Deploying After a Successful Build

If the script compiles the staging environment cleanly, you can deploy the new build permanently by executing:
```
cd ~/Developement/dwl/dwl-staging-main && sudo make install
```
