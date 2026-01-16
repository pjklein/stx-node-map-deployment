#!/bin/bash
# Deployment Script for STX Node Map
# Run this script as the 'stx' user or with sudo

set -e  # Exit on error

# Get script directory and load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/hetzner-config.env"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Set defaults if not configured
GITHUB_USERNAME="${GITHUB_USERNAME:-your-username}"
REPO_NAME="${REPO_NAME:-stx-node-map-monorepo}"
REPO_URL="https://github.com/$GITHUB_USERNAME/$REPO_NAME.git"

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

# Function to run command with sudo, optionally as a different user
run_cmd() {
    local run_as_user=""
    
    # Check if -u flag is provided
    if [ "$1" = "-u" ]; then
        run_as_user="$2"
        shift 2
    fi
    
    if [ "$IS_ROOT" = true ]; then
        if [ -n "$run_as_user" ]; then
            sudo -u "$run_as_user" "$@"
        else
            "$@"
        fi
    else
        if [ -n "$run_as_user" ]; then
            sudo -u "$run_as_user" "$@"
        else
            sudo "$@"
        fi
    fi
}

check_root

# Clone or update repository
echo "Step 1: Cloning/updating repository..."
if [ -d "$APP_DIR/.git" ]; then
    echo "Repository exists, checking remote URL..."
    cd "$APP_DIR"
    CURRENT_URL=$(run_cmd -u stx git remote get-url origin 2>/dev/null || echo "")
    
    if [ "$CURRENT_URL" = "$REPO_URL" ]; then
        echo "Correct repository found, updating..."
        run_cmd -u stx git pull
    else
        echo "ERROR: $APP_DIR contains a different git repository!"
        echo "  Expected: $REPO_URL"
        echo "  Found:    $CURRENT_URL"
        echo ""
        echo "Please remove the contents and try again:"
        echo "  sudo rm -rf $APP_DIR/*"
        echo "  sudo rm -rf $APP_DIR/.git"
        exit 1
    fi
else
    echo "Cloning repository..."
    # Check if directory exists and is not empty
    if [ -d "$APP_DIR" ] && [ "$(ls -A $APP_DIR 2>/dev/null)" ]; then
        echo "ERROR: $APP_DIR is not empty. Please backup and remove contents first."
        echo "  sudo rm -rf $APP_DIR/*"
        exit 1
    fi
    
    # Ensure directory exists with correct ownership
    run_cmd mkdir -p "$APP_DIR"
    run_cmd chown stx:stx "$APP_DIR"
    
    # Clone the repository
    run_cmd -u stx git clone "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR"

# Verify we have the right repository structure
if [ ! -d "backend" ] || [ ! -d "frontend" ]; then
    echo "ERROR: Repository structure is incorrect!"
    echo "Expected directories 'backend' and 'frontend' in $APP_DIR"
    echo ""
    echo "Current contents of $APP_DIR:"
    ls -la "$APP_DIR"
    echo ""
    echo "Git remote URL:"
    run_cmd -u stx git remote get-url origin 2>/dev/null || echo "No git remote found"
    echo ""
    echo "Please check the repository structure matches the monorepo"
    exit 1
fi

# Backend setup
echo ""
echo "Step 2: Setting up backend..."
cd "$BACKEND_DIR"

# Verify requirements.txt exists
if [ ! -f "requirements.txt" ]; then
    echo "ERROR: requirements.txt not found in $BACKEND_DIR"
    echo ""
    echo "Current contents:"
    ls -la
    echo ""
    echo "Please verify the monorepo structure is correct"
    exit 1
fi

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
    
    # Copy from example if it exists
    if [ -f ".env.production.example" ]; then
        run_cmd -u stx cp .env.production.example .env.production
        echo "Copied from .env.production.example"
    else
        # Create basic version
        cat > .env.production.tmp << 'EOF'
REACT_APP_API_URL=/api
GENERATE_SOURCEMAP=false
EOF
        run_cmd -u stx mv .env.production.tmp .env.production
    fi
    
    # Update DOMAIN_NAME if configured
    if [ -n "$DOMAIN_NAME" ]; then
        echo "Updating .env.production with domain: $DOMAIN_NAME"
        # Update any REACT_APP_DOMAIN or similar variables
        run_cmd -u stx sed -i "s|REACT_APP_DOMAIN=.*|REACT_APP_DOMAIN=https://$DOMAIN_NAME|g" .env.production
        # Add if doesn't exist
        if ! grep -q "REACT_APP_DOMAIN" .env.production; then
            echo "REACT_APP_DOMAIN=https://$DOMAIN_NAME" >> .env.production
        fi
    fi
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
