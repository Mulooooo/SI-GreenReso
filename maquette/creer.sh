#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"; source .env

for net in $(grep -vE '^\s*(#|$)' ../vms.conf | cut -d'|' -f5 | tr ',' '\n' | sort -u); do
  n=${net#vmnet}
  grep -q "VNET_${n}_" /etc/vmware/networking && continue
  sudo tee -a /etc/vmware/networking >/dev/null <<X
answer VNET_${n}_DHCP no
answer VNET_${n}_HOSTONLY_NETMASK 255.255.255.0
answer VNET_${n}_HOSTONLY_SUBNET 10.10.$(( (n-10)*10 )).0
answer VNET_${n}_VIRTUAL_ADAPTER no
X
  ajoute=oui
done
[ -z "${ajoute:-}" ] || { sudo vmware-networks --stop; sudo vmware-networks --start; }

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
