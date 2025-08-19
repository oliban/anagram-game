#!/bin/bash

# Database Health Monitoring Script
# Monitors database health, backups, and critical metrics
# Can be run manually or via cron for continuous monitoring

set -e

PI_IP="${1:-192.168.1.222}"
PI_USER="pi"
ALERT_THRESHOLD_HOURS=26  # Alert if daily backup is older than 26 hours
CRITICAL_THRESHOLD_HOURS=50  # Critical if daily backup is older than 50 hours

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Alert flags
ALERTS=()
CRITICALS=()

echo -e "${BLUE}🔍 Database Health Monitoring${NC}"
echo -e "${BLUE}Target: ${PI_USER}@${PI_IP}${NC}"
echo "==============================="

# Function to add alert
add_alert() {
    local message="$1"
    ALERTS+=("$message")
    echo -e "${YELLOW}⚠️  ALERT: $message${NC}"
}

# Function to add critical alert
add_critical() {
    local message="$1"
    CRITICALS+=("$message")
    echo -e "${RED}🚨 CRITICAL: $message${NC}"
}

# Function to test SSH connection
test_connection() {
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes ${PI_USER}@${PI_IP} "echo 'Connected'" > /dev/null 2>&1; then
        add_critical "Cannot connect to Pi at ${PI_IP}"
        return 1
    fi
    return 0
}

# Function to check Docker services
check_docker_services() {
    echo -e "${BLUE}🐳 Docker Services${NC}"
    echo "-------------------"
    
    # Check if Docker is running
    if ! ssh ${PI_USER}@${PI_IP} "docker ps > /dev/null 2>&1"; then
        add_critical "Docker daemon not running"
        return 1
    fi
    
    # Check database container
    DB_STATUS=$(ssh ${PI_USER}@${PI_IP} "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep anagram-db" 2>/dev/null || echo "")
    if [[ $DB_STATUS == *"Up"* ]]; then
        echo -e "✅ Database: Running"
    else
        add_critical "Database container not running"
    fi
    
    # Check game server container
    SERVER_STATUS=$(ssh ${PI_USER}@${PI_IP} "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep game-server" 2>/dev/null || echo "")
    if [[ $SERVER_STATUS == *"Up"* ]]; then
        echo -e "✅ Game Server: Running"
    else
        add_alert "Game server container not running"
    fi
    
    echo ""
}

# Function to check database connectivity and completeness
check_database_health() {
    echo -e "${BLUE}🗄️  Database Health${NC}"
    echo "--------------------"
    
    # Test basic connectivity
    local db_test=$(ssh ${PI_USER}@${PI_IP} "docker exec anagram-db psql -U postgres -d anagram_game -c 'SELECT 1;' -t 2>/dev/null" || echo "FAILED")
    if [[ "$db_test" != *"1"* ]]; then
        add_critical "Database not responding to queries"
        return 1
    fi
    echo -e "✅ Database connectivity: OK"
    
    # Check table count
    local table_count=$(ssh ${PI_USER}@${PI_IP} "docker exec anagram-db psql -U postgres -d anagram_game -c \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';\" -t 2>/dev/null" | tr -d ' ' || echo "0")
    if [[ $table_count -ge 10 ]]; then
        echo -e "✅ Database tables: ${table_count}/10+"
    elif [[ $table_count -ge 7 ]]; then
        add_alert "Database has only ${table_count} tables (expected 10+)"
    else
        add_critical "Database has only ${table_count} tables (expected 10+)"
    fi
    
    # Check critical tables
    local critical_tables=("phrases" "players" "emoji_catalog")
    for table in "${critical_tables[@]}"; do
        local exists=$(ssh ${PI_USER}@${PI_IP} "docker exec anagram-db psql -U postgres -d anagram_game -c \"SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name='$table');\" -t 2>/dev/null" | tr -d ' ' || echo "f")
        if [[ "$exists" == "t" ]]; then
            echo -e "✅ Table '$table': Present"
        else
            add_critical "Critical table '$table' missing"
        fi
    done
    
    # Check data counts
    local phrase_count=$(ssh ${PI_USER}@${PI_IP} "docker exec anagram-db psql -U postgres -d anagram_game -c 'SELECT COUNT(*) FROM phrases;' -t 2>/dev/null" | tr -d ' ' || echo "0")
    local player_count=$(ssh ${PI_USER}@${PI_IP} "docker exec anagram-db psql -U postgres -d anagram_game -c 'SELECT COUNT(*) FROM players;' -t 2>/dev/null" | tr -d ' ' || echo "0")
    local emoji_count=$(ssh ${PI_USER}@${PI_IP} "docker exec anagram-db psql -U postgres -d anagram_game -c 'SELECT COUNT(*) FROM emoji_catalog;' -t 2>/dev/null" | tr -d ' ' || echo "0")
    
    echo -e "📊 Data counts:"
    echo -e "   Phrases: $phrase_count"
    echo -e "   Players: $player_count"
    echo -e "   Emojis: $emoji_count"
    
    # Alert on low data counts
    if [[ $phrase_count -lt 50 ]]; then
        add_alert "Low phrase count: $phrase_count (consider importing more)"
    fi
    
    if [[ $emoji_count -lt 50 ]]; then
        add_alert "Low emoji count: $emoji_count (expected ~53)"
    fi
    
    echo ""
}

