net user Administrator /active:yes
netsh advfirewall firewall add rule name=icmp protocol=icmpv4:8,any dir=in action=allow
$t = Get-PSDrive -PSProvider FileSystem | ? { Test-Path "$($_.Root)Program Files\VMware" } | select -First 1
Start-Process "$($t.Root)setup.exe" -ArgumentList '/S /v "/qn REBOOT=ReallySuppress"' -Wait
shutdown /s /t 10
