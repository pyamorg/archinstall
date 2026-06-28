#!/usr/bin/env bash
#
# 03-chroot-config.sh
# Se ejecuta DENTRO de arch-chroot (después de 02-bootstrap.sh).
# Asume arranque UEFI (no BIOS legacy).

set -euo pipefail

echo "=================================================================="
echo "  Configuración del sistema (dentro del chroot)"
echo "=================================================================="

# ---- Zona horaria ----
read -rp "Zona horaria (ej: Europe/Madrid): " TZ_REGION
ln -sf "/usr/share/zoneinfo/${TZ_REGION}" /etc/localtime
hwclock --systohc

# ---- Locale ----
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#es_ES.UTF-8 UTF-8/es_ES.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=es_ES.UTF-8" > /etc/locale.conf

# ---- Hostname ----
read -rp "Hostname para este equipo: " HOSTNAME
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ---- Teclado en consola (vconsole, solo para la TTY de instalación) ----
# Tu Dvorak ya está configurado aparte dentro de hyprland.conf, esto es
# solo para la consola de texto antes de entrar a Hyprland.
echo "KEYMAP=us" > /etc/vconsole.conf

# ---- Contraseña de root ----
echo "Establece la contraseña de root:"
passwd

# ---- Usuario normal ----
read -rp "Nombre de usuario a crear: " USERNAME
useradd -m -G wheel -s /usr/bin/zsh "$USERNAME"
echo "Establece la contraseña de $USERNAME:"
passwd "$USERNAME"

# Habilitar sudo para el grupo wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Mover los dotfiles/scripts de root a la home del usuario nuevo
if [ -d /root/arch-hyprland-installer ]; then
    cp -r /root/arch-hyprland-installer "/home/${USERNAME}/arch-hyprland-installer"
    chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/arch-hyprland-installer"
fi

# ---- Cifrado de disco: detectar el contenedor LUKS ya abierto como "cryptroot" ----
LUKS_DEV=$(cryptsetup status cryptroot | awk '/device:/ {print $2}')
LUKS_UUID=$(cryptsetup luksUUID "$LUKS_DEV")
echo "Dispositivo LUKS detectado: $LUKS_DEV (UUID: $LUKS_UUID)"

# /etc/crypttab: permite que el initramfs sepa cómo desbloquear la raíz.
# "tpm2-device=auto" intenta TPM2 automáticamente si hay un token enrolado
# (lo enrolamos más abajo); si no hay token o falla, cae a pedir passphrase.
# "discard" pasa el TRIM al SSD a través del cifrado.
echo "cryptroot UUID=${LUKS_UUID} none tpm2-device=auto,discard" >> /etc/crypttab

# mkinitcpio: cambiar a hooks basados en systemd (necesarios para sd-encrypt,
# que es el que sabe hablar con TPM2 durante el arranque).
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard keymap consolefont block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# ---- Bootloader: GRUB (réplica de tu configuración actual, asume UEFI) ----
# grub y efibootmgr ya vienen instalados desde el pacstrap (02-bootstrap.sh)
# NOTA: /boot va en la partición EFI SIN cifrar, así que GRUB no necesita
# el módulo cryptodisk — solo arranca el kernel/initramfs normal, y es el
# propio initramfs (con sd-encrypt) el que desbloquea la raíz después.
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

# Tu /etc/default/grub, tal cual lo tenías
cat > /etc/default/grub << 'GRUBEOF'
# GRUB boot loader configuration
GRUB_DEFAULT="0"
GRUB_TIMEOUT="5"
GRUB_DISTRIBUTOR="Arch"
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"
GRUB_CMDLINE_LINUX="rd.luks.name=__LUKS_UUID__=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@"

# Preload both GPT and MBR modules so that they are not missed
GRUB_PRELOAD_MODULES="part_gpt part_msdos"

# Uncomment to enable booting from LUKS encrypted devices
#GRUB_ENABLE_CRYPTODISK="y"

