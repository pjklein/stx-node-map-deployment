#!/usr/bin/env python3
"""
Create a Hetzner Cloud server using the Hetzner Cloud API
This is a Python alternative to the bash script with better error handling
"""

import os
import sys
import time
import json
import requests
from datetime import datetime
from pathlib import Path

# Colors for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color

def load_config():
    """Load configuration from hetzner-config.env file"""
    script_dir = Path(__file__).parent
    config_file = script_dir / "hetzner-config.env"
    
    if not config_file.exists():
        print(f"{Colors.RED}ERROR: Configuration file not found!{Colors.NC}")
        print("Please copy hetzner-config.env.example to hetzner-config.env and configure it.")
        sys.exit(1)
    
    config = {}
    with open(config_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                # Remove quotes
                value = value.strip().strip('"').strip("'")
                config[key] = value
    
    return config

def validate_config(config):
    """Validate required configuration values"""
    required = ['HETZNER_API_TOKEN']
    for key in required:
        if key not in config or not config[key] or config[key] == 'your-api-token-here':
            print(f"{Colors.RED}ERROR: {key} not set!{Colors.NC}")
            print(f"Please set it in hetzner-config.env")
            sys.exit(1)
    
    # Set defaults
    config.setdefault('SERVER_NAME', 'stx-node-map-prod')
    config.setdefault('SERVER_TYPE', 'cx21')
    config.setdefault('SERVER_LOCATION', 'nbg1')
    config.setdefault('SERVER_IMAGE', 'ubuntu-22.04')
    config.setdefault('ENABLE_FIREWALL', 'true')
    config.setdefault('ENABLE_BACKUPS', 'false')

class HetznerAPI:
    """Hetzner Cloud API client"""
    
    def __init__(self, api_token):
        self.api_token = api_token
        self.base_url = "https://api.hetzner.cloud/v1"
        self.headers = {
            "Authorization": f"Bearer {api_token}",
            "Content-Type": "application/json"
        }
    
    def _request(self, method, endpoint, data=None):
        """Make API request"""
        url = f"{self.base_url}/{endpoint}"
        
        try:
            if method == 'GET':
                response = requests.get(url, headers=self.headers)
            elif method == 'POST':
                response = requests.post(url, headers=self.headers, json=data)
            elif method == 'DELETE':
                response = requests.delete(url, headers=self.headers)
            else:
                raise ValueError(f"Unsupported method: {method}")
            
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"{Colors.RED}API Error: {e}{Colors.NC}")
            if hasattr(e.response, 'text'):
                print(f"Response: {e.response.text}")
            sys.exit(1)
    
    def get(self, endpoint):
        return self._request('GET', endpoint)
    
    def post(self, endpoint, data):
        return self._request('POST', endpoint, data)
    
    def delete(self, endpoint):
        return self._request('DELETE', endpoint)

def get_ssh_key_id(api, ssh_key_name):
    """Get SSH key ID by name"""
    response = api.get("ssh_keys")
    
    for key in response['ssh_keys']:
        if key['name'] == ssh_key_name:
            return key['id']
    
    print(f"{Colors.RED}ERROR: SSH key '{ssh_key_name}' not found!{Colors.NC}")
    print("\nAvailable SSH keys:")
    for key in response['ssh_keys']:
        print(f"  - {key['name']} (ID: {key['id']})")
    print("\nPlease create an SSH key in Hetzner Console or update SSH_KEY_NAME in config")
    sys.exit(1)

def check_existing_server(api, server_name):
    """Check if server already exists"""
    response = api.get("servers")
    
    for server in response['servers']:
        if server['name'] == server_name:
            return server['id']
    
    return None

