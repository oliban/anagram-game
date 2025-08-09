#!/bin/bash

# Run Tests Script
# Runs all test suites for the Anagram Game Server

echo "🧪 Anagram Game Server - Test Runner"
echo "===================================="

# Check if server is running
SERVER_URL="http://localhost:3000"
if ! curl -s "$SERVER_URL/api/status" > /dev/null; then
    echo "❌ Server is not running on port 3000"
    echo "Please start the server first: node server.js"
    exit 1
fi

echo "✅ Server is running"
echo ""

# Run API Test Suite
echo "🔍 Running API Test Suite..."
node test_api_suite.js
API_EXIT_CODE=$?

echo ""
echo "📋 Test Results Summary:"
if [ $API_EXIT_CODE -eq 0 ]; then
    echo "✅ API Test Suite: PASSED"
else
    echo "❌ API Test Suite: FAILED"
fi

echo ""
echo "🎯 Overall Result: $([ $API_EXIT_CODE -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED")"

exit $API_EXIT_CODE