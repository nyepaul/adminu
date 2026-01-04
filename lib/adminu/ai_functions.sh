#!/bin/bash
# ai_functions.sh - AI assistant integration for AdminU
# Handles Claude Code and Gemini with context gathering

# Launch Claude Code (enhanced from original adminu)
launch_claude_code() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")

    echo -e "\n${COLOR_MAGENTA}═══ Launching Claude Code for: $project_name ═══${NC}\n"

    cd "$project_dir" || return 1

    # Check if claude command exists
    if ! command -v claude &>/dev/null; then
        error_message "Claude Code CLI not found"
        echo "Please install it first or check your PATH"
        pause_for_user
        return 1
    fi

    # Check for CLAUDE.md
    if [ -f "$project_dir/CLAUDE.md" ]; then
        success_message "Found CLAUDE.md"
        local updated=$(stat -c %y "$project_dir/CLAUDE.md" 2>/dev/null | cut -d' ' -f1)
        info_message "Last updated: $updated"
    else
        warning_message "No CLAUDE.md found"
        if confirm_action "Create CLAUDE.md template?"; then
            create_claude_template "$project_dir" "$project_name"
        fi
    fi

    echo ""
    info_message "Starting Claude Code in $project_dir"
    log_action "$project_name" "launch_claude" "success"

    claude

    pause_for_user
    return 0
}

# Launch Claude with context selection
launch_claude_with_context() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")

    display_project_header "$project_name - Claude Code"

    # Show CLAUDE.md status
    if [ -f "$project_dir/CLAUDE.md" ]; then
        local updated=$(stat -c %y "$project_dir/CLAUDE.md" 2>/dev/null | cut -d' ' -f1)
        echo -e "${COLOR_GREEN}✓${NC} CLAUDE.md found (Updated: $updated)"
    else
        echo -e "${COLOR_YELLOW}!${NC} CLAUDE.md not found"
    fi
    echo ""

    # Offer context options
    echo -e "${COLOR_YELLOW}Include context:${NC}"
    echo ""

    local context_items=(
        "Recent commits (last 10)"
        "Uncommitted changes"
        "Test results (last run)"
        "Running services"
        "Environment versions"
    )

    local selected=()
    select_multiple "Select context to include:" context_items selected

    # Generate context notes
    if [ ${#selected[@]} -gt 0 ]; then
        local notes_file="/tmp/claude_context_${project_name}.txt"
        {
            echo "# Context for $project_name"
            echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
            echo ""

            for item in "${selected[@]}"; do
                case "$item" in
                    *"commits"*)
                        echo "## Recent Commits"
                        cd "$project_dir" && git log --oneline -10 2>/dev/null
                        echo ""
                        ;;
                    *"changes"*)
                        echo "## Uncommitted Changes"
                        cd "$project_dir" && git status --short 2>/dev/null
                        echo ""
                        ;;
                    *"Test"*)
                        echo "## Last Test Results"
                        get_last_test_result "$project_name"
                        echo ""
                        ;;
                    *"services"*)
                        echo "## Running Services"
                        get_running_services "$project_name"
                        echo ""
                        ;;
                    *"versions"*)
                        echo "## Environment Versions"
                        get_env_context "$project_dir"
                        echo ""
                        ;;
                esac
            done
        } > "$notes_file"

        info_message "Context saved to: $notes_file"
        echo "You can reference this file when using Claude Code"
        echo ""
    fi

    # Launch options
    echo -e "${COLOR_YELLOW}Launch options:${NC}"
    echo ""
    echo " 1) Launch Claude Code now"
    echo " 2) Update CLAUDE.md first"
    echo " 3) Cancel"
    echo ""

    local choice
    read -p "Choice [1]: " choice
    choice=${choice:-1}

    case "$choice" in
        1)
            cd "$project_dir" && claude
            ;;
        2)
            update_claude_md "$project_dir" "$project_name"
            if confirm_action "Launch Claude Code now?"; then
                cd "$project_dir" && claude
            fi
            ;;
        *)
            info_message "Cancelled"
            ;;
    esac

    pause_for_user
    return 0
}

# Launch Gemini (enhanced from original adminu)
launch_gemini() {
    local project_dir="$1"
    local project_name=$(basename "$project_dir")

    echo -e "\n${COLOR_MAGENTA}═══ Launching Gemini for: $project_name ═══${NC}\n"

    cd "$project_dir" || return 1

    # Check for GEMINI.md
    if [ -f "$project_dir/GEMINI.md" ]; then
        success_message "Found GEMINI.md"
        local updated=$(stat -c %y "$project_dir/GEMINI.md" 2>/dev/null | cut -d' ' -f1)
        info_message "Last updated: $updated"
    else
        warning_message "No GEMINI.md found"
        if confirm_action "Create GEMINI.md template?"; then
            create_gemini_template "$project_dir" "$project_name"
        fi
    fi

    echo ""

    # Try to find gemini CLI or open browser
    if command -v gemini &>/dev/null; then
        info_message "Starting Gemini CLI in $project_dir"
        log_action "$project_name" "launch_gemini" "success"
        gemini
    elif command -v aistudio &>/dev/null; then
        info_message "Starting AI Studio in $project_dir"
        log_action "$project_name" "launch_gemini" "success"
        aistudio
    else
        warning_message "No Gemini CLI found"
        info_message "Opening Google AI Studio in browser..."
        if command -v xdg-open &>/dev/null; then
            xdg-open "https://aistudio.google.com/" 2>/dev/null &
        else
            echo "Please manually navigate to: https://aistudio.google.com/"
        fi
        log_action "$project_name" "launch_gemini_browser" "success"
    fi

    pause_for_user
    return 0
}

