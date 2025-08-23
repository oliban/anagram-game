#!/bin/bash

# Archive script for creating signed iOS release builds
# This creates a properly signed archive ready for App Store distribution
# Usage: ./archive-for-release.sh [environment] 
# Environments: staging (default), local, aws

set -e

# Environment parameter (defaults to staging for App Store builds)
ENVIRONMENT=${1:-staging}

echo "🚀 Creating signed archive for Wordshelf..."
echo "📱 Target: App Store Distribution"
echo "🌍 Environment: $ENVIRONMENT"
echo ""

# Check if we're in the right directory
if [ ! -f "Wordshelf.xcodeproj/project.pbxproj" ]; then
    echo "❌ Error: Must be run from the project root directory"
    exit 1
fi

# Verify environment configuration for staging builds
if [ "$ENVIRONMENT" = "staging" ]; then
    echo "🔍 Verifying staging environment configuration..."
    CURRENT_ENV=$(grep 'let env = ' Models/Network/NetworkConfiguration.swift | sed 's/.*"\(.*\)".*/\1/')
    
    if [ "$CURRENT_ENV" != "staging" ]; then
        echo "⚠️  WARNING: NetworkConfiguration is set to '$CURRENT_ENV', not 'staging'"
        echo "❌ For App Store/TestFlight builds, environment MUST be 'staging'"
        echo "📝 Please edit Models/Network/NetworkConfiguration.swift line 90:"
        echo "   Change: let env = \"$CURRENT_ENV\" "
        echo "   To:     let env = \"staging\" "
        echo ""
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "✅ Environment correctly set to 'staging'"
    fi
fi

# Create archive with automatic signing
echo "🔨 Building release archive for $ENVIRONMENT..."
ARCHIVE_NAME="Wordshelf-$(echo $ENVIRONMENT | tr '[:lower:]' '[:upper:]').xcarchive"

xcodebuild -project Wordshelf.xcodeproj \
    -scheme Wordshelf \
    -configuration Release \
    -sdk iphoneos \
    -archivePath ~/Desktop/$ARCHIVE_NAME \
    archive \
    -allowProvisioningUpdates

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Archive created successfully!"
    echo "📦 Location: ~/Desktop/$ARCHIVE_NAME"
    echo "🌍 Environment: $ENVIRONMENT"
    echo ""
    
    if [ "$ENVIRONMENT" = "staging" ]; then
        echo "📤 Next steps for STAGING/App Store:"
        echo "1. Xcode Organizer should open automatically"
        echo "2. Click 'Distribute App'"
        echo "3. Select 'App Store Connect' for TestFlight"
        echo "4. Follow the upload process"
        echo "💡 This archive connects to Pi staging server (192.168.1.188)"
    else
        echo "📤 Next steps for $ENVIRONMENT environment:"
        echo "1. This archive is configured for $ENVIRONMENT environment"
        echo "2. Use appropriate distribution method for your target"
    fi
    echo ""
    
    # Open the archive in Xcode
    open ~/Desktop/$ARCHIVE_NAME
else
    echo ""
    echo "❌ Archive creation failed for $ENVIRONMENT environment!"
    echo "Please check:"
    echo "1. You're signed into Xcode with your Apple Developer account"
    echo "2. The project has the correct team selected in Signing & Capabilities"
    echo "3. Your provisioning profiles are up to date"
    if [ "$ENVIRONMENT" = "staging" ]; then
        echo "4. NetworkConfiguration.swift is set to 'staging' (line 90)"
    fi
    exit 1
fi
