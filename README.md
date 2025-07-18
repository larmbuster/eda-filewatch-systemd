# EDA File Watch Monitor with systemd

![AI Assisted Yes](https://img.shields.io/badge/AI%20Assisted-Yes-green?style=for-the-badge)

⚠️ **This tool is under active development, features may not work entirely or as expected. Use at your own risk!!** ⚠️

A robust systemd service that monitors files for changes and triggers API calls when modifications are detected. Perfect for Event-Driven Architecture (EDA) scenarios where file changes need to trigger downstream processes.

## Features

- **Real-time file monitoring** using Linux inotify
- **Configurable API calls** with custom HTTP methods and timeouts
- **Multiple instance support** - monitor multiple files simultaneously
- **Robust error handling** with automatic retries
- **Comprehensive logging** with configurable log levels
- **Security-focused** with proper systemd security settings
- **Easy installation** with automated setup script

## Prerequisites

- Linux system with systemd
- Root/sudo access for installation
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
| `API_URL` | Yes | - | Complete URL to call when file changes |
| `API_METHOD` | No | `POST` | HTTP method for API calls |
| `API_TIMEOUT` | No | `30` | Timeout for API calls in seconds |
| `API_TOKEN` | No | - | Bearer token for API authentication |
| `RETRY_COUNT` | No | `3` | Number of retry attempts for failed API calls |
| `RETRY_DELAY` | No | `5` | Delay between retry attempts in seconds |
| `RATE_LIMIT` | No | `10` | Maximum API calls per minute |
| `SSL_VERIFY` | No | `true` | Enable/disable SSL certificate verification |
| `SSL_CACERT` | No | - | Path to custom CA certificate file |
| `SSL_CERT` | No | - | Path to client certificate file (mutual TLS) |
| `SSL_KEY` | No | - | Path to client private key file (mutual TLS) |
| `LOG_LEVEL` | No | `INFO` | Log level (DEBUG, INFO, WARN, ERROR) |

### Example Configuration

```bash
# Monitor a configuration file
WATCH_FILE="/etc/myapp/config.json"

# Call webhook when file changes
API_URL="https://api.myservice.com/webhooks/config-changed"

# Use PUT method with longer timeout
API_METHOD="PUT"
API_TIMEOUT=60

# Enable debug logging
LOG_LEVEL="DEBUG"
```

### Example with Ansible Automation Platform

```bash
# Monitor Ansible inventory file
WATCH_FILE="/etc/ansible/inventory/hosts"

# Call Ansible Automation Platform webhook
API_URL="https://ansible.example.com/api/v2/job_templates/123/launch/"

# Use authentication token
API_TOKEN="your-ansible-automation-platform-token"

# Use POST method (default for AAP)
API_METHOD="POST"
API_TIMEOUT=60

# Enable info logging
LOG_LEVEL="INFO"
```

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

# View logs
sudo journalctl -u eda-filewatch@myfile -f

# View recent logs
sudo journalctl -u eda-filewatch@myfile --since "1 hour ago"
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

## API Authentication

The service supports Bearer token authentication for secure API calls:

### Setting Up Authentication

1. **For Ansible Automation Platform:**
   - Generate a personal access token in AAP
   - Add it to your configuration: `API_TOKEN="your-aap-token"`

2. **For other APIs:**
   - Obtain your API token from your service provider
   - Configure it in your instance configuration file

### Security Considerations

- Store tokens securely in configuration files with restricted permissions
- Use environment variables for sensitive tokens in production
- Rotate tokens regularly according to your security policy
- Never commit tokens to version control

## API Payload

When a file change is detected, the service sends a JSON payload to your API endpoint:

```json
{
    "file_path": "/path/to/watched/file.txt",
    "change_time": "2023-12-07 14:30:15",
    "event": "file_modified",
    "hostname": "server-hostname"
}
```

## Security Features

The systemd service includes several security features:

- **Dedicated user/group**: Runs as `eda-filewatch` user with minimal privileges
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

3. **API calls failing:**
   - Test the API endpoint manually with curl
   - Check network connectivity
   - Verify API URL and method in configuration

4. **Permission issues:**
   - Ensure the `eda-filewatch` user can read the watched file
   - Check directory permissions along the path

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

# Run the script
sudo -u eda-filewatch /opt/eda-filewatch/filewatch-monitor.sh
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

# Remove user and group
sudo userdel eda-filewatch
sudo groupdel eda-filewatch

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

/var/log/eda-filewatch/          # Log directory (if needed)
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