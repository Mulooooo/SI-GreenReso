#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

sudo ip link set ens160 up
sudo ip link set ens192 up
sudo ip link set ens224 up
sudo ip link set ens256 up

[[ $EUID -eq 0 ]] || {
    echo "Exécuter ce script avec sudo."
    exit 1
}

WAN="ens256"
SERVERS="ens160"
RH="ens192"
COM="ens224"

AD="10.10.10.10"
FILES="10.10.10.20"

BACKUP="/root/greenreso-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

trap 'echo "Échec ligne $LINENO. Sauvegarde : $BACKUP"' ERR

for IFACE in "$WAN" "$SERVERS" "$RH" "$COM"; do
    [[ -d "/sys/class/net/$IFACE" ]] || {
        echo "Interface absente : $IFACE"
        exit 1
    }
done

if [[ "$(cat "/sys/class/net/$WAN/carrier" 2>/dev/null || true)" != 1 ]]; then
    echo "La carte $WAN n'a pas de lien."
    echo "Connecter Network Adapter 4 à vmnet8 dans VMware."
    exit 1
fi

command -v netplan >/dev/null || {
    echo "Netplan est nécessaire."
    exit 1
}

echo ">>> Sauvegarde"
for PATH_TO_SAVE in \
    /etc/dnsmasq-greenreso.conf \
    /etc/systemd/system/dnsmasq.service.d \
    /etc/sysctl.d/99-greenreso.conf; do

    if [[ -e "$PATH_TO_SAVE" ]]; then
        cp -a --parents "$PATH_TO_SAVE" "$BACKUP/"
    fi
done
cp -a /etc/netplan "$BACKUP/"
[[ ! -e /etc/nftables.conf ]] ||
    cp -a /etc/nftables.conf "$BACKUP/"
[[ ! -d /etc/ufw ]] ||
    cp -a /etc/ufw "$BACKUP/"
[[ ! -e /etc/dnsmasq.conf ]] ||
    cp -a /etc/dnsmasq.conf "$BACKUP/"

echo ">>> Configuration réseau"

# Évite que cloud-init régénère une configuration concurrente.
if [[ -d /etc/cloud/cloud.cfg.d ]]; then
    [[ ! -e /etc/cloud/cloud.cfg.d/99-greenreso-network.cfg ]] ||
        cp -a /etc/cloud/cloud.cfg.d/99-greenreso-network.cfg "$BACKUP/"
    echo 'network: {config: disabled}' \
        > /etc/cloud/cloud.cfg.d/99-greenreso-network.cfg
fi

find /etc/netplan -maxdepth 1 -type f \
    \( -name '*.yaml' -o -name '*.yml' \) -delete

cat > /etc/netplan/01-greenreso.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $SERVERS:
      dhcp4: false
      dhcp6: false
      accept-ra: false
      addresses: [10.10.10.1/24]
    $RH:
      dhcp4: false
      dhcp6: false
      accept-ra: false
      addresses: [10.10.40.1/24]
    $COM:
      dhcp4: false
      dhcp6: false
      accept-ra: false
      addresses: [10.10.60.1/24]
    $WAN:
      dhcp4: true
      dhcp6: false
      accept-ra: false
      optional: true
EOF

chmod 600 /etc/netplan/01-greenreso.yaml

# Netplan doit générer des fichiers lisibles par systemd-networkd.
# Le changement de masque reste limité à ce sous-shell.
(
    umask 022
    netplan generate
    netplan apply
)

# Répare aussi les permissions des fichiers éventuellement
# générés auparavant sous umask 077.
find /run/systemd/network \
    -maxdepth 1 -type f -name '10-netplan-*.network' \
    -exec chown root:systemd-network {} + \
    -exec chmod 0640 {} +

networkctl reload
networkctl reconfigure "$SERVERS" "$RH" "$COM" "$WAN"

# Attendre les adresses internes avant de continuer.
for _ in {1..15}; do
    if ip -4 -o addr show dev "$SERVERS" | grep -q 'inet 10\.10\.10\.1/24 ' &&
       ip -4 -o addr show dev "$RH"      | grep -q 'inet 10\.10\.40\.1/24 ' &&
       ip -4 -o addr show dev "$COM"     | grep -q 'inet 10\.10\.60\.1/24 '; then
        break
    fi
    sleep 1
done

for ENTRY in \
    "$SERVERS 10.10.10.1/24" \
    "$RH 10.10.40.1/24" \
    "$COM 10.10.60.1/24"; do

    read -r IFACE CIDR <<< "$ENTRY"

    if ! ip -4 -o addr show dev "$IFACE" |
        awk '{print $4}' | grep -Fxq "$CIDR"; then
        echo "Erreur : adresse $CIDR absente sur $IFACE."
        networkctl status "$IFACE" --no-pager || true
        exit 1
    fi
done

echo ">>> Attente du DHCP sur $WAN"
for _ in {1..30}; do
    if ip -4 route show default dev "$WAN" | grep -q default; then
        break
    fi
    sleep 2
done

ip -4 route show default dev "$WAN" | grep -q default || {
    echo "Aucune route Internet obtenue sur $WAN."
    echo "Vérifier le NAT et le DHCP de vmnet8."
    exit 1
}

echo ">>> Installation"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nftables dnsmasq

