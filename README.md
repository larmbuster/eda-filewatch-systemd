# EDA File Watch Monitor for Ansible Automation Platform

![AI Assisted Yes](https://img.shields.io/badge/AI%20Assisted-Yes-green?style=for-the-badge)

⚠️ **This tool is under active development, features may not work entirely or as expected. Use at your own risk!!** ⚠️

A robust systemd service that monitors files for changes and triggers Ansible Automation Platform (AAP) job template launches when modifications are detected. Specifically designed for seamless integration with AAP's Event-Driven Ansible capabilities, enabling automated responses to file system changes with enhanced error handling and reliability.

## Features

- **Real-time file monitoring** using Linux inotify
- **Enhanced AAP integration** with improved job template launching and error handling
- **Multiple instance support** - monitor multiple files simultaneously
- **Advanced error handling** with automatic retries and better error classification
- **Comprehensive logging** with configurable log levels
- **Root execution** for unrestricted file access across the system
- **Easy installation** with streamlined setup script

## Prerequisites

- Linux system with systemd
- Root/sudo access for installation and service operation
- Required packages: `inotify-tools`, `curl`

### Installing Dependencies

**CentOS/RHEL/Fedora:**
```bash
sudo yum install inotify-tools curl
# or on newer systems:
sudo dnf install inotify-tools curl
```

## Installation

1. **Clone or download the project:**
   ```bash
   git clone <repository-url>
   cd eda-filewatch-systemd
   ```

2. **Run the installation script:**
   ```bash
   sudo ./install.sh
   ```

   Or to create an example configuration for a specific instance:
   ```bash
   sudo ./install.sh myfile
   ```

## Configuration

After installation, create a configuration file for your instance:

```bash
sudo cp /etc/eda-filewatch/config.template /etc/eda-filewatch/myfile.conf
sudo nano /etc/eda-filewatch/myfile.conf
```

### Configuration Options

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `WATCH_FILE` | Yes | - | Absolute path to the file to monitor |
| `API_URL` | Yes | - | AAP job template launch URL (format: `https://server/api/controller/v2/job_templates/ID/launch/`) |
| `API_METHOD` | No | `POST` | HTTP method (must be POST for AAP) |
| `API_TIMEOUT` | No | `30` | Timeout for API calls in seconds |
| `API_TOKEN` | Yes | - | AAP authentication token (generate from AAP UI) |
| `RETRY_COUNT` | No | `3` | Number of retry attempts for failed API calls |
| `RETRY_DELAY` | No | `5` | Delay between retry attempts in seconds |
| `RATE_LIMIT` | No | `10` | Maximum API calls per minute |
| `DEBOUNCE_DELAY` | No | `2` | Wait time in seconds after last file event before triggering API call |
| `SSL_VERIFY` | No | `true` | Enable/disable SSL certificate verification |
| `SSL_CACERT` | No | - | Path to custom CA certificate file |
| `SSL_CERT` | No | - | Path to client certificate file (mutual TLS) |
| `SSL_KEY` | No | - | Path to client private key file (mutual TLS) |
| `LOG_LEVEL` | No | `INFO` | Log level (DEBUG, INFO, WARN, ERROR) |

### Example Configuration

```bash
# Monitor an Ansible inventory file
WATCH_FILE="/etc/ansible/inventory/hosts"

# AAP job template launch URL
API_URL="https://aap.example.com/api/controller/v2/job_templates/42/launch/"

# Required for AAP
API_METHOD="POST"
API_TOKEN="your-aap-authentication-token"

# For self-signed certificates
SSL_VERIFY="false"

# Enable debug logging
LOG_LEVEL="DEBUG"
```

### Generating AAP Authentication Token

1. Log into your AAP web interface
2. Navigate to Users → Your Username → Tokens
3. Click "Add" to create a new token
4. Provide a description and scope ("Write" for job launching)
5. Copy the generated token to your configuration file

## Usage

### Starting the Service

```bash
# Enable service to start on boot
sudo systemctl enable eda-filewatch@myfile

# Start the service
sudo systemctl start eda-filewatch@myfile
```

### Managing the Service

```bash
# Check service status
sudo systemctl status eda-filewatch@myfile

# Stop the service
sudo systemctl stop eda-filewatch@myfile

# Restart the service
sudo systemctl restart eda-filewatch@myfile

# View logs from journal
sudo journalctl -u eda-filewatch@myfile -f

# View recent logs from journal
sudo journalctl -u eda-filewatch@myfile --since "1 hour ago"

# View logs from file (also available in /var/log/eda-filewatch/)
sudo tail -f /var/log/eda-filewatch/myfile.log
```

### Multiple Instances

You can run multiple instances to monitor different files:

```bash
# Create configurations for different files
sudo cp /etc/eda-filewatch/config.template /etc/eda-filewatch/config-file.conf
sudo cp /etc/eda-filewatch/config.template /etc/eda-filewatch/data-file.conf

# Configure each instance for different files
sudo nano /etc/eda-filewatch/config-file.conf
sudo nano /etc/eda-filewatch/data-file.conf

# Start multiple instances
sudo systemctl enable eda-filewatch@config-file
sudo systemctl enable eda-filewatch@data-file
sudo systemctl start eda-filewatch@config-file
sudo systemctl start eda-filewatch@data-file
```

## SSL/Certificate Handling

The service provides comprehensive SSL certificate handling for secure API communications:

### Certificate Validation Options

1. **Default (Secure)**: Full SSL certificate verification
   ```bash
   SSL_VERIFY="true"  # Default behavior
   ```

2. **Self-Signed Certificates**: Disable verification (use with caution)
   ```bash
   SSL_VERIFY="false"
   ```

3. **Custom CA Certificate**: Use internal/corporate CA
   ```bash
   SSL_CACERT="/etc/ssl/certs/company-ca.pem"
   ```

4. **Mutual TLS**: Client certificate authentication
   ```bash
   SSL_CERT="/etc/ssl/certs/client.pem"
   SSL_KEY="/etc/ssl/private/client.key"
   ```

### Common Certificate Scenarios

| Scenario | Configuration | Example |
|----------|---------------|---------|
| **Public API** | Default settings | `SSL_VERIFY="true"` |
| **Internal API (Self-signed)** | Disable verification | `SSL_VERIFY="false"` |
| **Corporate Network** | Custom CA | `SSL_CACERT="/etc/ssl/certs/corporate.pem"` |
| **High Security** | Mutual TLS | `SSL_CERT` + `SSL_KEY` |

### Error Handling

The service now properly handles SSL certificate errors:

- **Certificate validation failures**: Logged with specific error messages
- **Custom CA loading errors**: Validated during startup
- **Client certificate issues**: Detected and reported
- **Retry logic**: Distinguishes SSL errors from network failures

### Security Best Practices

- ✅ **Keep SSL_VERIFY="true"** for production environments
- ✅ **Use custom CA certificates** instead of disabling verification
- ✅ **Secure certificate files** with proper permissions (600)
- ✅ **Rotate certificates** regularly
- ⚠️ **Only use SSL_VERIFY="false"** for testing/development

## AAP Authentication

The service requires AAP authentication for launching job templates:

### Token Setup

1. Generate a personal access token in AAP (see example above)
2. Add it to your configuration: `API_TOKEN="your-aap-token"`
3. Ensure the token has "Write" scope for job template launching

### Security Best Practices

- Store tokens in configuration files with 600 permissions
- Use AAP's token expiration features
- Rotate tokens regularly
- Monitor token usage in AAP's activity stream
- Never commit tokens to version control

## AAP Integration

The service provides enhanced integration with Ansible Automation Platform, ensuring reliable job template execution with improved error handling.

### Job Template Launching

When a file change is detected, the service launches an AAP job template with the following extra variables:

```json
{
    "extra_vars": {
        "file_path": "/path/to/watched/file.txt",
        "change_time": "2023-12-07 14:30:15",
        "event": "file_modified",
        "hostname": "server-hostname"
    }
}
```

These variables are available in your Ansible playbooks as:
- `{{ file_path }}` - The full path of the modified file
- `{{ change_time }}` - When the change was detected
- `{{ event }}` - The type of change (always "file_modified")
- `{{ hostname }}` - The hostname of the system running the monitor

## Security Features

The systemd service includes several security features:

- **Root privileges**: Service now runs as root to ensure access to all monitored files
- **Filesystem restrictions**: Limited access to only necessary directories
- **No new privileges**: Prevents privilege escalation
- **Resource limits**: CPU and memory limits to prevent resource exhaustion
- **Private temporary directory**: Isolated temporary files

## Enhanced Security & Reliability

The monitoring script includes several security and reliability improvements:

### Security Enhancements
- **Safe config loading**: Validates config file syntax before execution
- **JSON payload escaping**: Prevents injection attacks through file paths
- **Input validation**: Comprehensive validation of all configuration parameters
- **Permission checking**: Warns about overly permissive config file permissions

### Reliability Improvements
- **Retry logic**: Configurable retry attempts with exponential backoff
- **Rate limiting**: Prevents API endpoint overload (configurable calls/minute)
- **Enhanced error handling**: Distinguishes between client/server errors
- **Improved monitoring**: Uses FIFOs instead of subshells for better signal handling
- **Connection timeouts**: Prevents hanging on network issues
- **Event debouncing**: Prevents duplicate API calls from rapid file changes (configurable delay)

## Troubleshooting

### Common Issues

1. **Service fails to start:**
   ```bash
   # Check service status and logs
   sudo systemctl status eda-filewatch@myfile
   sudo journalctl -u eda-filewatch@myfile
   ```

2. **File not being monitored:**
   - Ensure the file exists and is accessible
   - Check file permissions
   - Verify the path in configuration is absolute

3. **AAP job template not launching:**
   - Verify the job template ID exists in AAP
   - Check token has proper permissions
   - Test manually: `curl -X POST -H "Authorization: Bearer $TOKEN" $API_URL`
   - Verify AAP URL format matches: `/api/controller/v2/job_templates/ID/launch/`

4. **Permission issues:**
   - Service runs as root to ensure file access
   - Verify the watched file path is correct and accessible

### Log Levels

- **DEBUG**: Detailed information including API payloads
- **INFO**: General information about file changes and API calls
- **WARN**: Warning messages about non-critical issues
- **ERROR**: Error messages about failures

### Manual Testing

Test the monitoring script manually:

```bash
# Set environment variables
export WATCH_FILE="/path/to/your/file.txt"
export API_URL="https://your-api-endpoint.com/webhook"
export LOG_LEVEL="DEBUG"

# Run the script as root
sudo /opt/eda-filewatch/filewatch-monitor.sh
```

## Uninstallation

To remove the service:

```bash
# Stop all instances
sudo systemctl stop eda-filewatch@*

# Disable all instances
sudo systemctl disable eda-filewatch@*

# Remove files
sudo rm -f /etc/systemd/system/eda-filewatch@.service
sudo rm -rf /opt/eda-filewatch
sudo rm -rf /etc/eda-filewatch
sudo rm -rf /var/log/eda-filewatch

# Note: Service runs as root, no dedicated user/group to remove

# Reload systemd
sudo systemctl daemon-reload
```

## File Structure

```
/opt/eda-filewatch/
├── filewatch-monitor.sh          # Main monitoring script

/etc/eda-filewatch/
├── config.template               # Configuration template
└── *.conf                       # Instance configurations

/etc/systemd/system/
└── eda-filewatch@.service       # Systemd service template

/var/log/eda-filewatch/          # Log files for each instance (*.log)
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review the logs with `journalctl`
3. Create an issue on the project repository 