# Wordshelf Production Deployment Guide

## Overview
This guide covers the complete deployment process for Wordshelf, including server hosting, database setup, iOS app distribution via TestFlight, and CI/CD pipeline configuration.

---

## Prerequisites

### Required Accounts
- [ ] Apple Developer Program account ($99/year)
- [ ] Hosting provider account (Railway, DigitalOcean, or AWS)
- [ ] Domain registrar account (for custom domain)
- [ ] GitHub account (for CI/CD)

### Required Tools
- [ ] Xcode (latest version)
- [ ] Node.js (v18+)
- [ ] Git
- [ ] Docker (optional but recommended)

---

## Part 1: Server Infrastructure Setup

### 1.1 Choose Hosting Provider

#### Option A: Railway (Recommended for Simplicity)
**Pros**: Zero-config deployments, automatic HTTPS, built-in PostgreSQL
**Cons**: More expensive at scale, less control

**Setup Steps**:
1. Create Railway account at railway.app
2. Connect GitHub repository
3. Create new project from GitHub repo
4. Add PostgreSQL service to project
5. Configure environment variables

#### Option B: DigitalOcean App Platform
**Pros**: Competitive pricing, good control, managed databases
**Cons**: More configuration required

**Setup Steps**:
1. Create DigitalOcean account
2. Create new App Platform app
3. Connect GitHub repository
4. Create managed PostgreSQL database
5. Configure environment variables and domains

#### Option C: AWS (Advanced Users)
**Pros**: Maximum control, extensive services, scalable
**Cons**: Complex setup, requires AWS knowledge

**Setup Steps**:
1. Create AWS account
2. Set up Elastic Beanstalk or ECS
3. Create RDS PostgreSQL instance
4. Configure Load Balancer and Auto Scaling
5. Set up CloudWatch monitoring

### 1.2 Database Setup

#### Production Database Configuration
```sql
-- Create production database
CREATE DATABASE anagram_game_prod;

-- Create application user with limited permissions
CREATE USER anagram_app_user WITH PASSWORD 'your_secure_password';
GRANT CONNECT ON DATABASE anagram_game_prod TO anagram_app_user;
GRANT USAGE ON SCHEMA public TO anagram_app_user;
GRANT CREATE ON SCHEMA public TO anagram_app_user;
```

#### Environment Variables Setup
Create `.env` file for production:
```bash
# Database Configuration
DATABASE_URL=postgresql://username:password@host:port/database
DB_HOST=your-db-host.com
DB_PORT=5432
DB_NAME=anagram_game_prod
DB_USER=anagram_app_user
DB_PASSWORD=your_secure_password
DB_SSL=true

# Server Configuration
PORT=3000
NODE_ENV=production
JWT_SECRET=your_jwt_secret_here

# CORS Configuration
ALLOWED_ORIGINS=https://yourdomain.com,https://www.yourdomain.com

# Monitoring (optional)
MONITORING_ENABLED=true
LOG_LEVEL=info
```

### 1.3 Domain and SSL Setup

#### Domain Configuration
1. **Purchase Domain**: Use Namecheap, GoDaddy, or Cloudflare
2. **DNS Setup**: Point A record to server IP
3. **SSL Certificate**: Most hosting providers provide automatic SSL

#### Example DNS Configuration
```
Type    Name    Value               TTL
A       @       your.server.ip      300
A       www     your.server.ip      300
CNAME   api     yourdomain.com      300
```

---

## Part 2: Server Deployment

### 2.1 Prepare Server Code

#### Update Production Configuration
```javascript
// server/config/production.js
module.exports = {
  port: process.env.PORT || 3000,
  database: {
    url: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  },
  cors: {
    origin: process.env.ALLOWED_ORIGINS?.split(',') || ['https://yourdomain.com'],
    credentials: true
  },
  rateLimiting: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100 // limit each IP to 100 requests per windowMs
  }
};
```

#### Create Dockerfile (if using containerized deployment)
```dockerfile
# server/Dockerfile
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install production dependencies
RUN npm ci --only=production

# Copy application code
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nodejs -u 1001

# Change ownership
RUN chown -R nodejs:nodejs /app
USER nodejs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node healthcheck.js

# Start application
CMD ["npm", "start"]
```

### 2.2 Database Migration

#### Run Schema Migration
```bash
# Connect to production database
psql $DATABASE_URL

# Run schema file
\i server/database/schema.sql

# Verify tables created
\dt
```

#### Import Initial Data
```bash
# Import phrase data (if needed)
node server/populate_level_phrases.js

# Verify data imported
psql $DATABASE_URL -c "SELECT COUNT(*) FROM phrases;"
```

### 2.3 Deploy Server

