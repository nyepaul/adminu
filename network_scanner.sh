#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# UI Helper Functions (Standardized)
BOX_COLOR="${GREEN}"
BOX_WIDTH=80

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

# Create a working temp directory
TEMP_DIR="$(pwd)/.network_scanner_temp"
HOSTS_FILE="$TEMP_DIR/discovered_hosts.txt"
SCAN_RESULTS="$TEMP_DIR/scan_results.txt"
REPORT_TEMP="$TEMP_DIR/report_temp.txt"
OUTPUT_TEMP="$TEMP_DIR/output_display.txt"
LINES_PER_PAGE=20

# Global array to cache discovered subnets
declare -a DISCOVERED_SUBNETS

setup_temp_directory() {
    # Create temp directory if it doesn't exist
    if [ ! -d "$TEMP_DIR" ]; then
        mkdir -p "$TEMP_DIR" 2>/dev/null || {
            echo -e "${RED}❌ Error: Cannot create temp directory $TEMP_DIR${NC}"
            echo -e "${BLUE}💡 Falling back to current directory${NC}"
            TEMP_DIR="$(pwd)"
            HOSTS_FILE="$TEMP_DIR/discovered_hosts.txt"
            SCAN_RESULTS="$TEMP_DIR/scan_results.txt"
            REPORT_TEMP="$TEMP_DIR/report_temp.txt"
            OUTPUT_TEMP="$TEMP_DIR/output_display.txt"
        }
    fi
    
    # Test write permission
    if ! touch "$TEMP_DIR/test_write.tmp" 2>/dev/null; then
        echo -e "${RED}❌ Error: No write permission in temp directory${NC}"
        echo -e "${BLUE}💡 Using current directory instead${NC}"
        TEMP_DIR="$(pwd)"
        HOSTS_FILE="$TEMP_DIR/discovered_hosts.txt"
        SCAN_RESULTS="$TEMP_DIR/scan_results.txt"
        REPORT_TEMP="$TEMP_DIR/report_temp.txt"
        OUTPUT_TEMP="$TEMP_DIR/output_display.txt"
    else
        rm -f "$TEMP_DIR/test_write.tmp" 2>/dev/null
    fi
}

check_dependencies() {
    local missing_deps=()
    
    if ! command -v nmap &> /dev/null; then
        missing_deps+=("nmap")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing dependencies: ${missing_deps[*]}${NC}"
        echo "Ubuntu/Debian: sudo apt install ${missing_deps[*]}"
        echo "CentOS/RHEL: sudo yum install ${missing_deps[*]}"
        exit 1
    fi
}

add_unique_subnet() {
    local new_subnet="$1"
    local -n subnet_array=$2
    
    # Check if already exists
    for existing in "${subnet_array[@]}"; do
        if [ "$existing" = "$new_subnet" ]; then
            return 1  # Already exists
        fi
    done
    
    subnet_array+=("$new_subnet")
    return 0
}

get_detected_subnets() {
    local subnets=()
    local temp_discovery="$TEMP_DIR/subnet_discovery.txt"
    local start_time=$(date +%s)
    
    # Send all discovery messages to stderr to keep stdout clean
    exec 3>&1
    exec 1>&2
    
    echo -e "${YELLOW}🔍 Discovering all available subnets...${NC}"
    
    # 1. Get subnets from local interfaces (only UP interfaces)
    echo -e "${BLUE}  • Checking local interfaces...${NC}"
    local current_interface=""
    local interface_status=""
    
    while read -r line; do
        # Check if this line contains interface info with status
        if [[ $line =~ ^[0-9]+:.*state\ ([A-Z]+) ]]; then
            current_interface=$(echo "$line" | awk '{print $2}' | tr -d ':')
            interface_status="${BASH_REMATCH[1]}"
        elif [[ $line =~ inet\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+) ]] && [[ "$interface_status" == "UP" ]]; then
            local ip_cidr="${BASH_REMATCH[1]}"
            if [[ ! "$ip_cidr" =~ ^127\. ]]; then
                local ip=$(echo "$ip_cidr" | cut -d'/' -f1)
                local mask=$(echo "$ip_cidr" | cut -d'/' -f2)
                local network=$(echo "$ip" | sed 's/\.[0-9]*$/.0/')
                local subnet="${network}/${mask}"
                add_unique_subnet "$subnet" subnets
                echo -e "${GREEN}    ✓ Added subnet $subnet from interface $current_interface (UP)${NC}"
            fi
        elif [[ $line =~ inet\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+) ]] && [[ "$interface_status" == "DOWN" ]]; then
            local ip_cidr="${BASH_REMATCH[1]}"
            echo -e "${YELLOW}    ⚠ Skipping subnet from interface $current_interface (DOWN): $ip_cidr${NC}"
        fi
    done < <(ip addr show)
    
    # 2. Get subnets from routing table
    echo -e "${BLUE}  • Analyzing routing table...${NC}"
    while read -r subnet; do
        if [[ "$subnet" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] && [[ ! "$subnet" =~ ^169\.254 ]]; then
            add_unique_subnet "$subnet" subnets
        fi
    done < <(ip route | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+" | awk '{print $1}')
    
    # 3. Discover subnets via ARP table analysis
    echo -e "${BLUE}  • Scanning ARP table...${NC}"
    if command -v arp &> /dev/null; then
        while read -r ip; do
            if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ ! "$ip" =~ ^127\. ]]; then
                # Determine likely subnet based on IP
                local network=$(echo "$ip" | sed 's/\.[0-9]*$/.0/')
                local subnet="${network}/24"
                add_unique_subnet "$subnet" subnets
            fi
        done < <(arp -a 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -20)
    fi
    
    # 4. Network discovery using nmap on local networks (fast scan)
    echo -e "${BLUE}  • Using nmap network discovery...${NC}"
    local primary_interface=$(ip route | grep default | head -1 | awk '{print $5}')
    if [ -n "$primary_interface" ]; then
        local primary_ip=$(ip addr show "$primary_interface" | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -1)
        if [ -n "$primary_ip" ]; then
            echo -e "${BLUE}    ↳ Scanning common network ranges...${NC}"
            
            # Scan only most common variations with very fast timeouts
            local base_network=$(echo "$primary_ip" | cut -d'.' -f1-2)
            local common_ranges=(0 1 10 87 100 122)
            local scan_count=0
            
            for third_octet in "${common_ranges[@]}"; do
                scan_count=$((scan_count + 1))
                echo -ne "${BLUE}    ↳ Checking ${base_network}.${third_octet}.0/24 (${scan_count}/${#common_ranges[@]})...${NC}\r"
                
                local test_network="${base_network}.${third_octet}.0/24"
                
                # Very quick ping sweep (max 500ms total)
                if timeout 0.5 nmap -sn -PE --max-retries 0 --host-timeout 100ms "${test_network}" 2>/dev/null | grep -q "Host is up"; then
                    add_unique_subnet "$test_network" subnets
                    echo -e "${BLUE}    ↳ ✅ Found active network: ${test_network}${NC}"
                fi
            done
            echo -e "${BLUE}    ↳ Common range scan complete           ${NC}"
        fi
    fi
    
    # 5. Check for common Docker/virtualization networks (fast)
    echo -e "${BLUE}  • Checking virtualization networks...${NC}"
    local common_virtual_subnets=(
        "172.17.0.0/16"    # Docker default
        "172.18.0.0/16"    # Docker networks
        "172.19.0.0/16"    # Docker networks
        "172.20.0.0/16"    # Docker networks
        "192.168.122.0/24" # libvirt default
        "192.168.99.0/24"  # Docker Machine
        "10.0.2.0/24"      # VirtualBox NAT
        "192.168.56.0/24"  # VirtualBox Host-Only
    )
    
    local vnet_count=0
    for vnet in "${common_virtual_subnets[@]}"; do
        vnet_count=$((vnet_count + 1))
        echo -ne "${BLUE}    ↳ Checking ${vnet} (${vnet_count}/${#common_virtual_subnets[@]})...${NC}\r"
        
        # Very quick check (max 300ms per network)
        if timeout 0.3 nmap -sn -PE --max-retries 0 --host-timeout 50ms "$vnet" 2>/dev/null | grep -q "Host is up"; then
            add_unique_subnet "$vnet" subnets
            echo -e "${BLUE}    ↳ ✅ Found active virtual network: ${vnet}${NC}"
        fi
    done
    echo -e "${BLUE}    ↳ Virtual network scan complete        ${NC}"
    
    # 6. Use netstat/ss to find connected networks (fast)
    echo -e "${BLUE}  • Analyzing network connections...${NC}"
    if command -v ss &> /dev/null; then
        local conn_count=0
        while read -r ip; do
            if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ ! "$ip" =~ ^127\. ]]; then
                conn_count=$((conn_count + 1))
                echo -ne "${BLUE}    ↳ Analyzing connection ${conn_count}: ${ip}...${NC}\r"
                local network=$(echo "$ip" | sed 's/\.[0-9]*$/.0/')
                local subnet="${network}/24"
                add_unique_subnet "$subnet" subnets
            fi
        done < <(timeout 2 ss -tn 2>/dev/null | grep ESTAB | awk '{print $5}' | cut -d':' -f1 | sort -u | head -5)
        echo -e "${BLUE}    ↳ Connection analysis complete         ${NC}"
    else
        echo -e "${BLUE}    ↳ ss command not available, skipping   ${NC}"
    fi
    
    # 7. Check DHCP leases if accessible (fast)
    echo -e "${BLUE}  • Checking DHCP information...${NC}"
    local dhcp_files=("/var/lib/dhcp/dhcpd.leases" "/var/lib/dhcpcd5/dhcpcd.leases" "/tmp/dhcp.leases")
    local dhcp_found=false
    
    for dhcp_file in "${dhcp_files[@]}"; do
        if [ -r "$dhcp_file" ]; then
            echo -e "${BLUE}    ↳ Reading ${dhcp_file}...${NC}"
            dhcp_found=true
            while read -r ip; do
                if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    local network=$(echo "$ip" | sed 's/\.[0-9]*$/.0/')
                    local subnet="${network}/24"
                    add_unique_subnet "$subnet" subnets
                fi
            done < <(timeout 1 grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$dhcp_file" 2>/dev/null | head -10)
        fi
    done
    
    if [ "$dhcp_found" = false ]; then
        echo -e "${BLUE}    ↳ No accessible DHCP files found      ${NC}"
    else
        echo -e "${BLUE}    ↳ DHCP analysis complete               ${NC}"
    fi
    
    # 8. If still no subnets, add common private network ranges
    if [ ${#subnets[@]} -eq 0 ]; then
        echo -e "${YELLOW}  • No networks detected, using common ranges...${NC}"
        subnets=(
            "192.168.1.0/24"
            "192.168.0.0/24" 
            "192.168.87.0/24"
            "10.0.0.0/24"
            "172.16.0.0/24"
        )
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo -e "${GREEN}✅ Network discovery complete: Found ${#subnets[@]} subnets in ${duration}s${NC}"
    
    # Restore stdout and output subnets
    exec 1>&3
    exec 3>&-
    
    # Output subnets to stdout (one per line)
    printf '%s\n' "${subnets[@]}"
}

show_subnet_selection_simple() {
    local subnet_file="$1"
    
    # Read subnets from file into array
    local subnets=()
    if [ -f "$subnet_file" ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                subnets+=("$line")
            fi
        done < "$subnet_file"
    fi
    
    # If no subnets found, add defaults
    if [ ${#subnets[@]} -eq 0 ]; then
        subnets=("192.168.87.0/24" "192.168.1.0/24" "192.168.0.0/24" "10.0.0.0/24")
    fi
    
    echo
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                        🔍 SELECT SUBNET TO SCAN                               ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${GREEN}📋 Available Networks (${#subnets[@]} discovered):${NC}"
    echo
    
    # Display numbered list
    local count=1
    for subnet in "${subnets[@]}"; do
        if [ $count -le 15 ]; then
            # Determine network type
            local network_type=""
            if [[ "$subnet" =~ ^192\.168\.87\. ]]; then
                network_type="${GREEN}[Current Network]${NC}"
            elif [[ "$subnet" =~ ^192\.168\.122\. ]]; then
                network_type="${PURPLE}[Virtual/KVM]${NC}"
            elif [[ "$subnet" =~ ^172\.1[7-9]\.|^172\.2[0-9]\. ]]; then
                network_type="${CYAN}[Docker]${NC}"
            elif [[ "$subnet" =~ ^192\.168\.[01]\. ]]; then
                network_type="${BLUE}[Home Router]${NC}"
            elif [[ "$subnet" =~ ^10\. ]]; then
                network_type="${BLUE}[Corporate]${NC}"
            else
                network_type="${YELLOW}[Private]${NC}"
            fi
            
            echo -e "${YELLOW}$(printf "%2d" $count))${NC} $(printf "%-18s" "$subnet") $network_type"
        fi
        count=$((count + 1))
    done
    
    echo
    echo -e "${YELLOW} c)${NC} Enter custom subnet"
    echo -e "${YELLOW} 0)${NC} Cancel"
    echo
    
    while true; do
        read -p "Select subnet number (1-${#subnets[@]}, c, or 0): " choice
        
        case $choice in
            [1-9]|1[0-5])
                if [ "$choice" -ge 1 ] && [ "$choice" -le "${#subnets[@]}" ]; then
                    local selected="${subnets[$((choice - 1))]}"
                    echo -e "${GREEN}✅ Selected: $selected${NC}"
                    echo "$selected" > "$TEMP_DIR/selected_subnet.txt"
                    return 0
                else
                    echo -e "${RED}❌ Invalid number. Please select 1-${#subnets[@]}${NC}"
                fi
                ;;
            c|C)
                echo
                read -p "Enter custom subnet (e.g., 192.168.1.0/24): " custom_subnet
                if [[ "$custom_subnet" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                    echo -e "${GREEN}✅ Selected: $custom_subnet${NC}"
                    echo "$custom_subnet" > "$TEMP_DIR/selected_subnet.txt"
                    return 0
                else
                    echo -e "${RED}❌ Invalid format. Use format like 192.168.1.0/24${NC}"
                fi
                ;;
            0|"")
                return 1
                ;;
            *)
                echo -e "${RED}❌ Invalid option. Please select a number, 'c', or '0'${NC}"
                ;;
        esac
    done
}

show_subnet_selection_cached() {
    local title="$1"
    
    # Don't clear screen to preserve discovery output
    echo
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ $title${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}Select a subnet or enter custom:${NC}"
    echo
    
    # Use cached results instead of re-running discovery
    local subnets=("${DISCOVERED_SUBNETS[@]}")
    local count=1
    
    # Show what was detected
    echo -e "${GREEN}📋 Available subnets (${#subnets[@]} found):${NC}"
    echo
    
    for subnet in "${subnets[@]}"; do
        if [ $count -le 15 ]; then  # Support up to 15 subnets
            # Add detailed network info and status
            local network_info=""
            local status_info=""
            
            # Network type identification (no slow host counting)
            if [[ "$subnet" =~ ^192\.168\.1\. ]]; then
                network_info=" ${BLUE}(home router)${NC}"
            elif [[ "$subnet" =~ ^192\.168\.0\. ]]; then
                network_info=" ${BLUE}(common router)${NC}"
            elif [[ "$subnet" =~ ^192\.168\.87\. ]]; then
                network_info=" ${GREEN}(current network)${NC}"
            elif [[ "$subnet" =~ ^192\.168\.122\. ]]; then
                network_info=" ${PURPLE}(libvirt/KVM)${NC}"
            elif [[ "$subnet" =~ ^172\.17\. ]]; then
                network_info=" ${CYAN}(docker default)${NC}"
            elif [[ "$subnet" =~ ^172\.(1[8-9]|2[0-9])\. ]]; then
                network_info=" ${CYAN}(docker network)${NC}"
            elif [[ "$subnet" =~ ^10\. ]]; then
                network_info=" ${BLUE}(corporate/VPN)${NC}"
            elif [[ "$subnet" =~ ^172\.16\. ]]; then
                network_info=" ${BLUE}(private network)${NC}"
            else
                network_info=" ${YELLOW}(detected network)${NC}"
            fi
            
            echo -e "${YELLOW}$count)${NC} $subnet$network_info"
        fi
        count=$((count + 1))
    done
    
    if [ "${#subnets[@]}" -gt 15 ]; then
        echo -e "${BLUE}... and $((${#subnets[@]} - 15)) more networks${NC}"
    fi
    
    echo -e "${YELLOW}c)${NC} Custom subnet"
    echo -e "${YELLOW}0)${NC} Cancel"
    echo
    
    read -p "Select option (1-15, c, or 0): " subnet_choice
    
    case $subnet_choice in
        [1-9]|1[0-5])
            if [ "$subnet_choice" -le "${#subnets[@]}" ]; then
                echo "${subnets[$((subnet_choice - 1))]}"
                return 0
            else
                echo ""
                return 1
            fi
            ;;
        c|C)
            echo
            read -p "Enter custom subnet (e.g., 192.168.1.0/24): " custom_subnet
            echo "$custom_subnet"
            return 0
            ;;
        0|"")
            echo ""
            return 1
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
}

show_subnet_selection() {
    local title="$1"
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ $title${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}Select a subnet or enter custom:${NC}"
    echo
    
    local subnets=($(get_detected_subnets))
    local count=1
    
    for subnet in "${subnets[@]}"; do
        if [ $count -le 15 ]; then  # Support up to 15 subnets
            # Add detailed network info and status
            local network_info=""
            local status_info=""
            
            # Network type identification (no slow host counting)
            if [[ "$subnet" =~ ^192\.168\.1\. ]]; then
                network_info=" ${BLUE}(home router)${NC}"
            elif [[ "$subnet" =~ ^192\.168\.0\. ]]; then
                network_info=" ${BLUE}(common router)${NC}"
            elif [[ "$subnet" =~ ^192\.168\.87\. ]]; then
                network_info=" ${GREEN}(current network)${NC}"
            elif [[ "$subnet" =~ ^192\.168\.122\. ]]; then
                network_info=" ${PURPLE}(libvirt/KVM)${NC}"
            elif [[ "$subnet" =~ ^172\.17\. ]]; then
                network_info=" ${CYAN}(docker default)${NC}"
            elif [[ "$subnet" =~ ^172\.(1[8-9]|2[0-9])\. ]]; then
                network_info=" ${CYAN}(docker network)${NC}"
            elif [[ "$subnet" =~ ^10\. ]]; then
                network_info=" ${BLUE}(corporate/VPN)${NC}"
            elif [[ "$subnet" =~ ^172\.16\. ]]; then
                network_info=" ${BLUE}(private network)${NC}"
            else
                network_info=" ${YELLOW}(detected network)${NC}"
            fi
            
            echo -e "${YELLOW}$count)${NC} $subnet$network_info"
        fi
        count=$((count + 1))
    done
    
    if [ "${#subnets[@]}" -gt 15 ]; then
        echo -e "${BLUE}... and $((${#subnets[@]} - 15)) more networks${NC}"
    fi
    
    echo -e "${YELLOW}c)${NC} Custom subnet"
    echo -e "${YELLOW}0)${NC} Cancel"
    echo
    
    read -p "Select option (1-15, c, or 0): " subnet_choice
    
    case $subnet_choice in
        [1-9]|1[0-5])
            if [ "$subnet_choice" -le "${#subnets[@]}" ]; then
                echo "${subnets[$((subnet_choice - 1))]}"
                return 0
            else
                echo ""
                return 1
            fi
            ;;
        c|C)
            echo
            read -p "Enter custom subnet (e.g., 192.168.1.0/24): " custom_subnet
            echo "$custom_subnet"
            return 0
            ;;
        0|"")
            echo ""
            return 1
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
}

