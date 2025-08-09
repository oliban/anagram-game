# Version Management & Deployment System

## 🎯 **Problem Statement**
Every server update requires:
1. New server URL (when containers restart)
2. New iOS app build (to point to new URL)
3. Clear version tracking for troubleshooting
4. Automated staging deployment

## 🏗️ **Proposed Solution: Semantic Versioning + Staging Infrastructure**

### **Version Format: `vMAJOR.MINOR.PATCH-BUILD`**
- **MAJOR**: Breaking API changes
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes, backward compatible  
- **BUILD**: Auto-incrementing build number

**Examples:**
- `v1.17.0-001` - First build of v1.17 release
- `v1.17.1-005` - Fifth build of patch v1.17.1
- `v2.0.0-001` - Major version with breaking changes

### **1. Server Version Management**

#### **Automatic Version Injection**
```bash
# In docker-compose.services.yml
environment:
  - SERVER_VERSION=${SERVER_VERSION:-v1.17.0-dev}
  - BUILD_NUMBER=${GITHUB_RUN_NUMBER:-local}
  - GIT_SHA=${GITHUB_SHA:-unknown}
```

#### **Version Endpoint**
```javascript
// GET /api/version
{
  "version": "v1.17.0-001",
  "build": "001", 
  "sha": "b33eb63",
  "environment": "staging",
  "services": {
    "game-server": "healthy",
    "web-dashboard": "healthy", 
    "admin-service": "healthy",
    "link-generator": "healthy"
  },
  "database": {
    "version": "15.13",
    "migrations": "up-to-date"
  }
}
```

### **2. Staging Infrastructure**

#### **Staging Server Setup (Pi or Cloud)**
```yaml
# staging-docker-compose.yml
version: '3.8'
services:
  # All services with staging configuration
  nginx:
    image: nginx:alpine
    volumes:
      - ./staging-nginx.conf:/etc/nginx/nginx.conf
    ports:
      - "80:80"
      - "443:443"
    environment:
      - ENVIRONMENT=staging
      - SERVER_VERSION=${SERVER_VERSION}
```

#### **Stable URLs with Nginx Reverse Proxy**
```nginx
# staging-nginx.conf
server {
    listen 80;
    server_name staging.wordshelf.com;
    
    location /api {
        proxy_pass http://game-server:3000;
        proxy_set_header X-Version $server_version;
    }
    
    location /health {
        return 200 '{"status":"healthy","version":"${SERVER_VERSION}"}';
        add_header Content-Type application/json;
    }
}
```

### **3. iOS App Version Management**

#### **Config-Based Server URLs**
```swift
// Config/ServerConfig.swift
struct ServerConfig {
    static let production = "https://api.wordshelf.com"
    static let staging = "https://staging.wordshelf.com"  
    static let development = "http://192.168.1.188:3000"
    
    static var current: String {
        #if STAGING
        return staging
        #elseif DEBUG  
        return development
        #else
        return production
        #endif
    }
}
```

#### **Version Compatibility Check**
```swift
// Services/VersionService.swift
func validateServerCompatibility() async throws {
    let serverVersion = try await fetchServerVersion()
    let clientVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    
    // Check if client can work with server
    if !isCompatible(client: clientVersion, server: serverVersion) {
        throw VersionError.incompatibleServer
    }
}
```

### **4. Automated Build Pipeline**

#### **GitHub Actions: Staging Deployment**
```yaml
# .github/workflows/deploy-staging.yml
name: 🚀 Deploy to Staging
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Generate Version
        run: |
          VERSION="v1.$(date +%m).$(date +%d)-$(printf '%03d' $GITHUB_RUN_NUMBER)"
          echo "SERVER_VERSION=$VERSION" >> $GITHUB_ENV
          
      - name: Deploy to Staging Server
        run: |
          ssh staging-server "cd /opt/wordshelf && \
            git pull origin main && \
            SERVER_VERSION=$VERSION docker-compose -f staging-docker-compose.yml up -d"
            
      - name: Trigger iOS Build
        if: success()
        run: |
          curl -X POST $FASTLANE_WEBHOOK \
            -H "Content-Type: application/json" \
            -d '{"version":"$SERVER_VERSION","environment":"staging"}'
```

#### **Automatic iOS Builds**
```ruby
# fastlane/Fastfile
lane :staging_build do |options|
  server_version = options[:version]
  
  # Update server URL in app
  update_plist(
    plist_path: "Wordshelf/Info.plist",
    block: proc do |plist|
      plist["ServerVersion"] = server_version
      plist["ServerEnvironment"] = "staging"
    end
  )
  
  # Build and deploy to TestFlight
  build_app(scheme: "Wordshelf-Staging")
  upload_to_testflight(
    changelog: "Staging build for server #{server_version}"
  )
end
```

### **5. Troubleshooting & Monitoring**

#### **Version Dashboard**
- **Live status**: https://staging.wordshelf.com/health
- **Admin panel**: Server version, database migrations, service health
- **Client compatibility**: Which app versions work with current server

#### **Deployment History**
```javascript
// GET /api/admin/deployments
[
  {
    "version": "v1.17.0-001",
    "deployed_at": "2025-08-09T09:30:00Z",
    "git_sha": "b33eb63",
    "status": "active",
    "ios_builds": ["1.16.1.001", "1.16.2.001"]
  },
  {
    "version": "v1.16.5-089", 
    "deployed_at": "2025-08-08T15:22:00Z",
    "status": "rolled_back",
    "rollback_reason": "Database migration issue"
  }
]
```

### **6. Implementation Steps**

1. **✅ Immediate**: Fix CI/CD test failures
2. **🏗️ Week 1**: Set up staging server with stable URLs
3. **📱 Week 2**: Implement iOS version management
4. **🤖 Week 3**: Automate build pipeline integration
5. **📊 Week 4**: Add monitoring dashboard

### **Benefits**
- **🎯 Clear versioning** for troubleshooting
- **🚀 Automatic deployments** reduce manual work
- **📱 Coordinated iOS builds** prevent version mismatches  
- **🔄 Easy rollbacks** with version history
- **⚡ Stable URLs** reduce iOS app rebuild frequency

This system ensures every deployment is tracked, tested, and automatically coordinated between server and iOS app builds!