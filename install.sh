#!/bin/bash
# 🔥 CGNAT BYPASS WireGuard v1.1.0 - FIXED ALL ERRORS
# Ubuntu 20.04/22.04/24.04 + Oracle Cloud ✅

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

uninstall_all() {
  echo -e "${YELLOW}${BOLD}🗑️  FULL CLEANUP${NC}"
  systemctl stop wg-quick@wg0 2>/dev/null; wg-quick down wg0 2>/dev/null
  rm -rf /etc/wireguard $WGCONF /etc/iptables/rules.v*
  iptables -F -t nat -F -t mangle -F -X -t nat -X -t mangle -X
  iptables -P INPUT ACCEPT -P FORWARD ACCEPT -P OUTPUT ACCEPT
  ufw disable 2>/dev/null || true
  apt purge -y wireguard wireguard-tools iptables-persistent netfilter-persistent -y 2>/dev/null || true
  apt autoremove -y
  echo -e "${GREEN}✅ CLEAN${NC}"; exit 0
}

install_prereqs() {
  apt update
  apt install -y wireguard wireguard-tools curl iputils-ping netfilter-persistent
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  sysctl -p
}

show_status() {
  clear; echo -e "${CYAN}${BOLD}📊 STATUS${NC}"
  wg show 2>/dev/null || echo "No tunnel"
  echo -e "\n${GREEN}Services:${NC}"; systemctl status wg-quick@wg0 2>/dev/null | head -8
  echo -e "\n${GREEN}UFW:${NC}"; ufw status 2>/dev/null | head -6
  echo -e "\n${GREEN}NAT Rules:${NC}"; iptables -t nat -L -n | grep -E "(DNAT|SNAT)" || echo "No rules"
  read -p "Press Enter..."
}

fix_forwarding() {
  CLIENT_IP=$(cat /etc/wireguard/client_ip 2>/dev/null || echo "10.1.0.2")
  PORTS=$(cat /etc/wireguard/ports 2>/dev/null || echo "80/tcp,443/tcp")
  INT=$(ip route | grep default | awk '{print $5}' | head -1)
  
  iptables -t nat -F
  for p in $(echo $PORTS | tr ',' '\n'); do
    PORT=$(echo $p | cut -d/ -f1); PROTO=$(echo $p | cut -d/ -f2)
    iptables -t nat -A PREROUTING -p $PROTO --dport $PORT -j DNAT --to $CLIENT_IP
  done
  iptables -t nat -A POSTROUTING -o $INT -j MASQUERADE
  netfilter-persistent save
  systemctl restart wg-quick@wg0
  echo -e "${GREEN}✅ Forwarding fixed${NC}"
}

