# MetaTrader 5 Docker Management Makefile

.PHONY: help build start stop restart status logs clean scale backup restore health monitor

# Default target
help:
	@echo "MetaTrader 5 Docker Management Commands:"
	@echo ""
	@echo "  build     - Build the MT5 Docker image"
	@echo "  start     - Start MT5 services"
	@echo "  stop      - Stop all MT5 services"
	@echo "  restart   - Restart MT5 services"
	@echo "  status    - Show status of all instances"
	@echo "  logs      - Show logs from main instance"
	@echo "  clean     - Clean up containers and images"
	@echo "  scale N   - Scale to N instances"
	@echo "  backup    - Create backup of all data"
	@echo "  restore   - Restore from latest backup"
	@echo "  health    - Run health check"
	@echo "  monitor   - Start monitoring"
	@echo ""
	@echo "Examples:"
	@echo "  make start"
	@echo "  make scale N=3"
	@echo "  make logs"

# Build the Docker image
build:
	@echo "Building MT5 Docker image..."
	docker-compose build

# Start services
start:
	@echo "Starting MT5 services..."
	./scripts/scale.sh start

# Stop services
stop:
	@echo "Stopping MT5 services..."
	./scripts/scale.sh stop

# Restart services
restart: stop start

# Show status
status:
	@echo "Checking MT5 instance status..."
	./scripts/scale.sh status

# Show logs
logs:
	@echo "Showing MT5 logs..."
	./scripts/scale.sh logs mt5-main

# Clean up
clean:
	@echo "Cleaning up containers and images..."
	docker-compose down -v --remove-orphans
	docker system prune -f

# Scale instances
scale:
	@if [ -z "$(N)" ]; then \
		echo "Error: Please specify number of instances with N=<number>"; \
		echo "Example: make scale N=3"; \
		exit 1; \
	fi
	@echo "Scaling to $(N) instances..."
	./scripts/scale.sh scale $(N)

# Create backup
backup:
	@echo "Creating backup..."
	./scripts/backup.sh backup

# Restore from backup
restore:
	@echo "Available backups:"
	@./scripts/backup.sh list
	@echo ""
	@echo "To restore, run: ./scripts/backup.sh restore <backup_file>"

# Health check
health:
	@echo "Running health check..."
	./scripts/monitor.sh health

# Start monitoring
monitor:
	@echo "Starting monitoring..."
	./scripts/monitor.sh monitor

# Development helpers
dev-start:
	@echo "Starting development environment..."
	docker-compose -f docker-compose.yml -f docker-compose.override.yml up -d

dev-logs:
	@echo "Following development logs..."
	docker-compose -f docker-compose.yml -f docker-compose.override.yml logs -f

# Quick setup for new installations
setup:
	@echo "Setting up MT5 Docker environment..."
	@if [ ! -f .env ]; then \
		echo "Creating .env file from template..."; \
		cp .env .env.backup; \
	fi
	@echo "Making scripts executable..."
	@chmod +x scripts/*.sh start.sh
	@echo "Creating required directories..."
	@mkdir -p data logs backups nginx/ssl
	@echo "Setup complete! Edit .env file and run 'make start'"

# Install system dependencies (Ubuntu/Debian)
install-deps:
	@echo "Installing Docker and Docker Compose..."
	@if ! command -v docker >/dev/null 2>&1; then \
		curl -fsSL https://get.docker.com -o get-docker.sh; \
		sudo sh get-docker.sh; \
		sudo usermod -aG docker $$USER; \
		rm get-docker.sh; \
	fi
	@if ! command -v docker-compose >/dev/null 2>&1; then \
		sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$$(uname -s)-$$(uname -m)" -o /usr/local/bin/docker-compose; \
		sudo chmod +x /usr/local/bin/docker-compose; \
	fi
	@echo "Dependencies installed. Please log out and back in to use Docker."

# Security setup
security-setup:
	@echo "Setting up security configurations..."
	@if [ ! -f nginx/ssl/cert.pem ]; then \
		echo "Generating self-signed SSL certificate..."; \
		mkdir -p nginx/ssl; \
		openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
			-keyout nginx/ssl/key.pem \
			-out nginx/ssl/cert.pem \
			-subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"; \
	fi
	@echo "SSL certificate generated in nginx/ssl/"
	@echo "Update .env to enable SSL: SSL_ENABLED=true"

# Performance testing
perf-test:
	@echo "Running performance tests..."
	@for i in $$(seq 1 5); do \
		echo "Test $$i: Checking response time..."; \
		curl -w "@curl-format.txt" -o /dev/null -s http://localhost/health; \
	done

# Update all containers
update:
	@echo "Updating containers..."
	docker-compose pull
	docker-compose up -d
	@echo "Cleaning up old images..."
	docker image prune -f