check_privileges() {
    if [ "$EUID" -eq 0 ]; then
        echo -e "${GREEN}✓ Running with root privileges - full scanning capabilities enabled${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Running without root privileges - some scans may be limited${NC}"
        echo -e "${BLUE}💡 For advanced features (SYN scans, OS detection), run: sudo $0${NC}"
        return 1
    fi
}

ensure_root_for_scan() {
    local scan_type="$1"
    
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}⚠️  $scan_type requires root privileges${NC}"
        echo -e "${BLUE}🔑 Requesting elevated privileges...${NC}"
        
        # Re-execute with sudo
        if command -v sudo &> /dev/null; then
            echo -e "${GREEN}🚀 Elevating to root for $scan_type...${NC}"
            exec sudo "$0" "$@"
        else
            echo -e "${RED}❌ sudo not available. Please run as root: su -c '$0'${NC}"
            sleep 3
            return 1
        fi
    fi
    return 0
}

run_privileged_command() {
    local command="$1"
    local description="$2"
    
    if [ "$EUID" -eq 0 ]; then
        # Already root, execute directly
        eval "$command"
    else
        # Try with sudo
        if command -v sudo &> /dev/null; then
            echo -e "${YELLOW}🔑 Requesting privileges for: $description${NC}"
            sudo bash -c "$command"
        else
            echo -e "${RED}❌ Root privileges required for: $description${NC}"
            echo -e "${BLUE}💡 Please run as root or install sudo${NC}"
            return 1
        fi
    fi
}

interactive_pager() {
    local content_file="$1"
    local title="$2"
    local current_page=1
    local total_lines=$(wc -l < "$content_file")
    local total_pages=$(( (total_lines + LINES_PER_PAGE - 1) / LINES_PER_PAGE ))
    
    if [ $total_pages -eq 0 ]; then
        total_pages=1
    fi
    
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║ $title${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo -e "${YELLOW}📄 Page $current_page of $total_pages (Lines: $total_lines)${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────${NC}"
        
        local start_line=$(( (current_page - 1) * LINES_PER_PAGE + 1 ))
        local end_line=$(( current_page * LINES_PER_PAGE ))
        
        sed -n "${start_line},${end_line}p" "$content_file"
        
        echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────${NC}"
        echo -e "${YELLOW}Navigation:${NC} [n]ext [p]revious [f]irst [l]ast [s]earch [g]oto [0/q]uit"
        read -p "Command (default: 0): " nav_choice
        nav_choice=${nav_choice:-0}
        
        case $nav_choice in
            n|N)
                if [ $current_page -lt $total_pages ]; then
                    current_page=$((current_page + 1))
                fi
                ;;
            p|P)
                if [ $current_page -gt 1 ]; then
                    current_page=$((current_page - 1))
                fi
                ;;
            f|F)
                current_page=1
                ;;
            l|L)
                current_page=$total_pages
                ;;
            s|S)
                search_in_report "$content_file" "$title"
                ;;
            g|G)
                read -p "Go to page (1-$total_pages): " goto_page
                if [[ "$goto_page" =~ ^[0-9]+$ ]] && [ "$goto_page" -ge 1 ] && [ "$goto_page" -le $total_pages ]; then
                    current_page=$goto_page
                else
                    echo -e "${RED}Invalid page number${NC}"
                    sleep 1
                fi
                ;;
            0|q|Q|"")
                break
                ;;
            *)
                echo -e "${RED}Invalid command${NC}"
                sleep 1
                ;;
        esac
    done
}

interactive_host_selector() {
    local content_file="$1"
    local title="$2"
    local current_page=1
    local total_lines=$(wc -l < "$content_file")
    local total_pages=$(( (total_lines + LINES_PER_PAGE - 1) / LINES_PER_PAGE ))
    
    if [ $total_pages -eq 0 ]; then
        total_pages=1
    fi
    
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║ $title${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo -e "${YELLOW}📄 Page $current_page of $total_pages (Lines: $total_lines)${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────${NC}"
        
        local start_line=$(( (current_page - 1) * LINES_PER_PAGE + 1 ))
        local end_line=$(( current_page * LINES_PER_PAGE ))
        
        sed -n "${start_line},${end_line}p" "$content_file"
        
        echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────────${NC}"
        echo -e "${YELLOW}Navigation:${NC} [n]ext [p]revious [f]irst [l]ast [s]earch [g]oto [h]ost [1-42]host# [0/q]uit"
        read -p "Command (default: 0): " nav_choice
        nav_choice=${nav_choice:-0}
        
        case $nav_choice in
            n|N)
                if [ $current_page -lt $total_pages ]; then
                    current_page=$((current_page + 1))
                fi
                ;;
            p|P)
                if [ $current_page -gt 1 ]; then
                    current_page=$((current_page - 1))
                fi
                ;;
            f|F)
                current_page=1
                ;;
            l|L)
                current_page=$total_pages
                ;;
            s|S)
                search_in_report "$content_file" "$title"
                ;;
            g|G)
                read -p "Go to page (1-$total_pages): " goto_page
                if [[ "$goto_page" =~ ^[0-9]+$ ]] && [ "$goto_page" -ge 1 ] && [ "$goto_page" -le $total_pages ]; then
                    current_page=$goto_page
                else
                    echo -e "${RED}Invalid page number${NC}"
                    sleep 1
                fi
                ;;
            h|H)
                select_host_for_analysis
                ;;
            [1-9]|[1-9][0-9]|[1-9][0-9][0-9])
                # Direct host selection by number
                if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
                    echo -e "${RED}❌ No hosts available${NC}"
                    sleep 1
                else
                    local host_count=$(wc -l < "$HOSTS_FILE")
                    if [ "$nav_choice" -ge 1 ] && [ "$nav_choice" -le "$host_count" ]; then
                        local selected_ip=$(sed -n "${nav_choice}p" "$HOSTS_FILE" | cut -d'|' -f1)
                        host_analysis_menu "$selected_ip"
                    else
                        echo -e "${RED}Invalid host number (1-$host_count)${NC}"
                        sleep 1
                    fi
                fi
                ;;
            0|q|Q|"")
                break
                ;;
            *)
                echo -e "${RED}Invalid command${NC}"
                sleep 1
                ;;
        esac
    done
}

select_host_for_analysis() {
    if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
        echo -e "${RED}❌ No hosts discovered.${NC}"
        sleep 2
        return
    fi
    
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                        🎯 SELECT HOST FOR ANALYSIS                            ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}Select a host by number:${NC}"
    echo
    
    # Display numbered list of hosts
    local count=1
    while IFS='|' read -r ip hostname status info; do
        if [ $count -le 20 ]; then  # Show first 20 hosts
            echo -e "${YELLOW}$count)${NC} $ip ${GREEN}($hostname)${NC} - $status"
        fi
        count=$((count + 1))
    done < "$HOSTS_FILE"
    
    local host_count=$(wc -l < "$HOSTS_FILE")
    if [ $host_count -gt 20 ]; then
        echo -e "${BLUE}... and $((host_count - 20)) more hosts${NC}"
        echo -e "${YELLOW}a)${NC} Show all hosts"
    fi
    
    echo -e "${YELLOW}0)${NC} Back to host list"
    echo
    
    read -p "Select host (1-$host_count, a, or 0): " host_choice
    
    case $host_choice in
        [1-9]|[1-9][0-9]|[1-9][0-9][0-9])
            if [ "$host_choice" -ge 1 ] && [ "$host_choice" -le "$host_count" ]; then
                local selected_ip=$(sed -n "${host_choice}p" "$HOSTS_FILE" | cut -d'|' -f1)
                host_analysis_menu "$selected_ip"
            else
                echo -e "${RED}Invalid host number${NC}"
                sleep 1
            fi
            ;;
        a|A)
            if [ $host_count -gt 20 ]; then
                show_all_hosts_for_selection
            else
                echo -e "${RED}All hosts already shown${NC}"
                sleep 1
            fi
            ;;
        0|"")
            return
            ;;
        *)
            echo -e "${RED}Invalid selection${NC}"
            sleep 1
            ;;
    esac
}

show_all_hosts_for_selection() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                          🎯 ALL DISCOVERED HOSTS                              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # Create numbered list of all hosts
    local count=1
    while IFS='|' read -r ip hostname status info; do
        printf "${YELLOW}%3d)${NC} %-15s ${GREEN}%-20s${NC} %s\n" "$count" "$ip" "($hostname)" "$status"
        count=$((count + 1))
    done < "$HOSTS_FILE"
    
    local host_count=$(wc -l < "$HOSTS_FILE")
    echo
    echo -e "${YELLOW}0)${NC} Back"
    echo
    
    read -p "Select host (1-$host_count or 0): " host_choice
    
    case $host_choice in
        [1-9]|[1-9][0-9]|[1-9][0-9][0-9])
            if [ "$host_choice" -ge 1 ] && [ "$host_choice" -le "$host_count" ]; then
                local selected_ip=$(sed -n "${host_choice}p" "$HOSTS_FILE" | cut -d'|' -f1)
                host_analysis_menu "$selected_ip"
            else
                echo -e "${RED}Invalid host number${NC}"
                sleep 1
            fi
            ;;
        0|"")
            return
            ;;
        *)
            echo -e "${RED}Invalid selection${NC}"
            sleep 1
            select_host_for_analysis
            ;;
    esac
}

paginated_output() {
    local content="$1"
    local title="$2"
    
    echo "$content" > "$OUTPUT_TEMP"
    interactive_pager "$OUTPUT_TEMP" "$title"
}

