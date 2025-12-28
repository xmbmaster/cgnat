#!/bin/bash
# One-click WireGuard Installer (Server & Local Client)
# Fixed all previous issues including ListenPort parsing

set -e

WGCONF="/etc/wireguard/wg0.conf"
WGCLIENTIP="/etc/wireguard/client_ip"
WGPUBKEY="/etc/wireguard/publickey"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[36m'; NC='\033[0m'

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Re-running as root...${NC}"
    sudo "$0" "$@"
    exit $?
fi

stop_wg() {
    echo -e "${YELLOW}Stopping WireGuard if running...${NC}"
    systemctl stop wg-quick@wg0 2>/dev/null || true
}

update_install() {
    echo -e "${YELLOW}Updating system and installing required packages...${NC}"
    apt update
    apt install -y wireguard iptables ufw iproute2 qrencode
}

enable_ip_forwarding() {
    echo -e "${YELLOW}Enabling IP forwarding...${NC}"
    sysctl -w net.ipv4.ip_forward=1
    sed -i '/^net.ipv4.ip_forward/d' /etc/sysctl.conf
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
}

generate_keys() {
    echo -e "${YELLOW}Generating WireGuard keys...${NC}"
    umask 077
    SERVER_PRIVATE=$(wg genkey)
    SERVER_PUBLIC=$(echo "$SERVER_PRIVATE" | wg pubkey)
    echo "$SERVER_PUBLIC" > $WGPUBKEY
}

create_server_config() {
    read -p "Enter VPS Public IP: " PUBLIC_IP
    read -p "Enter VPN server IP [10.1.0.1]: " SERVER_IP
    SERVER_IP=${SERVER_IP:-10.1.0.1}
    read -p "Enter VPN client IP [10.1.0.2]: " CLIENT_IP
    CLIENT_IP=${CLIENT_IP:-10.1.0.2}
    read -p "Enter WireGuard port [55108]: " WGPORT
    WGPORT=${WGPORT:-55108}

    echo "$CLIENT_IP" > $WGCLIENTIP

    echo -e "${YELLOW}Paste CLIENT Public Key: ${NC}"
    read CLIENT_PUBKEY

    mkdir -p /etc/wireguard
    chmod 700 /etc/wireguard

    cat > $WGCONF <<EOL
[Interface]
Address = $SERVER_IP/24
PrivateKey = $SERVER_PRIVATE
ListenPort = $WGPORT

[Peer]
PublicKey = $CLIENT_PUBKEY
AllowedIPs = $CLIENT_IP/32
EOL

    echo -e "${GREEN}Server config created at $WGCONF${NC}"
}

create_client_config() {
    SERVER_IP=$1
    SERVER_PORT=$2
    SERVER_PUBKEY=$3
    read -p "Enter Local VPN Client IP [10.1.0.2]: " CLIENT_IP
    CLIENT_IP=${CLIENT_IP:-10.1.0.2}

    cat > wg0-client.conf <<EOL
[Interface]
Address = $CLIENT_IP/24
PrivateKey = $(wg genkey)

[Peer]
PublicKey = $SERVER_PUBKEY
AllowedIPs = 0.0.0.0/0
Endpoint = $SERVER_IP:$SERVER_PORT
PersistentKeepalive = 25
EOL

    echo -e "${GREEN}Client config saved as wg0-client.conf${NC}"
}

setup_firewall() {
    echo -e "${YELLOW}Configuring UFW firewall...${NC}"
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow $WGPORT/udp
    ufw enable
}

start_wireguard() {
    echo -e "${YELLOW}Starting WireGuard...${NC}"
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
    systemctl status wg-quick@wg0 --no-pager
}

# Main execution
stop_wg
update_install
enable_ip_forwarding
generate_keys
create_server_config
setup_firewall
start_wireguard

echo -e "${GREEN}WireGuard server setup complete!${NC}"
echo -e "Server Public Key: $(cat $WGPUBKEY)"
echo -e "Use the above public key to generate your client config."
