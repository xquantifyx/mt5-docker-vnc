# MetaTrader 5 Docker Deployment

Deploy MetaTrader 5 on Ubuntu VPS with Docker, Wine, and noVNC for browser-based access. This solution provides easy management, scaling, and monitoring capabilities.

## Features

- 🖥️ **Browser Access**: Access MT5 through any web browser via noVNC
- 🐳 **Docker-based**: Containerized deployment for easy management
- 🍷 **Wine Integration**: Runs MT5 Windows application on Linux
- 📈 **Auto-scaling**: Scale multiple MT5 instances automatically
- 📊 **Monitoring**: Built-in health checks and monitoring
- 🔒 **Security**: Configurable security features and SSL support
- 💾 **Backup**: Automated backup and restore functionality
- ⚡ **Load Balancing**: Nginx-based load balancing for multiple instances

## Quick Start

### Prerequisites

- Ubuntu 18.04+ or compatible Linux distribution
- Docker and Docker Compose installed
- At least 2GB RAM and 10GB disk space
- Open ports: 80, 443, 5901, 6080

### Installation

1. **Clone or create the project directory:**
```bash
mkdir mt5-docker && cd mt5-docker
# Copy all files from this repository
```

2. **Configure environment:**
```bash
cp .env.example .env
# Edit .env with your settings
nano .env
```

3. **Make scripts executable:**
```bash
chmod +x scripts/*.sh
```

4. **Build and start:**
```bash
docker-compose build
./scripts/scale.sh start
```

5. **Access MT5:**
- Open browser: `http://your-server-ip`
- Or direct VNC: `your-server-ip:5901`

## Configuration

### Environment Variables

Edit `.env` file to configure:

```bash
# VNC Password
VNC_PASSWORD=your_secure_password

# MT5 Credentials (optional auto-login)
MT5_LOGIN=your_login
MT5_PASSWORD=your_password
MT5_SERVER=your_broker_server

# Monitoring
ALERT_EMAIL=support@xquantify.com
WEBHOOK_URL=https://hooks.slack.com/your-webhook

# Security
ALLOWED_IPS=192.168.1.0/24,10.0.0.0/8
```

### SSL Configuration

For HTTPS access:

1. **Generate SSL certificate:**
```bash
mkdir -p nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/key.pem \
  -out nginx/ssl/cert.pem
```

2. **Enable SSL in `.env`:**
```bash
SSL_ENABLED=true
```

3. **Restart services:**
```bash
./scripts/scale.sh stop
./scripts/scale.sh start
```

## Management Commands

### Scaling Operations

```bash
# Start main instance
./scripts/scale.sh start

# Scale to 3 instances
./scripts/scale.sh scale 3

# Create named instance
./scripts/scale.sh create mt5-client1

# Check status
./scripts/scale.sh status

# View logs
./scripts/scale.sh logs mt5-main

# Stop all instances
./scripts/scale.sh stop
```

### Monitoring

```bash
# Health check
./scripts/monitor.sh health

# Continuous monitoring
./scripts/monitor.sh monitor

# View metrics
./scripts/monitor.sh metrics

# Test alerts
./scripts/monitor.sh alerts
```

### Backup & Restore

```bash
# Full backup
./scripts/backup.sh backup

# Backup specific instance
./scripts/backup.sh backup mt5-main

# List backups
./scripts/backup.sh list

# Restore from backup
./scripts/backup.sh restore backups/mt5_full_backup_20241027_120000.tar.gz

# Cleanup old backups (>30 days)
./scripts/backup.sh cleanup 30
```

## Architecture

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Browser   │    │   Browser   │    │   Browser   │
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘
       │                  │                  │
       └──────────────────┼──────────────────┘
                          │
                   ┌──────┴──────┐
                   │    Nginx    │ (Load Balancer)
                   │  (Port 80)  │
                   └──────┬──────┘
                          │
         ┌────────────────┼────────────────┐
         │                │                │
  ┌──────┴──────┐  ┌──────┴──────┐  ┌──────┴──────┐
  │ MT5 Instance│  │ MT5 Instance│  │ MT5 Instance│
  │   (6080)    │  │   (6081)    │  │   (6082)    │
  └─────────────┘  └─────────────┘  └─────────────┘
  │ Wine + MT5  │  │ Wine + MT5  │  │ Wine + MT5  │
  │ X11 + VNC   │  │ X11 + VNC   │  │ X11 + VNC   │
  │   noVNC     │  │   noVNC     │  │   noVNC     │
  └─────────────┘  └─────────────┘  └─────────────┘
```

## Security Considerations

### Recommended Security Measures

1. **Change default passwords:**
```bash
# In .env file
VNC_PASSWORD=your_strong_password
```

2. **Configure firewall:**
```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

3. **Use SSL certificates:**
```bash
# Enable SSL in configuration
SSL_ENABLED=true
```

4. **Restrict IP access:**
```bash
# In .env file
ALLOWED_IPS=your.office.ip/32,192.168.1.0/24
```

5. **Regular updates:**
```bash
# Enable automatic updates
docker run -d --name watchtower \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower --cleanup
```

## Troubleshooting

### Common Issues

1. **Container won't start:**
```bash
# Check logs
docker-compose logs mt5-instance

# Check resources
docker system df
free -h
```

2. **No display/black screen:**
```bash
# Restart X11 services
docker-compose restart mt5-instance

# Check VNC connection
netstat -tuln | grep 5901
```

3. **High CPU usage:**
```bash
# Monitor resources
./scripts/monitor.sh metrics

# Adjust resource limits in docker-compose.yml
```

4. **Wine issues:**
```bash
# Reset Wine prefix
docker-compose exec mt5-instance wine wineboot --init

# Install additional components
docker-compose exec mt5-instance winetricks
```

### Performance Optimization

1. **Adjust memory limits:**
```yaml
# In docker-compose.yml
services:
  mt5-instance:
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G
```

2. **Optimize Wine settings:**
```bash
# Edit configs/wine.conf
[HKEY_CURRENT_USER\Software\Wine\Direct3D]
"VideoMemorySize"="2048"
```

3. **Use SSD storage:**
```bash
# Mount data on SSD
volumes:
  - /path/to/ssd/mt5-data:/home/mt5user/mt5data
```

## Development

### Building Custom Images

```bash
# Build with custom MT5 installer
docker build --build-arg MT5_INSTALLER_URL=https://your-broker.com/mt5setup.exe .

# Build with debugging enabled
docker build --build-arg DEBUG=true .
```

### Adding Custom Scripts

1. Place scripts in `scripts/` directory
2. Make executable: `chmod +x scripts/your-script.sh`
3. Rebuild container: `docker-compose build`

## Support

### Logs Location

- Container logs: `./logs/`
- Docker logs: `docker-compose logs`
- System logs: `/var/log/`

### Getting Help

1. Check logs: `./scripts/monitor.sh health`
2. View metrics: `./scripts/monitor.sh metrics`
3. Test connectivity: `curl http://localhost:6080/`

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## Changelog

### v1.0.0
- Initial release with basic MT5 deployment
- Docker-based containerization
- noVNC browser access
- Basic scaling capabilities

### v1.1.0
- Added monitoring and health checks
- Implemented backup/restore functionality
- Added SSL support
- Enhanced security features

## Roadmap

- [ ] API for programmatic management
- [ ] Kubernetes deployment manifests
- [ ] Multi-broker support
- [ ] Advanced trading analytics
- [ ] Mobile-responsive interface