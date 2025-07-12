#!/bin/bash

# Read PORT from server/.env
if [ -f "server/.env" ]; then
    PORT=$(grep "^PORT=" server/.env | cut -d'=' -f2)
else
    PORT=3000  # Default fallback
fi

# Create Config.swift file
cat > "Config/Config.swift" << EOF
// Auto-generated configuration file
// Do not edit manually - this file is generated from server/.env

import Foundation

struct Config {
    static let serverPort = "$PORT"
    static let baseURL = "http://localhost:\(serverPort)"
}
EOF

echo "Generated Config.swift with PORT=$PORT"