# Function to check backup system health
check_backup_health() {
    echo -e "${BLUE}💾 Backup System Health${NC}"
    echo "-----------------------"
    
    # Check if backup directories exist
    local backup_dirs=$(ssh ${PI_USER}@${PI_IP} "ls -d ~/anagram-game/backups/{daily,weekly,monthly,emergency} 2>/dev/null | wc -l" || echo "0")
    if [[ $backup_dirs -eq 4 ]]; then
        echo -e "✅ Backup directories: All present"
    else
        add_alert "Backup directories incomplete ($backup_dirs/4)"
    fi
    
    # Check latest daily backup
    local latest_daily=$(ssh ${PI_USER}@${PI_IP} "ls -t ~/anagram-game/backups/daily/*.gz 2>/dev/null | head -1" || echo "")
    if [[ -n "$latest_daily" ]]; then
        local backup_age_sec=$(ssh ${PI_USER}@${PI_IP} "echo \$(( \$(date +%s) - \$(stat -c %Y \"$latest_daily\") ))")
        local backup_age_hours=$((backup_age_sec / 3600))
        
        echo -e "📅 Latest daily backup: $(basename "$latest_daily") (${backup_age_hours}h ago)"
        
        if [[ $backup_age_hours -gt $CRITICAL_THRESHOLD_HOURS ]]; then
            add_critical "Daily backup is ${backup_age_hours} hours old (critical threshold: ${CRITICAL_THRESHOLD_HOURS}h)"
        elif [[ $backup_age_hours -gt $ALERT_THRESHOLD_HOURS ]]; then
            add_alert "Daily backup is ${backup_age_hours} hours old (alert threshold: ${ALERT_THRESHOLD_HOURS}h)"
        else
            echo -e "✅ Daily backup: Fresh (${backup_age_hours}h ago)"
        fi
    else
        add_critical "No daily backups found"
    fi
    
    # Check backup counts
    local daily_count=$(ssh ${PI_USER}@${PI_IP} "ls ~/anagram-game/backups/daily/*.gz 2>/dev/null | wc -l" || echo "0")
    local weekly_count=$(ssh ${PI_USER}@${PI_IP} "ls ~/anagram-game/backups/weekly/*.gz 2>/dev/null | wc -l" || echo "0")
    local monthly_count=$(ssh ${PI_USER}@${PI_IP} "ls ~/anagram-game/backups/monthly/*.gz 2>/dev/null | wc -l" || echo "0")
    
    echo -e "📊 Backup counts:"
    echo -e "   Daily: $daily_count (target: 7)"
    echo -e "   Weekly: $weekly_count (target: 4)"
    echo -e "   Monthly: $monthly_count (target: up to 12)"
    
    # Check cron jobs
    local cron_jobs=$(ssh ${PI_USER}@${PI_IP} "crontab -l 2>/dev/null | grep -c anagram-game" || echo "0")
    if [[ $cron_jobs -ge 3 ]]; then
        echo -e "✅ Backup cron jobs: $cron_jobs configured"
    else
        add_alert "Backup cron jobs: only $cron_jobs found (expected 3)"
    fi
    
    # Check disk usage
    local disk_usage=$(ssh ${PI_USER}@${PI_IP} "du -sh ~/anagram-game/backups 2>/dev/null | cut -f1" || echo "Unknown")
    local free_space=$(ssh ${PI_USER}@${PI_IP} "df -h ~ | awk 'NR==2 {print \$4}'" || echo "Unknown")
    
    echo -e "💾 Storage:"
    echo -e "   Backup size: $disk_usage"
    echo -e "   Free space: $free_space"
    
    echo ""
}