search_in_report() {
    local content_file="$1"
    local title="$2"
    
    read -p "Search for: " search_term
    if [ -z "$search_term" ]; then
        return
    fi
    
    local search_results="$TEMP_DIR/search_results.txt"
    grep -n -i "$search_term" "$content_file" > "$search_results"
    
    if [ ! -s "$search_results" ]; then
        echo -e "${RED}No matches found for '$search_term'${NC}"
        sleep 2
        return
    fi
    
    local matches=$(wc -l < "$search_results")
    echo -e "${GREEN}Found $matches matches for '$search_term'${NC}"
    
    interactive_pager "$search_results" "Search Results: $search_term"
}

generate_report_summary() {
    local content_file="$1"
    local summary_file="$TEMP_DIR/report_summary.txt"
    
    {
        echo "=== REPORT SUMMARY ==="
        echo
        echo "Total Lines: $(wc -l < "$content_file")"
        echo "File Size: $(du -h "$content_file" | cut -f1)"
        echo
        echo "=== OPEN PORTS ==="
        grep -i "open" "$content_file" | head -10
        echo
        echo "=== VULNERABILITIES ==="
        grep -i -E "(vulnerable|vuln|cve)" "$content_file" | head -10
        echo
        echo "=== SERVICES ==="
        grep -i -E "(service|version)" "$content_file" | head -10
        echo
        echo "=== ERRORS/WARNINGS ==="
        grep -i -E "(error|warning|failed)" "$content_file" | head -5
    } > "$summary_file"
    
    interactive_pager "$summary_file" "Report Summary"
}

view_report_menu() {
    local report_file="$1"
    local report_title="$2"
    
    if [ ! -f "$report_file" ] || [ ! -s "$report_file" ]; then
        echo -e "${RED}❌ Report file not found or empty${NC}"
        sleep 2
        return
    fi
    
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║ 📊 REPORT VIEWER: $report_title${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo
        echo -e "${YELLOW}1)${NC} 📄 View Full Report (Interactive)"
        echo -e "${YELLOW}2)${NC} 📋 View Report Summary"
        echo -e "${YELLOW}3)${NC} 🔍 Search in Report"
        echo -e "${YELLOW}4)${NC} 🔧 Filter Report"
        echo -e "${YELLOW}5)${NC} 💾 Export Filtered Report"
        echo -e "${YELLOW}0)${NC} ⬅️  Back"
        echo
        read -p "Select option (default: 0): " choice
        choice=${choice:-0}
        
        case $choice in
            1) interactive_pager "$report_file" "$report_title" ;;
            2) generate_report_summary "$report_file" ;;
            3) search_in_report "$report_file" "$report_title" ;;
            4) filter_report "$report_file" "$report_title" ;;
            5) export_filtered_report "$report_file" "$report_title" ;;
            0|"") break ;;
            *) echo -e "${RED}❌ Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

filter_report() {
    local report_file="$1"
    local report_title="$2"
    local filtered_file="$TEMP_DIR/filtered_report.txt"
    
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                              🔧 FILTER REPORT                                  ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}Report: $report_title${NC}"
    echo
    
    # Show filter statistics
    local open_count=$(grep -c -i "open" "$report_file" 2>/dev/null || echo 0)
    local vuln_count=$(grep -c -i -E "(vulnerable|vuln|cve)" "$report_file" 2>/dev/null || echo 0)
    local service_count=$(grep -c -i -E "(service|version)" "$report_file" 2>/dev/null || echo 0)
    local error_count=$(grep -c -i -E "(error|warning|failed)" "$report_file" 2>/dev/null || echo 0)
    
    echo -e "${CYAN}Available Filters:${NC}"
    echo -e "${YELLOW}p)${NC} 🔓 Show only open ports ($open_count matches)"
    echo -e "${YELLOW}v)${NC} 🛡️  Show only vulnerabilities ($vuln_count matches)"
    echo -e "${YELLOW}s)${NC} 🔧 Show only services ($service_count matches)"
    echo -e "${YELLOW}e)${NC} ⚠️  Show only errors/warnings ($error_count matches)"
    echo -e "${YELLOW}c)${NC} 🔍 Custom filter pattern"
    echo -e "${YELLOW}0)${NC} ⬅️  Cancel"
    echo
    read -p "Select filter (p/v/s/e/c/0): " filter_choice
    
    case $filter_choice in
        p|P) 
            if [ "$open_count" -gt 0 ]; then
                grep -i "open" "$report_file" > "$filtered_file"
                interactive_pager "$filtered_file" "🔓 Open Ports - $report_title"
            else
                echo -e "${BLUE}💡 No open ports found in this report${NC}"
                sleep 2
            fi
            ;;
        v|V)
            if [ "$vuln_count" -gt 0 ]; then
                grep -i -E "(vulnerable|vuln|cve)" "$report_file" > "$filtered_file"
                interactive_pager "$filtered_file" "🛡️ Vulnerabilities - $report_title"
            else
                echo -e "${BLUE}💡 No vulnerabilities found in this report${NC}"
                sleep 2
            fi
            ;;
        s|S)
            if [ "$service_count" -gt 0 ]; then
                grep -i -E "(service|version)" "$report_file" > "$filtered_file"
                interactive_pager "$filtered_file" "🔧 Services - $report_title"
            else
                echo -e "${BLUE}💡 No services found in this report${NC}"
                sleep 2
            fi
            ;;
        e|E)
            if [ "$error_count" -gt 0 ]; then
                grep -i -E "(error|warning|failed)" "$report_file" > "$filtered_file"
                interactive_pager "$filtered_file" "⚠️ Errors/Warnings - $report_title"
            else
                echo -e "${BLUE}💡 No errors/warnings found in this report${NC}"
                sleep 2
            fi
            ;;
        c|C)
            read -p "Enter custom filter pattern: " custom_pattern
            if [ -n "$custom_pattern" ]; then
                local matches=$(grep -c -i "$custom_pattern" "$report_file" 2>/dev/null || echo 0)
                if [ "$matches" -gt 0 ]; then
                    grep -i "$custom_pattern" "$report_file" > "$filtered_file"
                    interactive_pager "$filtered_file" "🔍 Custom Filter: $custom_pattern - $report_title"
                else
                    echo -e "${BLUE}💡 No matches found for pattern: $custom_pattern${NC}"
                    sleep 2
                fi
            fi
            ;;
        0|"") 
            return 
            ;;
        *) 
            echo -e "${RED}❌ Invalid option${NC}"
            sleep 1
            ;;
    esac
}

export_filtered_report() {
    local report_file="$1"
    local report_title="$2"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                           💾 EXPORT FILTERED REPORT                           ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}Report: $report_title${NC}"
    echo
    
    # Show export statistics
    local open_count=$(grep -c -i "open" "$report_file" 2>/dev/null || echo 0)
    local vuln_count=$(grep -c -i -E "(vulnerable|vuln|cve)" "$report_file" 2>/dev/null || echo 0)
    local service_count=$(grep -c -i -E "(service|version)" "$report_file" 2>/dev/null || echo 0)
    local total_lines=$(wc -l < "$report_file")
    
    echo -e "${CYAN}Export Options:${NC}"
    echo -e "${YELLOW}p)${NC} 🔓 Export open ports only ($open_count lines)"
    echo -e "${YELLOW}v)${NC} 🛡️  Export vulnerabilities only ($vuln_count lines)"
    echo -e "${YELLOW}s)${NC} 🔧 Export services only ($service_count lines)"
    echo -e "${YELLOW}u)${NC} 📋 Export summary only"
    echo -e "${YELLOW}f)${NC} 📄 Export full report ($total_lines lines)"
    echo -e "${YELLOW}c)${NC} 🔍 Export custom filter"
    echo -e "${YELLOW}0)${NC} ⬅️  Cancel"
    echo
    read -p "Select export type (p/v/s/u/f/c/0): " export_choice
    
    local export_file="$TEMP_DIR/export_${timestamp}.txt"
    
    case $export_choice in
        p|P) 
            if [ "$open_count" -gt 0 ]; then
                {
                    echo "Open Ports Report - $report_title"
                    echo "Generated: $(date)"
                    echo "======================================="
                    grep -i "open" "$report_file"
                } > "$export_file"
                echo -e "${GREEN}✅ Exported $open_count open port entries${NC}"
            else
                echo -e "${BLUE}💡 No open ports to export${NC}"
                sleep 2
                return
            fi
            ;;
        v|V)
            if [ "$vuln_count" -gt 0 ]; then
                {
                    echo "Vulnerabilities Report - $report_title"
                    echo "Generated: $(date)"
                    echo "======================================="
                    grep -i -E "(vulnerable|vuln|cve)" "$report_file"
                } > "$export_file"
                echo -e "${GREEN}✅ Exported $vuln_count vulnerability entries${NC}"
            else
                echo -e "${BLUE}💡 No vulnerabilities to export${NC}"
                sleep 2
                return
            fi
            ;;
        s|S)
            if [ "$service_count" -gt 0 ]; then
                {
                    echo "Services Report - $report_title"
                    echo "Generated: $(date)"
                    echo "======================================="
                    grep -i -E "(service|version)" "$report_file"
                } > "$export_file"
                echo -e "${GREEN}✅ Exported $service_count service entries${NC}"
            else
                echo -e "${BLUE}💡 No services to export${NC}"
                sleep 2
                return
            fi
            ;;
        u|U)
            generate_report_summary "$report_file"
            cp "$TEMP_DIR/report_summary.txt" "$export_file"
            echo -e "${GREEN}✅ Exported report summary${NC}"
            ;;
        f|F)
            cp "$report_file" "$export_file"
            echo -e "${GREEN}✅ Exported full report ($total_lines lines)${NC}"
            ;;
        c|C)
            read -p "Enter filter pattern: " filter_pattern
            if [ -n "$filter_pattern" ]; then
                local matches=$(grep -c -i "$filter_pattern" "$report_file" 2>/dev/null || echo 0)
                if [ "$matches" -gt 0 ]; then
                    {
                        echo "Custom Filter Report - $report_title"
                        echo "Filter: $filter_pattern"
                        echo "Generated: $(date)"
                        echo "======================================="
                        grep -i "$filter_pattern" "$report_file"
                    } > "$export_file"
                    echo -e "${GREEN}✅ Exported $matches matching entries${NC}"
                else
                    echo -e "${BLUE}💡 No matches found for pattern: $filter_pattern${NC}"
                    sleep 2
                    return
                fi
            else
                return
            fi
            ;;
        0|"") 
            echo -e "${YELLOW}❌ Export cancelled${NC}"
            sleep 1
            return 
            ;;
        *) 
            echo -e "${RED}❌ Invalid option${NC}"
            sleep 1
            return 
            ;;
    esac
    
    echo -e "${GREEN}📁 Report exported to: $export_file${NC}"
    sleep 2
}

network_discovery_workflow() {
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                     🌐 NETWORK DISCOVERY & HOST ANALYSIS                      ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo
        
        # Show current discovered hosts if any
        if [ -f "$HOSTS_FILE" ] && [ -s "$HOSTS_FILE" ]; then
            local host_count=$(wc -l < "$HOSTS_FILE")
            echo -e "${GREEN}📊 Current Status: $host_count hosts discovered${NC}"
            echo -e "${BLUE}💡 Choose an option below to discover more hosts or analyze existing ones${NC}"
        else
            echo -e "${YELLOW}📡 No hosts discovered yet - start with network discovery${NC}"
        fi
        echo
        
        echo -e "${CYAN}Available Options:${NC}"
        echo -e "${YELLOW}1)${NC} 🔍 Quick Host Discovery (choose subnet)"
        echo -e "${YELLOW}2)${NC} 🔬 Advanced Host Discovery (requires root)"
        echo -e "${YELLOW}3)${NC} 🥷 Stealth Host Discovery (requires root)"
        echo -e "${YELLOW}4)${NC} 📍 Custom Subnet Discovery"
        echo -e "${YELLOW}5)${NC} 🌍 Multi-subnet Discovery"
        
        if [ -f "$HOSTS_FILE" ] && [ -s "$HOSTS_FILE" ]; then
            echo -e "${YELLOW}6)${NC} 🎯 Analyze Discovered Hosts"
        fi
        
        echo -e "${YELLOW}0)${NC} ⬅️  Back to Main Menu"
        echo
        read -p "Select option (default: 0): " choice
        choice=${choice:-0}
        
        case $choice in
            1) discover_hosts_quick; show_post_discovery_menu ;;
            2) 
                if [ "$EUID" -ne 0 ]; then
                    echo -e "${YELLOW}🔑 Advanced discovery requires root privileges${NC}"
                    read -p "Continue with sudo? (y/N): " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        ensure_root_for_scan "Advanced Discovery"
                    fi
                else
                    discover_hosts_detailed; show_post_discovery_menu
                fi
                ;;
            3)
                if [ "$EUID" -ne 0 ]; then
                    echo -e "${YELLOW}🔑 Stealth discovery requires root privileges${NC}"
                    read -p "Continue with sudo? (y/N): " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        ensure_root_for_scan "Stealth Discovery"
                    fi
                else
                    discover_hosts_stealth; show_post_discovery_menu
                fi
                ;;
            4) discover_hosts_custom; show_post_discovery_menu ;;
            5) discover_hosts_multi; show_post_discovery_menu ;;
            6) 
                if [ -f "$HOSTS_FILE" ] && [ -s "$HOSTS_FILE" ]; then
                    host_analysis_menu
                else
                    echo -e "${RED}❌ No hosts to analyze${NC}"
                    sleep 2
                fi
                ;;
            0|"") break ;;
            *) echo -e "${RED}❌ Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

show_post_discovery_menu() {
    if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
        echo -e "${RED}❌ No hosts discovered${NC}"
        sleep 2
        return
    fi
    
    clear
    local host_count=$(wc -l < "$HOSTS_FILE")
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                         ✅ DISCOVERY COMPLETED                                 ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${GREEN}🎯 Found $host_count hosts on the network${NC}"
    echo
    echo -e "${CYAN}Next Steps:${NC}"
    echo -e "${YELLOW}1)${NC} 🎯 Analyze discovered hosts"
    echo -e "${YELLOW}2)${NC} 📄 View discovery results"
    echo -e "${YELLOW}3)${NC} 🔍 Run another discovery scan"
    echo -e "${YELLOW}0)${NC} ⬅️  Back to discovery menu"
    echo
    read -p "Select option (default: 0): " choice
    choice=${choice:-0}
    
    case $choice in
        1) host_analysis_menu ;;
        2) display_discovered_hosts ;;
        3) return ;;
        0|"") return ;;
        *) echo -e "${RED}❌ Invalid option${NC}"; sleep 1 ;;
    esac
}