def create_firewall(api, firewall_name):
    """Create firewall with standard rules"""
    # Check if firewall already exists
    response = api.get("firewalls")
    for firewall in response['firewalls']:
        if firewall['name'] == firewall_name:
            print(f"Firewall already exists (ID: {firewall['id']})")
            return firewall['id']
    
    # Create new firewall
    firewall_data = {
        "name": firewall_name,
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
    
    response = api.post("firewalls", firewall_data)
    firewall_id = response['firewall']['id']
    print(f"{Colors.GREEN}✓ Firewall created (ID: {firewall_id}){Colors.NC}")
    return firewall_id

def create_server(api, config, ssh_key_id, firewall_id=None):
    """Create the server"""
    server_data = {
        "name": config['SERVER_NAME'],
        "server_type": config['SERVER_TYPE'],
        "location": config['SERVER_LOCATION'],
        "image": config['SERVER_IMAGE'],
        "ssh_keys": [ssh_key_id],
        "start_after_create": True,
        "public_net": {
            "enable_ipv4": True,
            "enable_ipv6": True
        }
    }
    
    if config['ENABLE_BACKUPS'].lower() == 'true':
        server_data['backups'] = True
    
    if firewall_id:
        server_data['firewalls'] = [{"firewall": firewall_id}]
    
    response = api.post("servers", server_data)
    
    if 'error' in response:
        print(f"{Colors.RED}ERROR creating server:{Colors.NC}")
        print(json.dumps(response, indent=2))
        sys.exit(1)
    
    return response

def wait_for_server(api, server_id):
    """Wait for server to be ready"""
    print("\nWaiting for server to be ready...")
    print("(This may take 1-2 minutes)")
    
    for i in range(60):
        response = api.get(f"servers/{server_id}")
        status = response['server']['status']
        
        if status == 'running':
            print(f"\n{Colors.GREEN}✓ Server is running!{Colors.NC}")
            return response['server']
        
        print(".", end='', flush=True)
        time.sleep(2)
    
    print(f"\n{Colors.RED}Timeout waiting for server{Colors.NC}")
    sys.exit(1)

def save_server_info(config, server, root_password, firewall_id):
    """Save server information to file"""
    script_dir = Path(__file__).parent
    info_file = script_dir / "server-info.txt"
    
    ipv4 = server['public_net']['ipv4']['ip']
    ipv6 = server['public_net'].get('ipv6', {}).get('ip', 'N/A')
    
    info = f"""==========================================
STX Node Map Server Information
==========================================
Created: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

Server Details:
  Name:       {server['name']}
  ID:         {server['id']}
  Type:       {config['SERVER_TYPE']}
  Location:   {config['SERVER_LOCATION']}
  Image:      {config['SERVER_IMAGE']}
  Status:     {server['status']}

Network:
  IPv4:       {ipv4}
  IPv6:       {ipv6}

Access:
  SSH:        ssh root@{ipv4}
  Web:        http://{ipv4}

{f"Root Password: {root_password}" if root_password else "Root Password: (using SSH key)"}
{f"Firewall ID: {firewall_id}" if firewall_id else "Firewall: disabled"}

==========================================
Next Steps:
==========================================
1. SSH into the server:
   ssh root@{ipv4}

2. Run the server setup script:
   wget https://your-repo/deployment/01-server-setup.sh
   chmod +x 01-server-setup.sh
   ./01-server-setup.sh

   OR manually copy the deployment files:
   scp -r deployment/ root@{ipv4}:/root/

3. Clone your repository and deploy:
   cd /root
   ./deployment/02-deploy.sh

4. (Optional) Configure DNS:
   Point your domain to: {ipv4}

5. (Optional) Setup SSL:
   certbot --nginx -d your-domain.com

==========================================
"""
    
    with open(info_file, 'w') as f:
        f.write(info)
    
    return info_file, ipv4

def main():
    print("=" * 50)
    print("Hetzner Cloud Server Creation")
    print("=" * 50)
    print()
    
    # Load and validate configuration
    config = load_config()
    validate_config(config)
    
    print("Configuration:")
    print(f"  Server Name: {config['SERVER_NAME']}")
    print(f"  Server Type: {config['SERVER_TYPE']}")
    print(f"  Location:    {config['SERVER_LOCATION']}")
    print(f"  Image:       {config['SERVER_IMAGE']}")
    print(f"  SSH Key:     {config['SSH_KEY_NAME']}")
    print(f"  Firewall:    {config['ENABLE_FIREWALL']}")
    print(f"  Backups:     {config['ENABLE_BACKUPS']}")
    print()
    
    # Initialize API client
    api = HetznerAPI(config['HETZNER_API_TOKEN'])
    
    # Step 1: Check SSH key
    print("Step 1: Checking SSH key...")
    ssh_key_id = get_ssh_key_id(api, config['SSH_KEY_NAME'])
    print(f"{Colors.GREEN}✓ SSH key found (ID: {ssh_key_id}){Colors.NC}")
    
    # Step 2: Check existing server
    print("\nStep 2: Checking if server already exists...")
    existing_server_id = check_existing_server(api, config['SERVER_NAME'])
    
    if existing_server_id:
        print(f"{Colors.YELLOW}WARNING: Server '{config['SERVER_NAME']}' already exists (ID: {existing_server_id}){Colors.NC}")
        response = input("Do you want to delete it and create a new one? (yes/no): ")
        if response.lower() in ['yes', 'y']:
            print("Deleting existing server...")
            api.delete(f"servers/{existing_server_id}")
            print("Waiting for server deletion...")
            time.sleep(5)
        else:
            print("Aborting.")
            sys.exit(0)
    
    # Step 3: Create firewall
    firewall_id = None
    if config['ENABLE_FIREWALL'].lower() == 'true':
        print("\nStep 3: Creating firewall...")
        firewall_name = f"{config['SERVER_NAME']}-firewall"
        firewall_id = create_firewall(api, firewall_name)
    else:
        print("\nStep 3: Skipping firewall creation...")
    
    # Step 4: Create server
    print("\nStep 4: Creating server...")
    response = create_server(api, config, ssh_key_id, firewall_id)
    
    server_id = response['server']['id']
    root_password = response.get('root_password')
    
    print(f"{Colors.GREEN}✓ Server creation initiated (ID: {server_id}){Colors.NC}")
    
    # Step 5: Wait for server
    server = wait_for_server(api, server_id)
    
    # Save server info
    info_file, ipv4 = save_server_info(config, server, root_password, firewall_id)
    
    print()
    print("=" * 50)
    print(f"{Colors.GREEN}Server Created Successfully!{Colors.NC}")
    print("=" * 50)
    print()
    
    with open(info_file) as f:
        print(f.read())
    
    print(f"{Colors.YELLOW}Server information saved to: {info_file}{Colors.NC}")
    print()
    
    # Offer to copy deployment files
    response = input("Would you like to copy deployment files to the server now? (yes/no): ")
    if response.lower() in ['yes', 'y']:
        print("\nWaiting 10 seconds for SSH to be ready...")
        time.sleep(10)
        
        print("Copying deployment files...")
        script_dir = Path(__file__).parent
        os.system(f"scp -o StrictHostKeyChecking=no -r {script_dir} root@{ipv4}:/root/deployment")
        
        print()
        print(f"{Colors.GREEN}Deployment files copied!{Colors.NC}")
    
    # Offer to setup SSL with Cloudflare
    print()
    cloudflare_token = config.get('CLOUDFLARE_API_TOKEN', '')
    if cloudflare_token and cloudflare_token != 'your_cloudflare_api_token_here':
        response = input("Would you like to setup SSL and update Cloudflare DNS now? (yes/no): ")
        if response.lower() in ['yes', 'y']:
            print()
            print("Running SSL setup with Cloudflare DNS automation...")
            script_dir = Path(__file__).parent
            ssl_script = script_dir / "03-setup-ssl.sh"
            os.system(f"sudo {ssl_script} {ipv4}")
            
            print()
            print(f"{Colors.GREEN}✓ SSL and DNS configured!{Colors.NC}")
            print()
            print("You can now access your server at:")
            domain_name = config.get('DOMAIN_NAME', '')
            if domain_name and domain_name != 'your-domain.com':
                print(f"  https://{domain_name}")
    else:
        print(f"{Colors.YELLOW}Note: CLOUDFLARE_API_TOKEN not configured{Colors.NC}")
        print("To setup SSL later with Cloudflare automation:")
        print(f"  sudo ./03-setup-ssl.sh {ipv4}")
    
    print()
    print("You can now SSH into the server and run:")
    print(f"  ssh root@{ipv4}")
    print("  cd /root/deployment")
    print("  ./01-server-setup.sh")
    print("  ./02-deploy.sh")
    
    print()
    print("=" * 50)

if __name__ == '__main__':
    main()
