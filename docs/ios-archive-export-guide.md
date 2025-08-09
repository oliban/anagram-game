# iOS Archive and Export Guide

## Creating a Signed Archive for App Store Distribution

### ⚠️ IMPORTANT: Environment Configuration
**The app MUST be configured for STAGING environment before archiving:**
- Staging server: Cloudflare tunnel (URL changes on Pi reboot - check current URL first)
- Configuration file: `Models/Network/NetworkConfiguration.swift`
- Line 90 should read: `let env = "staging" // DEFAULT_ENVIRONMENT`
- Line 65 should contain current Cloudflare tunnel URL: `let stagingConfig = EnvironmentConfig(host: "[current-tunnel-url].trycloudflare.com", ...)`
- **IMPORTANT**: Tunnel URL changes when Pi reboots - always verify current URL before archiving
- NOT "local" or "aws" - specifically "staging" for TestFlight/App Store builds

### Prerequisites
1. Ensure you're signed into Xcode with your Apple Developer account
2. Verify team settings in Xcode project (Signing & Capabilities tab)
3. Ensure the project version and build number are updated
4. **VERIFY**: NetworkConfiguration.swift is set to "staging" environment
5. **UPDATE TUNNEL URL**: Get current Cloudflare tunnel URL and update NetworkConfiguration.swift

#### Getting Current Tunnel URL
```bash
# Check current Pi server tunnel (if Pi is running)
curl -s http://192.168.1.188:3000/api/status | grep -o 'tunnel.*\.trycloudflare\.com' || echo "Pi server not responding"

# Or check build script output
./build_multi_sim.sh staging 2>&1 | grep "tunnel detected" | grep -o 'https://[^"]*\.trycloudflare\.com'
```

### Command Line Archive Creation

#### Verify environment configuration first:
```bash
# Check current environment setting
grep 'let env = ' Models/Network/NetworkConfiguration.swift
# Should output: let env = "staging" // DEFAULT_ENVIRONMENT

# Check staging server configuration (URL will vary - changes on Pi reboot)
grep 'stagingConfig.*host' Models/Network/NetworkConfiguration.swift
# Should output: let stagingConfig = EnvironmentConfig(host: "[some-tunnel-name].trycloudflare.com", ...)
# Note: The exact tunnel URL changes when Pi server reboots
```

#### Create a signed archive for STAGING distribution:
```bash
xcodebuild -project Wordshelf.xcodeproj \
  -scheme Wordshelf \
  -configuration Release \
  -sdk iphoneos \
  -archivePath ~/Desktop/Wordshelf-Staging.xcarchive \
  archive \
  -allowProvisioningUpdates
```

**Important Notes:**
- The `-allowProvisioningUpdates` flag is essential for automatic signing
- The archive will use the team configured in the Xcode project file
- Current team ID: `5XR7USWXMZ`

### Alternative: Archive from Xcode UI
1. Open the project in Xcode
2. Select "Any iOS Device" as the build destination
3. Go to **Product → Archive**
4. Wait for the build to complete

### Distributing the Archive

Once the archive is created:

1. The archive will automatically open in Xcode Organizer
2. If not, open manually: **Window → Organizer**
3. Select your archive from the list
4. Click **Distribute App**
5. Choose distribution method:
   - **App Store Connect** - For TestFlight and App Store
   - **Ad Hoc** - For specific devices
   - **Enterprise** - For in-house distribution
   - **Development** - For development testing

### Export Options

For command-line export (after archive is created):
```bash
xcodebuild -exportArchive \
  -archivePath ~/Desktop/Wordshelf-Signed.xcarchive \
  -exportPath ~/Desktop/WordshelfExport \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
```

### Current App Configuration
- **Bundle ID**: `com.fredrik.anagramgame`
- **App Name**: Wordshelf
- **Current Version**: 1.16
- **Current Build**: 3
- **Team ID**: 5XR7USWXMZ
- **Development Team**: 5XR7USWXMZ
- **Encryption Exemption**: Configured (ITSAppUsesNonExemptEncryption = false)
- **Target Environment**: STAGING (Cloudflare tunnel - URL changes on Pi reboot)
- **Environment Config**: NetworkConfiguration.swift line 90

### Encryption Documentation

The app includes `ITSAppUsesNonExemptEncryption = false` in Info.plist, which means:
- You won't be prompted about encryption during each submission
- The app declares it doesn't use encryption beyond standard HTTPS/TLS
- This is appropriate for apps that only use:
  - HTTPS for network communication
  - Standard iOS encryption APIs
  - No custom encryption algorithms

### Troubleshooting

#### "No team found in archive" error
- Archive was built without signing
- Solution: Use the signed archive command above with `-allowProvisioningUpdates`

#### "No profiles found" error
- Xcode can't find matching provisioning profiles
- Solution: 
  1. Sign into Xcode with Apple Developer account
  2. Go to Xcode → Settings → Accounts
  3. Download manual profiles if needed
  4. Use `-allowProvisioningUpdates` flag

#### Archive not appearing in Organizer
- Check the archive location: `~/Library/Developer/Xcode/Archives/[Date]/`
- Or use custom location like `~/Desktop/Wordshelf-Signed.xcarchive`
- Open manually with: `open [path-to-archive]`

### Version Management

Before creating a release archive:
1. **SET ENVIRONMENT TO STAGING**: Edit NetworkConfiguration.swift line 90 to `"staging"`
2. Update version in project settings (MARKETING_VERSION)
3. Update build number (CURRENT_PROJECT_VERSION)
4. Commit changes to git
5. Tag the release: `git tag v1.16.3`

### Archive Locations

Default Xcode archives:
```
~/Library/Developer/Xcode/Archives/YYYY-MM-DD/
```

Custom archive (recommended for staging/production releases):
```
~/Desktop/Wordshelf-Staging.xcarchive  # For staging/TestFlight builds
~/Desktop/Wordshelf-Local.xcarchive     # For local testing only
~/Desktop/Wordshelf-AWS.xcarchive       # For AWS production (if needed)
```

### Quick Commands Reference

```bash
# STEP 1: Verify staging environment is configured
grep 'let env = ' Models/Network/NetworkConfiguration.swift
# Must show: let env = "staging"

# Also verify staging uses Cloudflare tunnel (URL will vary)
grep 'stagingConfig.*host' Models/Network/NetworkConfiguration.swift
# Must show: host: "[tunnel-name].trycloudflare.com" (exact URL varies)

# STEP 2: Build signed archive for STAGING
./scripts/archive-for-release.sh staging

# Or manually for staging:
xcodebuild -project Wordshelf.xcodeproj -scheme Wordshelf \
  -configuration Release -sdk iphoneos \
  -archivePath ~/Desktop/Wordshelf-Staging.xcarchive \
  archive -allowProvisioningUpdates

# STEP 3: Open in Organizer
open ~/Desktop/Wordshelf-Staging.xcarchive
```

## Notes
- Always use `-allowProvisioningUpdates` for automatic signing
- The archive must be signed to upload to App Store Connect
- Keep archives of released versions for debugging crash reports