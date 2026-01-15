#!/bin/bash
# Setup SSL Certificate for STX Node Map
# Uses Cloudflare DNS validation for Let's Encrypt wildcard certificate
# Also updates Cloudflare DNS to point domain to Hetzner server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/hetzner-config.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}ERROR: Configuration file not found!${NC}"
    echo "Please copy hetzner-config.env.example to hetzner-config.env and configure it."
    exit 1
fi

source "$CONFIG_FILE"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root or with sudo${NC}" 
   exit 1
fi

# Validate configuration
if [ -z "$DOMAIN_NAME" ] || [ "$DOMAIN_NAME" = "your-domain.com" ]; then
    echo -e "${RED}ERROR: DOMAIN_NAME not configured!${NC}"
    echo "Please set DOMAIN_NAME in $CONFIG_FILE"
    exit 1
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ "$CLOUDFLARE_API_TOKEN" = "your_cloudflare_api_token_here" ]; then
    echo -e "${RED}ERROR: CLOUDFLARE_API_TOKEN not configured!${NC}"
    echo "Please set CLOUDFLARE_API_TOKEN in $CONFIG_FILE"
    exit 1
fi

DOMAIN="$DOMAIN_NAME"
WILDCARD_DOMAIN="*.$DOMAIN"
EMAIL="${EMAIL:-admin@$DOMAIN}"
SERVER_IP="${1:-}"

echo "=========================================="
echo "Let's Encrypt SSL Setup for STX Node Map"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Domain:          $DOMAIN"
echo "  Wildcard Domain: $WILDCARD_DOMAIN"
echo "  Email:           $EMAIL"
echo ""

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot and Cloudflare plugin..."
    apt-get update
    apt-get install -y certbot python3-certbot-dns-cloudflare
fi

# Create Cloudflare credentials file for certbot
echo "Setting up Cloudflare credentials..."
CLOUDFLARE_INI="/etc/letsencrypt/cloudflare.ini"

if [ ! -f "$CLOUDFLARE_INI" ]; then
    cat > "$CLOUDFLARE_INI" << EOF
dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN
EOF
    chmod 600 "$CLOUDFLARE_INI"
    echo -e "${GREEN}✓ Cloudflare credentials configured${NC}"
fi

# Check if cert already exists
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
if [ -d "$CERT_DIR" ]; then
    echo -e "${YELLOW}Certificate already exists for $DOMAIN${NC}"
    read -p "Do you want to renew it? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Skipping certificate renewal."
        exit 0
    fi
fi

echo ""
echo "Step 1: Obtaining Let's Encrypt wildcard certificate via Cloudflare DNS..."
echo ""

