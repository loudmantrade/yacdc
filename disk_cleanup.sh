#!/bin/bash
# Automated disk cleanup script
# Runs daily to free up disk space
# Usage: disk_cleanup.sh [OPTIONS]
# Default: 7 days
# Supports: Linux (Ubuntu/Debian) and macOS

set -uo pipefail

# ============================================================================
# OS DETECTION
# ============================================================================

detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            echo "linux"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

readonly OS_TYPE=$(detect_os)

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_NAME=$(basename "$0")

# Default values (can be overridden by command line arguments)
DAYS_TO_KEEP=7
MAX_JOURNAL_SIZE="500M"
THUMBNAIL_MAX_AGE=30
LOG_TRUNCATE_LINES=10000
LARGE_LOG_SIZE="100"  # in MB
DRY_RUN=false
SKIP_TASKS=""
TASKS_TO_RUN=""
QUIET_MODE=false
SILENT_MODE=false
LOG_DESTINATION="/var/log/disk_cleanup.log"
INTERACTIVE_MODE=true
IGNORE_PATHS=""
CONFIG_FILE="${HOME}/.config/yacdc/yacdc_ignore.conf"

# Try to use /var/log, fall back to user's home on permission errors
if [ ! -w "/var/log" ] && [ ! -w "$LOG_DESTINATION" ]; then
    LOG_DESTINATION="${HOME}/.local/log/disk_cleanup.log"
    mkdir -p "$(dirname "$LOG_DESTINATION")" 2>/dev/null || true
fi

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

load_ignore_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log "Loading ignore configuration from $CONFIG_FILE"
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            # Expand ~ to home directory
            line="${line/#\~/$HOME}"
            if [ -n "$IGNORE_PATHS" ]; then
                IGNORE_PATHS="$IGNORE_PATHS:$line"
            else
                IGNORE_PATHS="$line"
            fi
        done < "$CONFIG_FILE"
    fi
}

is_ignored() {
    local path="$1"
    local expanded_path="${path/#\~/$HOME}"
    
    if [ -z "$IGNORE_PATHS" ]; then
        return 1  # false - not ignored
    fi
    
    IFS=':' read -ra IGNORE_ARRAY <<< "$IGNORE_PATHS"
    for ignore_pattern in "${IGNORE_ARRAY[@]}"; do
        # Expand ~ in ignore pattern
        ignore_pattern="${ignore_pattern/#\~/$HOME}"
        
        # Check if path matches ignore pattern
        if [[ "$expanded_path" == "$ignore_pattern"* ]] || [[ "$expanded_path" == "$ignore_pattern" ]]; then
            return 0  # true - ignored
        fi
    done
    
    return 1  # false - not ignored
}

confirm_action() {
    local message="$1"
    
    # Skip confirmation in non-interactive modes
    if [ "$INTERACTIVE_MODE" = false ] || [ "$QUIET_MODE" = true ] || [ "$SILENT_MODE" = true ]; then
        return 0  # proceed
    fi
    
    echo ""
    echo "$message"
    read -p "Proceed? [y/N] " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0  # proceed
    else
        log "Skipped by user"
        return 1  # skip
    fi
}

show_paths_to_clean() {
    local description="$1"
    shift
    local paths=("$@")
    
    if [ "$INTERACTIVE_MODE" = false ] || [ "$QUIET_MODE" = true ] || [ "$SILENT_MODE" = true ]; then
        return
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📂 $description"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local count=0
    local ignored_count=0
    
    for path in "${paths[@]}"; do
        if is_ignored "$path"; then
            echo "  ⊗ $path (ignored)"
            ((ignored_count++))
        else
            echo "  ✓ $path"
            ((count++))
        fi
    done
    
    echo ""
    echo "Items to clean: $count"
    [ $ignored_count -gt 0 ] && echo "Ignored items: $ignored_count"
}

# ============================================================================
# ORIGINAL UTILITY FUNCTIONS
# ============================================================================

log() {
    local message="$1"
    
    # Write to log destination
    if [ "$LOG_DESTINATION" = "syslog" ]; then
        logger -t "disk_cleanup" "$message"
    else
        echo "$message" >> "$LOG_DESTINATION"
    fi
    
    # Write to stdout based on mode
    if [ "$SILENT_MODE" = false ] && [ "$QUIET_MODE" = false ]; then
        echo "$message"
    fi
}

log_section() {
    local message="$1"
    local date=$(date '+%Y-%m-%d %H:%M:%S')
    log "[$date] $message"
}