# Create CLAUDE.md template
create_claude_template() {
    local project_dir="$1"
    local project_name="$2"
    local project_type=$(detect_project_type "$project_dir")

    cat > "$project_dir/CLAUDE.md" << EOF
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

$project_name - [$project_type project]

Brief description of what this project does.

## Architecture

Describe the high-level architecture and key components.

## Tech Stack

- **Language**:
- **Framework**:
- **Database**:
- **Key Dependencies**:

## Common Commands

### Development

\`\`\`bash
# Install dependencies

# Run development server

# Run tests

\`\`\`

### Building

\`\`\`bash
# Build for production

\`\`\`

## Directory Structure

\`\`\`
$project_name/
├──
└──
\`\`\`

## Common Tasks

### Adding a New Feature

1.
2.
3.

### Running Tests

\`\`\`bash
# Run all tests

# Run specific test

\`\`\`

## Security Considerations

-
-

## Notes

Auto-generated template by AdminU on $(date '+%Y-%m-%d %H:%M:%S')
EOF

    success_message "Created CLAUDE.md template"
    info_message "Please customize it for your project"

    return 0
}

# Create GEMINI.md template
create_gemini_template() {
    local project_dir="$1"
    local project_name="$2"
    local project_type=$(detect_project_type "$project_dir")

    cat > "$project_dir/GEMINI.md" << EOF
# GEMINI.md

Project context for Google Gemini AI.

## Project: $project_name

**Type**: $project_type

## Quick Info

- **Purpose**:
- **Language**:
- **Key Files**:

## Active Technologies

$project_type

## Common Commands

\`\`\`bash
# Development

# Testing

# Build

\`\`\`

## Code Style

-
-

## Recent Changes

Auto-generated template by AdminU on $(date '+%Y-%m-%d %H:%M:%S')
EOF

    success_message "Created GEMINI.md template"
    info_message "Please customize it for your project"

    return 0
}

# Update CLAUDE.md from project state
update_claude_md() {
    local project_dir="$1"
    local project_name="$2"

    if [ ! -f "$project_dir/CLAUDE.md" ]; then
        warning_message "CLAUDE.md not found"
        if confirm_action "Create it now?"; then
            create_claude_template "$project_dir" "$project_name"
        fi
        return 0
    fi

    info_message "Updating CLAUDE.md with current project state..."

    # Backup existing CLAUDE.md
    cp "$project_dir/CLAUDE.md" "$project_dir/CLAUDE.md.bak"

    # Could add auto-update logic here to append recent changes
    # For now, just update timestamp in comments

    success_message "CLAUDE.md backed up to CLAUDE.md.bak"
    info_message "Manual updates recommended for accuracy"

    return 0
}

# Get environment context
get_env_context() {
    local project_dir="$1"

    echo "Environment Information:"

    # Node.js
    if [ -f "$project_dir/package.json" ]; then
        if command -v node &>/dev/null; then
            echo "  Node: $(node --version)"
            echo "  npm: $(npm --version)"
        fi
    fi

    # Python
    if [ -f "$project_dir/requirements.txt" ] || [ -f "$project_dir/setup.py" ]; then
        if command -v python &>/dev/null; then
            echo "  Python: $(python --version 2>&1)"
        fi
        if command -v python3 &>/dev/null; then
            echo "  Python3: $(python3 --version)"
        fi
    fi

    # Rust
    if [ -f "$project_dir/Cargo.toml" ]; then
        if command -v rustc &>/dev/null; then
            echo "  Rust: $(rustc --version)"
        fi
    fi

    # Go
    if [ -f "$project_dir/go.mod" ]; then
        if command -v go &>/dev/null; then
            echo "  Go: $(go version)"
        fi
    fi

    # Docker
    if [ -f "$project_dir/docker-compose.yml" ] || [ -f "$project_dir/Dockerfile" ]; then
        if command -v docker &>/dev/null; then
            echo "  Docker: $(docker --version)"
        fi
    fi

    return 0
}

# Validate CLAUDE.md completeness
validate_claude_md() {
    local project_dir="$1"

    if [ ! -f "$project_dir/CLAUDE.md" ]; then
        echo "missing"
        return 1
    fi

    local content=$(cat "$project_dir/CLAUDE.md")
    local issues=()

    # Check for key sections
    if ! echo "$content" | grep -q "## Overview"; then
        issues+=("Missing Overview section")
    fi

    if ! echo "$content" | grep -q "## Common Commands"; then
        issues+=("Missing Common Commands section")
    fi

    if [ ${#issues[@]} -gt 0 ]; then
        echo "incomplete: ${issues[*]}"
        return 1
    fi

    echo "valid"
    return 0
}
