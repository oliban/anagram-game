#!/bin/bash

# GitHub Actions Secrets Setup Helper
# This script helps you configure the required secrets for GitHub Actions deployment

set -e

echo "🔐 GitHub Actions Secrets Setup Helper"
echo "========================================"
echo ""

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed."
    echo "   Install it from: https://cli.github.com/"
    echo "   Then run: gh auth login"
    exit 1
fi

# Check if user is authenticated
if ! gh auth status &> /dev/null; then
    echo "❌ Not authenticated with GitHub CLI."
    echo "   Run: gh auth login"
    exit 1
fi

echo "✅ GitHub CLI is installed and authenticated"
echo ""

# Get current AWS credentials
echo "📋 Current AWS Configuration:"
echo "   Account ID: $(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null || echo 'Not configured')"
echo "   Region: $(aws configure get region 2>/dev/null || echo 'Not configured')"
echo "   Access Key: $(aws configure get aws_access_key_id 2>/dev/null || echo 'Not configured')"
echo ""

# Check if we have AWS credentials
AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")

if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
    echo "❌ AWS credentials not found in ~/.aws/credentials"
    echo "   Run: aws configure"
    echo "   Or set environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
    exit 1
fi

echo "✅ AWS credentials found"
echo ""

# Confirm repository
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "")
if [[ -z "$REPO" ]]; then
    echo "❌ Not in a GitHub repository directory"
    exit 1
fi

echo "📦 Repository: $REPO"
echo ""

# Ask for confirmation
read -p "❓ Do you want to set up GitHub secrets for AWS deployment? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ Setup cancelled"
    exit 0
fi

echo ""
echo "🚀 Setting up GitHub secrets..."

# Set the secrets
echo "   Setting AWS_ACCESS_KEY_ID..."
echo "$AWS_ACCESS_KEY_ID" | gh secret set AWS_ACCESS_KEY_ID

echo "   Setting AWS_SECRET_ACCESS_KEY..."
echo "$AWS_SECRET_ACCESS_KEY" | gh secret set AWS_SECRET_ACCESS_KEY

echo ""
echo "✅ GitHub secrets configured successfully!"
echo ""
echo "📋 Next steps:"
echo "   1. Push to 'staging' branch to test staging deployment"
echo "   2. Push to 'main' branch for production deployment"
echo "   3. Monitor deployments in the GitHub Actions tab"
echo ""
echo "🔗 View repository secrets: https://github.com/$REPO/settings/secrets/actions"
echo ""

# Test if we can list secrets (requires admin access)
echo "🔍 Verifying secrets..."
if gh secret list &> /dev/null; then
    echo "✅ Secrets configured:"
    gh secret list
else
    echo "⚠️  Cannot list secrets (may require admin access), but they should be set correctly."
fi