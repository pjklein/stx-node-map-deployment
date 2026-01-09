#!/bin/bash
# Deployment Script for STX Node Map
# Run this script as the 'stx' user or with sudo

set -e  # Exit on error

REPO_URL="https://github.com/YOUR_USERNAME/stx-node-map-monorepo.git"  # Update this!
APP_DIR="/opt/stx-node-map"
FRONTEND_BUILD_DIR="$APP_DIR/frontend/build"
WEB_DIR="/var/www/stx-node-map"
BACKEND_DIR="$APP_DIR/backend"
LOG_DIR="/var/log/stx-node-map"

echo "=========================================="
echo "STX Node Map - Deployment Script"
echo "=========================================="
echo ""

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        IS_ROOT=true
    else
        IS_ROOT=false
    fi
}

# Function to run command with sudo if not root
run_cmd() {
    if [ "$IS_ROOT" = true ]; then
        "$@"
    else
        sudo "$@"
    fi
}

check_root

# Clone or update repository
echo "Step 1: Cloning/updating repository..."
if [ -d "$APP_DIR/.git" ]; then
    echo "Repository exists, updating..."
    cd "$APP_DIR"
    run_cmd -u stx git pull
else
    echo "Cloning repository..."
    if [ -z "$(ls -A $APP_DIR 2>/dev/null)" ]; then
        run_cmd -u stx git clone "$REPO_URL" "$APP_DIR"
    else
        echo "ERROR: $APP_DIR is not empty. Please backup and remove contents first."
        exit 1
    fi
fi

cd "$APP_DIR"

# Backend setup
echo ""
echo "Step 2: Setting up backend..."
cd "$BACKEND_DIR"

# Create virtual environment
if [ ! -d ".venv" ]; then
    echo "Creating Python virtual environment..."
    run_cmd -u stx python3 -m venv .venv
fi

# Install Python dependencies
echo "Installing Python dependencies..."
run_cmd -u stx .venv/bin/pip install --upgrade pip
run_cmd -u stx .venv/bin/pip install -r requirements.txt

# Create env file if it doesn't exist
if [ ! -f "env.sh" ]; then
    echo "Creating env.sh..."
    cat > env.sh.tmp << 'EOF'
#!/bin/bash
export NETWORK="mainnet"
EOF
    run_cmd -u stx mv env.sh.tmp env.sh
    run_cmd -u stx chmod +x env.sh
fi

# Initialize data.json if it doesn't exist
if [ ! -f "data.json" ]; then
    echo "Initializing data.json..."
    echo "[]" > data.json.tmp
    run_cmd -u stx mv data.json.tmp data.json
fi

# Initialize status.json if it doesn't exist
if [ ! -f "status.json" ]; then
    echo "Initializing status.json..."
    cat > status.json.tmp << 'EOF'
{
    "status": "Initializing",
    "nodes_count": 0,
    "scanning": false,
    "last_scan": null,
    "timestamp": null
}
EOF
    run_cmd -u stx mv status.json.tmp status.json
fi

# Frontend setup
echo ""
echo "Step 3: Setting up frontend..."
cd "$APP_DIR/frontend"

# Create production .env file
if [ ! -f ".env.production" ]; then
    echo "Creating .env.production..."
    cat > .env.production.tmp << 'EOF'
REACT_APP_API_URL=/api
GENERATE_SOURCEMAP=false
EOF
    run_cmd -u stx mv .env.production.tmp .env.production
fi

# Install dependencies
echo "Installing Node.js dependencies..."
run_cmd -u stx yarn install

# Build frontend
echo "Building frontend..."
run_cmd -u stx yarn build

# Deploy frontend build to web directory
echo "Deploying frontend to $WEB_DIR..."
run_cmd rm -rf "$WEB_DIR"/*
run_cmd cp -r "$FRONTEND_BUILD_DIR"/* "$WEB_DIR/"
run_cmd chown -R www-data:www-data "$WEB_DIR"

# Install systemd services
echo ""
echo "Step 4: Installing systemd services..."
run_cmd cp "$APP_DIR/../deployment/stx-node-map-api.service" /etc/systemd/system/ 2>/dev/null || \
    run_cmd cp /opt/stx-node-map/deployment/stx-node-map-api.service /etc/systemd/system/ 2>/dev/null || \
    echo "Warning: Could not find systemd service file. Please copy manually."

run_cmd cp "$APP_DIR/../deployment/stx-node-map-discoverer.service" /etc/systemd/system/ 2>/dev/null || \
    run_cmd cp /opt/stx-node-map/deployment/stx-node-map-discoverer.service /etc/systemd/system/ 2>/dev/null || \
    echo "Warning: Could not find discoverer service file."

# Install nginx configuration
echo ""
echo "Step 5: Installing nginx configuration..."
run_cmd cp "$APP_DIR/../deployment/nginx-stx-node-map.conf" /etc/nginx/sites-available/stx-node-map 2>/dev/null || \
    run_cmd cp /opt/stx-node-map/deployment/nginx-stx-node-map.conf /etc/nginx/sites-available/stx-node-map 2>/dev/null || \
    echo "Warning: Could not find nginx config file."

# Enable nginx site
if [ -f /etc/nginx/sites-available/stx-node-map ]; then
    run_cmd ln -sf /etc/nginx/sites-available/stx-node-map /etc/nginx/sites-enabled/
    run_cmd rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx configuration
    echo "Testing nginx configuration..."
    run_cmd nginx -t
fi

# Reload systemd
echo ""
echo "Step 6: Reloading systemd and starting services..."
run_cmd systemctl daemon-reload

# Start and enable services
echo "Starting API service..."
run_cmd systemctl enable stx-node-map-api
run_cmd systemctl restart stx-node-map-api

echo "Starting discoverer service..."
run_cmd systemctl enable stx-node-map-discoverer
run_cmd systemctl restart stx-node-map-discoverer

# Restart nginx
echo "Restarting nginx..."
run_cmd systemctl restart nginx

# Check service status
echo ""
echo "=========================================="
echo "Deployment completed!"
echo "=========================================="
echo ""
echo "Service Status:"
echo "---------------"
run_cmd systemctl status stx-node-map-api --no-pager -l || true
echo ""
run_cmd systemctl status stx-node-map-discoverer --no-pager -l || true
echo ""
run_cmd systemctl status nginx --no-pager -l || true
echo ""
echo "=========================================="
echo "To view logs:"
echo "  API logs:        journalctl -u stx-node-map-api -f"
echo "  Discoverer logs: journalctl -u stx-node-map-discoverer -f"
echo "  Nginx logs:      tail -f /var/log/nginx/stx-node-map-*.log"
echo "  App logs:        tail -f /var/log/stx-node-map/*.log"
echo "=========================================="
