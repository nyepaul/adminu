#!/usr/bin/env bash
#
# cgroups-master.sh - Unified interface for all cgroup management tools
#

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# UI Helper Functions (Standardized)
BOX_COLOR="${GREEN}"
BOX_WIDTH=60

strip_ansi() {
    echo -e "$1" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g'
}

draw_box_top() {
    local width="${1:-$BOX_WIDTH}"
    echo -ne "${BOX_COLOR}┌"
    printf '─%.0s' $(seq 1 $((width-2)))
    echo -e "┐${NC}"
}

draw_box_bottom() {
    local width="${1:-$BOX_WIDTH}"
    echo -ne "${BOX_COLOR}└"
    printf '─%.0s' $(seq 1 $((width-2)))
    echo -e "┘${NC}"
}

draw_box_separator() {
    local width="${1:-$BOX_WIDTH}"
    echo -ne "${BOX_COLOR}├"
    printf '─%.0s' $(seq 1 $((width-2)))
    echo -e "┤${NC}"
}

draw_box_line() {
    local content="$1"
    local width="${2:-$BOX_WIDTH}"
    
    local visual_content=$(strip_ansi "$content")
    local content_len=${#visual_content}
    local padding=$((width - content_len - 3))
    [ $padding -lt 0 ] && padding=0

    echo -ne "${BOX_COLOR}│${NC} ${content}"
    printf "%${padding}s" ""
    echo -e "${BOX_COLOR}│${NC}"
}

draw_box_centered() {
    local content="$1"
    local width="${2:-$BOX_WIDTH}"
    
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

# Print colored header
print_header() {
    draw_box_top
    draw_box_centered "Linux cgroups Management - Master Control Panel"
    draw_box_bottom
}

# Print section header
print_section() {
    echo -e "\n${BLUE}▶ $1${NC}"
    echo "────────────────────────────────────────────────────────"
}

# Pause function
pause() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

#═══════════════════════════════════════════════════════════════
# SECTION 1: CONTROLLER & CGROUP MANAGEMENT
#═══════════════════════════════════════════════════════════════

list_controllers() {
    print_section "Available Controllers"
    controllers=$(ls -l /sys/fs/cgroup 2>/dev/null | awk '{print $9}' | grep -v "^$")
    if [ -z "$controllers" ]; then
        echo -e "${RED}No controllers found or permission denied${NC}"
    else
        for controller in ${controllers}; do
            echo -e "${GREEN}  • ${controller}${NC}"
        done
    fi
    pause
}

list_all_cgroups() {
    print_section "All cgroups"
    lscgroup 2>/dev/null || echo -e "${RED}Error listing cgroups. Is cgroup-tools installed?${NC}"
    pause
}

list_custom_cgroups() {
    print_section "Custom cgroups (excluding system defaults)"
    lscgroup 2>/dev/null | grep -Ev "cgroup|slice|.mount|/$|:/user|:/snap" || echo "No custom cgroups found"
    pause
}

create_cgroup() {
    print_section "Create New cgroup"
    echo "Available controllers:"
    ls -l /sys/fs/cgroup 2>/dev/null | awk '{print $9}' | grep -v "^$" | sed 's/^/  • /'
    echo ""
    read -p "Controller type (cpu/memory/etc): " controller
    read -p "cgroup name: " cgroup_name

    if [ -z "$controller" ] || [ -z "$cgroup_name" ]; then
        echo -e "${RED}Both controller and name are required${NC}"
        pause
        return
    fi

    sudo cgcreate -g ${controller}:/${cgroup_name}
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully created ${controller}:/${cgroup_name}${NC}"

        # Set default values based on controller type
        if [ "$controller" = "cpu" ]; then
            sudo cgset -r cpu.shares=1024 ${cgroup_name} 2>/dev/null
            echo -e "${GREEN}  Set default cpu.shares=1024${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to create cgroup${NC}"
    fi
    pause
}

delete_cgroup() {
    print_section "Delete cgroup"
    list_custom_cgroups
    echo ""
    read -p "Controller type: " controller
    read -p "cgroup name to delete: " cgroup_name

    if [ -z "$controller" ] || [ -z "$cgroup_name" ]; then
        echo -e "${RED}Both controller and name are required${NC}"
        pause
        return
    fi

    read -p "Are you sure you want to delete ${controller}:/${cgroup_name}? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        sudo cgdelete ${controller}:/${cgroup_name}
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Successfully deleted ${controller}:/${cgroup_name}${NC}"
        else
            echo -e "${RED}✗ Failed to delete cgroup${NC}"
        fi
    else
        echo "Cancelled"
    fi
    pause
}

#═══════════════════════════════════════════════════════════════
# SECTION 2: CONFIGURATION & MONITORING
#═══════════════════════════════════════════════════════════════

show_cgroup_config() {
    print_section "Show cgroup Configuration"
    read -p "Controller type (cpu/memory): " controller
    read -p "cgroup name: " cgroup_name

    case $controller in
        cpu)
            echo -e "\n${CYAN}CPU Configuration for ${cgroup_name}:${NC}"
            echo "─────────────────────────────────────"
            echo -e "${YELLOW}cpu.cfs_period_us:${NC}"
            sudo cat /sys/fs/cgroup/${controller}/${cgroup_name}/cpu.cfs_period_us 2>/dev/null || echo "  N/A"
            echo -e "${YELLOW}cpu.cfs_quota_us:${NC}"
            sudo cat /sys/fs/cgroup/${controller}/${cgroup_name}/cpu.cfs_quota_us 2>/dev/null || echo "  N/A"
            echo -e "${YELLOW}cpu.shares:${NC}"
            sudo cat /sys/fs/cgroup/${controller}/${cgroup_name}/cpu.shares 2>/dev/null || echo "  N/A"
            echo -e "${YELLOW}cpu.stat:${NC}"
            sudo cat /sys/fs/cgroup/${controller}/${cgroup_name}/cpu.stat 2>/dev/null || echo "  N/A"
            ;;
        memory)
            echo -e "\n${CYAN}Memory Configuration for ${cgroup_name}:${NC}"
            echo "─────────────────────────────────────"
            echo -e "${YELLOW}memory.limit_in_bytes:${NC}"
            sudo cat /sys/fs/cgroup/${controller}/${cgroup_name}/memory.limit_in_bytes 2>/dev/null || echo "  N/A"
            echo -e "${YELLOW}memory.usage_in_bytes:${NC}"
            sudo cat /sys/fs/cgroup/${controller}/${cgroup_name}/memory.usage_in_bytes 2>/dev/null || echo "  N/A"
            echo -e "${YELLOW}memory.max_usage_in_bytes:${NC}"
            sudo cat /sys/fs/cgroup/${controller}/${cgroup_name}/memory.max_usage_in_bytes 2>/dev/null || echo "  N/A"
            echo -e "${YELLOW}memory.stat:${NC}"
            sudo cat /sys/fs/cgroup/${controller}/${cgroup_name}/memory.stat 2>/dev/null || echo "  N/A"
            ;;
        *)
            echo -e "${RED}Unsupported controller type${NC}"
            ;;
    esac
    pause
}