# Function to check API health
check_api_health() {
    echo -e "${BLUE}🌐 API Health${NC}"
    echo "---------------"
    
    # Check API status endpoint
    local api_status=$(ssh ${PI_USER}@${PI_IP} "curl -s --max-time 10 http://localhost:3000/api/status 2>/dev/null | grep -o '\"status\":\"[^\"]*\"' | cut -d'\"' -f4" || echo "unreachable")
    
    if [[ "$api_status" == "healthy" ]]; then
        echo -e "✅ API Status: Healthy"
    else
        add_critical "API Status: $api_status"
    fi
    
    # Test phrase retrieval
    local phrase_test=$(ssh ${PI_USER}@${PI_IP} "curl -s --max-time 10 http://localhost:3000/api/phrases/global?limit=1 2>/dev/null | grep -c '\"phrases\"'" || echo "0")
    if [[ "$phrase_test" == "1" ]]; then
        echo -e "✅ Phrase API: Working"
    else
        add_alert "Phrase API: Not responding correctly"
    fi
    
    # Check recent errors in logs
    local error_count=$(ssh ${PI_USER}@${PI_IP} "docker logs anagram-game-server --tail 100 2>/dev/null | grep -i error | wc -l" || echo "0")
    if [[ $error_count -eq 0 ]]; then
        echo -e "✅ Recent errors: None"
    elif [[ $error_count -lt 5 ]]; then
        echo -e "⚠️  Recent errors: $error_count (review logs)"
    else
        add_alert "High error count in logs: $error_count"
    fi
    
    echo ""
}

# Function to check system resources
check_system_resources() {
    echo -e "${BLUE}⚡ System Resources${NC}"
    echo "--------------------"
    
    # Memory usage
    local memory_info=$(ssh ${PI_USER}@${PI_IP} "free | awk 'NR==2{printf \"%.1f%% (%s/%s)\", \$3*100/\$2, \$3, \$2}'")
    echo -e "🧠 Memory usage: $memory_info"
    
    # Disk usage for home directory
    local disk_info=$(ssh ${PI_USER}@${PI_IP} "df -h ~ | awk 'NR==2{printf \"%s used, %s free (%s)\", \$3, \$4, \$5}'")
    echo -e "💾 Disk usage: $disk_info"
    
    # Docker volume usage
    local volume_size=$(ssh ${PI_USER}@${PI_IP} "docker system df -v 2>/dev/null | grep anagram-game_postgres_data | awk '{print \$3}'" || echo "Unknown")
    echo -e "🗄️  Database volume: $volume_size"
    
    # Check high disk usage
    local disk_percent=$(ssh ${PI_USER}@${PI_IP} "df ~ | awk 'NR==2{print \$5}' | sed 's/%//'" || echo "0")
    if [[ $disk_percent -gt 90 ]]; then
        add_critical "Disk usage critical: ${disk_percent}%"
    elif [[ $disk_percent -gt 80 ]]; then
        add_alert "Disk usage high: ${disk_percent}%"
    fi
    
    echo ""
}

