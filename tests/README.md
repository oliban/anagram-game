# Test Structure

This directory contains all tests for the Anagram Game project, organized by component type.

## Directory Structure

```
tests/
├── shared/          # Tests for shared components (used by both iOS and server)
├── server/          # Server-specific tests (Node.js backend)
├── ios/             # iOS app-specific tests (SwiftUI/SpriteKit)
└── README.md        # This file
```

## Shared Tests (`tests/shared/`)

Tests for components shared between iOS client and Node.js server:

- **`test-difficulty-algorithm.js`** - Comprehensive tests for the letter repetition enhanced difficulty scoring algorithm

### Running Shared Tests

```bash
# From project root
node tests/shared/test-difficulty-algorithm.js
```

## Server Tests (`tests/server/`)

Server-specific tests are currently located in the `server/` directory with `test_*.js` naming.

## iOS Tests (`tests/ios/`)

iOS-specific tests are currently in Xcode test targets:
- `Anagram GameTests/` - Unit tests
- `Anagram GameUITests/` - UI tests

## Test Philosophy

- **Shared components** get tests in `tests/shared/` to ensure consistency across platforms
- **Platform-specific logic** gets tested in respective directories
- **Cross-platform consistency** is verified through shared algorithm tests

## Running All Tests

```bash
# Shared tests
node tests/shared/test-difficulty-algorithm.js

# Server tests (from server directory)
cd server && npm test

# iOS tests (via Xcode)
xcodebuild test -project "Anagram Game.xcodeproj" -scheme "Anagram Game" -destination 'platform=iOS Simulator,name=iPhone 15'
```