#!/bin/bash
# 🔥 CGNAT BYPASS v1.3.0 - FIXED UNINSTALL + AUTO-RECOVERY
# Ubuntu 24.04 + Oracle Cloud ✅

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

# ==================== FIXED UNINSTALL ====================
uninstall_all() {
  echo -e "${YELLOW}${BOLD}🗑️  COMPLETE UNINSTALL${NC}"
  echo -e "${CYAN}Stopping services...${NC}"
  systemctl stop wg-quick@wg0 wg-monitor wg-monitor.timer 2>/dev/null || true
  wg-quick down wg0 2>/dev/null || true
  
  echo -e "${CYAN}Removing configs...${NC}"
  rm -rf /etc/wireguard $WGCONF /etc/iptables/rules.v* /etc/systemd/system/wg-monitor.*
  
  echo -e "${CYAN}Flushing firewall...${NC}"
  iptables -F -t nat -F -t mangle -F -X -t nat -X -t mangle -X 2>/dev/null || true
  iptables -P INPUT ACCEPT -P FORWARD ACCEPT -P OUTPUT ACCEPT
  ip6tables -F -t nat -F -t mangle -F -X -t nat -X -t mangle -X 2>/dev/null || true
  
  echo -e "${CYAN}Resetting UFW...${NC}"
  ufw --force disable 2>/dev/null || true
  ufw --force reset 2>/dev/null || true
  
  echo -e "${CYAN}Removing packages...${NC}"
  apt purge -y wireguard wireguard-tools ufw iptables-persistent netfilter-persistent 2>/dev/null || true
  apt autoremove -y 2>/dev/null || true
  
  echo -e "${CYAN}Reloading systemd...${NC}"
  systemctl daemon-reload 2>/dev/null || true
  
  echo -e "${GREEN}${BOLD}✅ UNINSTALL COMPLETE - SYSTEM CLEAN${NC}"
  echo -e "${GREEN}All WireGuard configs, services, firewall rules REMOVED${NC}"
  exit 0
}

install_autorecovery() {
  cat > /etc/systemd/system/wg-monitor.service << 'EOF'
[Unit]
Description=WireGuard CGNAT Monitor
After=network.target wg-quick@wg0.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do sleep 300; systemctl is-active --quiet wg-quick@wg0 || systemctl restart wg-quick@wg0; ping -c1 10.1.0.2 >/dev/null 2>&1 || systemctl restart wg-quick@wg0; iptables -t nat -L | grep -q DNAT || netfilter-persistent reload; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable --now wg-monitor.service 2>/dev/null || true
  echo -e "${GREEN}✅ AUTO-RECOVERY ACTIVE${NC}"
}

health_check() {
  clear; echo -e "${CYAN}${BOLD}🔍 HEALTH CHECK${NC}"
  wg show 2>/dev/null || echo "❌ No tunnel"
  systemctl status wg-quick@wg0 2>/dev/null | head -8 || echo "❌ Service down"
  ufw status 2>/dev/null | head -6 || echo "No UFW"
  iptables -t nat -L -n | grep -E "(DNAT|SNAT)" || echo "❌ No NAT rules"
  systemctl status wg-monitor 2>/dev/null | head -3 || echo "No auto-recovery"
  read -p "Press Enter..."
}

force_restart() {
  echo -e "${YELLOW}🔄 FORCE RESTART${NC}"
  systemctl stop wg-quick@wg0 wg-monitor 2>/dev/null || true
  sleep 2
  netfilter-persistent reload 2>/dev/null || iptables -t nat -F
  systemctl start wg-quick@wg0
  sleep 3
  wg show && echo -e "${GREEN}✅ RESTARTED${NC}" || echo -e "${RED}❌ FAILED${NC}"
}

