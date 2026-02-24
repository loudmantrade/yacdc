# Advanced Features of yacdc

## Updated: February 24, 2026

## Added Command-Line Options

### 1. Journal Size Management (`-j, --max-journal-size`)

**Description:** Sets maximum systemd journal size  
**Format:** Number + unit (K, M, G)  
**Default:** 500M  
**Validation:** Format check, fallback to default on error

**Examples:**
```bash
--max-journal-size 1G      # 1 gigabyte
--max-journal-size 200M    # 200 megabytes
-j 2G                      # short form
```

### 2. Thumbnail Cache Age (`-t, --thumbnail-age`)

**Description:** Days to keep thumbnails  
**Format:** Integer (days)  
**Default:** 30  
**Validation:** Minimum 1 day

**Examples:**
```bash
--thumbnail-age 60         # keep 60 days
-t 90                      # keep 90 days
```

### 3. Truncate Lines Count (`-l, --truncate-lines`)

**Description:** How many lines to keep in large log files  
**Format:** Integer  
**Default:** 10000  
**Validation:** Minimum 100 lines

**Examples:**
```bash
--truncate-lines 5000      # keep 5000 lines
-l 20000                   # keep 20000 lines
```

### 4. Minimum Size for Truncation (`-s, --min-log-size`)

**Description:** Minimum log file size in MB for truncation  
**Format:** Integer (megabytes)  
**Default:** 100  
**Validation:** Minimum 1 MB

**Examples:**
```bash
--min-log-size 50          # truncate files >50MB
-s 200                     # truncate files >200MB
```

### 5. Skip Tasks (`-S / --skip`)

**Description:** Skip specific cleanup tasks  
**Format:** Comma-separated list (no spaces)  
**Default:** Execute all  
**Validation:** None (unknown tasks are ignored)

**Available tasks:**
- `journals` - systemd journal cleanup
- `oldlogs` - compressed/rotated logs cleanup
- `apt` - APT cache cleanup
- `kernels` - old kernel removal
- `packages` - unused packages removal
- `snap-revisions` - old snap revisions removal
- `snap-cache` - snap cache cleanup
- `thumbnails` - thumbnail cache cleanup
- `temp` - temporary files cleanup
- `truncate` - large log files truncation

**Examples:**
```bash
-S apt                         # skip only APT
--skip apt,kernels             # skip APT and kernels
-S snap-revisions,snap-cache,thumbnails  # skip multiple snap tasks
```

---

### 6. Execute Only Specified Tasks (`-T / --tasks`)

**Description:** Execute ONLY specified tasks  
**Format:** Comma-separated list (no spaces)  
**Default:** Execute all  
**Combination:** Can be used with `-S` to exclude some tasks

**Available tasks:** same as for `-S` (see above)

**Examples:**
```bash
-T journals                        # execute only journal cleanup
--tasks journals,oldlogs           # only journals and old logs
-T apt,packages,snap-cache         # only apt, packages and snap cache
```

**When to use `-T` instead of `-S`:**
- When you need to execute 2-3 tasks out of 10 → `-T` is shorter
- When you need to quickly clean something specific → `-T journals`
- When you want to exclude 8 tasks → better use `-T task1,task2`

**When to use `-S` instead of `-T`:**
- When you need to skip 1-2 tasks → `-S kernels`
- When you need to execute almost everything → easier to specify what to skip

---

### 7. Combining `-T` and `-S`

🔧 **You can use both options simultaneously!**

**Logic:**
1. First `-T` is applied (filter only needed tasks)
2. Then `-S` is applied (exclude from remaining list)

**Examples:**
```bash
# Execute journals and oldlogs (exclude apt)
-T journals,oldlogs,apt -S apt
# Result: only journals, oldlogs execute

# Execute only journals
-T journals,apt,temp -S apt,temp
# Result: only journals executes

# All snap tasks except snap-cache
-T snap-revisions,snap-cache -S snap-cache
# Result: only snap-revisions executes
```

### 8. Quiet and Silent Modes (`-q, -Q, -L`)

**Quiet Mode (`-q / --quiet`):**  
- No stdout output
- Errors to stderr
- Perfect for cron jobs

**Silent Mode (`-Q / --silent`):**  
- No stdout output
- No stderr output
- Only log file

**Log Destination (`-L / --log`):**  
- `syslog` - write to system log
- `/path/to/file` - write to custom file
- Default: `/var/log/disk_cleanup.log`

**Examples:**
```bash
-q                             # quiet mode
-Q                             # silent mode
-L syslog                      # log to syslog
-L /var/log/custom.log         # custom log file
-q -L syslog                   # quiet + syslog (perfect for cron)
```

## Enhanced --dry-run

Preview mode now shows:
- ✅ All current settings (parameters)
- ✅ List of tasks to be executed
- ✅ `-T` indication (if used)
- ✅ `-S` indication (if used)
- ✅ Visual display (✓ for each task)

