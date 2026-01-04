# CLAUDE.md - AdminU

This file provides guidance to Claude Code when working with the AdminU project administration system.

## Overview

AdminU is a modular Bash-based project administration menu system that provides a unified interface for managing, running, testing, and enhancing all projects in `~/src`. It features consistent UI, status tracking, favorites, history, and deep integration with Claude Code and Gemini AI assistants.

## Architecture

**Modular Design**: AdminU follows a library-based architecture inspired by security-scanner:

```
/home/paul/src/
├── adminu                         # Main entry point (~565 lines)
├── adminu.old                     # Backup of original version
├── lib/adminu/                    # Shared library modules
│   ├── ui_functions.sh            # Box-drawing, colors, menus (~228 lines)
│   ├── config_functions.sh        # Configuration, favorites, history (~223 lines)
│   ├── project_functions.sh       # Project detection, status (~260 lines)
│   ├── action_functions.sh        # Run, test, process mgmt (~458 lines)
│   ├── file_functions.sh          # File operations, editing (~374 lines)
│   └── ai_functions.sh            # Claude/Gemini integration (~380 lines)
└── .adminu/                       # User data directory
    ├── config                     # User preferences
    ├── favorites                  # Starred projects
    ├── history                    # Recent actions log
    ├── logs/PROJECT_NAME/         # Action output logs
    ├── pids/                      # Process tracking
    └── project_status/            # Per-project metadata
        └── PROJECT_NAME/
            ├── status             # Git, services, test state
            └── tests/             # Test result history
```

## Key Features

### Management
- ★ **Favorites system**: Mark projects as favorites for quick access
- **Recent projects**: Quick access based on history
- **Status indicators**: Visual indicators for git changes, test results, running services
- **Search/filter**: Filter projects by name or type

### Launch
- **Background execution**: Run projects with PID tracking
- **Process management**: Stop, restart, show status
- **Log capture**: All operations logged to `.adminu/logs/`
- **Port detection**: Automatic port discovery for services

### Edit
- **Quick file access**: Menu-driven file editing
- **File discovery**: Automatic detection of configs, docs, scripts
- **Editor detection**: Smart editor selection ($EDITOR, vim, nano, code)
- **Sensitive file warnings**: Protection for .env and credential files

### Test
- **Result capture**: All test runs saved with timestamps
- **Test history**: View last 10 runs per project
- **Test comparison**: Diff between test runs
- **Multiple frameworks**: Django, npm, pytest, cargo, make support

### Claude/Gemini Integration
- **Context auto-gathering**: Collect git, test, environment info
- **CLAUDE.md/GEMINI.md**: Auto-update and template generation
- **Template creation**: Generate project documentation templates
- **Validation**: Check documentation completeness

### Menu System
- **Consistent UI**: Box-drawing characters throughout
- **Submenus**: Dedicated menus for View, Run, Test, Edit, Claude, Gemini, Tools, Settings
- **Quick actions**: `#r` (run), `#t` (test), `#c` (claude), etc.
- **Multi-action support**: Execute multiple actions in sequence

## Common Commands

### Running AdminU

```bash
# Launch AdminU
/home/paul/src/adminu

# Quick actions from main menu
5r          # Run project #5
3t          # Test project #3
7c          # Launch Claude Code for project #7
12g         # Launch Gemini for project #12
```

### Library Development

```bash
# Test a specific library in isolation
source /home/paul/src/lib/adminu/ui_functions.sh
SRC_DIR="/home/paul/src"
ADMINU_DIR="/home/paul/src/.adminu"

# Test UI functions
display_main_header
success_message "Test successful"
error_message "Test failed"

# Test project functions
source /home/paul/src/lib/adminu/project_functions.sh
detect_project_type "/home/paul/src/pando"
get_status_indicators "pando"
```

### Debugging

```bash
# Check syntax
bash -n /home/paul/src/adminu
bash -n /home/paul/src/lib/adminu/*.sh

# Enable set -x for tracing
bash -x /home/paul/src/adminu

# Test specific functions
bash -c 'source lib/adminu/project_functions.sh && SRC_DIR="/home/paul/src" && declare -a projects && list_all_projects projects && echo "Found: ${#projects[@]}"'
```

## Project Type Detection

AdminU automatically detects project types by checking for indicator files:

```bash
detect_project_type() {
    [[ -f "$project_dir/package.json" ]] && types="${types}Node.js "
    [[ -f "$project_dir/requirements.txt" ]] && types="${types}Python "
    [[ -f "$project_dir/Cargo.toml" ]] && types="${types}Rust "
    [[ -f "$project_dir/go.mod" ]] && types="${types}Go "
    [[ -f "$project_dir/Makefile" ]] && types="${types}Make "
    [[ -f "$project_dir/docker-compose.yml" ]] && types="${types}Docker "
    [[ -f "$project_dir/manage.py" ]] && types="${types}Django "
    ls "$project_dir"/*.sh &>/dev/null && types="${types}Bash "
}
```

