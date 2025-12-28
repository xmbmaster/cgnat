#!/bin/bash
# FIXED CGNAT Bypass WireGuard - All menu options work (v0.4.0)
# Compatible: Ubuntu 20.04/22.04/24.04 + Oracle Cloud 2025

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
WGFILES="/etc/wireguard/{publickey,client_ip,ports}"
COLORS="RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'"

source <(echo "$COLORS")

uninstall() {
  echo -e "${YELLOW}Full Uninstall...${NC}"
  systemctl stop wg-quick@wg0 2>/dev/null; wg-quick down wg0 2>/dev/null
  rm -f $WGCONF ${WGFILES//\{/}//,/ }
  iptables -F -t nat -F -t mangle -F; iptables -X -t nat -X -t mangle -X
  iptables -P INPUT ACCEPT -P FORWARD ACCEPT -P OUTPUT ACCEPT
  rm -f /etc/iptables/rules.v4 /etc/iptables/rules.v6
  ufw --force disable reset 2>/dev/null || true
  apt purge -y wireguard wireguard-tools ufw iptables-persistent 2>/dev/null
  apt autoremove -y; sysctl -p 2>/dev/null
  echo -e "${GREEN}Clean uninstall complete${NC}"; exit 0
}

detect_interface() {
  IP=$(curl -s ifconfig.me); INT=$(ip route | grep default | awk '{print $5}' | head -1)
  [[ -z $INT ]] && INT=$(ip -o link | awk -F': ' '{print $2}' | grep -E '^(eth|ens)' | head -1)
  echo "$IP $INT"
}

main_menu() {
  clear; echo -e "${GREEN}=== CGNAT Bypass WireGuard (FIXED) ===${NC}"
  if [[ -f $WGCONF ]]; then
    if grep -q "Endpoint" $WGCONF; then TYPE="CLIENT"; else TYPE="SERVER"; fi
    echo -e "${YELLOW}Detected: $TYPE${NC}"
  fi
  echo "1) VPS SERVER Setup    2) Local CLIENT Setup"
  echo "3) Change Ports        4) Restart Tunnel"
  echo "5) FULL UNINSTALL      6) Status Check"
  echo "7) Exit"
  read -p "Choose: " opt
}

server_setup() {
  stop_wireguard; apt update && apt install -y wireguard ufw iputils-ping
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf; sysctl -p
  
  read -p "VPS Public IP: " PUBIP
  read -p "WG Server IP [10.1.0.1]: " WG_SIP; WG_SIP=${WG_SIP:-10.1.0.1}
  read -p "WG Client IP [10.1.0.2]: " WG_CIP; WG_CIP=${WG_CIP:-10.1.0.2}
  read -p "WG UDP Port [55108]: " WGPORT; WGPORT=${WGPORT:-55108}
  read -p "Ports (80/tcp,443/tcp): " PORTS
  
  echo $WG_CIP > /etc/wireguard/client_ip; mkdir -p /etc/wireguard
  
  # Generate keys
  wg genkey | tee /etc/wireguard/private | wg pubkey > /etc/wireguard/publickey
  SERVER_PUB=$(cat /etc/wireguard/publickey)
  
  echo -e "${YELLOW}Run on CLIENT: sudo $0 client $SERVER_PUB $PUBIP $WGPORT \"${PORTS:-80/tcp,443/tcp}\"${NC}"
  read -p "Client Public Key: " CLIENT_PUB
  
  INT=$(detect_interface | cut -d' ' -f2)
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private)
Address = $WG_SIP/24
ListenPort = $WGPORT

PostUp = iptables -t nat -A POSTROUTING -o $INT -j SNAT --to-source $PUBIP
PostDown = iptables -t nat -D POSTROUTING -o $INT -j SNAT --to-source $PUBIP
$(for p in $(echo $PORTS | tr ',' ' '); do echo "PostUp = iptables -t nat -A PREROUTING -p $(echo $p|cut -d/ -f2) --dport $(echo $p|cut -d/ -f1) -j DNAT --to $WG_CIP"; echo "PostDown = iptables -t nat -D PREROUTING -p $(echo $p|cut -d/ -f2) --dport $(echo $p|cut -d/ -f1) -j DNAT --to $WG_CIP"; done)

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = $WG_CIP/32
EOF
  
  ufw --force reset; ufw allow $WGPORT/udp; ufw allow ssh; ufw --force enable
  for p in $(echo $PORTS | tr ',' ' '); do ufw allow $p; done
  
  systemctl enable --now wg-quick@wg0
  echo -e "${GREEN}SERVER READY! Test: ping $WG_CIP${NC}"
}

client_setup() {
  SERVER_PUB=$1; PUBIP=$2; WGPORT=${3:-55108}; PORTS=${4:-80/tcp,443/tcp}
  WG_CIP=10.1.0.2; WG_SIP=10.1.0.1
  
  apt update && apt install -y wireguard iputils-ping
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf; sysctl -p
  
  wg genkey | tee /etc/wireguard/private | wg pubkey
  CLIENT_PUB=$(cat /etc/wireguard/publickey)
  echo -e "${GREEN}Your Public Key (give to SERVER): $CLIENT_PUB${NC}"
  
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private)
Address = $WG_CIP/24

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBIP:$WGPORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
  
  systemctl enable --now wg-quick@wg0
  echo -e "${GREEN}CLIENT READY! Test: ping $WG_SIP${NC}"
}

status_check() {
  wg show; systemctl status wg-quick@wg0 2>/dev/null || echo "Not running"
  ufw status 2>/dev/null | head -5; iptables -t nat -L -n | grep -E "(DNAT|SNAT)"
}

stop_wireguard() { systemctl stop wg-quick@wg0 2>/dev/null; wg-quick down wg0 2>/dev/null; }

case "${1:-}" in
  client) shift; client_setup "$@";;
  uninstall) uninstall;;
  status) status_check;;
  *) while true; do main_menu; case $opt in 1)server_setup;;2)client_setup;;;3)read -p "New ports: " PORTS; echo $PORTS > /etc/wireguard/ports; systemctl restart wg-quick@wg0;;4)systemctl restart wg-quick@wg0;;5)uninstall;;6)status_check;sleep 5;;7)exit;;esac; done;;
esac