configure_cpu_cgroup() {
    print_section "Configure CPU cgroup"
    read -p "cgroup name: " cgroup_name

    echo -e "\n${CYAN}CPU Configuration Options:${NC}"
    echo "1. cpu.shares (relative weight, default 1024)"
    echo "2. cpu.cfs_quota_us (hard limit in microseconds per period)"
    echo "3. Both"
    read -p "Configure which? (1/2/3): " config_choice

    case $config_choice in
        1)
            read -p "Enter cpu.shares value (e.g., 512, 1024, 2048): " shares
            sudo cgset -r cpu.shares=${shares} ${cgroup_name}
            echo -e "${GREEN}✓ Set cpu.shares=${shares}${NC}"
            ;;
        2)
            read -p "Enter cpu.cfs_quota_us (e.g., 50000 for 50% of one core): " quota
            sudo cgset -r cpu.cfs_quota_us=${quota} ${cgroup_name}
            echo -e "${GREEN}✓ Set cpu.cfs_quota_us=${quota}${NC}"
            ;;
        3)
            read -p "Enter cpu.shares value: " shares
            read -p "Enter cpu.cfs_quota_us value: " quota
            sudo cgset -r cpu.shares=${shares} ${cgroup_name}
            sudo cgset -r cpu.cfs_quota_us=${quota} ${cgroup_name}
            echo -e "${GREEN}✓ Set cpu.shares=${shares} and cpu.cfs_quota_us=${quota}${NC}"
            ;;
    esac
    pause
}

