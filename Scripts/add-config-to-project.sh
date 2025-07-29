#!/bin/bash

# Script to add Config.swift to the Xcode project
# This is needed because Config.swift is auto-generated but not in the project

set -e

PROJECT_FILE="Anagram Game.xcodeproj"
CONFIG_FILE="Config/Config.swift"

echo "📁 Adding Config.swift to Xcode project..."

# Check if Config.swift exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config.swift not found at $CONFIG_FILE"
    echo "💡 Run ./Scripts/generate-config.sh first"
    exit 1
fi

# Use Ruby script to add file to project (Xcode project files are complex)
ruby << 'EOF'
require 'xcodeproj'

project_path = 'Anagram Game.xcodeproj'
config_file_path = 'Config/Config.swift'

# Open the project
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Check if file is already in project
existing_file = project.files.find { |f| f.path == config_file_path }

if existing_file.nil?
  # Add the file to the project
  file_ref = project.new_file(config_file_path)
  
  # Add to the target
  target.add_file_references([file_ref])
  
  # Save the project
  project.save
  
  puts "✅ Config.swift added to project successfully"
else
  puts "ℹ️  Config.swift is already in the project"
end
EOF

echo "🎉 Config.swift integration complete!"