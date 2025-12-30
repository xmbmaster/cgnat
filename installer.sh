#!/bin/bash
# 🔥 CGNAT BYPASS v7.0 - COMPLETE FIX
# VPS + Local + Full Port Forwarding + Auto-Recovery

if [ $EUID != 0 ]; then
  exec sudo "$0" "$@"
  exit $?
fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

# ==================== SYSTEM SETUP ====================
setup_system() {
  echo -e "${CYAN}Setting up system...${NC}"
  apt update >/dev/null 2>&1
  apt install -y wireguard wireguard-tools curl iputils-ping iptables-persistent netfilter-persistent ufw >/dev/null 2>&1
  
  # Enable IP forwarding
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
  sysctl -w net.ipv4.conf.all.forwarding=1 >/dev/null 2>&1
  
  # Persist IP forwarding
  echo "net.ipv4.ip_forward=1" | tee -a /etc/sysctl.conf >/dev/null
  echo "net.ipv4.conf.all.forwarding=1" | tee -a /etc/sysctl.conf >/dev/null
  sysctl -p >/dev/null 2>&1
  
  echo -e "${GREEN}✅ System setup complete${NC}"
}

# ==================== VPS SERVER SETUP ====================
vps_server() {
  echo -e "${LGREEN}${BOLD}☁️  VPS SERVER SETUP${NC}"
  setup_system

  WGPORT=55108
  WG_SERVER_IP="10.1.0.1"
  WG_CLIENT_IP="10.1.0.2"
  
  # Get public IP
  PUB_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
  read -p "Public IP [$PUB_IP]: " input_ip
  [[ -n "$input_ip" ]] && PUB_IP="$input_ip"
  
  read -p "Service Ports (comma-separated, e.g., 8098,3000,5000) [8098]: " SERVICE_PORTS
  SERVICE_PORTS=${SERVICE_PORTS:-"8098"}
  
  # Create directories
  mkdir -p /etc/wireguard
  chmod 700 /etc/wireguard
  
  # Generate keys
  wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
  chmod 600 /etc/wireguard/server_private.key
  SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)
  
  # Store config
  echo "$WG_CLIENT_IP" > /etc/wireguard/client_ip
  echo "$SERVICE_PORTS" > /etc/wireguard/service_ports
  echo "$PUB_IP" > /etc/wireguard/public_ip
  
  echo ""
  echo -e "${LGREEN}${BOLD}════════════════════════════════════════${NC}"
  echo -e "${LGREEN}${BOLD}CLIENT COMMAND (run on local):${NC}"
  echo -e "${CYAN}${NC}"
  echo -e "${YELLOW}sudo bash $0 client \"$SERVER_PUBLIC_KEY\" $PUB_IP $WGPORT \"$SERVICE_PORTS\"${NC}"
  echo -e "${CYAN}${NC}"
  echo -e "${LGREEN}${BOLD}════════════════════════════════════════${NC}"
  echo ""
  read -p "Paste client public key here: " CLIENT_PUBLIC_KEY
  
  if [[ ${#CLIENT_PUBLIC_KEY} -ne 44 ]]; then
    echo -e "${RED}❌ Invalid key length! Must be 44 characters.${NC}"
    exit 1
  fi
  
  # Create WireGuard config
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/server_private.key)
Address = $WG_SERVER_IP/24
ListenPort = $WGPORT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $WG_CLIENT_IP/32
PersistentKeepalive = 15
EOF

  chmod 600 $WGCONF
  
  # Setup firewall
  echo -e "${CYAN}Setting up firewall...${NC}"
  ufw --force enable >/dev/null 2>&1
  ufw default deny incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  
  # Allow SSH
  ufw allow 22/tcp >/dev/null 2>&1
  ufw allow 22/udp >/dev/null 2>&1
  
  # Allow WireGuard
  ufw allow $WGPORT/udp >/dev/null 2>&1
  
  # Allow service ports
  IFS=',' read -ra PORTS <<< "$SERVICE_PORTS"
  for port in "${PORTS[@]}"; do
    port=$(echo $port | xargs)
    ufw allow $port/tcp >/dev/null 2>&1
    ufw allow $port/udp >/dev/null 2>&1
    echo -e "${GREEN}✅ Allowed port $port${NC}"
  done
  
  # Enable WireGuard
  systemctl enable wg-quick@wg0 >/dev/null 2>&1
  systemctl restart wg-quick@wg0
  sleep 3
  
  # Setup port forwarding with iptables
  echo -e "${CYAN}Setting up port forwarding...${NC}"
  for port in "${PORTS[@]}"; do
    port=$(echo $port | xargs)
    iptables -t nat -A PREROUTING -p tcp --dport $port -j DNAT --to-destination $WG_CLIENT_IP:$port
    iptables -t nat -A PREROUTING -p udp --dport $port -j DNAT --to-destination $WG_CLIENT_IP:$port
    echo -e "${GREEN}✅ Forwarding port $port${NC}"
  done
  
  # Save iptables
  iptables-save > /etc/iptables/rules.v4
  netfilter-persistent save >/dev/null 2>&1
  netfilter-persistent reload >/dev/null 2>&1
  
  # Install monitoring
  install_recovery
  
  echo ""
  echo -e "${GREEN}${BOLD}✅ VPS SERVER READY${NC}"
  echo -e "${CYAN}Check status: wg show${NC}"
}

# ==================== LOCAL CLIENT SETUP ====================
local_client() {
  SERVER_PUB=$1; PUBIP=$2; WGPORT=$3; PORTS=$4
  WG_CLIENT_IP="10.1.0.2"
  WG_SERVER_IP="10.1.0.1"
  
  echo -e "${LGREEN}${BOLD}🏠 LOCAL CLIENT SETUP${NC}"
  setup_system
  
  # Create directories
  mkdir -p /etc/wireguard
  chmod 700 /etc/wireguard
  
  # Generate keys
  wg genkey | tee /etc/wireguard/client_private.key | wg pubkey > /etc/wireguard/client_public.key
  chmod 600 /etc/wireguard/client_private.key
  CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/client_public.key)
  
  echo ""
  echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}YOUR PUBLIC KEY (give to VPS):${NC}"
  echo -e "${YELLOW}$CLIENT_PUBLIC_KEY${NC}"
  echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
  echo ""
  
  # Create WireGuard config
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/client_private.key)
Address = $WG_CLIENT_IP/24
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $PUBIP:$WGPORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 15
EOF

  chmod 600 $WGCONF
  
  # Enable WireGuard
  systemctl enable wg-quick@wg0 >/dev/null 2>&1
  systemctl restart wg-quick@wg0
  sleep 3
  
  # Test connection
  echo -e "${CYAN}Testing connection...${NC}"
  if ping -c 3 $WG_SERVER_IP >/dev/null 2>&1; then
    echo -e "${GREEN}${BOLD}✅ TUNNEL CONNECTED${NC}"
    echo ""
    echo -e "${CYAN}Test your services:${NC}"
    IFS=',' read -ra PORTS <<< "$PORTS"
    for port in "${PORTS[@]}"; do
      port=$(echo $port | xargs)
      echo -e "${YELLOW}  http://$PUBIP:$port${NC}"
    done
  else
    echo -e "${RED}${BOLD}❌ TUNNEL NOT RESPONDING${NC}"
    echo -e "${YELLOW}Check VPS tunnel: wg show${NC}"
    echo -e "${YELLOW}Check firewall: ufw status${NC}"
  fi
  
  install_recovery
}

