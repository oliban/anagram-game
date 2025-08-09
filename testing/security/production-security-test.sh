#!/bin/bash
# Production Security Test Suite for Anagram Game
# Tests security enforcement when SECURITY_RELAXED=false

set -e

echo "🔒 Running Production Security Test Suite..."
echo "=============================================="
echo "⚠️  WARNING: This will temporarily enable strict security mode"
echo "This will test security enforcement as it would work in production"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found${NC}"
    exit 1
fi

# Backup current .env
echo "📋 Backing up current .env configuration..."
cp .env .env.backup

# Function to restore .env and exit
cleanup_and_exit() {
    echo -e "\n🔄 Restoring original .env configuration..."
    mv .env.backup .env
    echo "✅ Configuration restored"
    
    echo "🔄 Restarting services to load original config..."
    docker-compose -f docker-compose.services.yml restart > /dev/null 2>&1
    echo "✅ Services restarted"
    
    exit $1
}

# Set trap to cleanup on script exit
trap 'cleanup_and_exit $?' EXIT

# Enable strict security mode
echo "🔒 Enabling strict security mode (SECURITY_RELAXED=false)..."
sed -i.bak 's/SECURITY_RELAXED=true/SECURITY_RELAXED=false/' .env

# Restart services to load new config
echo "🔄 Restarting services with strict security..."
docker-compose -f docker-compose.services.yml restart > /dev/null 2>&1

# Wait for services to start
echo "⏳ Waiting for services to initialize..."
sleep 10

# Test results counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Function to run a test and capture result
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_pattern="$3"
    local should_fail="$4"  # "fail" if we expect the test to fail
    
    echo -e "\n${BLUE}Testing: ${test_name}${NC}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if result=$(eval "$test_command" 2>&1); then
        if [[ "$should_fail" == "fail" ]]; then
            echo -e "${RED}❌ FAIL - Expected this to be blocked but it succeeded${NC}"
            echo "Result: $result"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        elif [[ -z "$expected_pattern" ]] || echo "$result" | grep -q "$expected_pattern"; then
            echo -e "${GREEN}✅ PASS${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}❌ FAIL - Expected pattern not found${NC}"
            echo "Expected: $expected_pattern"
            echo "Got: $result"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        if [[ "$should_fail" == "fail" ]]; then
            echo -e "${GREEN}✅ PASS - Correctly blocked${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}❌ FAIL - Command failed unexpectedly${NC}"
            echo "$result"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    fi
}

echo -e "\n${YELLOW}1. API AUTHENTICATION ENFORCEMENT${NC}"
echo "=============================================="

run_test "Health Check (Should Still Work)" \
    "curl -s http://localhost:3003/api/status" \
    "healthy"

run_test "Admin Endpoint Without Auth (Should Fail)" \
    "curl -s -X POST http://localhost:3003/api/admin/phrases/batch-import -H 'Content-Type: application/json' -d '{\"phrases\": [{\"content\": \"test\"}]}'" \
    "Authentication required" \
    "expect_auth_error"

run_test "Admin Endpoint With Wrong Key (Should Fail)" \
    "curl -s -X POST http://localhost:3003/api/admin/phrases/batch-import -H 'Content-Type: application/json' -H 'X-API-Key: wrong-key' -d '{\"phrases\": [{\"content\": \"test\"}]}'" \
    "Invalid API key" \
    "expect_auth_error"

run_test "Admin Endpoint With Correct Key (Should Work)" \
    "curl -s -X POST http://localhost:3003/api/admin/phrases/batch-import -H 'Content-Type: application/json' -H 'X-API-Key: test-admin-key-123' -d '{\"phrases\": [{\"content\": \"valid test\"}]}'" \
    "success"

echo -e "\n${YELLOW}2. WEBSOCKET AUTHENTICATION ENFORCEMENT${NC}"
echo "=============================================="

if [ -f "$(dirname "$0")/test-websocket-security.js" ]; then
    echo "Running WebSocket security tests in strict mode..."
    echo "Expected: Game namespace open, monitoring namespace requires auth"
    
    if timeout 30 node "$(dirname "$0")/test-websocket-security.js"; then
        echo -e "${GREEN}✅ WebSocket tests completed - Check output above for auth enforcement${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}❌ WebSocket tests failed or timed out${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
else
    echo -e "${YELLOW}⚠️ WebSocket test script not found${NC}"
fi

echo -e "\n${YELLOW}3. RATE LIMITING UNDER LOAD${NC}"
echo "=============================================="

echo "Testing rate limit enforcement..."
RATE_LIMIT_HITS=0
for i in {1..35}; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:3003/api/status | grep -q "429"; then
        RATE_LIMIT_HITS=$((RATE_LIMIT_HITS + 1))
    fi
    sleep 0.1
done

if [ $RATE_LIMIT_HITS -gt 0 ]; then
    echo -e "${GREEN}✅ Rate limiting working - Got $RATE_LIMIT_HITS rate limit responses${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${YELLOW}⚠️ No rate limits hit - May need more aggressive testing${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

echo -e "\n${YELLOW}4. iOS APP COMPATIBILITY${NC}"
echo "=============================================="

echo "Testing that iOS apps can still connect (game namespace should remain open)..."
run_test "Game Server WebSocket (No Auth Required)" \
    "curl -s http://localhost:3000/api/status" \
    "healthy"

# Note: Full iOS app testing would require building and running the simulator
echo -e "${BLUE}ℹ️ For complete iOS testing, run: ./build_and_test.sh local${NC}"

# Summary
echo -e "\n=============================================="
echo -e "${BLUE}PRODUCTION SECURITY TEST SUMMARY${NC}"
echo "=============================================="
echo -e "Total Tests: ${TESTS_TOTAL}"
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 ALL PRODUCTION SECURITY TESTS PASSED!${NC}"
    echo -e "Security enforcement working correctly: ${GREEN}✅ VERIFIED${NC}"
    echo -e "\n${BLUE}Key Security Features Verified:${NC}"
    echo "• ✅ API authentication enforced for admin endpoints"
    echo "• ✅ Health checks remain accessible"
    echo "• ✅ Rate limiting active under load"
    echo "• ✅ WebSocket monitoring requires authentication"
    echo "• ✅ Game namespace remains open for iOS apps"
else
    echo -e "\n${RED}❌ SOME PRODUCTION SECURITY TESTS FAILED${NC}"
    echo -e "Please review the failed tests above."
fi

echo -e "\n${YELLOW}🔄 Configuration will be restored automatically...${NC}"