host_analysis_menu() {
    local target_ip="$1"
    
    # If a specific IP is provided, go directly to host detail menu
    if [ -n "$target_ip" ]; then
        local hostname=$(grep "^$target_ip|" "$HOSTS_FILE" | cut -d'|' -f2)
        if [ -n "$hostname" ]; then
            host_detail_menu "$target_ip" "$hostname"
        else
            echo -e "${RED}❌ Host $target_ip not found in discovered hosts${NC}"
            sleep 2
        fi
        return
    fi
    
    if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
        echo -e "${RED}❌ No hosts available for analysis${NC}"
        sleep 2
        return
    fi
    
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                            🎯 HOST ANALYSIS MENU                              ║${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo
        
        local host_count=$(wc -l < "$HOSTS_FILE")
        echo -e "${GREEN}📊 $host_count hosts available for analysis:${NC}"
        echo
        
        # Show numbered list of hosts
        local count=1
        while IFS='|' read -r ip hostname status info; do
            if [ $count -le 10 ]; then  # Show first 10 hosts
                echo -e "${YELLOW}$count)${NC} $ip ${BLUE}($hostname)${NC} - $status"
            fi
            count=$((count + 1))
        done < "$HOSTS_FILE"
        
        if [ $host_count -gt 10 ]; then
            echo -e "${BLUE}... and $((host_count - 10)) more hosts${NC}"
        fi
        
        echo
        echo -e "${CYAN}Analysis Options:${NC}"
        echo -e "${YELLOW}s)${NC} 📋 Show all hosts (paginated)"
        echo -e "${YELLOW}a)${NC} 🚀 Auto-analyze all hosts"
        echo -e "${YELLOW}0)${NC} ⬅️  Back to discovery menu"
        echo
        read -p "Select host number, option, or 0 to go back (default: 0): " choice
        choice=${choice:-0}
        
        case $choice in
            s|S) display_discovered_hosts ;;
            a|A) auto_analyze_all_hosts ;;
            0|"") break ;;
            [1-9]|[1-9][0-9])
                if [ "$choice" -le "$host_count" ]; then
                    host_line=$(sed -n "${choice}p" "$HOSTS_FILE")
                    if [ -n "$host_line" ]; then
                        IFS='|' read -r ip hostname <<< "$host_line"
                        host_detail_menu "$ip" "$hostname"
                    fi
                else
                    echo -e "${RED}❌ Invalid host number${NC}"
                    sleep 2
                fi
                ;;
            *) echo -e "${RED}❌ Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

auto_analyze_all_hosts() {
    if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
        echo -e "${RED}❌ No hosts to analyze${NC}"
        return
    fi
    
    clear
    local host_count=$(wc -l < "$HOSTS_FILE")
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                           🚀 AUTO-ANALYZE ALL HOSTS                           ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}This will perform a quick port scan on all $host_count discovered hosts${NC}"
    echo -e "${YELLOW}⚠️  This may take a while depending on the number of hosts${NC}"
    echo
    read -p "Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return
    fi
    
    clear
    echo -e "${CYAN}🚀 Auto-analyzing $host_count hosts...${NC}"
    echo
    
    local count=1
    while IFS='|' read -r ip hostname status info; do
        echo -e "${BLUE}[$count/$host_count] Analyzing $ip ($hostname)...${NC}"
        
        # Quick port scan with appropriate method based on privileges
        if [ "$EUID" -eq 0 ]; then
            nmap -sS --top-ports 100 "$ip" > "$TEMP_DIR/auto_scan_${ip}.txt" 2>&1
        else
            nmap -sT --top-ports 100 "$ip" > "$TEMP_DIR/auto_scan_${ip}.txt" 2>&1
        fi
        
        local open_ports=$(grep -c "open" "$TEMP_DIR/auto_scan_${ip}.txt" 2>/dev/null || echo 0)
        echo -e "  📊 Found $open_ports open ports"
        
        count=$((count + 1))
        echo
    done < "$HOSTS_FILE"
    
    echo -e "${GREEN}✅ Auto-analysis completed!${NC}"
    echo -e "${BLUE}💡 Use Report Management to view detailed results${NC}"
    echo
    read -p "Press Enter to continue..."
}

show_network_interfaces() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                           🔌 NETWORK INTERFACES                               ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    
    local interface_info="$TEMP_DIR/interface_info.txt"
    {
        echo "Interface | IP Address | Subnet | Status"
        echo "----------|------------|--------|-------"
        ip addr show | grep -E "^[0-9]+:|inet [0-9]" | while read line; do
            if [[ $line =~ ^[0-9]+: ]]; then
                interface=$(echo $line | awk '{print $2}' | tr -d ':')
                status=$(echo $line | grep -o "state [A-Z]*" | awk '{print $2}')
                echo -n "$interface | "
            elif [[ $line =~ inet && ! $line =~ 127.0.0.1 ]]; then
                ip=$(echo $line | awk '{print $2}')
                subnet=$(echo $ip | cut -d'/' -f1 | sed 's/\.[0-9]*$/.0/')
                subnet_mask=$(echo $ip | cut -d'/' -f2)
                echo "$ip | $subnet/$subnet_mask | $status"
            fi
        done
    } > "$interface_info"
    
    column -t -s '|' "$interface_info" | while read line; do
        if [[ $line == *"Interface"* ]]; then
            echo -e "${GREEN}$line${NC}"
        elif [[ $line == *"---"* ]]; then
            echo -e "${BLUE}$line${NC}"
        else
            echo -e "${YELLOW}$line${NC}"
        fi
    done
    echo
}

discover_hosts_quick() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                        🌐 NETWORK DISCOVERY                                   ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # Show progress for subnet discovery
    local subnet_list_file="$TEMP_DIR/discovered_subnets_list.txt"
    show_discovery_progress "$subnet_list_file"
    echo
    
    # Show subnet selection menu with file-based results
    show_subnet_selection_simple "$subnet_list_file"
    local selected_subnet="$?"
    
    # Get the selected subnet from the function output
    if [ $selected_subnet -eq 0 ]; then
        # Read the last line of the temp file that contains the selection
        MAIN_SUBNET=$(tail -1 "$TEMP_DIR/selected_subnet.txt" 2>/dev/null)
        if [ -z "$MAIN_SUBNET" ]; then
            echo -e "${YELLOW}⚠️  Discovery cancelled${NC}"
            sleep 1
            return
        fi
    else
        echo -e "${YELLOW}⚠️  Discovery cancelled${NC}"
        sleep 1
        return
    fi
    
    clear
    echo -e "${GREEN}🎯 Selected subnet: ${MAIN_SUBNET}${NC}"
    echo
    
    > "$HOSTS_FILE"
    local temp_scan="$TEMP_DIR/temp_scan.txt"
    
    # Calculate timeout based on subnet size
    local timeout_seconds=60  # Default for /24
    if [[ "$MAIN_SUBNET" =~ /16 ]]; then
        timeout_seconds=180  # 3 minutes for /16 networks
    elif [[ "$MAIN_SUBNET" =~ /8 ]]; then
        timeout_seconds=300  # 5 minutes for /8 networks
    elif [[ "$MAIN_SUBNET" =~ /([0-9]+)$ ]]; then
        local subnet_size="${BASH_REMATCH[1]}"
        if [ "$subnet_size" -lt 24 ]; then
            timeout_seconds=120  # 2 minutes for larger subnets
        fi
    fi
    
    # Show improved progress indicator for host discovery
    echo -e "${BLUE}⏱️  Estimated scan time: up to ${timeout_seconds} seconds for subnet size${NC}"
    show_progress_spinner_for_command "nmap -sn '$MAIN_SUBNET' > '$temp_scan' 2>&1" "$timeout_seconds" "${YELLOW}🔍 Scanning subnet ${MAIN_SUBNET} for active hosts..."
    echo -e " ✅ Discovery completed!${NC}"
    echo
    
    # Process results
    process_scan_results "$temp_scan"
    
    # Display results
    display_discovered_hosts
    
    # Show local network activity
    show_local_network_activity
}

discover_hosts_detailed() {
    clear
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ Detailed discovery requires root privileges for OS detection${NC}"
        echo -e "${BLUE}💡 Falling back to standard discovery${NC}"
        sleep 2
        discover_hosts_quick
        return
    fi
    
    show_network_interfaces
    
    local selected_subnet=$(show_subnet_selection "🔬 Detailed Discovery - Select Subnet")
    if [ -z "$selected_subnet" ]; then
        echo -e "${YELLOW}⚠️  Discovery cancelled${NC}"
        sleep 1
        return
    fi
    
    clear
    echo -e "${YELLOW}🔍 Performing detailed discovery on ${selected_subnet}...${NC}"
    echo -e "${CYAN}This includes OS detection and may take longer.${NC}\n"
    
    local temp_scan="$TEMP_DIR/detailed_scan.txt"
    > "$HOSTS_FILE"
    
    # Progress indicator
    echo -e "${CYAN}Discovery Progress:${NC}"
    
    # Run nmap directly since we're already root
    nmap -sn -O --osscan-guess "$selected_subnet" > "$temp_scan" 2>&1 &
    local scan_pid=$!
    
    show_progress_spinner $scan_pid "Performing detailed scan"
    
    # Process results with OS info
    process_detailed_scan_results "$temp_scan"
    display_discovered_hosts_detailed
    show_local_network_activity
}

discover_hosts_stealth() {
    clear
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ Stealth discovery requires root privileges for SYN scans${NC}"
        echo -e "${BLUE}💡 Falling back to standard discovery${NC}"
        sleep 2
        discover_hosts_quick
        return
    fi
    
    show_network_interfaces
    
    local selected_subnet=$(show_subnet_selection "🥷 Stealth Discovery - Select Subnet")
    if [ -z "$selected_subnet" ]; then
        echo -e "${YELLOW}⚠️  Discovery cancelled${NC}"
        sleep 1
        return
    fi
    
    clear
    echo -e "${YELLOW}🥷 Performing stealth discovery on ${selected_subnet}...${NC}"
    echo -e "${CYAN}Using SYN scan to avoid detection.${NC}\n"
    
    local temp_scan="$TEMP_DIR/stealth_scan.txt"
    > "$HOSTS_FILE"
    
    # Run nmap directly since we're already root
    nmap -sS -Pn --top-ports 100 "$selected_subnet" > "$temp_scan" 2>&1 &
    local scan_pid=$!
    
    show_progress_spinner $scan_pid "Performing stealth scan"
    
    process_stealth_scan_results "$temp_scan"
    display_discovered_hosts_stealth
    show_local_network_activity
}

discover_hosts_custom() {
    clear
    show_network_interfaces
    
    echo -e "${CYAN}📍 Custom Subnet Discovery${NC}"
    echo -e "${BLUE}Choose how to specify subnets:${NC}"
    echo
    echo -e "${YELLOW}1)${NC} Select from detected subnets"
    echo -e "${YELLOW}2)${NC} Enter multiple custom subnets"
    echo -e "${YELLOW}0)${NC} Cancel"
    echo
    read -p "Select option (1, 2, or 0): " method_choice
    
    local custom_subnets=""
    
    case $method_choice in
        1)
            while true; do
                local selected_subnet=$(show_subnet_selection "Select Additional Subnet (or 0 when done)")
                if [ -z "$selected_subnet" ]; then
                    break
                fi
                if [ -z "$custom_subnets" ]; then
                    custom_subnets="$selected_subnet"
                else
                    custom_subnets="$custom_subnets $selected_subnet"
                fi
                echo -e "${GREEN}✓ Added: $selected_subnet${NC}"
                echo -e "${BLUE}Current list: $custom_subnets${NC}"
                echo
            done
            ;;
        2)
            echo -e "${YELLOW}Enter multiple subnets separated by spaces${NC}"
            echo -e "${BLUE}Example: 192.168.1.0/24 10.0.0.0/24 172.16.0.0/24${NC}"
            echo
            read -p "Subnets to scan: " custom_subnets
            ;;
        0|"")
            echo -e "${YELLOW}⚠️  Discovery cancelled${NC}"
            sleep 1
            return
            ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            sleep 1
            return
            ;;
    esac
    
    if [ -z "$custom_subnets" ]; then
        echo -e "${RED}❌ No subnets specified.${NC}"
        sleep 1
        return
    fi
    
    > "$HOSTS_FILE"
    
    for subnet in $custom_subnets; do
        echo -e "\n${YELLOW}🔍 Scanning subnet: ${subnet}${NC}"
        local temp_scan="$TEMP_DIR/custom_scan_${subnet//\//_}.txt"
        
        nmap -sn $subnet > "$temp_scan" 2>&1 &
        local scan_pid=$!
        
        show_progress_spinner $scan_pid "Scanning $subnet"
        
        process_scan_results "$temp_scan"
    done
    
    display_discovered_hosts
    show_local_network_activity
}