server_setup() {
  echo -e "${LGREEN}${BOLD}☁️  VPS SERVER${NC}"
  install_prereqs
  
  read -p "Public IP [auto]: " PUBIP
  [[ -z $PUBIP ]] && PUBIP=$(curl -s ifconfig.me)
  read -p "Server IP [10.1.0.1]: " WG_SIP; WG_SIP=${WG_SIP:-10.1.0.1}
  read -p "Client IP [10.1.0.2]: " WG_CIP; WG_CIP=${WG_CIP:-10.1.0.2}
  read -p "UDP Port [55108]: " WGPORT; WGPORT=${WGPORT:-55108}
  read -p "Ports [80/tcp,443/tcp]: " PORTS; PORTS=${PORTS:-"80/tcp,443/tcp"}
  
  mkdir -p /etc/wireguard
  echo $WG_CIP > /etc/wireguard/client_ip
  echo $PORTS > /etc/wireguard/ports
  
  # Generate keys
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  SERVER_PUB=$(cat /etc/wireguard/public.key)
  
  echo -e "\n${YELLOW}${BOLD}=== CLIENT COMMAND ===${NC}"
  echo "sudo $0 client \"$SERVER_PUB\" $PUBIP $WGPORT \"$PORTS\""
  echo -e "${CYAN}Run on LOCAL SERVER, then paste its public key:${NC}"
  read -p "Client Public Key: " CLIENT_PUB
  
  # FIXED CONFIG - No syntax errors
  cat > $WGCONF << 'EOF'
[Interface]
PrivateKey = SERVER_PRIVATE_KEY
Address = WG_SERVER_IP/24
ListenPort = WG_PORT

PostUp = iptables -t nat -A POSTROUTING -o %i -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o %i -j MASQUERADE
EOF
  
  # Add port forwarding rules
  for p in $(echo $PORTS | tr ',' '\n'); do
    PROTO=$(echo $p | cut -d/ -f2); PORT=$(echo $p | cut -d/ -f1)
    echo "PostUp = iptables -t nat -A PREROUTING -p $PROTO --dport $PORT -j DNAT --to $WG_CIP" >> $WGCONF
    echo "PostDown = iptables -t nat -D PREROUTING -p $PROTO --dport $PORT -j DNAT --to $WG_CIP" >> $WGCONF
  done
  
  # Replace variables
  sed -i "s|SERVER_PRIVATE_KEY|$(cat /etc/wireguard/private.key)|g" $WGCONF
  sed -i "s/WG_SERVER_IP/$WG_SIP/g" $WGCONF
  sed -i "s/WG_PORT/$WGPORT/g" $WGCONF
  
  echo "[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = $WG_CIP/32" >> $WGCONF
  
  # Firewall
  ufw reset 2>/dev/null || true
  ufw allow $WGPORT/udp
  ufw allow OpenSSH
  for p in $(echo $PORTS | tr ',' '\n'); do ufw allow $p; done
  ufw enable
  
  systemctl enable --now wg-quick@wg0
  sleep 3
  echo -e "${GREEN}✅ SERVER READY!${NC}"
  fix_forwarding
}

client_setup() {
  SERVER_PUB=$1; PUBIP=$2; WGPORT=$3; PORTS=$4
  WG_CIP="10.1.0.2"; WG_SIP="10.1.0.1"
  
  echo -e "${LGREEN}${BOLD}🏠 LOCAL CLIENT${NC}"
  install_prereqs
  
  mkdir -p /etc/wireguard
  echo $PORTS > /etc/wireguard/ports
  
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  CLIENT_PUB=$(cat /etc/wireguard/public.key)
  
  echo -e "${GREEN}${BOLD}YOUR PUBLIC KEY: $CLIENT_PUB${NC}"
  
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = $WG_CIP/24

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBIP:$WGPORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
  
  systemctl enable --now wg-quick@wg0
  sleep 5
  ping -c 3 $WG_SIP >/dev/null 2>&1 && echo -e "${GREEN}✅ TUNNEL UP${NC}" || echo -e "${YELLOW}Check VPS firewall${NC}"
}

# MAIN MENU
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔══════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║   CGNAT BYPASS v1.1  ║${NC}"
    echo -e "${LGREEN}${BOLD}╠══════════════════════╣${NC}"
    echo -e "${LGREEN}${BOLD}║ 1) ☁️  VPS Server    ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 2) 🏠 Local Client   ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 3) 🔧 Fix Forwarding ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 4) 🔄 Restart        ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 5) 📊 Status         ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 6) 🗑️  Uninstall     ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 7) ❌ Exit           ║${NC}"
    echo -e "${LGREEN}${BOLD}╚══════════════════════╝${NC}"
    
    echo -ne "\n${CYAN}Choose: ${NC}"; read CHOICE
    
    case $CHOICE in
      1) server_setup ;;
      2) echo -e "${YELLOW}Paste VPS command:${NC}"; read CMD; eval $CMD ;;
      3) fix_forwarding ;;
      4) systemctl restart wg-quick@wg0 && echo "${GREEN}Restarted${NC}" || echo "${RED}Failed${NC}" ;;
      5) show_status ;;
      6) uninstall_all ;;
      7) exit ;;
      *) echo "${RED}Invalid${NC}"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in client) shift; client_setup "$@";;
  uninstall|remove) uninstall_all;;
  status) show_status;;
  fix) fix_forwarding;;
  *) main_menu ;;
esac
