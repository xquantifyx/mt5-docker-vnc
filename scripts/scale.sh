#!/bin/bash

# MT5 Scaling Management Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
MAX_INSTANCES=10
BASE_PORT=6080
BASE_VNC_PORT=5901

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 {start|stop|scale|status|logs} [options]"
    echo ""
    echo "Commands:"
    echo "  start                    Start the main MT5 instance"
    echo "  stop                     Stop all MT5 instances"
    echo "  scale <number>           Scale to specified number of instances"
    echo "  status                   Show status of all instances"
    echo "  logs <instance_name>     Show logs for specific instance"
    echo "  create <instance_name>   Create a new named instance"
    echo "  remove <instance_name>   Remove a specific instance"
    echo ""
    echo "Examples:"
    echo "  $0 start"
    echo "  $0 scale 3"
    echo "  $0 create mt5-client1"
    echo "  $0 logs mt5-main"
}

get_running_instances() {
    docker ps --filter "label=app=mt5" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -v NAMES || true
}

get_instance_count() {
    docker ps --filter "label=app=mt5" -q | wc -l
}

start_main_instance() {
    echo -e "${GREEN}Starting main MT5 instance...${NC}"
    cd "$PROJECT_DIR"
    docker-compose up -d mt5-instance nginx
    echo -e "${GREEN}Main instance started. Access via: http://localhost${NC}"
}

stop_all_instances() {
    echo -e "${YELLOW}Stopping all MT5 instances...${NC}"
    cd "$PROJECT_DIR"
    docker-compose down

    # Stop any additional instances
    docker ps --filter "label=app=mt5" -q | xargs -r docker stop
    docker ps -a --filter "label=app=mt5" -q | xargs -r docker rm

    echo -e "${GREEN}All instances stopped.${NC}"
}

create_instance() {
    local instance_name=$1
    local port=$2
    local vnc_port=$3

    if [ -z "$instance_name" ]; then
        echo -e "${RED}Error: Instance name required${NC}"
        return 1
    fi

    # Find available ports if not specified
    if [ -z "$port" ]; then
        port=$(find_available_port $BASE_PORT)
    fi

    if [ -z "$vnc_port" ]; then
        vnc_port=$(find_available_port $BASE_VNC_PORT)
    fi

    echo -e "${GREEN}Creating instance: $instance_name on port $port (VNC: $vnc_port)${NC}"

    # Create instance-specific directories
    mkdir -p "$PROJECT_DIR/data/$instance_name"
    mkdir -p "$PROJECT_DIR/logs/$instance_name"

    # Run new instance
    docker run -d \
        --name "$instance_name" \
        --label "app=mt5" \
        --label "instance=$instance_name" \
        -p "$port:6080" \
        -p "$vnc_port:5901" \
        -v "$PROJECT_DIR/data/$instance_name:/home/mt5user/mt5data" \
        -v "$PROJECT_DIR/logs/$instance_name:/home/mt5user/logs" \
        -v "$PROJECT_DIR/configs:/home/mt5user/configs:ro" \
        -e "INSTANCE_NAME=$instance_name" \
        -e "VNC_PASSWORD=${VNC_PASSWORD:-mt5password}" \
        --network "clouddesk_mt5-network" \
        --restart unless-stopped \
        mt5-docker:latest

    echo -e "${GREEN}Instance $instance_name created. Access via: http://localhost:$port${NC}"
}

find_available_port() {
    local start_port=$1
    local port=$start_port

    while netstat -tuln | grep -q ":$port "; do
        ((port++))
        if [ $port -gt $((start_port + 100)) ]; then
            echo -e "${RED}Error: Could not find available port${NC}"
            return 1
        fi
    done

    echo $port
}

scale_instances() {
    local target_count=$1
    local current_count=$(get_instance_count)

    if [ -z "$target_count" ] || [ "$target_count" -lt 0 ] || [ "$target_count" -gt $MAX_INSTANCES ]; then
        echo -e "${RED}Error: Invalid instance count. Must be between 0 and $MAX_INSTANCES${NC}"
        return 1
    fi

    echo -e "${YELLOW}Current instances: $current_count, Target: $target_count${NC}"

    if [ "$target_count" -gt "$current_count" ]; then
        # Scale up
        local instances_to_create=$((target_count - current_count))
        echo -e "${GREEN}Scaling up by $instances_to_create instances...${NC}"

        for i in $(seq 1 $instances_to_create); do
            local instance_name="mt5-auto-$((current_count + i))"
            create_instance "$instance_name"
        done

    elif [ "$target_count" -lt "$current_count" ]; then
        # Scale down
        local instances_to_remove=$((current_count - target_count))
        echo -e "${YELLOW}Scaling down by $instances_to_remove instances...${NC}"

        # Get auto-created instances (excluding main instance)
        local auto_instances=$(docker ps --filter "label=app=mt5" --filter "name=mt5-auto-" --format "{{.Names}}" | tail -n $instances_to_remove)

        for instance in $auto_instances; do
            echo -e "${YELLOW}Removing instance: $instance${NC}"
            docker stop "$instance"
            docker rm "$instance"
        done
    fi

    echo -e "${GREEN}Scaling completed. Current instances: $(get_instance_count)${NC}"
}

show_status() {
    echo -e "${GREEN}MT5 Instances Status:${NC}"
    echo "=========================="

    local instances=$(get_running_instances)
    if [ -z "$instances" ]; then
        echo -e "${YELLOW}No MT5 instances running${NC}"
    else
        echo "$instances"
    fi

    echo ""
    echo -e "${GREEN}Resource Usage:${NC}"
    docker stats --no-stream --filter "label=app=mt5" --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" | head -20
}

show_logs() {
    local instance_name=$1

    if [ -z "$instance_name" ]; then
        echo -e "${RED}Error: Instance name required${NC}"
        return 1
    fi

    if ! docker ps --filter "name=$instance_name" | grep -q "$instance_name"; then
        echo -e "${RED}Error: Instance $instance_name not found${NC}"
        return 1
    fi

    echo -e "${GREEN}Showing logs for $instance_name:${NC}"
    docker logs -f "$instance_name"
}

remove_instance() {
    local instance_name=$1

    if [ -z "$instance_name" ]; then
        echo -e "${RED}Error: Instance name required${NC}"
        return 1
    fi

    if [ "$instance_name" = "mt5-main" ]; then
        echo -e "${RED}Error: Cannot remove main instance. Use 'stop' command instead.${NC}"
        return 1
    fi

    echo -e "${YELLOW}Removing instance: $instance_name${NC}"
    docker stop "$instance_name" 2>/dev/null || true
    docker rm "$instance_name" 2>/dev/null || true

    # Remove data directories
    rm -rf "$PROJECT_DIR/data/$instance_name"
    rm -rf "$PROJECT_DIR/logs/$instance_name"

    echo -e "${GREEN}Instance $instance_name removed${NC}"
}

# Main script logic
case "${1:-}" in
    start)
        start_main_instance
        ;;
    stop)
        stop_all_instances
        ;;
    scale)
        scale_instances "$2"
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "$2"
        ;;
    create)
        create_instance "$2" "$3" "$4"
        ;;
    remove)
        remove_instance "$2"
        ;;
    *)
        usage
        exit 1
        ;;
esac