echo ">>> Routage IPv4"
cat > /etc/sysctl.d/99-greenreso.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=2
net.ipv4.conf.default.rp_filter=2
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
EOF
sysctl --system >/dev/null

echo ">>> Relais DHCP vers SRV-AD01"

# Configuration dédiée : dnsmasq n'est ni serveur DNS,
# ni serveur DHCP local. Il relaie uniquement les requêtes.
cat > /etc/dnsmasq-greenreso.conf <<EOF
port=0
interface=$RH
interface=$COM
interface=$SERVERS
bind-dynamic
dhcp-relay=10.10.40.1,$AD,$SERVERS
dhcp-relay=10.10.60.1,$AD,$SERVERS
log-dhcp
EOF

# Remplace uniquement la commande du service dnsmasq.
mkdir -p /etc/systemd/system/dnsmasq.service.d
cat > /etc/systemd/system/dnsmasq.service.d/greenreso.conf <<'EOF'
[Service]
Type=simple
PIDFile=
ExecStartPre=
ExecStart=
ExecStart=/usr/sbin/dnsmasq --keep-in-foreground --conf-file=/etc/dnsmasq-greenreso.conf
ExecStartPost=
ExecStop=
ExecReload=
ExecReload=/bin/kill -HUP $MAINPID
EOF

dnsmasq --test --conf-file=/etc/dnsmasq-greenreso.conf

echo ">>> Pare-feu et NAT"

cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset

table inet greenreso {
    set user_interfaces {
        type ifname
        elements = { "$RH", "$COM" }
    }

    set internal_networks {
        type ipv4_addr
        flags interval
        elements = {
            10.10.10.0/24,
            10.10.40.0/24,
            10.10.60.0/24
        }
    }

    chain input {
        type filter hook input priority 0; policy drop;

        iifname "lo" accept
        ct state invalid drop
        ct state established,related accept

        # Réponse DHCP du réseau VMware pour l'interface WAN.
        iifname "$WAN" udp sport 67 udp dport 68 accept

        # Administration SSH depuis le réseau serveurs uniquement.
        iifname "$SERVERS" ip saddr 10.10.10.0/24 tcp dport 22 accept

        # Diagnostic local depuis les réseaux internes.
        iifname { "$SERVERS", "$RH", "$COM" } \
            ip protocol icmp accept

        # Requêtes DHCP des clients vers le relais.
        iifname @user_interfaces udp sport 68 udp dport 67 accept

        # Réponses du serveur DHCP au relais.
        iifname "$SERVERS" ip saddr $AD \
            udp sport 67 udp dport 67 accept
    }

    chain forward {
        type filter hook forward priority 0; policy drop;

        ct state invalid drop

        # Protection contre l'usurpation des réseaux source.
        iifname "$SERVERS" ip saddr != 10.10.10.0/24 drop
        iifname "$RH" ip saddr != 10.10.40.0/24 drop
        iifname "$COM" ip saddr != 10.10.60.0/24 drop

        ct state established,related accept

        # DNS, Kerberos, LDAP, SMB, RPC et services AD.
        iifname @user_interfaces oifname "$SERVERS" \
            ip daddr $AD \
            tcp dport {
                53, 88, 135, 389, 445, 464,
                636, 3268, 3269, 49152-65535
            } accept

        iifname @user_interfaces oifname "$SERVERS" \
            ip daddr $AD \
            udp dport { 53, 88, 123, 389, 464 } accept

        # Partages du serveur de fichiers.
        iifname @user_interfaces oifname "$SERVERS" \
            ip daddr $FILES tcp dport 445 accept

        # Ping vers AD et serveur de fichiers pour les tests.
        iifname @user_interfaces oifname "$SERVERS" \
            ip daddr { $AD, $FILES } \
            ip protocol icmp accept

        # Navigation Internet : uniquement par l'interface WAN.
        iifname { "$SERVERS", "$RH", "$COM" } \
            oifname "$WAN" ip saddr @internal_networks \
            tcp dport { 80, 443 } accept

        # Résolution externe et synchronisation du serveur AD.
        iifname "$SERVERS" oifname "$WAN" ip saddr $AD \
            udp dport { 53, 123 } accept
        iifname "$SERVERS" oifname "$WAN" ip saddr $AD \
            tcp dport 53 accept

        # Ping Internet pour les diagnostics.
        iifname { "$SERVERS", "$RH", "$COM" } \
            oifname "$WAN" ip saddr @internal_networks \
            ip protocol icmp accept

        # RH vers Commercial et inversement : refus par défaut.
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}

table ip greenreso_nat {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;

        oifname "$WAN" ip saddr {
            10.10.10.0/24,
            10.10.40.0/24,
            10.10.60.0/24
        } masquerade
    }
}
EOF

# Vérification avant remplacement du pare-feu actif.
nft -c -f /etc/nftables.conf

# Évite le mélange de deux gestionnaires de pare-feu.
if command -v ufw >/dev/null 2>&1; then
    ufw --force disable
fi

systemctl disable --now ufw.service 2>/dev/null || true

nft -f /etc/nftables.conf
systemctl enable nftables

systemctl daemon-reload
systemctl enable dnsmasq
systemctl restart dnsmasq

echo
echo ">>> Configuration terminée"
echo "Sauvegarde : $BACKUP"
ip -br -4 addr
ip -4 route
systemctl --no-pager --full status dnsmasq
nft list ruleset
