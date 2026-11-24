$mdp = ConvertTo-SecureString "Azerty123!" -AsPlainText -Force
Install-ADDSForest -DomainName greenreso.local -DomainNetbiosName GREENRESO -SafeModeAdministratorPassword $mdp -InstallDns -Force