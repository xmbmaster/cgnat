#!/bin/bash
# Fully automated WireGuard installer for Oracle Cloud + Local Client
# https://github.com/xmbmaster/cgnat

if [ $EUID != 0 ]; then
  echo "Please run as root"
  exit 1
fi

WG_CONF='/etc/wireguard/wg0.conf'
WG_PUB='/etc/wireguard/publickey'
WG_CLIENT_IP_FILE='/etc/wireguard/client_ip'
WG_PORTS='/etc/wireguard/forwarded_ports'

install_wireguard() {
  apt update
  apt install -y wireguard iptables iputils-ping ufw
}

enable_ip_forwarding() {
  echo 1 > /proc/sys/net/ipv4/ip_forward
  if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  fi
  sysctl -p
}

create_server_keys() {
  mkdir -p /etc/wireguard
  umask 077
  wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > $WG_PUB
  SERVER_PRIV=$(cat /etc/wireguard/server_private.key)
  SERVER_PUB=$(cat $WG_PUB)
  echo "Server Public Key: $SERVER_PUB"
}

create_client_keys() {
  umask 077
  wg genkey | tee /etc/wireguard/client_private.key | wg pubkey > /etc/wireguard/client_public.key
  CLIENT_PRIV=$(cat /etc/wireguard/client_private.key)
  CLIENT_PUB=$(cat /etc/wireguard/client_public.key)
}

write_server_conf() {
  read -p "Enter ports to forward (comma separated, e.g., 443/tcp,8098/tcp): " PORTS
  echo "ListenPort=$WG_PORT" > $WG_CONF
  echo "Address=$WG_SERVER_IP/24" >> $WG_CONF
  echo "PrivateKey=$SERVER_PRIV" >> $WG_CONF

  # NAT rules
  TCP_PORTS=$(echo $PORTS | tr ',' '\n' | grep tcp | cut -d'/' -f1 | tr '\n' ',' | sed 's/,$//')
  UDP_PORTS=$(echo $PORTS | tr ',' '\n' | grep udp | cut -d'/' -f1 | tr '\n' ',' | sed 's/,$//')

  if [ -n "$TCP_PORTS" ]; then
    echo "PostUp=iptables -t nat -A PREROUTING -p tcp --dports $TCP_PORTS -j DNAT --to-destination $WG_CLIENT_IP" >> $WG_CONF
  fi
  if [ -n "$UDP_PORTS" ]; then
    echo "PostUp=iptables -t nat -A PREROUTING -p udp --dports $UDP_PORTS -j DNAT --to-destination $WG_CLIENT_IP" >> $WG_CONF
  fi
  echo "PostDown=iptables -t nat -F" >> $WG_CONF
}

write_client_conf() {
  echo "[Interface]" > $WG_CONF
  echo "PrivateKey = $CLIENT_PRIV" >> $WG_CONF
  echo "Address = $WG_CLIENT_IP/24" >> $WG_CONF
  echo "" >> $WG_CONF
  echo "[Peer]" >> $WG_CONF
  echo "PublicKey = $SERVER_PUB" >> $WG_CONF
  echo "Endpoint = $SERVER_PUBLIC_IP:$WG_PORT" >> $WG_CONF
  echo "AllowedIPs = 0.0.0.0/0" >> $WG_CONF
  echo "PersistentKeepalive = 25" >> $WG_CONF
}

start_wireguard() {
  systemctl enable wg-quick@wg0
  systemctl start wg-quick@wg0
  echo "WireGuard started"
}

uninstall_wireguard() {
  systemctl stop wg-quick@wg0
  systemctl disable wg-quick@wg0
  apt remove --purge -y wireguard
  rm -rf /etc/wireguard
  echo "WireGuard removed completely"
}

echo "Choose mode:"
echo "1) VPS Server"
echo "2) Local Client"
echo "3) Uninstall WireGuard"
read -p "Choice: " MODE

case $MODE in
1)
  read -p "Enter server VPN IP [10.1.0.1]: " WG_SERVER_IP
  WG_SERVER_IP=${WG_SERVER_IP:-10.1.0.1}
  read -p "Enter client VPN IP [10.1.0.2]: " WG_CLIENT_IP
  WG_CLIENT_IP=${WG_CLIENT_IP:-10.1.0.2}
  read -p "Enter WireGuard port [55108]: " WG_PORT
  WG_PORT=${WG_PORT:-55108}

  install_wireguard
  enable_ip_forwarding
  create_server_keys
  write_server_conf
  start_wireguard
  ;;
2)
  read -p "Enter server public key: " SERVER_PUB
  read -p "Enter server public IP: " SERVER_PUBLIC_IP
  read -p "Enter server WireGuard port [55108]: " WG_PORT
  WG_PORT=${WG_PORT:-55108}
  read -p "Enter client VPN IP [10.1.0.2]: " WG_CLIENT_IP
  WG_CLIENT_IP=${WG_CLIENT_IP:-10.1.0.2}

  install_wireguard
  enable_ip_forwarding
  create_client_keys
  write_client_conf
  start_wireguard
  ;;
3)
  uninstall_wireguard
  ;;
*)
  echo "Invalid choice"
  exit 1
  ;;
esac
