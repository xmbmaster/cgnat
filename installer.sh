#!/bin/bash
# 🔥 CGNAT BYPASS v4.0 - COMPLETE ALL-IN-ONE
# VPS + Local + Auto-Fix + Recovery + Diagnostics ✅

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

# ==================== UNIVERSAL FIXES ====================
fix_system() {
  apt update >/dev/null 2>&1
  apt install -y wireguard wireguard-tools iptables netfilter-persistent curl iputils-ping
  sysctl -w net.ipv4.ip_forward=1
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
}

# ==================== VPS SERVER SETUP ====================
vps_setup() {
  echo -e "${LGREEN}${BOLD}☁️  VPS SERVER SETUP${NC}"
  fix_system
  
  echo -e "${YELLOW}${BOLD}ORACLE VCN CHECKLIST:${NC}"
  echo "- Security List → Ingress Rules"
  echo "- UDP 55108 ← 0.0.0.0/0 (CRITICAL)"
  echo "- TCP your ports ← 0.0.0.0/0"
  read -p "Press Enter AFTER adding VCN rules..."
  
  WGPORT=55108; WG_SIP="10.1.0.1"; WG_CIP="10.1.0.2"
  PUBIP=$(curl -s ifconfig.me 2>/dev/null || echo "AUTO")
  read -p "Public IP [$PUBIP]: " INPUT; [[ -n "$INPUT" ]] && PUBIP=$INPUT
  read -p "Service Ports [8098/tcp]: " PORTS; PORTS=${PORTS:-"8098/tcp"}
  
  mkdir -p /etc/wireguard
  echo $WG_CIP > /etc/wireguard/client_ip
  echo $PORTS > /etc/wireguard/ports
  
  # Generate keys
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  SERVER_PUB=$(cat /etc/wireguard/public.key)
  
  # MINIMAL CRASH-PROOF CONFIG
  cat > $WGCONF << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = $WG_SIP/24
ListenPort = $WGPORT

[Peer]
PublicKey = CLIENT_PUBKEY_PLACEHOLDER
AllowedIPs = $WG_CIP/32
PersistentKeepalive = 15
EOF
  
  echo -e "\n${LGREEN}${BOLD}🏠 CLIENT SETUP COMMAND:${NC}"
  echo "sudo $0 client \"$SERVER_PUB\" $PUBIP $WGPORT \"$PORTS\""
  echo -e "${CYAN}Run on LOCAL server, copy its public key:${NC}"
  read -p "CLIENT public key: " CLIENT_PUB
  sed -i "s/CLIENT_PUBKEY_PLACEHOLDER/$CLIENT_PUB/" $WGCONF
  
  # MANUAL FIREWALL (no PostUp)
  iptables -F; iptables -t nat -F
  iptables -I INPUT 1 -p udp --dport $WGPORT -j ACCEPT
  iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
  for p in $(echo "$PORTS" | tr ',' '\n'); do 
    PORT=$(echo $p | cut -d/ -f1); PROTO=$(echo $p | cut -d/ -f2 2>/dev/null || echo tcp)
    iptables -t nat -A PREROUTING -p $PROTO --dport $PORT -j DNAT --to $WG_CIP
  done
  netfilter-persistent save 2>/dev/null || true
  
  # UFW
  ufw allow $WGPORT/udp 2>/dev/null || true
  ufw allow OpenSSH 2>/dev/null || true
  for p in $(echo "$PORTS" | tr ',' '\n'); do ufw allow "$p" 2>/dev/null; done
  
  systemctl enable --now wg-quick@wg0
  sleep 5
  
  install_recovery
  echo -e "${GREEN}${BOLD}✅ VPS SERVER READY ON $PUBIP:$WGPORT${NC}"
  echo -e "${YELLOW}Test: ss -ulnp | grep 55108${NC}"
}

# ==================== LOCAL CLIENT ====================
local_setup() {
  SERVER_PUB=$1; PUBIP=$2; WGPORT=$3; PORTS=$4
  WG_CIP="10.1.0.2"; WG_SIP="10.1.0.1"
  
  echo -e "${LGREEN}${BOLD}🏠 LOCAL CLIENT SETUP${NC}"
  fix_system
  
  mkdir -p /etc/wireguard
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  CLIENT_PUB=$(cat /etc/wireguard/public.key)
  
  echo -e "${GREEN}${BOLD}YOUR PUBLIC KEY (give to VPS): $CLIENT_PUB${NC}"
  
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
  
  # Local port forwarding to Docker (172.17.0.2)
  iptables -t nat -F PREROUTING POSTROUTING
  for p in $(echo "$PORTS" | tr ',' '\n'); do 
    PORT=$(echo $p | cut -d/ -f1); PROTO=$(echo $p | cut -d/ -f2 2>/dev/null || echo tcp)
    iptables -t nat -A PREROUTING -i wg0 -p $PROTO --dport $PORT -j DNAT --to 172.17.0.2:$PORT
    iptables -t nat -A POSTROUTING -o wg0 -p $PROTO -d 172.17.0.2 --dport $PORT -j MASQUERADE
  done
  
  systemctl enable --now wg-quick@wg0
  sleep 5
  
  if ping -c 3 $WG_SIP >/dev/null 2>&1; then
    echo -e "${GREEN}${BOLD}✅ TUNNEL CONNECTED${NC}"
    echo -e "${GREEN}Test: curl http://$PUBIP:8098${NC}"
  else
    echo -e "${RED}${BOLD}❌ VPS NOT RESPONDING${NC}"
    echo -e "${YELLOW}VPS CHECK:${NC}"
    echo "1. ss -ulnp | grep :55108"
    echo "2. Oracle VCN UDP 55108 allowed"
    echo "3. wg show (handshake?)"
  fi
}

