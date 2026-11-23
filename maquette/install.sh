#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"; source .env
taskset -pc 1-$(($(nproc)-1)) $$ >/dev/null
mkdir -p $V/_tpl

installe() {
  d=$V/_tpl/$1; vmx=$d/$1.vmx
  mkdir -p $d; rm -f $d/*
  vmware-vdiskmanager -c -s ${4}GB -a lsilogic -t 0 $d/$1.vmdk >/dev/null
  sed "s/@NAME@/$1/;s/@OS@/$2/;s/@RAM@/$3/" files/base.vmx > $vmx
  cat >> $vmx <<X
sata0:1.present = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "$PWD/iso/$1.iso"
X
  if [ -n "${5:-}" ]; then
    sed "s/@INDEX@/$5/;s/@PW@/$PW/" files/autounattend.xml > $d/autounattend.xml
    mformat -C -f 1440 -i $d/reponses.flp ::
    mcopy -i $d/reponses.flp $d/autounattend.xml files/first.ps1 ::
    cat >> $vmx <<X
sata0:2.present = "TRUE"
sata0:2.deviceType = "cdrom-image"
sata0:2.fileName = "/usr/lib/vmware/isoimages/windows.iso"
floppy0.present = "TRUE"
floppy0.fileType = "file"
floppy0.fileName = "$d/reponses.flp"
X
  fi
  vmrun -T ws start $vmx
}

termine() {
  vmx=$V/_tpl/$1/$1.vmx
  while vmrun -T ws list | grep -qF $vmx; do sleep 15; done
  sed -i -e '/^sata0:[1-9]/d' -e '/^floppy0/d' $vmx
  vmrun -T ws snapshot $vmx base
}

pret() { vmrun -T ws listSnapshots $V/_tpl/$1/$1.vmx 2>/dev/null | grep -qx base;}
faits=
pret ubuntu || { installe ubuntu ubuntu-64 2048 20;               faits="$faits ubuntu";}
pret winsrv || { installe winsrv windows2019srvnext-64 4096 40 2; faits="$faits winsrv";}
pret win10  || { installe win10 windows9-64 4096 40 1;            faits="$faits win10";}

for m in $faits; do termine $m; done