## Status Indicators

Visual symbols show project state:

- `★` Favorite
- `✓` Last test passed
- `✗` Last test failed
- `↻` Git changes pending
- `⚠` Issues detected
- `◆` Docker running
- `●` Systemd service active

## Configuration

Edit `/home/paul/src/.adminu/config`:

```bash
# Editor settings
EDITOR="vim"
GUI_EDITOR="code"

# Display
VIEW_MODE="grid"              # grid or list
SHOW_STATUS=true
FAVORITES_FIRST=true
RECENT_LIMIT=5

# Logging
ENABLE_LOGGING=true
LOG_RETENTION_DAYS=30

# Quick action aliases (customizable)
QUICK_ACTION_RUN="r"
QUICK_ACTION_TEST="t"
QUICK_ACTION_CLAUDE="c"
QUICK_ACTION_GEMINI="g"
```

## Adding New Features

### Adding a New Library Function

1. Choose the appropriate library file:
   - `ui_functions.sh` - Display/interaction
   - `project_functions.sh` - Project management
   - `action_functions.sh` - Run/test operations
   - `file_functions.sh` - File operations
   - `ai_functions.sh` - AI integrations
   - `config_functions.sh` - Configuration

2. Add the function with proper error handling:

```bash
my_new_function() {
    local param="$1"

    if [ -z "$param" ]; then
        error_message "Parameter required"
        return 1
    fi

    # Function logic here

    success_message "Operation completed"
    return 0
}
```

3. Use the function in main adminu script or submenus

### Adding a New Submenu

1. Create submenu function in main adminu script:

```bash
my_new_submenu() {
    local project="$1"

    while true; do
        display_project_header "$project - My Feature"

        echo -e "${COLOR_YELLOW}My Options:${NC}"
        echo ""
        echo -e " ${COLOR_GREEN}1)${NC} Option 1"
        echo -e " ${COLOR_GREEN}2)${NC} Option 2"
        echo -e " ${COLOR_GREEN}b)${NC} Back"
        echo ""

        local choice
        read -p "Select option: " choice

        case "$choice" in
            1) my_action_1 "$project" ;;
            2) my_action_2 "$project" ;;
            b|B) return 0 ;;
            *) error_message "Invalid selection"; pause_for_user ;;
        esac
    done
}
```

2. Add to `show_project_menu()` case statement

### Extending Project Type Detection

Add new patterns to `detect_project_type()`:

```bash
[[ -f "$project_dir/pom.xml" ]] && types="${types}Maven "
[[ -f "$project_dir/build.gradle" ]] && types="${types}Gradle "
```

## Troubleshooting

### Projects Not Showing

Check that:
- `SRC_DIR="/home/paul/src"` is correct
- Projects are directories (not files)
- Directory permissions allow reading

Debug:
```bash
find /home/paul/src -maxdepth 1 -type d ! -name ".*" ! -path "/home/paul/src"
```

### Library Not Loading

Error: `Library not found: /home/paul/src/lib/adminu/xxx.sh`

Fix:
```bash
ls -l /home/paul/src/lib/adminu/
# Ensure all 6 libraries exist and are readable
```

### Nameref Issues

When passing arrays to functions, use nameref pattern:

```bash
my_function() {
    local -n result_ref=$1

    # Assign directly to result_ref
    result_ref=()
    while read item; do
        result_ref+=("$item")
    done < <(command)
}

# Call it
declare -a my_array
my_function my_array
echo "${#my_array[@]}"  # Should show count
```

## Security Considerations

- `.env` files trigger warnings before editing
- Sensitive file warnings for credentials
- PID files stored in protected `.adminu/` directory
- History logs may contain sensitive command output - review retention settings
- `.adminu/` directory has 700 permissions

## Testing Strategy

1. **Syntax checking**: `bash -n adminu` and all libraries
2. **Manual testing**: Test each menu option with diverse projects
3. **Project type coverage**: Test with Node.js, Python, Django, Docker, Rust, Go, Make, Bash projects
4. **Error handling**: Test with missing commands, invalid paths, permission issues
5. **Configuration**: Test defaults, custom settings, favorites, history
6. **Backward compatibility**: Ensure all original quick actions still work

## Rollback

If issues arise, restore original:

```bash
cp /home/paul/src/adminu.old /home/paul/src/adminu
```

## Future Enhancements

- Search/filter implementation in main menu
- Favorites sorting integration
- Cache management for performance
- Test watch mode implementation
- Docker service selection menu
- npm script selection from package.json
- Background execution with screen/tmux
- Port detection and display
- Multi-action execution (e.g., `5r,3c,7t`)

---

Created: 2026-01-04
Updated: 2026-01-04
