#Start-Transcript -Path C:\Windows\Temp\log.txt

#Rename-Computer -NewName SRV-AD01
#New-NetIPAddress -InterfaceAlias "Ethernet0" -IPaddress 10.10.10.10 -PrefixLength 24 -DefaultGateway 10.10.10.1
#Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses "10.10.10.10"

#Install-WindowsFeature -Name AD-Domain-Services, DNS, DHCP -IncludeManagementTools

Restart-Computer -Force