configure_memory_cgroup() {
    print_section "Configure Memory cgroup"
    read -p "cgroup name: " cgroup_name

    echo -e "\n${CYAN}Enter memory limit:${NC}"
    echo "Examples: 524288000 (500MB), 1073741824 (1GB)"
    read -p "Memory limit in bytes: " limit

    sudo cgset -r memory.limit_in_bytes=${limit} ${cgroup_name}
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Set memory.limit_in_bytes=${limit}${NC}"
    else
        echo -e "${RED}✗ Failed to set memory limit${NC}"
    fi
    pause
}

#═══════════════════════════════════════════════════════════════
# SECTION 3: PROCESS MANAGEMENT
#═══════════════════════════════════════════════════════════════

list_processes() {
    print_section "Process List"
    echo "Use 'q' to quit top"
    sleep 1
    top
}

list_applications() {
    print_section "Running Applications"
    ps aux | awk '{print $11}' | sort -u | grep -v "^$" | head -50
    pause
}

move_process_to_cgroup() {
    print_section "Move Process to cgroup"
    read -p "Enter PID: " pid
    read -p "Controller (cpu/memory): " controller
    read -p "cgroup name: " cgroup_name

    if [ -z "$pid" ] || [ -z "$controller" ] || [ -z "$cgroup_name" ]; then
        echo -e "${RED}All fields are required${NC}"
        pause
        return
    fi

    sudo cgclassify -g ${controller}:/${cgroup_name} ${pid}
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Moved process ${pid} to ${controller}:/${cgroup_name}${NC}"
    else
        echo -e "${RED}✗ Failed to move process${NC}"
    fi
    pause
}

move_application_to_cgroup() {
    print_section "Move Application to cgroup"
    read -p "Application name (e.g., firefox, chrome): " app_name
    read -p "Controller (cpu/memory): " controller
    read -p "cgroup name: " cgroup_name

    if [ -z "$app_name" ] || [ -z "$controller" ] || [ -z "$cgroup_name" ]; then
        echo -e "${RED}All fields are required${NC}"
        pause
        return
    fi

    pids=$(pgrep ${app_name})
    if [ -z "$pids" ]; then
        echo -e "${RED}No processes found for '${app_name}'${NC}"
        pause
        return
    fi

    echo -e "${CYAN}Found PIDs: ${pids}${NC}"
    moved=0
    for pid in ${pids}; do
        sudo cgclassify -g ${controller}:/${cgroup_name} ${pid}
        if [ $? -eq 0 ]; then
            ((moved++))
        fi
    done
    echo -e "${GREEN}✓ Moved ${moved} processes to ${controller}:/${cgroup_name}${NC}"
    pause
}

#═══════════════════════════════════════════════════════════════
# SECTION 4: TESTING & MONITORING
#═══════════════════════════════════════════════════════════════

generate_cpu_load() {
    print_section "Generate CPU Load Test"
    echo -e "${YELLOW}Warning: This will spawn an infinite loop consuming CPU${NC}"
    echo "You'll need to kill it manually (use 'killall bash' or find PID)"
    read -p "Continue? (yes/no): " confirm

    if [ "$confirm" = "yes" ]; then
        echo -e "${GREEN}Starting CPU load... (running in background)${NC}"
        echo "PID will be displayed. Use 'kill <PID>' to stop it."
        (while true; do true; done) &
        echo -e "${CYAN}CPU load test PID: $!${NC}"
    fi
    pause
}

monitor_systemd_cgroups() {
    print_section "Systemd cgroup Monitoring"
    echo "Real-time resource usage (press 'q' to quit)"
    sleep 1
    sudo systemd-cgtop
}

list_systemd_cgroups() {
    print_section "Systemd cgroup Hierarchy"
    sudo systemd-cgls
    pause
}

