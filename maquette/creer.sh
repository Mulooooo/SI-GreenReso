#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"; source .env

# Réseau WAN VMware : choisir un sous-réseau libre sur l'hôte.
WAN_SUBNET="192.168.200.0"

sudo -v

# Sauvegarde avant modification.
sudo cp -a /etc/vmware/networking \
    "/etc/vmware/networking.bak-$(date +%Y%m%d-%H%M%S)"

ajoute=""

for net in $(
    grep -vE '^\s*(#|$)' ../vms.conf |
        cut -d'|' -f5 |
        tr ',' '\n' |
        sort -u
); do
    n=${net#vmnet}

    # VMnet8 : sortie Internet avec NAT et DHCP VMware.
    # Ce traitement doit être AVANT le test des entrées existantes.
    if [[ "$n" == "8" ]]; then
        sudo sed -i '/^answer VNET_8_/d' /etc/vmware/networking

        sudo tee -a /etc/vmware/networking >/dev/null <<EOF
answer VNET_8_DHCP yes
answer VNET_8_HOSTONLY_NETMASK 255.255.255.0
answer VNET_8_HOSTONLY_SUBNET $WAN_SUBNET
answer VNET_8_NAT yes
answer VNET_8_VIRTUAL_ADAPTER yes
EOF
        ajoute="oui"
        continue
    fi

    # Réseaux internes : conserver les configurations existantes.
    if grep -q "^answer VNET_${n}_" /etc/vmware/networking; then
        continue
    fi

    sudo tee -a /etc/vmware/networking >/dev/null <<EOF
answer VNET_${n}_DHCP no
answer VNET_${n}_HOSTONLY_NETMASK 255.255.255.0
answer VNET_${n}_HOSTONLY_SUBNET 10.10.$(( (n-10)*10 )).0
answer VNET_${n}_VIRTUAL_ADAPTER no
EOF
    ajoute="oui"
done

if [[ -n "$ajoute" ]]; then
    sudo vmware-networks --stop
    sudo vmware-networks --start
    sudo vmware-networks --status
fi

numero=0
grep -vE '^\s*(#|$)' ../vms.conf | while IFS='|' read -r nom modele cpu ram reseaux ip; do
  numero=$((numero+1)); vmx=$V/$nom/$nom.vmx
  [ -f $vmx ] && { echo "$nom existe déjà"; continue; }
  vmrun -T ws clone $V/_tpl/$modele/$modele.vmx $vmx linked -snapshot=base -cloneName=$nom
  sed -i -e '/^ethernet/d' -e '/^numvcpus/d' -e '/^memsize/d' -e '/^displayName/d' $vmx
  printf 'displayName = "%s"\nnumvcpus = "%s"\nmemsize = "%s"\n' $nom $cpu $ram >> $vmx
  carte=0
  for reseau in ${reseaux//,/ }; do
    cat >> $vmx <<X
ethernet$carte.present = "TRUE"
ethernet$carte.startConnected = "TRUE"
ethernet$carte.connectionType = "custom"
ethernet$carte.vnet = "$reseau"
ethernet$carte.virtualDev = "e1000e"
ethernet$carte.addressType = "static"
ethernet$carte.address = "00:50:56:3F:$(printf '%02X:%02X' $numero $carte)"
X
    carte=$((carte+1))
  done
  echo "$nom créée"
done
