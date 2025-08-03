#!/bin/bash

# Anagram Game - File Logger Monitor
# This script finds and tails the app's debug log files

echo "🔍 Searching for Anagram Game log files..."

# Find all debug log files across all simulators
LOG_FILES=$(find ~/Library/Developer/CoreSimulator -name 'anagram-debug*.log' 2>/dev/null)

if [ -z "$LOG_FILES" ]; then
    echo "❌ Could not find any anagram-debug log files."
    echo "💡 Make sure the app has been launched at least once to create the log files."
    exit 1
fi

echo "📱 Found log files:"
echo "$LOG_FILES"
echo ""

# Get the most recently modified log file
LATEST_LOG=$(echo "$LOG_FILES" | xargs ls -t | head -1)

echo "📋 Using most recent log file: $LATEST_LOG"
echo "🔄 Starting live tail (press Ctrl+C to stop)..."
echo "=" | tr '=' '='
echo ""

# Tail the most recent log file
tail -f "$LATEST_LOG"