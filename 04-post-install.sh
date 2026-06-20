#!/usr/bin/env bash
#
# 04-post-install.sh
# Se ejecuta como USUARIO NORMAL (no root), tras el primer arranque.
#
# 03-chroot-config.sh solo dejó el SISTEMA listo (cuenta, cifrado,
# bootloader, snapshots). Este script es el que monta el ESCRITORIO:
#
#   1. yay + paquetes de AUR (wlogout, librewolf) — necesitan un
#      usuario normal real con systemd/red ya arrancados, no un chroot.
#   2. oh-my-zsh, y zsh como shell por defecto.
#   3. chezmoi: clona tu repo de dotfiles y aplica TODA la config real
#      de Hyprland/waybar/rofi/dunst/kitty/etc. Hasta este paso, el
#      Hyprland que ves tras el primer login es el de fábrica.
#   4. Preferencia de modo oscuro (dconf), que necesita un bus de
#      sesión real y por eso no se podía hacer dentro del chroot.
#
# Uso:
#   ./04-post-install.sh [URL_REPO_CHEZMOI]
#   DOTFILES_REPO="git@github.com:usuario/dotfiles.git" ./04-post-install.sh
#
# Si no se indica nada, usa DOTFILES_REPO_DEFAULT (más abajo).

set -euo pipefail

DOTFILES_REPO_DEFAULT="git@github.com:pyamorg/dotfiles.git"
DOTFILES_REPO="${1:-${DOTFILES_REPO:-$DOTFILES_REPO_DEFAULT}}"

if [ "$EUID" -eq 0 ]; then
    echo "ERROR: no corras este script como root. Hazlo con tu usuario normal."
    exit 1
fi

echo "=================================================================="
echo "  Instalando yay (AUR helper) + wlogout"
echo "=================================================================="

if ! command -v yay &> /dev/null; then
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
    (cd "$tmpdir/yay" && makepkg -si --noconfirm)
    rm -rf "$tmpdir"
fi

yay -S --needed --noconfirm wlogout

echo
echo "=================================================================="
echo "  Instalando oh-my-zsh"
echo "=================================================================="
# zsh y chezmoi ya vienen del pacstrap (02-bootstrap.sh). oh-my-zsh no
# tiene paquete de pacman, así que se instala con su script oficial.
# RUNZSH=no evita que el instalador entre directo a una sesión zsh
# (se quedaría colgado en un script no interactivo).
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no CHSH=no sh -c \
        "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "--> oh-my-zsh ya estaba instalado, omitiendo."
fi

echo
echo "--> Cambiando la shell por defecto a zsh"
sudo usermod -s "$(command -v zsh)" "$USER"

echo
echo "=================================================================="
echo "  Aplicando dotfiles reales con chezmoi ($DOTFILES_REPO)"
echo "=================================================================="
# Este paso clona tu repo de dotfiles y escribe Hyprland, waybar, rofi,
# dunst, kitty, qt5ct/qt6ct, gtk, btop y .zshrc de verdad en ~/.config
# y en la home. Sustituye al Hyprland de fábrica con el que arrancaste.
chezmoi init --apply "$DOTFILES_REPO"

# scripts/quake-terminal.sh necesita el bit ejecutable. chezmoi solo lo
# preserva si el archivo está marcado como "executable_" en el repo;
# si no, lo forzamos aquí también para no depender de eso.
QUAKE_SCRIPT="$HOME/.config/hypr/scripts/quake-terminal.sh"
if [ -f "$QUAKE_SCRIPT" ]; then
    chmod +x "$QUAKE_SCRIPT"
fi

echo
echo "=================================================================="
echo "  Aplicando preferencia de modo oscuro (dconf)"
echo "=================================================================="
# Esto necesita un bus de sesión real corriendo, por eso no se puede
# hacer dentro del chroot en 03-chroot-config.sh.
dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita-dark'"

echo
echo "=================================================================="
echo "  Listo. Tu Hyprland real (el del repo de chezmoi) ya está"
echo "  aplicado. Recárgalo sin cerrar sesión con:"
echo "    hyprctl reload"
echo
echo "  No olvides poner tu wallpaper en:"
echo "    ~/Pictures/wallpapers/fondo.jpg"
echo "  (la carpeta ya existe, solo falta el archivo)"
echo
echo "  Si el nombre de tu monitor no es eDP-1, ajusta en tu repo de"
echo "  dotfiles: hypr/hyprpaper.conf (lo ves con: hyprctl monitors)"
echo
echo "  La shell por defecto ahora es zsh: cierra sesión y vuelve a"
echo "  entrar (o abre una terminal nueva) para que se aplique."
echo "=================================================================="
