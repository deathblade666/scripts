#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- CONFIGURATION ---
TARGET_VER=""
WLR_SLOT=""
SRC_DIR=""
STAGING_DIR=""
PATCH_DIR=""

echo "=== Starting dwl Update Staging Workflow ==="

# 1. Clean up any previous staging attempts
if [ -d "$STAGING_DIR" ]; then
    echo "--> Cleaning up old staging directory..."
    rm -rf "$STAGING_DIR"
fi

# 2. Clone fresh upstream target version
echo "--> Fetching clean dwl source ($TARGET_VER)..."
git clone --depth 1 --branch "$TARGET_VER" https://codeberg.org/dwl/dwl "$STAGING_DIR"
cd "$STAGING_DIR"

# 3. Patch config.mk to point to the correct Arch wlroots slot
echo "--> Injecting Arch wlroots slot configuration ($WLR_SLOT)..."
if [ -f "config.mk" ]; then
    # Safely substitute standard wlroots strings with versioned package
    sed -i "s/pkg-config --libs wlroots/pkg-config --libs $WLR_SLOT/g" config.mk
    sed -i "s/pkg-config --cflags wlroots/pkg-config --cflags $WLR_SLOT/g" config.mk
    # Catch any variations where it targets just 'wlroots' variable directly
    sed -i "s/wlroots/ $WLR_SLOT /g" Makefile 2>/dev/null || true
else
    echo "⚠️ Warning: config.mk not found, verify build system changes."
fi

# 4. Bring over your custom config template
if [ -f "$SRC_DIR/config.h" ]; then
    echo "--> Copying your existing config.h to staging..."
    cp "$SRC_DIR/config.h" "$STAGING_DIR/config.h"
else
    echo "--> No previous config.h found. Creating template..."
    cp config.def.h config.h
fi

# 5. Apply automated patches
if [ -d "$PATCH_DIR" ] && [ "$(ls -A $PATCH_DIR)" ]; then
    echo "--> Applying version-compatible patches from $PATCH_DIR..."
    for patch in "$PATCH_DIR"/*; do
        # Ignore non-patch files if any exist
        [[ "$patch" != *.patch ]] && continue
        
        echo "   Applying: $(basename "$patch")"
        # Switch from git apply to gnu patch with a merge fallback
        if patch -p1 --forward < "$patch"; then
            echo "   ✅ Success"
        else
            echo "   ❌ Patch failed! Halting for manual intervention."
            exit 1
        fi
    done
fi

# 6. Build and Test Compile
echo "--> Attempting dry run compilation..."
if make; then
    echo "=================================================="
    echo " 🎉 STAGING COMPILED CLEANLY FOR $TARGET_VER!"
    echo "=================================================="
    echo "To deploy this build permanently, run:"
    echo "cd $STAGING_DIR && sudo make install"
    echo "=================================================="
else
    echo "❌ Build failed. Check the error log above."
    exit 1
fi

