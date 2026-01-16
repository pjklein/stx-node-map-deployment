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

# Get SSH key name and user from environment or parameter
SSH_KEY_NAME="${SSH_KEY_NAME:-${1}}"
ADMIN_USER="${SSH_KEY_NAME}"

if [ -z "$ADMIN_USER" ]; then
    echo "ERROR: SSH_KEY_NAME not set and no parameter provided"
    echo "Usage: $0 <username>"
    echo "Or set SSH_KEY_NAME environment variable"
    exit 1
fi

echo "Admin user: $ADMIN_USER"

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
echo "Step 5: Creating application user 'stx'..."
if ! id -u stx > /dev/null 2>&1; then
    useradd -r -m -s /bin/bash stx
    echo "User 'stx' created"
else
    echo "User 'stx' already exists"
fi

# Create admin user with sudo access
echo "Step 6: Creating admin user '$ADMIN_USER'..."
if ! id -u "$ADMIN_USER" > /dev/null 2>&1; then
    # Create user with home directory
    useradd -m -s /bin/bash "$ADMIN_USER"
    
    # Add to sudo group
    usermod -aG sudo "$ADMIN_USER"
    
    # Allow passwordless sudo
    echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$ADMIN_USER
    chmod 0440 /etc/sudoers.d/$ADMIN_USER
    
    echo "User '$ADMIN_USER' created with sudo access"
else
    echo "User '$ADMIN_USER' already exists"
    # Ensure they have sudo
    usermod -aG sudo "$ADMIN_USER" 2>/dev/null || true
fi

# Set up SSH keys for admin user
echo "Step 7: Setting up SSH keys for $ADMIN_USER..."
mkdir -p /home/$ADMIN_USER/.ssh
chmod 700 /home/$ADMIN_USER/.ssh

# Copy authorized keys from root (Hetzner sets this up)
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/$ADMIN_USER/.ssh/authorized_keys
    chmod 600 /home/$ADMIN_USER/.ssh/authorized_keys
    chown -R $ADMIN_USER:$ADMIN_USER /home/$ADMIN_USER/.ssh
    echo "SSH keys copied from root"
fi

# Configure SSH for security
echo "Step 8: Configuring SSH security..."
SSH_CONFIG="/etc/ssh/sshd_config"

# Backup original config
cp $SSH_CONFIG ${SSH_CONFIG}.backup

# Disable root login
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' $SSH_CONFIG
# If line doesn't exist, add it
grep -q "^PermitRootLogin" $SSH_CONFIG || echo "PermitRootLogin no" >> $SSH_CONFIG

# Disable password authentication
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' $SSH_CONFIG
grep -q "^PasswordAuthentication" $SSH_CONFIG || echo "PasswordAuthentication no" >> $SSH_CONFIG

# Disable challenge-response authentication
sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' $SSH_CONFIG
grep -q "^ChallengeResponseAuthentication" $SSH_CONFIG || echo "ChallengeResponseAuthentication no" >> $SSH_CONFIG

# Enable public key authentication
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' $SSH_CONFIG
grep -q "^PubkeyAuthentication" $SSH_CONFIG || echo "PubkeyAuthentication yes" >> $SSH_CONFIG

echo "SSH configured: Root login disabled, password auth disabled, key-only access enabled"

# Create application directories
echo "Step 9: Creating application directories..."
mkdir -p /opt/stx-node-map
mkdir -p /var/www/stx-node-map
mkdir -p /var/log/stx-node-map

# Set ownership
chown -R stx:stx /opt/stx-node-map
chown -R stx:stx /var/www/stx-node-map
chown -R stx:stx /var/log/stx-node-map

# Configure firewall
echo "Step 10: Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable

# Restart SSH to apply security changes
echo "Step 11: Restarting SSH service..."
systemctl restart ssh
echo "SSH service restarted with new security settings"

echo ""
echo "=========================================="
echo "Basic server setup completed!"
echo "=========================================="
echo ""
echo "Security Configuration:"
echo "  ✓ Admin user '$ADMIN_USER' created with sudo access"
echo "  ✓ SSH key authentication enabled"
echo "  ✓ Root login disabled"
echo "  ✓ Password authentication disabled"
echo "  ✓ Application user 'stx' created"
echo ""
echo "IMPORTANT: Test SSH login as '$ADMIN_USER' BEFORE logging out of root!"
echo "  ssh $ADMIN_USER@<SERVER_IP>"
echo ""
echo ""
echo "Next steps:"
echo "1. Clone the repository to /opt/stx-node-map/"
echo "2. Run the deployment script"
echo "=========================================="
