#!/bin/bash

# Anagram Game - File Logger Monitor
# This script finds and tails the app's debug log file

echo "🔍 Searching for Anagram Game log files..."

# Get the list of booted simulators
SIMULATORS=$(xcrun simctl list devices | grep "(Booted)" | grep -E "iPhone|iPad")

if [ -z "$SIMULATORS" ]; then
    echo "❌ No booted simulators found. Please start a simulator first."
    exit 1
fi

echo "📱 Found booted simulators:"
echo "$SIMULATORS"

# Find the log file in any booted simulator
LOG_FILE=""
for sim_line in $SIMULATORS; do
    # Extract UUID from the line
    UUID=$(echo "$sim_line" | grep -o '[A-F0-9-]\{36\}')
    if [ ! -z "$UUID" ]; then
        echo "🔍 Checking simulator $UUID..."
        
        # Search for the log file in this simulator
        SEARCH_PATH="$HOME/Library/Developer/CoreSimulator/Devices/$UUID/data/Containers/Data/Application"
        
        if [ -d "$SEARCH_PATH" ]; then
            FOUND_LOG=$(find "$SEARCH_PATH" -name "anagram-debug.log" 2>/dev/null | head -1)
            if [ ! -z "$FOUND_LOG" ]; then
                LOG_FILE="$FOUND_LOG"
                echo "✅ Found log file: $LOG_FILE"
                break
            fi
        fi
    fi
done

if [ -z "$LOG_FILE" ]; then
    echo "❌ Could not find anagram-debug.log file."
    echo "💡 Make sure the app has been launched at least once to create the log file."
    echo ""
    echo "🔍 Manual search command:"
    echo "find ~/Library/Developer/CoreSimulator -name 'anagram-debug.log' 2>/dev/null"
    exit 1
fi

echo ""
echo "📋 Log file location: $LOG_FILE"
echo "🔄 Starting live tail (press Ctrl+C to stop)..."
echo "=" | tr '=' '='
echo ""

# Tail the log file
tail -f "$LOG_FILE"