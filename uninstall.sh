#!/bin/bash

# EDA File Watch Monitor Uninstallation Script
# This script removes all components installed by install.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVICE_NAME="eda-filewatch@"
INSTALL_DIR="/opt/eda-filewatch"
CONFIG_DIR="/etc/eda-filewatch"
LOG_DIR="/var/log/eda-filewatch"
SYSTEMD_DIR="/etc/systemd/system"

# Print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Confirmation prompt
confirm_uninstall() {
    print_warning "This will remove the EDA File Watch Monitor service and all its components."
    print_warning "The following will be removed:"
    echo "  - All running eda-filewatch@ service instances"
    echo "  - Service files from $SYSTEMD_DIR"
    echo "  - Scripts and files from $INSTALL_DIR"
    echo "  - Configuration files from $CONFIG_DIR"
    echo "  - Log files from $LOG_DIR"
    echo
    read -p "Are you sure you want to continue? (yes/NO): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        print_status "Uninstallation cancelled"
        exit 0
    fi
}

# Stop and disable all service instances
stop_services() {
    print_status "Stopping and disabling all service instances..."
    
    # Get list of all eda-filewatch@ instances
    local instances=$(systemctl list-units --full --all --no-legend | grep "eda-filewatch@" | awk '{print $1}')
    
    if [[ -n "$instances" ]]; then
        for instance in $instances; do
            print_status "Stopping $instance..."
            systemctl stop "$instance" 2>/dev/null || true
            
            print_status "Disabling $instance..."
            systemctl disable "$instance" 2>/dev/null || true
        done
    else
        print_status "No active service instances found"
    fi
}

# Remove systemd service file
remove_systemd_service() {
    print_status "Removing systemd service file..."
    
    if [[ -f "$SYSTEMD_DIR/eda-filewatch@.service" ]]; then
        rm -f "$SYSTEMD_DIR/eda-filewatch@.service"
        print_status "Removed $SYSTEMD_DIR/eda-filewatch@.service"
    else
        print_status "Service file not found"
    fi
    
    # Reload systemd
    print_status "Reloading systemd..."
    systemctl daemon-reload
}

# Remove installation directory
remove_install_dir() {
    print_status "Removing installation directory..."
    
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        print_status "Removed $INSTALL_DIR"
    else
        print_status "Installation directory not found"
    fi
}

# Remove configuration directory
remove_config_dir() {
    print_status "Removing configuration directory..."
    
    if [[ -d "$CONFIG_DIR" ]]; then
        # Check if there are custom config files
        local config_files=$(find "$CONFIG_DIR" -name "*.conf" -type f 2>/dev/null | wc -l)
        
        if [[ $config_files -gt 0 ]]; then
            print_warning "Found $config_files configuration file(s) in $CONFIG_DIR"
            read -p "Do you want to remove configuration files as well? (yes/NO): " remove_configs
            
            if [[ "$remove_configs" == "yes" ]]; then
                rm -rf "$CONFIG_DIR"
                print_status "Removed $CONFIG_DIR and all configuration files"
            else
                # Remove only the template file
                rm -f "$CONFIG_DIR/config.template"
                print_status "Kept configuration files, removed only config.template"
                print_warning "Configuration directory $CONFIG_DIR was preserved"
            fi
        else
            rm -rf "$CONFIG_DIR"
            print_status "Removed $CONFIG_DIR"
        fi
    else
        print_status "Configuration directory not found"
    fi
}

# Remove log directory
remove_log_dir() {
    print_status "Removing log directory..."
    
    if [[ -d "$LOG_DIR" ]]; then
        # Check if there are log files
        local log_files=$(find "$LOG_DIR" -name "*.log" -type f 2>/dev/null | wc -l)
        
        if [[ $log_files -gt 0 ]]; then
            print_warning "Found $log_files log file(s) in $LOG_DIR"
            read -p "Do you want to remove log files as well? (yes/NO): " remove_logs
            
            if [[ "$remove_logs" == "yes" ]]; then
                rm -rf "$LOG_DIR"
                print_status "Removed $LOG_DIR and all log files"
            else
                print_warning "Log directory $LOG_DIR was preserved"
            fi
        else
            rm -rf "$LOG_DIR"
            print_status "Removed $LOG_DIR"
        fi
    else
        print_status "Log directory not found"
    fi
}

# Show summary
show_summary() {
    echo
    print_status "Uninstallation completed successfully!"
    echo
    echo "The following have been removed:"
    echo "  ✓ All eda-filewatch@ service instances"
    echo "  ✓ Systemd service file"
    echo "  ✓ Installation directory ($INSTALL_DIR)"
    
    if [[ ! -d "$CONFIG_DIR" ]]; then
        echo "  ✓ Configuration directory ($CONFIG_DIR)"
    else
        echo "  ⚠ Configuration directory preserved ($CONFIG_DIR)"
    fi
    
    if [[ ! -d "$LOG_DIR" ]]; then
        echo "  ✓ Log directory ($LOG_DIR)"
    else
        echo "  ⚠ Log directory preserved ($LOG_DIR)"
    fi
    
    echo
    print_status "The EDA File Watch Monitor has been completely removed from your system."
}

# Main uninstallation function
main() {
    echo "EDA File Watch Monitor Uninstallation Script"
    echo "============================================"
    echo
    
    check_root
    confirm_uninstall
    
    echo
    stop_services
    remove_systemd_service
    remove_install_dir
    remove_config_dir
    remove_log_dir
    
    show_summary
}

# Run main function
main "$@"