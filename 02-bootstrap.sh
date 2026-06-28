#!/usr/bin/env bash
#
# 02-bootstrap.sh
# Se ejecuta DESDE EL ISO LIVE, justo después de 01-partition.sh
# (con todo ya montado en /mnt).
#
# Instala el sistema base + un Hyprland mínimo razonable, y genera el fstab.
#
# Paquetes específicos de un usuario concreto (notificaciones, calendario,
# lockscreens vistosos, shells alternativos, etc.) NO van aquí — van en
# el "install-packages.sh" del repo de dotfiles de cada persona, que se
# ejecuta en 04-post-install.sh si lo provee.

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
    snapper snap-pac \
    grub efibootmgr \
    intel-ucode amd-ucode \
    chezmoi \
    hyprland waybar kitty rofi thunar dunst \
    hyprpaper hyprlock hypridle grim slurp wl-clipboard \
    qt5ct qt6ct polkit-kde-agent \
    pipewire pipewire-pulse wireplumber pavucontrol \
    network-manager-applet brightnessctl \
    bluez bluez-utils blueman \
    ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji papirus-icon-theme \
    dconf xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland \
    gnome-themes-extra xdg-user-dirs \
    btop sddm firefox

echo "--> Generando fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
echo
echo "fstab generado:"
cat /mnt/etc/fstab

echo
echo "--> Copiando scripts del instalador dentro del nuevo sistema..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -r "$SCRIPT_DIR" /mnt/root/arch-hyprland-installer

echo
echo "=================================================================="
echo "  Sistema base + Hyprland mínimo instalados."
echo "  Siguiente paso:"
echo "    arch-chroot /mnt"
echo "    cd /root/arch-hyprland-installer"
echo "    ./03-chroot-config.sh"
echo "=================================================================="
