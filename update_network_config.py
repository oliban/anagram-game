#!/usr/bin/env python3
"""
Update NetworkConfiguration.swift for different environments
Usage: python3 update_network_config.py <mode> [tunnel_url]
"""
import sys
import re

def update_network_config(mode, tunnel_url=None):
    """Update NetworkConfiguration.swift for the specified mode"""
    
    # Read the file
    with open('Models/Network/NetworkConfiguration.swift', 'r') as f:
        content = f.read()
    
    # Update environment setting - use flexible regex to match any current value
    if mode == 'staging':
        content = re.sub(
            r'let env = "[^"]*" // DEFAULT_ENVIRONMENT',
            'let env = "staging" // DEFAULT_ENVIRONMENT',
            content
        )
        
        # Update tunnel URL if provided
        if tunnel_url:
            # Remove https:// or http:// prefix
            tunnel_host = tunnel_url.replace('https://', '').replace('http://', '')
            content = re.sub(
                r'let stagingConfig = EnvironmentConfig\(host: "[^"]*"',
                f'let stagingConfig = EnvironmentConfig(host: "{tunnel_host}"',
                content
            )
    elif mode == 'aws':
        content = re.sub(
            r'let env = "[^"]*" // DEFAULT_ENVIRONMENT',
            'let env = "aws" // DEFAULT_ENVIRONMENT',
            content
        )
    elif mode == 'local':
        content = re.sub(
            r'let env = "[^"]*" // DEFAULT_ENVIRONMENT',
            'let env = "local" // DEFAULT_ENVIRONMENT',
            content
        )
    
    # Write the file back
    with open('Models/Network/NetworkConfiguration.swift', 'w') as f:
        f.write(content)
    
    print(f"✅ NetworkConfiguration.swift updated for {mode} mode")
    if mode == 'staging' and tunnel_url:
        print(f"   Tunnel host set to: {tunnel_url.replace('https://', '').replace('http://', '')}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 update_network_config.py <mode> [tunnel_url]")
        sys.exit(1)
    
    mode = sys.argv[1]
    tunnel_url = sys.argv[2] if len(sys.argv) > 2 else None
    
    update_network_config(mode, tunnel_url)