# ==================== AUTO-RECOVERY MONITOR ====================
install_recovery() {
  cat > /etc/systemd/system/wg-monitor.service << 'EOF'
[Unit]
Description=WireGuard Monitor & Recovery
After=wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do \
  sleep 60; \
  if ! systemctl is-active --quiet wg-quick@wg0; then \
    echo "[$(date)] Tunnel down, restarting..." >> /var/log/wg-monitor.log; \
    systemctl restart wg-quick@wg0; \
  fi; \
done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable --now wg-monitor.service >/dev/null 2>&1
  echo -e "${GREEN}✅ Auto-recovery installed${NC}"
}

# ==================== STATUS CHECK ====================
status_check() {
  clear
  echo -e "${CYAN}${BOLD}🔍 WIREGUARD STATUS${NC}"
  echo ""
  wg show 2>/dev/null || echo -e "${RED}❌ WireGuard not running${NC}"
  
  echo ""
  echo -e "${CYAN}${BOLD}📡 SERVICE STATUS${NC}"
  systemctl status wg-quick@wg0 --no-pager 2>/dev/null | head -15
  
  echo ""
  echo -e "${CYAN}${BOLD}🛡️  FIREWALL STATUS${NC}"
  ufw status | head -20
  
  echo ""
  echo -e "${CYAN}${BOLD}🔀 PORT FORWARDING${NC}"
  iptables -t nat -L -n | grep DNAT || echo "No rules"
  
  echo ""
  read -p "Press Enter to continue..."
}

