#!/bin/bash
# project_functions.sh - Project detection and management for AdminU
# Handles project discovery, type detection, status tracking

# Project type detection (ported and enhanced from original adminu)
detect_project_type() {
    local project_dir="$1"
    local types=""

    # Check for various project indicators
    [[ -f "$project_dir/package.json" ]] && types="${types}Node.js "
    [[ -f "$project_dir/requirements.txt" ]] && types="${types}Python "
    [[ -f "$project_dir/Cargo.toml" ]] && types="${types}Rust "
    [[ -f "$project_dir/go.mod" ]] && types="${types}Go "
    [[ -f "$project_dir/Makefile" ]] && types="${types}Make "
    [[ -f "$project_dir/docker-compose.yml" ]] && types="${types}Docker "
    [[ -f "$project_dir/manage.py" ]] && types="${types}Django "

    # Check for bash scripts
    if ls "$project_dir"/*.sh &>/dev/null; then
        types="${types}Bash "
    fi

    # Default if nothing detected
    [[ -z "$types" ]] && types="Unknown"

    echo "$types" | xargs  # trim whitespace
}

# List all projects in SRC_DIR
list_all_projects() {
    local -n result_ref=$1

    # Get all directories in SRC_DIR (excluding hidden and SRC_DIR itself)
    result_ref=()
    while IFS= read -r -d '' dir; do
        result_ref+=("$dir")
    done < <(find "$SRC_DIR" -maxdepth 1 -type d ! -name ".*" ! -path "$SRC_DIR" -print0 | sort -z)

    return 0
}

# Get project status (git, services, tests)
get_project_status() {
    local project="$1"
    local project_dir="$SRC_DIR/$project"
    local status_file="$ADMINU_DIR/project_status/$project/status"

    # Create status directory if it doesn't exist
    mkdir -p "$ADMINU_DIR/project_status/$project"

    # Gather status information
    local git_status=$(get_git_status "$project_dir" 2>/dev/null || echo "")
    local services=$(get_running_services "$project" 2>/dev/null || echo "")
    local test_status=$(get_last_test_result "$project" 2>/dev/null || echo "")

    # Save to status file
    cat > "$status_file" << EOF
GIT_STATUS=$git_status
SERVICES=$services
TEST_STATUS=$test_status
UPDATED=$(date '+%Y-%m-%d %H:%M:%S')
EOF

    return 0
}

# Get git status for a project
get_git_status() {
    local project_dir="$1"

    if [ ! -d "$project_dir/.git" ]; then
        echo ""
        return 1
    fi

    cd "$project_dir" || return 1

    local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    local uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
    local ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
    local behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)

    cd - > /dev/null || true

    echo "branch=$branch,uncommitted=$uncommitted,ahead=$ahead,behind=$behind"
    return 0
}

# Get running services (Docker, systemd)
get_running_services() {
    local project="$1"
    local services=""

    # Check Docker containers
    if command -v docker &>/dev/null; then
        local docker_count=$(docker ps --filter "name=${project}" --format "{{.Names}}" 2>/dev/null | wc -l)
        [ "$docker_count" -gt 0 ] && services="${services}docker:$docker_count "
    fi

    # Check systemd services
    if command -v systemctl &>/dev/null; then
        if systemctl is-active "${project}.service" &>/dev/null; then
            services="${services}systemd:active "
        fi
    fi

    echo "$services" | xargs
    return 0
}

# Get last test result
get_last_test_result() {
    local project="$1"
    local test_dir="$ADMINU_DIR/project_status/$project/tests"

    if [ ! -d "$test_dir" ]; then
        echo ""
        return 1
    fi

    # Find most recent test log
    local latest_test=$(find "$test_dir" -type f -name "*.log" -printf '%T+ %p\n' 2>/dev/null | sort -r | head -1 | cut -d' ' -f2-)

    if [ -z "$latest_test" ]; then
        echo ""
        return 1
    fi

    # Extract exit code from log (first line should have it)
    local exit_code=$(head -1 "$latest_test" | grep -oP 'EXIT_CODE=\K\d+' || echo "unknown")

    if [ "$exit_code" = "0" ]; then
        echo "passed"
    elif [ "$exit_code" = "unknown" ]; then
        echo "unknown"
    else
        echo "failed"
    fi

    return 0
}

# Get status indicators for display
get_status_indicators() {
    local project="$1"
    local indicators=""

    # Check favorite
    if is_favorite "$project"; then
        indicators="${indicators}${COLOR_YELLOW}★${NC} "
    fi

    # Check test status
    local test_status=$(get_last_test_result "$project" 2>/dev/null)
    case "$test_status" in
        passed)
            indicators="${indicators}${COLOR_GREEN}✓${NC} "
            ;;
        failed)
            indicators="${indicators}${COLOR_RED}✗${NC} "
            ;;
    esac

    # Check git status
    local project_dir="$SRC_DIR/$project"
    if [ -d "$project_dir/.git" ]; then
        local git_status=$(get_git_status "$project_dir" 2>/dev/null)
        if echo "$git_status" | grep -q "uncommitted=[1-9]"; then
            indicators="${indicators}${COLOR_YELLOW}↻${NC} "
        fi
    fi

    # Check services
    local services=$(get_running_services "$project" 2>/dev/null)
    if echo "$services" | grep -q "docker:"; then
        indicators="${indicators}${COLOR_CYAN}◆${NC} "
    fi
    if echo "$services" | grep -q "systemd:active"; then
        indicators="${indicators}${COLOR_GREEN}●${NC} "
    fi

    echo -e "$indicators"
    return 0
}

# Validate project structure
validate_project_structure() {
    local project_dir="$1"
    local issues=()

    # Check if directory exists
    if [ ! -d "$project_dir" ]; then
        issues+=("Directory does not exist")
        echo "${issues[@]}"
        return 1
    fi

    # Check if readable
    if [ ! -r "$project_dir" ]; then
        issues+=("Directory not readable")
    fi

    # Check for common issues
    if [ ! -f "$project_dir/README.md" ] && [ ! -f "$project_dir/CLAUDE.md" ]; then
        issues+=("No documentation found")
    fi

    if [ ${#issues[@]} -gt 0 ]; then
        echo "${issues[@]}"
        return 1
    fi

    return 0
}

# Search/filter projects
search_projects() {
    local query="$1"
    local -n result_ref=$2

    result_ref=()

    # Get all projects
    local all_projects=()
    list_all_projects all_projects

    # Filter by query
    for project in "${all_projects[@]}"; do
        local project_name=$(basename "$project")
        local project_type=$(detect_project_type "$project")

        # Match against name or type (case-insensitive)
        if echo "$project_name" | grep -iq "$query" || \
           echo "$project_type" | grep -iq "$query"; then
            result_ref+=("$project")
        fi
    done

    return 0
}

# Cache management (for performance)
update_project_cache() {
    local cache_file="$ADMINU_DIR/.project_cache"
    local cache_lock="$ADMINU_DIR/.project_cache.lock"

    # Use lock to prevent concurrent updates
    if [ -f "$cache_lock" ]; then
        return 1
    fi

    touch "$cache_lock"

    {
        echo "# Project cache - auto-generated"
        echo "CACHE_TIME=$(date +%s)"
        echo ""

        local all_projects=()
        list_all_projects all_projects

        for project in "${all_projects[@]}"; do
            local project_name=$(basename "$project")
            local project_type=$(detect_project_type "$project")
            echo "PROJECT:$project_name:$project_type"
        done
    } > "$cache_file"

    rm -f "$cache_lock"
    return 0
}

load_project_cache() {
    local cache_file="$ADMINU_DIR/.project_cache"
    local cache_timeout="${CACHE_TIMEOUT:-300}"

    if [ ! -f "$cache_file" ]; then
        return 1
    fi

    # Check if cache is expired
    local cache_time=$(grep "CACHE_TIME=" "$cache_file" | cut -d= -f2)
    local current_time=$(date +%s)
    local age=$((current_time - cache_time))

    if [ "$age" -gt "$cache_timeout" ]; then
        return 1
    fi

    return 0
}
