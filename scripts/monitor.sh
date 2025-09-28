#!/bin/bash

# MT5 Monitoring and Health Check Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Monitoring configuration
CHECK_INTERVAL=30
LOG_FILE="$PROJECT_DIR/logs/monitor.log"
ALERT_EMAIL="${ALERT_EMAIL:-}"
WEBHOOK_URL="${WEBHOOK_URL:-}"

usage() {
    echo "Usage: $0 {health|monitor|alerts|metrics} [options]"
    echo ""
    echo "Commands:"
    echo "  health                   Check health of all instances"
    echo "  monitor                  Start continuous monitoring"
    echo "  alerts                   Send test alerts"
    echo "  metrics                  Show detailed metrics"
    echo ""
    echo "Environment variables:"
    echo "  ALERT_EMAIL             Email for alerts"
    echo "  WEBHOOK_URL             Webhook URL for alerts"
    echo "  CHECK_INTERVAL          Check interval in seconds (default: 30)"
}

log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

check_container_health() {
    local container_name=$1
    local status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "not_found")

    case $status in
        "healthy")
            echo -e "${GREEN}✓${NC} $container_name: Healthy"
            return 0
            ;;
        "unhealthy")
            echo -e "${RED}✗${NC} $container_name: Unhealthy"
            return 1
            ;;
        "starting")
            echo -e "${YELLOW}⚠${NC} $container_name: Starting"
            return 2
            ;;
        "not_found")
            echo -e "${RED}✗${NC} $container_name: Not found"
            return 3
            ;;
        *)
            echo -e "${YELLOW}?${NC} $container_name: Unknown status ($status)"
            return 2
            ;;
    esac
}

check_service_connectivity() {
    local container_name=$1
    local port=$2

    if timeout 5 docker exec "$container_name" curl -f "http://localhost:$port/" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $container_name: Service responding on port $port"
        return 0
    else
        echo -e "${RED}✗${NC} $container_name: Service not responding on port $port"
        return 1
    fi
}

check_resource_usage() {
    local container_name=$1

    local stats=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}" "$container_name" 2>/dev/null)

    if [ -n "$stats" ]; then
        IFS=',' read -r cpu_percent mem_usage mem_percent <<< "$stats"

        # Remove % sign for comparison
        cpu_num=$(echo "$cpu_percent" | tr -d '%')
        mem_num=$(echo "$mem_percent" | tr -d '%')

        echo "  CPU: $cpu_percent, Memory: $mem_usage ($mem_percent)"

        # Alert thresholds
        if (( $(echo "$cpu_num > 80" | bc -l) )); then
            log_message "WARNING" "$container_name: High CPU usage: $cpu_percent"
        fi

        if (( $(echo "$mem_num > 80" | bc -l) )); then
            log_message "WARNING" "$container_name: High memory usage: $mem_percent"
        fi
    fi
}

perform_health_check() {
    echo -e "${GREEN}=== MT5 Health Check ===${NC}"
    echo "Timestamp: $(date)"
    echo ""

    local overall_status=0
    local instances=$(docker ps --filter "label=app=mt5" --format "{{.Names}}")

    if [ -z "$instances" ]; then
        echo -e "${RED}No MT5 instances running${NC}"
        return 1
    fi

    for instance in $instances; do
        echo "Checking $instance..."

        # Check container health
        if ! check_container_health "$instance"; then
            overall_status=1
        fi

        # Check service connectivity
        local port=$(docker port "$instance" 6080 | cut -d: -f2)
        if [ -n "$port" ]; then
            if ! check_service_connectivity "$instance" 6080; then
                overall_status=1
            fi
        fi

        # Check resource usage
        check_resource_usage "$instance"

        echo ""
    done

    if [ $overall_status -eq 0 ]; then
        echo -e "${GREEN}Overall status: All systems healthy${NC}"
        log_message "INFO" "Health check passed - all systems healthy"
    else
        echo -e "${RED}Overall status: Issues detected${NC}"
        log_message "ERROR" "Health check failed - issues detected"
        send_alert "MT5 Health Check Failed" "Some MT5 instances are experiencing issues. Check the logs for details."
    fi

    return $overall_status
}

send_alert() {
    local subject=$1
    local message=$2

    log_message "ALERT" "$subject: $message"

    # Send email alert if configured
    if [ -n "$ALERT_EMAIL" ]; then
        echo "$message" | mail -s "$subject" "$ALERT_EMAIL" 2>/dev/null || \
            log_message "ERROR" "Failed to send email alert to $ALERT_EMAIL"
    fi

    # Send webhook alert if configured
    if [ -n "$WEBHOOK_URL" ]; then
        curl -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"$subject: $message\"}" \
            2>/dev/null || log_message "ERROR" "Failed to send webhook alert"
    fi
}

start_monitoring() {
    echo -e "${GREEN}Starting continuous monitoring...${NC}"
    echo "Check interval: $CHECK_INTERVAL seconds"
    echo "Log file: $LOG_FILE"
    echo "Press Ctrl+C to stop"
    echo ""

    mkdir -p "$(dirname "$LOG_FILE")"

    while true; do
        if ! perform_health_check; then
            log_message "ERROR" "Health check failed during monitoring"
        fi

        echo "Next check in $CHECK_INTERVAL seconds..."
        echo "=================================="
        sleep "$CHECK_INTERVAL"
    done
}

show_metrics() {
    echo -e "${GREEN}=== MT5 Detailed Metrics ===${NC}"
    echo ""

    # Docker stats
    echo "Container Resource Usage:"
    docker stats --no-stream --filter "label=app=mt5" --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
    echo ""

    # Disk usage
    echo "Data Directory Usage:"
    if [ -d "$PROJECT_DIR/data" ]; then
        du -sh "$PROJECT_DIR/data"/* 2>/dev/null | sort -hr || echo "No data directories found"
    fi
    echo ""

    # Log file sizes
    echo "Log File Sizes:"
    if [ -d "$PROJECT_DIR/logs" ]; then
        find "$PROJECT_DIR/logs" -name "*.log" -exec du -sh {} \; | sort -hr | head -10
    fi
    echo ""

    # Network connections
    echo "Network Connections:"
    docker ps --filter "label=app=mt5" --format "table {{.Names}}\t{{.Ports}}"
}

test_alerts() {
    echo -e "${GREEN}Testing alert system...${NC}"

    if [ -n "$ALERT_EMAIL" ]; then
        echo "Testing email alerts to: $ALERT_EMAIL"
        send_alert "MT5 Alert Test" "This is a test alert from the MT5 monitoring system."
    else
        echo "Email alerts not configured (ALERT_EMAIL not set)"
    fi

    if [ -n "$WEBHOOK_URL" ]; then
        echo "Testing webhook alerts to: $WEBHOOK_URL"
        send_alert "MT5 Webhook Test" "This is a test webhook alert from the MT5 monitoring system."
    else
        echo "Webhook alerts not configured (WEBHOOK_URL not set)"
    fi

    echo "Alert test completed."
}

# Main script logic
case "${1:-}" in
    health)
        perform_health_check
        ;;
    monitor)
        start_monitoring
        ;;
    alerts)
        test_alerts
        ;;
    metrics)
        show_metrics
        ;;
    *)
        usage
        exit 1
        ;;
esac