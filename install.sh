#!/bin/bash
# All-in-One WireGuard Installer (VPS / Local / Uninstall)
# Fixed for wg-quick parsing issues

set -e

WGCONFLOC='/etc/wireguard/wg0.conf'
WGPUBKEY='/etc/wireguard/publickey'
WGCLIENTIPFILE='/etc/wireguard/client_ip'
WGPORTSFILE='/etc/wireguard/forwarded_ports'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[36m'
NC='\033[0m'

check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root"
    exit 1
  fi
}

stop_wireguard() {
  echo -e "${YELLOW}Stopping WireGuard...${NC}"
  systemctl stop wg-quick@wg0 2>/dev/null || true
  wg-quick down wg0 2>/dev/null || true
}

uninstall_wireguard() {
  stop_wireguard
  echo -e "${YELLOW}Removing WireGuard packages and configs...${NC}"
  apt remove wireguard -y
  rm -f $WGCONFLOC $WGPUBKEY $WGCLIENTIPFILE $WGPORTSFILE
  systemctl disable wg-quick@wg0 >/dev/null 2>&1 || true
  echo -e "${GREEN}Uninstalled successfully${NC}"
  exit
}

enable_ip_forward() {
  echo -e "${YELLOW}Enabling IP forwarding...${NC}"
  sysctl -w net.ipv4.ip_forward=1
  if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  fi
}

install_dependencies() {
  echo -e "${YELLOW}Installing required packages...${NC}"
  apt update
  apt install -y wireguard iptables-persistent ufw
}

generate_keys() {
  echo -e "${YELLOW}Generating WireGuard keys...${NC}"
  mkdir -p /etc/wireguard
  umask 077
  wg genkey | tee $WGCONFLOC.priv | wg pubkey | tee $WGPUBKEY
  PRIVKEY=$(cat $WGCONFLOC.priv)
  rm -f $WGCONFLOC.priv
}

setup_firewall() {
  echo -e "${YELLOW}Configuring firewall...${NC}"
  ufw allow OpenSSH
  ufw allow $WGPORT/udp
  ufw --force enable
}

create_vps_config() {
  echo -e "${YELLOW}Creating VPS WireGuard config...${NC}"
  read -p "Enter VPS public IP [auto-detect]: " PUBLIC_IP
  PUBLIC_IP=${PUBLIC_IP:-$(curl -s ifconfig.me)}
  read -p "Enter VPN Server IP [10.1.0.1]: " SERVER_IP
  SERVER_IP=${SERVER_IP:-10.1.0.1}
  read -p "Enter VPN client IP [10.1.0.2]: " CLIENT_IP
  CLIENT_IP=${CLIENT_IP:-10.1.0.2}
  read -p "Enter WireGuard port [55108]: " WGPORT
  WGPORT=${WGPORT:-55108}

  CLIENT_PUBKEY=$(read -p "Paste client public key: " x; echo "$x")

  cat > $WGCONFLOC <<EOF
[Interface]
PrivateKey = $(cat $WGCONFLOC)
Address = $SERVER_IP/24
ListenPort = $WGPORT

[Peer]
PublicKey = $CLIENT_PUBKEY
AllowedIPs = $CLIENT_IP/32
EOF

  chmod 600 $WGCONFLOC
  systemctl enable wg-quick@wg0
  systemctl start wg-quick@wg0
  echo -e "${GREEN}VPS WireGuard setup complete!${NC}"
}

create_local_config() {
  echo -e "${YELLOW}Creating Local WireGuard client config...${NC}"
  read -p "Enter Server Public IP: " SERVER_PUBLIC_IP
  read -p "Enter Local VPN IP [10.1.0.2]: " CLIENT_IP
  CLIENT_IP=${CLIENT_IP:-10.1.0.2}
  read -p "Enter WireGuard port [55108]: " WGPORT
  WGPORT=${WGPORT:-55108}
  read -p "Paste Server Public Key: " SERVER_PUBKEY

  cat > $WGCONFLOC <<EOF
[Interface]
PrivateKey = $(cat $WGPUBKEY)
Address = $CLIENT_IP/24

[Peer]
PublicKey = $SERVER_PUBKEY
AllowedIPs = 0.0.0.0/0
Endpoint = $SERVER_PUBLIC_IP:$WGPORT
PersistentKeepalive = 25
EOF

  chmod 600 $WGCONFLOC
  systemctl enable wg-quick@wg0
  systemctl start wg-quick@wg0
  echo -e "${GREEN}Local WireGuard client setup complete!${NC}"
}

check_existing() {
  if [[ -f $WGCONFLOC ]]; then
    echo -e "${YELLOW}Existing WireGuard config detected.${NC}"
  fi
}

# ******** MAIN ********
check_root
echo ""
echo -e "Select option:"
echo "1) VPS Server"
echo "2) Local Client"
echo "3) Uninstall WireGuard"
read -p "Choice: " CHOICE

install_dependencies
enable_ip_forward
generate_keys
setup_firewall
check_existing

case $CHOICE in
  1) create_vps_config ;;
  2) create_local_config ;;
  3) uninstall_wireguard ;;
  *) echo "Invalid choice"; exit 1 ;;
esac
