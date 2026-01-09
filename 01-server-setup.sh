#!/bin/bash
# Server Setup Script for STX Node Map on Hetzner
# Run this script on a fresh Ubuntu 22.04 or 24.04 server

set -e  # Exit on error

echo "=========================================="
echo "STX Node Map - Hetzner Server Setup"
echo "=========================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo" 
   exit 1
fi

# Update system
echo "Step 1: Updating system packages..."
apt-get update
apt-get upgrade -y

# Install required packages
echo "Step 2: Installing required packages..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    nginx \
    git \
    curl \
    build-essential \
    ufw \
    certbot \
    python3-certbot-nginx

# Install Node.js 18.x
echo "Step 3: Installing Node.js 18.x..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Install Yarn
echo "Step 4: Installing Yarn..."
npm install -g yarn

# Create application user
echo "Step 5: Creating application user..."
if ! id -u stx > /dev/null 2>&1; then
    useradd -r -m -s /bin/bash stx
    echo "User 'stx' created"
else
    echo "User 'stx' already exists"
fi

# Create application directories
echo "Step 6: Creating application directories..."
mkdir -p /opt/stx-node-map
mkdir -p /var/www/stx-node-map
mkdir -p /var/log/stx-node-map

# Set ownership
chown -R stx:stx /opt/stx-node-map
chown -R stx:stx /var/www/stx-node-map
chown -R stx:stx /var/log/stx-node-map

# Configure firewall
echo "Step 7: Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable

echo ""
echo "=========================================="
echo "Basic server setup completed!"
echo ""
echo "Next steps:"
echo "1. Clone the repository to /opt/stx-node-map/"
echo "2. Run the deployment script"
echo "=========================================="
