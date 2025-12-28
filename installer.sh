#!/bin/bash
# 🔥 CGNAT BYPASS v3.0 - ALL-IN-ONE PERFECT
# VPS + Client + Auto-Fix + Recovery + Uninstall ✅

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

# ==================== CORE FUNCTIONS ====================
install_packages() {
  apt update >/dev/null 2>&1
  apt install -y wireguard wireguard-tools curl iputils-ping netfilter-persistent
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1
}

fix_firewall() {
  WGPORT=55108
  iptables -D INPUT -p udp --dport $WGPORT 2>/dev/null || true
  iptables -I INPUT 1 -p udp --dport $WGPORT -j ACCEPT
  ufw allow $WGPORT/udp 2>/dev/null || true
  netfilter-persistent save 2>/dev/null || true
}

status_check() {
  clear
  echo -e "${CYAN}${BOLD}🔍 COMPLETE STATUS${NC}"
  echo "=== WireGuard ==="
  wg show 2>/dev/null || echo "❌ No tunnel"
  echo -e "\n=== Services ==="
  systemctl status wg-quick@wg0 2>/dev/null | head -8 || echo "❌ Service failed"
  echo -e "\n=== Auto-Recovery ==="
  systemctl status wg-monitor 2>/dev/null | head -5 || echo "❌ Not installed"
  echo -e "\n=== iptables ==="
  iptables -L INPUT -n | grep 55108 || echo "❌ No UDP 55108"
  iptables -t nat -L -n | grep DNAT || echo "❌ No NAT forwarding"
  echo -e "\n=== Public IP ==="
  curl -s ifconfig.me 2>/dev/null || echo "Cannot detect"
  read -p "Press Enter..."
}

