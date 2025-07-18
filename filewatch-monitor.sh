#!/bin/bash

# EDA File Watch Monitor
# Monitors a specified file for changes and triggers API calls

set -euo pipefail

# Configuration - can be overridden by environment variables or config file
WATCH_FILE="${WATCH_FILE:-}"
API_URL="${API_URL:-}"
API_METHOD="${API_METHOD:-POST}"
API_TIMEOUT="${API_TIMEOUT:-30}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
CONFIG_FILE="${CONFIG_FILE:-/etc/eda-filewatch/config}"

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        ERROR)
            echo -e "${timestamp} [${RED}ERROR${NC}] $message" >&2
            ;;
        WARN)
            echo -e "${timestamp} [${YELLOW}WARN${NC}] $message" >&2
            ;;
        INFO)
            echo -e "${timestamp} [${GREEN}INFO${NC}] $message"
            ;;
        DEBUG)
            if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
                echo -e "${timestamp} [${BLUE}DEBUG${NC}] $message"
            fi
            ;;
    esac
}

# Load configuration file if it exists
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log "INFO" "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
}

# Validate configuration
validate_config() {
    if [[ -z "$WATCH_FILE" ]]; then
        log "ERROR" "WATCH_FILE is not set. Please set it in environment or config file."
        exit 1
    fi
    
    if [[ -z "$API_URL" ]]; then
        log "ERROR" "API_URL is not set. Please set it in environment or config file."
        exit 1
    fi
    
    if [[ ! -f "$WATCH_FILE" ]]; then
        log "ERROR" "Watch file '$WATCH_FILE' does not exist."
        exit 1
    fi
    
    if ! command -v inotifywait >/dev/null 2>&1; then
        log "ERROR" "inotifywait is not installed. Please install inotify-tools package."
        exit 1
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        log "ERROR" "curl is not installed. Please install curl package."
        exit 1
    fi
}

# Make API call
make_api_call() {
    local file_path="$1"
    local change_time="$2"
    
    log "INFO" "Making API call to $API_URL"
    
    # Prepare JSON payload
    local payload=$(cat <<EOF
{
    "file_path": "$file_path",
    "change_time": "$change_time",
    "event": "file_modified",
    "hostname": "$(hostname)"
}
EOF
)
    
    log "DEBUG" "Payload: $payload"
    
    # Make the API call
    local response
    local http_code
    
    response=$(curl -s -w "\n%{http_code}" \
        -X "$API_METHOD" \
        -H "Content-Type: application/json" \
        -H "User-Agent: EDA-FileWatch-Monitor/1.0" \
        -d "$payload" \
        --max-time "$API_TIMEOUT" \
        "$API_URL" 2>&1)
    
    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        log "INFO" "API call successful (HTTP $http_code)"
        log "DEBUG" "Response: $response_body"
        return 0
    else
        log "ERROR" "API call failed (HTTP $http_code)"
        log "ERROR" "Response: $response_body"
        return 1
    fi
}

# Handle shutdown gracefully
cleanup() {
    log "INFO" "Shutting down file monitor..."
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Main monitoring loop
main() {
    log "INFO" "Starting EDA File Watch Monitor"
    log "INFO" "Watching file: $WATCH_FILE"
    log "INFO" "API URL: $API_URL"
    log "INFO" "API Method: $API_METHOD"
    log "INFO" "API Timeout: ${API_TIMEOUT}s"
    
    # Start monitoring
    log "INFO" "Starting file monitor..."
    
    while true; do
        # Wait for file modification events
        inotifywait -e modify,move,create,delete "$WATCH_FILE" --format '%w%f %e %T' --timefmt '%Y-%m-%d %H:%M:%S' 2>/dev/null | while read file event time; do
            log "INFO" "File change detected: $file ($event) at $time"
            
            # Make API call
            if make_api_call "$file" "$time"; then
                log "INFO" "Successfully processed file change event"
            else
                log "WARN" "Failed to process file change event, but continuing to monitor"
            fi
        done
        
        # If inotifywait exits, wait a bit before restarting
        log "WARN" "inotifywait exited, restarting in 5 seconds..."
        sleep 5
    done
}

# Start the program
load_config
validate_config
main 