#!/bin/bash
set -e  # stop bij fouten

echo "Update en upgrade..."
sudo apt update && sudo apt upgrade -y

echo "Installeer Cockpit..."
sudo apt install cockpit -y

echo "Installeer bpytop..."
sudo apt install bpytop -y

echo "Installeer unattended-upgrades..."
sudo apt install unattended-upgrades -y

echo "Configureer unattended-upgrades..."
sudo dpkg-reconfigure unattended-upgrades

echo "Download Nx Witness server package..."
wget https://updates.networkoptix.com/default/41837/linux/nxwitness-server-6.0.6.41837-linux_x64.deb

echo "Installeer Nx Witness server..."
sudo dpkg -i nxwitness-server-6.0.6.41837-linux_x64.deb
sudo apt install -f -y

echo "Download Nx Witness client package..."
wget https://updates.networkoptix.com/default/41837/linux/nxwitness-client-6.0.6.41837-linux_x64.deb

echo "Installeer Nx Witness client..."
sudo dpkg -i nxwitness-client-6.0.6.41837-linux_x64.deb
sudo apt install -f -y

echo "Installeer Neofetch..."
sudo apt install neofetch -y

echo "Klaar! Met veel dank aan Vanherwegen Brent die alles voor je gedaan heeft! :) 🎉"
