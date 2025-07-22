#!/bin/bash

# EDA File Watch Monitor Installation Script
# This script installs and configures the EDA File Watch Monitor service

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVICE_NAME="eda-filewatch@"
SERVICE_USER="eda-filewatch"
SERVICE_GROUP="eda-filewatch"
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

# Check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check for required packages
    local missing_packages=()
    
    if ! command -v inotifywait >/dev/null 2>&1; then
        missing_packages+=("inotify-tools")
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        missing_packages+=("curl")
    fi
    
    if ! command -v systemctl >/dev/null 2>&1; then
        print_error "systemctl not found. This system does not support systemd."
        exit 1
    fi
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        print_error "Missing required packages: ${missing_packages[*]}"
        echo "Please install them first:"
        echo "  Ubuntu/Debian: sudo apt-get install ${missing_packages[*]}"
        echo "  CentOS/RHEL/Fedora: sudo yum install ${missing_packages[*]}"
        exit 1
    fi
    
    print_status "All requirements satisfied"
}

# Create service user and group - SKIPPED as service runs as root
create_service_user() {
    print_status "Service will run as root for system-wide file access"
    print_warning "No separate service user will be created"
}

# Create directories
create_directories() {
    print_status "Creating directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    
    # Set ownership and permissions
    chown root:root "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"
    
    chown root:root "$CONFIG_DIR"
    chmod 755 "$CONFIG_DIR"
    
    chown root:root "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    
    print_status "Directories created successfully"
}

# Install files
install_files() {
    print_status "Installing files..."
    
    # Copy and set permissions for the monitor script
    if [[ -f "filewatch-monitor.sh" ]]; then
        cp "filewatch-monitor.sh" "$INSTALL_DIR/"
        chmod 755 "$INSTALL_DIR/filewatch-monitor.sh"
        chown root:root "$INSTALL_DIR/filewatch-monitor.sh"
        print_status "Installed monitor script"
    else
        print_error "filewatch-monitor.sh not found in current directory"
        exit 1
    fi
    
    # Copy systemd service file
    if [[ -f "eda-filewatch@.service" ]]; then
        cp "eda-filewatch@.service" "$SYSTEMD_DIR/"
        chmod 644 "$SYSTEMD_DIR/eda-filewatch@.service"
        chown root:root "$SYSTEMD_DIR/eda-filewatch@.service"
        print_status "Installed systemd service file"
    else
        print_error "eda-filewatch@.service not found in current directory"
        exit 1
    fi
    
    # Copy configuration template
    if [[ -f "config.template" ]]; then
        cp "config.template" "$CONFIG_DIR/"
        chmod 644 "$CONFIG_DIR/config.template"
        chown root:root "$CONFIG_DIR/config.template"
        print_status "Installed configuration template"
    else
        print_error "config.template not found in current directory"
        exit 1
    fi
}

# Reload systemd
reload_systemd() {
    print_status "Reloading systemd..."
    systemctl daemon-reload
    print_status "Systemd reloaded"
}

# Create example configuration
create_example_config() {
    local instance_name="$1"
    local config_file="$CONFIG_DIR/$instance_name.conf"
    
    if [[ -f "$config_file" ]]; then
        print_warning "Configuration file $config_file already exists"
        return
    fi
    
    print_status "Creating example configuration for instance '$instance_name'..."
    
    cat > "$config_file" << EOF
# EDA File Watch Monitor Configuration for '$instance_name'
# Customize the values below for your specific needs

# Required: File to watch for changes
WATCH_FILE="/path/to/your/file.txt"

# Required: API URL to call when file changes
API_URL="https://your-api-endpoint.com/webhook"

# Optional: HTTP method to use for API calls (default: POST)
API_METHOD="POST"

# Optional: Timeout for API calls in seconds (default: 30)
API_TIMEOUT=30

# Optional: Log level (DEBUG, INFO, WARN, ERROR) (default: INFO)
LOG_LEVEL="INFO"
EOF
    
    chmod 644 "$config_file"
    chown root:root "$config_file"
    
    print_status "Created configuration file: $config_file"
    print_warning "Please edit $config_file to configure your specific settings"
}

# Show usage information
show_usage() {
    print_status "Installation completed successfully!"
    echo
    print_warning "Note: The service runs as root to allow monitoring any file on the system"
    echo
    echo "Usage:"
    echo "  1. Create a configuration file for your instance:"
    echo "     sudo cp $CONFIG_DIR/config.template $CONFIG_DIR/myfile.conf"
    echo "     sudo nano $CONFIG_DIR/myfile.conf"
    echo
    echo "  2. Enable and start the service:"
    echo "     sudo systemctl enable eda-filewatch@myfile"
    echo "     sudo systemctl start eda-filewatch@myfile"
    echo
    echo "  3. Check service status:"
    echo "     sudo systemctl status eda-filewatch@myfile"
    echo
    echo "  4. View logs:"
    echo "     sudo journalctl -u eda-filewatch@myfile -f"
    echo
    echo "Multiple instances can be run simultaneously by using different instance names."
}

# Main installation function
main() {
    echo "EDA File Watch Monitor Installation Script"
    echo "=========================================="
    echo
    
    check_root
    check_requirements
    create_service_user
    create_directories
    install_files
    reload_systemd
    
    # If instance name provided, create example config
    if [[ $# -gt 0 ]]; then
        create_example_config "$1"
    fi
    
    echo
    show_usage
}

# Run main function with all arguments
main "$@" 