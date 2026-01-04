#!/bin/bash
# file_functions.sh - File operations and editing for AdminU
# Handles file discovery, editing, and browsing

# Detect available editor
detect_editor() {
    # Check in order of preference
    if [ -n "$EDITOR" ] && command -v "$EDITOR" &>/dev/null; then
        echo "$EDITOR"
    elif command -v vim &>/dev/null; then
        echo "vim"
    elif command -v nano &>/dev/null; then
        echo "nano"
    elif command -v vi &>/dev/null; then
        echo "vi"
    elif [ -n "$GUI_EDITOR" ] && command -v "$GUI_EDITOR" &>/dev/null; then
        echo "$GUI_EDITOR"
    else
        echo ""
    fi
}

# Find config files in project
find_config_files() {
    local project_dir="$1"
    local -n result_ref=$2

    result_ref=()

    # Common config file patterns
    local patterns=(
        "*.conf"
        "*.config"
        "*.yml"
        "*.yaml"
        "*.json"
        ".env"
        "*.ini"
        "*.toml"
    )

    for pattern in "${patterns[@]}"; do
        while IFS= read -r -d '' file; do
            result_ref+=("$file")
        done < <(find "$project_dir" -maxdepth 2 -type f -name "$pattern" -print0 2>/dev/null)
    done

    return 0
}

# Find documentation files
find_documentation() {
    local project_dir="$1"
    local -n result_ref=$2

    result_ref=()

    # Documentation file patterns
    local patterns=(
        "README*"
        "CLAUDE.md"
        "GEMINI.md"
        "*.md"
        "CONTRIBUTING*"
        "CHANGELOG*"
        "LICENSE*"
    )

    for pattern in "${patterns[@]}"; do
        while IFS= read -r -d '' file; do
            result_ref+=("$file")
        done < <(find "$project_dir" -maxdepth 1 -type f -name "$pattern" -print0 2>/dev/null)
    done

    return 0
}

# Find scripts
find_scripts() {
    local project_dir="$1"
    local -n result_ref=$2

    result_ref=()

    # Find executable scripts
    while IFS= read -r -d '' file; do
        result_ref+=("$file")
    done < <(find "$project_dir" -maxdepth 2 -type f \( -name "*.sh" -o -executable \) -print0 2>/dev/null)

    # Also check for Makefile
    if [ -f "$project_dir/Makefile" ]; then
        result_ref+=("$project_dir/Makefile")
    fi

    return 0
}

# Edit project files menu
edit_project_files() {
    local project="$1"
    local project_dir="$SRC_DIR/$project"

    while true; do
        display_project_header "$project - Edit Files"

        echo -e "${COLOR_YELLOW}Quick Access:${NC}"
        echo ""

        local files=()
        local index=1

        # Add common files if they exist
        if [ -f "$project_dir/README.md" ]; then
            echo -e " ${COLOR_GREEN}${index})${NC} README.md"
            files+=("$project_dir/README.md")
            ((index++))
        fi

        if [ -f "$project_dir/CLAUDE.md" ]; then
            echo -e " ${COLOR_GREEN}${index})${NC} CLAUDE.md"
            files+=("$project_dir/CLAUDE.md")
            ((index++))
        fi

        if [ -f "$project_dir/GEMINI.md" ]; then
            echo -e " ${COLOR_GREEN}${index})${NC} GEMINI.md"
            files+=("$project_dir/GEMINI.md")
            ((index++))
        fi

        if [ -f "$project_dir/docker-compose.yml" ]; then
            echo -e " ${COLOR_GREEN}${index})${NC} docker-compose.yml"
            files+=("$project_dir/docker-compose.yml")
            ((index++))
        fi

        if [ -f "$project_dir/package.json" ]; then
            echo -e " ${COLOR_GREEN}${index})${NC} package.json"
            files+=("$project_dir/package.json")
            ((index++))
        fi

        if [ -f "$project_dir/requirements.txt" ]; then
            echo -e " ${COLOR_GREEN}${index})${NC} requirements.txt"
            files+=("$project_dir/requirements.txt")
            ((index++))
        fi

        if [ -f "$project_dir/.env" ]; then
            echo -e " ${COLOR_GREEN}${index})${NC} .env ${COLOR_RED}[SENSITIVE]${NC}"
            files+=("$project_dir/.env")
            ((index++))
        fi

        echo ""
        echo -e " ${COLOR_GREEN}c)${NC} Browse config files"
        echo -e " ${COLOR_GREEN}d)${NC} Browse documentation"
        echo -e " ${COLOR_GREEN}s)${NC} Browse scripts"
        echo -e " ${COLOR_GREEN}a)${NC} Browse all files"
        echo -e " ${COLOR_GREEN}b)${NC} Back"
        echo ""

        local choice
        read -p "Select file to edit: " choice

        case "$choice" in
            b|B)
                return 0
                ;;
            c|C)
                edit_config_files "$project_dir"
                ;;
            d|D)
                edit_documentation "$project_dir"
                ;;
            s|S)
                edit_scripts "$project_dir"
                ;;
            a|A)
                browse_all_files "$project_dir"
                ;;
            [0-9]*)
                if [ "$choice" -ge 1 ] && [ "$choice" -le ${#files[@]} ]; then
                    edit_file "${files[$((choice-1))]}"
                else
                    error_message "Invalid selection"
                    pause_for_user
                fi
                ;;
            *)
                error_message "Invalid selection"
                pause_for_user
                ;;
        esac
    done
}