log_error() {
    local message="$1"
    local date=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to log destination
    if [ "$LOG_DESTINATION" = "syslog" ]; then
        logger -t "disk_cleanup" -p user.err "ERROR: $message"
    else
        echo "[$date] ERROR: $message" >> "$LOG_DESTINATION"
    fi
    
    # Write to stderr based on mode
    if [ "$SILENT_MODE" = false ]; then
        echo "[$date] ERROR: $message" >&2
    fi
}

show_disk_usage() {
    local label="$1"
    log "$label:"
    local disk_info=$(df -h / | grep -v Filesystem)
    
    # Write to log
    if [ "$LOG_DESTINATION" = "syslog" ]; then
        logger -t "disk_cleanup" "$disk_info"
    else
        echo "$disk_info" >> "$LOG_DESTINATION"
    fi
    
    # Write to stdout based on mode
    if [ "$SILENT_MODE" = false ] && [ "$QUIET_MODE" = false ]; then
        echo "$disk_info"
    fi
}

should_skip_task() {
    local task="$1"
    
    # If --tasks is specified, first check if task is in the list
    if [ -n "$TASKS_TO_RUN" ]; then
        if [[ ",$TASKS_TO_RUN," != *",$task,"* ]]; then
            return 0  # true - skip (task is not in TASKS list)
        fi
    fi
    
    # Then check if task is in --skip list (this works with or without --tasks)
    if [[ ",$SKIP_TASKS," == *",$task,"* ]]; then
        return 0  # true - skip this task
    fi
    
    return 1  # false - don't skip
}

# ============================================================================
# CLEANUP FUNCTIONS
# ============================================================================

clean_systemd_journals() {
    log_section "Cleaning systemd journals..."
    journalctl --vacuum-time=${DAYS_TO_KEEP}d >> "$LOG_DESTINATION" 2>&1 || true
    journalctl --vacuum-size=$MAX_JOURNAL_SIZE >> "$LOG_DESTINATION" 2>&1 || true
}

clean_old_log_files() {
    log_section "Removing old log files..."
    find /var/log -type f \( -name '*.gz' -o -name '*.1' -o -name '*.old' \) \
        -mtime +${DAYS_TO_KEEP} -delete 2>> "$LOG_DESTINATION" || true
}

clean_apt_cache() {
    log_section "Cleaning APT cache..."
    apt-get clean >> "$LOG_DESTINATION" 2>&1 || true
    apt-get autoclean >> "$LOG_DESTINATION" 2>&1 || true
}

remove_old_kernels() {
    log_section "Checking for old kernels..."
    local current_kernel=$(uname -r | sed 's/-generic//')
    
    dpkg -l 'linux-image-*' 2>/dev/null | grep '^ii' | awk '{print $2}' | \
        grep -v "$current_kernel" | grep -v 'linux-image-generic' | \
        while read kernel; do
            local kernel_count=$(dpkg -l 'linux-image-[0-9]*' 2>/dev/null | grep '^ii' | wc -l)
            if [ "$kernel_count" -gt 2 ]; then
                log "Removing old kernel: $kernel"
                apt-get remove --purge -y "$kernel" >> "$LOG_DESTINATION" 2>&1 || true
            fi
        done || true
}

remove_unused_packages() {
    log_section "Removing unused packages..."
    apt-get autoremove -y >> "$LOG_DESTINATION" 2>&1 || true
}

clean_snap_revisions() {
    log_section "Removing old snap revisions..."
    snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | \
        while read snapname revision; do
            log "Removing snap: $snapname (revision $revision)"
            snap remove "$snapname" --revision="$revision" >> "$LOG_DESTINATION" 2>&1 || true
        done || true
}

clean_snap_cache() {
    log_section "Cleaning snap cache..."
    if [ -d /var/lib/snapd/cache ]; then
        rm -rf /var/lib/snapd/cache/* 2>/dev/null || true
        log "Snap cache cleaned"
    fi
}

clean_thumbnail_cache() {
    log_section "Cleaning thumbnail caches..."
    find /home/*/.cache/thumbnails -type f -atime +${THUMBNAIL_MAX_AGE} \
        -delete 2>> "$LOG_DESTINATION" || true
}

clean_temp_files() {
    log_section "Cleaning old temporary files..."
    find /tmp -type f -atime +${DAYS_TO_KEEP} -delete 2>> "$LOG_DESTINATION" || true
    find /var/tmp -type f -atime +${DAYS_TO_KEEP} -delete 2>> "$LOG_DESTINATION" || true
}

