
#!/bin/bash
set -e

############################################################
# Controleer rootrechten
############################################################
if [ "$EUID" -ne 0 ]; then
  echo "Dit script moet als root worden uitgevoerd. Gebruik: sudo $0"
  exit 1
fi

LOGFILE="/var/log/install-script.log"
echo "=== Installatie gestart op $(date) ===" | tee -a "$LOGFILE"

############################################################
# 0. BASISINSTALLATIE
############################################################
echo "[INFO] Update en upgrade..." | tee -a "$LOGFILE"
apt update && apt upgrade -y

echo "[INFO] Universe repository toevoegen..." | tee -a "$LOGFILE"
add-apt-repository universe -y

echo "[INFO] Installeer benodigde pakketten..." | tee -a "$LOGFILE"
apt install -y openssh-server cockpit cockpit-networkmanager bpytop unattended-upgrades neofetch figlet wget curl parted e2fsprogs lsb-release speedtest-cli stress iperf3 netcat-openbsd

echo "[INFO] SSH activeren..." | tee -a "$LOGFILE"
systemctl enable --now ssh

echo "[INFO] Cockpit activeren..." | tee -a "$LOGFILE"
systemctl enable --now cockpit.socket

echo "[INFO] Configureer unattended-upgrades..." | tee -a "$LOGFILE"
dpkg-reconfigure unattended-upgrades

############################################################
# 0.1 FIX: NetworkManager inschakelen voor Cockpit (met check)
############################################################
if systemctl is-active --quiet NetworkManager; then
  echo "[INFO] NetworkManager is al actief, geen wijzigingen nodig." | tee -a "$LOGFILE"
