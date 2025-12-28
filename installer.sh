#!/bin/bash
# All-in-one WireGuard installer/fixer for VPS or local servers
# Auto-fixes packages, sets up VPN server/client, UFW rules, IP forwarding
# https://github.com/xmbmaster/cgnat

if [ $EUID != 0 ]; then
  sudo "$0" "$@"
  exit $?
fi

WGCONFLOC='/etc/wireguard/wg0.conf'
WGPUBKEY='/etc/wireguard/publickey'
WGCLIENTIPFILE='/etc/wireguard/client_ip'

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

fix_packages() {
  echo -e "${YELLOW}Fixing broken dependencies...${NC}"
  systemctl stop ufw 2>/dev/null
  apt remove --purge -y iptables-persistent netfilter-persistent
  apt --fix-broken install -y
  apt update
  apt install -y wireguard ufw
  echo -e "${GREEN}Packages fixed.${NC}"
}

stop_wg() {
  systemctl stop wg-quick@wg0 2>/dev/null
  wg-quick down wg0 2>/dev/null
}

uninstall_wg() {
  echo -e "${YELLOW}Removing WireGuard and configuration...${NC}"
  stop_wg
  systemctl disable wg-quick@wg0 >/dev/null
  rm -f $WGCONFLOC $WGPUBKEY $WGCLIENTIPFILE
  apt remove --purge -y wireguard ufw
  echo -e "${GREEN}WireGuard uninstalled.${NC}"
  exit
}

setup_ufw() {
  echo -e "${YELLOW}Configuring UFW rules...${NC}"
  ufw allow ssh
  ufw allow $WGPORT/udp
  ufw --force enable
  echo -e "${GREEN}UFW rules applied.${NC}"
}

echo ""
echo -e "${GREEN}All-in-one WireGuard Installer${NC}"
echo ""
echo "Select option:"
echo "1) Install Server"
echo "2) Install Client"
echo "3) Uninstall"
read -p "Option [1-3]: " OPT

fix_packages
stop_wg
sysctl -w net.ipv4.ip_forward=1 >/dev/null

if [[ $OPT == "3" ]]; then
  uninstall_wg
fi

read -p "Enter server VPN IP [10.1.0.1]: " SERVER_IP
SERVER_IP=${SERVER_IP:-10.1.0.1}

read -p "Enter client VPN IP [10.1.0.2]: " CLIENT_IP
CLIENT_IP=${CLIENT_IP:-10.1.0.2}

read -p "WireGuard port [55108]: " WGPORT
WGPORT=${WGPORT:-55108}

echo -e "${YELLOW}Generating keys...${NC}"
umask 077
WG_PRIVKEY=$(wg genkey)
WG_PUBKEY=$(echo $WG_PRIVKEY | wg pubkey)
echo $WG_PUBKEY > $WGPUBKEY

if [[ $OPT == "1" ]]; then
  echo -e "${GREEN}Server config: $WGCONFLOC${NC}"
  cat > $WGCONFLOC <<EOL
[Interface]
Address = $SERVER_IP/24
ListenPort = $WGPORT
PrivateKey = $WG_PRIVKEY

[Peer]
PublicKey =
AllowedIPs = $CLIENT_IP/32
EOL
  setup_ufw
  echo -e "${YELLOW}Server config created. Edit client public key later.${NC}"
elif [[ $OPT == "2" ]]; then
  read -p "Paste SERVER Public Key: " SERVER_PUBKEY
  cat > $WGCONFLOC <<EOL
[Interface]
Address = $CLIENT_IP/24
PrivateKey = $WG_PRIVKEY

[Peer]
PublicKey = $SERVER_PUBKEY
AllowedIPs = 0.0.0.0/0
Endpoint = $SERVER_IP:$WGPORT
PersistentKeepalive = 25
EOL
fi

echo -e "${YELLOW}Starting WireGuard...${NC}"
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo -e "${GREEN}WireGuard setup completed.${NC}"
echo "Server Public Key: $WG_PUBKEY"
echo -e "${GREEN}You can now edit the config files for additional peers if needed.${NC}"
