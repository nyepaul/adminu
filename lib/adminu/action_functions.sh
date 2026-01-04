#!/bin/bash
# action_functions.sh - Project action functions for AdminU
# Handles running, testing, and process management

# Main run function (enhanced from original adminu)
run_project() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")
    local log_file=""

    echo -e "\n${COLOR_YELLOW}═══ Running: $project_name ═══${NC}\n"

    if [ "$ENABLE_LOGGING" = "true" ]; then
        mkdir -p "$ADMINU_DIR/logs/$project_name"
        log_file="$ADMINU_DIR/logs/$project_name/run_$(date +%Y%m%d_%H%M%S).log"
    fi

    cd "$project_dir" || return 1

    # Detect and run based on project type
    if [[ -f "docker-compose.yml" ]]; then
        run_docker_compose "$project_dir" "$log_file"
    elif [[ -f "manage.py" ]]; then
        run_django "$project_dir" "$log_file"
    elif [[ -f "package.json" ]]; then
        run_nodejs "$project_dir" "$log_file"
    elif [[ -f "Makefile" ]]; then
        run_makefile "$project_dir" "$log_file"
    else
        run_custom_script "$project_dir" "$log_file"
    fi

    local exit_code=$?
    log_action "$project_name" "run" "$([ $exit_code -eq 0 ] && echo 'success' || echo 'failed')"

    cd - > /dev/null || true
    pause_for_user
    return $exit_code
}

# Docker Compose handler
run_docker_compose() {
    local project_dir="$1"
    local log_file="$2"

    echo -e "${COLOR_GREEN}Found docker-compose.yml${NC}"
    echo "Run: docker-compose up -d"

    if confirm_action "Execute?"; then
        if [ -n "$log_file" ]; then
            docker-compose up -d 2>&1 | tee "$log_file"
        else
            docker-compose up -d
        fi

        # Save PID if possible
        local project_name=$(basename "$project_dir")
        local container_id=$(docker-compose ps -q 2>/dev/null | head -1)
        if [ -n "$container_id" ]; then
            echo "$container_id" > "$ADMINU_DIR/pids/${project_name}.docker"
            success_message "Docker containers started. Container ID saved."
        fi
    fi
}

# Django handler
run_django() {
    local project_dir="$1"
    local log_file="$2"

    echo -e "${COLOR_GREEN}Found Django project${NC}"
    echo "Options:"
    echo "  1) runserver (default: 0.0.0.0:8000)"
    echo "  2) runserver with custom host:port"
    echo "  3) Cancel"

    local choice
    read -p "Choice [1]: " choice
    choice=${choice:-1}

    case "$choice" in
        1)
            echo "Run: python manage.py runserver"
            if confirm_action "Execute?"; then
                if [ -n "$log_file" ]; then
                    python manage.py runserver 2>&1 | tee "$log_file"
                else
                    python manage.py runserver
                fi
            fi
            ;;
        2)
            read -p "Enter host:port (e.g., 0.0.0.0:8080): " hostport
            if [ -n "$hostport" ]; then
                if [ -n "$log_file" ]; then
                    python manage.py runserver "$hostport" 2>&1 | tee "$log_file"
                else
                    python manage.py runserver "$hostport"
                fi
            fi
            ;;
        *)
            info_message "Cancelled"
            ;;
    esac
}

# Node.js handler
run_nodejs() {
    local project_dir="$1"
    local log_file="$2"

    echo -e "${COLOR_GREEN}Found Node.js project${NC}"

    # Show available scripts
    if grep -q '"scripts"' package.json; then
        echo "Available scripts:"
        grep -A20 '"scripts"' package.json | grep '":' | sed 's/.*"\(.*\)".*/  - \1/'
        echo ""
    fi

    if grep -q '"start"' package.json; then
        echo "Run: npm start"
        if confirm_action "Execute?"; then
            if [ -n "$log_file" ]; then
                npm start 2>&1 | tee "$log_file"
            else
                npm start
            fi
        fi
    else
        read -p "Enter script name (or Enter to skip): " script
        if [ -n "$script" ]; then
            if [ -n "$log_file" ]; then
                npm run "$script" 2>&1 | tee "$log_file"
            else
                npm run "$script"
            fi
        fi
    fi
}

