#!/usr/bin/env bash

set -e  # Exit on error

echo "======================================"
echo "Nix Configuration Installation Script"
echo "======================================"
echo ""

# Step 1: Install Nix using Determinate Systems installer
echo "[1/5] Installing Nix..."
if command -v nix &> /dev/null; then
    echo "Nix is already installed. Skipping installation."
else
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    echo "Nix installed successfully!"
fi
echo ""

# Step 2: Backup /etc files
echo "[2/5] Backing up /etc files..."

# Backup /etc/shells
if [ -f /etc/shells ] && [ ! -f /etc/shells.before-nix-darwin ]; then
    sudo mv /etc/shells /etc/shells.before-nix-darwin
    echo "/etc/shells backed up to /etc/shells.before-nix-darwin"
elif [ -f /etc/shells.before-nix-darwin ]; then
    echo "/etc/shells.before-nix-darwin already exists. Skipping backup."
else
    echo "/etc/shells does not exist. Skipping backup."
fi

# Backup /etc/zshenv
if [ -f /etc/zshenv ] && [ ! -f /etc/zshenv.before-nix-darwin ]; then
    sudo mv /etc/zshenv /etc/zshenv.before-nix-darwin
    echo "/etc/zshenv backed up to /etc/zshenv.before-nix-darwin"
elif [ -f /etc/zshenv.before-nix-darwin ]; then
    echo "/etc/zshenv.before-nix-darwin already exists. Skipping backup."
else
    echo "/etc/zshenv does not exist. Skipping backup."
fi
echo ""

# Step 3: Capture system information
echo "[3/5] Capturing system information..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_INFO_NIX="$SCRIPT_DIR/host-info.nix"

# Tell git to ignore local changes to this file (must be done before modifying)
git update-index --skip-worktree "$HOST_INFO_NIX" 2>/dev/null || true

# Create Nix version for use in flake.nix
cat > "$HOST_INFO_NIX" << EOF
# Auto-generated host information for Nix flake
# This file is created by install.sh
{
  hostname = "$(hostname -s)";
  username = "$USER";
  homedir = "$HOME";
  flakedir = "$SCRIPT_DIR";
}
EOF

echo "System information saved:"
echo "  Nix:   $HOST_INFO_NIX"
echo ""
echo "  HOSTNAME: $(hostname -s)"
echo "  USER: $USER"
echo "  HOME: $HOME"
echo ""

# Step 4: Run nix-darwin switch (system-level configuration)
echo "[4/5] Running nix-darwin switch..."
echo "This will configure system-level settings (requires sudo)"
echo ""

# Source the Nix environment if it exists
if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

sudo -H nix run nix-darwin -- switch --flake $SCRIPT_DIR

echo ""
echo "nix-darwin configuration applied successfully!"
echo ""

# Step 5: Run home-manager switch (user-level configuration)
echo "[5/5] Running home-manager switch..."
echo "This will configure user-level settings (no sudo required)"
echo ""

nix run home-manager/master -- switch --flake $SCRIPT_DIR

echo ""
echo "======================================"
echo "Installation Complete!"
echo "======================================"
echo ""
echo "Your system has been configured with:"
echo "  - nix-darwin (system-level)"
echo "  - home-manager (user-level)"
echo ""
echo "You may need to restart your terminal or run:"
echo "  source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
echo ""
echo "To apply future configuration changes:"
echo ""
echo "  System changes (requires sudo, use rarely):"
echo "    sudo -H darwin-rebuild switch --flake $SCRIPT_DIR"
echo "    Or use the fish alias: dr:switch"
echo ""
echo "  User changes (no sudo, use for most updates):"
echo "    home-manager switch --flake $SCRIPT_DIR"
echo "    Or use the fish alias: hm:switch"
