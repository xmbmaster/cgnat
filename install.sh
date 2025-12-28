#!/bin/bash
# WireGuard Oracle VPS Installer - Fixed & Auto
# Works on Debian/Ubuntu/CasaOS

set -e

WGCONF="/etc/wireguard/wg0.conf"
WGKEY="/etc/wireguard/privatekey"
WGPORT=55108
WGNET="10.1.0.0/24"
WGCLIENT="10.1.0.2/32"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

# Install dependencies
echo -e "${YELLOW}Installing WireGuard and dependencies...${NC}"
apt update && apt install -y wireguard iptables ufw curl qrencode

# Enable IP forwarding
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
sysctl -w net.ipv4.ip_forward=1
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

# Generate keys
mkdir -p /etc/wireguard
if [ ! -f "$WGKEY" ]; then
  echo -e "${YELLOW}Generating WireGuard keys...${NC}"
  umask 077
  wg genkey | tee $WGKEY | wg pubkey > /etc/wireguard/publickey
fi

SERVER_PUBKEY=$(cat /etc/wireguard/publickey)

# Ask for client public key
echo -e "${YELLOW}Enter CLIENT Public Key:${NC}"
read -r CLIENT_PUBKEY

# Ask for VPS public IP (for endpoint)
echo -e "${YELLOW}Enter your VPS Public IP:${NC}"
read -r PUBLIC_IP

# Create wg0.conf
cat > $WGCONF <<EOF
[Interface]
PrivateKey = $(cat $WGKEY)
Address = 10.1.0.1/24
ListenPort = $WGPORT

[Peer]
PublicKey = $CLIENT_PUBKEY
AllowedIPs = $WGCLIENT
Endpoint = $PUBLIC_IP:$WGPORT
PersistentKeepalive = 25
EOF

chmod 600 $WGCONF

# Firewall
echo -e "${YELLOW}Configuring UFW...${NC}"
ufw allow $WGPORT/udp
ufw allow ssh
ufw --force enable

# Start WireGuard
echo -e "${YELLOW}Starting WireGuard...${NC}"
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo -e "${GREEN}WireGuard is up and running!${NC}"
echo -e "Server Public Key: ${SERVER_PUBKEY}"
echo -e "Client IP: ${WGCLIENT}"

# One-click uninstall
cat > /usr/local/bin/wg-uninstall.sh <<'UNINSTALL'
#!/bin/bash
systemctl stop wg-quick@wg0
systemctl disable wg-quick@wg0
rm -f /etc/wireguard/wg0.conf /etc/wireguard/privatekey /etc/wireguard/publickey
ufw --force reset
echo "WireGuard uninstalled."
UNINSTALL
chmod +x /usr/local/bin/wg-uninstall.sh
echo -e "${GREEN}One-command uninstall available: wg-uninstall.sh${NC}"
