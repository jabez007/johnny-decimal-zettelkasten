#!/bin/bash

# --- CONFIGURATION ---
CONTAINER_NAME="obsidian" # Change this if your container has a different name
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
BRIDGE_SCRIPT="$BIN_DIR/obsidian-docker-bridge"
DESKTOP_FILE="$APP_DIR/obsidian-docker.desktop"

echo "Starting Obsidian-Docker URI bridge setup..."

# 1. Create bin directory if it doesn't exist
mkdir -p "$BIN_DIR"
mkdir -p "$APP_DIR"

# 2. Create the bridge script
echo "Creating bridge script at $BRIDGE_SCRIPT"
cat <<EOF > "$BRIDGE_SCRIPT"
#!/bin/bash
# Forwards the URI to the running Obsidian container
docker exec "$CONTAINER_NAME" obsidian "\$1"
EOF

chmod +x "$BRIDGE_SCRIPT"

# 3. Create the .desktop entry
echo "Creating desktop entry at $DESKTOP_FILE"
cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Name=Obsidian (Docker Bridge)
Exec=$BRIDGE_SCRIPT %u
Type=Application
Terminal=false
MimeType=x-scheme-handler/obsidian;
NoDisplay=true
EOF

# 4. Register the scheme handler
echo "Registering obsidian:// protocol..."
update-desktop-database "$APP_DIR"
xdg-settings set default-url-scheme-handler obsidian obsidian-docker.desktop

echo "Setup complete!"
echo "ote: Ensure your container name is '$CONTAINER_NAME' and it is currently running."
