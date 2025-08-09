# CI/CD Test Runner Execution Guide

## When Does the Test Runner Execute?

The automated test runner is designed to run at **multiple strategic points** in the development lifecycle to ensure code quality and catch issues early.

## 🔄 Execution Triggers

### 1. **Code Changes (Most Common)**

#### **Every Push to Main/Develop Branches**
```yaml
on:
  push:
    branches: [ main, develop ]
    paths:
      - 'services/**'
      - 'testing/**'
      - 'docker-compose.services.yml'
```

**What happens:**
- ✅ Full API test suite (5-10 minutes)
- ⚠️ Performance tests (only on main branch)
- 📊 Comprehensive reporting
- 🚨 Deployment gate evaluation

**Use case:** Validate that new code doesn't break existing functionality

#### **Every Pull Request**
```yaml
on:
  pull_request:
    branches: [ main ]
```

**What happens:**
- ✅ Full API test suite (5-10 minutes)
- ❌ Skip performance tests (faster feedback)
- 💬 Comment results on PR
- 🚫 Block merge if critical tests fail

**Use case:** Prevent broken code from being merged

### 2. **Scheduled Runs (Monitoring)**

#### **Nightly Health Checks**
```yaml
schedule:
  - cron: '0 2 * * *'  # 2 AM UTC daily
```

**What happens:**
- ✅ Full test suite including performance
- 🔍 Memory leak detection
- 📈 Performance baseline validation
- 🚨 Create GitHub issue if failures detected

**Use case:** Detect infrastructure drift or gradual degradation

#### **Business Hours Monitoring**
```yaml
schedule:
  - cron: '0 14 * * 1-5'  # 2 PM UTC weekdays
```

**What happens:**
- ✅ Critical tests only (faster)
- 📊 Service health validation
- 🔔 Immediate notifications if issues found

**Use case:** Early warning system during active development hours

### 3. **Manual Triggers (On-Demand)**

#### **Workflow Dispatch (GitHub Actions)**
```yaml
workflow_dispatch:
  inputs:
    skip_performance:
      description: 'Skip performance tests'
      default: 'true'
```

**What happens:**
- ✅ Configurable test execution
- 🎯 Custom parameters (skip performance, stop on failure)
- 📋 Full reporting for investigation

**Use case:** Debug issues, validate fixes, pre-deployment checks

#### **Jenkins Manual Builds**
- **Build Now** button in Jenkins UI
- **Parameterized builds** with custom options
- **Remote API triggers** from external tools

### 4. **Deployment Pipeline Integration**

#### **Pre-Staging Deployment**
```groovy
stage('🚀 Deployment Gate') {
    when { branch 'main' }
    steps {
        // Evaluate test results
        // Block deployment if success rate < 95%
    }
}
```

**What happens:**
- ✅ **95%+ success rate** → ✅ Deployment approved
- ⚠️ **90-95% success rate** → ⚠️ Manual approval required  
- ❌ **<90% success rate** → ❌ Deployment blocked

#### **Post-Deployment Validation**
```bash
# After deployment to staging/production
curl -X POST "https://jenkins.example.com/job/api-tests/buildWithParameters" \
  -d "ENVIRONMENT=staging&NOTIFY_ON_FAILURE=true"
```

**Use case:** Validate that deployed services are working correctly

## 🎯 Execution Contexts

### **Development Context (Feature Branches)**
```
Trigger: Push to feature/branch
Duration: ~5-8 minutes
Tests: API + Integration + Workflows
Skip: Performance tests
Notify: Developer only
```

### **Integration Context (Main/Develop)**
```
Trigger: Push to main/develop
Duration: ~15-20 minutes  
Tests: All tests including performance
Skip: None
Notify: Team channels
Gate: Deployment approval
```

### **Monitoring Context (Scheduled)**
```
Trigger: Cron schedule
Duration: ~10-25 minutes
Tests: Full suite + health monitoring
Skip: None (comprehensive)
Notify: Operations team
Action: Create incident tickets
```

### **Emergency Context (Manual)**
```
Trigger: Manual/API call
Duration: Configurable
Tests: Targeted or full suite
Skip: Configurable
Notify: Requester
Purpose: Investigation/validation
```

