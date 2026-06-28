#!/usr/bin/env bash
#
# 04-post-install.sh
# Se ejecuta como USUARIO NORMAL (no root), tras el primer arranque.
#
# Genérico: solo bootstrapea yay (AUR) y, si tu repo de dotfiles trae un
# install-packages.sh en su raíz, lo ejecuta. Ese archivo es donde TÚ
# defines tus paquetes personales (AUR incluido) — este instalador no
# asume nada sobre ellos.

set -euo pipefail

if [ "$EUID" -eq 0 ]; then
    echo "ERROR: no corras este script como root. Hazlo con tu usuario normal."
    exit 1
fi

echo "=================================================================="
echo "  Instalando yay (AUR helper)"
echo "=================================================================="

if ! command -v yay &> /dev/null; then
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
    (cd "$tmpdir/yay" && makepkg -si --noconfirm)
    rm -rf "$tmpdir"
fi

INSTALL_PKGS="$HOME/.local/share/chezmoi/install-packages.sh"
if [ -f "$INSTALL_PKGS" ]; then
    echo
    echo "=================================================================="
    echo "  Ejecutando install-packages.sh de tu repo de dotfiles"
    echo "=================================================================="
    chmod +x "$INSTALL_PKGS"
    "$INSTALL_PKGS"
else
    echo
    echo "Sin install-packages.sh en tu repo de dotfiles (o sin dotfiles) —"
    echo "nada más que instalar aquí."
fi

echo
echo "=================================================================="
echo "  Listo. Reinicia sesión o el equipo, y elige Hyprland en SDDM."
echo "=================================================================="
