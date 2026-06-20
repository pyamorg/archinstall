#!/usr/bin/env bash
#
# 02-bootstrap.sh
# Se ejecuta DESDE EL ISO LIVE, justo después de 01-partition.sh
# (con todo ya montado en /mnt).
#
# Instala el sistema base con pacstrap y genera el fstab.

set -euo pipefail

if ! mountpoint -q /mnt; then
    echo "ERROR: /mnt no está montado. Corre primero 01-partition.sh"
    exit 1
fi

echo "--> Sincronizando reloj..."
timedatectl set-ntp true

echo "--> Instalando sistema base (esto tarda varios minutos)..."
pacstrap -K /mnt \
    base base-devel linux linux-firmware \
    btrfs-progs cryptsetup tpm2-tools \
    networkmanager \
    sudo vim git \
    zsh chezmoi \
    snapper snap-pac \
    grub efibootmgr \
    intel-ucode amd-ucode \
    hyprland waybar kitty rofi thunar dunst \
    hyprpaper hyprlock hypridle grim slurp wl-clipboard \
    qt5ct qt6ct polkit-kde-agent \
    pipewire pipewire-pulse wireplumber pavucontrol \
    network-manager-applet brightnessctl \
    ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji \
    btop papirus-icon-theme \
    sddm firefox \
    bluez bluez-utils blueman pacman-contrib \
    dconf xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland \
    gnome-themes-extra xdg-user-dirs

echo "--> Generando fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
echo
echo "fstab generado:"
cat /mnt/etc/fstab

echo
echo "--> Copiando los scripts de instalación dentro del nuevo sistema..."
# Solo los scripts (01-04, snap-now.sh, README). Los dotfiles de
# escritorio (Hyprland, waybar, zsh...) NO viven aquí: viven en un repo
# aparte gestionado con chezmoi y se aplican en 04-post-install.sh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "$SCRIPT_DIR" /mnt/root/arch-install-scripts

echo
echo "=================================================================="
echo "  Sistema base instalado."
echo "  Siguiente paso:"
echo "    arch-chroot /mnt"
echo "    cd /root/arch-install-scripts"
echo "    ./03-chroot-config.sh"
echo "=================================================================="
