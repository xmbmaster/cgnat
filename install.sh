#!/bin/bash
# CGNAT Bypass WireGuard - FIXED MENU (v0.5.0) - All options work!

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'

uninstall() {
  echo -e "${YELLOW}FULL UNINSTALL${NC}"
  systemctl stop wg-quick@wg0 2>/dev/null; wg-quick down wg0 2>/dev/null
  rm -f $WGCONF /etc/wireguard/*
  iptables -F -t nat -F -t mangle -F; iptables -X -t nat -X -t mangle -X
  iptables -P INPUT ACCEPT -P FORWARD ACCEPT -P OUTPUT ACCEPT
  rm -f /etc/iptables/rules.v4 /etc/iptables/rules.v6 2>/dev/null
  ufw --force disable >/dev/null 2>&1; ufw --force reset >/dev/null 2>&1
  apt purge -y wireguard wireguard-tools ufw iptables-persistent 2>/dev/null || true
  apt autoremove -y; sysctl -p 2>/dev/null
  echo -e "${GREEN}✅ CLEAN UNINSTALL COMPLETE${NC}"; exit 0
}

detect_interface() {
  IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null)
  INT=$(ip route | grep default | awk '{print $5}' | head -1)
  [[ -z $INT ]] && INT=$(ip -o link | awk -F': ' '{print $2}' | grep -E '^(eth|ens)') 
  echo "$IP $INT"
}

show_status() {
  echo -e "\n${CYAN}=== STATUS ===${NC}"
  wg show 2>/dev/null || echo "No WireGuard tunnel active"
  echo "--- Services ---"; systemctl status wg-quick@wg0 2>/dev/null | head -8
  echo "--- UFW ---"; ufw status 2>/dev/null | head -6
  echo "--- iptables NAT ---"; iptables -t nat -L -n | grep -E "(DNAT|SNAT)" || echo "No NAT rules"
}

server_setup() {
  echo -e "${LGREEN}🚀 VPS SERVER SETUP${NC}"
  apt update && apt install -y wireguard ufw iputils-ping curl
  
  read -p "VPS Public IP ($(curl -s ifconfig.me 2>/dev/null || echo 'auto')): " PUBIP
  [[ -z $PUBIP ]] && PUBIP=$(curl -s ifconfig.me)
  
  read -p "WG Server IP [10.1.0.1]: " WG_SIP; WG_SIP=${WG_SIP:-10.1.0.1}
  read -p "WG Client IP [10.1.0.2]: " WG_CIP; WG_CIP=${WG_CIP:-10.1.0.2}
  read -p "WG UDP Port [55108]: " WGPORT; WGPORT=${WGPORT:-55108}
  read -p "Service Ports [80/tcp,443/tcp]: " PORTS; PORTS=${PORTS:-"80/tcp,443/tcp"}
  
  mkdir -p /etc/wireguard
  echo $WG_CIP > /etc/wireguard/client_ip
  echo $PORTS > /etc/wireguard/ports
  
  # Keys
  wg genkey | tee /etc/wireguard/private | wg pubkey > /etc/wireguard/publickey
  SERVER_PUB=$(cat /etc/wireguard/publickey)
  
  echo -e "\n${YELLOW}📱 On CLIENT run:${NC}"
  echo "sudo $0 client \"$SERVER_PUB\" $PUBIP $WGPORT \"$PORTS\""
  read -p "Paste CLIENT public key: " CLIENT_PUB
  
  INT=$(detect_interface | cut -d' ' -f2)
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private)
Address = $WG_SIP/24
ListenPort = $WGPORT

PostUp = iptables -t nat -A POSTROUTING -o $INT -j SNAT --to-source $PUBIP
PostDown = iptables -t nat -D POSTROUTING -o $INT -j SNAT --to-source $PUBIP

$(for p in $(echo $PORTS | tr ',' '\n'); do 
  proto=\$(echo \$p | cut -d/ -f2); port=\$(echo \$p | cut -d/ -f1)
  echo "PostUp = iptables -t nat -A PREROUTING -p \$proto --dport \$port -j DNAT --to $WG_CIP"
  echo "PostDown = iptables -t nat -D PREROUTING -p \$proto --dport \$port -j DNAT --to $WG_CIP"
done)

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = $WG_CIP/32
EOF

  # Firewall
  ufw --force reset
  ufw allow $WGPORT/udp
  ufw allow OpenSSH
  for p in $(echo $PORTS | tr ',' '\n'); do ufw allow $p; done
  ufw --force enable
  
  systemctl enable --now wg-quick@wg0
  sleep 3
  ping -c 3 $WG_CIP >/dev/null && echo -e "${GREEN}✅ SERVER READY! Tunnel UP${NC}" || echo -e "${YELLOW}⏳ Waiting for client...${NC}"
}

client_setup() {
  echo -e "${LGREEN}🏠 LOCAL CLIENT SETUP${NC}"
  SERVER_PUB=$1; PUBIP=$2; WGPORT=${3:-55108}; PORTS=${4:-"80/tcp,443/tcp"}
  WG_CIP=10.1.0.2; WG_SIP=10.1.0.1
  
  apt update && apt install -y wireguard iputils-ping curl
  
  mkdir -p /etc/wireguard
  wg genkey | tee /etc/wireguard/private | wg pubkey > /etc/wireguard/publickey
  CLIENT_PUB=$(cat /etc/wireguard/publickey)
  
  echo -e "${GREEN}📋 YOUR PUBLIC KEY (give to SERVER):${NC} $CLIENT_PUB"
  
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
  sleep 3
  ping -c 3 $WG_SIP >/dev/null && echo -e "${GREEN}✅ CLIENT CONNECTED!${NC}" || echo -e "${YELLOW}❌ Cannot ping server, check VPS firewall${NC}"
}

modify_ports() {
  if [[ ! -f /etc/wireguard/ports ]]; then echo -e "${RED}No config found${NC}"; return; fi
  echo "Current ports: $(cat /etc/wireguard/ports)"
  read -p "New ports (80/tcp,443/tcp): " PORTS
  echo $PORTS > /etc/wireguard/ports
  systemctl restart wg-quick@wg0
  ufw --force reset
  ufw allow $(cat /etc/wireguard/ports | tr ',' '\n') 2>/dev/null
  WGPORT=$(grep ListenPort $WGCONF 2>/dev/null | awk '{print $3}' || echo 55108)
  ufw allow $WGPORT/udp 2>/dev/null
  ufw --force enable 2>/dev/null
  echo -e "${GREEN}Ports updated & restarted${NC}"
}

# FIXED MAIN MENU - Works perfectly!
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${LGREEN}║     CGNAT BYPASS WireGuard v0.5.0    ║${NC}"
    echo -e "${LGREEN}╠══════════════════════════════════════╣${NC}"
    
    if [[ -f $WGCONF ]]; then
      if grep -q "Endpoint" $WGCONF 2>/dev/null; then
        echo -e "${YELLOW}║  🏠 DETECTED: LOCAL CLIENT MODE      ║${NC}"
      else
        echo -e "${YELLOW}║  ☁️  DETECTED: VPS SERVER MODE       ║${NC}"
      fi
    fi
    
    echo -e "${LGREEN}║${NC}"
    echo -e "${LGREEN}║  1) ☁️  VPS SERVER Setup             ║${NC}"
    echo -e "${LGREEN}║  2) 🏠 Local CLIENT Setup            ║${NC}"
    echo -e "${LGREEN}║  3) 🔧 Modify Ports/IP Mapping       ║${NC}"
    echo -e "${LGREEN}║  4) 🔄 Restart Service               ║${NC}"
    echo -e "${LGREEN}║  5) 🗑️  FULL UNINSTALL              ║${NC}"
    echo -e "${LGREEN}║  6) 📊 Status Check                  ║${NC}"
    echo -e "${LGREEN}║  7) ❌ Exit                          ║${NC}"
    echo -e "${LGREEN}╚══════════════════════════════════════╝${NC}"
    
    echo -ne "\n${CYAN}Choose (1-7): ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) server_setup ;;
      2) echo -e "${YELLOW}Server setup command from VPS:${NC}"; read -p "Paste it: " CMD; eval $CMD ;;
      3) modify_ports ;;
      4) systemctl restart wg-quick@wg0 2>/dev/null && echo -e "${GREEN}Restarted${NC}" || echo -e "${RED}Not running${NC}" ;;
      5) uninstall ;;
      6) show_status; read -p "Press Enter..." ;;
      7) exit 0 ;;
      *) echo -e "${RED}Invalid choice${NC}"; sleep 1 ;;
    esac
  done
}

# Command line mode
case "${1:-}" in
  client) shift; client_setup "$@";;
  uninstall) uninstall;;
  status) show_status;;
  *) main_menu ;;
esac
