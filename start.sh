#!/bin/bash

# Start script for MT5 Docker container
set -e

echo "Starting MT5 Docker container..."

# Set VNC password
if [ -n "$VNC_PASSWORD" ]; then
    echo "$VNC_PASSWORD" | vncpasswd -f > /home/mt5user/.vnc/passwd
    chmod 600 /home/mt5user/.vnc/passwd
fi

# Create necessary directories
mkdir -p /home/mt5user/.vnc /home/mt5user/logs /home/mt5user/mt5data

# Set proper ownership
chown -R mt5user:mt5user /home/mt5user/

# Start supervisor as mt5user
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf