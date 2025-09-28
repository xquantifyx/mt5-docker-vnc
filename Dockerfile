FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV VNC_PORT=5901
ENV NOVNC_PORT=6080
ENV WINE_PREFIX=/home/mt5user/.wine
ENV WINEARCH=win64

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    xvfb \
    x11vnc \
    fluxbox \
    supervisor \
    nodejs \
    npm \
    git \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Wine
RUN dpkg --add-architecture i386 && \
    mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable winetricks && \
    rm -rf /var/lib/apt/lists/*

# Install noVNC
RUN git clone https://github.com/novnc/noVNC.git /opt/novnc && \
    git clone https://github.com/novnc/websockify /opt/novnc/utils/websockify && \
    chmod +x /opt/novnc/utils/novnc_proxy

# Create user for MT5
RUN useradd -m -s /bin/bash mt5user && \
    usermod -aG sudo mt5user && \
    echo "mt5user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to mt5user
USER mt5user
WORKDIR /home/mt5user

# Initialize Wine prefix
RUN wine wineboot --init && \
    winetricks -q corefonts vcrun2019 && \
    wine reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "mscoree" /d "disabled" /f && \
    wine reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "mshtml" /d "disabled" /f

# Create directories
RUN mkdir -p /home/mt5user/mt5 /home/mt5user/logs /home/mt5user/.vnc

# Download MetaTrader 5 installer (you can replace with your preferred broker's MT5)
RUN wget -O /home/mt5user/mt5/mt5setup.exe "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"

# Copy configuration files
COPY --chown=mt5user:mt5user configs/ /home/mt5user/configs/
COPY --chown=mt5user:mt5user scripts/ /home/mt5user/scripts/

# Switch back to root to copy supervisor config
USER root
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Create startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Expose ports
EXPOSE 5901 6080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:6080/ || exit 1

# Start services
CMD ["/start.sh"]