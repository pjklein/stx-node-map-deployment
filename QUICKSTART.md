# Quick Reference - Deploy STX Node Map to Hetzner

## 🚀 Quick Deploy (5 minutes)

### 1. Configure Hetzner Settings
```bash
cd /home/red/stx-infra/deployment
cp hetzner-config.env.example hetzner-config.env
nano hetzner-config.env
```

Required settings:
- `HETZNER_API_TOKEN` - Get from: https://console.hetzner.cloud/ → Security → API Tokens
- `SSH_KEY_NAME` - Upload your SSH key first at: Security → SSH Keys
- `DOMAIN_NAME` - Your domain (e.g., stacks-node-map.evanidanim.com)

### 2. Create the Server (Python - Recommended)
```bash
# Install requests library if needed
pip3 install requests

# Run the creation script
./create-hetzner-server.py
```

OR using Bash:
```bash
# Requires: curl, jq
sudo apt-get install -y curl jq  # If not installed
./create-hetzner-server.sh
```

### 3. Deploy the Application
```bash
# The script will offer to copy files automatically
# If you chose 'yes', SSH into server:
ssh root@<SERVER_IP>

# Run deployment
cd /root/deployment
./01-server-setup.sh
./02-deploy.sh
```

### 4. Configure DNS
Point your domain's A record to the server IP:
```
stacks-node-map.evanidanim.com → <SERVER_IP>
```

Wait 5-30 minutes for DNS propagation.

### 5. Setup SSL Certificate
```bash
# From the deployment directory on your local machine (or the server):
sudo ./03-setup-ssl.sh
```

This will:
- ✅ Get a Let's Encrypt wildcard certificate
- ✅ Configure Nginx to use it
- ✅ Setup auto-renewal
- ✅ Redirect HTTP → HTTPS

### 6. Access Your Application
- Web: `https://stacks-node-map.evanidanim.com`
- API: `https://stacks-node-map.evanidanim.com/api/nodes`

## 📋 What Gets Created

- **Server**: Ubuntu 22.04 on Hetzner Cloud (cx21 = 4GB RAM)
- **Firewall**: Ports 22 (SSH), 80 (HTTP), 443 (HTTPS)
- **Services**:
  - Nginx (web server + reverse proxy)
  - Gunicorn (Python WSGI server, 4 workers)
  - STX Node Map API (Flask app)
  - STX Node Discoverer (background service)

## 🔧 Common Commands

### Check Service Status
```bash
systemctl status stx-node-map-api
systemctl status stx-node-map-discoverer
systemctl status nginx
```

### View Logs
```bash
journalctl -u stx-node-map-api -f
journalctl -u stx-node-map-discoverer -f
tail -f /var/log/stx-node-map/*.log
```

### Restart Services
```bash
systemctl restart stx-node-map-api
systemctl restart stx-node-map-discoverer
systemctl restart nginx
```

### Update Application
```bash
cd /opt/stx-node-map
sudo -u stx git pull
cd /root/deployment
sudo ./02-deploy.sh
```

### SSL Certificate Management
```bash
# View all certificates
sudo certbot certificates

# Renew all certificates now (usually automatic)
sudo certbot renew

# Check renewal status
sudo certbot renew --dry-run

# View certificate details
openssl x509 -in /etc/letsencrypt/live/DOMAIN/fullchain.pem -text -noout
```

## 💰 Cost
- **cx21 Server**: ~€5.83/month
- **Traffic**: Free (20TB included)
- **Total**: ~€6/month

## 📁 File Structure on Server

```
/opt/stx-node-map/          # Application code
├── backend/                # Python Flask API
│   ├── .venv/             # Python virtual environment
│   ├── run.py
│   └── requirements.txt
└── frontend/              # React app (built)

/var/www/stx-node-map/     # Nginx serves from here
└── (Frontend build files)

/var/log/stx-node-map/     # Application logs
├── api-access.log
├── api-error.log
└── discoverer.log

/etc/systemd/system/       # Service definitions
├── stx-node-map-api.service
└── stx-node-map-discoverer.service

/etc/nginx/sites-available/ # Nginx config
└── stx-node-map
```

## 🛠️ Troubleshooting

### API not responding
```bash
systemctl status stx-node-map-api
journalctl -u stx-node-map-api -n 50
systemctl restart stx-node-map-api
```

### Frontend not loading
```bash
nginx -t  # Test config
systemctl restart nginx
tail -f /var/log/nginx/stx-node-map-error.log
```

### Need to update repository URL in deploy script
Edit line 9 in `02-deploy.sh`:
```bash
REPO_URL="https://github.com/YOUR_USERNAME/stx-node-map-monorepo.git"
```

## 📚 Full Documentation

See [README-DEPLOYMENT.md](README-DEPLOYMENT.md) for complete documentation.
