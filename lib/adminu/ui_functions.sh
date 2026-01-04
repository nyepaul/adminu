#!/bin/bash
# ui_functions.sh - UI/Display helper functions for AdminU
# Provides consistent box-drawing, colors, menus, and user interaction

# Color definitions (consistent with security-scanner pattern)
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[1;37m'
readonly COLOR_MAGENTA='\033[0;35m'
readonly COLOR_BOLD='\033[1m'
readonly NC='\033[0m'

# Helper to get consistent width
get_ui_width() {
    local term_width=$(tput cols 2>/dev/null || echo 80)
    # Cap width at 100 to avoid being too wide on large screens, min 60
    if [ "$term_width" -gt 100 ]; then
        echo 100
    elif [ "$term_width" -lt 60 ]; then
        echo 60
    else
        echo "$term_width"
    fi
}

# Box-drawing helper functions (ported from security-scanner)
# Style: Single thin line, Green color
readonly BOX_COLOR="${COLOR_GREEN}"

draw_box_top() {
    local width="${1:-60}"
    echo -ne "${BOX_COLOR}┌"
    printf '─%.0s' $(seq 1 $((width-2)))
    echo -e "┐${NC}"
}

draw_box_bottom() {
    local width="${1:-60}"
    echo -ne "${BOX_COLOR}└"
    printf '─%.0s' $(seq 1 $((width-2)))
    echo -e "┘${NC}"
}

draw_box_separator() {
    local width="${1:-60}"
    echo -ne "${BOX_COLOR}├"
    printf '─%.0s' $(seq 1 $((width-2)))
    echo -e "┤${NC}"
}

draw_box_line() {
    local content="$1"
    local width="${2:-60}"

    # Strip ANSI codes for length calculation
    local visual_content=$(strip_ansi "$content")
    local content_len=${#visual_content}
    local padding=$((width - content_len - 3))
    
    # Safety check for negative padding
    [ $padding -lt 0 ] && padding=0

    echo -ne "${BOX_COLOR}│${NC} ${content}"
    printf "%${padding}s" ""
    echo -e "${BOX_COLOR}│${NC}"
}

draw_box_centered() {
    local content="$1"
    local width="${2:-60}"
    
    local visual_content=$(strip_ansi "$content")
    local content_len=${#visual_content}
    local left_pad=$(( (width - content_len - 2) / 2 ))
    local right_pad=$(( width - content_len - left_pad - 2 ))
    
    echo -ne "${BOX_COLOR}│${NC}"
    printf "%${left_pad}s" ""
    echo -ne "${content}"
    printf "%${right_pad}s" ""
    echo -e "${BOX_COLOR}│${NC}"
}

# Display headers
display_main_header() {
    local width=$(get_ui_width)
    clear
    echo ""
    draw_box_top $width
    draw_box_centered "${COLOR_WHITE}AdminU - Project Administration${NC}" $width
    draw_box_bottom $width
    echo ""

    # Display stats if available
    local total_projects=$(find "$SRC_DIR" -maxdepth 1 -type d ! -name ".*" ! -path "$SRC_DIR" 2>/dev/null | wc -l)
    local favorites_count=0
    [ -f "$ADMINU_DIR/favorites" ] && favorites_count=$(wc -l < "$ADMINU_DIR/favorites" 2>/dev/null || echo 0)

    echo -e "${COLOR_WHITE}Host:${NC} ${COLOR_GREEN}$(hostname)${NC}  ${COLOR_WHITE}Date:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${COLOR_WHITE}Projects:${NC} ${COLOR_GREEN}$total_projects${NC}  ${COLOR_WHITE}Favorites:${NC} ${COLOR_YELLOW}$favorites_count${NC}"
    echo ""
}

display_project_header() {
    local project_name="$1"
    local width=$(get_ui_width)

    clear
    echo ""
    draw_box_top $width
    draw_box_centered "${COLOR_WHITE}Project: $project_name${NC}" $width
    draw_box_bottom $width
    echo ""
}

display_footer() {
    echo ""
    echo -e "${COLOR_BLUE}Working directory: $SRC_DIR${COLOR_RESET}"
    echo -e "${COLOR_BLUE}Time: $(date '+%H:%M:%S')${COLOR_RESET}"
}

# Message functions (ported from security-scanner)
error_message() {
    local message="$1"
    echo -e "${COLOR_RED}[✗] ERROR: $message${NC}" >&2
}

success_message() {
    local message="$1"
    echo -e "${COLOR_GREEN}[✓] SUCCESS: $message${NC}"
}

warning_message() {
    local message="$1"
    echo -e "${COLOR_YELLOW}[!] WARNING: $message${NC}"
}

info_message() {
    local message="$1"
    echo -e "${COLOR_CYAN}[i] INFO: $message${NC}"
}

# User interaction functions
pause_for_user() {
    echo ""
    read -p "Press Enter to continue..." -r
}

confirm_action() {
    local prompt="$1"
    local response

    while true; do
        read -p "$prompt [y/N]: " -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                return 0
                ;;
            [nN][oO]|[nN]|"")
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Menu rendering functions
render_menu() {
    local title="$1"
    shift
    local items=("$@")
    local width=$(get_ui_width)

    draw_box_top $width
    draw_box_line "${COLOR_YELLOW}${title}${NC}" $width
    draw_box_separator $width

    for item in "${items[@]}"; do
        draw_box_line "$item" $width
    done

    draw_box_bottom $width
    echo ""
}

# Helper to strip ANSI codes for length calculations
strip_ansi() {
    echo -e "$1" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g'
}

render_project_list() {
    local view_mode="${VIEW_MODE:-grid}"
    local projects=("$@")
    local width=$(get_ui_width)
    
    # Calculate column width: (Total - margin) / 2
    # Margin: 2 chars left padding + 2 chars gap
    local col_width=$(( (width - 4) / 2 ))
    
    # Enforce minimum column width or fallback to list view
    if [ "$col_width" -lt 30 ]; then
        view_mode="list"
    fi

    if [ ${#projects[@]} -eq 0 ]; then
        warning_message "No projects found in $SRC_DIR"
        return 1
    fi

    echo -e "${COLOR_YELLOW}Available Projects:${NC}"
    echo ""

    if [ "$view_mode" = "grid" ]; then
        # Two-column layout
        local index=1
        for project in "${projects[@]}"; do
            local project_name=$(basename "$project")
            local project_type=$(detect_project_type "$project" 2>/dev/null || echo "")
            local status_icons=$(get_status_indicators "$project_name" 2>/dev/null || echo "")

            # Format: " 1) project-name [Type] ★"
            local display="${COLOR_GREEN}${index})${NC} ${project_name}"
            [ -n "$project_type" ] && display="${display} ${COLOR_BLUE}[${project_type}]${NC}"
            [ -n "$status_icons" ] && display="${display} ${status_icons}"

            # Print in columns
            if (( index % 2 == 1 )); then
                # Left column: Calculate visible length to pad correctly
                local visible_text=$(strip_ansi "$display")
                local visible_len=${#visible_text}
                local padding=$(( col_width - visible_len ))
                
                # Ensure at least one space of padding
                [ $padding -lt 1 ] && padding=1
                
                echo -ne " ${display}"
                printf "%${padding}s" ""
            else
                # Right column
                echo -e "${display}"
            fi

            ((index++))
        done

        # Add newline if odd number of projects
        (( (index - 1) % 2 == 1 )) && echo ""
    else
        # List view
        local index=1
        for project in "${projects[@]}"; do
            local project_name=$(basename "$project")
            local project_type=$(detect_project_type "$project" 2>/dev/null || echo "")
            local status_icons=$(get_status_indicators "$project_name" 2>/dev/null || echo "")

            echo -ne " ${COLOR_GREEN}${index})${NC} ${project_name}"
            [ -n "$project_type" ] && echo -ne " ${COLOR_BLUE}[${project_type}]${NC}"
            [ -n "$status_icons" ] && echo -ne " ${status_icons}"
            echo ""

            ((index++))
        done
    fi

    echo ""
    return 0
}

render_quick_actions() {
    local width=$(get_ui_width)
    draw_box_top $width
    draw_box_line "${COLOR_YELLOW}Quick Actions:${NC}" $width
    draw_box_line "  ${COLOR_GREEN}#${NC}   = Show project menu      ${COLOR_GREEN}#v${NC} = View overview" $width
    draw_box_line "  ${COLOR_GREEN}#r${NC}  = Run project            ${COLOR_GREEN}#t${NC} = Test project" $width
    draw_box_line "  ${COLOR_GREEN}#c${NC}  = Launch Claude Code     ${COLOR_GREEN}#g${NC} = Launch Gemini" $width
    draw_box_line "  ${COLOR_GREEN}#e${NC}  = Edit files             ${COLOR_GREEN}#f${NC} = File manager" $width
    draw_box_line "  ${COLOR_GREEN}#o${NC}  = Open terminal          ${COLOR_GREEN}#s${NC} = Show status" $width
    draw_box_line "  ${COLOR_GREEN}q${NC}   = Quit" $width
    draw_box_bottom $width
    echo ""
}

render_action_menu() {
    local project_name="$1"
    local width=$(get_ui_width)

    draw_box_top $width
    draw_box_line "${COLOR_YELLOW}Actions: ${project_name}${NC}" $width
    draw_box_separator $width
    draw_box_line "${COLOR_GREEN}1)${NC} View (overview, files, logs, git)" $width
    draw_box_line "${COLOR_GREEN}2)${NC} Run (start, stop, restart, status)" $width
    draw_box_line "${COLOR_GREEN}3)${NC} Test (run tests, history, compare)" $width
    draw_box_line "${COLOR_GREEN}4)${NC} Edit (quick files, browse)" $width
    draw_box_line "${COLOR_GREEN}5)${NC} Claude (launch, context, update docs)" $width
    draw_box_line "${COLOR_GREEN}6)${NC} Gemini (launch, context, update docs)" $width
    draw_box_line "${COLOR_GREEN}7)${NC} Tools (git, docker, terminal, file manager)" $width
    draw_box_line "${COLOR_GREEN}8)${NC} Settings (favorites, preferences)" $width
    draw_box_separator $width
    draw_box_line "${COLOR_GREEN}b)${NC} Back to Project List" $width
    draw_box_line "${COLOR_GREEN}q)${NC} Quit" $width
    draw_box_bottom $width
    echo ""
}

# Selection functions
select_option() {
    local prompt="$1"
    local response

    read -p "$prompt: " -r response
    echo "$response"
}

select_multiple() {
    local title="$1"
    shift
    local -n items_ref=$1
    local -n selected_ref=$2

    echo -e "${COLOR_YELLOW}${title}${NC}"
    echo -e "${COLOR_CYAN}Select items (space-separated numbers, 'a' for all, or Enter to skip):${NC}"
    echo ""

    local index=1
    for item in "${items_ref[@]}"; do
        echo " ${index}) $item"
        ((index++))
    done

    echo ""
    local response
    read -p "Selection: " -r response

    selected_ref=()

    if [ "$response" = "a" ] || [ "$response" = "A" ]; then
        selected_ref=("${items_ref[@]}")
        return 0
    fi

    if [ -z "$response" ]; then
        return 1
    fi

    # Parse space-separated numbers
    for num in $response; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#items_ref[@]} ]; then
            selected_ref+=("${items_ref[$((num-1))]}")
        fi
    done

    return 0
}

input_text() {
    local prompt="$1"
    local validate_fn="${2:-}"
    local response

    while true; do
        read -p "$prompt: " -r response

        if [ -z "$validate_fn" ]; then
            echo "$response"
            return 0
        fi

        # Call validation function if provided
        if $validate_fn "$response"; then
            echo "$response"
            return 0
        else
            error_message "Invalid input. Please try again."
        fi
    done
}
