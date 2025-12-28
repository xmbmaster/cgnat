#!/bin/bash
# Auto WireGuard Installer for Oracle Cloud + Local Server
# Handles package conflicts and includes uninstall
# Version 1.0

WGCONFLOC='/etc/wireguard/wg0.conf'
WGPUBKEY='/etc/wireguard/publickey'
WGCLIENTIPFILE='/etc/wireguard/client_ip'
WGPORTSFILE='/etc/wireguard/forwarded_ports'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

#---------------- Functions ----------------#

stop_wireguard() {
  echo -e "${YELLOW}Stopping WireGuard...${NC}"
  systemctl stop wg-quick@wg0 2>/dev/null
  wg-quick down wg0 2>/dev/null
}

uninstall_all() {
  stop_wireguard
  echo -e "${YELLOW}Removing WireGuard and configs...${NC}"
  apt remove --purge wireguard ufw -y
  rm -rf /etc/wireguard
  echo -e "${GREEN}Uninstall complete${NC}"
  exit
}

fix_conflicts() {
  echo -e "${YELLOW}Fixing package conflicts...${NC}"
  apt remove iptables-persistent netfilter-persistent -y
  apt --fix-broken install -y
  apt update
}

install_required() {
  fix_conflicts
  echo -e "${YELLOW}Installing WireGuard & UFW...${NC}"
  apt install wireguard ufw -y
}

enable_ip_forwarding() {
  if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  fi
  sysctl -p
}

create_keys() {
  echo -e "${YELLOW}Generating WireGuard keys...${NC}"
  umask 077 && wg genkey | tee $WGCONFLOC | wg pubkey | tee $WGPUBKEY
}

generate_server_conf() {
  read -p "Server VPN IP [10.1.0.1]: " WG_SERVER_IP
  WG_SERVER_IP=${WG_SERVER_IP:-10.1.0.1}

  read -p "Client VPN IP [10.1.0.2]: " WG_CLIENT_IP
  WG_CLIENT_IP=${WG_CLIENT_IP:-10.1.0.2}

  read -p "WireGuard Port [55108]: " WGPORT
  WGPORT=${WGPORT:-55108}

  PK_FOR_CLIENT=$(cat $WGPUBKEY)

  echo "[Interface]" > $WGCONFLOC
  echo "PrivateKey = $(cat $WGCONFLOC)" >> $WGCONFLOC
  echo "Address = $WG_SERVER_IP/24" >> $WGCONFLOC
  echo "ListenPort = $WGPORT" >> $WGCONFLOC
  echo "" >> $WGCONFLOC

  read -p "Public Key from Client: " PK_FOR_SERVER
  echo "[Peer]" >> $WGCONFLOC
  echo "PublicKey = $PK_FOR_SERVER" >> $WGCONFLOC
  echo "AllowedIPs = $WG_CLIENT_IP/32" >> $WGCONFLOC

  echo -e "${GREEN}Server config created at $WGCONFLOC${NC}"
}

generate_client_conf() {
  read -p "Server Public IP: " PUBLIC_IP
  read -p "Client VPN IP [10.1.0.2]: " WG_CLIENT_IP
  WG_CLIENT_IP=${WG_CLIENT_IP:-10.1.0.2}

  read -p "WireGuard Port [55108]: " WGPORT
  WGPORT=${WGPORT:-55108}

  PK_FOR_SERVER=$(cat $WGPUBKEY)
  PK_FOR_CLIENT=$(wg genkey | tee /etc/wireguard/client_privatekey | wg pubkey)

  echo "[Interface]" > $WGCONFLOC
  echo "PrivateKey = $PK_FOR_CLIENT" >> $WGCONFLOC
  echo "Address = $WG_CLIENT_IP/24" >> $WGCONFLOC
  echo "" >> $WGCONFLOC
  echo "[Peer]" >> $WGCONFLOC
  echo "PublicKey = $PK_FOR_SERVER" >> $WGCONFLOC
  echo "AllowedIPs = 0.0.0.0/0" >> $WGCONFLOC
  echo "Endpoint = $PUBLIC_IP:$WGPORT" >> $WGCONFLOC
  echo "PersistentKeepalive = 25"
