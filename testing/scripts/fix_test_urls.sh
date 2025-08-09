#!/bin/bash

echo "🔄 Updating test URLs from localhost to current server configuration..."

# Find all test files and update URLs
find ../.. -name "*.js" -path "*/testing/*" -exec grep -l "localhost:3000" {} \; | while read file; do
    echo "  📝 Updating $file"
    
    # Update localhost URLs to use environment variable with fallback
    sed -i.bak 's|http://localhost:3000|${process.env.API_URL || '\''http://192.168.1.188:3000'\''}|g' "$file"
    sed -i.bak 's|ws://localhost:3000|${process.env.WS_URL || '\''ws://192.168.1.188:3000'\''}|g' "$file"
    
    # Update static URL assignments to use environment variables
    sed -i.bak 's|const SERVER_URL = '\''http://localhost:3000'\'';|const SERVER_URL = process.env.API_URL || '\''http://192.168.1.188:3000'\'';|g' "$file"
    sed -i.bak 's|const BASE_URL = '\''http://localhost:3000'\'';|const BASE_URL = process.env.API_URL || '\''http://192.168.1.188:3000'\'';|g' "$file"
    sed -i.bak 's|const WS_URL = '\''ws://localhost:3000'\'';|const WS_URL = process.env.WS_URL || '\''ws://192.168.1.188:3000'\'';|g' "$file"
    
    # Remove backup files
    rm -f "$file.bak"
done

echo "🔄 Updating /api/phrases endpoints to /api/phrases/create..."

# Fix API endpoint paths
find ../.. -name "*.js" -path "*/testing/*" -exec grep -l "/api/phrases[^/]" {} \; | while read file; do
    echo "  📝 Updating endpoints in $file"
    
    # Update phrase creation endpoint
    sed -i.bak 's|/api/phrases\([^/]\)|/api/phrases/create\1|g' "$file"
    
    # Remove backup files  
    rm -f "$file.bak"
done

echo "✅ URL updates complete! Test files now use environment-aware configuration."
echo "💡 Run tests with: API_URL=http://192.168.1.188:3000 node test_file.js"