#!/bin/bash
set -e

# ================= COLORS =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ================= VARS =================
WGDIR="/etc/wireguard"
WGCONF="$WGDIR/wg0.conf"
WGPUBKEY="$WGDIR/publickey"
WGPRIVKEY="$WGDIR/privatekey"
WGPORTSFILE="$WGDIR/forwarded_ports"
WGCLIENTIPFILE="$WGDIR/client_ip"

# ================= PREP =================
mkdir -p $WGDIR
chmod 700 $WGDIR
touch $WGCONF $WGPUBKEY $WGPRIVKEY $WGPORTSFILE $WGCLIENTIPFILE
chmod 600 $WGDIR/*

# ================= UNINSTALL =================
uninstall_all () {
  echo -e "${RED}Uninstalling WireGuard & cleaning system${NC}"

  systemctl stop wg-quick@wg0 2>/dev/null || true
  systemctl disable wg-quick@wg0 2>/dev/null || true

  iptables -F || true
  iptables -t nat -F || true
  iptables -X || true
  nft flush ruleset 2>/dev/null || true

  rm -rf /etc/wireguard

  apt purge -y wireguard wireguard-tools iptables-persistent netfilter-persistent || true
  apt autoremove -y

  echo -e "${GREEN}DONE. Reboot recommended.${NC}"
  exit 0
}

# ================= ARG HANDLER =================
if [[ "$1" == "uninstall" ]]; then
  uninstall_all
fi

# ================= DEPENDENCIES =================
echo -e "${YELLOW}Installing dependencies...${NC}"
apt update -y
apt install -y wireguard wireguard-tools iptables-persistent netfilter-persistent curl
echo -e "[${GREEN}Done${NC}]"

# ================= SYSCTL =================
echo -e "${YELLOW}Enabling IP Forwarding...${NC}"
sysctl -w net.ipv4.ip_forward=1
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
echo -e "[${GREEN}Done${NC}]"

# ================= KEYS =================
if [[ ! -s $WGPRIVKEY ]]; then
  echo -e "${YELLOW}Generating WireGuard keys...${NC}"
  wg genkey | tee $WGPRIVKEY | wg pubkey > $WGPUBKEY
  echo -e "[${GREEN}Done${NC}]"
fi

SERVER_PRIV=$(cat $WGPRIVKEY)
SERVER_PUB=$(cat $WGPUBKEY)

# ================= MODE =================
if [[ "$1" == "Local" ]]; then
  MODE="CLIENT"
else
  MODE="SERVER"
fi

# ================= SERVER MODE =================
if [[ "$MODE" == "SERVER" ]]; then

  read -p "WireGuard listen port [55108]: " WGPORT
  WGPORT=${WGPORT:-55108}

  read -p "Server WG IP [10.1.0.1]: " WGIP
  WGIP=${WGIP:-10.1.0.1}

  read -p "Ports to forward (e.g. 8098/tcp,443/tcp): " PORTLIST
  echo "$PORTLIST" > $WGPORTSFILE

  cat > $WGCONF <<EOF
[Interface]
Address = $WGIP/24
ListenPort = $WGPORT
PrivateKey = $SERVER_PRIV
EOF

  for i in $(echo $PORTLIST | tr ',' ' '); do
    PORT=$(echo $i | cut -d'/' -f1)
    PROT=$(echo $i | cut -d'/' -f2)
    iptables -t nat -A PREROUTING -p $PROT --dport $PORT -j DNAT --to-destination $WGIP:$PORT
    iptables -t nat -A POSTROUTING -p $PROT --dport $PORT -j MASQUERADE
  done

  netfilter-persistent save

  systemctl enable wg-quick@wg0
  systemctl restart wg-quick@wg0

  echo ""
  echo -e "${GREEN}SERVER READY${NC}"
  echo "Public Key:"
  echo "$SERVER_PUB"
  exit 0
fi

# ================= CLIENT MODE =================
PUBLIC_IP="$2"
SERVER_WG_IP="$3"
CLIENT_WG_IP="$4"
WGPORT="$5"
PORTLIST="$6"

read -p "Paste SERVER Public Key: " SERVER_PUBKEY

cat > $WGCONF <<EOF
[Interface]
Address = $CLIENT_WG_IP/24
PrivateKey = $SERVER_PRIV
EOF

for i in $(echo $PORTLIST | tr ',' ' '); do
  PORT=$(echo $i | cut -d'/' -f1)
  PROT=$(echo $i | cut -d'/' -f2)
  read -p "IP of service using $PORT/$PROT (Enter for this server): " SVC_IP
  if [[ -n "$SVC_IP" ]]; then
    echo "PostUp = iptables -t nat -A PREROUTING -p $PROT --dport $PORT -j DNAT --to-destination $SVC_IP:$PORT" >> $WGCONF
    echo "PostDown = iptables -t nat -D PREROUTING -p $PROT --dport $PORT -j DNAT --to-destination $SVC_IP:$PORT" >> $WGCONF
  fi
done

cat >> $WGCONF <<EOF

[Peer]
PublicKey = $SERVER_PUBKEY
AllowedIPs = 0.0.0.0/0
Endpoint = $PUBLIC_IP:$WGPORT
PersistentKeepalive = 25
EOF

systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo -e "${GREEN}CLIENT READY${NC}"