discover_hosts_multi() {
    clear
    show_network_interfaces
    
    echo -e "${CYAN}Multi-Subnet Auto-Discovery${NC}"
    echo -e "${YELLOW}Automatically detecting and scanning all local subnets...${NC}\n"
    
    # Get all local subnets
    local subnets=($(ip route | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+" | awk '{print $1}' | grep -v "169.254"))
    
    if [ ${#subnets[@]} -eq 0 ]; then
        echo -e "${RED}❌ No local subnets found.${NC}"
        return
    fi
    
    > "$HOSTS_FILE"
    
    echo -e "${GREEN}Found ${#subnets[@]} local subnets:${NC}"
    for subnet in "${subnets[@]}"; do
        echo -e "  ${BLUE}📡 $subnet${NC}"
    done
    echo
    
    for subnet in "${subnets[@]}"; do
        echo -e "${YELLOW}🔍 Scanning subnet: ${subnet}${NC}"
        local temp_scan="$TEMP_DIR/multi_scan_${subnet//\//_}.txt"
        
        nmap -sn $subnet > "$temp_scan" 2>&1 &
        local scan_pid=$!
        
        show_progress_spinner $scan_pid "Scanning $subnet"
        
        process_scan_results "$temp_scan"
    done
    
    display_discovered_hosts
    show_local_network_activity
}

show_discovery_progress() {
    local output_file="$1"
    local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local spinner_length=${#spinner_chars}
    local count=0
    
    # Start subnet discovery in background
    get_detected_subnets > "$output_file" 2>/dev/null &
    local discovery_pid=$!
    
    # Show spinner while discovery runs
    while kill -0 $discovery_pid 2>/dev/null; do
        local spinner_char=${spinner_chars:$((count % spinner_length)):1}
        echo -ne "\r${YELLOW}🔍 Discovering available subnets... ${spinner_char}${NC}"
        sleep 0.2
        count=$((count + 1))
        
        # Timeout protection (max 60 seconds)
        if [ $((count / 5)) -ge 60 ]; then
            kill $discovery_pid 2>/dev/null
            echo -ne "\r${YELLOW}🔍 Discovering available subnets... ${RED}⚠️ Timeout${NC}"
            return 1
        fi
    done
    
    # Wait for discovery to finish
    wait $discovery_pid
    local exit_code=$?
    
    # Show completion
    if [ $exit_code -eq 0 ]; then
        local subnet_count=$(wc -l < "$output_file" 2>/dev/null || echo 0)
        echo -ne "\r${YELLOW}🔍 Discovering available subnets... ${GREEN}✅ Found $subnet_count networks${NC}"
    else
        echo -ne "\r${YELLOW}🔍 Discovering available subnets... ${RED}❌ Failed${NC}"
    fi
    
    return $exit_code
}

show_progress_spinner_for_command() {
    local command="$1"
    local max_time="$2"
    local phase_msg="$3"
    local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local spinner_length=${#spinner_chars}
    local count=0
    local start_time=$(date +%s)
    
    # Start the command in background
    eval "$command" &
    local cmd_pid=$!
    
    # Show spinner while command runs
    local timeout_reached=false
    while kill -0 $cmd_pid 2>/dev/null; do
        local spinner_char=${spinner_chars:$((count % spinner_length)):1}
        local elapsed=$(($(date +%s) - start_time))
        echo -ne "\r${phase_msg} ${YELLOW}${spinner_char}${NC} ${CYAN}(${elapsed}s)${NC}"
        sleep 0.1
        count=$((count + 1))
        
        # Timeout protection
        if [ $((count / 10)) -ge $max_time ]; then
            kill $cmd_pid 2>/dev/null
            timeout_reached=true
            break
        fi
    done
    
    # Wait for command to finish and get exit code
    wait $cmd_pid
    local exit_code=$?
    
    # Clear the spinner line - no timeout messages, just let the calling function handle success/failure
    local elapsed=$(($(date +%s) - start_time))
    echo -ne "\r${phase_msg} ${CYAN}(${elapsed}s)${NC}"
    
    return $exit_code
}

show_progress_spinner() {
    local pid=$1
    local message=$2
    local spin_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        printf "\r${CYAN}[${spin_chars:$i:1}] $message...${NC}"
        i=$(( (i + 1) % ${#spin_chars} ))
        sleep 0.1
    done
    
    wait $pid
    printf "\r${GREEN}[✓] $message completed!${NC}\n"
}

process_scan_results() {
    local scan_file="$1"
    
    grep -E "Nmap scan report" "$scan_file" | while read line; do
        if [[ $line == *"Nmap scan report"* ]]; then
            local host=$(echo $line | awk '{print $NF}' | tr -d '()')
            local hostname=$(echo $line | awk '{if(NF>4) print $5; else print "Unknown"}' | tr -d '()')
            echo "$host|$hostname|up|unknown" >> "$HOSTS_FILE"
        fi
    done
}

process_detailed_scan_results() {
    local scan_file="$1"
    
    local current_host=""
    local current_hostname=""
    local os_info=""
    
    while read line; do
        if [[ $line == *"Nmap scan report"* ]]; then
            current_host=$(echo $line | awk '{print $NF}' | tr -d '()')
            current_hostname=$(echo $line | awk '{if(NF>4) print $5; else print "Unknown"}' | tr -d '()')
            os_info="unknown"
        elif [[ $line == *"OS details"* ]]; then
            os_info=$(echo $line | cut -d':' -f2 | xargs)
        elif [[ $line == *"Host is up"* ]]; then
            echo "$current_host|$current_hostname|up|$os_info" >> "$HOSTS_FILE"
        fi
    done < "$scan_file"
}

process_stealth_scan_results() {
    local scan_file="$1"
    
    local current_host=""
    local port_count=0
    
    while read line; do
        if [[ $line == *"Nmap scan report"* ]]; then
            current_host=$(echo $line | awk '{print $NF}' | tr -d '()')
            port_count=0
        elif [[ $line == *"open"* ]]; then
            port_count=$((port_count + 1))
        elif [[ $line == *"Host is up"* ]] || [[ $line == *"Not shown"* ]]; then
            if [ "$port_count" -gt 0 ]; then
                echo "$current_host|Unknown|up|$port_count open ports" >> "$HOSTS_FILE"
            fi
        fi
    done < "$scan_file"
}

display_discovered_hosts() {
    if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
        echo -e "${RED}❌ No hosts discovered.${NC}"
        sleep 2
        return
    fi
    
    local host_count=$(wc -l < "$HOSTS_FILE")
    
    # Create formatted table
    local table_file="$TEMP_DIR/hosts_table.txt"
    {
        echo "No.|IP Address|Hostname|Status|Info"
        echo "---|----------|--------|------|----"
        local count=1
        while IFS='|' read -r ip hostname status info; do
            printf "%3d|%s|%s|%s|%s\n" "$count" "$ip" "$hostname" "$status" "$info"
            count=$((count + 1))
        done < "$HOSTS_FILE"
    } > "$table_file"
    
    # Create complete display
    {
        echo "╔═══════════════════════════════════════════════════════════════════════════════╗"
        echo "║                            🌐 DISCOVERED HOSTS                                ║"
        echo "╚═══════════════════════════════════════════════════════════════════════════════╝"
        echo
        echo "🎯 Found $host_count active hosts:"
        echo
        column -t -s '|' "$table_file"
        echo
        echo "📊 Host Categories:"
        
        local routers=0 servers=0 workstations=0 others=0
        while IFS='|' read -r ip hostname status info; do
            if [[ $hostname =~ (router|gateway|gw) ]] || [[ $ip =~ \.1$ ]]; then
                routers=$((routers + 1))
            elif [[ $hostname =~ (server|srv|nas) ]]; then
                servers=$((servers + 1))
            elif [[ $hostname =~ (pc|desktop|laptop|workstation) ]]; then
                workstations=$((workstations + 1))
            else
                others=$((others + 1))
            fi
        done < "$HOSTS_FILE"
        
        echo "  🔀 Routers/Gateways: $routers"
        echo "  🖥️  Servers: $servers"
        echo "  💻 Workstations: $workstations"
        echo "  ❓ Others: $others"
        echo
        echo "Press [h] to select a host for detailed analysis"
        
    } > "$OUTPUT_TEMP"
    
    interactive_host_selector "$OUTPUT_TEMP" "🌐 DISCOVERED HOSTS"
}

display_discovered_hosts_detailed() {
    display_discovered_hosts
    
    echo -e "${PURPLE}🔍 Detailed OS Information:${NC}"
    while IFS='|' read -r ip hostname status os_info; do
        if [ "$os_info" != "unknown" ]; then
            echo -e "  ${YELLOW}$ip${NC} - ${GREEN}$os_info${NC}"
        fi
    done < "$HOSTS_FILE"
    echo
}

display_discovered_hosts_stealth() {
    display_discovered_hosts
    
    echo -e "${PURPLE}🥷 Stealth Scan Results:${NC}"
    while IFS='|' read -r ip hostname status port_info; do
        if [ "$port_info" != "unknown" ]; then
            echo -e "  ${YELLOW}$ip${NC} - ${GREEN}$port_info${NC}"
        fi
    done < "$HOSTS_FILE"
    echo
}

categorize_hosts() {
    echo -e "${CYAN}📊 Host Categories:${NC}"
    
    local routers=0
    local servers=0
    local workstations=0
    local others=0
    
    while IFS='|' read -r ip hostname status info; do
        if [[ $hostname =~ (router|gateway|gw) ]] || [[ $ip =~ \.1$ ]]; then
            routers=$((routers + 1))
        elif [[ $hostname =~ (server|srv|nas) ]]; then
            servers=$((servers + 1))
        elif [[ $hostname =~ (pc|desktop|laptop|workstation) ]]; then
            workstations=$((workstations + 1))
        else
            others=$((others + 1))
        fi
    done < "$HOSTS_FILE"
    
    echo -e "  ${BLUE}🔀 Routers/Gateways: $routers${NC}"
    echo -e "  ${GREEN}🖥️  Servers: $servers${NC}"
    echo -e "  ${YELLOW}💻 Workstations: $workstations${NC}"
    echo -e "  ${PURPLE}❓ Others: $others${NC}"
    echo
}

show_local_network_activity() {
    local activity_content=""
    activity_content+="╔═══════════════════════════════════════════════════════════════════════════════╗\n"
    activity_content+="║                          🔌 LOCAL NETWORK ACTIVITY                            ║\n"
    activity_content+="╚═══════════════════════════════════════════════════════════════════════════════╝\n\n"
    
    activity_content+="🔊 Listening Services:\n"
    
    # Create listening services table
    local services_file="$TEMP_DIR/services_table.txt"
    {
        echo "Port|Protocol|Service|State"
        echo "----|--------|-------|-----"
        netstat -tuln 2>/dev/null | grep LISTEN | head -15 | while read line; do
            port=$(echo $line | awk '{print $4}' | cut -d':' -f2)
            protocol=$(echo $line | awk '{print $1}')
            service=$(getent services $port 2>/dev/null | awk '{print $1}' || echo "unknown")
            echo "$port|$protocol|$service|LISTENING"
        done
    } > "$services_file"
    
    column -t -s '|' "$services_file" >> "$OUTPUT_TEMP"
    activity_content+="\n\n"
    
    activity_content+="🔗 Active Connections:\n"
    
    # Create connections table
    local connections_file="$TEMP_DIR/connections_table.txt"
    {
        echo "Remote Host|Port|State|Protocol"
        echo "-----------|----|----|--------"
        netstat -tn 2>/dev/null | grep ESTABLISHED | head -15 | while read line; do
            remote=$(echo $line | awk '{print $5}' | cut -d':' -f1)
            port=$(echo $line | awk '{print $5}' | cut -d':' -f2)
            protocol=$(echo $line | awk '{print $1}')
            echo "$remote|$port|ESTABLISHED|$protocol"
        done
    } > "$connections_file"
    
    column -t -s '|' "$connections_file" >> "$OUTPUT_TEMP"
    activity_content+="\n\n"
    
    activity_content+="📈 Network Statistics:\n"
    activity_content+="  📊 Total discovered hosts: $(wc -l < "$HOSTS_FILE" 2>/dev/null || echo 0)\n"
    activity_content+="  🔊 Active listening ports: $(netstat -tuln 2>/dev/null | grep LISTEN | wc -l)\n"
    activity_content+="  🔗 Established connections: $(netstat -tn 2>/dev/null | grep ESTABLISHED | wc -l)\n"
    activity_content+="  🌐 Network interfaces: $(ip addr show | grep -c "inet ")\n"
    activity_content+="  📡 Routing table entries: $(ip route | wc -l)\n"
    
    # Use paginated output
    echo -e "$activity_content" > "$OUTPUT_TEMP"
    interactive_pager "$OUTPUT_TEMP" "🔌 LOCAL NETWORK ACTIVITY"
}

show_host_menu() {
    echo -e "\n${CYAN}=== Discovered Hosts ===${NC}"
    
    if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
        echo -e "${RED}No hosts discovered. Run initial scan first.${NC}"
        return 1
    fi
    
    local count=1
    while IFS='|' read -r ip hostname; do
        echo -e "${YELLOW}$count)${NC} $ip ${BLUE}($hostname)${NC}"
        count=$((count + 1))
    done < "$HOSTS_FILE"
    
    echo -e "${YELLOW}0)${NC} Return to main menu"
    echo -e "${YELLOW}r)${NC} Rescan network"
    echo
}

scan_host_ports() {
    local target_ip="$1"
    local hostname="$2"
    
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 🔍 PORT SCANNING: $target_ip ($hostname)${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # Use appropriate scan type based on privileges
    if [ "$EUID" -eq 0 ]; then
        echo -e "${GREEN}🔑 Using SYN scan (faster, requires root)${NC}"
        echo -e "${BLUE}⏱️  Estimated scan time: 45-90 seconds${NC}"
        echo
        show_progress_spinner_for_command "nmap -sS -O -sV --top-ports 1000 '$target_ip' > '$SCAN_RESULTS' 2>&1" 90 "${YELLOW}🔍 Scanning 1000 common ports on $target_ip..."
        echo -e " ✅ Scan completed!${NC}"
    else
        echo -e "${BLUE}🔓 Using TCP connect scan (slower, no root required)${NC}"
        echo -e "${BLUE}⏱️  Estimated scan time: 60-120 seconds${NC}"
        echo
        show_progress_spinner_for_command "nmap -sT -sV --top-ports 1000 '$target_ip' > '$SCAN_RESULTS' 2>&1" 120 "${YELLOW}🔍 Scanning 1000 common ports on $target_ip..."
        echo -e " ✅ Scan completed!${NC}"
    fi
    
    echo
    echo -e "${GREEN}📊 Quick Summary:${NC}"
    echo -e "${BLUE}   Open ports: $(grep -c "open" "$SCAN_RESULTS")${NC}"
    echo -e "${BLUE}   Filtered ports: $(grep -c "filtered" "$SCAN_RESULTS")${NC}"
    echo -e "${BLUE}   Services detected: $(grep -c "service" "$SCAN_RESULTS")${NC}"
    
    echo
    echo -e "${YELLOW}Options:${NC}"
    echo -e "${YELLOW}1)${NC} 📄 View full results interactively"
    echo -e "${YELLOW}0)${NC} ⬅️  Continue"
    echo
    read -p "Select option (default: 0): " view_choice
    view_choice=${view_choice:-0}
    
    if [ "$view_choice" = "1" ]; then
        view_report_menu "$SCAN_RESULTS" "Port Scan: $target_ip ($hostname)"
    fi
}

vulnerability_scan() {
    local target_ip="$1"
    local hostname="$2"
    local vuln_results="$TEMP_DIR/vuln_results_${target_ip}.txt"
    
    clear
    echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║ 🛡️ VULNERABILITY SCANNING: $target_ip ($hostname)${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}Running comprehensive vulnerability checks...${NC}"
    echo
    
    {
        echo "=== VULNERABILITY SCAN REPORT ==="
        echo "Target: $target_ip ($hostname)"
        echo "Date: $(date)"
        echo "======================================="
        echo
        echo "=== GENERAL VULNERABILITIES ==="
        nmap --script vuln "$target_ip" 2>/dev/null
        echo
        echo "=== SSL/TLS SECURITY CHECK ==="
        nmap --script ssl-enum-ciphers -p 443,8443 "$target_ip" 2>/dev/null
        echo
        echo "=== SMB SECURITY CHECK ==="
        nmap --script smb-vuln-* -p 445 "$target_ip" 2>/dev/null
        echo
        echo "=== HTTP VULNERABILITIES ==="
        nmap --script http-vuln-* -p 80,443,8080,8443 "$target_ip" 2>/dev/null
    } > "$vuln_results"
    
    clear
    echo -e "${GREEN}✅ Vulnerability scan completed${NC}"
    echo
    echo -e "${GREEN}📊 Quick Summary:${NC}"
    echo "   Vulnerabilities found: $(grep -c -i "vulnerable" "$vuln_results")"
    echo "   CVEs identified: $(grep -c -i "cve" "$vuln_results")"
    echo "   Security issues: $(grep -c -i -E "(security|risk|exploit)" "$vuln_results")"
    
    echo
    echo -e "${YELLOW}Options:${NC}"
    echo -e "${YELLOW}1)${NC} 📄 View full vulnerability report interactively"
    echo -e "${YELLOW}0)${NC} ⬅️  Continue"
    echo
    read -p "Select option (default: 0): " view_choice
    view_choice=${view_choice:-0}
    
    if [ "$view_choice" = "1" ]; then
        view_report_menu "$vuln_results" "Vulnerability Scan: $target_ip ($hostname)"
    fi
}

host_detail_menu() {
    local target_ip="$1"
    local hostname="$2"
    
    while true; do
        clear
        echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║ 🎯 HOST ANALYSIS: $target_ip ($hostname)${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo
        echo -e "${YELLOW}1)${NC} 📊 Custom Scan (Choose Tests)"
        echo -e "${YELLOW}2)${NC} 🔍 Port Scan"
        echo -e "${YELLOW}3)${NC} 🔎 Service Enumeration"
        echo -e "${YELLOW}4)${NC} 🛡️  Vulnerability Scan"
        echo -e "${YELLOW}5)${NC} 🌐 Network Trace"
        echo -e "${YELLOW}6)${NC} 📄 View Previous Results"
        echo -e "${YELLOW}7)${NC} 💾 Save Results"
        echo -e "${YELLOW}0)${NC} ⬅️  Back to Host List"
        echo
        read -p "Select option (default: 0): " choice
        choice=${choice:-0}
        
        case $choice in
            1) select_analysis_phases "$target_ip" "$hostname" ;;
            2) scan_host_ports "$target_ip" "$hostname" ;;
            3) service_enumeration "$target_ip" "$hostname" ;;
            4) vulnerability_scan "$target_ip" "$hostname" ;;
            5) network_trace "$target_ip" "$hostname" ;;
            6) view_previous_results "$target_ip" "$hostname" ;;
            7) save_results "$target_ip" "$hostname" ;;
            0|"") break ;;
            *) echo -e "${RED}❌ Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

select_analysis_phases() {
    local target_ip="$1"
    local hostname="$2"
    
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 📊 SELECT ANALYSIS PHASES: $target_ip ($hostname)${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}Select which analysis phases to run:${NC}"
    echo
    echo -e "${BLUE}1)${NC} 🔗 Connectivity Test (3-5 seconds)"
    echo -e "${BLUE}2)${NC} 🖥️  OS Detection (30-90 seconds)"
    echo -e "${BLUE}3)${NC} 🔍 Port Scanning (45-120 seconds)"
    echo -e "${BLUE}4)${NC} 🔎 Service Enumeration (2-5 minutes)"
    echo -e "${BLUE}5)${NC} 🛡️  Vulnerability Assessment (2-8 minutes)"
    echo -e "${BLUE}6)${NC} 🌐 Network Analysis (15-30 seconds)"
    echo
    echo -e "${GREEN}a)${NC} Run All Phases"
    echo -e "${GREEN}f)${NC} Fast Scan (1,2,3 only)"
    echo -e "${GREEN}s)${NC} Security Focus (1,3,5 only)"
    echo -e "${YELLOW}0)${NC} Back to host menu"
    echo
    
    read -p "Enter phase numbers (e.g., 1,3,5) or preset (a/f/s/0): " phase_selection
    
    case "$phase_selection" in
        0|"")
            return 1
            ;;
        a|A)
            complete_host_analysis "$target_ip" "$hostname" "1,2,3,4,5,6"
            ;;
        f|F)
            complete_host_analysis "$target_ip" "$hostname" "1,2,3"
            ;;
        s|S)
            complete_host_analysis "$target_ip" "$hostname" "1,3,5"
            ;;
        *)
            complete_host_analysis "$target_ip" "$hostname" "$phase_selection"
            ;;
    esac
}

