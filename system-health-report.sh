#!/bin/bash


##################
## Hamza Alhalabi
## 24/Jan/2025
##################


# Log file location
log_file="$(dirname "$0")/system-health-report.log"


# Display the help message
function show_help() {
    echo "Usage: sys-health-report [critical_service1] [critical_service2] ... [critical_serviceN] " 
    echo "Description: Generates a system health report and checks critical services" 
    echo "If no arguments are provided, default critical services will be checked" 
    echo 
    echo "Options:" 
    echo "  --help                    Show this help message and exit" 
    echo "  [critical_serviceN]       Specify critical services names like [name.service]" 
}

# Redirect all output to the console and log file
exec > >(tee "$log_file") 2>&1

# Check if --help is provided as the first argument
if [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Check disk space
check_disk_space() {
    echo "Disk Space Check:"
    echo ""

    # Disk usage details for the root partition
    disk_info=$(df -h / | awk 'NR==2')
    total_space=$(echo "$disk_info" | awk '{printf "%.1f GiB", $2+0}')
    used_space=$(echo "$disk_info" | awk '{printf "%.1f GiB", $3+0}')
    available_space=$(echo "$disk_info" | awk '{printf "%.1f GiB", $4+0}')
    disk_usage=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')

    # Display details
    echo "Total disk space: $total_space"
    echo "Used space: $used_space"
    echo "Available space: $available_space"
    echo "Usage: ${disk_usage}% full"

    # Check if disk usage exceeds 80%
    if [ "$disk_usage" -gt 80 ]; then
        echo "Warning! Disk space usage is higher than 80%"
        echo "Recommendation: Clean up the disk space. Remove unnecessary files or expand your disk."
    else
        echo "Disk usage is within healthy limits."
    fi
    echo ""
    echo "================="
}

# Check memory usage
check_memory_usage() {
    echo "Memory Usage Check:"
    echo ""

    total_mem=$(free -m | awk '/Mem:/ {print $2}')
    used_mem=$(free -m | awk '/Mem:/ {print $3}')
    mem_usage_percent=$((used_mem * 100 / total_mem))
    echo "Memory usage: ${mem_usage_percent}% ($(printf "%.2f" "$(bc <<< "scale=2; ${used_mem}/1024")") GiB used of $(printf "%.2f" "$(bc <<< "scale=2; ${total_mem}/1024")") GiB total)"

    # Check if memory usage exceeds 90%
    if [ "$mem_usage_percent" -gt 90 ]; then
        echo "Warning! Memory usage is higher than 90%"
        echo "Recommendation: Consider closing unused applications or increasing system RAM."
    else
        echo "Memory usage is within healthy limits."
    fi
    echo ""
    echo "================="
}

# Check device's running services
check_running_services() {
    echo "Running Services Check:"
    echo ""

    # Default critical services
    critical_services=("cron.service")

    if [ "$#" -eq 0 ]; then
        echo "No arguments provided. Using default critical services: ${critical_services[@]}"
    else
        echo "Checking user-specified critical services: $@"
        # Override if arguments are provided
        critical_services=("$@")
    fi
    echo ""

    # List all active services
    readarray -t running_services < <(systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}')

    if [ -z "$running_services" ]; then
        echo "No services are currently running"
        echo "Recommendation: Start necessary services if required for your system's functionality."
    else
        echo "The following services are currently running:"
        printf "  - %s\n" "${running_services[@]}"
        echo ""

        echo "Top Resource-Consuming Services:"
        echo "--------------------------------"
        printf "%-8s %-40s %-6s %-6s\n" "PID" "COMMAND" "%MEM" "%CPU"
        ps -eo pid,args,%mem,%cpu --sort=-%mem --cols=200 | head -n 10 | awk 'NR>1 {
            cmd=$2; for(i=3;i<=NF-2;i++) cmd=cmd" "$i;
            printf "%-8s %-40s %-6s %-6s\n", $1, cmd, $(NF-1), $NF
        }'
        echo ""

        running_services=$(systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}')

        # Critical Services information
        echo "Critical Services:"
        echo ""
        for service in "${critical_services[@]}"; do
            if ! echo "$running_services" | grep -qw "$service"; then
                echo "Warning: Critical service $service is not running."
                echo "$service is stopped. Attempting to restart..."
                sudo systemctl restart "$service"
                if [ $? -eq 0 ]; then
                    echo "$service restarted successfully."
                else
                    echo "Failed to restart $service. Please check manually."
                fi
            else
                echo "$service is running."
            fi
        done
    fi

    echo ""
    echo "System Load:"
    uptime
    echo ""

    echo "================="
}

check_system_updates(){
    echo "System Updates Check:"
    echo ""

    # Check for available updates
    updates=$(sudo apt list --upgradable 2>/dev/null | grep -v "Listing" | wc -l)

    if [[ $updates -gt 0 ]]; then
        echo "There are $updates package(s) available for update."
        echo ""
        echo "Here is a categorized list of updates (Kernel, Security, and Other):"
        echo ""

        # Fetch list of upgradable packages
        upgradable_packages=$(sudo apt list --upgradable 2>/dev/null | grep -v "Listing")

        # Variables for categorized output
        kernel_updates=()
        security_updates=()
        other_updates=()

        # Process each line of the upgradable packages
        while IFS= read -r line; do
            package=$(echo "$line" | awk -F/ '{print $1}')
            if [[ $package == "linux-image-"* ]] || [[ $package == "linux-headers-"* ]]; then
                kernel_updates+=("$line")
            elif echo "$package" | grep -qi "security"; then
                security_updates+=("$line")
            else
                other_updates+=("$line")
            fi
        done <<< "$upgradable_packages"

        # Display updates
        if [[ ${#kernel_updates[@]} -gt 0 ]]; then
            echo "Kernel Updates:"
            printf "  - %s\n" "${kernel_updates[@]}"
            echo ""
        fi

        if [[ ${#security_updates[@]} -gt 0 ]]; then
            echo "Security Updates:"
            printf "  - %s\n" "${security_updates[@]}"
            echo ""
        fi

        if [[ ${#other_updates[@]} -gt 0 ]]; then
            echo "Other Updates:"
            printf "  - %s\n" "${other_updates[@]}"
            echo ""
        fi

        echo "Recommendations:"
        echo "1. Run 'sudo apt upgrade' to apply the updates."
        echo "2. Run 'sudo apt dist-upgrade' for a full upgrade (if necessary)."
        echo "3. Run 'sudo apt autoremove' to clean up unnecessary packages after upgrading."
        if [[ ${#kernel_updates[@]} -gt 0 ]]; then
            echo "4. Kernel updates detected. Reboot is recommended after applying updates."
        fi
    else
        echo "Your system is up to date. No updates are available."
    fi

    echo ""
}

# Generate system health report
generate_health_report() {
    echo "================================="
    echo "        System Health Report      "
    echo "        $(date)"
    echo "================================="
    check_disk_space
    check_memory_usage
    check_running_services "$@"
    check_system_updates
    echo "================================="
    echo "Health check completed."
}

# Execute the main function with all arguments
generate_health_report "$@"