# Makefile handler
run_makefile() {
    local project_dir="$1"
    local log_file="$2"

    echo -e "${COLOR_GREEN}Found Makefile${NC}"
    echo "Available targets:"
    make -qp 2>/dev/null | awk -F':' '/^[a-zA-Z0-9][^$#\/\t=]*:([^=]|$)/ {split($1,A,/ /);for(i in A)print A[i]}' | sort -u | head -20 | sed 's/^/  - /'
    echo ""

    read -p "Enter target to run (or Enter to skip): " target
    if [ -n "$target" ]; then
        if [ -n "$log_file" ]; then
            make "$target" 2>&1 | tee "$log_file"
        else
            make "$target"
        fi
    fi
}

# Custom script handler
run_custom_script() {
    local project_dir="$1"
    local log_file="$2"

    echo -e "${COLOR_YELLOW}No standard run configuration detected${NC}"
    echo ""
    echo "Executable files in directory:"
    find . -maxdepth 1 -type f -executable 2>/dev/null | sed 's|^\./|  - |'
    echo ""

    read -p "Enter script name to run (or Enter to skip): " script
    if [ -n "$script" ]; then
        if [ -n "$log_file" ]; then
            "./$script" 2>&1 | tee "$log_file"
        else
            "./$script"
        fi
    fi
}

# Test function (enhanced from original adminu)
test_project() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local test_log="$ADMINU_DIR/project_status/$project_name/tests/${timestamp}.log"

    echo -e "\n${COLOR_YELLOW}═══ Testing: $project_name ═══${NC}\n"

    mkdir -p "$ADMINU_DIR/project_status/$project_name/tests"

    cd "$project_dir" || return 1

    local start_time=$(date +%s)
    local exit_code=0
    local output=""

    # Detect and run tests
    if [[ -f "manage.py" ]]; then
        run_django_tests "$project_dir" "$test_log"
        exit_code=$?
    elif [[ -f "package.json" ]] && grep -q '"test"' package.json; then
        run_npm_tests "$project_dir" "$test_log"
        exit_code=$?
    elif [[ -f "pytest.ini" ]] || [[ -f "setup.py" ]] || [[ -f "requirements.txt" ]]; then
        run_pytest "$project_dir" "$test_log"
        exit_code=$?
    elif [[ -f "Makefile" ]] && grep -q "^test:" Makefile; then
        run_make_tests "$project_dir" "$test_log"
        exit_code=$?
    elif [[ -f "Cargo.toml" ]]; then
        run_cargo_tests "$project_dir" "$test_log"
        exit_code=$?
    else
        echo -e "${COLOR_YELLOW}No standard test configuration detected${NC}"
        read -p "Enter test command (or Enter to skip): " cmd
        if [ -n "$cmd" ]; then
            eval "$cmd" 2>&1 | tee "$test_log"
            exit_code=${PIPESTATUS[0]}
        fi
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Save test results
    save_test_results "$project_name" "$test_log" "$exit_code" "$duration"

    log_action "$project_name" "test" "$([ $exit_code -eq 0 ] && echo 'passed' || echo 'failed')"

    cd - > /dev/null || true
    pause_for_user
    return $exit_code
}

# Django test handler
run_django_tests() {
    local project_dir="$1"
    local test_log="$2"

    echo -e "${COLOR_GREEN}Running Django tests${NC}"
    python manage.py test 2>&1 | tee "$test_log"
    return ${PIPESTATUS[0]}
}

# npm test handler
run_npm_tests() {
    local project_dir="$1"
    local test_log="$2"

    echo -e "${COLOR_GREEN}Running npm test${NC}"
    npm test 2>&1 | tee "$test_log"
    return ${PIPESTATUS[0]}
}

# pytest handler
run_pytest() {
    local project_dir="$1"
    local test_log="$2"

    echo -e "${COLOR_GREEN}Running pytest${NC}"
    pytest 2>&1 | tee "$test_log"
    return ${PIPESTATUS[0]}
}

# make test handler
run_make_tests() {
    local project_dir="$1"
    local test_log="$2"

    echo -e "${COLOR_GREEN}Running make test${NC}"
    make test 2>&1 | tee "$test_log"
    return ${PIPESTATUS[0]}
}

# cargo test handler
run_cargo_tests() {
    local project_dir="$1"
    local test_log="$2"

    echo -e "${COLOR_GREEN}Running cargo test${NC}"
    cargo test 2>&1 | tee "$test_log"
    return ${PIPESTATUS[0]}
}