#═══════════════════════════════════════════════════════════════
# SECTION 5: PAM-BASED USER RESTRICTIONS
#═══════════════════════════════════════════════════════════════

pam_install() {
    print_section "Install PAM CPU Restrictions"
    echo -e "${YELLOW}This will modify /etc/pam.d/sshd and restart sshd${NC}"
    read -p "Continue? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        pause
        return
    fi

    # Check if already installed
    if grep -q "pam_limits.so" /etc/pam.d/sshd; then
        echo -e "${YELLOW}PAM limits already configured in sshd${NC}"
    else
        echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/sshd > /dev/null
        echo -e "${GREEN}✓ Added pam_limits.so to /etc/pam.d/sshd${NC}"
    fi

    # Create limits directory if needed
    sudo mkdir -p /etc/security/limits.d/

    # Restart sshd
    sudo systemctl restart sshd
    echo -e "${GREEN}✓ Restarted sshd service${NC}"
    echo -e "${CYAN}PAM restrictions installed. Use 'Toggle user CPU limits' to configure users.${NC}"
    pause
}

pam_remove() {
    print_section "Remove PAM CPU Restrictions"
    echo -e "${YELLOW}This will remove PAM configuration and restart sshd${NC}"
    read -p "Continue? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        pause
        return
    fi

    sudo sed -i '/session required pam_limits.so/d' /etc/pam.d/sshd
    sudo rm -f /etc/security/limits.d/limit_cpu.conf
    sudo systemctl restart sshd
    echo -e "${GREEN}✓ PAM restrictions removed${NC}"
    pause
}

pam_toggle_user() {
    print_section "Toggle User CPU Limits"

    if [ -f /etc/security/limits.d/limit_cpu.conf ]; then
        echo -e "${CYAN}Current limits:${NC}"
        cat /etc/security/limits.d/limit_cpu.conf
        echo ""
    fi

    read -p "Enter username: " username

    if [ -z "$username" ]; then
        echo -e "${RED}Username required${NC}"
        pause
        return
    fi

    if sudo grep -q "^${username}" /etc/security/limits.d/limit_cpu.conf 2>/dev/null; then
        sudo sed -i "/^${username}/d" /etc/security/limits.d/limit_cpu.conf
        echo -e "${GREEN}✓ Removed CPU limits for '${username}'${NC}"
    else
        read -p "Enter CPU limit percentage for '${username}': " cpu_limit
        echo "${username} hard cpu ${cpu_limit}" | sudo tee -a /etc/security/limits.d/limit_cpu.conf > /dev/null
        echo -e "${GREEN}✓ Set ${cpu_limit}% CPU limit for '${username}'${NC}"
    fi

    sudo systemctl restart sshd
    echo -e "${CYAN}Changes applied. Will affect new SSH sessions.${NC}"
    pause
}

#═══════════════════════════════════════════════════════════════
# MENU SYSTEMS
#═══════════════════════════════════════════════════════════════

menu_cgroup_management() {
    while true; do
        clear
        print_header
        echo ""
        draw_box_top
        draw_box_line "cgroup Management"
        draw_box_separator
        draw_box_line "1.  List all controllers"
        draw_box_line "2.  List all cgroups"
        draw_box_line "3.  List custom cgroups only"
        draw_box_line "4.  Create new cgroup"
        draw_box_line "5.  Delete cgroup"
        draw_box_line "6.  Show cgroup configuration"
        draw_box_line "7.  Configure CPU cgroup"
        draw_box_line "8.  Configure memory cgroup"
        draw_box_line "0.  ← Back to main menu"
        draw_box_bottom
        echo ""
        read -p "Select option: " choice

        case $choice in
            1) list_controllers ;;
            2) list_all_cgroups ;;
            3) list_custom_cgroups ;;
            4) create_cgroup ;;
            5) delete_cgroup ;;
            6) show_cgroup_config ;;
            7) configure_cpu_cgroup ;;
            8) configure_memory_cgroup ;;
            0) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

