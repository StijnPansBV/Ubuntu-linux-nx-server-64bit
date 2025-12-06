Automatische Installatie & Watchdog Services voor Ubuntu 24.04 LTS
Auteur: Stijn Pans BV
Versie: 1.0
Datum: 2025-12-06

Beschrijving
Dit script automatiseert de installatie en configuratie van een Ubuntu 24.04 LTS server voor gebruik met Nx Witness en voegt twee belangrijke watchdog-mechanismen toe:


Disk Watchdog

Controleert extra schijven, maakt partities en labels aan indien nodig.
Mount schijven automatisch via UUID en LABEL.
Voert een reboot uit als geen enkele schijf gemount is (max. 1x per uur).



NX Watchdog

Controleert of de Nx Witness mediaserver draait.
Herstart de service indien deze niet actief is.



Daarnaast configureert het script:

Basisinstallatie van essentiële pakketten.
Unattended upgrades voor automatische updates.
Welkomstbanner met systeeminformatie.
Systemd timers voor periodieke uitvoering van watchdog scripts.
Cockpit inclusief Network Manager voor IP-configuratie via webinterface.


Installatie

Zorg dat je rootrechten hebt.
Download het script en voer het uit:

chmod +x install-ubuntu.sh
sudo ./install-ubuntu.sh

Het script installeert:

openssh-server, cockpit, cockpit-networkmanager, bpytop, unattended-upgrades, neofetch, figlet, wget, curl, parted, e2fsprogs, lsb-release
Nx Witness (versie 6.1.0.42176)
Welkomstbanner in /etc/motd




Nx Witness details

Downloadlink: https://updates.networkoptix.com/default/42176/linux/nxwitness-server-6.1.0.42176-linux_x64.deb
Wordt automatisch geïnstalleerd door het script.


IP-configuratie via Cockpit
Na installatie kun je IP-adressen beheren via Cockpit:

Open Cockpit in je browser:
https://<server-ip>:9090


Log in met je servergebruikersnaam.
Ga naar Netwerk → wijzig IP-instellingen via cockpit-networkmanager

Watchdog Functionaliteit

Disk Watchdog:

Script: /usr/local/bin/disk-watchdog.sh
Timer: /etc/systemd/system/disk-watchdog.timer (elke 30 seconden)


NX Watchdog:

Script: /usr/local/bin/nx-watchdog.sh
Timer: /etc/systemd/system/nx-watchdog.timer (elke 30 seconden)




Logbestanden

Disk Watchdog: /var/log/disk-watchdog.log
NX Watchdog: /var/log/nx-watchdog.log


Disclaimer
Gebruik dit script op eigen risico. Zorg voor back-ups van belangrijke data voordat je schijven formatteert.
