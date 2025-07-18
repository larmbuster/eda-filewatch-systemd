# EDA File Watch Monitor with systemd

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