menu_process_management() {
    while true; do
        clear
        print_header
        echo ""
        draw_box_top
        draw_box_line "Process Management"
        draw_box_separator
        draw_box_line "1.  List all running processes (top)"
        draw_box_line "2.  List running applications"
        draw_box_line "3.  Move process (by PID) to cgroup"
        draw_box_line "4.  Move application (by name) to cgroup"
        draw_box_line "0.  ← Back to main menu"
        draw_box_bottom
        echo ""
        read -p "Select option: " choice

        case $choice in
            1) list_processes ;;
            2) list_applications ;;
            3) move_process_to_cgroup ;;
            4) move_application_to_cgroup ;;
            0) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

menu_monitoring_testing() {
    while true; do
        clear
        print_header
        echo ""
        draw_box_top
        draw_box_line "Monitoring & Testing"
        draw_box_separator
        draw_box_line "1.  Generate CPU load test"
        draw_box_line "2.  Monitor cgroups (systemd-cgtop)"
        draw_box_line "3.  List systemd cgroup hierarchy"
        draw_box_line "0.  ← Back to main menu"
        draw_box_bottom
        echo ""
        read -p "Select option: " choice

        case $choice in
            1) generate_cpu_load ;;
            2) monitor_systemd_cgroups ;;
            3) list_systemd_cgroups ;;
            0) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

menu_pam_restrictions() {
    while true; do
        clear
        print_header
        echo ""
        draw_box_top
        draw_box_line "PAM-based User Restrictions"
        draw_box_separator
        draw_box_line "1.  Install PAM CPU restrictions"
        draw_box_line "2.  Remove PAM CPU restrictions"
        draw_box_line "3.  Toggle user CPU limits"
        draw_box_line "0.  ← Back to main menu"
        draw_box_bottom
        echo ""
        read -p "Select option: " choice

        case $choice in
            1) pam_install ;;
            2) pam_remove ;;
            3) pam_toggle_user ;;
            0) return ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

menu_main() {
    while true; do
        clear
        print_header
        echo ""
        draw_box_top
        draw_box_line "Main Menu"
        draw_box_separator
        draw_box_line "${GREEN}1.${NC}  cgroup Management"
        draw_box_line "${GREEN}2.${NC}  Process Management"
        draw_box_line "${GREEN}3.${NC}  Monitoring & Testing"
        draw_box_line "${GREEN}4.${NC}  PAM User Restrictions"
        draw_box_line "${GREEN}5.${NC}  Help & Documentation"
        draw_box_line "${RED}0.${NC}  Exit"
        draw_box_bottom
        echo ""
        read -p "Select option: " choice

        case $choice in
            1) menu_cgroup_management ;;
            2) menu_process_management ;;
            3) menu_monitoring_testing ;;
            4) menu_pam_restrictions ;;
            5) show_help ;;
            0)
                echo -e "${CYAN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

show_help() {
    clear
    print_header
    print_section "Quick Reference"
    cat << 'EOF'

COMMON WORKFLOWS:

1. Limit CPU for an application:
   • Main Menu → 1 (cgroup Management) → 4 (Create new cgroup)
   • Choose 'cpu' controller, give it a name
   • Configure it: 7 (Configure CPU cgroup)
   • Go back, then: 2 (Process Management) → 4 (Move application)

2. Monitor resource usage:
   • Main Menu → 3 (Monitoring) → 2 (systemd-cgtop)

3. Set per-user SSH limits:
   • Main Menu → 4 (PAM Restrictions) → 1 (Install)
   • Then: 3 (Toggle user) to set limits

KEY CONCEPTS:

• cpu.shares: Relative weight (higher = more CPU when contested)
• cpu.cfs_quota_us: Hard limit (50000 = 50% of one core)
• memory.limit_in_bytes: Maximum memory in bytes

REQUIREMENTS:

• cgroup-tools package (sudo apt install cgroup-tools)
• Root/sudo privileges
• Mounted cgroup filesystem

EOF
    pause
}

#═══════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
#═══════════════════════════════════════════════════════════════

# Check for required tools
if ! command -v cgcreate &> /dev/null; then
    echo -e "${RED}Error: cgroup-tools not found${NC}"
    echo "Please install: sudo apt-get install cgroup-tools"
    exit 1
fi

# Start main menu
menu_main
