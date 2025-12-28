#!/bin/bash
# 🔥 CGNAT BYPASS v1.2.0 - AUTO-RECOVERY (Never Dies!)
# Auto-restarts every 5min + Health checks

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

# ==================== AUTO-RECOVERY SYSTEM ====================
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
  
  cat > /etc/systemd/system/wg-monitor.timer << 'EOF'
[Unit]
Description=Run WG Monitor every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
  
  systemctl daemon-reload
  systemctl enable --now wg-monitor.timer wg-monitor.service
  echo -e "${GREEN}✅ AUTO-RECOVERY INSTALLED (5min checks)${NC}"
}

# ==================== HEALTH CHECK ====================
health_check() {
  clear; echo -e "${CYAN}${BOLD}🔍 HEALTH CHECK${NC}"
  
  STATUS="🟢 UP"
  [[ ! -f $WGCONF ]] && STATUS="🔴 NO CONFIG"
  
  WG_UP=$(wg show wg0 2>/dev/null | grep -c "transfer:")
  [[ $WG_UP -eq 0 ]] && STATUS="🟡 NO TRAFFIC"
  
  PING_VPS=$(ping -c1 10.1.0.1 >/dev/null 2>&1 && echo "🟢" || echo "🔴")
  PING_CLIENT=$(ping -c1 10.1.0.2 >/dev/null 2>&1 && echo "🟢" || echo "🔴")
  
  NAT_RULES=$(iptables -t nat -L | grep -c DNAT)
  [[ $NAT_RULES -eq 0 ]] && STATUS="🟡 NO FORWARDING"
  
  echo -e "${LGREEN}Tunnel: $STATUS${NC}"
  echo -e "VPS Ping: $PING_VPS | Client Ping: $PING_CLIENT${NC}"
  echo -e "NAT Rules: $NAT_RULES | Auto-Recovery: $(systemctl is-active wg-monitor.timer 2>/dev/null && echo "🟢" || echo "🔴")${NC}"
  
  wg show 2>/dev/null || echo "No WG tunnel"
  read -p "Press Enter..."
}

# ==================== FORCE RESTART ====================
force_restart() {
  echo -e "${YELLOW}🔄 FORCE RESTARTING...${NC}"
  systemctl stop wg-quick@wg0 2>/dev/null
  wg-quick down wg0 2>/dev/null
  sleep 2
  
  # Reload iptables
  netfilter-persistent reload 2>/dev/null || iptables -t nat -F
  
  # Restart tunnel
  systemctl start wg-quick@wg0
  sleep 5
  
  # Verify
  if wg show wg0 >/dev/null 2>&1; then
    echo -e "${GREEN}✅ RESTARTED SUCCESSFULLY${NC}"
  else
    echo -e "${RED}❌ RESTART FAILED${NC}"
  fi
}

# ==================== FIXED SETUP (from previous) ====================
server_setup() {
  echo -e "${LGREEN}${BOLD}☁️  VPS SERVER + AUTO-RECOVERY${NC}"
  
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
  read -p "Client Public Key: " CLIENT_PUB
  
  # PERFECT CONFIG
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = $WG_SIP/24
ListenPort = $WGPORT

PostUp = iptables -t nat -A POSTROUTING -o %i -j MASQUERADE; netfilter-persistent save
PostDown = iptables -t nat -D POSTROUTING -o %i -j MASQUERADE; netfilter-persistent save

$(for p in $(echo $PORTS | tr ',' '\n'); do 
  PROTO=$(echo $p | cut -d/ -f2); PORT=$(echo $p | cut -d/ -f1)
  echo "PostUp = iptables -t nat -A PREROUTING -p $PROTO --dport $PORT -j DNAT --to $WG_CIP"
  echo "PostDown = iptables -t nat -D PREROUTING -p $PROTO --dport $PORT -j DNAT --to $WG_CIP"
done)

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = $WG_CIP/32
PersistentKeepalive = 15
EOF
  
  # UFW + iptables
  ufw reset >/dev/null 2>&1
  ufw allow $WGPORT/udp
  ufw allow OpenSSH
  for p in $(echo $PORTS | tr ',' '\n'); do ufw allow $p; done
  ufw enable
  
  systemctl enable --now wg-quick@wg0
  sleep 3
  
  # INSTALL AUTO-RECOVERY
  install_autorecovery
  
  echo -e "${GREEN}✅ SERVER + AUTO-RECOVERY INSTALLED${NC}"
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
  ping -c 3 $WG_SIP >/dev/null 2>&1 && echo -e "${GREEN}✅ CONNECTED${NC}" || echo -e "${YELLOW}Check VPS${NC}"
}

# ==================== MAIN MENU ====================
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔══════════════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║  CGNAT BYPASS v1.2 AUTO-FIX  ║${NC}"
    echo -e "${LGREEN}${BOLD}╠══════════════════════════════╣${NC}"
    echo -e "${LGREEN}${BOLD}║ 1) ☁️  VPS Server Setup      ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 2) 🏠 Local Client           ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 3) 🔧 Force Restart          ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 4) 🛡️  Install Auto-Recovery ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 5) 📊 Health Check           ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 6) 🗑️  Uninstall             ║${NC}"
    echo -e "${LGREEN}${BOLD}║ 7) ❌ Exit                   ║${NC}"
    echo -e "${LGREEN}${BOLD}╚══════════════════════════════╝${NC}"
    
    echo -ne "\n${CYAN}Choose: ${NC}"; read CHOICE
    
    case $CHOICE in
      1) server_setup ;;
      2) echo -e "${YELLOW}Paste VPS command:${NC}"; read CMD; eval $CMD ;;
      3) force_restart ;;
      4) install_autorecovery ;;
      5) health_check ;;
      6) uninstall_all ;;
      7) exit ;;
      *) echo -e "${RED}Invalid${NC}"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  client) shift; client_setup "$@";;
  autorecovery|monitor) install_autorecovery;;
  health|check) health_check;;
  restart|fix) force_restart;;
  *) main_menu ;;
esac