## 📊 Real-World Execution Examples

### **Typical Day in Development:**

**9:00 AM** - Developer pushes feature branch
```
✅ API Tests: 95% success (8 minutes)
💬 PR comment: "Tests mostly passing, 1 validation issue"
```

**10:30 AM** - Code review completed, PR merged to main
```
✅ Full Test Suite: 98% success (18 minutes)  
✅ Deployment Gate: APPROVED
🚀 Auto-deploy to staging initiated
```

**2:00 PM** - Scheduled business hours check
```
✅ Health Check: All services healthy (3 minutes)
📊 Response times within normal range
```

**2:00 AM** - Nightly comprehensive check
```
✅ Full Suite: 97% success (22 minutes)
📈 Performance: Response times +5% (within tolerance)
🔍 Memory usage: Normal, no leaks detected
```

### **Issue Detection Scenario:**

**Tuesday 2:15 AM** - Nightly build detects issues
```
❌ API Tests: 78% success rate
❌ Socket.IO tests: Connection timeouts
🚨 GitHub issue auto-created: "Nightly API Tests Failed"
📧 Email alert sent to on-call team
```

**Tuesday 8:30 AM** - Team investigates
```
🔍 Manual test run: SKIP_PERFORMANCE=true node automated-test-runner.js
📋 Reports show database connection issues
🔧 Infrastructure team notified
```

**Tuesday 9:15 AM** - Fix deployed, validation run
```
✅ Manual test run: 99% success rate
✅ Issue auto-closed by next scheduled run
📊 Post-incident report generated
```

## 🛠️ Configuration by Environment

### **Local Development**
```bash
# Quick validation before pushing
node testing/scripts/automated-test-runner.js --skip-performance
```

### **CI/CD Development Environment**
```yaml
env:
  SKIP_PERFORMANCE: "true"
  STOP_ON_FAILURE: "false"
  GENERATE_REPORTS: "true"
```

### **CI/CD Staging Environment**  
```yaml
env:
  SKIP_PERFORMANCE: "false"
  STOP_ON_FAILURE: "true"
  DEPLOYMENT_GATE: "true"
```

### **CI/CD Production Monitoring**
```yaml
env:
  SKIP_PERFORMANCE: "false"
  COMPREHENSIVE_LOGGING: "true"
  ALERT_THRESHOLDS: "strict"
```

## 📋 Test Execution Matrix

| Trigger | API Tests | Performance | Workflows | Duration | Notifications |
|---------|-----------|-------------|-----------|----------|---------------|
| Feature Push | ✅ | ❌ | ✅ | 5-8 min | Developer |
| Main Push | ✅ | ✅ | ✅ | 15-20 min | Team |
| Pull Request | ✅ | ❌ | ✅ | 5-8 min | PR Comments |
| Nightly | ✅ | ✅ | ✅ | 20-25 min | Operations |
| Manual | 🎯 Config | 🎯 Config | 🎯 Config | Variable | Requester |
| Pre-Deploy | ✅ | ✅ | ✅ | 15-20 min | Release Team |
| Post-Deploy | ✅ | ❌ | ✅ | 5-10 min | Ops + DevOps |

## 🚨 Failure Response Workflows

### **Critical Failure (< 90% success)**
1. 🚫 Block deployments immediately
2. 🚨 Page on-call engineer  
3. 📋 Auto-create incident ticket
4. 📧 Notify team leads
5. 🔄 Prevent further merges to main

### **Warning Failure (90-95% success)**
1. ⚠️ Mark build as unstable
2. 📧 Email development team
3. 📊 Generate detailed analysis report
4. 🤔 Require manual deployment approval

### **Performance Degradation**
1. 📈 Compare against baseline metrics
2. 🔔 Notify performance team
3. 📊 Generate performance trending report
4. ⚡ Trigger infrastructure health checks

## 🎯 Key Success Metrics

- **Response Time**: < 2 minutes for critical failures
- **Coverage**: 95%+ of API functionality tested
- **Reliability**: < 1% false positive rate  
- **Performance**: Catch >5% performance regressions
- **Integration**: Block 99%+ of breaking changes

The automated test runner serves as the **quality gateway** for the entire Wordshelf platform, ensuring that every code change is validated before reaching users.