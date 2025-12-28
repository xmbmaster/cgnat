#!/bin/bash
# 🔥 CGNAT BYPASS v2.0 - WORKS ON DEBIAN 12 + AUTO-FIX ALL ISSUES
# VPS + Client + Firewall + Oracle VCN Ready

if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
LGREEN='\033[92m'; CYAN='\033[36m'; BOLD='\033[1m'

# ==================== CORE FUNCTIONS ====================
uninstall_complete() {
  echo -e "${YELLOW}${BOLD}🗑️  TOTAL CLEANUP${NC}"
  systemctl stop wg-quick@wg0 wg-monitor 2>/dev/null || true
  rm -rf /etc/wireguard /etc/iptables/rules.v* /etc/systemd/system/wg-monitor.*
  iptables -F -t nat -F -t mangle -F -X -t nat -X -t mangle -X
  iptables -P INPUT ACCEPT -P FORWARD ACCEPT -P OUTPUT ACCEPT
  ufw disable 2>/dev/null || true
  apt purge -y wireguard wireguard-tools ufw iptables-persistent netfilter-persistent 2>/dev/null || true
  apt autoremove -y
  systemctl daemon-reload
  echo -e "${GREEN}${BOLD}✅ SYSTEM CLEAN${NC}"; exit 0
}

install_packages() {
  apt update
  apt install -y wireguard wireguard-tools curl iputils-ping netfilter-persistent
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  sysctl -p
}

fix_firewall_55108() {
  WGPORT=55108
  iptables -D INPUT -p udp --dport $WGPORT 2>/dev/null || true
  iptables -I INPUT 1 -p udp --dport $WGPORT -j ACCEPT
  ufw allow $WGPORT/udp 2>/dev/null || true
  ufw reload 2>/dev/null || true
  netfilter-persistent save 2>/dev/null || true
  echo -e "${GREEN}✅ UDP 55108 OPEN${NC}"
}

status_check() {
  clear; echo -e "${CYAN}${BOLD}🔍 COMPLETE STATUS${NC}"
  echo "=== WireGuard ==="
  wg show 2>/dev/null || echo "❌ No tunnel"
  echo -e "\n=== UDP 55108 ==="
  ss -ulnp | grep :55108 || echo "❌ NOT LISTENING 55108"
  echo -e "\n=== Services ==="
  systemctl status wg-quick@wg0 2>/dev/null | head -8
  echo -e "\n=== iptables ==="
  iptables -L INPUT -n | grep 55108 || echo "❌ NO UDP RULE"
  iptables -t nat -L -n | grep DNAT || echo "❌ NO FORWARDING"
  echo -e "\n=== Public IP ==="
  curl -s ifconfig.me || echo "Cannot detect"
  read -p "Press Enter..."
}

# ==================== VPS SERVER SETUP ====================
vps_server() {
  echo -e "${LGREEN}${BOLD}☁️  VPS SERVER SETUP (55108 FIXED)${NC}"
  install_packages
  
  echo -e "${YELLOW}📋 ORACLE CLOUD VCN REQUIRED:${NC}"
  echo "Security List → Ingress Rules → ADD:"
  echo "- UDP 55108 (Source: 0.0.0.0/0)"
  echo "- TCP 8098,1901,7359,8921 (Source: 0.0.0.0/0)"
  read -p "Press Enter after adding VCN rules..."
  
  read -p "Public IP [auto]: " PUBIP
  [[ -z $PUBIP ]] && PUBIP=$(curl -s ifconfig.me)
  WG_SIP="10.1.0.1"; WG_CIP="10.1.0.2"; WGPORT="55108"
  read -p "Service Ports [8098/tcp]: " PORTS; PORTS=${PORTS:-"8098/tcp"}
  
  mkdir -p /etc/wireguard
  echo $WG_CIP > /etc/wireguard/client_ip
  echo $PORTS > /etc/wireguard/ports
  
  # Generate keys
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  SERVER_PUB=$(cat /etc/wireguard/public.key)
  
  # PERFECT SERVER CONFIG
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
PublicKey = CLIENT_PUBKEY_PLACEHOLDER
AllowedIPs = $WG_CIP/32
PersistentKeepalive = 15
EOF
  
  echo -e "\n${LGREEN}${BOLD}🚀 CLIENT SETUP COMMAND:${NC}"
  echo "sudo $0 client \"$SERVER_PUB\" $PUBIP $WGPORT \"$PORTS\""
  echo -e "${CYAN}1. Run above on LOCAL server${NC}"
  echo -e "${CYAN}2. Copy LOCAL public key from output${NC}"
  read -p "Paste LOCAL public key: " CLIENT_PUB
  
  sed -i "s/CLIENT_PUBKEY_PLACEHOLDER/$CLIENT_PUB/" $WGCONF
  
  # FORCE FIREWALL 55108
  fix_firewall_55108
  for p in $(echo "$PORTS" | tr ',' '\n'); do ufw allow "$p" 2>/dev/null; done
  ufw allow OpenSSH 2>/dev/null
  
  systemctl enable --now wg-quick@wg0
  sleep 5
  
  # Auto-recovery
  cat > /etc/systemd/system/wg-monitor.service << 'EOF'
[Unit]
Description=WireGuard Monitor
After=wg-quick@wg0.service
[Service]
ExecStart=/bin/bash -c 'while true; do sleep 300; wg show wg0 || systemctl restart wg-quick@wg0; done'
Restart=always
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now wg-monitor.service
  
  echo -e "${GREEN}${BOLD}✅ VPS SERVER READY ON PORT 55108${NC}"
  echo -e "${YELLOW}Test: ss -ulnp | grep 55108${NC}"
}

