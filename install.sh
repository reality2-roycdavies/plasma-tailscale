#!/usr/bin/env bash
set -e

APPLET_ID="org.tailscale.monitor"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/$APPLET_ID"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Tailscale Monitor plasmoid..."

# Install plasmoid
if command -v kpackagetool6 &>/dev/null; then
    if [ -d "$PLASMOID_DIR" ]; then
        echo "Upgrading existing plasmoid..."
        kpackagetool6 --type Plasma/Applet --upgrade "$SCRIPT_DIR" 2>/dev/null || {
            echo "Upgrade failed, reinstalling..."
            rm -rf "$PLASMOID_DIR"
            kpackagetool6 --type Plasma/Applet --install "$SCRIPT_DIR"
        }
    else
        kpackagetool6 --type Plasma/Applet --install "$SCRIPT_DIR"
    fi
else
    echo "kpackagetool6 not found, copying manually..."
    mkdir -p "$PLASMOID_DIR/contents/ui"
    mkdir -p "$PLASMOID_DIR/contents/tools"
    mkdir -p "$PLASMOID_DIR/contents/icons"
    cp "$SCRIPT_DIR/metadata.json" "$PLASMOID_DIR/"
    cp "$SCRIPT_DIR/contents/ui/main.qml" "$PLASMOID_DIR/contents/ui/"
    cp "$SCRIPT_DIR/contents/tools/tailscale-status.py" "$PLASMOID_DIR/contents/tools/"
    cp "$SCRIPT_DIR/contents/icons/"*.svg "$PLASMOID_DIR/contents/icons/"
fi

chmod +x "$PLASMOID_DIR/contents/tools/tailscale-status.py"

echo ""
echo "Done! To add the widget to your panel:"
echo "  1. Right-click on the panel -> 'Add Widgets...'"
echo "  2. Search for 'Tailscale Monitor'"
echo "  3. Drag it to the panel"
echo ""
echo "If the widget doesn't appear, restart Plasma:"
echo "  kquitapp6 plasmashell && kstart plasmashell"