# Save test results
save_test_results() {
    local project="$1"
    local test_log="$2"
    local exit_code="$3"
    local duration="$4"

    # Add header to log file
    {
        echo "EXIT_CODE=$exit_code"
        echo "DURATION=$duration"
        echo "TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "---"
        cat "$test_log"
    } > "${test_log}.tmp"
    mv "${test_log}.tmp" "$test_log"

    # Display summary
    echo ""
    if [ "$exit_code" -eq 0 ]; then
        success_message "Tests passed"
    else
        error_message "Tests failed (exit code: $exit_code)"
    fi
    info_message "Duration: ${duration}s"
    info_message "Results saved to: $test_log"

    # Cleanup old results
    cleanup_old_test_results
}

# Show test history
show_test_history() {
    local project="$1"
    local test_dir="$ADMINU_DIR/project_status/$project/tests"

    if [ ! -d "$test_dir" ]; then
        warning_message "No test history found for $project"
        return 1
    fi

    echo ""
    echo -e "${COLOR_YELLOW}Test History: $project${NC}"
    echo ""

    local index=1
    while IFS= read -r test_file; do
        local timestamp=$(basename "$test_file" .log)
        local exit_code=$(grep "EXIT_CODE=" "$test_file" | cut -d= -f2)
        local duration=$(grep "DURATION=" "$test_file" | cut -d= -f2)

        local status="✗ FAILED"
        local color="$COLOR_RED"
        if [ "$exit_code" = "0" ]; then
            status="✓ PASSED"
            color="$COLOR_GREEN"
        fi

        echo -e "$index) ${color}${status}${NC} - ${timestamp} - ${duration}s"
        ((index++))
    done < <(find "$test_dir" -type f -name "*.log" -printf '%T+ %p\n' | sort -r | head -10 | cut -d' ' -f2-)

    echo ""
    return 0
}

# Process management functions
stop_project() {
    local project="$1"
    local pid_file="$ADMINU_DIR/pids/${project}.pid"
    local docker_file="$ADMINU_DIR/pids/${project}.docker"

    # Check for Docker container
    if [ -f "$docker_file" ]; then
        local container_id=$(cat "$docker_file")
        if docker ps -q --filter "id=$container_id" 2>/dev/null | grep -q .; then
            info_message "Stopping Docker container..."
            docker stop "$container_id"
            rm -f "$docker_file"
            success_message "Docker container stopped"
            return 0
        else
            warning_message "Docker container not running"
            rm -f "$docker_file"
        fi
    fi

    # Check for regular PID
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            info_message "Stopping process $pid..."
            kill "$pid"
            rm -f "$pid_file"
            success_message "Process stopped"
            return 0
        else
            warning_message "Process not running"
            rm -f "$pid_file"
        fi
    fi

    warning_message "No running process found for $project"
    return 1
}

show_project_status() {
    local project="$1"
    local project_dir="$SRC_DIR/$project"

    echo ""
    echo -e "${COLOR_YELLOW}═══ Status: $project ═══${NC}"
    echo ""

    # Git status
    if [ -d "$project_dir/.git" ]; then
        local git_status=$(get_git_status "$project_dir")
        echo -e "${COLOR_WHITE}Git:${NC}"
        echo "$git_status" | tr ',' '\n' | sed 's/^/  /'
        echo ""
    fi

    # Services
    local services=$(get_running_services "$project")
    if [ -n "$services" ]; then
        echo -e "${COLOR_WHITE}Services:${NC}"
        echo "$services" | tr ' ' '\n' | sed 's/^/  /'
        echo ""
    else
        echo -e "${COLOR_WHITE}Services:${NC} None running"
        echo ""
    fi

    # Last test
    local test_status=$(get_last_test_result "$project")
    if [ -n "$test_status" ]; then
        echo -e "${COLOR_WHITE}Last Test:${NC} $test_status"
    fi

    echo ""
}

tail_project_logs() {
    local project="$1"
    local log_dir="$ADMINU_DIR/logs/$project"

    if [ ! -d "$log_dir" ]; then
        warning_message "No logs found for $project"
        return 1
    fi

    local latest_log=$(find "$log_dir" -type f -name "*.log" -printf '%T+ %p\n' | sort -r | head -1 | cut -d' ' -f2-)

    if [ -z "$latest_log" ]; then
        warning_message "No log files found"
        return 1
    fi

    info_message "Following: $(basename "$latest_log")"
    info_message "Press Ctrl+C to stop"
    echo ""
    sleep 1
    tail -f "$latest_log"
}
