#!/bin/bash

# GitFlow Setup Script
# Sets up the improved branch structure and protection rules

echo "🌊 Setting up GitFlow workflow for Wordshelf"
echo "============================================="

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ Not in a git repository. Please run this from the project root."
    exit 1
fi

echo "📍 Current repository: $(basename $(git rev-parse --show-toplevel))"
echo "🌿 Current branch: $(git branch --show-current)"
echo ""

# Step 1: Create develop branch from main
echo "1️⃣ Creating develop branch..."
if git show-ref --verify --quiet refs/heads/develop; then
    echo "   ✅ develop branch already exists"
else
    git checkout main
    git pull origin main
    git checkout -b develop
    git push -u origin develop
    echo "   ✅ develop branch created and pushed"
fi

# Step 2: Set up branch protection (requires GitHub CLI)
echo ""
echo "2️⃣ Setting up branch protection rules..."

if command -v gh &> /dev/null; then
    echo "   📋 Setting up main branch protection..."
    gh api repos/:owner/:repo/branches/main/protection \
        --method PUT \
        --field required_status_checks='{"strict":true,"contexts":["Comprehensive Testing"]}' \
        --field enforce_admins=true \
        --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true}' \
        --field restrictions=null \
        --field allow_force_pushes=false \
        --field allow_deletions=false 2>/dev/null || echo "   ⚠️ Could not set main branch protection (may need repository admin rights)"

    echo "   📋 Setting up develop branch protection..."
    gh api repos/:owner/:repo/branches/develop/protection \
        --method PUT \
        --field required_status_checks='{"strict":true,"contexts":["Integration Testing"]}' \
        --field enforce_admins=false \
        --field required_pull_request_reviews='{"required_approving_review_count":1}' \
        --field restrictions=null \
        --field allow_force_pushes=false \
        --field allow_deletions=false 2>/dev/null || echo "   ⚠️ Could not set develop branch protection (may need repository admin rights)"

    echo "   ✅ Branch protection rules configured"
else
    echo "   ⚠️ GitHub CLI not installed. Branch protection must be set up manually in GitHub:"
    echo "      1. Go to Settings → Branches in GitHub"
    echo "      2. Add protection rules for 'main' and 'develop' branches"
    echo "      3. Require pull request reviews"
    echo "      4. Require status checks to pass"
fi

# Step 3: Create example feature branch
echo ""
echo "3️⃣ Creating example feature branch..."
git checkout develop
git checkout -b feature/setup-gitflow-example
echo "   ✅ Created feature/setup-gitflow-example branch"

# Step 4: Show next steps
echo ""
echo "🎉 GitFlow setup complete!"
echo "=========================="
echo ""
echo "📋 Next steps:"
echo "   1. Push this feature branch: git push -u origin feature/setup-gitflow-example"
echo "   2. Create a PR to develop: gh pr create --base develop --title 'Setup GitFlow workflow'"
echo "   3. Test the new workflow with the example PR"
echo ""
echo "🔧 New workflow commands:"
echo "   • Start feature: git checkout develop && git pull && git checkout -b feature/my-feature"
echo "   • Create feature PR: gh pr create --base develop --title 'feat: my feature'"
echo "   • Create release PR: gh pr create --base main --title 'Release v1.X'"
echo ""
echo "📚 Read the full guide: docs/IMPROVED_WORKFLOW_GUIDE.md"
echo ""

# Step 5: Create a sample commit to test the workflow
cat > GITFLOW_SETUP.md << 'EOF'
# GitFlow Setup Complete

This file was created during GitFlow setup to test the new workflow.

## New Branch Structure
- `main` - Production releases only
- `develop` - Integration branch for features  
- `feature/*` - Individual feature development

## Workflow Summary
1. Develop features in `feature/*` branches
2. Create PRs to `develop` for integration
3. Create PRs from `develop` to `main` for releases

## Quality Gates
- Feature branches: Quick validation (5 min)
- Develop integration: Comprehensive testing (15 min)  
- Main releases: Production-level testing (25 min)

Delete this file after confirming the new workflow works correctly.
EOF

git add GITFLOW_SETUP.md
git commit -m "docs: add GitFlow setup confirmation file

This commit tests the new GitFlow workflow setup.
When pushed, it should trigger quick validation tests for feature branches."

echo "📝 Created test commit. Push with: git push -u origin feature/setup-gitflow-example"
echo "🧪 This will trigger the new feature development workflow for testing."