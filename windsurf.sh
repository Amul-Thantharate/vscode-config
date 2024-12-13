#!/bin/bash

# Exit script immediately on any error
set -e

# Ensure this script is run as root (with sudo privileges)
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo privileges"
    exit 1
fi

# Check and install 'jq' if it is not already installed
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Installing jq..."
    if command -v dnf &> /dev/null; then
        dnf install -y jq
    elif command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y jq
    elif command -v pacman &> /dev/null; then
        pacman -Sy --noconfirm jq
    else
        echo "Error: Could not install jq. Please install it manually."
        exit 1
    fi
fi

# Define installation paths and variables
INSTALL_DIR="/opt/windsurf"
DESKTOP_FILE="/usr/share/applications/windsurf.desktop"
ICON_DIR="/usr/share/icons/hicolor/128x128/apps"
BINARY_LINK="/usr/local/bin/windsurf"
TEMP_DIR="/tmp/windsurf_install"

# Fetch the latest version info and download URL
echo "Fetching latest version information..."
VERSION_INFO=$(curl -s "https://windsurf-stable.codeium.com/api/update/linux-x64/stable/latest")
DOWNLOAD_URL=$(echo "$VERSION_INFO" | jq -r '.url')
VERSION=$(echo "$VERSION_INFO" | jq -r '.windsurfVersion')
SHA256HASH=$(echo "$VERSION_INFO" | jq -r '.sha256hash')

echo "Latest version: $VERSION"
echo "Download URL: $DOWNLOAD_URL"

# Check if Windsurf is already installed and get current version
CURRENT_VERSION=""
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/version" ]; then
    CURRENT_VERSION=$(cat "$INSTALL_DIR/version")
    echo "Current installed version: $CURRENT_VERSION"
    
    if [ "$CURRENT_VERSION" = "$VERSION" ]; then
        echo "Already running the latest version ($VERSION). No update needed."
        exit 0
    fi
fi

# Create temporary directory for download
echo "Creating temporary directory..."
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download Windsurf package
echo "Downloading Windsurf $VERSION..."
curl -L "$DOWNLOAD_URL" -o windsurf.tar.gz || { echo "Error: Failed to download Windsurf"; exit 1; }

# Verify the integrity of downloaded package using SHA256 checksum
echo "Verifying download integrity..."
DOWNLOADED_HASH=$(sha256sum windsurf.tar.gz | cut -d' ' -f1)
if [ "$DOWNLOADED_HASH" != "$SHA256HASH" ]; then
    echo "Error: Download verification failed. SHA256 hash mismatch."
    echo "Expected: $SHA256HASH"
    echo "Got: $DOWNLOADED_HASH"
    rm -f windsurf.tar.gz
    exit 1
fi

# After successful download and verification, handle existing installation
if [ -d "$INSTALL_DIR" ]; then
    echo "Existing Windsurf installation detected."
    echo "Performing upgrade..."
    BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    echo "Creating backup at $BACKUP_DIR"
    mv "$INSTALL_DIR" "$BACKUP_DIR"
    # Remove old backups if there are more than 3
    BACKUP_COUNT=$(find "$(dirname "${INSTALL_DIR}")" -maxdepth 1 -name "$(basename "${INSTALL_DIR}_backup_*")" -type d | wc -l)
    if [ "$BACKUP_COUNT" -gt 3 ]; then
        echo "More than 3 backups found. Deleting oldest..."
        find "$(dirname "${INSTALL_DIR}")" -maxdepth 1 -name "$(basename "${INSTALL_DIR}_backup_*")" -type d -print0 | xargs -0 ls -dt | tail -n +4 | xargs rm -rf
    fi
    echo "Cleaning up old installation..."
    rm -f "$BINARY_LINK" "$DESKTOP_FILE" "$ICON_DIR/windsurf.png"
else
    echo "Performing fresh installation..."
fi

# Create necessary directories for installation
echo "Creating installation directories..."
mkdir -p "$INSTALL_DIR" "$ICON_DIR" "$(dirname "$DESKTOP_FILE")"

# Extract downloaded package to the installation directory
echo "Extracting Windsurf..."
tar --strip-components=1 -xzf windsurf.tar.gz -C "$INSTALL_DIR" || { echo "Error: Failed to extract Windsurf"; rm -f windsurf.tar.gz; exit 1; }

# Set permissions for the installed files
echo "Setting permissions..."
chown -R root:root "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"
ln -s "$INSTALL_DIR/windsurf" "$BINARY_LINK" && chmod 755 "$INSTALL_DIR/windsurf"

# Create version file
echo "$VERSION" > "$INSTALL_DIR/version"
chmod 644 "$INSTALL_DIR/version"

# Install application icon if exists
echo "Installing icon..."
ICON_PATH="$INSTALL_DIR/resources/app/resources/linux/code.png"
[ -f "$ICON_PATH" ] && cp "$ICON_PATH" "$ICON_DIR/windsurf.png" && chmod 644 "$ICON_DIR/windsurf.png" || echo "Warning: Icon not found in the package, application icon might not display correctly"

# Create desktop entry for the application
echo "Creating desktop entry..."
cat > "$DESKTOP_FILE" << EOL
[Desktop Entry]
Name=Windsurf
Comment=Windsurf IDE (Version $VERSION)
Exec=$BINARY_LINK
Icon=windsurf
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=Windsurf
EOL
chmod 644 "$DESKTOP_FILE"

# Clean up temporary files and directories
echo "Cleaning up..."
cd /
rm -rf "$TEMP_DIR"

# Update system caches for icons and desktop entries
echo "Updating icon cache..."
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f -t /usr/share/icons/hicolor

echo "Updating desktop database..."
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database /usr/share/applications

echo "Installation complete!"
echo "Windsurf version $VERSION has been installed to $INSTALL_DIR"
echo "You can run it by typing 'windsurf' in the terminal or launching it from your application menu"
echo "You may need to log out and log back in for the desktop icon to appear."

# Verify if installation was successful
if [ -f "$BINARY_LINK" ] && [ -f "$DESKTOP_FILE" ]; then
    echo "Installation verification successful!"
else
    echo "Warning: Installation verification failed. Please check the error messages above."
    exit 1
fi
