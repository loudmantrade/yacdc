# Interactive Mode and Ignore Patterns

## Overview

YACDC now supports **interactive mode** and **ignore patterns** for safer and more controlled cleanup operations.

## Interactive Mode (Default)

### How It Works

By default, the script runs in **INTERACTIVE mode**, which means:

1. **Before each cleanup task**, the script shows:
   - List of files/folders that will be cleaned
   - Items marked as ignored (with ⊗ symbol)
   - Count of items to clean vs. ignored items

2. **Asks for confirmation** before proceeding with each task

3. **Respects ignore patterns** from both:
   - Command-line arguments (`-i/--ignore`)
   - Configuration file (`~/.config/yacdc/yacdc_ignore.conf`)

### Example Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📂 User Cache Files (older than 7 days)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✓ /Users/user/Library/Caches/com.app1/cache.db
  ✓ /Users/user/Library/Caches/com.app2/data
  ⊗ /Users/user/Library/Caches/com.important.app (ignored)
  ✓ /Users/user/Library/Caches/temp.cache

Items to clean: 3
Ignored items: 1

Proceed? [y/N]
```

## Non-Interactive Mode

For automation (cron jobs, scripts), use non-interactive mode:

```bash
# Skip all confirmations
./disk_cleanup.sh -y
./disk_cleanup.sh --yes
./disk_cleanup.sh --non-interactive

# Combine with quiet mode for cron
./disk_cleanup.sh -y -q
```

## Ignore Patterns

### Command-Line Ignore

Use `-i` or `--ignore` to specify paths to ignore:

```bash
# Single path
./disk_cleanup.sh -i ~/Documents/important

# Multiple paths (use flag multiple times)
./disk_cleanup.sh -i ~/Documents/work -i ~/Downloads/keep-this.dmg

# Use ~ for home directory
./disk_cleanup.sh -i ~/Photos -i ~/Library/Caches/com.myapp
```

### Configuration File

Create `~/.config/yacdc/yacdc_ignore.conf` for persistent ignore patterns:

**Location:** `~/.config/yacdc/yacdc_ignore.conf`

**Format:**
- One path per line
- Lines starting with `#` are comments
- Use `~` for home directory (will be expanded)
- Paths are matched with prefix matching

**Example:**

```conf
# Documents and important files
~/Documents/important-projects
~/Documents/work

# Specific downloads to keep
~/Downloads/important-installer.dmg
~/Downloads/licenses

# Development caches to preserve
~/Library/Developer/Xcode/DerivedData/MyActiveProject
~/Library/Caches/Homebrew/downloads/critical-package

# Application caches
~/Library/Caches/com.important.app
~/Library/Caches/com.company.essential

# Mail attachments
~/Library/Mail Downloads/contract.pdf

# Trash items to restore later
~/.Trash/important-file-to-review.txt

# iOS backups to keep
~/Library/Application Support/MobileSync/Backup/00000000-0000000000000000
```

### How Ignore Patterns Work

#### Prefix Matching

Paths are matched using **prefix matching**:

```conf
~/Downloads/keep
```

This will ignore:
- `~/Downloads/keep` (exact match)
- `~/Downloads/keep-this-file.txt` (prefix match)
- `~/Downloads/keep/subfolder/file.txt` (prefix match)

#### Loading Priority

1. Configuration file is loaded first
2. Command-line `-i` flags are added to the ignore list
3. All ignore patterns are combined (no duplicates)

#### Example Usage

```bash
# Use both config and command-line ignores
./disk_cleanup.sh -i ~/Downloads/new-important.zip

# This will ignore:
# - Everything in ~/.config/yacdc/yacdc_ignore.conf
# - ~/Downloads/new-important.zip (from command line)
```

## Usage Examples

### Safe Interactive Cleanup

```bash
# Run with default settings, confirm each step
./disk_cleanup.sh

# Preview what would be cleaned
./disk_cleanup.sh --dry-run

# Clean only specific tasks, interactively
./disk_cleanup.sh -T user-caches,trash
```

### Automated Cleanup (Cron)

