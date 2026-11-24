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
    d="/tmp/$f"

    # Copie du script de configuration dans Ubuntu.
    vmrun -T ws -gu ubuntu -gp "$UPW" \
        copyFileFromHostToGuest "$vmx" "$s" "$d"

    # Création d'un lanceur temporaire pour éviter les problèmes
    # de transmission des arguments de bash -c par VMware.
    launcher="$(mktemp)"
    guest_launcher="/tmp/greenreso-launch-$(basename "$launcher").sh"

    chmod 600 "$launcher"

    {
        printf '#!/usr/bin/env bash\n'
        printf 'set -eu\n'
        printf 'trap '\''rm -f -- "$0"'\'' EXIT\n'
        printf 'exec > /tmp/greenreso-deploy.log 2>&1\n'
        printf 'password=%q\n' "$UPW"
        printf 'script=%q\n' "$d"

        cat <<'EOF'
printf '%s\n' "$password" |
    /usr/bin/sudo -S -- /bin/bash "$script"
EOF
    } > "$launcher"

    # Copie du lanceur, puis suppression de sa version locale.
    if ! vmrun -T ws -gu ubuntu -gp "$UPW" \
        copyFileFromHostToGuest \
        "$vmx" "$launcher" "$guest_launcher"; then
        rm -f "$launcher"
        exit 1
    fi

    rm -f "$launcher"

    # Exécution directe : aucun bash -c ni argument vide.
    rc=0
    vmrun -T ws -gu ubuntu -gp "$UPW" \
        runProgramInGuest "$vmx" \
        /bin/bash "$guest_launcher" || rc=$?

    # Récupération du journal, même en cas d'échec.
    log="$PWD/../FW-NANTES-deploy.log"

    if vmrun -T ws -gu ubuntu -gp "$UPW" \
        copyFileFromGuestToHost \
        "$vmx" /tmp/greenreso-deploy.log "$log"; then
        cat "$log"
    else
        echo "Impossible de récupérer le journal de déploiement."
    fi

    exit "$rc"
fi
