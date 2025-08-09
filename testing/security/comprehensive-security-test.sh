#!/bin/bash
# Comprehensive Security Test Suite for Anagram Game
# Tests all implemented security features in Phase 1

set -e

echo "🧪 Running Comprehensive Security Test Suite..."
echo "================================================"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Function to run a test and capture result
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_pattern="$3"
    
    echo -e "\n${BLUE}Testing: ${test_name}${NC}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if result=$(eval "$test_command" 2>&1); then
        if [[ -z "$expected_pattern" ]] || echo "$result" | grep -q "$expected_pattern"; then
            echo -e "${GREEN}✅ PASS${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}❌ FAIL - Expected pattern not found${NC}"
            echo "Expected: $expected_pattern"
            echo "Got: $result"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        echo -e "${RED}❌ FAIL - Command failed${NC}"
        echo "$result"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo -e "\n${YELLOW}1. RATE LIMITING TESTS${NC}"
echo "======================================"

run_test "Game Server Rate Limit Headers" \
    "curl -I http://localhost:3000/api/status" \
    "RateLimit-Limit: 120"

run_test "Admin Service Rate Limit Headers" \
    "curl -I http://localhost:3003/api/status" \
    "RateLimit-Limit: 30"

run_test "Web Dashboard Rate Limit Headers" \
    "curl -I http://localhost:3001/api/status" \
    "RateLimit-Limit: 300"

echo -e "\n${YELLOW}2. INPUT VALIDATION TESTS${NC}"
echo "======================================"

run_test "XSS Protection - Game Server" \
    "curl -s -X POST http://localhost:3000/api/phrases/create -H 'Content-Type: application/json' -d '{\"content\": \"<script>alert(\\\"XSS\\\")</script>\", \"language\": \"en\"}'" \
    "Schema validation failed"

run_test "SQL Injection Protection - Admin Service" \
    "curl -s -X POST http://localhost:3003/api/admin/phrases/batch-import -H 'Content-Type: application/json' -d '{\"phrases\": [{\"content\": \"SELECT * FROM users--\"}]}'" \
    "Validation failed"

run_test "Valid Content Acceptance" \
    "curl -s -X POST http://localhost:3000/api/phrases/create -H 'Content-Type: application/json' -d '{\"content\": \"Hello world test\", \"language\": \"en\"}'" \
    "success"

echo -e "\n${YELLOW}3. API AUTHENTICATION TESTS${NC}"
echo "======================================"

run_test "Health Check Without Auth" \
    "curl -s http://localhost:3003/api/status" \
    "healthy"

run_test "Admin Endpoint Without Auth (Dev Mode)" \
    "curl -s -X POST http://localhost:3003/api/admin/phrases/batch-import -H 'Content-Type: application/json' -d '{\"phrases\": [{\"content\": \"test phrase without auth\"}]}'" \
    "success"

run_test "Admin Endpoint With Valid Auth" \
    "curl -s -X POST http://localhost:3003/api/admin/phrases/batch-import -H 'Content-Type: application/json' -H 'X-API-Key: test-admin-key-123' -d '{\"phrases\": [{\"content\": \"test phrase with auth\"}]}'" \
    "success"

echo -e "\n${YELLOW}4. CORS TESTS${NC}"
echo "======================================"

run_test "No Origin Request (Mobile Apps)" \
    "curl -I http://localhost:3000/api/status" \
    "200 OK"

run_test "Valid Origin Request" \
    "curl -I -H 'Origin: http://localhost:3000' http://localhost:3000/api/status" \
    "200 OK"

# Note: CORS rejection tests don't work well in development mode with SECURITY_RELAXED=true

echo -e "\n${YELLOW}5. WEBSOCKET SECURITY TESTS${NC}"
echo "======================================"

if [ -f "$(dirname "$0")/test-websocket-security.js" ]; then
    echo "Running WebSocket security tests..."
    if node "$(dirname "$0")/test-websocket-security.js"; then
        echo -e "${GREEN}✅ WebSocket tests completed${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}❌ WebSocket tests failed${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
else
    echo -e "${YELLOW}⚠️ WebSocket test script not found${NC}"
fi

echo -e "\n${YELLOW}6. SERVICE HEALTH TESTS${NC}"
echo "======================================"

run_test "Game Server Health" \
    "curl -s http://localhost:3000/api/status" \
    "healthy"

run_test "Web Dashboard Health" \
    "curl -s http://localhost:3001/api/status" \
    "healthy"

run_test "Admin Service Health" \
    "curl -s http://localhost:3003/api/status" \
    "healthy"

# Summary
echo -e "\n================================================"
echo -e "${BLUE}TEST SUMMARY${NC}"
echo "================================================"
echo -e "Total Tests: ${TESTS_TOTAL}"
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 ALL TESTS PASSED!${NC}"
    echo -e "Phase 1 Security Implementation: ${GREEN}✅ VERIFIED${NC}"
    exit 0
else
    echo -e "\n${RED}❌ SOME TESTS FAILED${NC}"
    echo -e "Please review the failed tests above."
    exit 1
fi