```bash
# Non-interactive, quiet mode, log to file
./disk_cleanup.sh -y -q -L ~/cleanup.log

# Clean specific tasks automatically
./disk_cleanup.sh -y -q -T user-caches,temp,homebrew
```

### Protected Cleanup

```bash
# Ignore specific paths during cleanup
./disk_cleanup.sh -i ~/Documents/active-project -i ~/Downloads/installer.dmg

# Clean everything except certain apps
./disk_cleanup.sh -i ~/Library/Caches/com.app1 -i ~/Library/Caches/com.app2
```

### Dry-Run Before Real Cleanup

```bash
# Step 1: See what would be cleaned
./disk_cleanup.sh --dry-run -T trash,downloads

# Step 2: If satisfied, run for real
./disk_cleanup.sh -T trash,downloads

# Each task will show files and ask for confirmation
```

## Setup Configuration File

### Create Config Directory

```bash
mkdir -p ~/.config/yacdc
```

### Create Config File

```bash
# Copy example
cp yacdc_ignore.conf.example ~/.config/yacdc/yacdc_ignore.conf

# Or create from scratch
nano ~/.config/yacdc/yacdc_ignore.conf
```

### Example Config for Developers

```conf
# Active development projects
~/Developer/active-projects
~/Library/Developer/Xcode/DerivedData/CurrentProject

# Important downloads
~/Downloads/installers
~/Downloads/documentation

# App caches that shouldn't be cleared
~/Library/Caches/com.jetbrains.intellij
~/Library/Caches/com.docker

# Homebrew packages in use
~/Library/Caches/Homebrew/downloads/node
~/Library/Caches/Homebrew/downloads/python
```

### Example Config for Regular Users

```conf
# Important documents
~/Documents/taxes
~/Documents/legal

# Downloads to keep
~/Downloads/purchased-software
~/Downloads/important-files

# Don't empty these from trash yet
~/.Trash/photo-to-review.jpg
~/.Trash/document-backup.pdf

# Mail attachments
~/Library/Mail Downloads/invoice.pdf
~/Library/Mail Downloads/contract.pdf
```

## Combining Features

### Maximum Safety

```bash
# Interactive + dry-run + ignore patterns
./disk_cleanup.sh --dry-run -i ~/Documents -i ~/Photos
```

### Selective Automated Cleanup

```bash
# Only safe tasks, non-interactive, with protections
./disk_cleanup.sh -y -q \
  -T temp,user-caches \
  -i ~/Library/Caches/com.important.app \
  -L ~/.local/log/cleanup.log
```

### Conservative Daily Cleanup

```bash
# Safe daily cleanup with confirmations
./disk_cleanup.sh -d 30 -T temp,user-caches,trash
# Will ask before cleaning each category
```

## Scheduling with Interactive Mode Disabled

### Cron Example

```bash
# Edit crontab
crontab -e

# Add daily cleanup at 3 AM (non-interactive)
0 3 * * * /usr/local/bin/disk_cleanup -y -q >> ~/.local/log/cleanup.log 2>&1
```

### LaunchAgent Example

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.yacdc.cleanup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/disk_cleanup</string>
        <string>-y</string>
        <string>-q</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
    </dict>
</dict>
</plist>
```

## Tips

1. **Always use `--dry-run` first** when trying new settings
2. **Start with interactive mode** to see what will be cleaned
3. **Build your ignore config gradually** as you discover important files
4. **Use `-T` to test single tasks** before cleaning everything
5. **Combine `-i` with interactive mode** for one-time protections
6. **Use `-y -q` only in scripts/cron** after testing interactively

## Troubleshooting

### Config File Not Loading

Check the file location:
```bash
ls -la ~/.config/yacdc/yacdc_ignore.conf
```

### Paths Not Being Ignored

- Make sure to use `~` for home directory
- Check for typos in paths
- Remember: prefix matching (not exact match)
- Test with `--dry-run` first

### Too Many Confirmations

Use non-interactive mode:
```bash
./disk_cleanup.sh -y
```

Or clean only specific tasks:
```bash
./disk_cleanup.sh -T user-caches
```

## Version

Interactive mode and ignore patterns added: February 24, 2026