# Function to generate summary report
generate_summary() {
    echo -e "${BLUE}📊 HEALTH SUMMARY${NC}"
    echo "=================="
    
    local total_issues=$((${#ALERTS[@]} + ${#CRITICALS[@]}))
    
    if [[ $total_issues -eq 0 ]]; then
        echo -e "${GREEN}🎉 All systems healthy!${NC}"
        echo -e "${GREEN}✅ No issues detected${NC}"
    else
        echo -e "${YELLOW}⚠️  Found $total_issues issue(s):${NC}"
        
        if [[ ${#CRITICALS[@]} -gt 0 ]]; then
            echo -e "${RED}🚨 CRITICAL ISSUES (${#CRITICALS[@]}):${NC}"
            for critical in "${CRITICALS[@]}"; do
                echo -e "${RED}   • $critical${NC}"
            done
        fi
        
        if [[ ${#ALERTS[@]} -gt 0 ]]; then
            echo -e "${YELLOW}⚠️  ALERTS (${#ALERTS[@]}):${NC}"
            for alert in "${ALERTS[@]}"; do
                echo -e "${YELLOW}   • $alert${NC}"
            done
        fi
    fi
    
    echo ""
    echo -e "${BLUE}📅 Next actions:${NC}"
    if [[ ${#CRITICALS[@]} -gt 0 ]]; then
        echo -e "${RED}   1. Address CRITICAL issues immediately${NC}"
        echo -e "   2. Check DATABASE_RECOVERY_PROCEDURES.md for guidance"
        echo -e "   3. Consider creating emergency backup if database is accessible"
    elif [[ ${#ALERTS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}   1. Review and address alerts during maintenance window${NC}"
        echo -e "   2. Monitor for pattern of increasing issues"
    else
        echo -e "${GREEN}   1. Continue regular monitoring${NC}"
        echo -e "   2. Next check in 24 hours or as scheduled"
    fi
    
    echo ""
    echo -e "${BLUE}🔧 Useful commands:${NC}"
    echo "   • Manual backup: bash Scripts/backup-database.sh ${PI_IP}"
    echo "   • Check completeness: bash Scripts/check-database-completeness.sh ${PI_IP}"  
    echo "   • View logs: ssh ${PI_USER}@${PI_IP} 'docker logs anagram-game-server --tail 50'"
    echo "   • Restore schema: bash Scripts/restore-database-schema.sh ${PI_IP}"
}

# Function to save monitoring log
save_monitoring_log() {
    local log_file="/tmp/database-health-$(date +%Y%m%d_%H%M%S).log"
    {
        echo "Database Health Monitoring Report"
        echo "Generated: $(date)"
        echo "Target: ${PI_USER}@${PI_IP}"
        echo "==============================="
        echo ""
        if [[ ${#CRITICALS[@]} -gt 0 ]]; then
            echo "CRITICAL ISSUES:"
            for critical in "${CRITICALS[@]}"; do
                echo "  • $critical"
            done
            echo ""
        fi
        if [[ ${#ALERTS[@]} -gt 0 ]]; then
            echo "ALERTS:"
            for alert in "${ALERTS[@]}"; do
                echo "  • $alert"
            done
            echo ""
        fi
        if [[ ${#CRITICALS[@]} -eq 0 && ${#ALERTS[@]} -eq 0 ]]; then
            echo "All systems healthy - no issues detected."
        fi
    } > "$log_file"
    
    echo -e "${BLUE}📝 Log saved: $log_file${NC}"
}

# Main execution
main() {
    if ! test_connection; then
        echo -e "${RED}❌ Cannot proceed with health check${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Connection established${NC}"
    echo ""
    
    check_docker_services
    check_database_health  
    check_backup_health
    check_api_health
    check_system_resources
    generate_summary
    save_monitoring_log
    
    # Exit with appropriate code
    if [[ ${#CRITICALS[@]} -gt 0 ]]; then
        exit 2  # Critical issues
    elif [[ ${#ALERTS[@]} -gt 0 ]]; then
        exit 1  # Warnings
    else
        exit 0  # All good
    fi
}

# Help function
show_help() {
    echo "Database Health Monitoring Script"
    echo ""
    echo "Usage: $0 [PI_IP] [options]"
    echo ""
    echo "Arguments:"
    echo "  PI_IP               IP address of the Pi (default: 192.168.1.222)"
    echo ""
    echo "Options:"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                  # Use default IP (192.168.1.222)"
    echo "  $0 192.168.1.100    # Use custom IP"
    echo ""
    echo "Exit codes:"
    echo "  0  - All systems healthy"
    echo "  1  - Warnings present"
    echo "  2  - Critical issues present"
    echo ""
    echo "This script can be run manually or scheduled via cron for continuous monitoring."
}

# Handle arguments
if [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Run the monitoring
main