#### Manual Deployment (First Time)
```bash
# Clone repository on server
git clone https://github.com/yourusername/anagram-game.git
cd anagram-game/server

# Install dependencies
npm ci --only=production

# Set environment variables
cp .env.example .env
# Edit .env with production values

# Start server with PM2 (process manager)
npm install -g pm2
pm2 start server.js --name anagram-server
pm2 save
pm2 startup
```

#### Verify Deployment
```bash
# Test health endpoint
curl https://yourdomain.com/api/status

# Test WebSocket connection
# Use browser console or WebSocket testing tool
```

---

## Part 3: iOS App Configuration for Production

### 3.1 Update App Configuration

#### Update NetworkManager for Production
```swift
// Models/NetworkManager.swift
class NetworkManager: ObservableObject {
    private let baseURL: String = {
        #if DEBUG
        return "http://localhost:3000"
        #else
        return "https://yourdomain.com"  // Your production URL
        #endif
    }()
    
    private let socketURL: String = {
        #if DEBUG
        return "ws://localhost:3000"
        #else
        return "wss://yourdomain.com"  // Your production WebSocket URL
        #endif
    }()
}
```

#### Update Info.plist for Production
```xml
<!-- Remove or restrict NSAppTransportSecurity -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>yourdomain.com</key>
        <dict>
            <key>NSExceptionRequiresForwardSecrecy</key>
            <false/>
        </dict>
    </dict>
</dict>
```

### 3.2 Version Management

#### Update Version Numbers
```bash
# In Xcode project settings, update:
# - Version: 1.16 (increment from current 1.15)
# - Build: 3 (increment from current 2)

# Or via command line:
agvtool new-marketing-version 1.16
agvtool new-version -all 3
```

---

## Part 4: TestFlight Distribution

### 4.1 App Store Connect Setup

#### Create App Record
1. **Login** to App Store Connect
2. **Create New App**:
   - Platform: iOS
   - Name: "Wordshelf"
   - Bundle ID: `com.fredrik.anagramgame`
   - Language: English (or primary language)
   - SKU: unique identifier

#### Configure App Information
```
App Name: Wordshelf
Subtitle: Multiplayer Word Puzzle Game
Category: Games > Word Games
Content Rating: 4+ (or appropriate rating)

Description:
"Challenge your mind with Wordshelf! Unscramble letters to form words from hidden phrases in this engaging multiplayer word puzzle game. Compete with friends, climb the leaderboard, and test your vocabulary skills with hints and physics-based gameplay."

Keywords: anagram, word game, puzzle, multiplayer, vocabulary
```

### 4.2 Code Signing and Certificates

#### Set up Development Team
1. **Xcode** → Preferences → Accounts
2. **Add Apple ID** associated with Developer Program
3. **Select Team** in project settings
4. **Enable Automatic Signing**

#### Archive and Upload
```bash
# Clean and build for release
xcodebuild clean -project "Anagram Game.xcodeproj" -scheme "Anagram Game"

# Create archive
xcodebuild archive \
  -project "Anagram Game.xcodeproj" \
  -scheme "Anagram Game" \
  -archivePath "./build/AnagramGame.xcarchive" \
  -configuration Release

# Upload to App Store Connect
xcodebuild -exportArchive \
  -archivePath "./build/AnagramGame.xcarchive" \
  -exportPath "./build/export" \
  -exportOptionsPlist ExportOptions.plist
```

#### ExportOptions.plist
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
```

### 4.3 TestFlight Configuration

#### Set up Beta Testing
1. **App Store Connect** → Your App → TestFlight
2. **Create Internal Testing Group**:
   - Add team members (up to 25)
   - Enable automatic distribution
3. **Create External Testing Group**:
   - Add external testers (up to 10,000)
   - Requires Beta App Review

#### Beta Testing Information
```
Beta App Name: Wordshelf Beta
Beta App Description: 
"Help us test the latest version of Wordshelf! This multiplayer word puzzle game lets you compete with friends to unscramble letters and form words from hidden phrases.

What to Test:
- Multiplayer functionality
- Game performance and stability
- User interface and experience
- Network connectivity

Please report any bugs or feedback through TestFlight or email: your-email@domain.com"

Feedback Email: your-feedback-email@domain.com
Marketing URL: https://yourdomain.com
Privacy Policy URL: https://yourdomain.com/privacy
```

---

## Part 5: CI/CD Pipeline Setup

### 5.1 GitHub Actions Workflow

#### Create Workflow File
```yaml
# .github/workflows/deploy-server.yml
name: Deploy Server to Production

on:
  push:
    branches: [main]
    paths: ['server/**']
  pull_request:
    branches: [main]
    paths: ['server/**']

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:13
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test_db
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Node.js
      uses: actions/setup-node@v3
      with:
        node-version: '18'
        cache: 'npm'
        cache-dependency-path: server/package-lock.json
    
    - name: Install dependencies
      working-directory: ./server
      run: npm ci
    
    - name: Run tests
      working-directory: ./server
      run: npm test
      env:
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/test_db

  deploy:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Deploy to Railway
      uses: railway-app/railway-cli@v1
      with:
        command: up
      env:
        RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
