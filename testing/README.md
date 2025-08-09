# Wordshelf Testing Suite

Centralized testing resources for the Wordshelf multiplayer word game.

## Directory Structure

```
testing/
├── api/                    # API endpoint tests
│   ├── test_api_suite.js
│   ├── test_database.js
│   ├── test_database_phrase_structure.js
│   └── test_websocket_data_structure.js
│
├── integration/            # End-to-end integration tests
│   ├── test_comprehensive_suite.js
│   ├── test_phase3_features.js
│   ├── test_phase4_enhanced_creation.js
│   ├── test_phase4_global_phrases.js
│   ├── test_hint_system.js
│   ├── test_language_functionality.js
│   ├── test_phrase_approval.js
│   └── infrastructure.test.ts
│
├── performance/            # Performance and algorithm tests
│   ├── test_difficulty_filtering.js
│   ├── test_difficulty_scoring.js
│   ├── test_scoring_system.js
│   └── test-difficulty-algorithm.js
│
├── security/              # Security testing scripts
│   ├── comprehensive-security-test.sh
│   ├── production-security-test.sh
│   └── test-websocket-security.js
│
├── scripts/               # Test runners and utilities
│   ├── run_tests.sh
│   ├── test_runner_all.js
│   └── quick_test.sh
│
├── data/                  # Test data and fixtures
│   ├── test-gaming-phrases.json
│   ├── test-gaming-3-phrases.json
│   └── test-data.html
│
├── ios/                   # iOS-specific test utilities
│   └── (iOS testing utilities - see CLAUDE.md for iOS testing procedures)
│
└── docs/                  # Testing documentation
    ├── TEST_SUITE_SUMMARY.md
    ├── test_coverage_analysis.md
    └── WEB_SYSTEM_TEST_RESULTS.md
```

## Quick Start

### Run All Tests
```bash
cd testing/scripts
./run_tests.sh
```

### Run Specific Test Categories
```bash
# API Tests
node testing/api/test_api_suite.js

# Integration Tests
node testing/integration/test_comprehensive_suite.js

# Infrastructure Tests (TypeScript)
cd testing/integration && npx ts-node infrastructure.test.ts

# Security Tests
./testing/security/comprehensive-security-test.sh

# Performance Tests
node testing/performance/test_scoring_system.js
```

### Quick Health Check
```bash
./testing/scripts/quick_test.sh
```

## Test Categories

### 1. API Tests (`/api`)
- **test_api_suite.js** - Complete API endpoint testing (42 tests)
- **test_database.js** - Database connection and query tests
- **test_database_phrase_structure.js** - Phrase data structure validation
- **test_websocket_data_structure.js** - WebSocket event validation

### 2. Integration Tests (`/integration`)
- **test_comprehensive_suite.js** - Full system integration tests
- **test_phase3_features.js** - Phase 3 migration tests
- **test_phase4_enhanced_creation.js** - Enhanced phrase creation
- **test_phase4_global_phrases.js** - Global phrase system
- **test_hint_system.js** - Hint functionality
- **test_language_functionality.js** - Multi-language support
- **test_phrase_approval.js** - Phrase moderation system
- **infrastructure.test.ts** - AWS infrastructure testing (TypeScript)

### 3. Performance Tests (`/performance`)
- **test_difficulty_filtering.js** - Difficulty algorithm performance
- **test_difficulty_scoring.js** - Scoring system benchmarks
- **test_scoring_system.js** - Player scoring calculations
- **test-difficulty-algorithm.js** - Difficulty algorithm validation

### 4. Security Tests (`/security`)
- **comprehensive-security-test.sh** - Full security audit
- **production-security-test.sh** - Production environment security
- **test-websocket-security.js** - WebSocket security validation

## Environment Setup

### Local Development
```bash
# Start services
docker-compose -f docker-compose.services.yml up -d

# Set environment
export TEST_ENV=local
export API_URL=http://192.168.1.188:3000
```

### Production Testing
```bash
export TEST_ENV=production
export API_URL=https://anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com
```

## Common Test Commands

### Check Service Health
```bash
curl -s http://192.168.1.188:3000/api/status | jq .
```

### Monitor Test Logs
```bash
docker-compose -f docker-compose.services.yml logs -f game-server | grep TEST
```

### Database Queries for Testing
```sql
-- Get test players
SELECT id, name FROM players WHERE name LIKE 'Test%';

-- Check test phrases
SELECT * FROM phrases WHERE content LIKE 'test%' ORDER BY created_at DESC;

-- Clean test data
DELETE FROM phrases WHERE content LIKE 'test%';
DELETE FROM players WHERE name LIKE 'Test%';
```

## Writing New Tests

### Test Template
```javascript
// test_example.js
const assert = require('assert');
const axios = require('axios');

const API_URL = process.env.API_URL || 'http://192.168.1.188:3000';

describe('Example Test Suite', () => {
    it('should test something', async () => {
        const response = await axios.get(`${API_URL}/api/status`);
        assert.equal(response.data.status, 'healthy');
    });
});
```

### Adding to Test Runner
1. Place test file in appropriate category folder
2. Update `scripts/test_runner_all.js` to include new test
3. Document in this README

## Test Results

### Current Coverage
- **API Endpoints**: 100% (42/42 tests passing)
- **WebSocket Events**: 85% coverage
- **Security**: All critical paths tested
- **Performance**: Benchmarks established
- **Infrastructure**: AWS deployment testing (TypeScript)

### Known Issues
- See `docs/test_coverage_analysis.md` for gaps
- Check GitHub Issues for test-related bugs

## CI/CD Integration

### GitHub Actions
- `.github/workflows/test.yml` - PR tests
- `.github/workflows/production-tests.yml` - Production validation

### Pre-commit Testing
```bash
# Add to .git/hooks/pre-commit
./testing/scripts/quick_test.sh
```

## Troubleshooting

### Common Issues

#### Tests Failing with Connection Errors
```bash
# Check services are running
docker-compose -f docker-compose.services.yml ps

# Restart services
docker-compose -f docker-compose.services.yml restart
```

#### Rate Limiting During Tests
```bash
# Disable rate limits for testing
export SKIP_RATE_LIMITS=true
docker-compose -f docker-compose.services.yml up -d
```

#### Database State Issues
```bash
# Reset test database
docker-compose -f docker-compose.services.yml exec postgres psql -U postgres -d anagram_game < testing/data/reset_test_data.sql
```

## Related Documentation

- **Main Testing Guide**: `/docs/testing-guide.md`
- **Security Testing**: `/security-testing/README.md`
- **iOS Testing**: `/docs/device-user-association-guide.md`
- **API Documentation**: `/docs/api-documentation.md`

## Contributing

1. Write tests for new features
2. Ensure all tests pass before PR
3. Update this README when adding test files
4. Document test dependencies and setup

---

Last Updated: 2025-08-09