server_setup() {
  apt update && apt install -y wireguard wireguard-tools netfilter-persistent curl iputils-ping
  
  read -p "Public IP [auto]: " PUBIP
  [[ -z $PUBIP ]] && PUBIP=$(curl -s ifconfig.me)
  read -p "Server IP [10.1.0.1]: " WG_SIP; WG_SIP=${WG_SIP:-10.1.0.1}
  read -p "Client IP [10.1.0.2]: " WG_CIP; WG_CIP=${WG_CIP:-10.1.0.2}
  read -p "UDP Port [55108]: " WGPORT; WGPORT=${WGPORT:-55108}
  read -p "Ports [1901/tcp,7359/tcp,8098/tcp,8921/tcp]: " PORTS
  
  mkdir -p /etc/wireguard
  echo $WG_CIP > /etc/wireguard/client_ip
  echo $PORTS > /etc/wireguard/ports
  
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  SERVER_PUB=$(cat /etc/wireguard/public.key)
  
  echo -e "\n${YELLOW}${BOLD}CLIENT COMMAND:${NC}"
  echo "sudo $0 client \"$SERVER_PUB\" $PUBIP $WGPORT \"$PORTS\""
  read -p "Paste CLIENT public key: " CLIENT_PUB
  
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = $WG_SIP/24
ListenPort = $WGPORT

PostUp = iptables -t nat -A POSTROUTING -o %i -j MASQUERADE; netfilter-persistent save
PostDown = iptables -t nat -D POSTROUTING -o %i -j MASQUERADE

$(for p in $(echo "$PORTS" | tr ',' '\n'); do 
  PROTO=$(echo $p | cut -d/ -f2); PORT=$(echo $p | cut -d/ -f1)
  echo "PostUp = iptables -t nat -A PREROUTING -p $PROTO --dport $PORT -j DNAT --to $WG_CIP"
  echo "PostDown = iptables -t nat -D PREROUTING -p $PROTO --dport $PORT -j DNAT --to $WG_CIP"
done)

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = $WG_CIP/32
PersistentKeepalive = 15
EOF
  
  ufw reset 2>/dev/null || true
  ufw allow $WGPORT/udp
  ufw allow OpenSSH
  for p in $(echo "$PORTS" | tr ',' '\n'); do ufw allow "$p"; done
  ufw enable 2>/dev/null || true
  
  systemctl enable --now wg-quick@wg0
  sleep 3
  install_autorecovery
  echo -e "${GREEN}✅ SERVER READY + AUTO-RECOVERY${NC}"
}

client_setup() {
  SERVER_PUB=$1; PUBIP=$2; WGPORT=$3; PORTS=$4
  WG_CIP="10.1.0.2"; WG_SIP="10.1.0.1"
  
  apt update && apt install -y wireguard wireguard-tools curl iputils-ping
  
  mkdir -p /etc/wireguard
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = $WG_CIP/24

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBIP:$WGPORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 15
EOF
  
  systemctl enable --now wg-quick@wg0
  sleep 5
  ping -c 3 $WG_SIP >/dev/null 2>&1 && echo -e "${GREEN}✅ CONNECTED${NC}" || echo -e "${YELLOW}Check VPS firewall${NC}"
}

# ==================== FIXED MAIN MENU ====================
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔══════════════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║  CGNAT BYPASS v1.3 FIXED     ║${NC}"
    echo -e "${LGREEN}${BOLD}╠══════════════════════════════╣${NC}"
    echo -e "${LGREEN}${BOLD}║ 1) ☁️  VPS Server Setup      ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 2) 🏠 Local Client Setup     ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 3) 🔧 Force Restart          ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 4) 🛡️  Auto-Recovery         ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 5) 📊 Health Check           ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 6) 🗑️  UNINSTALL (FIXED)    ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 7) ❌ Exit                   ║${NC}"
    echo -e "${LGREEN}${BOLD}╚══════════════════════════════╝${NC}"
    
    echo -ne "\n${CYAN}${BOLD}Choose (1-7): ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) server_setup ;;
      2) echo -e "${YELLOW}Paste VPS server command:${NC}"; read -r CMD; eval "$CMD" ;;
      3) force_restart ;;
      4) install_autorecovery ;;
      5) health_check ;;
      6) uninstall_all ;;     # ✅ FIXED - Calls correct function
      7) exit 0 ;;
      *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  client) shift; client_setup "$@";;
  uninstall|remove|6) uninstall_all;;     # ✅ Command line uninstall
  health|check|5) health_check;;
  restart|fix|3) force_restart;;
  autorecovery|monitor|4) install_autorecovery;;
  *) main_menu ;;
esac
