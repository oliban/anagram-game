# Raspberry Pi Setup Guide for Anagram Game Server

## Prerequisites
- Raspberry Pi 4 (4GB+ RAM recommended)
- MicroSD card (32GB+) + USB SSD (optional but recommended)
- Ethernet connection (more stable than WiFi)
- Router access for port forwarding

## Step 1: Install Raspberry Pi OS

1. Download Raspberry Pi Imager: https://www.raspberrypi.com/software/
2. Choose "Raspberry Pi OS Lite (64-bit)" - no desktop needed
3. Configure before writing:
   - Set hostname: `anagram-pi`
   - Enable SSH
   - Set username/password
   - Configure WiFi (if not using ethernet)
4. Write to SD card and boot Pi

## Step 2: Initial Pi Configuration

SSH into your Pi:
```bash
ssh pi@raspberrypi.local
```

Update system:
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget htop
```

## Step 3: Install Docker & Docker Compose

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
logout  # Log out and back in for group changes

# Install Docker Compose
sudo apt install -y docker-compose
```

## Step 4: Setup Storage (Optional but Recommended)

If using USB SSD for better performance:
```bash
# List drives
lsblk

# Format SSD (replace sdX with your drive)
sudo mkfs.ext4 /dev/sdX1

# Mount SSD
sudo mkdir /mnt/ssd
sudo mount /dev/sdX1 /mnt/ssd

# Auto-mount on boot
echo "/dev/sdX1 /mnt/ssd ext4 defaults 0 0" | sudo tee -a /etc/fstab

# Move Docker data to SSD
sudo systemctl stop docker
sudo mv /var/lib/docker /mnt/ssd/
sudo ln -s /mnt/ssd/docker /var/lib/docker
sudo systemctl start docker
```

## Step 5: Setup Dynamic DNS

For external access without static IP:

1. Sign up at https://www.duckdns.org
2. Create a subdomain (e.g., `yourgame.duckdns.org`)
3. Install DuckDNS updater:

```bash
mkdir ~/duckdns
cd ~/duckdns
cat > duck.sh << 'EOF'
echo url="https://www.duckdns.org/update?domains=YOURDOMAIN&token=YOURTOKEN&ip=" | curl -k -o ~/duckdns/duck.log -K -
EOF

chmod +x duck.sh
# Add to crontab
(crontab -l 2>/dev/null; echo "*/5 * * * * ~/duckdns/duck.sh >/dev/null 2>&1") | crontab -
```

## Step 6: Clone and Configure Game

```bash
# Clone repository
cd ~
git clone https://github.com/yourusername/anagram-game.git
cd anagram-game

# Create environment file
cat > .env << 'EOF'
# Server Configuration
NODE_ENV=production
SERVER_URL=http://yourgame.duckdns.org:3000
DASHBOARD_URL=http://yourgame.duckdns.org:3001
LINK_GENERATOR_URL=http://yourgame.duckdns.org:3002
ADMIN_SERVICE_URL=http://yourgame.duckdns.org:3003

# Database
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your-secure-password
POSTGRES_DB=anagram_game
DATABASE_URL=postgresql://postgres:your-secure-password@postgres:5432/anagram_game

# Security
ADMIN_API_KEY=your-admin-key
SECURITY_RELAXED=false
LOG_SECURITY_EVENTS=true
EOF
```

## Step 7: Setup Firewall & Port Forwarding

On Pi:
```bash
# Install UFW firewall
sudo apt install ufw
sudo ufw allow ssh
sudo ufw allow 3000:3003/tcp  # Game services
sudo ufw allow 80/tcp          # Future nginx
sudo ufw allow 443/tcp         # Future HTTPS
sudo ufw enable
```

On Router:
- Forward ports 3000-3003 to Pi's internal IP
- Consider static DHCP reservation for Pi

## Step 8: Deploy Services

```bash
cd ~/anagram-game

# Build for ARM64
docker-compose -f docker-compose.services.yml build

# Start services
docker-compose -f docker-compose.services.yml up -d

# Check logs
docker-compose -f docker-compose.services.yml logs -f
```

## Step 9: Setup Monitoring & Maintenance

Create update script:
```bash
cat > ~/update-game.sh << 'EOF'
#!/bin/bash
cd ~/anagram-game
git pull
docker-compose -f docker-compose.services.yml down
docker-compose -f docker-compose.services.yml build
docker-compose -f docker-compose.services.yml up -d
docker system prune -f
EOF

chmod +x ~/update-game.sh
```

Setup automatic backups:
```bash
cat > ~/backup-game.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/mnt/ssd/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup database
docker-compose -f ~/anagram-game/docker-compose.services.yml exec -T postgres \
  pg_dump -U postgres anagram_game > $BACKUP_DIR/database.sql

# Keep only last 7 days
find /mnt/ssd/backups -type d -mtime +7 -exec rm -rf {} \;
EOF

chmod +x ~/backup-game.sh
# Add to crontab for daily backups
(crontab -l 2>/dev/null; echo "0 3 * * * ~/backup-game.sh >/dev/null 2>&1") | crontab -
```

## Step 10: Test Everything

```bash
# Check all services
curl http://localhost:3000/api/status
curl http://localhost:3001/api/status
curl http://localhost:3002/api/status
curl http://localhost:3003/api/status

# Test from external device
curl http://yourgame.duckdns.org:3000/api/status
```

## Optional: Setup Nginx Reverse Proxy

For cleaner URLs and HTTPS:
```bash
sudo apt install nginx certbot python3-certbot-nginx

# Configure nginx (create /etc/nginx/sites-available/anagram)
# Then get SSL certificate:
sudo certbot --nginx -d yourgame.duckdns.org
```

## Monitoring & Maintenance

- Check logs: `docker-compose -f ~/anagram-game/docker-compose.services.yml logs -f`
- Monitor resources: `htop`
- Check disk space: `df -h`
- Update game: `~/update-game.sh`
- Backup database: `~/backup-game.sh`

## Performance Tips

1. Use USB SSD for Docker volumes
2. Limit container memory if needed
3. Enable swap for stability:
```bash
sudo dphys-swapfile swapoff
sudo nano /etc/dphys-swapfile  # Set CONF_SWAPSIZE=2048
sudo dphys-swapfile setup
sudo dphys-swapfile swapon
```

## Troubleshooting

- **Services not accessible externally**: Check port forwarding and firewall
- **Out of memory**: Reduce container limits or add swap
- **Slow performance**: Move Docker to SSD, check SD card health
- **Connection refused**: Verify services are running with `docker ps`