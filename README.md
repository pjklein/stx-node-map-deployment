# STX Node Map - Hetzner Deployment

Automated deployment scripts and configuration for deploying the STX Node Map application to Hetzner Cloud.

## 🚀 Quick Start

1. **Setup configuration**:

   ```bash
   cp hetzner-config.env.example hetzner-config.env
   nano hetzner-config.env  # Add your Hetzner API token
   ```

2. **Create server**:

   ```bash
   # Install Python dependencies
   pip3 install requests
   
   # Run the creation script
   ./create-hetzner-server.py
   ```

3. **Initial setup (as root)**:

   ```bash
   # SSH into the created server as root
   ssh root@<SERVER_IP>
   
   # Run server setup
   cd /tmp/deployment
   SSH_KEY_NAME=pjklein ./01-server-setup.sh
   ```

4. **Switch to admin user**:

   ```bash
   # SSH as the new admin user (pjklein)
   # Logout from root first
   exit
   
   ssh pjklein@<SERVER_IP>
   ```

5. **Deploy application (as admin user)**:

   ```bash
   cd /tmp/deployment
   sudo ./02-deploy.sh
   ```

## 📁 Files

- `create-hetzner-server.py` - Python script to create Hetzner server via API
- `hetzner-config.env.example` - Configuration template
- `01-server-setup.sh` - Initial server setup (packages, users, firewall)
- `02-deploy.sh` - Application deployment script
- `nginx-stx-node-map.conf` - Nginx configuration
- `stx-node-map-api.service` - Systemd service for API (Gunicorn)
- `stx-node-map-discoverer.service` - Systemd service for node discoverer

## 📚 Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Quick reference guide
- **[README-DEPLOYMENT.md](README-DEPLOYMENT.md)** - Complete deployment documentation

## 🔑 Prerequisites

1. **Hetzner Cloud Account**: <https://console.hetzner.com/>
2. **API Token**: Console → Project → Security → API Tokens
3. **SSH Key**: Upload at Console → Project → Security → SSH Keys

## 💰 Cost

- **Server (cx21)**: ~€5.83/month (4GB RAM, 2 vCPU)
- **Traffic**: Free (20TB included)
- **Total**: ~€6/month

## 🛠️ Tech Stack

- **Server**: Ubuntu 22.04 on Hetzner Cloud
- **Web Server**: Nginx
- **API Server**: Gunicorn (4 workers) + Flask
- **Frontend**: React (static build)
- **Background**: Node discoverer service

## 📝 License

MIT
