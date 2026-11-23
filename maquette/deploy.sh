#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
source .env
vmx=$V/$1/$1.vmx; s=$(realpath "$2"); f=$(basename "$s")

if [[ $f = *.ps1 ]]; then
  g="-gu Administrator -gp $PW"; d="C:\\Windows\\Temp\\$f"
  vmrun -T ws $g copyFileFromHostToGuest "$vmx" "$s" "$d"
  vmrun -T ws $g runProgramInGuest "$vmx" 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ExecutionPolicy Bypass -File "$d"
else
  g="-gu ubuntu -gp $UPW"; d=/tmp/$f
  vmrun -T ws $g copyFileFromHostToGuest "$vmx" "$s" "$d"
  vmrun -T ws $g runProgramInGuest "$vmx" /usr/bin/sudo /bin/bash "$d"
fi
