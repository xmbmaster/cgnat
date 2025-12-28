#!/bin/bash
# 🔥 CGNAT BYPASS WireGuard ALL-IN-ONE (v1.0.0) - FIXED TRAFFIC + MENU
# Works: Ubuntu/Oracle Cloud 2025 | All ports forward correctly

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

# ==================== FUNCTIONS ====================
uninstall_all() {
  echo -e "${YELLOW}${BOLD}🗑️  FULL UNINSTALL${NC}"
  systemctl stop wg-quick@wg0 2>/dev/null; wg-quick down wg0 2>/dev/null
  rm -f $WGCONF /etc/wireguard/* /etc/iptables/rules.v*
  iptables -F -t nat -F -t mangle -F -X -t nat -X -t mangle -X
  iptables -P INPUT ACCEPT -P FORWARD ACCEPT -P OUTPUT ACCEPT
  ufw --force disable >/dev/null 2>&1; ufw --force reset >/dev/null 2>&1
  apt purge -y wireguard wireguard-tools ufw iptables-persistent netfilter-persistent 2>/dev/null || true
  apt autoremove -y; sysctl -p 2>/dev/null
  echo -e "${GREEN}${BOLD}✅ CLEAN UNINSTALL COMPLETE${NC}"; exit 0
}

get_public_info() {
  PUBIP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "DETECT")
  INT=$(ip route | grep default | awk '{print $5}' | head -1)
  [[ -z $INT ]] && INT=$(ip -o link | awk -F': ' '{print $2}' | grep -E '^(eth|ens)' | head -1)
  WGPORT=${WGPORT:-55108}
  echo "$PUBIP $INT"
}

show_status() {
  clear; echo -e "${CYAN}${BOLD}📊 TUNNEL STATUS${NC}"
  echo "=== WireGuard ==="
  wg show 2>/dev/null || echo "❌ No tunnel active"
  echo -ne "\n=== Services ===\n"
  systemctl status wg-quick@wg0 2>/dev/null | head -10
  echo -ne "\n=== UFW ===\n"
  ufw status 2>/dev/null | head -8
  echo -ne "\n=== iptables NAT ===\n"
  iptables -t nat -L -n -v | grep -E "(DNAT|SNAT)" || echo "❌ No forwarding rules"
  echo -ne "\n${YELLOW}Press Enter...${NC}"; read
}

fix_traffic_forwarding() {
  echo -e "${LGREEN}${BOLD}🔧 FIXING TRAFFIC FORWARDING${NC}"
  
  CLIENT_IP=$(cat /etc/wireguard/client_ip 2>/dev/null || echo "10.1.0.2")
  PORTS=$(cat /etc/wireguard/ports 2>/dev/null || echo "80/tcp,443/tcp")
  INT=$(get_public_info | cut -d' ' -f2)
  PUBIP=$(get_public_info | cut -d' ' -f1)
  
  # Clear broken rules
  iptables -t nat -F PREROUTING; iptables -t nat -F POSTROUTING
  
  # IP Forwarding
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  sysctl -p
  
  # Add NAT rules for ALL ports
  for p in $(echo $PORTS | tr ',' '\n'); do
    PORT=$(echo $p | cut -d/ -f1); PROTO=$(echo $p | cut -d/ -f2)
    echo "➤ Forwarding ${PROTO^^} $PORT → $CLIENT_IP"
    iptables -t nat -A PREROUTING -p $PROTO --dport $PORT -j DNAT --to $CLIENT_IP
  done
  
  # SNAT for return traffic
  iptables -t nat -A POSTROUTING -o $INT -j SNAT --to-source $PUBIP
  
  # Install persistent
  apt install -y iptables-persistent netfilter-persistent
  netfilter-persistent save
  
  # Fix UFW
  ufw --force reset
  WGPORT=$(wg show wg0 listen-port 2>/dev/null || ss -ulnp | grep wireguard | awk '{print $4}' | cut -d: -f2 || echo 55108)
  ufw allow $WGPORT/udp; ufw allow OpenSSH
  for p in $(echo $PORTS | tr ',' '\n'); do ufw allow $p; done
  ufw --force enable
  
  systemctl restart wg-quick@wg0
  echo -e "${GREEN}${BOLD}✅ TRAFFIC FIXED! Test: curl VPS_IP:YOUR_PORT${NC}"
}

server_setup() {
  echo -e "${LGREEN}${BOLD}☁️  VPS SERVER SETUP${NC}"
  apt update && apt install -y wireguard wireguard-tools ufw iptables-persistent iputils-ping curl
  
  read -p "VPS Public IP [auto]: " PUBIP
  [[ -z $PUBIP ]] && PUBIP=$(get_public_info | cut -d' ' -f1)
  read -p "WG Server IP [10.1.0.1]: " WG_SIP; WG_SIP=${WG_SIP:-10.1.0.1}
  read -p "WG Client IP [10.1.0.2]: " WG_CIP; WG_CIP=${WG_CIP:-10.1.0.2}
  read -p "WG UDP Port [55108]: " WGPORT; WGPORT=${WGPORT:-55108}
  read -p "Service Ports [80/tcp,443/tcp,1901/tcp,8096/tcp]: " PORTS
  
  mkdir -p /etc/wireguard
  echo $WG_CIP > /etc/wireguard/client_ip
  echo $PORTS > /etc/wireguard/ports
  
  # Generate keys
  wg genkey | tee /etc/wireguard/private | wg pubkey > /etc/wireguard/publickey
  SERVER_PUB=$(cat /etc/wireguard/publickey)
  
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private)
Address = $WG_SIP/24
ListenPort = $WGPORT

PostUp = iptables -t nat -A POSTROUTING -o %i -j SNAT --to-source $PUBIP
PostDown = iptables -t nat -D POSTROUTING -o %i -j SNAT --to-source $PUBIP

$(for p in $(echo $PORTS | tr ',' '\n'); do 
  proto=\$(echo \$p | cut -d/ -f2); port=\$(echo \$p | cut -d/ -f1)
  echo "PostUp = iptables -t nat -A PREROUTING -p \$proto --dport \$port -j DNAT --to $WG_CIP"
  echo "PostDown = iptables -t nat -D PREROUTING -p \$proto --dport \$port -j DNAT --to $WG_CIP"
done)

[Peer]
PublicKey = PLACEHOLDER_CLIENT_PUBKEY
AllowedIPs = $WG_CIP/32
EOF
  
  echo -e "\n${YELLOW}${BOLD}📱 CLIENT SETUP COMMAND:${NC}"
  echo "sudo $0 client \"$SERVER_PUB\" $PUBIP $WGPORT \"$PORTS\""
  echo -e "${CYAN}Run this on your LOCAL SERVER, then paste CLIENT public key here:${NC}"
  read -p "Client Public Key: " CLIENT_PUB
  
  sed -i "s/PLACEHOLDER_CLIENT_PUBKEY/$CLIENT_PUB/" $WGCONF
  
  systemctl enable --now wg-quick@wg0
  sleep 3; fix_traffic_forwarding
  echo -e "${GREEN}${BOLD}✅ SERVER READY!${NC}"
}

client_setup() {
  SERVER_PUB=$1; PUBIP=$2; WGPORT=${3:-55108}; PORTS=${4:-"80/tcp,443/tcp"}
  WG_CIP=10.1.0.2; WG_SIP=10.1.0.1
  
  echo -e "${LGREEN}${BOLD}🏠 LOCAL CLIENT SETUP${NC}"
  apt update && apt install -y wireguard wireguard-tools iputils-ping curl
  
  mkdir -p /etc/wireguard
  echo $PORTS > /etc/wireguard/ports
  
  wg genkey | tee /etc/wireguard/private | wg pubkey > /etc/wireguard/publickey
  CLIENT_PUB=$(cat /etc/wireguard/publickey)
  
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
  sleep 5
  if ping -c 3 $WG_SIP >/dev/null 2>&1; then
    echo -e "${GREEN}${BOLD}✅ CLIENT CONNECTED! Tunnel UP${NC}"
  else
    echo -e "${YELLOW}❌ Ping failed - check VPS firewall/Oracle VCN${NC}"
  fi
  echo -e "${GREEN}Your Public Key: $CLIENT_PUB${NC}"
}

# ==================== MAIN MENU ====================
main_menu() {
  while true; do
    clear
    PUBINFO=$(get_public_info)
    echo -e "${LGREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║        CGNAT BYPASS v1.0.0           ║${NC}"
    echo -e "${LGREEN}${BOLD}║     WireGuard Tunnel Manager         ║${NC}"
    echo -e "${LGREEN}${BOLD}╠══════════════════════════════════════╣${NC}"
    
    if [[ -f $WGCONF ]]; then
      if grep -q "Endpoint" $WGCONF; then
        echo -e "${YELLOW}║  🏠 LOCAL CLIENT $(ping -c1 10.1.0.1 >/dev/null 2>&1 && echo "✅ UP" || echo "❌ DOWN")    ║${NC}"
      else
        echo -e "${YELLOW}║  ☁️  VPS SERVER $(ping -c1 10.1.0.2 >/dev/null 2>&1 && echo "✅ UP" || echo "⏳ WAIT") ║${NC}"
      fi
    fi
    
    echo -e "${LGREEN}${BOLD}║                                      ║${NC}"
    echo -e "${LGREEN}${BOLD}║  1) ☁️  VPS SERVER Setup             ║${NC}"
    echo -e "${LGREEN}${BOLD}║  2) 🏠 Local CLIENT Setup            ║${NC}"
    echo -e "${LGREEN}${BOLD}║  3) 🔧 Fix Traffic/Ports             ║${NC}"
    echo -e "${LGREEN}${BOLD}║  4) 🔄 Restart Tunnel                ║${NC}"
    echo -e "${LGREEN}${BOLD}║  5) 📊 Status Check                  ║${NC}"
    echo -e "${LGREEN}${BOLD}║  6) 🗑️  FULL UNINSTALL              ║${NC}"
    echo -e "${LGREEN}${BOLD}║  7) ❌ Exit                          ║${NC}"
    echo -e "${LGREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
    
    echo -ne "\n${CYAN}${BOLD}Choose (1-7): ${NC}"; read -r CHOICE
    
    case $CHOICE in
      1) server_setup ;;
      2) echo -e "${YELLOW}Paste VPS server command:${NC}"; read -r CMD; eval $CMD ;;
      3) fix_traffic_forwarding ;;
      4) systemctl restart wg-quick@wg0 && echo -e "${GREEN}🔄 Restarted${NC}" || echo -e "${RED}Failed${NC}" ;;
      5) show_status ;;
      6) uninstall_all ;;
      7) exit 0 ;;
      *) echo -e "${RED}Invalid${NC}"; sleep 1 ;;
    esac
  done
}

# Command line args
case "${1:-}" in
  client) shift; client_setup "$@";;
  uninstall|remove) uninstall_all;;
  status|check) show_status;;
  fix|repair) fix_traffic_forwarding;;
  *) main_menu ;;
esac
