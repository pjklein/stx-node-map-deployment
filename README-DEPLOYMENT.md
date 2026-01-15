# STX Node Map - Hetzner Deployment Guide

This guide covers deploying the STX Node Map application to a Hetzner Cloud server.

## Prerequisites

1. **Hetzner Cloud Account**: Sign up at [https://console.hetzner.com/](https://console.hetzner.com/)
2. **API Token**: Generate from Hetzner Console → Project → Security → API Tokens
3. **SSH Key**: Upload your SSH public key to Hetzner Console → Project → Security → SSH Keys

## Quick Start

### Option 1: Automated Server Creation (Python)

1. **Configure the deployment**:
   ```bash
   cd deployment
   cp hetzner-config.env.example hetzner-config.env
   nano hetzner-config.env  # Edit with your settings
   ```

2. **Install Python dependencies** (if using Python script):
   ```bash
   pip3 install requests
   ```

3. **Run the server creation script**:
   ```bash
   # Using Python (recommended)
   chmod +x create-hetzner-server.py
   ./create-hetzner-server.py
   
   # OR using Bash
   chmod +x create-hetzner-server.sh
   ./create-hetzner-server.sh
   ```

4. **The script will**:
   - Create a new server on Hetzner Cloud
   - Configure firewall rules
   - Save server information to `server-info.txt`
   - Optionally copy deployment files to the server

5. **SSH into the server**:
   ```bash
   ssh root@<SERVER_IP>
   ```

6. **Run the deployment**:
   ```bash
   cd /root/deployment
   ./01-server-setup.sh
   ./02-deploy.sh
   ```

### Option 2: Manual Server Creation

1. **Create server manually** in Hetzner Console:
   - Choose Ubuntu 22.04 or 24.04
   - Select server type (cx21 recommended for production)
   - Select location (Nuremberg, Falkenstein, or Helsinki for EU)
   - Add your SSH key
   - Configure firewall (ports 22, 80, 443)

2. **Copy deployment files**:
   ```bash
   scp -r deployment/ root@<SERVER_IP>:/root/
   ```

3. **SSH and deploy**:
   ```bash
   ssh root@<SERVER_IP>
   cd /root/deployment
   ./01-server-setup.sh
   ./02-deploy.sh
   ```

## Configuration Files

### hetzner-config.env

Configure your Hetzner deployment:

```bash
# API Token from Hetzner Console
HETZNER_API_TOKEN="your-token-here"

# Server configuration
SERVER_NAME="stx-node-map-prod"
SERVER_TYPE="cx21"              # 2 vCPU, 4GB RAM
SERVER_LOCATION="nbg1"          # Nuremberg
SERVER_IMAGE="ubuntu-22.04"
SSH_KEY_NAME="my-ssh-key"       # Must exist in Hetzner
ENABLE_FIREWALL="true"
ENABLE_BACKUPS="false"
```

### Server Types

| Type | vCPU | RAM | Disk | Price/month |
|------|------|-----|------|-------------|
| cx11 | 1 | 2 GB | 20 GB | ~€3.79 |
| cx21 | 2 | 4 GB | 40 GB | ~€5.83 |
| cx31 | 2 | 8 GB | 80 GB | ~€11.05 |
| cx41 | 4 | 16 GB | 160 GB | ~€21.50 |

**Recommended**: `cx21` for production (handles ~1000 concurrent users)

### Locations

- `nbg1` - Nuremberg, Germany
- `fsn1` - Falkenstein, Germany  
- `hel1` - Helsinki, Finland
- `ash` - Ashburn, USA

## Deployment Scripts

### 01-server-setup.sh

Initial server configuration:
- Updates system packages
- Installs Python 3, Node.js 18, Nginx
- Creates application user and directories
- Configures firewall (UFW)

**Usage**:
```bash
sudo ./01-server-setup.sh
```

### 02-deploy.sh

Application deployment:
- Clones/updates repository
- Sets up Python virtual environment
- Installs backend dependencies
- Builds frontend (React)
- Configures systemd services
- Configures Nginx
- Starts all services

**Usage**:
```bash
sudo ./02-deploy.sh
```

## Architecture

```
Internet
    ↓
  Nginx (Port 80/443)
    ├── / → Frontend (React static files)
    └── /api → Backend (Gunicorn + Flask)
              ↓
         STX Node Map API (Port 8089)
              ↓
         Discoverer Service (Background)
```

## Services

### API Service
- **Service**: `stx-node-map-api`
- **Port**: 8089 (internal)
- **Workers**: 4 Gunicorn workers
- **Auto-restart**: Yes

**Commands**:
```bash
systemctl status stx-node-map-api
systemctl restart stx-node-map-api
journalctl -u stx-node-map-api -f
```

### Discoverer Service
- **Service**: `stx-node-map-discoverer`
- **Function**: Scans network for STX nodes
- **Runs**: Continuously in background
- **Auto-restart**: Yes

**Commands**:
```bash
systemctl status stx-node-map-discoverer
systemctl restart stx-node-map-discoverer
journalctl -u stx-node-map-discoverer -f
```

### Nginx
- **Serves**: Frontend static files
- **Proxies**: API requests to backend
- **Port**: 80 (HTTP), 443 (HTTPS with SSL)

**Commands**:
```bash
systemctl status nginx
systemctl restart nginx
nginx -t  # Test configuration
tail -f /var/log/nginx/stx-node-map-*.log
```

## SSL/HTTPS Setup

After deployment, set up SSL with Let's Encrypt:

```bash
# Install certbot (already done by 01-server-setup.sh)

# Get certificate (replace with your domain)
certbot --nginx -d your-domain.com

# Auto-renewal is configured automatically
```

Update DNS:
```
A Record: your-domain.com → <SERVER_IP>
```

## Monitoring & Logs

### Application Logs
```bash
# API logs
tail -f /var/log/stx-node-map/api-access.log
tail -f /var/log/stx-node-map/api-error.log

# Discoverer logs
tail -f /var/log/stx-node-map/discoverer.log

# All logs
tail -f /var/log/stx-node-map/*.log
```

### System Logs
```bash
# API service
journalctl -u stx-node-map-api -f

# Discoverer service
journalctl -u stx-node-map-discoverer -f

# Nginx
journalctl -u nginx -f
```

### Check Service Status
```bash
systemctl status stx-node-map-api
systemctl status stx-node-map-discoverer
systemctl status nginx
```

## Updating the Application

```bash
cd /opt/stx-node-map
sudo -u stx git pull
cd /root/deployment
sudo ./02-deploy.sh
```

## Troubleshooting

### API not responding
```bash
# Check service status
systemctl status stx-node-map-api

# Check logs
journalctl -u stx-node-map-api -n 50

# Restart service
systemctl restart stx-node-map-api
```

### Frontend not loading
```bash
# Check Nginx status
systemctl status nginx

# Test Nginx config
nginx -t

# Check Nginx logs
tail -f /var/log/nginx/stx-node-map-error.log

# Restart Nginx
systemctl restart nginx
```

### Discoverer not running
```bash
# Check service
systemctl status stx-node-map-discoverer

# View logs
journalctl -u stx-node-map-discoverer -n 50

# Restart
systemctl restart stx-node-map-discoverer
```

## Cost Estimation

**Monthly Costs** (approximate):
- Server (cx21): €5.83
- Backups (optional): €1.17
- Traffic: Free (20TB included)
- **Total**: ~€6-7/month

## Security Considerations

1. **Firewall**: Only ports 22, 80, 443 open
2. **SSH**: Key-based authentication only
3. **Services**: Running as non-root user (`stx`)
4. **Updates**: Regular system updates recommended
5. **SSL**: Use HTTPS in production (Let's Encrypt)

## Performance Tuning

### For higher traffic:
1. Increase Gunicorn workers in `stx-node-map-api.service`
2. Upgrade to larger server type (cx31 or cx41)
3. Enable Nginx caching for static assets
4. Consider adding a CDN for static files

### For better response times:
1. Choose server location closest to users
2. Enable Nginx gzip compression (already configured)
3. Use HTTP/2 with SSL

## Support

- **Hetzner Docs**: https://docs.hetzner.com/
- **Hetzner API**: https://docs.hetzner.cloud/
- **Project Repository**: Update with your repo URL

## License

MIT
