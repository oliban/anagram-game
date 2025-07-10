#!/bin/bash

# Anagram Game Server Setup Script
# This script automates the setup process for new environments

set -e  # Exit on any error

echo "🎯 Anagram Game Server Setup"
echo "============================"

# Check if we're in the server directory
if [ ! -f "package.json" ]; then
    echo "❌ Error: Please run this script from the server directory"
    exit 1
fi

echo "📦 Installing Node.js dependencies..."
npm install

echo "📚 Generating API documentation..."
npm run docs

echo "⚙️ Setting up environment variables..."
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo "✅ Created .env file from .env.example"
        echo "⚠️  Please edit .env file with your database credentials before starting the server"
    else
        echo "❌ Error: .env.example file not found"
        exit 1
    fi
else
    echo "ℹ️  .env file already exists"
fi

echo "🗄️ Database setup instructions:"
echo "   1. Make sure PostgreSQL is running"
echo "   2. Create a database for the anagram game"
echo "   3. Run: psql -U <DB_USER> -d <DB_NAME> -f database/schema.sql"
echo "   4. Update .env file with your database credentials"

echo ""
echo "🚀 Setup complete! To start the server:"
echo "   npm start"
echo ""
echo "📚 API Documentation will be available at:"
echo "   http://localhost:3000/api/docs (or your configured port)"
echo ""
echo "🔧 Don't forget to:"
echo "   - Edit .env file with your database settings"
echo "   - Initialize your database with schema.sql"
echo ""