# ==================== FULL DIAGNOSTIC ====================
full_diagnostic() {
  echo -e "${CYAN}${BOLD}🔧 FULL DIAGNOSTIC${NC}"
  echo ""
  
  echo -e "${YELLOW}1. Checking IP forwarding...${NC}"
  sysctl net.ipv4.ip_forward
  
  echo ""
  echo -e "${YELLOW}2. Checking WireGuard service...${NC}"
  systemctl is-active wg-quick@wg0 && echo -e "${GREEN}✅ Running${NC}" || echo -e "${RED}❌ Stopped${NC}"
  
  echo ""
  echo -e "${YELLOW}3. Checking firewall...${NC}"
  ufw status | grep -E "55108|^Status"
  
  echo ""
  echo -e "${YELLOW}4. Checking iptables rules...${NC}"
  iptables -t nat -L -n | grep -E "DNAT|Chain PREROUTING" || echo "No rules"
  
  echo ""
  echo -e "${YELLOW}5. Checking WireGuard config...${NC}"
  [[ -f $WGCONF ]] && echo -e "${GREEN}✅ Config exists${NC}" || echo -e "${RED}❌ Missing${NC}"
  
  echo ""
  echo -e "${YELLOW}6. Checking service ports...${NC}"
  [[ -f /etc/wireguard/service_ports ]] && cat /etc/wireguard/service_ports || echo "Not set"
  
  echo ""
  read -p "Press Enter to continue..."
}

# ==================== REPAIR ALL ====================
repair_all() {
  echo -e "${YELLOW}${BOLD}🔧 REPAIRING ALL...${NC}"
  
  # Restart services
  systemctl restart wg-quick@wg0
  sleep 2
  
  # Reload firewall
  ufw reload >/dev/null 2>&1
  
  # Reload iptables
  iptables-restore < /etc/iptables/rules.v4 2>/dev/null || true
  netfilter-persistent reload >/dev/null 2>&1
  
  # Restart monitor
  systemctl restart wg-monitor >/dev/null 2>&1
  
  echo -e "${GREEN}${BOLD}✅ REPAIR COMPLETE${NC}"
  sleep 2
}

# ==================== UNINSTALL ====================
uninstall_all() {
  echo -e "${YELLOW}${BOLD}🗑️  SAFE UNINSTALL${NC}"
  echo -e "${RED}This will remove WireGuard completely${NC}"
  read -p "Continue? (yes/no): " confirm
  [[ "$confirm" != "yes" ]] && return
  
  systemctl stop wg-quick@wg0 wg-monitor 2>/dev/null || true
  systemctl disable wg-quick@wg0 wg-monitor 2>/dev/null || true
  
  rm -rf /etc/wireguard $WGCONF /etc/systemd/system/wg-monitor* 2>/dev/null || true
  apt purge -y wireguard wireguard-tools 2>/dev/null || true
  
  echo -e "${GREEN}${BOLD}✅ UNINSTALL COMPLETE${NC}"
  echo -e "${CYAN}CasaOS & other services remain intact${NC}"
  exit 0
}

# ==================== MAIN MENU ====================
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔═══════════════════════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║     CGNAT BYPASS v7.0 - COMPLETE      ║${NC}"
    echo -e "${LGREEN}${BOLD}║    PRODUCTION READY SYSTEM             ║${NC}"
    echo -e "${LGREEN}${BOLD}╠═══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  1) ☁️  VPS Server Setup               ║${NC}"
    echo -e "${CYAN}║  2) 🏠 Local Client Setup              ║${NC}"
    echo -e "${CYAN}║  3) 🔍 Status Check                   ║${NC}"
    echo -e "${CYAN}║  4) 🔧 Full Diagnostic                ║${NC}"
    echo -e "${CYAN}║  5) 🔨 Repair All                     ║${NC}"
    echo -e "${LGREEN}║  6) 🛡️  Install Auto-Recovery         ║${NC}"
    echo -e "${RED}║  7) 🗑️  Complete Uninstall            ║${NC}"
    echo -e "${CYAN}║  8) ❌ Exit                            ║${NC}"
    echo -e "${LGREEN}${BOLD}╚═══════════════════════════════════════╝${NC}"
    
    echo -ne "\n${CYAN}Choose (1-8): ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) vps_server ;;
      2) 
        echo -e "${YELLOW}Paste the CLIENT command from VPS output:${NC}"
        read CMD
        eval "$CMD"
        ;;
      3) status_check ;;
      4) full_diagnostic ;;
      5) repair_all ;;
      6) install_recovery ;;
      7) uninstall_all ;;
      8) exit 0 ;;
      *) echo -e "${RED}Invalid choice${NC}"; sleep 1 ;;
    esac
  done
}

# ==================== ENTRY POINT ====================
case "${1:-}" in
  client) shift; local_client "$@" ;;
  uninstall|7) uninstall_all ;;
  status|3) status_check ;;
  diagnostic|4) full_diagnostic ;;
  repair|5) repair_all ;;
  recovery|6) install_recovery ;;
  *) main_menu ;;
esac