```

### 5.2 Environment Secrets

#### GitHub Repository Secrets
Add these secrets in GitHub repository settings:
```
RAILWAY_TOKEN: your_railway_deployment_token
DATABASE_URL: production_database_url
JWT_SECRET: production_jwt_secret
ALLOWED_ORIGINS: https://yourdomain.com
```

### 5.3 iOS App CI/CD (Optional)

#### Fastlane Setup
```ruby
# fastlane/Fastfile
default_platform(:ios)

platform :ios do
  desc "Build and upload to TestFlight"
  lane :beta do
    increment_build_number(xcodeproj: "Anagram Game.xcodeproj")
    build_app(scheme: "Anagram Game")
    upload_to_testflight(skip_waiting_for_build_processing: true)
  end
end
```

---

## Part 6: Monitoring and Maintenance

### 6.1 Server Monitoring

#### Health Check Endpoint
```javascript
// server/routes/health.js
app.get('/health', async (req, res) => {
  try {
    // Check database connection
    await pool.query('SELECT 1');
    
    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      version: process.env.npm_package_version,
      uptime: process.uptime(),
      database: 'connected'
    });
  } catch (error) {
    res.status(500).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});
```

#### Set up Monitoring Alerts
1. **Uptime Robot**: Monitor health endpoint
2. **Railway/DigitalOcean**: Built-in monitoring
3. **Custom Alerts**: Email/Slack notifications

### 6.2 Logging and Analytics

#### Structured Logging
```javascript
// server/utils/logger.js
const winston = require('winston');

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'app.log' })
  ]
});

module.exports = logger;
```

---

## Part 7: Rollback and Recovery

### 7.1 Rollback Procedures

#### Server Rollback
```bash
# Railway: Use web dashboard to rollback to previous deployment
# Manual: Keep previous version tagged in git
git checkout previous-stable-tag
railway up
```

#### Database Rollback
```bash
# Create backup before deployments
pg_dump $DATABASE_URL > backup_$(date +%Y%m%d_%H%M%S).sql

# Restore if needed
psql $DATABASE_URL < backup_file.sql
```

### 7.2 Disaster Recovery

#### Backup Strategy
1. **Database**: Automated daily backups
2. **Code**: Git repository with tags
3. **Environment**: Document all configurations
4. **Monitoring**: Alert on service failures

---

## Deployment Checklist

### Pre-Deployment
- [ ] All tests pass
- [ ] Security audit completed
- [ ] Environment variables configured
- [ ] Domain and SSL certificates ready
- [ ] Database backup created

### Server Deployment
- [ ] Code deployed to staging environment
- [ ] Database migrations completed
- [ ] Health checks passing
- [ ] WebSocket connections working
- [ ] API endpoints responding correctly

### iOS App Deployment
- [ ] Version numbers incremented
- [ ] Production URLs configured
- [ ] Archive created successfully
- [ ] Uploaded to TestFlight
- [ ] Beta testing configured

### Post-Deployment
- [ ] End-to-end testing completed
- [ ] Monitoring alerts configured
- [ ] Performance metrics baseline established
- [ ] Documentation updated
- [ ] Team notified of deployment

### Rollback Plan
- [ ] Previous version tagged in git
- [ ] Database backup verified
- [ ] Rollback procedure documented
- [ ] Emergency contacts identified

---

## Troubleshooting Common Issues

### Server Issues
```bash
# Check server logs
railway logs
# or
pm2 logs anagram-server

# Check database connection
psql $DATABASE_URL -c "SELECT 1;"

# Check environment variables
env | grep DATABASE
```

### iOS Issues
```bash
# Check code signing
security find-identity -v -p codesigning

# Clean build cache
rm -rf ~/Library/Developer/Xcode/DerivedData
```

### Network Issues
```bash
# Test server endpoint
curl -I https://yourdomain.com/api/status

# Test WebSocket connection
wscat -c wss://yourdomain.com
```

---

## Estimated Timeline

### First-Time Deployment: 7-10 days
- **Days 1-2**: Infrastructure setup and domain configuration
- **Days 3-4**: Server deployment and database setup
- **Days 5-6**: iOS app configuration and TestFlight setup
- **Days 7-8**: CI/CD pipeline configuration
- **Days 9-10**: Testing and monitoring setup

### Subsequent Deployments: 1-2 hours
- Automated via CI/CD pipeline
- Manual verification and testing

---

## Success Metrics

### Technical Metrics
- Server uptime > 99.5%
- Response time < 200ms average
- Error rate < 1%
- TestFlight crash rate < 0.1%

### User Metrics
- Beta tester feedback scores
- App Store review ratings
- User retention rates
- Game completion rates

---

*This deployment guide should be updated as infrastructure and processes evolve.*