complete_host_analysis() {
    local target_ip="$1"
    local hostname="$2"
    local selected_phases="$3"
    local analysis_results="$TEMP_DIR/complete_analysis_${target_ip}.txt"
    
    # Parse selected phases
    local run_phase1=false run_phase2=false run_phase3=false
    local run_phase4=false run_phase5=false run_phase6=false
    
    if [[ "$selected_phases" == *"1"* ]]; then run_phase1=true; fi
    if [[ "$selected_phases" == *"2"* ]]; then run_phase2=true; fi
    if [[ "$selected_phases" == *"3"* ]]; then run_phase3=true; fi
    if [[ "$selected_phases" == *"4"* ]]; then run_phase4=true; fi
    if [[ "$selected_phases" == *"5"* ]]; then run_phase5=true; fi
    if [[ "$selected_phases" == *"6"* ]]; then run_phase6=true; fi
    
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 📊 HOST ANALYSIS: $target_ip ($hostname)${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}🔍 Running selected analysis phases...${NC}"
    echo
    
    # Start the analysis report
    {
        echo "╔═══════════════════════════════════════════════════════════════════════════════╗"
        echo "║                        COMPLETE HOST ANALYSIS REPORT                          ║"
        echo "╚═══════════════════════════════════════════════════════════════════════════════╝"
        echo
        echo "🎯 TARGET: $target_ip ($hostname)"
        echo "📅 SCAN DATE: $(date)"
        echo "🖥️  SCANNING FROM: $(hostname) ($(ip route get 8.8.8.8 | grep -oP 'src \K\S+'))"
        echo
        
        echo "═══════════════════════════════════════════════════════════════════════════════"
        echo "🔍 BASIC HOST INFORMATION"
        echo "═══════════════════════════════════════════════════════════════════════════════"
    } > "$analysis_results"
    
    # Phase 1: Connectivity Test (with live progress)
    if [ "$run_phase1" = true ]; then
        echo -e "${BLUE}⏱️  Phase 1/6: Connectivity test - Expected time: 3-5 seconds${NC}"
        show_progress_spinner_for_command "ping -c 3 -W 2 '$target_ip' >/dev/null 2>&1" 5 "${GREEN}[1/6] 🔗 Testing connectivity..."
        echo -e " ✅ Done${NC}"
        
        {
            echo -n "🔗 Connectivity: "
            if ping -c 1 -W 2 "$target_ip" &>/dev/null; then
                echo "✅ ONLINE"
                local ping_result=$(ping -c 3 "$target_ip" 2>/dev/null | grep "time=" | tail -1)
                if [ -n "$ping_result" ]; then
                    echo "📡 Ping Response: $ping_result"
                fi
            else
                echo "❌ OFFLINE or FILTERED"
            fi
        } >> "$analysis_results"
    fi
    
    # Phase 2: OS Detection (with live progress)
    if [ "$run_phase2" = true ]; then
        local phase2_start=$(date +%s)
        if [ "$EUID" -eq 0 ]; then
        echo -e "${BLUE}⏱️  Phase 2/6: OS detection with root privileges - Expected time: 30-90 seconds${NC}"
        echo -ne "${GREEN}[2/6] 🖥️  Operating system detection...${NC}"
        {
            nmap -O -sV --version-intensity 5 --osscan-guess "$target_ip" 2>/dev/null > "$TEMP_DIR/os_detection.tmp"
        } &
        local phase2_pid=$!
        
        # Show spinner with elapsed time for entire phase
        local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local spinner_length=${#spinner_chars}
        local count=0
        while kill -0 $phase2_pid 2>/dev/null; do
            local spinner_char=${spinner_chars:$((count % spinner_length)):1}
            local elapsed=$(($(date +%s) - phase2_start))
            local time_color="${CYAN}"
            if [ $elapsed -gt 90 ]; then
                time_color="${RED}"
            fi
            echo -ne "\r${GREEN}[2/6] 🖥️  Operating system detection... ${YELLOW}${spinner_char}${NC} ${time_color}(${elapsed}s)${NC}"
            sleep 0.1
            count=$((count + 1))
        done
        wait $phase2_pid
    else
        echo -e "${BLUE}⏱️  Phase 2/6: Basic OS detection (limited) - Expected time: 20-60 seconds${NC}"
        echo -ne "${GREEN}[2/6] 🖥️  Operating system detection...${NC}"
        {
            nmap -sV --version-intensity 5 "$target_ip" 2>/dev/null > "$TEMP_DIR/os_detection.tmp"
        } &
        local phase2_pid=$!
        
        # Show spinner with elapsed time for entire phase
        local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local spinner_length=${#spinner_chars}
        local count=0
        while kill -0 $phase2_pid 2>/dev/null; do
            local spinner_char=${spinner_chars:$((count % spinner_length)):1}
            local elapsed=$(($(date +%s) - phase2_start))
            local time_color="${CYAN}"
            if [ $elapsed -gt 120 ]; then
                time_color="${RED}"
            fi
            echo -ne "\r${GREEN}[2/6] 🖥️  Operating system detection... ${YELLOW}${spinner_char}${NC} ${time_color}(${elapsed}s)${NC}"
            sleep 0.1
            count=$((count + 1))
        done
        wait $phase2_pid
    fi
    
        # Final elapsed time and completion
        local phase2_elapsed=$(($(date +%s) - phase2_start))
        echo -ne "\r${GREEN}[2/6] 🖥️  Operating system detection... ${CYAN}(${phase2_elapsed}s)${NC}"
        echo -e " ✅ Done${NC}"
        
        {
            echo "🖥️  Operating System Detection:"
            if [ -f "$TEMP_DIR/os_detection.tmp" ]; then
                grep -E "(OS|Service|Device)" "$TEMP_DIR/os_detection.tmp" | head -10
            fi
        } >> "$analysis_results"
    fi
    
    # Phase 3: Port Scanning (with live progress)
    if [ "$run_phase3" = true ]; then
        local phase3_start=$(date +%s)
        if [ "$EUID" -eq 0 ]; then
        echo -e "${BLUE}⏱️  Phase 3/6: SYN port scan (1000 ports) - Expected time: 45-90 seconds${NC}"
        echo -ne "${GREEN}[3/6] 🔍 Comprehensive port scanning...${NC}"
        {
            nmap -sS -sV --version-intensity 5 --top-ports 1000 "$target_ip" 2>/dev/null > "$TEMP_DIR/port_scan.tmp"
        } &
        local phase3_pid=$!
        
        # Show spinner with elapsed time for entire phase
        local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local spinner_length=${#spinner_chars}
        local count=0
        while kill -0 $phase3_pid 2>/dev/null; do
            local spinner_char=${spinner_chars:$((count % spinner_length)):1}
            local elapsed=$(($(date +%s) - phase3_start))
            local time_color="${CYAN}"
            if [ $elapsed -gt 90 ]; then
                time_color="${RED}"
            fi
            echo -ne "\r${GREEN}[3/6] 🔍 Comprehensive port scanning... ${YELLOW}${spinner_char}${NC} ${time_color}(${elapsed}s)${NC}"
            sleep 0.1
            count=$((count + 1))
        done
        wait $phase3_pid
    else
        echo -e "${BLUE}⏱️  Phase 3/6: TCP connect scan (1000 ports) - Expected time: 60-120 seconds${NC}"
        echo -ne "${GREEN}[3/6] 🔍 Comprehensive port scanning...${NC}"
        {
            nmap -sT -sV --version-intensity 5 --top-ports 1000 "$target_ip" 2>/dev/null > "$TEMP_DIR/port_scan.tmp"
        } &
        local phase3_pid=$!
        
        # Show spinner with elapsed time for entire phase
        local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local spinner_length=${#spinner_chars}
        local count=0
        while kill -0 $phase3_pid 2>/dev/null; do
            local spinner_char=${spinner_chars:$((count % spinner_length)):1}
            local elapsed=$(($(date +%s) - phase3_start))
            local time_color="${CYAN}"
            if [ $elapsed -gt 120 ]; then
                time_color="${RED}"
            fi
            echo -ne "\r${GREEN}[3/6] 🔍 Comprehensive port scanning... ${YELLOW}${spinner_char}${NC} ${time_color}(${elapsed}s)${NC}"
            sleep 0.1
            count=$((count + 1))
        done
        wait $phase3_pid
    fi
    
        # Final elapsed time and completion
        local phase3_elapsed=$(($(date +%s) - phase3_start))
        echo -ne "\r${GREEN}[3/6] 🔍 Comprehensive port scanning... ${CYAN}(${phase3_elapsed}s)${NC}"
        echo -e " ✅ Done${NC}"
        
        {
            echo
            echo "═══════════════════════════════════════════════════════════════════════════════"
            echo "🔍 PORT SCAN RESULTS"
            echo "═══════════════════════════════════════════════════════════════════════════════"
            
            echo "🔍 Scanning common ports..."
            if [ -f "$TEMP_DIR/port_scan.tmp" ]; then
                grep -E "(open|filtered|closed)" "$TEMP_DIR/port_scan.tmp"
            fi
        } >> "$analysis_results"
    fi
    
    # Phase 4: Service Enumeration (with live progress)
    if [ "$run_phase4" = true ]; then
        local phase4_start=$(date +%s)
        echo -e "${BLUE}⏱️  Phase 4/6: Service version detection & scripts - Expected time: 2-5 minutes${NC}"
    echo -ne "${GREEN}[4/6] 🔎 Service enumeration...${NC}"
    {
        nmap -sV --version-all --script=banner,http-title,ssh-hostkey,ssl-cert "$target_ip" 2>/dev/null > "$TEMP_DIR/service_enum.tmp"
    } &
    local phase4_pid=$!
    
    # Show spinner with elapsed time for entire phase
    local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local spinner_length=${#spinner_chars}
    local count=0
    while kill -0 $phase4_pid 2>/dev/null; do
        local spinner_char=${spinner_chars:$((count % spinner_length)):1}
        local elapsed=$(($(date +%s) - phase4_start))
        local time_color="${CYAN}"
        if [ $elapsed -gt 300 ]; then
            time_color="${RED}"
        fi
        echo -ne "\r${GREEN}[4/6] 🔎 Service enumeration... ${YELLOW}${spinner_char}${NC} ${time_color}(${elapsed}s)${NC}"
        sleep 0.1
        count=$((count + 1))
    done
    wait $phase4_pid
    
    # Final elapsed time and completion
    local phase4_elapsed=$(($(date +%s) - phase4_start))
    echo -ne "\r${GREEN}[4/6] 🔎 Service enumeration... ${CYAN}(${phase4_elapsed}s)${NC}"
    echo -e " ✅ Done${NC}"
    
        {
            echo
            echo "═══════════════════════════════════════════════════════════════════════════════"
            echo "🔎 SERVICE ENUMERATION"
            echo "═══════════════════════════════════════════════════════════════════════════════"
            
            echo "🔍 Detecting services and versions..."
            if [ -f "$TEMP_DIR/service_enum.tmp" ]; then
                grep -E "(open|Service|Version|title|ssl|ssh|banner)" "$TEMP_DIR/service_enum.tmp" | head -20
            fi
        } >> "$analysis_results"
    fi
    
    # Phase 5: Security Assessment (with live progress)
    if [ "$run_phase5" = true ]; then
        local phase5_start=$(date +%s)
        if [ "$EUID" -eq 0 ]; then
        echo -e "${BLUE}⏱️  Phase 5/6: Vulnerability scan (comprehensive) - Expected time: 3-8 minutes${NC}"
        echo -ne "${GREEN}[5/6] 🛡️  Security vulnerability assessment...${NC}"
        {
            nmap --script vuln --script-args=unsafe=1 "$target_ip" 2>/dev/null > "$TEMP_DIR/vuln_scan.tmp"
        } &
        local phase5_pid=$!
        
        # Show spinner with elapsed time for entire phase
        local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local spinner_length=${#spinner_chars}
        local count=0
        while kill -0 $phase5_pid 2>/dev/null; do
            local spinner_char=${spinner_chars:$((count % spinner_length)):1}
            local elapsed=$(($(date +%s) - phase5_start))
            local time_color="${CYAN}"
            if [ $elapsed -gt 120 ]; then
                time_color="${RED}"
            fi
            echo -ne "\r${GREEN}[5/6] 🛡️  Security vulnerability assessment... ${YELLOW}${spinner_char}${NC} ${time_color}(${elapsed}s)${NC}"
            sleep 0.1
            count=$((count + 1))
        done
        wait $phase5_pid
    else
        echo -e "${BLUE}⏱️  Phase 5/6: Vulnerability scan (safe mode) - Expected time: 2-6 minutes${NC}"
        echo -ne "${GREEN}[5/6] 🛡️  Security vulnerability assessment...${NC}"
        {
            nmap --script vuln "$target_ip" 2>/dev/null > "$TEMP_DIR/vuln_scan.tmp"
        } &
        local phase5_pid=$!
        
        # Show spinner with elapsed time for entire phase
        local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local spinner_length=${#spinner_chars}
        local count=0
        while kill -0 $phase5_pid 2>/dev/null; do
            local spinner_char=${spinner_chars:$((count % spinner_length)):1}
            local elapsed=$(($(date +%s) - phase5_start))
            local time_color="${CYAN}"
            if [ $elapsed -gt 90 ]; then
                time_color="${RED}"
            fi
            echo -ne "\r${GREEN}[5/6] 🛡️  Security vulnerability assessment... ${YELLOW}${spinner_char}${NC} ${time_color}(${elapsed}s)${NC}"
            sleep 0.1
            count=$((count + 1))
        done
        wait $phase5_pid
    fi
    
    # Final elapsed time and completion
    local phase5_elapsed=$(($(date +%s) - phase5_start))
    echo -ne "\r${GREEN}[5/6] 🛡️  Security vulnerability assessment... ${CYAN}(${phase5_elapsed}s)${NC}"
    echo -e " ✅ Done${NC}"
    
    {
        echo
        echo "═══════════════════════════════════════════════════════════════════════════════"
        echo "🛡️  SECURITY ASSESSMENT"
        echo "═══════════════════════════════════════════════════════════════════════════════"
        
        echo "🔍 Checking for common vulnerabilities..."
            if [ -f "$TEMP_DIR/vuln_scan.tmp" ]; then
                grep -E "(VULNERABLE|CVE|exploit|risk)" "$TEMP_DIR/vuln_scan.tmp" | head -10
            fi
        } >> "$analysis_results"
    fi
    
    # Phase 6: Network Analysis (with live progress)
    if [ "$run_phase6" = true ]; then
        local phase6_start=$(date +%s)
        echo -e "${BLUE}⏱️  Phase 6/6: Network trace & DNS lookup - Expected time: 15-30 seconds${NC}"
    echo -ne "${GREEN}[6/6] 🌐 Network path analysis...${NC}"
    {
        traceroute -m 10 "$target_ip" 2>/dev/null > "$TEMP_DIR/traceroute.tmp" &
        nslookup "$target_ip" 2>/dev/null > "$TEMP_DIR/dns_lookup.tmp" &
        wait
    } &
    local phase6_pid=$!
    
    # Show spinner with elapsed time for entire phase
    local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local spinner_length=${#spinner_chars}
    local count=0
    while kill -0 $phase6_pid 2>/dev/null; do
        local spinner_char=${spinner_chars:$((count % spinner_length)):1}
        local elapsed=$(($(date +%s) - phase6_start))
        local time_color="${CYAN}"
        if [ $elapsed -gt 30 ]; then
            time_color="${RED}"
        fi
        echo -ne "\r${GREEN}[6/6] 🌐 Network path analysis... ${YELLOW}${spinner_char}${NC} ${time_color}(${elapsed}s)${NC}"
        sleep 0.1
        count=$((count + 1))
    done
    wait $phase6_pid
    
    # Final elapsed time and completion
    local phase6_elapsed=$(($(date +%s) - phase6_start))
    echo -ne "\r${GREEN}[6/6] 🌐 Network path analysis... ${CYAN}(${phase6_elapsed}s)${NC}"
    echo -e " ✅ Done${NC}"
    
    {
        echo
        echo "═══════════════════════════════════════════════════════════════════════════════"
        echo "🌐 NETWORK INFORMATION"
        echo "═══════════════════════════════════════════════════════════════════════════════"
        
        echo "🔍 Network path to target:"
        if [ -f "$TEMP_DIR/traceroute.tmp" ]; then
            head -15 "$TEMP_DIR/traceroute.tmp"
        fi
        
        echo
        echo "🔍 DNS Information:"
        if [ -f "$TEMP_DIR/dns_lookup.tmp" ]; then
            grep -E "(name|Name)" "$TEMP_DIR/dns_lookup.tmp" | head -5
        fi
            
            echo
            echo "═══════════════════════════════════════════════════════════════════════════════"
            echo "📊 SCAN SUMMARY"
            echo "═══════════════════════════════════════════════════════════════════════════════"
            echo "✅ Scan completed: $(date)"
            echo "🎯 Target: $target_ip ($hostname)"
            echo "📈 Analysis Level: Comprehensive"
            echo "🔍 Scan Type: Full TCP/UDP service detection with vulnerability assessment"
            echo "⚠️  Note: This scan may have triggered security alerts on the target system"
            echo
            
        } >> "$analysis_results"
    fi
    
    # Final completion message
    echo
    echo -e "${GREEN}✅ All analysis phases completed successfully!${NC}"
    echo -e "${CYAN}📄 Report generated with comprehensive findings${NC}"
    sleep 1
    
    # Display results with pagination
    interactive_pager "$analysis_results" "📊 COMPLETE ANALYSIS: $target_ip"
    
    # Ask if user wants to save results
    echo
    read -p "Save this analysis report? (y/N): " save_choice
    if [[ "$save_choice" =~ ^[Yy]$ ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local save_file="host_analysis_${target_ip}_${timestamp}.txt"
        cp "$analysis_results" "$save_file"
        echo -e "${GREEN}📄 Analysis saved to: $save_file${NC}"
        sleep 2
    fi
}

service_enumeration() {
    local target_ip="$1"
    local hostname="$2"
    local service_results="$TEMP_DIR/service_enum_${target_ip}.txt"
    
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 🔎 SERVICE ENUMERATION: $target_ip ($hostname)${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}Detecting services and versions...${NC}"
    echo
    
    {
        echo "=== SERVICE ENUMERATION REPORT ==="
        echo "Target: $target_ip ($hostname)"
        echo "Date: $(date)"
        echo "======================================="
        echo
        echo "=== DETAILED SERVICE SCAN ==="
        nmap -sV -sC --script=banner,http-title,ftp-anon,smb-os-discovery "$target_ip" 2>/dev/null
        echo
        echo "=== HTTP SERVICE ENUMERATION ==="
        nmap --script http-enum -p 80,443,8080,8443 "$target_ip" 2>/dev/null
        echo
        echo "=== FTP ENUMERATION ==="
        nmap --script ftp-anon,ftp-bounce,ftp-proftpd-backdoor -p 21 "$target_ip" 2>/dev/null
        echo
        echo "=== SMB ENUMERATION ==="
        nmap --script smb-enum-shares,smb-enum-users,smb-os-discovery -p 445 "$target_ip" 2>/dev/null
    } > "$service_results"
    
    clear
    echo -e "${GREEN}✅ Service enumeration completed${NC}"
    echo
    echo -e "${GREEN}📊 Quick Summary:${NC}"
    echo "   Services detected: $(grep -c -i "service" "$service_results")"
    echo "   Open ports: $(grep -c "open" "$service_results")"
    echo "   HTTP services: $(grep -c -i "http" "$service_results")"
    
    echo
    echo -e "${YELLOW}Options:${NC}"
    echo -e "${YELLOW}1)${NC} 📄 View full service enumeration report interactively"
    echo -e "${YELLOW}0)${NC} ⬅️  Continue"
    echo
    read -p "Select option (default: 0): " view_choice
    view_choice=${view_choice:-0}
    
    if [ "$view_choice" = "1" ]; then
        view_report_menu "$service_results" "Service Enumeration: $target_ip ($hostname)"
    fi
}

network_trace() {
    local target_ip="$1"
    local hostname="$2"
    local trace_results="$TEMP_DIR/network_trace_${target_ip}.txt"
    
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ 🌐 NETWORK TRACE: $target_ip ($hostname)${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}Tracing network path and testing connectivity...${NC}"
    echo
    
    {
        echo "=== NETWORK TRACE REPORT ==="
        echo "Target: $target_ip ($hostname)"
        echo "Date: $(date)"
        echo "======================================="
        echo
        echo "=== TRACEROUTE ==="
        traceroute "$target_ip" 2>/dev/null || echo "Traceroute failed or not available"
        echo
        echo "=== PING STATISTICS ==="
        ping -c 10 "$target_ip" 2>/dev/null
        echo
        echo "=== NETWORK CONNECTIVITY TEST ==="
        echo "Testing common ports:"
        nc -zv "$target_ip" 22 2>&1 | head -1
        nc -zv "$target_ip" 80 2>&1 | head -1
        nc -zv "$target_ip" 443 2>&1 | head -1
    } > "$trace_results"
    
    clear
    echo -e "${GREEN}✅ Network trace completed${NC}"
    echo
    echo -e "${GREEN}📊 Quick Summary:${NC}"
    echo "   Hops to target: $(grep -c "ms" "$trace_results")"
    echo "   Ping average: $(grep "avg" "$trace_results" | awk -F'/' '{print $5}' | head -1)ms"
    
    echo
    echo -e "${YELLOW}Options:${NC}"
    echo -e "${YELLOW}1)${NC} 📄 View full network trace report interactively"
    echo -e "${YELLOW}0)${NC} ⬅️  Continue"
    echo
    read -p "Select option (default: 0): " view_choice
    view_choice=${view_choice:-0}
    
    if [ "$view_choice" = "1" ]; then
        view_report_menu "$trace_results" "Network Trace: $target_ip ($hostname)"
    fi
}

view_previous_results() {
    local target_ip="$1"
    local hostname="$2"
    
    echo -e "${CYAN}=== Previous Results: $target_ip ($hostname) ===${NC}"
    echo -e "${YELLOW}Available report files:${NC}\n"
    
    local count=1
    local files=()
    
    for file in $TEMP_DIR/*${target_ip}*.txt; do
        if [ -f "$file" ]; then
            local basename=$(basename "$file")
            local size=$(du -h "$file" | cut -f1)
            local date=$(stat -c %y "$file" | cut -d' ' -f1,2 | cut -d'.' -f1)
            echo -e "${YELLOW}$count)${NC} $basename ${BLUE}($size, $date)${NC}"
            files+=("$file")
            count=$((count + 1))
        fi
    done
    
    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${RED}No previous results found for this host.${NC}"
        sleep 2
        return
    fi
    
    echo -e "${YELLOW}0)${NC} Back"
    echo
    read -p "Select report to view: " file_choice
    
    if [[ "$file_choice" =~ ^[0-9]+$ ]] && [ "$file_choice" -gt 0 ] && [ "$file_choice" -le ${#files[@]} ]; then
        local selected_file="${files[$((file_choice - 1))]}"
        local report_name=$(basename "$selected_file")
        view_report_menu "$selected_file" "$report_name"
    elif [ "$file_choice" = "0" ]; then
        return
    else
        echo -e "${RED}Invalid selection${NC}"
        sleep 1
    fi
}

save_results() {
    local target_ip="$1"
    local hostname="$2"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local output_file="$TEMP_DIR/scan_${target_ip}_${timestamp}.txt"
    
    echo -e "${CYAN}=== Saving Results: $target_ip ($hostname) ===${NC}"
    echo -e "${YELLOW}Generating comprehensive report...${NC}\n"
    
    {
        echo "Network Security Scan Report"
        echo "Generated: $(date)"
        echo "Target: $target_ip ($hostname)"
        echo "================================="
        echo
        echo "PORT SCAN RESULTS:"
        nmap -sS -sV --top-ports 1000 "$target_ip" 2>/dev/null
        echo
        echo "VULNERABILITY SCAN:"
        nmap --script vuln "$target_ip" 2>/dev/null
        echo
        echo "SERVICE ENUMERATION:"
        nmap -sV -sC "$target_ip" 2>/dev/null
    } > "$output_file"
    
    echo -e "${GREEN}Results saved to: $output_file${NC}"
}

main_menu() {
    while true; do
        clear
        draw_box_top
        draw_box_centered "🛡️  INTERACTIVE NETWORK SECURITY SCANNER"
        draw_box_bottom
        echo
        
        # Show privilege status
        if [ "$EUID" -eq 0 ]; then
            echo -e "${GREEN}🔑 Status: Running with root privileges${NC}"
        else
            echo -e "${YELLOW}🔓 Status: Limited privileges (use 'sudo $0' for full features)${NC}"
        fi
        echo
        
        echo -e "${YELLOW}1)${NC} 🌐 Network Discovery & Host Analysis"
        echo -e "${YELLOW}2)${NC} 📊 Quick Network Overview"
        echo -e "${YELLOW}3)${NC} 📋 Report Management"
        echo -e "${YELLOW}4)${NC} 💾 Export All Results"
        echo -e "${YELLOW}0)${NC} 🚪 Exit"
        echo
        read -p "Select option (default: 0): " choice
        choice=${choice:-0}
        
        case $choice in
            1) network_discovery_workflow ;;
            2) quick_overview ;;
            3) report_management ;;
            4) export_all_results ;;
            0|"") echo -e "${GREEN}👋 Exiting...${NC}"; exit 0 ;;
            *) echo -e "${RED}❌ Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

report_management() {
    while true; do
        clear
        draw_box_top
        draw_box_centered "📋 REPORT MANAGEMENT"
        draw_box_bottom
        echo
        echo -e "${YELLOW}1)${NC} 📄 View All Reports"
        echo -e "${YELLOW}2)${NC} 🔍 Search Reports"
        echo -e "${YELLOW}3)${NC} 🧹 Clean Old Reports"
        echo -e "${YELLOW}4)${NC} 📊 Report Statistics"
        echo -e "${YELLOW}0)${NC} ⬅️  Back to Main Menu"
        echo
        read -p "Select option (default: 0): " choice
        choice=${choice:-0}
        
        case $choice in
            1) view_all_reports ;;
            2) search_all_reports ;;
            3) clean_old_reports ;;
            4) report_statistics ;;
            0|"") break ;;
            *) echo -e "${RED}❌ Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

view_all_reports() {
    while true; do
        clear
        draw_box_top
        draw_box_centered "📄 ALL REPORTS"
        draw_box_bottom
        echo
        
        local count=1
        local files=()
        
        for file in $TEMP_DIR/*.txt; do
            if [ -f "$file" ] && [[ "$file" =~ (scan|vuln|service|trace|export) ]]; then
                local basename=$(basename "$file")
                local size=$(du -h "$file" | cut -f1)
                local date=$(stat -c %y "$file" | cut -d' ' -f1,2 | cut -d'.' -f1)
                echo -e "${YELLOW}$count)${NC} $basename ${BLUE}($size, $date)${NC}"
                files+=("$file")
                count=$((count + 1))
            fi
        done
        
        if [ ${#files[@]} -eq 0 ]; then
            echo -e "${RED}❌ No reports found.${NC}"
            echo -e "${BLUE}💡 Run some scans first to generate reports${NC}"
            sleep 2
            return
        fi
        
        echo
        echo -e "${CYAN}Quick Actions:${NC}"
        echo -e "${YELLOW}a)${NC} 📊 View all report summaries"
        echo -e "${YELLOW}d)${NC} 🗑️  Delete old reports"
        echo -e "${YELLOW}0)${NC} ⬅️  Back"
        echo
        read -p "Select report number (1-${#files[@]}), action (a/d), or 0: " choice
        
        case $choice in
            [1-9]|[1-9][0-9])
                if [ "$choice" -le "${#files[@]}" ]; then
                    local selected_file="${files[$((choice - 1))]}"
                    local report_name=$(basename "$selected_file")
                    view_report_menu "$selected_file" "$report_name"
                else
                    echo -e "${RED}❌ Invalid report number${NC}"
                    sleep 1
                fi
                ;;
            a|A)
                show_all_report_summaries "${files[@]}"
                ;;
            d|D)
                clean_old_reports
                ;;
            0|"")
                break
                ;;
            *)
                echo -e "${RED}❌ Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

show_all_report_summaries() {
    local files=("$@")
    local summary_content=""
    
    summary_content+="╔═══════════════════════════════════════════════════════════════════════════════╗\n"
    summary_content+="║                            📊 ALL REPORT SUMMARIES                            ║\n"
    summary_content+="╚═══════════════════════════════════════════════════════════════════════════════╝\n\n"
    
    local count=1
    for file in "${files[@]}"; do
        local basename=$(basename "$file")
        local size=$(du -h "$file" | cut -f1)
        local lines=$(wc -l < "$file")
        
        summary_content+="[$count] $basename ($size, $lines lines)\n"
        summary_content+="    Open ports: $(grep -c -i "open" "$file" 2>/dev/null || echo 0)\n"
        summary_content+="    Vulnerabilities: $(grep -c -i -E "(vulnerable|vuln|cve)" "$file" 2>/dev/null || echo 0)\n"
        summary_content+="    Services: $(grep -c -i "service" "$file" 2>/dev/null || echo 0)\n"
        summary_content+="\n"
        count=$((count + 1))
    done
    
    echo -e "$summary_content" > "$OUTPUT_TEMP"
    interactive_pager "$OUTPUT_TEMP" "📊 ALL REPORT SUMMARIES"
}

search_all_reports() {
    echo -e "${CYAN}=== Search Reports ===${NC}"
    read -p "Enter search term: " search_term
    
    if [ -z "$search_term" ]; then
        return
    fi
    
    local search_results="$TEMP_DIR/global_search_results.txt"
    echo "=== GLOBAL SEARCH RESULTS ===" > "$search_results"
    echo "Search term: $search_term" >> "$search_results"
    echo "Date: $(date)" >> "$search_results"
    echo "=======================================" >> "$search_results"
    echo >> "$search_results"
    
    local matches=0
    for file in $TEMP_DIR/*.txt; do
        if [ -f "$file" ] && [[ "$file" =~ (scan|vuln|service|trace|export) ]]; then
            local file_matches=$(grep -c -i "$search_term" "$file" 2>/dev/null)
            if [ "$file_matches" -gt 0 ]; then
                echo "=== $(basename "$file") ($file_matches matches) ===" >> "$search_results"
                grep -n -i "$search_term" "$file" >> "$search_results"
                echo >> "$search_results"
                matches=$((matches + file_matches))
            fi
        fi
    done
    
    if [ "$matches" -gt 0 ]; then
        echo -e "${GREEN}Found $matches matches across all reports.${NC}"
        view_report_menu "$search_results" "Global Search Results: $search_term"
    else
        echo -e "${RED}No matches found for '$search_term'.${NC}"
        sleep 2
    fi
}

clean_old_reports() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                              🧹 CLEAN OLD REPORTS                              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # Show current report statistics
    local total_reports=$(find /tmp -name "*.txt" -type f 2>/dev/null | wc -l)
    local old_day=$(find /tmp -name "*.txt" -type f -mtime +1 2>/dev/null | wc -l)
    local old_week=$(find /tmp -name "*.txt" -type f -mtime +7 2>/dev/null | wc -l)
    
    echo -e "${BLUE}📊 Current Report Statistics:${NC}"
    echo -e "   Total reports: $total_reports"
    echo -e "   Older than 1 day: $old_day"
    echo -e "   Older than 1 week: $old_week"
    echo
    
    echo -e "${CYAN}Cleanup Options:${NC}"
    echo -e "${YELLOW}1)${NC} 📅 Delete reports older than 1 day ($old_day files)"
    echo -e "${YELLOW}2)${NC} 📆 Delete reports older than 1 week ($old_week files)"
    echo -e "${YELLOW}3)${NC} 🗑️  Delete ALL reports ($total_reports files)"
    echo -e "${YELLOW}s)${NC} 📋 Show detailed file list"
    echo -e "${YELLOW}0)${NC} ⬅️  Cancel"
    echo
    read -p "Select option (1/2/3/s/0): " clean_choice
    
    case $clean_choice in
        1)
            if [ "$old_day" -gt 0 ]; then
                find /tmp -name "*.txt" -type f -mtime +1 -exec rm {} \; 2>/dev/null
                echo -e "${GREEN}✅ Deleted $old_day reports older than 1 day${NC}"
            else
                echo -e "${BLUE}💡 No reports older than 1 day found${NC}"
            fi
            ;;
        2)
            if [ "$old_week" -gt 0 ]; then
                find /tmp -name "*.txt" -type f -mtime +7 -exec rm {} \; 2>/dev/null
                echo -e "${GREEN}✅ Deleted $old_week reports older than 1 week${NC}"
            else
                echo -e "${BLUE}💡 No reports older than 1 week found${NC}"
            fi
            ;;
        3)
            echo -e "${RED}⚠️  WARNING: This will delete ALL reports!${NC}"
            read -p "Type 'DELETE' to confirm: " confirm
            if [ "$confirm" = "DELETE" ]; then
                rm -f $TEMP_DIR/scan_*.txt $TEMP_DIR/vuln_*.txt $TEMP_DIR/service_*.txt $TEMP_DIR/trace_*.txt $TEMP_DIR/export_*.txt 2>/dev/null
                echo -e "${GREEN}✅ All reports deleted${NC}"
            else
                echo -e "${YELLOW}❌ Cancelled - confirmation text did not match${NC}"
            fi
            ;;
        s|S)
            show_detailed_file_list
            ;;
        0|"")
            echo -e "${YELLOW}❌ Cleanup cancelled${NC}"
            ;;
        *)
            echo -e "${RED}❌ Invalid option${NC}"
            ;;
    esac
    sleep 2
}

show_detailed_file_list() {
    local file_content=""
    file_content+="╔═══════════════════════════════════════════════════════════════════════════════╗\n"
    file_content+="║                             📋 DETAILED FILE LIST                             ║\n"
    file_content+="╚═══════════════════════════════════════════════════════════════════════════════╝\n\n"
    
    file_content+="Report Files by Age:\n\n"
    
    for file in $TEMP_DIR/*.txt; do
        if [ -f "$file" ] && [[ "$file" =~ (scan|vuln|service|trace|export) ]]; then
            local basename=$(basename "$file")
            local size=$(du -h "$file" | cut -f1)
            local date=$(stat -c %y "$file" | cut -d' ' -f1,2)
            local age_days=$(( ($(date +%s) - $(stat -c %Y "$file")) / 86400 ))
            
            file_content+="$basename ($size) - $date ($age_days days old)\n"
        fi
    done | sort -k3
    
    echo -e "$file_content" > "$OUTPUT_TEMP"
    interactive_pager "$OUTPUT_TEMP" "📋 DETAILED FILE LIST"
}

report_statistics() {
    echo -e "${CYAN}=== Report Statistics ===${NC}"
    echo -e "${YELLOW}Analyzing all reports...${NC}\n"
    
    local total_reports=0
    local total_size=0
    local port_scans=0
    local vuln_scans=0
    local service_scans=0
    local trace_scans=0
    
    for file in $TEMP_DIR/*.txt; do
        if [ -f "$file" ] && [[ "$file" =~ (scan|vuln|service|trace|export) ]]; then
            total_reports=$((total_reports + 1))
            total_size=$((total_size + $(stat -c%s "$file" 2>/dev/null || echo 0)))
            
            if [[ "$file" =~ scan ]]; then
                port_scans=$((port_scans + 1))
            elif [[ "$file" =~ vuln ]]; then
                vuln_scans=$((vuln_scans + 1))
            elif [[ "$file" =~ service ]]; then
                service_scans=$((service_scans + 1))
            elif [[ "$file" =~ trace ]]; then
                trace_scans=$((trace_scans + 1))
            fi
        fi
    done
    
    echo -e "${GREEN}Total Reports: $total_reports${NC}"
    echo -e "${GREEN}Total Size: $(numfmt --to=iec $total_size)${NC}"
    echo -e "${GREEN}Port Scans: $port_scans${NC}"
    echo -e "${GREEN}Vulnerability Scans: $vuln_scans${NC}"
    echo -e "${GREEN}Service Scans: $service_scans${NC}"
    echo -e "${GREEN}Network Traces: $trace_scans${NC}"
    echo
    
    if [ $total_reports -gt 0 ]; then
        echo -e "${YELLOW}Recent Activity:${NC}"
        ls -lt $TEMP_DIR/*.txt 2>/dev/null | head -5 | while read line; do
            echo "  $line"
        done
    fi
}

quick_overview() {
    local overview_content=""
    overview_content+="╔═══════════════════════════════════════════════════════════════════════════════╗\n"
    overview_content+="║                            📊 QUICK NETWORK OVERVIEW                          ║\n"
    overview_content+="╚═══════════════════════════════════════════════════════════════════════════════╝\n\n"
    
    if [ -f "$HOSTS_FILE" ] && [ -s "$HOSTS_FILE" ]; then
        overview_content+="🌐 Discovered Hosts:\n"
        while IFS='|' read -r ip hostname status info; do
            overview_content+="  $ip ($hostname)\n"
        done < "$HOSTS_FILE"
        overview_content+="\n"
    else
        overview_content+="🌐 No hosts discovered yet. Run 'Discover Network Hosts' first.\n\n"
    fi
    
    overview_content+="🔊 Local Listening Ports:\n"
    netstat -tuln 2>/dev/null | grep LISTEN | head -20 | while read line; do
        port=$(echo $line | awk '{print $4}' | cut -d':' -f2)
        protocol=$(echo $line | awk '{print $1}')
        service=$(getent services $port 2>/dev/null | awk '{print $1}' || echo "unknown")
        overview_content+="  $port/$protocol ($service)\n"
    done
    overview_content+="\n"
    
    overview_content+="🔗 Active Connections:\n"
    netstat -tn 2>/dev/null | grep ESTABLISHED | head -15 | while read line; do
        remote=$(echo $line | awk '{print $5}' | cut -d':' -f1)
        port=$(echo $line | awk '{print $5}' | cut -d':' -f2)
        protocol=$(echo $line | awk '{print $1}')
        overview_content+="  $remote:$port ($protocol)\n"
    done
    overview_content+="\n"
    
    overview_content+="📈 Summary Statistics:\n"
    overview_content+="  📊 Discovered hosts: $(wc -l < "$HOSTS_FILE" 2>/dev/null || echo 0)\n"
    overview_content+="  🔊 Listening ports: $(netstat -tuln 2>/dev/null | grep LISTEN | wc -l)\n"
    overview_content+="  🔗 Active connections: $(netstat -tn 2>/dev/null | grep ESTABLISHED | wc -l)\n"
    overview_content+="  🌐 Network interfaces: $(ip addr show | grep -c "inet ")\n"
    
    echo -e "$overview_content" > "$OUTPUT_TEMP"
    interactive_pager "$OUTPUT_TEMP" "📊 QUICK NETWORK OVERVIEW"
}

export_all_results() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local export_file="$TEMP_DIR/network_scan_export_${timestamp}.txt"
    
    echo -e "${CYAN}=== Exporting All Results ===${NC}"
    echo -e "${YELLOW}Generating comprehensive network report...${NC}\n"
    
    {
        echo "Complete Network Security Assessment"
        echo "Generated: $(date)"
        echo "======================================="
        echo
        echo "NETWORK OVERVIEW:"
        ip addr show | grep -E "inet [0-9]" | grep -v "127.0.0.1"
        echo
        echo "DISCOVERED HOSTS:"
        cat "$HOSTS_FILE" 2>/dev/null || echo "No hosts discovered"
        echo
        echo "LOCAL SERVICES:"
        netstat -tuln 2>/dev/null | grep LISTEN || ss -tuln | grep LISTEN
        echo
        echo "ACTIVE CONNECTIONS:"
        netstat -tn 2>/dev/null | grep ESTABLISHED || ss -tn | grep ESTAB
    } > "$export_file"
    
    echo -e "${GREEN}Complete report exported to: $export_file${NC}"
}

setup_temp_directory
check_dependencies
check_privileges
main_menu