**Example output:**
```
========================================
DRY RUN MODE - No actual cleanup will be performed
========================================

Configuration:
  Days to keep logs: 14
  Max journal size: 1G
  Thumbnail max age: 60 days
  Log truncate lines: 5000
  Min log size to truncate: 50MB
  Log destination: syslog
  Executing ONLY tasks: journals,oldlogs,apt
  Skipping tasks: apt

Tasks that would be executed:
  ✓ Clean systemd journals
  ✓ Remove old log files

========================================
```

## Parameter Validation

All parameters are validated:

| Parameter | Validation | On Error |
|-----------|-----------|----------|
| `--days` | Integer ≥ 1 | Default: 7, warning |
| `--max-journal-size` | Format: number+K/M/G | Default: 500M, warning |
| `--thumbnail-age` | Integer ≥ 1 | Default: 30, warning |
| `--truncate-lines` | Integer ≥ 100 | Default: 10000, warning |
| `--min-log-size` | Integer ≥ 1 | Default: 100, warning |
| `-S/--skip` | String list | Unknown tasks ignored |
| `-T/--tasks` | String list | Unknown tasks ignored, combines with `-S` |
| `-L/--log` | Path or "syslog" | Creates directory if needed |

**Validation example:**
```bash
$ yacdc -d abc --max-journal-size invalid --dry-run
Error: Invalid number of days: abc
Using default (7 days).
Warning: Invalid journal size format: invalid
Using default (500M). Format should be like: 100M, 1G, etc.
# ... then continues with default values
```

## Combined Usage Examples

### Scenario 1: Workstation (frequently powered on/off)
```bash
# Conservative cleanup, don't touch kernels
yacdc -d 30 --skip kernels
```

### Scenario 2: Server with limited space
```bash
# Aggressive cleanup
yacdc -d 3 -s 50 -l 5000 -j 200M
```

### Scenario 3: Development server
```bash
# Medium cleanup, skip long operations
yacdc -d 14 --skip kernels,packages
```

### Scenario 4: Production server
```bash
# Safe cleanup with large buffers
yacdc -d 30 -j 2G -s 200 --skip kernels
```

### Scenario 5: Testing new settings
```bash
# First dry-run
yacdc -d 7 -s 30 --dry-run
# If OK, run it
yacdc -d 7 -s 30
```

### Scenario 6: Quick cleanup of specific tasks
```bash
# Clean only journals and apt cache (fast, no package/kernel removal)
yacdc -T journals,apt

# Clean only snap-related tasks
yacdc --tasks snap-revisions,snap-cache
```

### Scenario 7: Combining -T and -S for precise control
```bash
# Execute journals and oldlogs (exclude apt from list)
yacdc -T journals,oldlogs,apt -S apt

# Execute several tasks but exclude some (e.g., for testing)
yacdc -T journals,apt,temp,packages -S packages

# All except one task (e.g., all snap except cache)
yacdc -T snap-revisions,snap-cache -S snap-cache
```

### Scenario 8: Cron with quiet mode
```bash
# Quiet mode with syslog (perfect for cron)
0 3 * * * root /usr/local/bin/yacdc -q -L syslog

# Silent mode with custom parameters
0 3 * * * root /usr/local/bin/yacdc -Q -d 14 -S kernels
```

## Internal Changes

### New Utility Function

```bash
should_skip_task() {
    local task="$1"
    
    # If --tasks is specified, first check if task is in the list
    if [ -n "$TASKS_TO_RUN" ]; then
        if [[ ",$TASKS_TO_RUN," != *",$task,"* ]]; then
            return 0  # true - skip (task is not in TASKS list)
        fi
    fi
    
    # Then check if task is in --skip list
    if [[ ",$SKIP_TASKS," == *",$task,"* ]]; then
        return 0  # true - skip this task
    fi
    
    return 1  # false - don't skip
}
```

### Usage in main()

```bash
# Instead of direct call:
clean_systemd_journals

# Now with check:
should_skip_task "journals" || clean_systemd_journals
```

### Log Functions

```bash
log() {
    # Writes to log destination and stdout (respects quiet/silent modes)
}

log_error() {
    # Writes errors to log destination and stderr (respects silent mode)
}
```

## Compatibility

- ✅ Full backward compatibility
- ✅ Old commands work without changes
- ✅ New parameters are optional
- ✅ Default behavior unchanged
- ✅ Cron and systemd service work without modifications

## Tests

All features tested:

- ✅ Help (`--help`)
- ✅ Dry-run (`--dry-run`)
- ✅ All new parameters (`-d`, `-j`, `-t`, `-l`, `-s`)
- ✅ Skip tasks (`-S/--skip`)
- ✅ Execute only specified tasks (`-T/--tasks`)
- 🔧 Combining `-T` and `-S` (new!)
- 🔊 Quiet mode (`-q/--quiet`)
- 🔇 Silent mode (`-Q/--silent`)
- 📝 Log destination (`-L/--log`)
- ✅ Invalid value validation
- ✅ Parameter combinations
- ✅ Real execution with custom parameters

## Code Size

- Before: 255 lines
- Now: ~500 lines  
- Increase: ~96% (due to extended functionality)

All new features are production-ready and fully tested.
