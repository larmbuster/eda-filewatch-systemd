#!/bin/bash

# EDA File Watch Monitor for Ansible Automation Platform
# Monitors a specified file for changes and triggers AAP job template launches
# Can also be run manually to trigger a single API call

set -euo pipefail

# Parse command line arguments
MANUAL_MODE=false
if [[ $# -gt 0 ]]; then
    if [[ "$1" == "--trigger" ]] && [[ -n "${2:-}" ]]; then
        MANUAL_MODE=true
        CONFIG_FILE="$2"
        if [[ ! -f "$CONFIG_FILE" ]]; then
            echo "Error: Config file '$CONFIG_FILE' not found" >&2
            exit 1
        fi
    elif [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        echo "Usage: $0 [--trigger CONFIG_FILE]"
        echo ""
        echo "Normal mode (no arguments):"
        echo "  Runs as a service, continuously monitoring the configured file"
        echo ""
        echo "Manual trigger mode:"
        echo "  --trigger CONFIG_FILE   Load config and trigger a single API call"
        echo ""
        echo "Example:"
        echo "  $0 --trigger /etc/eda-filewatch/myfile.conf"
        exit 0
    else
        echo "Error: Invalid arguments. Use --help for usage information" >&2
        exit 1
    fi
fi

# Configuration - can be overridden by environment variables or config file
WATCH_FILE="${WATCH_FILE:-}"
API_URL="${API_URL:-}"
API_METHOD="${API_METHOD:-POST}"
API_TIMEOUT="${API_TIMEOUT:-30}"
API_TOKEN="${API_TOKEN:-}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
CONFIG_FILE="${CONFIG_FILE:-/etc/eda-filewatch/config}"
RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"
RATE_LIMIT="${RATE_LIMIT:-10}"  # Max API calls per minute
SSL_VERIFY="${SSL_VERIFY:-true}"  # SSL certificate verification
SSL_CACERT="${SSL_CACERT:-}"     # Custom CA certificate file
SSL_CERT="${SSL_CERT:-}"         # Client certificate file
SSL_KEY="${SSL_KEY:-}"           # Client private key file

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Rate limiting variables
declare -a api_call_times=()

# Debouncing variables
last_event_time=0
DEBOUNCE_DELAY="${DEBOUNCE_DELAY:-2}"  # Wait 2 seconds after last event before triggering

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

# Secure config loading with validation
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Check file permissions
        local perms=$(stat -c "%a" "$CONFIG_FILE" 2>/dev/null || echo "000")
        if [[ $perms -gt 644 ]]; then
            log "WARN" "Config file $CONFIG_FILE has overly permissive permissions ($perms)"
        fi
        
        log "INFO" "Loading configuration from $CONFIG_FILE"
        
        # Validate config file content before sourcing
        if ! bash -n "$CONFIG_FILE"; then
            log "ERROR" "Config file $CONFIG_FILE contains syntax errors"
            exit 1
        fi
        
        # Source config file directly
        source "$CONFIG_FILE" || {
            log "ERROR" "Failed to load config file"
            exit 1
        }
    fi
}

# Enhanced configuration validation
validate_config() {
    if [[ -z "$WATCH_FILE" ]]; then
        log "ERROR" "WATCH_FILE is not set. Please set it in environment or config file."
        exit 1
    fi
    
    if [[ -z "$API_URL" ]]; then
        log "ERROR" "API_URL is not set. Please set it in environment or config file."
        exit 1
    fi
    
    # Validate AAP API URL format
    if ! [[ "$API_URL" =~ /api/(v2|controller/v2)/job_templates/[0-9]+/launch/? ]]; then
        log "ERROR" "Invalid AAP API URL format. Expected: https://<server>/api/controller/v2/job_templates/<id>/launch/"
        log "ERROR" "Got: $API_URL"
        exit 1
    fi
    
    # Validate API_TIMEOUT is numeric
    if ! [[ "$API_TIMEOUT" =~ ^[0-9]+$ ]]; then
        log "ERROR" "API_TIMEOUT must be a positive integer, got: $API_TIMEOUT"
        exit 1
    fi
    
    # Validate API_TIMEOUT range
    if [[ "$API_TIMEOUT" -lt 1 || "$API_TIMEOUT" -gt 300 ]]; then
        log "ERROR" "API_TIMEOUT must be between 1 and 300 seconds, got: $API_TIMEOUT"
        exit 1
    fi
    
    # Validate RETRY_COUNT
    if ! [[ "$RETRY_COUNT" =~ ^[0-9]+$ ]]; then
        log "ERROR" "RETRY_COUNT must be a positive integer, got: $RETRY_COUNT"
        exit 1
    fi
    
    # Validate RATE_LIMIT
    if ! [[ "$RATE_LIMIT" =~ ^[0-9]+$ ]]; then
        log "ERROR" "RATE_LIMIT must be a positive integer, got: $RATE_LIMIT"
        exit 1
    fi
    
    # Validate DEBOUNCE_DELAY
    if ! [[ "$DEBOUNCE_DELAY" =~ ^[0-9]+$ ]]; then
        log "ERROR" "DEBOUNCE_DELAY must be a positive integer, got: $DEBOUNCE_DELAY"
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
    
    # Test file readability
    if ! [[ -r "$WATCH_FILE" ]]; then
        log "ERROR" "Cannot read watch file '$WATCH_FILE'. Check permissions."
        exit 1
    fi
    
    # Validate SSL certificate files if specified
    if [[ -n "$SSL_CACERT" && ! -f "$SSL_CACERT" ]]; then
        log "ERROR" "SSL_CACERT file '$SSL_CACERT' does not exist."
        exit 1
    fi
    
    if [[ -n "$SSL_CERT" && ! -f "$SSL_CERT" ]]; then
        log "ERROR" "SSL_CERT file '$SSL_CERT' does not exist."
        exit 1
    fi
    
    if [[ -n "$SSL_KEY" && ! -f "$SSL_KEY" ]]; then
        log "ERROR" "SSL_KEY file '$SSL_KEY' does not exist."
        exit 1
    fi
    
    # Validate SSL_VERIFY is boolean
    if [[ "$SSL_VERIFY" != "true" && "$SSL_VERIFY" != "false" ]]; then
        log "ERROR" "SSL_VERIFY must be 'true' or 'false', got: $SSL_VERIFY"
        exit 1
    fi
}

# JSON escape function
json_escape() {
    local input="$1"
    # Escape backslashes, quotes, and control characters
    printf '%s' "$input" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g; s/\r/\\r/g'
}

# Rate limiting function
check_rate_limit() {
    local current_time=$(date +%s)
    local one_minute_ago=$((current_time - 60))
    
    # Remove old timestamps
    local new_times=()
    if [[ ${#api_call_times[@]} -gt 0 ]]; then
        for time in "${api_call_times[@]}"; do
            if [[ "$time" -gt "$one_minute_ago" ]]; then
                new_times+=("$time")
            fi
        done
    fi
    if [[ ${#new_times[@]} -gt 0 ]]; then
        api_call_times=("${new_times[@]}")
    else
        api_call_times=()
    fi
    
    # Check if we're under the rate limit
    if [[ ${#api_call_times[@]} -ge $RATE_LIMIT ]]; then
        log "WARN" "Rate limit exceeded ($RATE_LIMIT calls/minute). Delaying..."
        local sleep_time=$((61 - (current_time - api_call_times[0])))
        if [[ $sleep_time -gt 0 ]]; then
            sleep "$sleep_time"
        else
            sleep 1
        fi
        return 1
    fi
    
    # Add current timestamp
    api_call_times+=("$current_time")
    return 0
}

# Enhanced API call with retry logic
make_api_call() {
    local file_path="$1"
    local change_time="$2"
    local attempt=1
    
    # Apply rate limiting
    check_rate_limit
    
    log "INFO" "Launching AAP job template: $API_URL"
    
    # Prepare JSON payload for AAP with proper escaping
    local escaped_file_path=$(json_escape "$file_path")
    local escaped_change_time=$(json_escape "$change_time")
    local escaped_hostname=$(json_escape "$(hostname)")
    
    # AAP expects extra_vars format
    local payload=$(cat <<EOF
{
    "extra_vars": {
        "file_path": "$escaped_file_path",
        "change_time": "$escaped_change_time",
        "event": "file_modified",
        "hostname": "$escaped_hostname"
    }
}
EOF
)
    
    log "DEBUG" "Payload: $payload"
    
    # Retry loop
    while [[ $attempt -le $RETRY_COUNT ]]; do
        if [[ $attempt -gt 1 ]]; then
            log "INFO" "API call attempt $attempt of $RETRY_COUNT"
            sleep "$RETRY_DELAY"
        fi
        
        # Make the API call
        local response
        local http_code
        
        # Build curl command with conditional auth header
        local curl_args=(
            -s
            -w "\n%{http_code}"
            -X "$API_METHOD"
            -H "Content-Type: application/json"
            -H "User-Agent: EDA-FileWatch-Monitor/1.0"
            --connect-timeout 10
            --max-time "$API_TIMEOUT"
        )
        
        # Add Authorization header if API_TOKEN is set
        if [[ -n "$API_TOKEN" ]]; then
            curl_args+=(-H "Authorization: Bearer $API_TOKEN")
            log "DEBUG" "Using API token for authentication"
        fi
        
        # Add SSL/certificate options
        if [[ "$SSL_VERIFY" == "false" ]]; then
            curl_args+=(--insecure)
            log "DEBUG" "SSL certificate verification disabled"
        fi
        
        if [[ -n "$SSL_CACERT" ]]; then
            curl_args+=(--cacert "$SSL_CACERT")
            log "DEBUG" "Using custom CA certificate: $SSL_CACERT"
        fi
        
        if [[ -n "$SSL_CERT" ]]; then
            curl_args+=(--cert "$SSL_CERT")
            log "DEBUG" "Using client certificate: $SSL_CERT"
        fi
        
        if [[ -n "$SSL_KEY" ]]; then
            curl_args+=(--key "$SSL_KEY")
            log "DEBUG" "Using client private key: $SSL_KEY"
        fi
        
        # Add remaining arguments
        curl_args+=(
            -d "$payload"
            "$API_URL"
        )
        
        response=$(curl "${curl_args[@]}" 2>&1)
        local curl_exit_code=$?
        
        if [[ $curl_exit_code -eq 0 ]]; then
            http_code=$(echo "$response" | tail -n1)
            response_body=$(echo "$response" | head -n -1)
            
            if [[ "$http_code" =~ ^[0-9]+$ ]] && [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
                log "INFO" "AAP job template launched successfully (HTTP $http_code)"
                log "DEBUG" "AAP Response: $response_body"
                return 0
            elif [[ "$http_code" =~ ^[0-9]+$ ]] && [[ "$http_code" -ge 400 && "$http_code" -lt 500 ]]; then
                log "ERROR" "AAP job template launch failed with client error (HTTP $http_code)"
                log "ERROR" "AAP Response: $response_body"
                log "ERROR" "Check: Token permissions, job template ID, and AAP URL format"
                return 1  # Don't retry client errors
            else
                log "WARN" "AAP job template launch failed (HTTP $http_code), will retry"
                log "DEBUG" "AAP Response: $response_body"
            fi
        else
            log "WARN" "Curl failed with exit code $curl_exit_code, will retry"
            log "DEBUG" "Error: $response"
        fi
        
        ((attempt++))
    done
    
    log "ERROR" "AAP job template launch failed after $RETRY_COUNT attempts"
    return 1
}

# Enhanced signal handling
cleanup() {
    log "INFO" "Shutting down file monitor..."
    # Kill any child processes (including debounce timers)
    pkill -P $$ 2>/dev/null || true
    # Clean up any temporary files
    rm -f /tmp/inotify_fifo_$$ 2>/dev/null || true
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGHUP

# Main monitoring loop with improved error handling
main() {
    log "INFO" "Starting EDA File Watch Monitor for Ansible Automation Platform"
    log "INFO" "Watching file: $WATCH_FILE"
    log "INFO" "AAP Job Template URL: $API_URL"
    log "INFO" "HTTP Method: $API_METHOD"
    log "INFO" "Request Timeout: ${API_TIMEOUT}s"
    log "INFO" "Retry Count: $RETRY_COUNT"
    log "INFO" "Rate Limit: $RATE_LIMIT calls/minute"
    log "INFO" "Debounce Delay: ${DEBOUNCE_DELAY}s"
    
    if [[ -z "$API_TOKEN" ]]; then
        log "ERROR" "AAP Authentication token not configured - this is required!"
        exit 1
    fi
    log "INFO" "AAP Authentication: Token configured"
    
    # Start monitoring
    log "INFO" "Starting file monitor..."
    
    while true; do
        # Use a more robust approach to handle the pipe
        local temp_fifo="/tmp/inotify_fifo_$$"
        if [[ -p "$temp_fifo" ]]; then
            rm -f "$temp_fifo"
        fi
        mkfifo "$temp_fifo"
        
        # Start inotifywait in monitor mode in background
        inotifywait -m -e modify,move,create,delete "$WATCH_FILE" \
            --format '%w%f %e %T' --timefmt '%Y-%m-%d %H:%M:%S' \
            2>/dev/null > "$temp_fifo" &
        
        local inotify_pid=$!
        
        # Read from fifo with timeout check
        # Variables for debouncing
        local pending_file=""
        local pending_time=""
        local debounce_timer_pid=""
        
        while true; do
            # Check if inotifywait is still running
            if ! kill -0 $inotify_pid 2>/dev/null; then
                log "WARN" "inotifywait process died"
                break
            fi
            
            # Read with timeout
            if read -r file event time < "$temp_fifo"; then
                log "DEBUG" "File event detected: $file ($event) at $time"
                
                # Kill any existing debounce timer
                if [[ -n "$debounce_timer_pid" ]] && kill -0 "$debounce_timer_pid" 2>/dev/null; then
                    kill "$debounce_timer_pid" 2>/dev/null || true
                    log "DEBUG" "Cancelled previous debounce timer"
                fi
                
                # Store the latest event details
                pending_file="$file"
                pending_time="$time"
                
                # Start a new debounce timer in background
                (
                    sleep "$DEBOUNCE_DELAY"
                    log "INFO" "Processing file change: $pending_file (changed at $pending_time)"
                    
                    # Make API call
                    if make_api_call "$pending_file" "$pending_time"; then
                        log "INFO" "Successfully processed file change event"
                    else
                        log "WARN" "Failed to process file change event, but continuing to monitor"
                    fi
                ) &
                debounce_timer_pid=$!
                
            else
                # Read failed, check if process is still alive
                if ! kill -0 $inotify_pid 2>/dev/null; then
                    break
                fi
            fi
        done
        
        # Clean up
        kill $inotify_pid 2>/dev/null || true
        if [[ -n "$debounce_timer_pid" ]] && kill -0 "$debounce_timer_pid" 2>/dev/null; then
            kill "$debounce_timer_pid" 2>/dev/null || true
        fi
        rm -f "$temp_fifo"
        
        # If we get here, inotifywait exited
        log "WARN" "inotifywait exited, restarting in 5 seconds..."
        sleep 5
    done
}

# Manual trigger mode - make a single API call
manual_trigger() {
    log "INFO" "Manual trigger mode - Loading configuration"
    log "INFO" "Config file: $CONFIG_FILE"
    
    # Show current configuration
    log "INFO" "Configuration:"
    log "INFO" "  Watch file: $WATCH_FILE"
    log "INFO" "  API URL: $API_URL"
    
    # Make a single API call
    log "INFO" "Triggering API call..."
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    if make_api_call "$WATCH_FILE" "$current_time"; then
        log "INFO" "Manual trigger completed successfully"
        exit 0
    else
        log "ERROR" "Manual trigger failed"
        exit 1
    fi
}

# Start the program
load_config
validate_config

if [[ "$MANUAL_MODE" == "true" ]]; then
    manual_trigger
else
    main
fi 