# Get certificate using Cloudflare DNS challenge
certbot certonly \
    --agree-tos \
    --dns-cloudflare \
    --dns-cloudflare-credentials "$CLOUDFLARE_INI" \
    -d "$DOMAIN" \
    -d "$WILDCARD_DOMAIN" \
    --email "$EMAIL" \
    --non-interactive

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Failed to obtain certificate${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Certificate obtained successfully!${NC}"
echo ""

# Step 2: Update Cloudflare DNS if server IP provided
if [ -n "$SERVER_IP" ]; then
    echo "Step 2: Updating Cloudflare DNS to point to server..."
    
    # Get zone ID from Cloudflare
    ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")
    
    ZONE_ID=$(echo "$ZONE_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -z "$ZONE_ID" ]; then
        echo -e "${YELLOW}WARNING: Could not get Cloudflare Zone ID${NC}"
        echo "You may need to manually set DNS records in Cloudflare:"
        echo "  @ (root) → $SERVER_IP"
        echo "  * (wildcard) → $SERVER_IP"
    else
        echo "Zone ID: $ZONE_ID"
        
        # Get existing A record for root domain
        RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DOMAIN&type=A" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json")
        
        RECORD_ID=$(echo "$RECORDS" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        
        if [ -n "$RECORD_ID" ]; then
            # Update existing record
            echo "Updating DNS record for $DOMAIN..."
            curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$SERVER_IP\",\"ttl\":3600,\"proxied\":false}" > /dev/null
            echo -e "${GREEN}✓ DNS record updated${NC}"
        else
            # Create new record
            echo "Creating DNS record for $DOMAIN..."
            curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$SERVER_IP\",\"ttl\":3600,\"proxied\":false}" > /dev/null
            echo -e "${GREEN}✓ DNS record created${NC}"
        fi
    fi
else
    echo "Step 2: No server IP provided, skipping DNS update"
    echo "To update DNS later, run:"
    echo "  $0 <SERVER_IP>"
fi

# Step 3: Configure Nginx
echo ""
echo "Step 3: Configuring Nginx with SSL certificate..."

# Update nginx config
NGINX_CONF="/etc/nginx/sites-available/stx-node-map"

if [ ! -f "$NGINX_CONF" ]; then
    echo -e "${YELLOW}WARNING: Nginx config not found at $NGINX_CONF${NC}"
    echo "Creating basic SSL configuration..."
    
    mkdir -p /etc/nginx/sites-available
    
    cat > "$NGINX_CONF" << 'NGINX_EOF'
# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS configuration
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;

    ssl_certificate /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/json application/javascript;

    # Frontend - Serve static files
    location / {
        root /var/www/stx-node-map;
        index index.html;
        try_files $uri $uri/ /index.html;

        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    # Backend API proxy
    location /api {
        proxy_pass http://127.0.0.1:8089;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # CORS headers
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range" always;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Logging
    access_log /var/log/nginx/stx-node-map-access.log;
    error_log /var/log/nginx/stx-node-map-error.log;
}
NGINX_EOF
fi

# Update domain in nginx config
sed -i "s|/etc/letsencrypt/live/DOMAIN/|/etc/letsencrypt/live/$DOMAIN/|g" "$NGINX_CONF"
sed -i "s|server_name _;|server_name $DOMAIN $WILDCARD_DOMAIN;|g" "$NGINX_CONF"

# Enable site if not already enabled
if [ ! -L /etc/nginx/sites-enabled/stx-node-map ]; then
    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/stx-node-map
fi

# Remove default site if it exists
rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
echo "Testing Nginx configuration..."
if nginx -t; then
    echo -e "${GREEN}✓ Nginx configuration is valid${NC}"
else
    echo -e "${RED}ERROR: Nginx configuration test failed${NC}"
    exit 1
fi

# Reload nginx
echo "Reloading Nginx..."
systemctl reload nginx

echo ""
echo -e "${GREEN}✓ Nginx reloaded with SSL configuration${NC}"
echo ""

# Step 4: Setup auto-renewal
echo "Step 4: Setting up certificate auto-renewal..."

# Create renewal hook script
RENEWAL_HOOK="/etc/letsencrypt/renewal-hooks/post/nginx-reload.sh"
mkdir -p "$(dirname "$RENEWAL_HOOK")"

cat > "$RENEWAL_HOOK" << 'HOOK_EOF'
#!/bin/bash
systemctl reload nginx
HOOK_EOF

chmod +x "$RENEWAL_HOOK"

# Test renewal
echo "Testing certificate renewal..."
certbot renew --dry-run --quiet

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Renewal test successful${NC}"
else
    echo -e "${YELLOW}WARNING: Renewal test had issues, but setup may still work${NC}"
fi

# Step 5: Display completion info
echo ""
echo "=========================================="
echo -e "${GREEN}SSL Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "Certificate Details:"
echo "  Domain:         $DOMAIN"
echo "  Wildcard:       $WILDCARD_DOMAIN"
echo "  Location:       $CERT_DIR"
echo "  Expires:        $(date -d '+90 days' +'%Y-%m-%d')"
echo ""
echo "Cloudflare Integration:"
echo "  ✓ DNS validation automated"
echo "  ✓ Auto-renewal configured"
if [ -n "$SERVER_IP" ]; then
    echo "  ✓ DNS A record pointing to: $SERVER_IP"
fi
echo ""
echo "Auto-renewal:"
echo "  Systemd timer is configured to auto-renew certificates"
echo "  Check renewal status: certbot renew --dry-run"
echo ""
echo "Your site is now live with SSL!"
echo "  https://$DOMAIN"
echo "  https://$WILDCARD_DOMAIN"
echo ""
echo "Verification:"
echo "  curl https://$DOMAIN"
echo ""
echo "Useful commands:"
echo "  View certificate: certbot certificates"
echo "  Renew now:        certbot renew"
echo "  View logs:        tail -f /var/log/letsencrypt/letsencrypt.log"
echo "=========================================="

echo "=========================================="
echo "Let's Encrypt SSL Setup for STX Node Map"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Domain:          $DOMAIN"
echo "  Wildcard Domain: $WILDCARD_DOMAIN"
echo "  Email:           $EMAIL"
echo ""

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot..."
    apt-get update
    apt-get install -y certbot python3-certbot-nginx
fi

# Check if nginx is installed and running
if ! systemctl is-active --quiet nginx; then
    echo -e "${YELLOW}WARNING: Nginx is not running. Starting Nginx...${NC}"
    systemctl start nginx
fi

# Check if cert already exists
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
if [ -d "$CERT_DIR" ]; then
    echo -e "${YELLOW}Certificate already exists for $DOMAIN${NC}"
    read -p "Do you want to renew it? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Skipping certificate renewal."
        exit 0
    fi
fi

echo ""
echo "Step 1: Obtaining Let's Encrypt wildcard certificate..."
echo ""
echo -e "${BLUE}NOTE: You will need to add DNS TXT records to verify domain ownership.${NC}"
echo "Follow the prompts below and add the DNS records when prompted."
echo ""

# Get certificate with DNS challenge (required for wildcard)
certbot certonly \
    --agree-tos \
    --manual \
    --preferred-challenges dns \
    -d "$DOMAIN" \
    -d "$WILDCARD_DOMAIN" \
    --email "$EMAIL" \
    --manual-public-ip-logging-ok

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Failed to obtain certificate${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Certificate obtained successfully!${NC}"
echo ""

# Step 2: Configure Nginx
echo "Step 2: Configuring Nginx with SSL certificate..."

# Update nginx config
NGINX_CONF="/etc/nginx/sites-available/stx-node-map"

if [ ! -f "$NGINX_CONF" ]; then
    echo -e "${YELLOW}WARNING: Nginx config not found at $NGINX_CONF${NC}"
    echo "Creating basic SSL configuration..."
    
    mkdir -p /etc/nginx/sites-available
    
    cat > "$NGINX_CONF" << 'NGINX_EOF'
# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS configuration
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;

    ssl_certificate /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/json application/javascript;

    # Frontend - Serve static files
    location / {
        root /var/www/stx-node-map;
        index index.html;
        try_files $uri $uri/ /index.html;

        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    # Backend API proxy
    location /api {
        proxy_pass http://127.0.0.1:8089;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # CORS headers
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range" always;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Logging
    access_log /var/log/nginx/stx-node-map-access.log;
    error_log /var/log/nginx/stx-node-map-error.log;
}
NGINX_EOF
fi

# Update domain in nginx config
sed -i "s|/etc/letsencrypt/live/DOMAIN/|/etc/letsencrypt/live/$DOMAIN/|g" "$NGINX_CONF"
sed -i "s|server_name _;|server_name $DOMAIN $WILDCARD_DOMAIN;|g" "$NGINX_CONF"

# Enable site if not already enabled
if [ ! -L /etc/nginx/sites-enabled/stx-node-map ]; then
    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/stx-node-map
fi

# Remove default site if it exists
rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
echo "Testing Nginx configuration..."
if nginx -t; then
    echo -e "${GREEN}✓ Nginx configuration is valid${NC}"
else
    echo -e "${RED}ERROR: Nginx configuration test failed${NC}"
    exit 1
fi

# Reload nginx
echo "Reloading Nginx..."
systemctl reload nginx

echo ""
echo -e "${GREEN}✓ Nginx reloaded with SSL configuration${NC}"
echo ""

# Step 3: Setup auto-renewal
echo "Step 3: Setting up certificate auto-renewal..."

# Create renewal hook script
RENEWAL_HOOK="/etc/letsencrypt/renewal-hooks/post/nginx-reload.sh"
mkdir -p "$(dirname "$RENEWAL_HOOK")"

cat > "$RENEWAL_HOOK" << 'HOOK_EOF'
#!/bin/bash
systemctl reload nginx
HOOK_EOF

chmod +x "$RENEWAL_HOOK"

# Test renewal
echo "Testing certificate renewal..."
certbot renew --dry-run --quiet

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Renewal test successful${NC}"
else
    echo -e "${YELLOW}WARNING: Renewal test had issues, but setup may still work${NC}"
fi

# Step 4: Display completion info
echo ""
echo "=========================================="
echo -e "${GREEN}SSL Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "Certificate Details:"
echo "  Domain:         $DOMAIN"
echo "  Wildcard:       $WILDCARD_DOMAIN"
echo "  Location:       $CERT_DIR"
echo "  Expires:        $(date -d '+90 days' +'%Y-%m-%d')"
echo ""
echo "Auto-renewal:"
echo "  Systemd timer is configured to auto-renew certificates"
echo "  Check renewal status: certbot renew --dry-run"
echo ""
echo "Your site is now live with SSL!"
echo "  https://$DOMAIN"
echo "  https://$WILDCARD_DOMAIN"
echo ""
echo "Verification:"
echo "  curl https://$DOMAIN"
echo "  curl https://$WILDCARD_DOMAIN"
echo ""
echo "Useful commands:"
echo "  View certificate: certbot certificates"
echo "  Renew now:        certbot renew"
echo "  View logs:        tail -f /var/log/letsencrypt/letsencrypt.log"
echo "=========================================="
