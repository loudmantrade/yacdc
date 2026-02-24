# Automated Disk Cleanup for Servers

## Supported Platforms

- ✅ **Linux** (Ubuntu/Debian) - Full support
- ✅ **macOS** - Full support (see [macOS Support Guide](MACOS_SUPPORT.md))

The script automatically detects your operating system and runs appropriate cleanup tasks.

## For Linux (Server len)

## Installed Script

**Location:** `/usr/local/bin/disk_cleanup.sh`

**Schedule:** 
- **Daily:** Every day at 3:00 AM (via cron)
- **On Shutdown:** Automatically before shutdown/reboot (via systemd)

**Log File:** `/var/log/disk_cleanup.log`

**Systemd Service:** `/etc/systemd/system/disk-cleanup-shutdown.service`

## Command-Line Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--days` | `-d` | Days to keep logs | 7 |
| `--max-journal-size` | `-j` | Max journal size (500M, 1G, etc.) | 500M |
| `--thumbnail-age` | `-t` | Max thumbnail age in days | 30 |
| `--truncate-lines` | `-l` | Lines to keep when truncating logs | 10000 |
| `--min-log-size` | `-s` | Min log size for truncation (MB) | 100 |
| `--skip` | `-S` | Skip tasks (comma-separated) | - |
| `--tasks` | `-T` | Execute ONLY specified tasks (comma-separated) | - |
| `--quiet` | `-q` | Quiet mode: no stdout, only stderr for errors | - |
| `--silent` | `-Q` | Silent mode: no stdout, no stderr | - |
| `--log` | `-L` | Log destination: syslog or file path | /var/log/disk_cleanup.log |
| `--dry-run` | - | Preview without actual cleanup | - |
| `--help` | `-h` | Show help message | - |

🔧 **Combining Options:** You can use `-T` (specify tasks) and `-S` (skip some) simultaneously!  
Example: `-T journals,apt,temp -S apt` → executes only `journals` and `temp`

🔊 **Output Modes:**
- Normal: output to stdout and log file
- `-q/--quiet`: only log file, errors to stderr (perfect for cron)
- `-Q/--silent`: only log file, no console output

**Usage:** `/usr/local/bin/disk_cleanup.sh [OPTIONS]`

**Quick Examples:**
```bash
disk_cleanup.sh                           # Default
disk_cleanup.sh -d 14                     # 14 days
disk_cleanup.sh -d 3 -s 50                # Aggressive
disk_cleanup.sh -S apt,kernels            # Skip APT and kernels
disk_cleanup.sh -T journals,oldlogs       # Only journals and logs
disk_cleanup.sh -T journals,apt -S apt    # Only journals (excluding apt)
disk_cleanup.sh -q                        # Quiet mode (for cron)
disk_cleanup.sh -q -L syslog              # Quiet mode with syslog
disk_cleanup.sh --dry-run                 # Preview
```

**What Gets Cleaned:**

1. **systemd Journals** - keeps only last N days (default 7), max SIZE (default 500M)
2. **Old Log Files** - removes archives (.gz, .1, .old) older than N days (default 7)
3. **APT Cache** - cleans package manager cache
4. **Unused Packages** - automatically removes orphaned dependencies
5. **Old Snap Revisions** - removes disabled snap package versions
6. **Snap Cache** - cleans snap package cache
7. **Thumbnails** - removes preview cache older than 30 days
8. **Temporary Files** - removes files from /tmp and /var/tmp older than N days (default 7)
9. **Large Log Files** - truncates .log files >100MB to last 10000 lines

## Management Commands

### Show Help
```bash
ssh len "sudo /usr/local/bin/disk_cleanup.sh --help"
```

### Basic Examples

**Run with default settings (7 days)**
```bash
ssh len "sudo /usr/local/bin/disk_cleanup.sh"
```

**Custom log retention period**
```bash
ssh len "sudo /usr/local/bin/disk_cleanup.sh -d 14"
ssh len "sudo /usr/local/bin/disk_cleanup.sh --days 14"
```

