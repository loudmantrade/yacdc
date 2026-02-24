# macOS Support for YACDC

## Overview

YACDC (Yet Another Console Disk Cleaner) now supports **macOS** in addition to Linux!

The script automatically detects your operating system and executes the appropriate cleanup tasks.

## Supported Operating Systems

- ✅ **Linux** (Ubuntu/Debian)
- ✅ **macOS** (all versions)

## macOS Cleanup Tasks

### System Tasks

| Task | Description | Location |
|------|-------------|----------|
| `system-caches` | System caches cleanup | `/Library/Caches` |
| `user-caches` | User caches cleanup | `~/Library/Caches` |
| `system-logs` | System logs cleanup | `/var/log` |
| `user-logs` | User logs cleanup | `~/Library/Logs` |
| `temp` | Temporary files | `/tmp`, `/var/tmp`, `/private/tmp` |

### User Tasks

| Task | Description | Location |
|------|-------------|----------|
| `trash` | Empty Trash | `~/.Trash` |
| `downloads` | Old downloads (older than N days) | `~/Downloads` |
| `mail-downloads` | Mail attachments | `~/Library/Mail Downloads` |

### Developer Tasks

| Task | Description | Location |
|------|-------------|----------|
| `homebrew` | Homebrew cache cleanup | `~/Library/Caches/Homebrew` |
| `xcode-derived` | Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` |
| `ios-backups` | Old iOS device backups | `~/Library/Application Support/MobileSync/Backup` |
| `ios-simulators` | iOS simulator caches | `~/Library/Developer/CoreSimulator/Caches` |

### System Maintenance

| Task | Description |
|------|-------------|
| `dns-cache` | Flush DNS cache |
| `font-cache` | Rebuild font cache |

## Usage Examples

### Basic Usage

**Run with default settings (7 days):**
```bash
./yacdc
```

**Preview mode (dry-run):**
```bash
./yacdc --dry-run
```

**Custom retention period:**
```bash
./yacdc -d 14              # Keep logs for 14 days
./yacdc --days 30          # Keep logs for 30 days
```

### Selective Cleanup

**Clean only user data:**
```bash
./yacdc -T user-caches,user-logs,trash,downloads
```

**Clean only developer tools:**
```bash
./yacdc -T homebrew,xcode-derived,ios-simulators
```

**Clean everything except trash and downloads:**
```bash
./yacdc -S trash,downloads
```

**Combine tasks and skip:**
```bash
./yacdc -T user-caches,homebrew,trash -S homebrew
# This will clean only: user-caches and trash
```

### Advanced Options

**Change download retention:**
```bash
./yacdc -d 30              # Delete downloads older than 30 days
```

**Quiet mode (for cron/scheduled tasks):**
```bash
./yacdc -q                 # No stdout, errors to stderr
./yacdc -Q                 # Completely silent
```

**Custom log destination:**
```bash
./yacdc -L ~/cleanup.log   # Log to custom file
./yacdc -L syslog          # Log to system log
```

## Installation on macOS

### Manual Installation

1. **Download the script:**
   ```bash
   curl -O https://raw.githubusercontent.com/loudmantrade/yacdc/main/yacdc
   chmod +x yacdc
   ```

2. **Move to system location:**
   ```bash
   sudo mv yacdc /usr/local/bin/yacdc
   ```

3. **Create log directory:**
   ```bash
   sudo mkdir -p /var/log
   ```

### Automated Scheduling

#### Using cron

**Edit crontab:**
```bash
crontab -e
```

**Add daily cleanup at 3 AM:**
```
0 3 * * * /usr/local/bin/yacdc -q >> /var/log/disk_cleanup.log 2>&1
```

**Weekly cleanup on Sunday at 4 AM:**
```
0 4 * * 0 /usr/local/bin/yacdc -q >> /var/log/disk_cleanup.log 2>&1
```

#### Using LaunchAgent (macOS preferred method)

**Create plist file:**
```bash
sudo nano /Library/LaunchDaemons/com.yacdc.cleanup.plist
```

**Add content:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.yacdc.cleanup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/yacdc</string>
        <string>-q</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/var/log/disk_cleanup.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/disk_cleanup.log</string>
</dict>
</plist>
```

**Load the service:**
```bash
sudo launchctl load /Library/LaunchDaemons/com.yacdc.cleanup.plist
```

**Check status:**
```bash
sudo launchctl list | grep yacdc
```

## Permission Requirements

Some tasks require elevated privileges:

- `dns-cache` - requires sudo
- `font-cache` - requires sudo
- `system-caches` - may require sudo for some files
- `system-logs` - requires sudo

**Run with sudo for full functionality:**
```bash
sudo ./yacdc
```

## Differences from Linux Version

| Feature | Linux | macOS |
|---------|-------|-------|
| Journal cleanup | systemd journals | System logs |
| Package manager | APT | Homebrew |
| Snap packages | ✓ | ✗ |
| Xcode support | ✗ | ✓ |
| iOS backups | ✗ | ✓ |
| DNS cache flush | ✗ | ✓ |
| Font cache | ✗ | ✓ |

## Troubleshooting

### Permission Denied Errors

Run with sudo:
```bash
sudo ./yacdc
```

### Homebrew Not Found

If you don't have Homebrew installed, the script will skip Homebrew cleanup automatically.

### Font Cache Rebuild Requires Restart

After cleaning font cache, you may need to restart applications or log out/in.

## Safety Features

- **Dry-run mode**: Preview changes before execution
- **Selective cleanup**: Choose specific tasks
- **Error handling**: Script continues even if one task fails
- **Logging**: All actions are logged
- **Age-based deletion**: Files are only deleted if older than N days

## Examples for Common Scenarios

**Developer workstation cleanup:**
```bash
sudo ./yacdc -T homebrew,xcode-derived,ios-simulators,user-caches
```

**Light cleanup (safe for daily use):**
```bash
./yacdc -T temp,user-caches,trash
```

**Aggressive cleanup (monthly):**
```bash
sudo ./yacdc -d 3
```

**Preview before cleanup:**
```bash
sudo ./yacdc --dry-run
```

## Support

For issues, questions, or contributions:
- GitHub: https://github.com/loudmantrade/yacdc
- Report bugs via GitHub Issues

## Version

macOS support added: February 24, 2026