# Edit config files
edit_config_files() {
    local project_dir="$1"
    local configs=()

    find_config_files "$project_dir" configs

    if [ ${#configs[@]} -eq 0 ]; then
        warning_message "No config files found"
        pause_for_user
        return 1
    fi

    echo ""
    echo -e "${COLOR_YELLOW}Config Files:${NC}"
    echo ""

    local index=1
    for file in "${configs[@]}"; do
        local rel_path="${file#$project_dir/}"
        echo -e " ${COLOR_GREEN}${index})${NC} $rel_path"
        ((index++))
    done

    echo ""
    local choice
    read -p "Select file to edit (or 0 to cancel): " choice

    if [ "$choice" -ge 1 ] && [ "$choice" -le ${#configs[@]} ]; then
        edit_file "${configs[$((choice-1))]}"
    fi
}

# Edit documentation
edit_documentation() {
    local project_dir="$1"
    local docs=()

    find_documentation "$project_dir" docs

    if [ ${#docs[@]} -eq 0 ]; then
        warning_message "No documentation files found"
        pause_for_user
        return 1
    fi

    echo ""
    echo -e "${COLOR_YELLOW}Documentation Files:${NC}"
    echo ""

    local index=1
    for file in "${docs[@]}"; do
        local rel_path="${file#$project_dir/}"
        echo -e " ${COLOR_GREEN}${index})${NC} $rel_path"
        ((index++))
    done

    echo ""
    local choice
    read -p "Select file to edit (or 0 to cancel): " choice

    if [ "$choice" -ge 1 ] && [ "$choice" -le ${#docs[@]} ]; then
        edit_file "${docs[$((choice-1))]}"
    fi
}

# Edit scripts
edit_scripts() {
    local project_dir="$1"
    local scripts=()

    find_scripts "$project_dir" scripts

    if [ ${#scripts[@]} -eq 0 ]; then
        warning_message "No scripts found"
        pause_for_user
        return 1
    fi

    echo ""
    echo -e "${COLOR_YELLOW}Scripts:${NC}"
    echo ""

    local index=1
    for file in "${scripts[@]}"; do
        local rel_path="${file#$project_dir/}"
        echo -e " ${COLOR_GREEN}${index})${NC} $rel_path"
        ((index++))
    done

    echo ""
    local choice
    read -p "Select file to edit (or 0 to cancel): " choice

    if [ "$choice" -ge 1 ] && [ "$choice" -le ${#scripts[@]} ]; then
        edit_file "${scripts[$((choice-1))]}"
    fi
}

# Browse all files
browse_all_files() {
    local project_dir="$1"

    info_message "Opening file manager in $project_dir"

    if command -v xdg-open &>/dev/null; then
        xdg-open "$project_dir" &
    elif command -v nautilus &>/dev/null; then
        nautilus "$project_dir" &
    elif command -v dolphin &>/dev/null; then
        dolphin "$project_dir" &
    else
        warning_message "No file manager found. Use terminal to browse."
        echo "Directory: $project_dir"
        pause_for_user
    fi
}

# Edit a file
edit_file() {
    local file="$1"

    if [ ! -f "$file" ]; then
        error_message "File not found: $file"
        pause_for_user
        return 1
    fi

    # Warn if editing sensitive file
    if [[ "$file" == *".env"* ]] || [[ "$file" == *"credential"* ]] || [[ "$file" == *"secret"* ]]; then
        warning_message "This is a sensitive file!"
        if ! confirm_action "Continue editing?"; then
            return 0
        fi
    fi

    local editor=$(detect_editor)

    if [ -z "$editor" ]; then
        error_message "No editor found. Set \$EDITOR environment variable."
        pause_for_user
        return 1
    fi

    info_message "Opening with $editor..."
    sleep 0.5

    "$editor" "$file"

    return 0
}

# Edit specific file types
edit_readme() {
    local project="$1"
    local project_dir="$SRC_DIR/$project"

    if [ -f "$project_dir/CLAUDE.md" ]; then
        edit_file "$project_dir/CLAUDE.md"
    elif [ -f "$project_dir/README.md" ]; then
        edit_file "$project_dir/README.md"
    else
        warning_message "No README or CLAUDE.md found"
        if confirm_action "Create CLAUDE.md?"; then
            touch "$project_dir/CLAUDE.md"
            edit_file "$project_dir/CLAUDE.md"
        fi
    fi
}

edit_env() {
    local project="$1"
    local project_dir="$SRC_DIR/$project"

    if [ -f "$project_dir/.env" ]; then
        warning_message "Editing sensitive .env file!"
        if confirm_action "Continue?"; then
            edit_file "$project_dir/.env"
        fi
    else
        warning_message "No .env file found"
        if confirm_action "Create .env?"; then
            touch "$project_dir/.env"
            chmod 600 "$project_dir/.env"
            edit_file "$project_dir/.env"
        fi
    fi
}

edit_docker_compose() {
    local project="$1"
    local project_dir="$SRC_DIR/$project"

    if [ -f "$project_dir/docker-compose.yml" ]; then
        edit_file "$project_dir/docker-compose.yml"
    else
        warning_message "No docker-compose.yml found"
        pause_for_user
    fi
}

edit_package_json() {
    local project="$1"
    local project_dir="$SRC_DIR/$project"

    if [ -f "$project_dir/package.json" ]; then
        edit_file "$project_dir/package.json"
    else
        warning_message "No package.json found"
        pause_for_user
    fi
}

edit_requirements() {
    local project="$1"
    local project_dir="$SRC_DIR/$project"

    if [ -f "$project_dir/requirements.txt" ]; then
        edit_file "$project_dir/requirements.txt"
    else
        warning_message "No requirements.txt found"
        pause_for_user
    fi
}
