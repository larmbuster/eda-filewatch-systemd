#!/bin/bash

# EDA File Watch Monitor for Ansible Automation Platform
# Uses AIDE to monitor file integrity and triggers AAP job template launches
# Designed for RHEL 8/9 systems

set -euo pipefail

# Parse command line arguments
if [[ $# -gt 0 ]]; then
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        echo "Usage: $0"
        echo ""
        echo "Runs as a service using AIDE to monitor file integrity"
        echo "Configuration is loaded from /etc/eda-filewatch/<instance>.conf"
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
CONFIG_FILE="${CONFIG_FILE:-}"
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

# AIDE-specific variables
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"  # How often to run AIDE check (seconds)
AIDE_CONFIG="${AIDE_CONFIG:-/etc/aide.conf}"
# AIDE database paths will be set after config is loaded
AIDE_DB="${AIDE_DB:-}"
AIDE_DB_NEW="${AIDE_DB_NEW:-}"

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
    if [[ -n "$CONFIG_FILE" ]] && [[ -f "$CONFIG_FILE" ]]; then
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
    # Validate CONFIG_FILE is set
    if [[ -z "$CONFIG_FILE" ]]; then
        log "ERROR" "CONFIG_FILE is not set. This should be set by systemd."
        exit 1
    fi
    
    # Set instance-specific AIDE database paths after config is loaded
    local instance_name="${CONFIG_FILE##*/}"
    instance_name="${instance_name%.conf}"
    # Fallback to default if empty
    instance_name="${instance_name:-default}"
    export AIDE_DB="${AIDE_DB:-/var/lib/aide/aide-${instance_name}.db.gz}"
    export AIDE_DB_NEW="${AIDE_DB_NEW:-/var/lib/aide/aide-${instance_name}.db.new.gz}"
    
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
    
    # Validate CHECK_INTERVAL
    if ! [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]]; then
        log "ERROR" "CHECK_INTERVAL must be a positive integer, got: $CHECK_INTERVAL"
        exit 1
    fi
    
    if [[ "$CHECK_INTERVAL" -lt 30 ]]; then
        log "WARN" "CHECK_INTERVAL is less than 30 seconds. This may cause high system load."
    fi
    
    if [[ ! -e "$WATCH_FILE" ]]; then
        log "ERROR" "Watch file '$WATCH_FILE' does not exist."
        exit 1
    fi
    
    if [[ ! -f "$WATCH_FILE" ]]; then
        log "ERROR" "Watch file '$WATCH_FILE' is not a regular file."
        exit 1
    fi
    
    if ! command -v aide >/dev/null 2>&1; then
        log "ERROR" "AIDE is not installed. Please install aide package."
        log "ERROR" "RHEL/CentOS: sudo yum install aide"
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
    
    # Validate file path doesn't contain newlines (would break AIDE config)
    if [[ "$WATCH_FILE" =~ $'\n' ]]; then
        log "ERROR" "Watch file path cannot contain newlines"
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
    local change_details="$3"
    local attempt=1
    
    # Apply rate limiting
    check_rate_limit
    
    log "INFO" "Launching AAP job template: $API_URL"
    
    # Prepare JSON payload for AAP with proper escaping
    local escaped_file_path=$(json_escape "$file_path")
    local escaped_change_time=$(json_escape "$change_time")
    local escaped_hostname=$(json_escape "$(hostname)")
    local escaped_change_details=$(json_escape "$change_details")
    
    # AAP expects extra_vars format
    local payload=$(cat <<EOF
{
    "extra_vars": {
        "file_path": "$escaped_file_path",
        "change_time": "$escaped_change_time",
        "event": "file_modified",
        "hostname": "$escaped_hostname",
        "change_details": "$escaped_change_details"
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
            -H "User-Agent: EDA-AIDE-FileWatch/1.0"
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

# Initialize AIDE for our specific file
init_aide() {
    log "INFO" "Initializing AIDE monitoring for $WATCH_FILE"
    
    # Create a custom AIDE config for our specific file
    local instance_name="${CONFIG_FILE##*/}"
    instance_name="${instance_name%.conf}"
    instance_name="${instance_name:-default}"
    local custom_aide_config="/etc/eda-filewatch/aide-${instance_name}.conf"
    local aide_db_dir=$(dirname "$AIDE_DB")
    
    # Ensure directories exist
    if ! mkdir -p "$(dirname "$custom_aide_config")" 2>/dev/null; then
        log "ERROR" "Failed to create config directory: $(dirname "$custom_aide_config")"
        exit 1
    fi
    
    # Ensure parent directory exists first
    local aide_parent_dir="/var/lib/aide"
    if [[ ! -d "$aide_parent_dir" ]]; then
        if ! mkdir -p "$aide_parent_dir" 2>/dev/null; then
            log "ERROR" "Failed to create AIDE parent directory: $aide_parent_dir"
            log "ERROR" "Please run: sudo mkdir -p $aide_parent_dir && sudo chmod 700 $aide_parent_dir"
            exit 1
        fi
        chmod 700 "$aide_parent_dir" 2>/dev/null || true
    fi
    
    if ! mkdir -p "$aide_db_dir" 2>/dev/null; then
        log "ERROR" "Failed to create AIDE database directory: $aide_db_dir"
        exit 1
    fi
    
    # Create minimal AIDE config for our file
    if ! cat > "$custom_aide_config" << EOF
# AIDE config for EDA File Watch Monitor
# Monitoring: $WATCH_FILE

# Database locations
database=file://${AIDE_DB}
database_out=file://${AIDE_DB_NEW}

# Log settings
verbose=5
report_url=stdout

# Define what to check
# p: permissions, u: user, g: group, s: size, m: mtime, c: ctime, md5: MD5 hash
NORMAL = p+u+g+s+m+c+md5

# Monitor our specific file
$WATCH_FILE NORMAL

# Exclude everything else
!/.*
EOF
    then
        log "ERROR" "Failed to create AIDE config file: $custom_aide_config"
        exit 1
    fi
    
    # Update our AIDE_CONFIG to use the custom config
    export AIDE_CONFIG="$custom_aide_config"
    
    # Initialize AIDE database if it doesn't exist
    if [[ ! -f "$AIDE_DB" ]]; then
        log "INFO" "Creating initial AIDE database..."
        if aide --config="$AIDE_CONFIG" --init 2>&1 | grep -v "^$" >/dev/null; then
            # Move new database to active location
            mv "$AIDE_DB_NEW" "$AIDE_DB"
            log "INFO" "AIDE database initialized successfully"
        else
            log "ERROR" "Failed to initialize AIDE database"
            exit 1
        fi
    else
        log "INFO" "AIDE database already exists"
    fi
}

# Check for file changes using AIDE
check_aide_changes() {
    log "DEBUG" "Running AIDE check..."
    
    # Run AIDE check and capture output
    local aide_output
    local aide_exit_code
    
    # Run AIDE with our custom config
    aide_output=$(aide --config="$AIDE_CONFIG" --check 2>&1)
    aide_exit_code=$?
    
    # AIDE exit codes:
    # 0 = No changes
    # 1 = New files added
    # 2 = Files removed  
    # 4 = Files changed
    # Combinations possible (e.g., 3 = new + removed, 7 = all changes)
    # Higher codes indicate errors
    
    if [[ $aide_exit_code -eq 0 ]]; then
        log "DEBUG" "No changes detected"
        return 0
    elif [[ $aide_exit_code -ge 1 && $aide_exit_code -le 7 ]]; then
        log "INFO" "Changes detected in $WATCH_FILE (exit code: $aide_exit_code)"
        # Don't log full AIDE output for security - it may contain sensitive data
        log "DEBUG" "AIDE check completed with changes"
        
        # Extract change details
        local change_details=""
        if echo "$aide_output" | grep -q "$WATCH_FILE"; then
            change_details=$(echo "$aide_output" | grep -A5 "$WATCH_FILE" | head -6)
        fi
        
        # Get current time
        local change_time=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Make API call
        if make_api_call "$WATCH_FILE" "$change_time" "$change_details"; then
            log "INFO" "Successfully processed file change event"
            
            # Update AIDE database with locking
            log "INFO" "Updating AIDE database..."
            local instance_name="${CONFIG_FILE##*/}"
            instance_name="${instance_name%.conf}"
            instance_name="${instance_name:-default}"
            local lock_file="/tmp/aide-${instance_name}.lock"
            (
                flock -x -w 30 200 || {
                    log "ERROR" "Failed to acquire AIDE database lock"
                    return 1
                }
                if aide --config="$AIDE_CONFIG" --update 2>&1 | grep -v "^$" >/dev/null; then
                    # Move new database to active location
                    mv -f "$AIDE_DB_NEW" "$AIDE_DB"
                    log "INFO" "AIDE database updated"
                else
                    log "ERROR" "Failed to update AIDE database"
                fi
            ) 200>"$lock_file"
        else
            log "WARN" "Failed to process file change event, but continuing to monitor"
        fi
        
        return 1
    else
        log "ERROR" "AIDE check failed with exit code $aide_exit_code"
        # Log only first line of error for security
        local error_summary=$(echo "$aide_output" | head -n1)
        log "ERROR" "AIDE error: $error_summary"
        return 2
    fi
}

# Enhanced signal handling
cleanup() {
    log "INFO" "Shutting down AIDE file monitor..."
    # Note: We don't kill AIDE processes as they should complete naturally
    # Killing AIDE mid-operation could corrupt the database
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGHUP

# Main monitoring loop
main() {
    log "INFO" "Starting AIDE-based File Watch Monitor for Ansible Automation Platform"
    log "INFO" "Watching file: $WATCH_FILE"
    log "INFO" "AAP Job Template URL: $API_URL"
    log "INFO" "Check interval: ${CHECK_INTERVAL}s"
    log "INFO" "HTTP Method: $API_METHOD"
    log "INFO" "Request Timeout: ${API_TIMEOUT}s"
    log "INFO" "Retry Count: $RETRY_COUNT"
    log "INFO" "Rate Limit: $RATE_LIMIT calls/minute"
    
    if [[ -z "$API_TOKEN" ]]; then
        log "ERROR" "AAP Authentication token not configured - this is required!"
        exit 1
    fi
    log "INFO" "AAP Authentication: Token configured"
    
    # Initialize AIDE
    init_aide
    
    # Start monitoring
    log "INFO" "Starting AIDE monitoring loop..."
    
    while true; do
        # Check for changes
        check_aide_changes
        
        # Sleep before next check
        log "DEBUG" "Sleeping for ${CHECK_INTERVAL}s before next check..."
        sleep "$CHECK_INTERVAL"
    done
}

# Start the program
load_config
validate_config
main 