#!/bin/bash

# Safe server management script for Anagram Game
# Reads port from .env file and only manages processes on that specific port

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Function to get port from .env file
get_port() {
    if [ -f "$ENV_FILE" ]; then
        PORT=$(grep "^PORT=" "$ENV_FILE" | cut -d '=' -f2 | tr -d ' ')
        if [ -z "$PORT" ]; then
            PORT=3000  # Default fallback
        fi
    else
        PORT=3000  # Default if no .env file
    fi
    echo $PORT
}

# Function to find process using our port
find_process_on_port() {
    local port=$1
    lsof -ti tcp:$port 2>/dev/null
}

# Function to safely kill server
kill_server() {
    local port=$(get_port)
    echo "🔍 Looking for processes on port $port..."
    
    local pids=$(find_process_on_port $port)
    
    if [ -z "$pids" ]; then
        echo "✅ No processes found on port $port"
        return 0
    fi
    
    echo "🛑 Found processes on port $port: $pids"
    
    for pid in $pids; do
        # Get process info to verify it's our server
        local process_info=$(ps -p $pid -o comm= 2>/dev/null)
        echo "   Process $pid: $process_info"
        
        # Kill the process
        kill $pid 2>/dev/null && echo "   ✅ Killed process $pid" || echo "   ❌ Failed to kill process $pid"
    done
    
    # Wait a moment and check if any processes are still running
    sleep 1
    local remaining_pids=$(find_process_on_port $port)
    if [ ! -z "$remaining_pids" ]; then
        echo "⚠️  Some processes still running, force killing..."
        for pid in $remaining_pids; do
            kill -9 $pid 2>/dev/null && echo "   ✅ Force killed process $pid"
        done
    fi
}

# Function to start server
start_server() {
    local port=$(get_port)
    echo "🚀 Starting Anagram Game Server on port $port..."
    
    # Check if port is already in use
    if [ ! -z "$(find_process_on_port $port)" ]; then
        echo "❌ Port $port is already in use. Run './manage-server.sh stop' first."
        return 1
    fi
    
    # Start the server with logging
    cd "$SCRIPT_DIR"
    node server.js > server_output.log 2>&1 &
    local server_pid=$!
    
    echo "📝 Server started with PID $server_pid"
    echo "📋 Logs: tail -f $SCRIPT_DIR/server_output.log"
    echo "🌐 Status: http://localhost:$port/api/status"
}

# Function to show server status
status_server() {
    local port=$(get_port)
    echo "📊 Anagram Game Server Status (Port $port):"
    
    local pids=$(find_process_on_port $port)
    if [ -z "$pids" ]; then
        echo "   Status: ❌ Not running"
    else
        echo "   Status: ✅ Running"
        for pid in $pids; do
            local process_info=$(ps -p $pid -o pid,comm,etime,cpu,rss 2>/dev/null)
            echo "   $process_info"
        done
        echo "   🌐 Available at: http://localhost:$port/api/status"
    fi
}

# Function to restart server
restart_server() {
    echo "🔄 Restarting Anagram Game Server..."
    kill_server
    sleep 2
    start_server
}

# Function to show logs
show_logs() {
    local log_file="$SCRIPT_DIR/server_output.log"
    if [ -f "$log_file" ]; then
        echo "📋 Server logs (last 50 lines):"
        tail -50 "$log_file"
        echo ""
        echo "💡 For live logs: tail -f $log_file"
    else
        echo "❌ No log file found at $log_file"
    fi
}

# Main script logic
case "$1" in
    "start")
        start_server
        ;;
    "stop")
        kill_server
        ;;
    "restart")
        restart_server
        ;;
    "status")
        status_server
        ;;
    "logs")
        show_logs
        ;;
    *)
        echo "🎮 Anagram Game Server Management"
        echo ""
        echo "Usage: $0 {start|stop|restart|status|logs}"
        echo ""
        echo "Commands:"
        echo "  start   - Start the server"
        echo "  stop    - Stop the server (safe, port-specific)"
        echo "  restart - Restart the server"
        echo "  status  - Show server status"
        echo "  logs    - Show recent server logs"
        echo ""
        echo "Configuration:"
        echo "  Port: $(get_port) (from .env file)"
        echo "  Logs: $SCRIPT_DIR/server_output.log"
        ;;
esac