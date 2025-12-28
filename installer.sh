#!/bin/bash
set -e

WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/wg0.conf"
WG_PORT=51820
SERVER_VPN_IP="10.1.0.1/24"
CLIENT_VPN_IP="10.1.0.2/24"

require_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Run as root"
    exit 1
  fi
}

pause() {
  read -rp "Press Enter to continue..."
}

wipe_all() {
  echo ">>> FULL WIPE"
  systemctl stop wg-quick@wg0 2>/dev/null || true
  systemctl disable wg-quick@wg0 2>/dev/null || true
  ip link del wg0 2>/dev/null || true
  rm -rf /etc/wireguard
  ufw --force reset 2>/dev/null || true
  sysctl -w net.ipv4.ip_forward=0 >/dev/null
  echo "DONE"
  pause
}

install_deps() {
  apt update -y
  apt install -y wireguard curl qrencode iproute2 iptables
}

enable_forwarding() {
  sysctl -w net.ipv4.ip_forward=1
  sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
}

server_install() {
  wipe_all
  install_deps
  enable_forwarding

  SERVER_PUBLIC_IP=$(curl -s https://api.ipify.org)
  mkdir -p $WG_DIR
  chmod 700 $WG_DIR

  SERVER_PRIV=$(wg genkey)
  SERVER_PUB=$(echo "$SERVER_PRIV" | wg pubkey)

  cat > $WG_CONF <<EOF
[Interface]
PrivateKey = $SERVER_PRIV
Address = $SERVER_VPN_IP
ListenPort = $WG_PORT
SaveConfig = false
EOF

  chmod 600 $WG_CONF

  systemctl enable wg-quick@wg0
  systemctl start wg-quick@wg0

  echo ""
  echo "===================================="
  echo " SERVER READY"
  echo " Public IP : $SERVER_PUBLIC_IP"
  echo " Port      : $WG_PORT"
  echo " PublicKey : $SERVER_PUB"
  echo "===================================="
  pause
}

client_install() {
  install_deps
  enable_forwarding

  read -rp "Enter SERVER PUBLIC IP: " SERVER_PUBLIC_IP
  read -rp "Paste SERVER PUBLIC KEY: " SERVER_PUB

  if [[ -z "$SERVER_PUBLIC_IP" || -z "$SERVER_PUB" ]]; then
    echo "ERROR: Empty values"
    exit 1
  fi

  mkdir -p $WG_DIR
  chmod 700 $WG_DIR

  CLIENT_PRIV=$(wg genkey)
  CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)

  cat > $WG_CONF <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_VPN_IP
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $SERVER_PUBLIC_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  chmod 600 $WG_CONF

  systemctl enable wg-quick@wg0
  systemctl restart wg-quick@wg0

  echo ""
  echo "===================================="
  echo " CLIENT READY"
  echo " Client PublicKey:"
  echo " $CLIENT_PUB"
  echo "===================================="
  echo ""
  echo "QR CODE:"
  qrencode -t ansiutf8 < $WG_CONF
  pause
}

menu() {
  clear
  echo "===================================="
  echo " CGNAT WireGuard Installer"
  echo "===================================="
  echo "1) Install SERVER (VPS / Oracle)"
  echo "2) Install CLIENT (Home / CasaOS)"
  echo "3) FULL UNINSTALL / WIPE"
  echo "4) Exit"
  echo "===================================="
  read -rp "Choose: " CHOICE

  case "$CHOICE" in
    1) server_install ;;
    2) client_install ;;
    3) wipe_all ;;
    4) exit 0 ;;
    *) echo "Invalid"; pause ;;
  esac
}

require_root
while true; do menu; done