# Set to 'countdown' or 'hidden' to change timeout behavior,
# press ESC key to display menu.
GRUB_TIMEOUT_STYLE="menu"

# Uncomment to use basic console
GRUB_TERMINAL_INPUT="console"

# Uncomment to disable graphical terminal
#GRUB_TERMINAL_OUTPUT=console

# The resolution used on graphical terminal
GRUB_GFXMODE=auto

# Uncomment to allow the kernel use the same resolution used by grub
GRUB_GFXPAYLOAD_LINUX="keep"

#GRUB_DISABLE_LINUX_UUID="true"

# Uncomment to disable generation of recovery mode menu entries
GRUB_DISABLE_RECOVERY="true"

GRUB_DISABLE_OS_PROBER="false"
GRUBEOF

# Sustituir el placeholder del UUID LUKS por el valor real detectado arriba
sed -i "s/__LUKS_UUID__/${LUKS_UUID}/" /etc/default/grub

# ---- Tema visual de GRUB (opcional) ----
echo
read -rp "¿Instalar un tema visual para GRUB (Particle-window)? [s/N]: " GRUB_THEME_YN
if [[ "$GRUB_THEME_YN" =~ ^[sS]$ ]]; then
    read -rp "Resolución de tu pantalla para el tema (ej: 2560x1440, o 'auto'): " GRUB_RES
    GRUB_RES="${GRUB_RES:-auto}"

    # Mapear resolución a la opción -s del instalador del tema (acepta
    # 2k/4k/etc; si no coincide con nada conocido, usa "2k" por defecto)
    case "$GRUB_RES" in
        *3840*|*4k*|*4K*) THEME_SIZE="4k" ;;
        *) THEME_SIZE="2k" ;;
    esac

    sed -i "s/^GRUB_GFXMODE=auto/GRUB_GFXMODE=${GRUB_RES},auto/" /etc/default/grub
    cat >> /etc/default/grub << EOF

# Tema Particle-window
GRUB_BACKGROUND="/usr/share/grub/themes/Particle-window/background.jpg"
GRUB_THEME="/usr/share/grub/themes/Particle-window/theme.txt"
EOF

    git clone https://github.com/yeyushengfan258/Particle-grub-theme.git /tmp/particle-theme
    (cd /tmp/particle-theme && ./install.sh -t window -s "$THEME_SIZE")
    rm -rf /tmp/particle-theme
fi

grub-mkconfig -o /boot/grub/grub.cfg

# ---- Dotfiles vía chezmoi (opcional, repo de cada persona) ----
USER_HOME="/home/${USERNAME}"
mkdir -p "${USER_HOME}/Pictures/wallpapers"
chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}/Pictures"

echo
echo "Si tienes un repositorio de dotfiles gestionado con chezmoi, dame"
echo "la URL (ej: https://github.com/tu-usuario/dotfiles.git o un path"
echo "local). Déjalo vacío si quieres un Hyprland limpio sin dotfiles."
read -rp "URL del repo de dotfiles (opcional): " DOTFILES_URL

if [ -n "$DOTFILES_URL" ]; then
    su - "${USERNAME}" -c "chezmoi init --apply '${DOTFILES_URL}'"

    # Convención: si el repo de dotfiles trae un install-packages.sh en
    # su raíz, es el lugar donde cada persona pone SUS paquetes (AUR
    # incluido) — este instalador genérico no asume nada sobre eso.
    INSTALL_PKGS="${USER_HOME}/.local/share/chezmoi/install-packages.sh"
    if [ -f "$INSTALL_PKGS" ]; then
        echo
        echo "Encontrado install-packages.sh en tu repo de dotfiles."
        echo "Se ejecutará en el paso 4 (04-post-install.sh), como tu"
        echo "usuario normal — necesita una sesión real para AUR/yay."
    fi
else
    echo "Sin dotfiles — Hyprland queda con su configuración por defecto."
fi

