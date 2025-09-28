#!/bin/bash

# MT5 Backup and Restore Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_DIR}/backups"
DATE=$(date +%Y%m%d_%H%M%S)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Usage: $0 {backup|restore|list|cleanup} [options]"
    echo ""
    echo "Commands:"
    echo "  backup [instance_name]   Backup instance data (default: all)"
    echo "  restore <backup_file>    Restore from backup"
    echo "  list                     List available backups"
    echo "  cleanup [days]           Remove backups older than X days (default: 30)"
    echo ""
    echo "Examples:"
    echo "  $0 backup"
    echo "  $0 backup mt5-main"
    echo "  $0 restore backups/mt5_backup_20241027_120000.tar.gz"
    echo "  $0 cleanup 7"
}

create_backup() {
    local instance_name=$1
    mkdir -p "$BACKUP_DIR"

    if [ -n "$instance_name" ]; then
        # Backup specific instance
        if [ ! -d "$PROJECT_DIR/data/$instance_name" ]; then
            echo -e "${RED}Error: Instance $instance_name not found${NC}"
            return 1
        fi

        local backup_file="${BACKUP_DIR}/${instance_name}_backup_${DATE}.tar.gz"
        echo -e "${GREEN}Creating backup for $instance_name...${NC}"

        tar -czf "$backup_file" \
            -C "$PROJECT_DIR" \
            "data/$instance_name" \
            "logs/$instance_name" \
            "configs" 2>/dev/null || true

        echo -e "${GREEN}Backup created: $backup_file${NC}"
    else
        # Backup all instances
        local backup_file="${BACKUP_DIR}/mt5_full_backup_${DATE}.tar.gz"
        echo -e "${GREEN}Creating full backup...${NC}"

        tar -czf "$backup_file" \
            -C "$PROJECT_DIR" \
            data \
            logs \
            configs \
            docker-compose.yml \
            .env 2>/dev/null || true

        echo -e "${GREEN}Full backup created: $backup_file${NC}"
    fi
}

restore_backup() {
    local backup_file=$1

    if [ -z "$backup_file" ]; then
        echo -e "${RED}Error: Backup file required${NC}"
        return 1
    fi

    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Error: Backup file not found: $backup_file${NC}"
        return 1
    fi

    echo -e "${YELLOW}Warning: This will overwrite existing data. Continue? (y/N)${NC}"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Restore cancelled."
        return 0
    fi

    echo -e "${GREEN}Restoring from backup: $backup_file${NC}"

    # Stop all instances before restore
    cd "$PROJECT_DIR"
    docker-compose down || true

    # Extract backup
    tar -xzf "$backup_file" -C "$PROJECT_DIR"

    echo -e "${GREEN}Restore completed. You can now start the instances.${NC}"
}

list_backups() {
    echo -e "${GREEN}Available backups:${NC}"
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR")" ]; then
        ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{print $9, $5, $6, $7, $8}' | sort -r
    else
        echo "No backups found."
    fi
}

cleanup_backups() {
    local days=${1:-30}

    if [ ! -d "$BACKUP_DIR" ]; then
        echo "No backup directory found."
        return 0
    fi

    echo -e "${GREEN}Removing backups older than $days days...${NC}"

    find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +$days -delete

    echo -e "${GREEN}Cleanup completed.${NC}"
}

# Main script logic
case "${1:-}" in
    backup)
        create_backup "$2"
        ;;
    restore)
        restore_backup "$2"
        ;;
    list)
        list_backups
        ;;
    cleanup)
        cleanup_backups "$2"
        ;;
    *)
        usage
        exit 1
        ;;
esac