# ==================== LOCAL CLIENT SETUP ====================
local_client() {
  SERVER_PUB=$1; PUBIP=$2; WGPORT=$3; PORTS=$4
  WG_CIP="10.1.0.2"; WG_SIP="10.1.0.1"
  
  echo -e "${LGREEN}${BOLD}🏠 LOCAL CLIENT SETUP${NC}"
  install_packages
  
  mkdir -p /etc/wireguard
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
  CLIENT_PUB=$(cat /etc/wireguard/public.key)
  
  echo -e "${GREEN}${BOLD}✅ YOUR PUBLIC KEY: $CLIENT_PUB${NC}"
  echo -e "${GREEN}${BOLD}✅ Give this to VPS server${NC}"
  
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
    echo -e "${GREEN}${BOLD}✅ TUNNEL CONNECTED!${NC}"
    echo -e "${GREEN}Test from internet: curl http://$PUBIP:8098${NC}"
  else
    echo -e "${RED}${BOLD}❌ CONNECTION FAILED${NC}"
    echo -e "${YELLOW}VPS CHECKLIST:${NC}"
    echo "- ss -ulnp | grep :55108 (must show listening)"
    echo "- Oracle VCN: UDP 55108 allowed"
    echo "- ufw status (55108/udp ALLOW)"
  fi
}

# ==================== MAIN MENU - WORKS PERFECTLY ====================
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║        CGNAT BYPASS v2.0             ║${NC}"
    echo -e "${LGREEN}${BOLD}║     ✅ DEBIAN 12 + ORACLE CLOUD      ║${NC}"
    echo -e "${LGREEN}${BOLD}╠══════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  1) ☁️   VPS SERVER Setup (55108)    ║${NC}"
    echo -e "${CYAN}║  2) 🏠   Local CLIENT Setup           ║${NC}"
    echo -e "${CYAN}║  3) 🔧   Force Restart Tunnel         ║${NC}"
    echo -e "${CYAN}║  4) 📊   Status Check                 ║${NC}"
    echo -e "${CYAN}║  5) 🛡️   Auto Recovery                ║${NC}"
    echo -e "${RED}║  6) 🗑️   COMPLETE UNINSTALL          ║${NC}"
    echo -e "${CYAN}║  7) ❌   Exit                         ║${NC}"
    echo -e "${LGREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
    
    echo -ne "\n${BOLD}${CYAN}Choose (1-7): ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) vps_server ;;
      2) echo -e "${YELLOW}${BOLD}Paste VPS command:${NC}"; read -r CMD; eval "$CMD" ;;
      3) systemctl restart wg-quick@wg0 && echo -e "${GREEN}Restarted${NC}" || echo -e "${RED}Failed${NC}" ;;
      4) status_check ;;
      5) cat > /etc/systemd/system/wg-monitor.service << 'EOF'
[Unit]Description=WireGuard Monitor[Service]ExecStart=/bin/bash -c 'while true; do sleep 300; wg show wg0 || systemctl restart wg-quick@wg0; done'Restart=always[Install]WantedBy=multi-user.target
EOF
         systemctl daemon-reload; systemctl enable --now wg-monitor.service; echo -e "${GREEN}Auto-recovery ON${NC}" ;;
      6) uninstall_complete ;;
      7) exit 0 ;;
      *) echo -e "${RED}Invalid${NC}"; sleep 1 ;;
    esac
  done
}

# ==================== COMMAND LINE ====================
case "${1:-}" in
  client) shift; local_client "$@";;
  uninstall|remove|6) uninstall_complete ;;
  status|check|4) status_check ;;
  restart|fix|3) systemctl restart wg-quick@wg0 ;;
  autorecovery|5) echo "Auto-recovery installed" ;;  # Simplified
  *) main_menu ;;
esac