else
  echo "[INFO] NetworkManager niet actief → installeren en activeren..." | tee -a "$LOGFILE"
  apt install -y network-manager
  systemctl disable --now systemd-networkd || true
  systemctl enable --now NetworkManager

  NETPLAN_FILE=$(ls /etc/netplan/*.yaml | head -n 1)
  if [ -n "$NETPLAN_FILE" ]; then
    sed -i 's/renderer: networkd/renderer: NetworkManager/' "$NETPLAN_FILE"
    netplan apply
    echo "[INFO] Netplan aangepast naar NetworkManager in $NETPLAN_FILE" | tee -a "$LOGFILE"
  else
    echo "[WAARSCHUWING] Geen Netplan-configuratie gevonden!" | tee -a "$LOGFILE"
  fi
fi

############################################################
# 0.2 NX Witness installeren
############################################################
echo "[INFO] Download en installeer Nx Witness..." | tee -a "$LOGFILE"
wget https://updates.networkoptix.com/default/42176/linux/nxwitness-server-6.1.0.42176-linux_x64.deb
dpkg -i nxwitness-server-6.1.0.42176-linux_x64.deb || apt install -f -y

############################################################
# 0.3 Welkomstbanner instellen
############################################################
echo "[INFO] Welkomstbanner instellen..." | tee -a "$LOGFILE"
{
  figlet "Welkom Stijn Pans BV"
  echo "OS: $(lsb_release -d | cut -f2)"
  echo "Kernel: $(uname -r)"
  echo "Host: $(hostname)"
} | tee /etc/motd
echo "neofetch" >> ~/.bashrc

############################################################
# 1. DISK WATCHDOG MET UUID + LABEL + MOUNT FIX + REBOOT
############################################################
mkdir -p /usr/local/bin /var/log /mnt/media

cat << 'EOF' > /usr/local/bin/disk-watchdog.sh
#!/bin/bash
LOGFILE="/var/log/disk-watchdog.log"
BASE="/mnt/media"
LAST_REBOOT_FILE="/var/log/last_disk_reboot"
echo "$(date): Disk Watchdog gestart" >> "$LOGFILE"

OS_PART=$(df / | tail -1 | awk '{print $1}')
OS_DISK="/dev/$(lsblk -no PKNAME $OS_PART)"
ALL_DISKS=($(lsblk -ndo NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}'))

DISKS=()
for D in "${ALL_DISKS[@]}"; do
    [ "$D" != "$OS_DISK" ] && DISKS+=("$D")
done

IFS=$'\n' DISKS=($(sort <<<"${DISKS[*]}"))
unset IFS

sed -i '/\/mnt\/media\//d' /etc/fstab

INDEX=1
SUCCESS=0
for DISK in "${DISKS[@]}"; do
    PART="${DISK}1"
    LABEL="MEDIA_${INDEX}"
    MOUNTPOINT="$BASE/$LABEL"

    if [ ! -e "$PART" ]; then
        echo "$(date): $DISK geen partitie → aanmaken" >> "$LOGFILE"
        parted "$DISK" --script mklabel gpt
        parted "$DISK" --script mkpart primary 0% 100%
        sleep 3
        mkfs.ext4 -F "$PART"
        sleep 2
    fi

    e2label "$PART" "$LABEL"
    UUID=$(blkid -s UUID -o value "$PART")
    mkdir -p "$MOUNTPOINT"

    if ! grep -q "$UUID" /etc/fstab; then
        echo "UUID=$UUID $MOUNTPOINT ext4 defaults,nofail,auto 0 0" >> /etc/fstab
        echo "$(date): fstab toegevoegd: $LABEL ($UUID)" >> "$LOGFILE"
        mount -a
    fi

    if ! mountpoint -q "$MOUNTPOINT"; then
        if mount "$MOUNTPOINT"; then
            SUCCESS=$((SUCCESS+1))
        else
            echo "$(date): MOUNT FAALDE voor $LABEL" >> "$LOGFILE"
        fi
    else
        SUCCESS=$((SUCCESS+1))
    fi

    INDEX=$((INDEX+1))
done

if [ $SUCCESS -eq 0 ]; then
    NOW=$(date +%s)
    if [ ! -f "$LAST_REBOOT_FILE" ] || [ $((NOW - $(cat $LAST_REBOOT_FILE))) -ge 3600 ]; then
        echo "$(date): Geen enkele schijf gemount → herstarten" >> "$LOGFILE"
        echo "$NOW" > "$LAST_REBOOT_FILE"
        reboot
    else
        echo "$(date): Geen schijven gemount, maar reboot al uitgevoerd in afgelopen uur" >> "$LOGFILE"
    fi
fi
EOF

chmod +x /usr/local/bin/disk-watchdog.sh

############################################################
# 2. NX WATCHDOG
############################################################
cat << 'EOF' > /usr/local/bin/nx-watchdog.sh
#!/bin/bash
LOGFILE="/var/log/nx-watchdog.log"
echo "$(date): NX Watchdog gestart" >> "$LOGFILE"
if ! systemctl is-active --quiet networkoptix-mediaserver.service; then
    echo "$(date): Nx Server draait niet → herstarten" >> "$LOGFILE"
    systemctl restart networkoptix-mediaserver.service
else
    echo "$(date): Nx Server OK" >> "$LOGFILE"
fi
EOF

chmod +x /usr/local/bin/nx-watchdog.sh

############################################################
# 3. SYSTEMD SERVICES + TIMERS
############################################################
cat << 'EOF' > /etc/systemd/system/disk-watchdog.service
[Unit]
Description=Disk Watchdog Service
[Service]
ExecStart=/usr/local/bin/disk-watchdog.sh
Type=oneshot
EOF

cat << 'EOF' > /etc/systemd/system/disk-watchdog.timer
[Unit]
Description=Run Disk Watchdog every 30 seconds
[Timer]
OnBootSec=15
OnUnitActiveSec=30
[Install]
WantedBy=timers.target
EOF

cat << 'EOF' > /etc/systemd/system/nx-watchdog.service
[Unit]
Description=NX Server Watchdog
[Service]
ExecStart=/usr/local/bin/nx-watchdog.sh
Type=oneshot
EOF

cat << 'EOF' > /etc/systemd/system/nx-watchdog.timer
[Unit]
Description=Run NX Watchdog every 30 seconds
[Timer]
OnBootSec=20
OnUnitActiveSec=30
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now disk-watchdog.timer
systemctl enable --now nx-watchdog.timer

############################################################
# 4. TECHNIEKER MENU INSTALLEREN (met kleurcodes en iperf3 fix)
############################################################
touch /var/log/techniekermenu.log
chmod 666 /var/log/techniekermenu.log

cat << 'EOF' > /usr/local/bin/techniekermenu
#!/bin/bash
LOGFILE="/var/log/techniekermenu.log"
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

while true; do
    clear
    echo -e "${BLUE}==============================================${RESET}"
    echo -e "${BLUE} TECHNIEKER MENU - SYSTEEM STATUS ${RESET}"
    echo -e "${BLUE}==============================================${RESET}"
    echo -e "${RED}⚠️  FOUT: Controleer systeemconfiguratie!${RESET}"
    echo -e "${YELLOW}Copyright © Vanherwegen Brent${RESET}"
    echo -e "${BLUE}----------------------------------------------${RESET}"
    echo -e "${GREEN}Health-check:${RESET}"
    echo -e "CPU Load: ${GREEN}$(uptime | awk '{print $10 $11 $12}')${RESET}"
    echo -e "RAM: ${GREEN}$(free -h | awk '/Mem:/ {print $3 \"/\" $2}')${RESET}"
    echo -e "Disk: ${GREEN}$(df -h / | tail -1 | awk '{print $3 \"/\" $2}')${RESET}"
    echo -e "${BLUE}----------------------------------------------${RESET}"
    echo -e "${YELLOW}1) Nx Witness opties${RESET}"
    echo -e "${YELLOW}2) Netwerk tests${RESET}"
    echo -e "${YELLOW}3) Systeem acties${RESET}"
    echo -e "${YELLOW}4) Schijfbeheer${RESET}"
    echo -e "${RED}0) Afsluiten${RESET}"
    echo -e "${BLUE}==============================================${RESET}"
    read -p "Maak een keuze: " keuze

    case $keuze in
        1)
            clear
            echo -e "${BLUE}Nx Witness opties:${RESET}"
            echo "a) Status bekijken"
            echo "b) Herstarten"
            echo "c) Terug"
            read -p "Keuze: " nx
            case $nx in
                a)
                    log_action "Nx Witness status opgevraagd"
                    systemctl status networkoptix-mediaserver.service
                    read -p "Enter om verder te gaan..."
                    ;;
                b)
                    log_action "Nx Witness herstart"
                    systemctl restart networkoptix-mediaserver.service
                    echo -e "${GREEN}[OK] Nx Witness herstart uitgevoerd.${RESET}"
                    read -p "Enter om verder te gaan..."
                    ;;
            esac
            ;;
        2)
            clear
            echo -e "${BLUE}Netwerk tests:${RESET}"
            echo "a) Speedtest"
            echo "b) Ping naar Google"
            echo "c) Open poort test (7001 & 9090)"
            echo "d) Bandbreedte test (iperf3)"
            echo "e) Terug"
            read -p "Keuze: " net
            case $net in
                a)
                    log_action "Speedtest uitgevoerd"
                    speedtest-cli
                    read -p "Enter om verder te gaan..."
                    ;;
                b)
                    log_action "Ping test naar Google"
                    ping -c 4 google.com
                    read -p "Enter om verder te gaan..."
                    ;;
                c)
                    log_action "Poort test uitgevoerd"
                    nc -zv localhost 7001 && echo -e "${GREEN}Poort 7001 open${RESET}" || echo -e "${RED}Poort 7001 gesloten${RESET}"
                    nc -zv localhost 9090 && echo -e "${GREEN}Poort 9090 open${RESET}" || echo -e "${RED}Poort 9090 gesloten${RESET}"
                    read -p "Enter om verder te gaan..."
                    ;;
                d)
                    log_action "Bandbreedte test gestart"
                    read -p "Voer het IP-adres van de iperf3-server in: " server_ip
                    iperf3 -c "$server_ip"
                    read -p "Enter om verder te gaan..."
                    ;;
            esac
            ;;
        3)
            clear
            echo -e "${BLUE}Systeem acties:${RESET}"
            echo "a) Ubuntu update"
            echo "b) Duurtest (CPU/RAM stress)"
            echo "c) Reboot systeem"
            echo "d) Terug"
            read -p "Keuze: " sys
            case $sys in
                a)
                    log_action "Ubuntu update uitgevoerd"
                    apt update && apt upgrade -y
                    echo -e "${GREEN}[OK] Update voltooid.${RESET}"
                    read -p "Enter om verder te gaan..."
                    ;;
                b)
                    log_action "Duurtest gestart"
                    stress --cpu 4 --timeout 60
                    echo -e "${GREEN}[OK] Duurtest voltooid.${RESET}"
                    read -p "Enter om verder te gaan..."
                    ;;
                c)
                    log_action "Systeem reboot"
                    reboot
                    ;;
            esac
            ;;
        4)
            clear
            echo -e "${BLUE}Schijfbeheer:${RESET}"
            echo "a) Oude harde schijf verwijderen"
            echo "b) Terug"
            read -p "Keuze: " disk
            case $disk in
                a)
                    log_action "Schijf verwijdering gestart"
                    lsblk
                    read -p "Voer device naam in (bijv. sdb): " dname
                    read -p "Weet je zeker dat je $dname wilt verwijderen? (ja/nee): " confirm
                    if [ "$confirm" == "ja" ]; then
                        wipefs -a /dev/$dname
                        echo -e "${GREEN}[OK] Schijf $dname gewist.${RESET}"
                        log_action "Schijf $dname gewist"
                    else
                        echo -e "${YELLOW}Actie geannuleerd.${RESET}"
                        log_action "Schijf verwijdering geannuleerd"
                    fi
                    read -p "Enter om verder te gaan..."
                    ;;
            esac
            ;;
        0)
            echo "Afsluiten..."
            log_action "Techniekermenu afgesloten"
            exit 0
            ;;
        *)
            echo -e "${RED}Ongeldige keuze!${RESET}"
            sleep 2
            ;;
    esac
done
EOF

chmod +x /usr/local/bin/techniekermenu

echo "=== Installatie voltooid ===" | tee -a "$LOGFILE"
echo "Compatibel met Ubuntu Server 24.04 LTS"
echo "Nx Witness geïnstalleerd (versie 6.1.0.42176)."
echo "Cockpit uitgebreid met IP-configuratie via NetworkManager."
echo "Techniekermenu beschikbaar via commando: techniekermenu"
echo "Klaar! 🎉"
``
