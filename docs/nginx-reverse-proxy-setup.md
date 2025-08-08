# Nginx Reverse Proxy Setup for Wordshelf

## Overview
This document describes the nginx reverse proxy configuration that allows all Wordshelf services to be accessed through a single Cloudflare tunnel, eliminating the need for multiple tunnels and complex routing.

## Architecture

```
Internet → Cloudflare Tunnel → Nginx (port 80) → Service Routing
                                        ├── /api/* → Game Server (3000)
                                        ├── /socket.io/* → Game Server WebSocket
                                        ├── /dashboard/* → Web Dashboard (3001) 
                                        ├── /monitoring/* → Web Dashboard
                                        ├── /links/* → Link Generator (3002)
                                        └── /admin/* → Admin Service (3003)
```

## Configuration Files

### docker-compose.nginx.yml
The main Docker Compose configuration that includes:
- Nginx reverse proxy container
- All service containers (game-server, web-dashboard, link-generator, admin-service)
- PostgreSQL database
- Cloudflared tunnel container
- Shared network for inter-container communication

### nginx.conf
The nginx configuration that handles:
- Path-based routing to different services
- WebSocket upgrade for Socket.IO connections
- Static file serving for web interfaces
- Security headers and compression
- Proper proxy headers for client IP forwarding

## Key Features

### 1. Single Entry Point
All services are accessible through one Cloudflare tunnel URL, simplifying:
- iOS app configuration (only one base URL needed)
- SSL/TLS management (handled by Cloudflare)
- DNS and firewall configuration

### 2. WebSocket Support
Special handling for Socket.IO connections:
```nginx
location /socket.io/ {
    proxy_pass http://game-server;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    # Extended timeouts for persistent connections
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
}
```

### 3. Path Rewriting
Services expect to run at root path, so nginx rewrites URLs:
```nginx
location /dashboard {
    rewrite ^/dashboard(/.*)$ $1 break;
    proxy_pass http://web-dashboard;
}
```

### 4. Static File Handling
Proper content type handling and caching for static assets:
```nginx
location ~ ^/monitoring/.*\.(css|js|png|jpg|gif|ico)$ {
    proxy_pass http://web-dashboard$request_uri;
    expires 1h;
    add_header Cache-Control "public, immutable";
}
```

## Deployment

### Starting the Services
```bash
# Start all services with nginx reverse proxy
docker-compose -f docker-compose.nginx.yml up -d

# Check service health
docker-compose -f docker-compose.nginx.yml ps

# View logs
docker-compose -f docker-compose.nginx.yml logs -f
```

### Accessing Services

Once the Cloudflare tunnel is running, services are available at:
- Game API: `https://[tunnel-url]/api/`
- Web Dashboard: `https://[tunnel-url]/dashboard`
- Monitoring: `https://[tunnel-url]/monitoring`
- Link Generator: `https://[tunnel-url]/links`
- Admin Panel: `https://[tunnel-url]/admin`

### iOS App Configuration
Update NetworkConfiguration.swift with the tunnel URL:
```swift
let stagingConfig = EnvironmentConfig(
    host: "[tunnel-url]", 
    description: "Pi Staging Server (Cloudflare reverse proxy)"
)
```

## Troubleshooting

### Common Issues

1. **502 Bad Gateway**
   - Check if all services are running: `docker-compose -f docker-compose.nginx.yml ps`
   - Verify service names in nginx.conf match container names

2. **WebSocket Connection Failed**
   - Ensure WebSocket upgrade headers are properly configured
   - Check iOS app is using correct Socket.IO path

3. **Static Files Not Loading**
   - Verify static file routes in nginx.conf
   - Check file paths in service containers

### Debugging Commands
```bash
# Test internal connectivity
docker-compose -f docker-compose.nginx.yml exec nginx curl http://game-server:3000/api/status

# Check nginx configuration
docker-compose -f docker-compose.nginx.yml exec nginx nginx -t

# View nginx access logs
docker-compose -f docker-compose.nginx.yml logs nginx
```

## Security Considerations

1. **Rate Limiting**: Configured per-service with appropriate limits
2. **CORS**: Properly configured for mobile app access
3. **Headers**: Security headers added by nginx (X-Frame-Options, X-Content-Type-Options, etc.)
4. **SSL/TLS**: Handled by Cloudflare tunnel (always HTTPS)

## Maintenance

### Updating Services
```bash
# Rebuild a specific service
docker-compose -f docker-compose.nginx.yml build game-server

# Restart all services
docker-compose -f docker-compose.nginx.yml restart

# Update nginx configuration
# Edit nginx.conf, then:
docker-compose -f docker-compose.nginx.yml restart nginx
```

### Monitoring
- Check service health endpoints through reverse proxy
- Monitor Cloudflare tunnel status
- Use Web Dashboard at `/monitoring` for real-time metrics