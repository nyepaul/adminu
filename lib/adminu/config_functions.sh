#!/bin/bash
# config_functions.sh - Configuration management for AdminU
# Handles config loading/saving, favorites, and history tracking

# Configuration functions
load_config() {
    if [ -f "$ADMINU_DIR/config" ]; then
        source "$ADMINU_DIR/config"
    else
        # Use defaults if config doesn't exist
        init_default_config
    fi
}

save_config() {
    cat > "$ADMINU_DIR/config" << 'EOF'
# AdminU Configuration

# Editor settings
EDITOR="${EDITOR:-vim}"
GUI_EDITOR="code"

# Display settings
VIEW_MODE="grid"              # grid or list
SHOW_STATUS=true              # Status indicators
FAVORITES_FIRST=true          # Show favorites first
RECENT_LIMIT=5                # Recent projects to show

# Performance
ENABLE_CACHE=true
CACHE_TIMEOUT=300             # seconds

# Logging
ENABLE_LOGGING=true
LOG_RETENTION_DAYS=30

# AI
AUTO_UPDATE_DOCS=false        # Auto-update CLAUDE.md/GEMINI.md

# Quick action aliases
QUICK_ACTION_RUN="r"
QUICK_ACTION_TEST="t"
QUICK_ACTION_CLAUDE="c"
QUICK_ACTION_GEMINI="g"
QUICK_ACTION_VIEW="v"
QUICK_ACTION_EDIT="e"
QUICK_ACTION_FILES="f"
QUICK_ACTION_TERMINAL="o"
QUICK_ACTION_STOP="x"
QUICK_ACTION_STATUS="s"
QUICK_ACTION_LOGS="l"
EOF

    chmod 600 "$ADMINU_DIR/config"
}

init_default_config() {
    # Set defaults if not already set
    : "${EDITOR:=vim}"
    : "${GUI_EDITOR:=code}"
    : "${VIEW_MODE:=grid}"
    : "${SHOW_STATUS:=true}"
    : "${FAVORITES_FIRST:=true}"
    : "${RECENT_LIMIT:=5}"
    : "${ENABLE_CACHE:=true}"
    : "${CACHE_TIMEOUT:=300}"
    : "${ENABLE_LOGGING:=true}"
    : "${LOG_RETENTION_DAYS:=30}"
    : "${AUTO_UPDATE_DOCS:=false}"
    : "${QUICK_ACTION_RUN:=r}"
    : "${QUICK_ACTION_TEST:=t}"
    : "${QUICK_ACTION_CLAUDE:=c}"
    : "${QUICK_ACTION_GEMINI:=g}"
    : "${QUICK_ACTION_VIEW:=v}"
    : "${QUICK_ACTION_EDIT:=e}"
    : "${QUICK_ACTION_FILES:=f}"
    : "${QUICK_ACTION_TERMINAL:=o}"
    : "${QUICK_ACTION_STOP:=x}"
    : "${QUICK_ACTION_STATUS:=s}"
    : "${QUICK_ACTION_LOGS:=l}"

    # Create config file if it doesn't exist
    if [ ! -f "$ADMINU_DIR/config" ]; then
        save_config
    fi
}

# Favorites management
add_favorite() {
    local project="$1"

    if [ -z "$project" ]; then
        return 1
    fi

    # Check if already favorite
    if is_favorite "$project"; then
        return 0
    fi

    echo "$project" >> "$ADMINU_DIR/favorites"
    return 0
}

remove_favorite() {
    local project="$1"

    if [ -z "$project" ]; then
        return 1
    fi

    if [ ! -f "$ADMINU_DIR/favorites" ]; then
        return 1
    fi

    # Remove project from favorites
    grep -v "^${project}$" "$ADMINU_DIR/favorites" > "$ADMINU_DIR/favorites.tmp" 2>/dev/null
    mv "$ADMINU_DIR/favorites.tmp" "$ADMINU_DIR/favorites"
    return 0
}

list_favorites() {
    if [ ! -f "$ADMINU_DIR/favorites" ]; then
        return 1
    fi

    cat "$ADMINU_DIR/favorites" 2>/dev/null
    return 0
}

is_favorite() {
    local project="$1"

    if [ -z "$project" ]; then
        return 1
    fi

    if [ ! -f "$ADMINU_DIR/favorites" ]; then
        return 1
    fi

    grep -q "^${project}$" "$ADMINU_DIR/favorites" 2>/dev/null
    return $?
}

toggle_favorite() {
    local project="$1"

    if is_favorite "$project"; then
        remove_favorite "$project"
        echo "removed"
    else
        add_favorite "$project"
        echo "added"
    fi
}

# History management
log_action() {
    local project="$1"
    local action="$2"
    local result="${3:-success}"

    if [ "$ENABLE_LOGGING" != "true" ]; then
        return 0
    fi

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp}|${project}|${action}|${result}" >> "$ADMINU_DIR/history"

    # Clean up old entries if file gets too large
    local line_count=$(wc -l < "$ADMINU_DIR/history" 2>/dev/null || echo 0)
    if [ "$line_count" -gt 1000 ]; then
        tail -500 "$ADMINU_DIR/history" > "$ADMINU_DIR/history.tmp"
        mv "$ADMINU_DIR/history.tmp" "$ADMINU_DIR/history"
    fi

    return 0
}

get_recent_projects() {
    local limit="${1:-5}"

    if [ ! -f "$ADMINU_DIR/history" ]; then
        return 1
    fi

    # Extract unique project names from history, most recent first
    awk -F'|' '{print $2}' "$ADMINU_DIR/history" | \
        tail -50 | \
        awk '!seen[$0]++' | \
        head -"$limit"

    return 0
}

get_recent_actions() {
    local project="$1"
    local limit="${2:-10}"

    if [ ! -f "$ADMINU_DIR/history" ]; then
        return 1
    fi

    # Get recent actions for specific project
    grep "|${project}|" "$ADMINU_DIR/history" | tail -"$limit"
    return 0
}

get_last_action() {
    local project="$1"

    if [ ! -f "$ADMINU_DIR/history" ]; then
        return 1
    fi

    grep "|${project}|" "$ADMINU_DIR/history" | tail -1
    return 0
}

# Cleanup functions
cleanup_old_logs() {
    local retention_days="${LOG_RETENTION_DAYS:-30}"

    if [ ! -d "$ADMINU_DIR/logs" ]; then
        return 0
    fi

    # Find and delete logs older than retention period
    find "$ADMINU_DIR/logs" -type f -name "*.log" -mtime +${retention_days} -delete 2>/dev/null
    return 0
}

cleanup_old_test_results() {
    local retention_count=10

    if [ ! -d "$ADMINU_DIR/project_status" ]; then
        return 0
    fi

    # For each project, keep only the last N test results
    for project_dir in "$ADMINU_DIR/project_status"/*; do
        if [ -d "$project_dir/tests" ]; then
            local test_files=$(find "$project_dir/tests" -type f -name "*.log" 2>/dev/null | wc -l)
            if [ "$test_files" -gt "$retention_count" ]; then
                # Delete oldest test files, keep newest N
                find "$project_dir/tests" -type f -name "*.log" -printf '%T+ %p\n' | \
                    sort | \
                    head -n -${retention_count} | \
                    cut -d' ' -f2- | \
                    xargs -r rm
            fi
        fi
    done

    return 0
}
