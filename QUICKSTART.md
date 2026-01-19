# Quick Reference - Deploy STX Node Map to Hetzner

## 🚀 Quick Deploy (5 minutes)

### 1. Configure Hetzner Settings

```bash
cd /home/red/stx-infra/deployment
cp hetzner-config.env.example hetzner-config.env
nano hetzner-config.env
```

Required settings:

- `HETZNER_API_TOKEN` - Get from: <https://console.hetzner.com/> → Security → API Tokens
- `SSH_KEY_NAME` - Upload your SSH key first at: Security → SSH Keys
- `DOMAIN_NAME` - Your domain (e.g., your-domain.com)

### 2. Create the Server

```bash
# Install requests library if needed
pip3 install requests

# Run the creation script
./create-hetzner-server.py
```

### 3. Initial Setup (as root)

```bash
# SSH into server as root (Hetzner default)
ssh root@<SERVER_IP>

# Navigate to deployment directory
cd /tmp/deployment

# Run server setup (creates admin user)
SSH_KEY_NAME=pjklein ./01-server-setup.sh

# Logout from root
exit
```

### 4. Switch to Admin User

```bash
# SSH as the new admin user (pjklein)
ssh pjklein@<SERVER_IP>

# Navigate to deployment directory
cd /tmp/deployment
```

### 5. Deploy Application

```bash
# Run deployment with sudo (passwordless for pjklein)
sudo ./02-deploy.sh
```

### 6. Configure DNS

Point your domain's A record to the server IP:

```text
your-domain.com → <SERVER_IP>
```

Wait 5-30 minutes for DNS propagation.

### 7. Setup SSL Certificate

```bash
# From server as pjklein with sudo:
sudo ./03-setup-ssl.sh <SERVER_IP>
```

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

- Web: `https://your-domain.com`
- API: `https://your-domain.com/api/nodes`

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

```text
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

Edit the `hetzner-config.env` file to set your GitHub username:

```bash
GITHUB_USERNAME="your-username"
```

## 📚 Full Documentation

See [README-DEPLOYMENT.md](README-DEPLOYMENT.md) for complete documentation.