**Preview mode (dry-run)**
```bash
ssh len "sudo /usr/local/bin/disk_cleanup.sh --dry-run"
```

### Advanced Options

**Configure journal size**
```bash
# Allow journals up to 1GB instead of 500MB
ssh len "sudo /usr/local/bin/disk_cleanup.sh --max-journal-size 1G"
```

**Configure thumbnail cleanup**
```bash
# Keep thumbnails for 60 days instead of 30
ssh len "sudo /usr/local/bin/disk_cleanup.sh --thumbnail-age 60"
```

**Configure log truncation**
```bash
# Keep only 5000 lines instead of 10000
ssh len "sudo /usr/local/bin/disk_cleanup.sh --truncate-lines 5000"

# Truncate files larger than 50MB instead of 100MB
ssh len "sudo /usr/local/bin/disk_cleanup.sh --min-log-size 50"
```

**Skip specific tasks**
```bash
# Don't clean APT cache and don't remove old kernels
ssh len "sudo /usr/local/bin/disk_cleanup.sh -S apt,kernels"

# Skip only snap-related tasks
ssh len "sudo /usr/local/bin/disk_cleanup.sh --skip snap-revisions,snap-cache"
```

**Execute only specific tasks (-T/--tasks)**
```bash
# Clean ONLY systemd journals
ssh len "sudo /usr/local/bin/disk_cleanup.sh -T journals"

# Clean ONLY journals and old logs
ssh len "sudo /usr/local/bin/disk_cleanup.sh --tasks journals,oldlogs"

# Clean ONLY apt cache, unused packages and snap cache
ssh len "sudo /usr/local/bin/disk_cleanup.sh -T apt,packages,snap-cache"
```

**Combining -T and -S**
```bash
# Execute journals and oldlogs (exclude apt from list)
ssh len "sudo /usr/local/bin/disk_cleanup.sh -T journals,oldlogs,apt -S apt"

# Execute only journals (exclude temp and apt)
ssh len "sudo /usr/local/bin/disk_cleanup.sh -T journals,apt,temp -S apt,temp"
```

### Combined Examples

**Aggressive cleanup**
```bash
ssh len "sudo /usr/local/bin/disk_cleanup.sh -d 3 -s 50 -l 5000"
# Keep logs for 3 days, truncate files >50MB, keep 5000 lines
```

**Conservative cleanup**
```bash
ssh len "sudo /usr/local/bin/disk_cleanup.sh -d 30 -j 2G -t 90 --skip kernels"
# Keep logs 30 days, journals up to 2GB, thumbnails 90 days, don't touch kernels
```

**Quick cleanup without long operations**
```bash
ssh len "sudo /usr/local/bin/disk_cleanup.sh --skip kernels,packages"
# Skip kernel and package removal (longest operations)
```

### Available Tasks for -S/--skip and -T/--tasks

💡 **How it works:**
- `-S/--skip` - Skip specified tasks, execute all others
- `-T/--tasks` - Execute ONLY specified tasks
- 🔧 Can combine: `-T task1,task2,task3 -S task2` → executes task1 and task3

📝 **Format:**
- ✅ Correct: `-S apt,kernels` or `-T journals,oldlogs`
- ❌ Incorrect: `-S apt -S kernels` (multiple calls)

| Task Name | Description |
|-----------|-------------|
| `journals` | systemd journal cleanup |
| `oldlogs` | Compressed/rotated logs cleanup |
| `apt` | APT cache cleanup |
| `kernels` | Old kernel removal |
| `packages` | Unused packages removal |
| `snap-revisions` | Old snap revisions removal |
| `snap-cache` | Snap cache cleanup |
| `thumbnails` | Thumbnail cache cleanup |
| `temp` | Temporary files cleanup |
| `truncate` | Large log files truncation |

### View Last Cleanup Log
```bash
ssh len "tail -50 /var/log/disk_cleanup.log"
```

### View Cron Status
```bash
ssh len "cat /etc/cron.d/disk-cleanup"
```

