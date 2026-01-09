#!/bin/bash
# Script to create a Hetzner Cloud server using their API
# This script creates a server and optionally configures firewall rules

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Validate required variables
if [ -z "$HETZNER_API_TOKEN" ] || [ "$HETZNER_API_TOKEN" = "your-api-token-here" ]; then
    echo -e "${RED}ERROR: HETZNER_API_TOKEN not set!${NC}"
    echo "Please set your Hetzner API token in $CONFIG_FILE"
    exit 1
fi

# Set defaults
SERVER_NAME="${SERVER_NAME:-stx-node-map-prod}"
SERVER_TYPE="${SERVER_TYPE:-cx21}"
SERVER_LOCATION="${SERVER_LOCATION:-nbg1}"
SERVER_IMAGE="${SERVER_IMAGE:-ubuntu-22.04}"
ENABLE_FIREWALL="${ENABLE_FIREWALL:-true}"
ENABLE_BACKUPS="${ENABLE_BACKUPS:-false}"

API_URL="https://api.hetzner.cloud/v1"

echo "=========================================="
echo "Hetzner Cloud Server Creation"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Server Name: $SERVER_NAME"
echo "  Server Type: $SERVER_TYPE"
echo "  Location:    $SERVER_LOCATION"
echo "  Image:       $SERVER_IMAGE"
echo "  SSH Key:     $SSH_KEY_NAME"
echo "  Firewall:    $ENABLE_FIREWALL"
echo "  Backups:     $ENABLE_BACKUPS"
echo ""

# Function to make API calls
api_call() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    if [ -n "$data" ]; then
        curl -s -X "$method" \
            -H "Authorization: Bearer $HETZNER_API_TOKEN" \
            -H "Content-Type: application/json" \
            "$API_URL/$endpoint" \
            -d "$data"
    else
        curl -s -X "$method" \
            -H "Authorization: Bearer $HETZNER_API_TOKEN" \
            "$API_URL/$endpoint"
    fi
}

# Check if SSH key exists
echo "Step 1: Checking SSH key..."
SSH_KEYS=$(api_call GET "ssh_keys")
SSH_KEY_ID=$(echo "$SSH_KEYS" | jq -r ".ssh_keys[] | select(.name==\"$SSH_KEY_NAME\") | .id")

if [ -z "$SSH_KEY_ID" ]; then
    echo -e "${RED}ERROR: SSH key '$SSH_KEY_NAME' not found!${NC}"
    echo ""
    echo "Available SSH keys:"
    echo "$SSH_KEYS" | jq -r '.ssh_keys[] | "  - \(.name) (ID: \(.id))"'
    echo ""
    echo "Please create an SSH key in Hetzner Console or update SSH_KEY_NAME in $CONFIG_FILE"
    exit 1
fi

echo -e "${GREEN}✓ SSH key found (ID: $SSH_KEY_ID)${NC}"

# Check if server already exists
echo ""
echo "Step 2: Checking if server already exists..."
EXISTING_SERVER=$(api_call GET "servers" | jq -r ".servers[] | select(.name==\"$SERVER_NAME\") | .id")

if [ -n "$EXISTING_SERVER" ]; then
    echo -e "${YELLOW}WARNING: Server '$SERVER_NAME' already exists (ID: $EXISTING_SERVER)${NC}"
    read -p "Do you want to delete it and create a new one? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Deleting existing server..."
        api_call DELETE "servers/$EXISTING_SERVER"
        echo "Waiting for server deletion..."
        sleep 5
    else
        echo "Aborting."
        exit 1
    fi
fi

# Create firewall if enabled
FIREWALL_ID=""
if [ "$ENABLE_FIREWALL" = "true" ]; then
    echo ""
    echo "Step 3: Creating firewall..."
    
    FIREWALL_NAME="${SERVER_NAME}-firewall"
    
    # Check if firewall exists
    EXISTING_FIREWALL=$(api_call GET "firewalls" | jq -r ".firewalls[] | select(.name==\"$FIREWALL_NAME\") | .id")
    
    if [ -n "$EXISTING_FIREWALL" ]; then
        echo "Firewall already exists, using existing one (ID: $EXISTING_FIREWALL)"
        FIREWALL_ID=$EXISTING_FIREWALL
    else
        FIREWALL_DATA=$(cat <<EOF
{
  "name": "$FIREWALL_NAME",
  "rules": [
    {
      "direction": "in",
      "protocol": "tcp",
      "port": "22",
      "source_ips": ["0.0.0.0/0", "::/0"],
      "description": "SSH"
    },
    {
      "direction": "in",
      "protocol": "tcp",
      "port": "80",
      "source_ips": ["0.0.0.0/0", "::/0"],
      "description": "HTTP"
    },
    {
      "direction": "in",
      "protocol": "tcp",
      "port": "443",
      "source_ips": ["0.0.0.0/0", "::/0"],
      "description": "HTTPS"
    },
    {
      "direction": "in",
      "protocol": "icmp",
      "source_ips": ["0.0.0.0/0", "::/0"],
      "description": "ICMP (ping)"
    }
  ]
}
EOF
)
        
        FIREWALL_RESPONSE=$(api_call POST "firewalls" "$FIREWALL_DATA")
        FIREWALL_ID=$(echo "$FIREWALL_RESPONSE" | jq -r '.firewall.id')
        echo -e "${GREEN}✓ Firewall created (ID: $FIREWALL_ID)${NC}"
    fi