truncate_large_logs() {
    log_section "Truncating large log files..."
    find /var/log -type f -name "*.log" -size +${LARGE_LOG_SIZE}M 2>/dev/null | \
        while read logfile; do
            log "Truncating large file: $logfile"
            tail -n $LOG_TRUNCATE_LINES "$logfile" > "$logfile.tmp" && \
                mv "$logfile.tmp" "$logfile" || true
        done || true
}

cleanup_own_log() {
    # Don't truncate syslog - it manages itself
    if [ "$LOG_DESTINATION" = "syslog" ]; then
        return
    fi
    
    if [ -f "$LOG_DESTINATION" ]; then
        tail -n $LOG_TRUNCATE_LINES "$LOG_DESTINATION" > "$LOG_DESTINATION.tmp" && \
            mv "$LOG_DESTINATION.tmp" "$LOG_DESTINATION"
    fi
}

# ============================================================================
# MACOS CLEANUP FUNCTIONS
# ============================================================================

clean_macos_system_caches() {
    log_section "Cleaning system caches..."
    if [ -d /Library/Caches ]; then
        find /Library/Caches -type f -atime +${DAYS_TO_KEEP} -delete 2>> "$LOG_DESTINATION" || true
        log "System caches cleaned"
    fi
}

clean_macos_user_caches() {
    log_section "Cleaning user caches..."
    local cache_dir=~/Library/Caches
    
    if [ ! -d "$cache_dir" ]; then
        log "Cache directory not found, skipping"
        return
    fi
    
    # Collect paths to clean
    local paths=()
    while IFS= read -r -d '' file; do
        if ! is_ignored "$file"; then
            paths+=("$file")
        fi
    done < <(find "$cache_dir" -type f -atime +${DAYS_TO_KEEP} -print0 2>/dev/null)
    
    if [ ${#paths[@]} -eq 0 ]; then
        log "No cache files older than ${DAYS_TO_KEEP} days found"
        return
    fi
    
    show_paths_to_clean "User Cache Files (older than ${DAYS_TO_KEEP} days)" "${paths[@]}"
    
    if confirm_action "Clean ${#paths[@]} user cache files?"; then
        for file in "${paths[@]}"; do
            rm -f "$file" 2>> "$LOG_DESTINATION" || true
        done
        log "User caches cleaned (${#paths[@]} files)"
    fi
}

clean_macos_system_logs() {
    log_section "Cleaning system logs..."
    if [ -d /var/log ]; then
        find /var/log -type f \( -name '*.log.*' -o -name '*.gz' \) -mtime +${DAYS_TO_KEEP} \
            -delete 2>> "$LOG_DESTINATION" || true
        log "System logs cleaned"
    fi
}

clean_macos_user_logs() {
    log_section "Cleaning user logs..."
    if [ -d ~/Library/Logs ]; then
        find ~/Library/Logs -type f -mtime +${DAYS_TO_KEEP} -delete 2>> "$LOG_DESTINATION" || true
        log "User logs cleaned"
    fi
}

clean_macos_temp_files() {
    log_section "Cleaning temporary files..."
    find /tmp -type f -atime +${DAYS_TO_KEEP} -delete 2>> "$LOG_DESTINATION" || true
    find /var/tmp -type f -atime +${DAYS_TO_KEEP} -delete 2>> "$LOG_DESTINATION" || true
    [ -d /private/tmp ] && find /private/tmp -type f -atime +${DAYS_TO_KEEP} -delete 2>> "$LOG_DESTINATION" || true
}

clean_macos_trash() {
    log_section "Emptying trash..."
    local trash_dir=~/.Trash
    
    if [ ! -d "$trash_dir" ]; then
        log "Trash directory not found, skipping"
        return
    fi
    
    # Collect trash items
    local paths=()
    for item in "$trash_dir"/*; do
        [ -e "$item" ] || continue
        if ! is_ignored "$item"; then
            paths+=("$item")
        fi
    done
    
    if [ ${#paths[@]} -eq 0 ]; then
        log "Trash is empty"
        return
    fi
    
    show_paths_to_clean "Trash Items" "${paths[@]}"
    
    if confirm_action "Empty trash (${#paths[@]} items)?"; then
        for item in "${paths[@]}"; do
            rm -rf "$item" 2>> "$LOG_DESTINATION" || true
        done
        log "Trash emptied (${#paths[@]} items)"
    fi
}

clean_macos_downloads() {
    log_section "Cleaning old downloads (older than ${DAYS_TO_KEEP} days)..."
    local downloads_dir=~/Downloads
    
    if [ ! -d "$downloads_dir" ]; then
        log "Downloads directory not found, skipping"
        return
    fi
    
    # Collect old downloads
    local paths=()
    while IFS= read -r -d '' file; do
        if ! is_ignored "$file"; then
            paths+=("$file")
        fi
    done < <(find "$downloads_dir" -type f -atime +${DAYS_TO_KEEP} -print0 2>/dev/null)
    
    if [ ${#paths[@]} -eq 0 ]; then
        log "No downloads older than ${DAYS_TO_KEEP} days found"
        return
    fi
    
    show_paths_to_clean "Old Downloads (older than ${DAYS_TO_KEEP} days)" "${paths[@]}"
    
    if confirm_action "Delete ${#paths[@]} old downloads?"; then
        for file in "${paths[@]}"; do
            rm -f "$file" 2>> "$LOG_DESTINATION" || true
        done
        log "Old downloads cleaned (${#paths[@]} files)"
    fi
}

clean_macos_mail_downloads() {
    log_section "Cleaning Mail downloads..."
    local mail_downloads=~/Library/"Mail Downloads"
    if [ -d "$mail_downloads" ]; then
        find "$mail_downloads" -type f -atime +${DAYS_TO_KEEP} -delete 2>> "$LOG_DESTINATION" || true
        log "Mail downloads cleaned"
    fi
}

clean_macos_homebrew() {
    log_section "Cleaning Homebrew cache..."
    if command -v brew &> /dev/null; then
        brew cleanup -s >> "$LOG_DESTINATION" 2>&1 || true
        brew autoremove >> "$LOG_DESTINATION" 2>&1 || true
        rm -rf ~/Library/Caches/Homebrew/* 2>> "$LOG_DESTINATION" || true
        log "Homebrew cache cleaned"
    else
        log "Homebrew not installed, skipping"
    fi
}

clean_macos_xcode_derived() {
    log_section "Cleaning Xcode DerivedData..."
    local derived_data=~/Library/Developer/Xcode/DerivedData
    
    if [ ! -d "$derived_data" ]; then
        log "Xcode DerivedData not found, skipping"
        return
    fi
    
    # Collect derived data folders
    local paths=()
    for item in "$derived_data"/*; do
        [ -e "$item" ] || continue
        if ! is_ignored "$item"; then
            paths+=("$item")
        fi
    done
    
    if [ ${#paths[@]} -eq 0 ]; then
        log "No DerivedData found"
        return
    fi
    
    show_paths_to_clean "Xcode DerivedData Folders" "${paths[@]}"
    
    if confirm_action "Delete ${#paths[@]} DerivedData folders?"; then
        for item in "${paths[@]}"; do
            rm -rf "$item" 2>> "$LOG_DESTINATION" || true
        done
        log "Xcode DerivedData cleaned (${#paths[@]} folders)"
    fi
}

clean_macos_ios_backups() {
    log_section "Cleaning old iOS device backups (older than ${DAYS_TO_KEEP} days)..."
    local backup_dir=~/Library/Application\ Support/MobileSync/Backup
    if [ -d "$backup_dir" ]; then
        find "$backup_dir" -type d -mindepth 1 -maxdepth 1 -mtime +${DAYS_TO_KEEP} \
            -exec rm -rf {} \; 2>> "$LOG_DESTINATION" || true
        log "Old iOS backups cleaned"
    fi
}

clean_macos_ios_simulators() {
    log_section "Cleaning iOS simulator caches..."
    local sim_cache=~/Library/Developer/CoreSimulator/Caches
    if [ -d "$sim_cache" ]; then
        rm -rf "$sim_cache"/* 2>> "$LOG_DESTINATION" || true
        log "iOS simulator caches cleaned"
    fi
}

clean_macos_dns_cache() {
    log_section "Flushing DNS cache..."
    sudo dscacheutil -flushcache >> "$LOG_DESTINATION" 2>&1 || true
    sudo killall -HUP mDNSResponder >> "$LOG_DESTINATION" 2>&1 || true
    log "DNS cache flushed"
}

clean_macos_font_cache() {
    log_section "Cleaning font caches..."
    sudo atsutil databases -remove >> "$LOG_DESTINATION" 2>&1 || true
    log "Font cache cleaned"
}

# ============================================================================
# HELP AND ARGUMENT PARSING
# ============================================================================

show_help() {
    cat << EOF
Disk Cleanup Script - Automated system cleanup

Usage: $SCRIPT_NAME [OPTIONS]

Options:
  -d, --days DAYS              Number of days to keep logs (default: 7)
  -j, --max-journal-size SIZE  Maximum journal size, e.g. 500M, 1G (default: 500M)
  -t, --thumbnail-age DAYS     Thumbnail cache max age in days (default: 30)
  -l, --truncate-lines NUM     Lines to keep when truncating logs (default: 10000)
  -s, --min-log-size MB        Minimum log file size in MB to truncate (default: 100)
  -S, --skip TASKS             Skip specific tasks (comma-separated, no spaces!)
                               Example: --skip apt,kernels,snap-cache
  -T, --tasks TASKS            Execute ONLY specific tasks (comma-separated, no spaces!)
                               Example: --tasks journals,oldlogs,apt
                               Can be combined with --skip to exclude some tasks
  -q, --quiet                  Quiet mode: no stdout, only stderr for errors (for cron)
  -Q, --silent                 Silent mode: no stdout, no stderr (completely silent)
  -L, --log DEST               Log destination: 'syslog' or file path (default: /var/log/disk_cleanup.log)
  -i, --ignore PATH            Ignore specific paths (can be used multiple times)
                               Example: --ignore ~/Documents --ignore ~/Photos
                               Paths can use ~ for home directory
  -y, --yes, --non-interactive Non-interactive mode: skip all confirmations (for automation)
  -h, --help                   Show this help message
  --dry-run                    Show what would be cleaned without actually cleaning

Interactive Mode:
  By default, the script runs in INTERACTIVE mode and will:
  - Show paths to be cleaned before each task
  - Ask for confirmation before proceeding
  - Respect ignore patterns from command line and config file
  
  Use -y/--yes/--non-interactive to skip confirmations (useful for cron jobs)

Ignore Configuration:
  Create ~/.config/yacdc/yacdc_ignore.conf with patterns to ignore:
    # One path per line, comments with #
    ~/Documents/important
    ~/Downloads/keep-this-file.txt
    ~/Library/Caches/com.important.app

Task names for --skip and --tasks (use comma-separated list):
  
  Linux tasks:
  journals        - systemd journal cleanup
  oldlogs         - compressed/rotated logs cleanup
  apt             - APT cache cleanup
  kernels         - old kernel removal
  packages        - unused packages removal
  snap-revisions  - old snap revisions removal
  snap-cache      - snap cache cleanup
  thumbnails      - thumbnail cache cleanup
  temp            - temporary files cleanup
  truncate        - large log files truncation

  macOS tasks:
  system-caches   - system caches cleanup (/Library/Caches)
  user-caches     - user caches cleanup (~/Library/Caches)
  system-logs     - system logs cleanup (/var/log)
  user-logs       - user logs cleanup (~/Library/Logs)
  temp            - temporary files cleanup (/tmp, /var/tmp)
  trash           - empty trash (~/.Trash)
  downloads       - old downloads cleanup (~/Downloads)
  mail-downloads  - Mail attachments cleanup
  homebrew        - Homebrew cache cleanup
  xcode-derived   - Xcode DerivedData cleanup
  ios-backups     - old iOS device backups cleanup
  ios-simulators  - iOS simulator caches cleanup
  dns-cache       - flush DNS cache
  font-cache      - font cache cleanup

Examples:
  Basic usage:
    $SCRIPT_NAME                           # Clean with default settings
    $SCRIPT_NAME -d 14                     # Keep logs for 14 days
    $SCRIPT_NAME -d 3 -s 50                # Aggressive: 3 days, truncate files >50MB
    $SCRIPT_NAME --dry-run                 # Preview cleanup actions

  Advanced options:
    $SCRIPT_NAME --max-journal-size 1G     # Allow journals up to 1GB
    $SCRIPT_NAME --thumbnail-age 60        # Keep thumbnails for 60 days
    $SCRIPT_NAME --truncate-lines 5000     # Keep only 5000 lines in large logs

  Skipping tasks (note: comma-separated, NO spaces):
    $SCRIPT_NAME --skip apt                # Skip ONLY APT cache cleanup
    $SCRIPT_NAME -S apt,kernels            # Skip APT AND kernel cleanup (short form)
    $SCRIPT_NAME --skip snap-revisions,snap-cache,thumbnails
                                           # Skip multiple snap/thumbnail tasks

  Execute only specific tasks:
    $SCRIPT_NAME --tasks journals          # Clean ONLY systemd journals
    $SCRIPT_NAME -T journals,oldlogs       # Clean ONLY journals and old logs (short form)
    $SCRIPT_NAME --tasks apt,packages,snap-cache
                                           # Clean ONLY apt, packages, snap cache

  Combine --tasks and --skip:
    $SCRIPT_NAME -T journals,oldlogs,apt -S apt
                                           # Run journals and oldlogs (exclude apt from list)
    $SCRIPT_NAME --tasks journals,apt,temp --skip temp
                                           # Run journals and apt (exclude temp from list)

  Combined examples:
    $SCRIPT_NAME -d 30 --skip kernels      # Conservative: 30 days, don't touch kernels
    $SCRIPT_NAME -d 7 -s 50 --skip apt,packages
                                           # 7 days, truncate >50MB, skip apt & packages

  Output control:
    $SCRIPT_NAME -q                        # Quiet mode (for cron)
    $SCRIPT_NAME -Q                        # Silent mode (no output at all)
    $SCRIPT_NAME -L syslog                 # Log to system log instead of file
    $SCRIPT_NAME -L /var/log/custom.log    # Log to custom file
    $SCRIPT_NAME -q -L syslog              # Quiet mode with syslog

Description:
  This script cleans:
  - systemd journal logs (older than N days, max size)
  - Compressed/rotated logs (*.gz, *.1, *.old)
  - APT cache
  - Unused packages
  - Old snap revisions
  - Snap cache
  - Thumbnail cache
  - Temporary files in /tmp and /var/tmp
  - Large log files (truncates to specified number of lines)

Output modes:
  Normal: output to stdout and log file
  -q/--quiet: only log file, errors to stderr
  -Q/--silent: only log file, no console output
EOF
    exit 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--days)
                DAYS_TO_KEEP="$2"
                shift 2
                ;;
            -j|--max-journal-size)
                MAX_JOURNAL_SIZE="$2"
                shift 2
                ;;
            -t|--thumbnail-age)
                THUMBNAIL_MAX_AGE="$2"
                shift 2
                ;;
            -l|--truncate-lines)
                LOG_TRUNCATE_LINES="$2"
                shift 2
                ;;
            -s|--min-log-size)
                LARGE_LOG_SIZE="$2"
                shift 2
                ;;
            -S|--skip)
                SKIP_TASKS="$2"
                shift 2
                ;;
            -T|--tasks)
                TASKS_TO_RUN="$2"
                shift 2
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            -Q|--silent)
                SILENT_MODE=true
                QUIET_MODE=true  # Silent implies quiet
                shift
                ;;
            -L|--log)
                LOG_DESTINATION="$2"
                shift 2
                ;;
            -i|--ignore)
                if [ -n "$IGNORE_PATHS" ]; then
                    IGNORE_PATHS="$IGNORE_PATHS:$2"
                else
                    IGNORE_PATHS="$2"
                fi
                shift 2
                ;;
            -y|--yes|--non-interactive)
                INTERACTIVE_MODE=false
                shift
                ;;
            -h|--help)
                show_help
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                [ "$SILENT_MODE" = false ] && echo "Error: Unknown option: $1" >&2
                [ "$SILENT_MODE" = false ] && [ "$QUIET_MODE" = false ] && echo "Use -h or --help for usage information" >&2
                exit 1
                ;;
        esac
    done
}

validate_arguments() {
    # Validate log destination (create directory if needed)
    if [ "$LOG_DESTINATION" != "syslog" ]; then
        local log_dir=$(dirname "$LOG_DESTINATION")
        if [ ! -d "$log_dir" ]; then
            mkdir -p "$log_dir" 2>/dev/null || {
                [ "$SILENT_MODE" = false ] && echo "Error: Cannot create log directory: $log_dir" >&2
                [ "$SILENT_MODE" = false ] && [ "$QUIET_MODE" = false ] && echo "Using /tmp/disk_cleanup.log instead"
                LOG_DESTINATION="/tmp/disk_cleanup.log"
            }
        fi
    fi
    
    # Validate days
    if ! [[ "$DAYS_TO_KEEP" =~ ^[0-9]+$ ]]; then
        [ "$SILENT_MODE" = false ] && echo "Error: Invalid number of days: $DAYS_TO_KEEP" >&2
        [ "$SILENT_MODE" = false ] && [ "$QUIET_MODE" = false ] && echo "Using default (7 days)."
        DAYS_TO_KEEP=7
    fi

    if [ "$DAYS_TO_KEEP" -lt 1 ]; then
        [ "$SILENT_MODE" = false ] && echo "Error: Days must be at least 1" >&2
        exit 1
    fi

    # Validate journal size format (must be like 500M, 1G, etc.)
    if ! [[ "$MAX_JOURNAL_SIZE" =~ ^[0-9]+[KMG]$ ]]; then
        [ "$SILENT_MODE" = false ] && echo "Warning: Invalid journal size format: $MAX_JOURNAL_SIZE" >&2
        [ "$SILENT_MODE" = false ] && [ "$QUIET_MODE" = false ] && echo "Using default (500M). Format should be like: 100M, 1G, etc."
        MAX_JOURNAL_SIZE="500M"
    fi

    # Validate thumbnail age
    if ! [[ "$THUMBNAIL_MAX_AGE" =~ ^[0-9]+$ ]] || [ "$THUMBNAIL_MAX_AGE" -lt 1 ]; then
        [ "$SILENT_MODE" = false ] && echo "Warning: Invalid thumbnail age: $THUMBNAIL_MAX_AGE" >&2
        [ "$SILENT_MODE" = false ] && [ "$QUIET_MODE" = false ] && echo "Using default (30 days)."
        THUMBNAIL_MAX_AGE=30
    fi

    # Validate truncate lines
    if ! [[ "$LOG_TRUNCATE_LINES" =~ ^[0-9]+$ ]] || [ "$LOG_TRUNCATE_LINES" -lt 100 ]; then
        [ "$SILENT_MODE" = false ] && echo "Warning: Invalid truncate lines: $LOG_TRUNCATE_LINES" >&2
        [ "$SILENT_MODE" = false ] && [ "$QUIET_MODE" = false ] && echo "Using default (10000 lines). Minimum is 100."
        LOG_TRUNCATE_LINES=10000
    fi

    # Validate min log size
    if ! [[ "$LARGE_LOG_SIZE" =~ ^[0-9]+$ ]] || [ "$LARGE_LOG_SIZE" -lt 1 ]; then
        [ "$SILENT_MODE" = false ] && echo "Warning: Invalid min log size: $LARGE_LOG_SIZE" >&2
        [ "$SILENT_MODE" = false ] && [ "$QUIET_MODE" = false ] && echo "Using default (100 MB)."
        LARGE_LOG_SIZE=100
    fi
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

main() {
    parse_arguments "$@"
    validate_arguments
    load_ignore_config

    # Check OS compatibility
    if [ "$OS_TYPE" = "unknown" ]; then
        log_error "Unsupported operating system: $(uname -s)"
        log_error "This script supports Linux and macOS only"
        exit 1
    fi

    if [ "$DRY_RUN" = true ]; then
        # Dry-run output respects quiet/silent modes
        if [ "$SILENT_MODE" = false ] && [ "$QUIET_MODE" = false ]; then
            echo "========================================"
            echo "DRY RUN MODE - No actual cleanup will be performed"
            echo "========================================"
            echo ""
            echo "Operating System: $OS_TYPE"
            echo "Configuration:"
            echo "  Days to keep logs: $DAYS_TO_KEEP"
            echo "  Max journal size: $MAX_JOURNAL_SIZE"
            echo "  Thumbnail max age: $THUMBNAIL_MAX_AGE days"
            echo "  Log truncate lines: $LOG_TRUNCATE_LINES"
            echo "  Min log size to truncate: ${LARGE_LOG_SIZE}MB"
            echo "  Log destination: $LOG_DESTINATION"
            [ -n "$TASKS_TO_RUN" ] && echo "  Executing ONLY tasks: $TASKS_TO_RUN"
            [ -n "$SKIP_TASKS" ] && echo "  Skipping tasks: $SKIP_TASKS"
            [ "$QUIET_MODE" = true ] && echo "  Output mode: QUIET"
            echo ""
            echo "Tasks that would be executed:"
            
            if [ "$OS_TYPE" = "linux" ]; then
                should_skip_task "journals" || echo "  ✓ Clean systemd journals"
                should_skip_task "oldlogs" || echo "  ✓ Remove old log files"
                should_skip_task "apt" || echo "  ✓ Clean APT cache"
                should_skip_task "kernels" || echo "  ✓ Remove old kernels"
                should_skip_task "packages" || echo "  ✓ Remove unused packages"
                should_skip_task "snap-revisions" || echo "  ✓ Clean snap revisions"
                should_skip_task "snap-cache" || echo "  ✓ Clean snap cache"
                should_skip_task "thumbnails" || echo "  ✓ Clean thumbnail cache"
                should_skip_task "temp" || echo "  ✓ Clean temporary files"
                should_skip_task "truncate" || echo "  ✓ Truncate large log files"
            elif [ "$OS_TYPE" = "macos" ]; then
                should_skip_task "system-caches" || echo "  ✓ Clean system caches"
                should_skip_task "user-caches" || echo "  ✓ Clean user caches"
                should_skip_task "system-logs" || echo "  ✓ Clean system logs"
                should_skip_task "user-logs" || echo "  ✓ Clean user logs"
                should_skip_task "temp" || echo "  ✓ Clean temporary files"
                should_skip_task "trash" || echo "  ✓ Empty trash"
                should_skip_task "downloads" || echo "  ✓ Clean old downloads"
                should_skip_task "mail-downloads" || echo "  ✓ Clean Mail downloads"
                should_skip_task "homebrew" || echo "  ✓ Clean Homebrew cache"
                should_skip_task "xcode-derived" || echo "  ✓ Clean Xcode DerivedData"
                should_skip_task "ios-backups" || echo "  ✓ Clean old iOS backups"
                should_skip_task "ios-simulators" || echo "  ✓ Clean iOS simulator caches"
                should_skip_task "dns-cache" || echo "  ✓ Flush DNS cache"
                should_skip_task "font-cache" || echo "  ✓ Clean font cache"
            fi
            
            echo ""
            echo "========================================"
        fi
        exit 0
    fi

    local date_start=$(date '+%Y-%m-%d %H:%M:%S')
    
    log "========================================"
    log "[$date_start] Starting disk cleanup on $OS_TYPE (keeping logs for $DAYS_TO_KEEP days)..."
    [ -n "$TASKS_TO_RUN" ] && log "Executing ONLY tasks: $TASKS_TO_RUN"
    [ -n "$SKIP_TASKS" ] && log "Skipping tasks: $SKIP_TASKS"
    
    show_disk_usage "Disk usage before cleanup"
    
    # Execute cleanup tasks based on OS
    if [ "$OS_TYPE" = "linux" ]; then
        should_skip_task "journals" || clean_systemd_journals
        should_skip_task "oldlogs" || clean_old_log_files
        should_skip_task "apt" || clean_apt_cache
        should_skip_task "kernels" || remove_old_kernels
        should_skip_task "packages" || remove_unused_packages
        should_skip_task "snap-revisions" || clean_snap_revisions
        should_skip_task "snap-cache" || clean_snap_cache
        should_skip_task "thumbnails" || clean_thumbnail_cache
        should_skip_task "temp" || clean_temp_files
        should_skip_task "truncate" || truncate_large_logs
    elif [ "$OS_TYPE" = "macos" ]; then
        should_skip_task "system-caches" || clean_macos_system_caches
        should_skip_task "user-caches" || clean_macos_user_caches
        should_skip_task "system-logs" || clean_macos_system_logs
        should_skip_task "user-logs" || clean_macos_user_logs
        should_skip_task "temp" || clean_macos_temp_files
        should_skip_task "trash" || clean_macos_trash
        should_skip_task "downloads" || clean_macos_downloads
        should_skip_task "mail-downloads" || clean_macos_mail_downloads
        should_skip_task "homebrew" || clean_macos_homebrew
        should_skip_task "xcode-derived" || clean_macos_xcode_derived
        should_skip_task "ios-backups" || clean_macos_ios_backups
        should_skip_task "ios-simulators" || clean_macos_ios_simulators
        should_skip_task "dns-cache" || clean_macos_dns_cache
        should_skip_task "font-cache" || clean_macos_font_cache
    fi
    
    show_disk_usage "Disk usage after cleanup"
    
    local date_end=$(date '+%Y-%m-%d %H:%M:%S')
    log "[$date_end] Disk cleanup completed!"
    log "========================================"
    log ""
    
    cleanup_own_log
}

# ============================================================================
# ENTRY POINT
# ============================================================================

main "$@"
