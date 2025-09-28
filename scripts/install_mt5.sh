#!/bin/bash

# MT5 Installation Script
set -e

DISPLAY=:1
WINE_PREFIX=/home/mt5user/.wine
MT5_INSTALLER=/home/mt5user/mt5/mt5setup.exe
MT5_DATA_DIR=/home/mt5user/mt5data

echo "Starting MT5 installation..."

# Wait for X server to be ready
sleep 10

# Install MT5 if not already installed
if [ ! -d "$WINE_PREFIX/drive_c/Program Files/MetaTrader 5" ]; then
    echo "Installing MetaTrader 5..."

    # Run MT5 installer silently
    DISPLAY=:1 wine "$MT5_INSTALLER" /S

    # Wait for installation to complete
    sleep 30

    echo "MT5 installation completed."
else
    echo "MT5 already installed."
fi

# Configure MT5 data directory
if [ ! -d "$MT5_DATA_DIR" ]; then
    mkdir -p "$MT5_DATA_DIR"
fi

# Start MT5 if login credentials are provided
if [ -n "$MT5_LOGIN" ] && [ -n "$MT5_PASSWORD" ] && [ -n "$MT5_SERVER" ]; then
    echo "Starting MT5 with auto-login..."

    # Create config file for auto-login
    cat > /tmp/mt5_config.ini << EOF
[Login]
Login=$MT5_LOGIN
Password=$MT5_PASSWORD
Server=$MT5_SERVER
EOF

    # Start MT5 with configuration
    DISPLAY=:1 wine "$WINE_PREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" /config:/tmp/mt5_config.ini &
else
    echo "Starting MT5 without auto-login..."
    DISPLAY=:1 wine "$WINE_PREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" &
fi

# Keep the script running
while true; do
    sleep 60
    # Check if MT5 is still running
    if ! pgrep -f "terminal64.exe" > /dev/null; then
        echo "MT5 process not found, restarting..."
        DISPLAY=:1 wine "$WINE_PREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe" &
    fi
done