else
    echo ""
    echo "Step 3: Skipping firewall creation..."
fi

# Create server
echo ""
echo "Step 4: Creating server..."

CREATE_DATA=$(cat <<EOF
{
  "name": "$SERVER_NAME",
  "server_type": "$SERVER_TYPE",
  "location": "$SERVER_LOCATION",
  "image": "$SERVER_IMAGE",
  "ssh_keys": [$SSH_KEY_ID],
  "start_after_create": true,
  "public_net": {
    "enable_ipv4": true,
    "enable_ipv6": true
  }
  $([ "$ENABLE_BACKUPS" = "true" ] && echo ', "backups": true' || echo '')
  $([ -n "$FIREWALL_ID" ] && echo ", \"firewalls\": [{\"firewall\": $FIREWALL_ID}]" || echo '')
}
EOF
)

SERVER_RESPONSE=$(api_call POST "servers" "$CREATE_DATA")

# Check for errors
ERROR=$(echo "$SERVER_RESPONSE" | jq -r '.error // empty')
if [ -n "$ERROR" ]; then
    echo -e "${RED}ERROR creating server:${NC}"
    echo "$SERVER_RESPONSE" | jq .
    exit 1
fi

SERVER_ID=$(echo "$SERVER_RESPONSE" | jq -r '.server.id')
ROOT_PASSWORD=$(echo "$SERVER_RESPONSE" | jq -r '.root_password')

echo -e "${GREEN}✓ Server creation initiated (ID: $SERVER_ID)${NC}"

# Wait for server to be ready
echo ""
echo "Step 5: Waiting for server to be ready..."
echo "(This may take 1-2 minutes)"

for i in {1..60}; do
    SERVER_STATUS=$(api_call GET "servers/$SERVER_ID" | jq -r '.server.status')
    if [ "$SERVER_STATUS" = "running" ]; then
        echo -e "${GREEN}✓ Server is running!${NC}"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Get server details
SERVER_DETAILS=$(api_call GET "servers/$SERVER_ID")
IPV4=$(echo "$SERVER_DETAILS" | jq -r '.server.public_net.ipv4.ip')
IPV6=$(echo "$SERVER_DETAILS" | jq -r '.server.public_net.ipv6.ip // "N/A"')

# Save server info
INFO_FILE="$SCRIPT_DIR/server-info.txt"
cat > "$INFO_FILE" <<EOF
========================================
STX Node Map Server Information
========================================
Created: $(date)

Server Details:
  Name:       $SERVER_NAME
  ID:         $SERVER_ID
  Type:       $SERVER_TYPE
  Location:   $SERVER_LOCATION
  Image:      $SERVER_IMAGE
  Status:     running

Network:
  IPv4:       $IPV4
  IPv6:       $IPV6

Access:
  SSH:        ssh root@$IPV4
  Web:        http://$IPV4

$([ -n "$ROOT_PASSWORD" ] && echo "Root Password: $ROOT_PASSWORD" || echo "Root Password: (using SSH key)")
$([ -n "$FIREWALL_ID" ] && echo "Firewall ID: $FIREWALL_ID" || echo "Firewall: disabled")

========================================
Next Steps:
========================================
1. SSH into the server:
   ssh root@$IPV4

2. Run the server setup script:
   wget https://your-repo/deployment/01-server-setup.sh
   chmod +x 01-server-setup.sh
   ./01-server-setup.sh

   OR manually copy the deployment files:
   scp -r deployment/ root@$IPV4:/root/

3. Clone your repository and deploy:
   cd /root
   ./deployment/02-deploy.sh

4. (Optional) Configure DNS:
   Point your domain to: $IPV4

5. (Optional) Setup SSL:
   certbot --nginx -d your-domain.com

========================================
EOF

echo ""
echo "=========================================="
echo -e "${GREEN}Server Created Successfully!${NC}"
echo "=========================================="
echo ""
cat "$INFO_FILE"
echo ""
echo -e "${YELLOW}Server information saved to: $INFO_FILE${NC}"
echo ""

# Offer to copy deployment files
read -p "Would you like to copy deployment files to the server now? (yes/no): " -r
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo ""
    echo "Waiting 10 seconds for SSH to be ready..."
    sleep 10
    
    echo "Copying deployment files..."
    scp -o StrictHostKeyChecking=no -r "$SCRIPT_DIR" root@$IPV4:/root/deployment
    
    echo ""
    echo -e "${GREEN}Deployment files copied!${NC}"
    echo ""
    echo "You can now SSH into the server and run:"
    echo "  cd /root/deployment"
    echo "  ./01-server-setup.sh"
    echo "  ./02-deploy.sh"
fi

echo ""
echo "=========================================="
