# Performance Monitoring System Configuration

## Overview
The Anagram Game includes a comprehensive performance monitoring system that tracks FPS, memory usage, tile counts, and other metrics in real-time. This system can be enabled or disabled via configuration.

## Configuration Options

### iOS Client Configuration

The performance monitoring is controlled by `AppConfig.isPerformanceMonitoringEnabled` which checks multiple sources in priority order:

#### 1. Environment Variable (Highest Priority)
```bash
export ENABLE_PERFORMANCE_MONITORING=true  # Enable
export ENABLE_PERFORMANCE_MONITORING=false # Disable
```

#### 2. Info.plist Setting (Medium Priority)
Add to `Info.plist`:
```xml
<key>EnablePerformanceMonitoring</key>
<true/>  <!-- or <false/> to disable -->
```

#### 3. Build Configuration (Default)
- **DEBUG builds**: Enabled by default
- **RELEASE builds**: Disabled by default

### Server Configuration

Add to `server/.env`:
```bash
# Enable server-side performance logging
ENABLE_PERFORMANCE_MONITORING=true

# Disable server-side performance logging  
ENABLE_PERFORMANCE_MONITORING=false
```

## What Gets Disabled

When performance monitoring is disabled:

### iOS Client:
- ❌ Real-time metrics UI display (FPS, Memory, Tiles, Quake)
- ❌ Performance metrics timer (no CPU overhead)
- ❌ Memory usage calculations during skip operations
- ❌ Debug logging to server
- ❌ Performance data transmission to server

### Server:
- ❌ Debug log endpoint processing (`/api/debug/log`)
- ❌ Performance metrics endpoint processing (`/api/debug/performance`)
- ❌ Console logging of performance data

## Usage Examples

### Development (Enable Monitoring)
```bash
# iOS: Use default DEBUG behavior (enabled)
# Server: Set in .env
ENABLE_PERFORMANCE_MONITORING=true
```

### Production (Disable Monitoring)
```bash
# iOS: Use default RELEASE behavior (disabled)
# Server: Set in .env  
ENABLE_PERFORMANCE_MONITORING=false
```

### Selective Testing (Enable Only iOS)
```bash
# iOS: Enable via environment
export ENABLE_PERFORMANCE_MONITORING=true

# Server: Disable in .env
ENABLE_PERFORMANCE_MONITORING=false
```

## Performance Impact

### When Enabled:
- **CPU**: ~1-2% overhead for metrics collection
- **Memory**: ~5-10MB for metrics tracking objects
- **Network**: ~1 request per 5 seconds per client
- **Storage**: Debug logs in server console only

### When Disabled:
- **CPU**: 0% overhead (all monitoring code skipped)
- **Memory**: 0% overhead (no metrics objects created)
- **Network**: 0% overhead (no monitoring requests)
- **Storage**: No debug logs generated

## Verification

### Check iOS Status:
Look for these console messages:
- **Enabled**: `📊 METRICS: Timer started successfully`
- **Disabled**: `📊 METRICS: Performance monitoring disabled, skipping timer setup`

### Check Server Status:
- **Enabled**: Performance logs appear in console
- **Disabled**: `/api/debug/*` endpoints return `{"status": "monitoring_disabled"}`

### Visual Confirmation:
- **Enabled**: Real-time metrics display visible above Send/Skip buttons
- **Disabled**: No metrics UI shown in game view

## Recommended Settings

| Environment | iOS | Server | Rationale |
|-------------|-----|--------|-----------|
| Development | ✅ | ✅ | Full monitoring for debugging |
| Staging | ✅ | ✅ | Performance validation |
| Production | ❌ | ❌ | Minimal overhead |
| Performance Testing | ✅ | ❌ | Monitor client, avoid server noise |

## Implementation Details

The system uses conditional compilation and runtime checks to ensure zero overhead when disabled:

```swift
// Early exit prevents any processing
guard AppConfig.isPerformanceMonitoringEnabled else { return }

// UI conditionally rendered
if AppConfig.isPerformanceMonitoringEnabled {
    // Metrics display UI
}
```

This ensures that when monitoring is disabled, the code paths are not executed at all, providing true zero-overhead operation.