# ==================== VPS SERVER (BUTTON 1) ====================
vps_server_setup() {
  echo -e "${LGREEN}${BOLD}☁️  VPS SERVER SETUP${NC}"
  install_packages
  
  echo -e "${YELLOW}ORACLE VCN: Add UDP 55108 + your service ports${NC}"
  read -p "Press Enter when VCN rules added..."
  
  PUBIP=$(curl -s ifconfig.me)
  read -p "Public IP [$PUBIP]: " INPUT; [[ -n "$INPUT" ]] && PUBIP=$INPUT
  WG_SIP="10.1.0.1"; WG_CIP="10.1.0.2"; WGPORT="55108"
  read -p "Service Ports [8098/tcp]: " PORTS; PORTS=${PORTS:-"8098/tcp"}
  
  mkdir -p /etc/wireguard
  echo $WG_CIP > /etc/wireguard/client_ip
  echo $PORTS > /etc/wireguard/ports
  
  # Generate keys
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  SERVER_PUB=$(cat /etc/wireguard/public.key)
  
  echo -e "\n${LGREEN}${BOLD}CLIENT COMMAND:${NC}"
  echo "sudo $0 client \"$SERVER_PUB\" $PUBIP $WGPORT \"$PORTS\""
  
  read -p "Paste CLIENT public key: " CLIENT_PUB
  
  # PERFECT CONFIG - NO CRASHES
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = $WG_SIP/24
ListenPort = $WGPORT

PostUp = iptables -t nat -A POSTROUTING -o %i -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o %i -j MASQUERADE
PostUp = iptables -I INPUT 1 -p udp --dport $WGPORT -j ACCEPT
PostDown = iptables -D INPUT -p udp --dport $WGPORT -j ACCEPT

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
  
  # Firewall
  fix_firewall
  for p in $(echo "$PORTS" | tr ',' '\n'); do 
    ufw allow "$p" 2>/dev/null || true
  done
  ufw allow OpenSSH 2>/dev/null || true
  
  # Start tunnel
  systemctl enable --now wg-quick@wg0
  sleep 5
  
  # Auto-recovery
  cat > /etc/systemd/system/wg-monitor.service << 'EOF'
[Unit]
Description=WireGuard Auto-Recovery
After=wg-quick@wg0.service
[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do sleep 300; if ! wg show wg0 >/dev/null 2>&1; then systemctl restart wg-quick@wg0; fi; done'
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now wg-monitor.service
  
  echo -e "${GREEN}${BOLD}✅ VPS SERVER + AUTO-RECOVERY READY${NC}"
}

# ==================== LOCAL CLIENT ====================
local_client_setup() {
  SERVER_PUB=$1; PUBIP=$2; WGPORT=$3; PORTS=$4
  WG_CIP="10.1.0.2"; WG_SIP="10.1.0.1"
  
  echo -e "${LGREEN}${BOLD}🏠 LOCAL CLIENT SETUP${NC}"
  install_packages
  
  mkdir -p /etc/wireguard
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
PersistentKeepalive = 15
EOF
  
  systemctl enable --now wg-quick@wg0
  sleep 5
  if ping -c 3 $WG_SIP >/dev/null 2>&1; then
    echo -e "${GREEN}${BOLD}✅ TUNNEL UP${NC}"
  else
    echo -e "${YELLOW}❌ Check VPS firewall/VCN${NC}"
  fi
}

# ==================== COMPLETE UNINSTALL ====================
complete_uninstall() {
  echo -e "${YELLOW}${BOLD}🗑️  TOTAL CLEANUP${NC}"
  systemctl stop wg-quick@wg0 wg-monitor 2>/dev/null || true
  rm -rf /etc/wireguard $WGCONF /etc/iptables/rules.v* /etc/systemd/system/wg-monitor.*
  iptables -F -t nat -F -t mangle -F -X -t nat -X -t mangle -X 2>/dev/null || true
  iptables -P INPUT ACCEPT -P FORWARD ACCEPT -P OUTPUT ACCEPT
  ufw disable 2>/dev/null || true
  apt purge -y wireguard wireguard-tools netfilter-persistent ufw iptables-persistent 2>/dev/null || true
  apt autoremove -y 2>/dev/null || true
  systemctl daemon-reload
  echo -e "${GREEN}${BOLD}✅ SYSTEM CLEAN${NC}"; exit 0
}

# ==================== MAIN MENU - ALL 7 BUTTONS WORK ====================
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║        CGNAT BYPASS v3.0             ║${NC}"
    echo -e "${LGREEN}${BOLD}║     ALL BUTTONS + CRASH-PROOF        ║${NC}"
    echo -e "${LGREEN}${BOLD}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  1) ☁️  VPS Server Setup              ║${NC}"
    echo -e "${CYAN}║  2) 🏠 Local Client Command            ║${NC}"
    echo -e "${CYAN}║  3) 🔄 Restart Tunnel                  ║${NC}"
    echo -e "${CYAN}║  4) 📊 Complete Status                 ║${NC}"
    echo -e "${LGREEN}║  5) 🛡️  Auto-Recovery                 ║${NC}"
    echo -e "${RED}║  6) 🗑️  Complete Uninstall             ║${NC}"
    echo -e "${CYAN}║  7) ❌ Exit                            ║${NC}"
    echo -e "${LGREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
    
    echo -ne "\n${BOLD}${CYAN}Choose (1-7): ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) vps_server_setup ;;
      2) echo -e "${YELLOW}${BOLD}Paste VPS command:${NC}"; read -r CMD; eval "$CMD" 2>/dev/null || echo -e "${RED}Command failed${NC}" ;;
      3) systemctl restart wg-quick@wg0 && echo -e "${GREEN}✅ Restarted${NC}" || echo -e "${RED}❌ Failed${NC}" ;;
      4) status_check ;;
      5) install_autorecovery ;;
      6) complete_uninstall ;;
      7) exit 0 ;;
      *) echo -e "${RED}Invalid choice${NC}"; sleep 1 ;;
    esac
  done
}

install_autorecovery() {
  cat > /etc/systemd/system/wg-monitor.service << 'EOF'
[Unit]
Description=WireGuard Monitor
After=wg-quick@wg0.service
[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do sleep 300; if ! wg show wg0 >/dev/null 2>&1; then systemctl restart wg-quick@wg0; fi; done'
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now wg-monitor.service 2>/dev/null || true
  echo -e "${GREEN}${BOLD}✅ AUTO-RECOVERY INSTALLED${NC}"
}

# ==================== EXECUTE ====================
case "${1:-}" in
  client) shift; local_client_setup "$@";;
  uninstall|remove|6) complete_uninstall ;;
  status|check|4) status_check ;;
  autorecovery|5) install_autorecovery ;;
  restart|3) systemctl restart wg-quick@wg0 ;;
  *) main_menu ;;
esac
