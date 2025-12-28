#!/bin/bash
# 🔥 CGNAT BYPASS v2.3 - AUTO-FIX CRASHES
if [ $EUID != 0 ]; then exec sudo "$0" "$@"; fi

WGCONF="/etc/wireguard/wg0.conf"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
CYAN='\033[36m'; BOLD='\033[1m'

# ==================== EMERGENCY FIX ====================
emergency_fix() {
  echo -e "${YELLOW}🔧 EMERGENCY FIX${NC}"
  
  # Stop broken services
  systemctl stop wg-quick@wg0 wg-monitor 2>/dev/null
  
  # Clear broken iptables
  iptables -t nat -F PREROUTING POSTROUTING
  netfilter-persistent save 2>/dev/null
  
  # Check config syntax
  if ! wg-quick up wg0 --dry-run 2>/dev/null; then
    echo -e "${RED}Config broken - rebuilding...${NC}"
    # Rebuild minimal config
    CLIENT_IP=$(cat /etc/wireguard/client_ip 2>/dev/null || echo "10.1.0.2")
    SERVER_PRIV=$(cat /etc/wireguard/private.key 2>/dev/null)
    CLIENT_PUB=$(grep PublicKey $WGCONF | tail -1 | cut -d' ' -f3 2>/dev/null)
    
    cat > $WGCONF << EOF
[Interface]
PrivateKey = $SERVER_PRIV
Address = 10.1.0.1/24
ListenPort = 55108

PostUp = iptables -t nat -A POSTROUTING -o %i -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o %i -j MASQUERADE
PostUp = iptables -I INPUT 1 -p udp --dport 55108 -j ACCEPT
PostDown = iptables -D INPUT -p udp --dport 55108 -j ACCEPT
PostUp = iptables -t nat -A PREROUTING -p tcp --dport 8098 -j DNAT --to $CLIENT_IP
PostDown = iptables -t nat -D PREROUTING -p tcp --dport 8098 -j DNAT --to $CLIENT_IP

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = $CLIENT_IP/32
PersistentKeepalive = 15
EOF
  fi
  
  # Restart
  systemctl start wg-quick@wg0
  sleep 3
  
  if wg show wg0 >/dev/null 2>&1; then
    echo -e "${GREEN}✅ FIXED & RUNNING${NC}"
  else
    echo -e "${RED}❌ STILL BROKEN${NC}"
  fi
}

# ==================== MAIN MENU ====================
main_menu() {
  while true; do
    clear
    echo -e "${LGREEN}${BOLD}╔═══════════════════════╗${NC}"
    echo -e "${LGREEN}${BOLD}║   CGNAT BYPASS v2.3   ║${NC}"
    echo -e "${LGREEN}${BOLD}║  CRASH AUTO-FIXER     ║${NC}"
    echo -e "${LGREEN}${BOLD}╠═══════════════════════╣${NC}"
    echo -e "${RED}║  1) 🚨 EMERGENCY FIX  ║${NC}"
    echo -e "${CYAN}║  2) 🔄 Quick Restart   ║${NC}"
    echo -e "${CYAN}║  3) 📊 Status          ║${NC}"
    echo -e "${LGREEN}║  4) 🛡️ Auto-Recovery  ║${NC}"
    echo -e "${RED}║  5) 🗑️  Uninstall     ║${NC}"
    echo -e "${CYAN}║  6) ❌ Exit            ║${NC}"
    echo -e "${LGREEN}${BOLD}╚═══════════════════════╝${NC}"
    
    WG_STATUS=$(wg show wg0 >/dev/null 2>&1 && echo "🟢 UP" || echo "🔴 DOWN")
    echo -e "\n${BOLD}Tunnel: $WG_STATUS${NC}"
    
    echo -ne "\n${CYAN}Choose: ${NC}"
    read -r CHOICE
    
    case $CHOICE in
      1) emergency_fix ;;
      2) systemctl restart wg-quick@wg0 && echo -e "${GREEN}Restarted${NC}" || echo -e "${RED}Failed${NC}" ;;
      3) clear; wg show 2>/dev/null || echo "No tunnel"; systemctl status wg-quick@wg0 2>/dev/null | head -10; iptables -t nat -L | grep DNAT || echo "No NAT"; read -p "Enter..." ;;
      4) install_autorecovery ;;
      5) uninstall_complete ;;
      6) exit 0 ;;
      *) echo -e "${RED}Invalid${NC}"; sleep 1 ;;
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
ExecStart=/bin/bash -c 'while true; do sleep 300; if ! pgrep -f "wg-quick.*wg0" >/dev/null; then systemctl restart wg-quick@wg0; fi; done'
Restart=always
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload && systemctl restart wg-monitor.service
  echo -e "${GREEN}✅ Auto-recovery restarted${NC}"
}

uninstall_complete() {
  systemctl stop wg-quick@wg0 wg-monitor
  rm -rf /etc/wireguard $WGCONF /etc/iptables/rules.v* /etc/systemd/system/wg-*
  iptables -F -t nat -F -X; iptables -P INPUT ACCEPT -P FORWARD ACCEPT
  apt purge -y wireguard wireguard-tools netfilter-persistent
  systemctl daemon-reload
  echo -e "${GREEN}✅ CLEAN${NC}"
}

case "${1:-}" in
  fix|1) emergency_fix ;;
  status|3) wg show 2>/dev/null || echo "No tunnel"; systemctl status wg-quick@wg0 ;;
  autorecovery|4) install_autorecovery ;;
  uninstall|5) uninstall_complete ;;
  *) main_menu ;;
esac
