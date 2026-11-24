Get-ADDomain
Resolve-DnsName greenreso.local

Read-Host "Enter"

New-ADOrganizationalUnit -Name "RH" -Path "DC=greenreso,DC=local"
