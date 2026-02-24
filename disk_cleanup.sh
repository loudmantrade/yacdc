#!/bin/bash
# Automated disk cleanup script
# Runs daily to free up disk space
# Usage: disk_cleanup.sh [OPTIONS]
# Default: 7 days

set -uo pipefail

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

# ============================================================================
# UTILITY FUNCTIONS
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
    journalctl --vacuum-time=${DAYS_TO_KEEP}d >> "$LOG_FILE" 2>&1 || true
    journalctl --vacuum-size=$MAX_JOURNAL_SIZE >> "$LOG_FILE" 2>&1 || true
}

clean_old_log_files() {
    log_section "Removing old log files..."
    find /var/log -type f \( -name '*.gz' -o -name '*.1' -o -name '*.old' \) \
        -mtime +${DAYS_TO_KEEP} -delete 2>> "$LOG_FILE" || true
}

clean_apt_cache() {
    log_section "Cleaning APT cache..."
    apt-get clean >> "$LOG_FILE" 2>&1 || true
    apt-get autoclean >> "$LOG_FILE" 2>&1 || true
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
                apt-get remove --purge -y "$kernel" >> "$LOG_FILE" 2>&1 || true
            fi
        done || true
}

remove_unused_packages() {
    log_section "Removing unused packages..."
    apt-get autoremove -y >> "$LOG_FILE" 2>&1 || true
}

clean_snap_revisions() {
    log_section "Removing old snap revisions..."
    snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | \
        while read snapname revision; do
            log "Removing snap: $snapname (revision $revision)"
            snap remove "$snapname" --revision="$revision" >> "$LOG_FILE" 2>&1 || true
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
        -delete 2>> "$LOG_FILE" || true
}

clean_temp_files() {
    log_section "Cleaning old temporary files..."
    find /tmp -type f -atime +${DAYS_TO_KEEP} -delete 2>> "$LOG_FILE" || true
    find /var/tmp -type f -atime +${DAYS_TO_KEEP} -delete 2>> "$LOG_FILE" || true
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
  -h, --help                   Show this help message
  --dry-run                    Show what would be cleaned without actually cleaning

Task names for --skip and --tasks (use comma-separated list):
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

    if [ "$DRY_RUN" = true ]; then
        # Dry-run output respects quiet/silent modes
        if [ "$SILENT_MODE" = false ] && [ "$QUIET_MODE" = false ]; then
            echo "========================================"
            echo "DRY RUN MODE - No actual cleanup will be performed"
            echo "========================================"
            echo ""
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
            echo ""
            echo "========================================"
        fi
        exit 0
    fi

    local date_start=$(date '+%Y-%m-%d %H:%M:%S')
    
    log "========================================"
    log "[$date_start] Starting disk cleanup (keeping logs for $DAYS_TO_KEEP days)..."
    [ -n "$TASKS_TO_RUN" ] && log "Executing ONLY tasks: $TASKS_TO_RUN"
    [ -n "$SKIP_TASKS" ] && log "Skipping tasks: $SKIP_TASKS"
    
    show_disk_usage "Disk usage before cleanup"
    
    # Execute cleanup tasks (skip if requested)
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