### Change Schedule (e.g., to 2:00 AM)
```bash
ssh len "sudo bash -c 'echo \"0 2 * * * root /usr/local/bin/disk_cleanup.sh\" > /etc/cron.d/disk-cleanup'"
```

### Configure Cron with Custom Parameters

**Keep logs for 14 days**
```bash
ssh len "sudo bash -c 'echo \"0 3 * * * root /usr/local/bin/disk_cleanup.sh -d 14\" > /etc/cron.d/disk-cleanup'"
```

**Aggressive cleanup at night**
```bash
ssh len "sudo bash -c 'echo \"0 3 * * * root /usr/local/bin/disk_cleanup.sh -d 3 -s 50\" > /etc/cron.d/disk-cleanup'"
```

**Conservative cleanup with kernel skip**
```bash
ssh len "sudo bash -c 'echo \"0 3 * * * root /usr/local/bin/disk_cleanup.sh -d 30 --skip kernels\" > /etc/cron.d/disk-cleanup'"
```

**Allow large journals**
```bash
ssh len "sudo bash -c 'echo \"0 3 * * * root /usr/local/bin/disk_cleanup.sh -j 2G\" > /etc/cron.d/disk-cleanup'"
```

### Restore Default Cron Settings
```bash
ssh len "sudo bash -c 'echo \"0 3 * * * root /usr/local/bin/disk_cleanup.sh\" > /etc/cron.d/disk-cleanup'"
```

### Disable Automatic Cleanup
```bash
ssh len "sudo rm /etc/cron.d/disk-cleanup"
```

### Re-enable
```bash
ssh len "sudo bash -c 'echo \"0 3 * * * root /usr/local/bin/disk_cleanup.sh\" > /etc/cron.d/disk-cleanup'"
```

## Shutdown Service Management

### Check Service Status
```bash
ssh len "sudo systemctl status disk-cleanup-shutdown.service"
```

### Disable Cleanup on Shutdown
```bash
ssh len "sudo systemctl disable disk-cleanup-shutdown.service"
```

### Enable Cleanup on Shutdown
```bash
ssh len "sudo systemctl enable disk-cleanup-shutdown.service"
```

### View Last Shutdown Logs
```bash
ssh len "sudo journalctl -u disk-cleanup-shutdown.service -n 50"
```

## Current Status

- **Partition Size:** 29GB
- **Used:** 23GB (84%)
- **Free:** 4.5GB
- **Script Tested:** ✓
- **Cron Configured:** ✓ (daily at 3:00 AM)
- **Systemd Service:** ✓ (on shutdown/reboot)
- **CLI Interface:** ✓ Full-featured
- **Architecture:** ✓ Modular (functional code separation)

## CLI Features

- ✅ Configure log retention period (`-d/--days`)
- ✅ Manage journal size (`-j/--max-journal-size`)
- ✅ Configure thumbnail age (`-t/--thumbnail-age`)
- ✅ Control log truncation (`-l/--truncate-lines`, `-s/--min-log-size`)
- ✅ Skip tasks (`-S/--skip`)
- ✅ Execute only specified tasks (`-T/--tasks`)
- 🔧 Combine `-T` and `-S` for precise control
- 🔊 Quiet mode (`-q/--quiet`) for cron
- 🔇 Silent mode (`-Q/--silent`)
- 📝 Choose log destination (`-L/--log`): file or syslog
- ✅ Preview mode (`--dry-run`)
- ✅ Parameter validation with default values
- ✅ Detailed help (`--help`)

## Code Structure

The script is organized modularly:
- **Configuration** - constants and settings
- **Utility Functions** - logging and common tasks
- **Cleanup Functions** - each task in separate function
- **CLI Parsing** - argument processing
- **Main Function** - execution orchestration

See [REFACTORING_NOTES.md](REFACTORING_NOTES.md) for details.

## Cleanup History

Initial run (24.02.2026) freed:
- 1.1GB - systemd journals
- 1.2GB - archived logs
- 0.5GB - old kernel and packages
- 2.1GB - snap cache

**Total freed:** ~5GB (from 100% to 84% usage)