# ---- Carpetas de usuario en inglés (Downloads, Documents, etc.) ----
# Se escriben a mano en vez de depender de xdg-user-dirs-update, para
# que queden en inglés sin importar el locale del sistema (es_ES).
mkdir -p "$USER_HOME"/{Desktop,Downloads,Templates,Public,Documents,Music,Pictures,Videos}
cat > "$USER_HOME/.config/user-dirs.dirs" << 'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
EOF

chown -R "${USERNAME}:${USERNAME}" "$USER_HOME"

# ---- Display manager ----
systemctl enable sddm

# Auto-desbloquear gnome-keyring con la misma contraseña de login (SDDM),
# para que apps como gnome-calendar no vuelvan a pedir la contraseña
# del keyring por separado cada vez.
if ! grep -q pam_gnome_keyring /etc/pam.d/sddm 2>/dev/null; then
    sed -i '/^auth.*include.*system-login/a auth       optional     pam_gnome_keyring.so' /etc/pam.d/sddm
    sed -i '/^session.*include.*system-login/a session    optional     pam_gnome_keyring.so auto_start' /etc/pam.d/sddm
fi

# ---- Bluetooth ----
systemctl enable bluetooth

# ---- Servicios ----
systemctl enable NetworkManager

# ---- Snapper: snapshots automáticos del subvolumen raíz ----
# snap-pac crea un snapshot antes/después de cada operación de pacman,
# y se pueden tomar snapshots manuales en cualquier momento.
umount /.snapshots
rm -rf /.snapshots
snapper -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount -a
snapper -c root set-config "TIMELINE_CREATE=yes"
snapper -c root set-config "TIMELINE_CLEANUP=yes"
snapper -c root set-config "TIMELINE_LIMIT_HOURLY=6"
snapper -c root set-config "TIMELINE_LIMIT_DAILY=7"
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

# ---- TPM2: desbloqueo automático del disco con passphrase de respaldo ----
# Si el chip TPM2 falla, está ausente, o detecta manipulación del arranque
# (firmware/bootloader modificados), simplemente cae a pedir la passphrase
# que pusiste en 01-partition.sh — nunca te quedas sin acceso.
if [ -e /dev/tpmrm0 ] || [ -e /dev/tpm0 ]; then
    echo "--> TPM2 detectado, enrolando para desbloqueo automático..."
    if systemd-cryptenroll --tpm2-device=auto "$LUKS_DEV"; then
        echo "    TPM2 enrolado correctamente."
    else
        echo "    AVISO: el enrolamiento de TPM2 falló. El disco seguirá"
        echo "    pidiendo la passphrase manualmente en cada arranque, sin"
        echo "    problema. Puedes reintentarlo después con:"
        echo "      sudo systemd-cryptenroll --tpm2-device=auto $LUKS_DEV"
    fi
else
    echo "--> No se detectó TPM2 en este entorno. El disco pedirá la"
    echo "    passphrase manualmente en cada arranque. Si tu equipo sí"
    echo "    tiene TPM2 pero no se detectó aquí (puede pasar en el ISO"
    echo "    live), intenta esto después del primer arranque:"
    echo "      sudo systemd-cryptenroll --tpm2-device=auto $LUKS_DEV"
fi

echo
echo "=================================================================="
echo "  Configuración completa. Hyprland, SDDM y todos los dotfiles ya"
echo "  están listos para el primer arranque."
echo
echo "  Sal del chroot, desmonta y reinicia:"
echo "    exit"
echo "    umount -R /mnt"
echo "    reboot"
echo
echo "  Tras reiniciar, inicia sesión gráfica en SDDM con tu usuario"
echo "  ($USERNAME) y elige la sesión Hyprland. Todo debería funcionar"
echo "  YA, salvo wlogout (viene de AUR, requiere usuario normal real"
echo "  para compilar) — corre ./04-post-install.sh una vez dentro para"
echo "  completar eso."
echo "=================================================================="