# ==================== AUTO-RECOVERY ====================
install_recovery() {
  cat > /etc/systemd/system/wg-monitor.service << 'EOF'
[Unit]
Description=WireGuard Monitor
After=wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do sleep 300; systemctl is-active --quiet wg-quick@wg0 || systemctl restart wg-quick@wg0; pgrep -f "wg.*wg0" || systemctl restart wg-quick@wg0; done'
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now wg-monitor.service 2>/dev/null || true
  echo -e "${GREEN}${BOLD}✅ AUTO-RECOVERY INSTALLED${NC}"
}

# ==================== DIAGNOSTICS ====================
diagnostics() {
  clear; echo -e "${CYAN}${BOLD}🔍 FULL DIAGNOSTICS${NC}"
  echo -e "\n=== WireGuard ==="
  wg show 2>/dev/null || echo "❌ No tunnel"
  echo -e "\n=== UDP 55108 ==="
  ss -ulnp | grep :55108 || echo "❌ Port closed (VPS only)"
  echo -e "\n=== Services ==="
  systemctl status wg-quick@wg0 2>/dev/null | head -10
  echo -e "\n=== Recovery ==="
  systemctl status wg-monitor 2>/dev/null | head -5 || echo "❌ Off"
  echo -e "\n=== iptables ==="
  iptables -L INPUT -n | grep 55108 || echo "❌ No UDP rule"
  iptables -t nat -L -n | grep DNAT || echo "❌ No forwarding"
  echo -e "\n=== Logs ==="
  journalctl -u wg-quick@wg0 -n 5 2>/dev/null || echo "No recent errors"
  read -p "Press Enter..."
}

# ==================== UNINSTALL ====================
uninstall_all() {
  echo -e "${YELLOW}${BOLD}🗑️  COMPLETE CLEANUP${NC}"
  systemctl stop wg-quick@wg0 wg-monitor 2>/dev/null || true
  rm -rf /etc/wireguard $WGCONF /etc/iptables/rules.v* /etc/systemd/system/wg-*
  iptables -F -t nat -F -t mangle -F -X -t nat -X -t mangle -X 2>/dev/null || true
  iptables -P INPUT ACCEPT -P FORWARD ACCEPT -P OUTPUT ACCEPT
  iptables -t nat -P PREROUTING ACCEPT -t nat -P POSTROUTING ACCEPT
  ufw disable 2>/dev/null || true
  apt purge -y wireguard wireguard-tools netfilter-persistent iptables ufw 2>/dev/null || true
  apt autoremove -y 2>/dev/null || true
  systemctl daemon-reload
  echo -e "${GREEN}${BOLD}✅ SYSTEM CLEAN${NC}"; exit 0
}

# ==================== MAIN MENU ====================
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║        CGNAT BYPASS v4.0             ║${NC}"
    echo -e "${LGREEN}${BOLD}║     VPS + LOCAL + AUTO-FIX           ║${NC}"
    echo -e "${LGREEN}${BOLD}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  1) ☁️  VPS Server Setup              ║${NC}"
    echo -e "${CYAN}║  2) 🏠 Local Client Command            ║${NC}"
    echo -e "${CYAN}║  3) 🔧 Fix VPS Issues                  ║${NC}"
    echo -e "${CYAN}║  4) 📊 Full Diagnostics                ║${NC}"
    echo -e "${LGREEN}║  5) 🛡️  Auto-Recovery                 ║${NC}"
    echo -e "${CYAN}║  6) 🔄 Restart Everything              ║${NC}"
    echo -e "${RED}║  7) 🗑️  Complete Uninstall             ║${NC}"
    echo -e "${CYAN}║  8) ❌ Exit                            ║${NC}"
    echo -e "${LGREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
    
    echo -ne "\n${BOLD}${CYAN}Choose (1-8): ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) vps_setup ;;
      2) echo -e "${YELLOW}${BOLD}Paste VPS command:${NC}"; read -r CMD; eval "$CMD" 2>/dev/null ;;
      3) fix_firewall; echo -e "${GREEN}VPS firewall fixed${NC}" ;;
      4) diagnostics ;;
      5) install_recovery ;;
      6) systemctl restart wg-quick@wg0 wg-monitor 2>/dev/null && echo -e "${GREEN}Restarted${NC}" || echo -e "${RED}Failed${NC}" ;;
      7) uninstall_all ;;
      8) exit 0 ;;
      *) echo -e "${RED}Invalid${NC}"; sleep 1 ;;
    esac
  done
}

# ==================== EXECUTE ====================
case "${1:-}" in
  client) shift; local_setup "$@";;
  fix-vps|3) fix_firewall ;;
  diagnose|4) diagnostics ;;
  recovery|5) install_recovery ;;
  restart|6) systemctl restart wg-quick@wg0 ;;
  uninstall|7) uninstall_all ;;
  *) main_menu ;;
esac
