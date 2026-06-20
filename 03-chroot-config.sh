#!/usr/bin/env bash
#
# 03-chroot-config.sh
# Se ejecuta DENTRO de arch-chroot (después de 02-bootstrap.sh).
# Asume arranque UEFI (no BIOS legacy).
#
# Este script monta el SISTEMA: locale, hostname, usuario, cifrado,
# bootloader, snapshots. NO toca configuración de escritorio (eso no
# vive en este repo): Hyprland/waybar/rofi/zsh/etc. se aplican después
# del primer arranque, en 04-post-install.sh, vía chezmoi.

set -euo pipefail

echo "=================================================================="
echo "  Configuración del sistema (dentro del chroot)"
echo "=================================================================="

# ---- Zona horaria ----
read -rp "Zona horaria (ej: Europe/Madrid): " TZ_REGION
ln -sf "/usr/share/zoneinfo/${TZ_REGION}" /etc/localtime
hwclock --systohc

# ---- Idioma / Locale ----
# Preguntamos el idioma del sistema (LANG), pero las carpetas de
# usuario (Desktop, Downloads...) más abajo se dejan en inglés SIEMPRE,
# sea cual sea el idioma elegido aquí — son cosas independientes.
read -rp "Idioma del sistema, formato locale (ej: es_ES, en_US, fr_FR) [es_ES]: " SYS_LANG
SYS_LANG="${SYS_LANG:-es_ES}"

# en_US.UTF-8 se genera siempre como base/fallback (muchas herramientas
# lo asumen disponible), y además el que hayas elegido si es distinto.
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
if [ "$SYS_LANG" != "en_US" ]; then
    if ! grep -q "^${SYS_LANG}.UTF-8 UTF-8" /etc/locale.gen; then
        echo "ADVERTENCIA: ${SYS_LANG}.UTF-8 no aparece en /etc/locale.gen."
        echo "Revisa que el locale exista (ver /etc/locale.gen) y vuelve a lanzar este script si falla."
    fi
    sed -i "s/^#${SYS_LANG}.UTF-8 UTF-8/${SYS_LANG}.UTF-8 UTF-8/" /etc/locale.gen
fi
locale-gen
echo "LANG=${SYS_LANG}.UTF-8" > /etc/locale.conf

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
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "Establece la contraseña de $USERNAME:"
passwd "$USERNAME"

# Habilitar sudo para el grupo wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Mover los scripts de instalación de root a la home del usuario nuevo
# (para poder correr 04-post-install.sh tras el primer arranque)
if [ -d /root/arch-install-scripts ]; then
    cp -r /root/arch-install-scripts "/home/${USERNAME}/arch-install-scripts"
    chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/arch-install-scripts"
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
GRUB_GFXMODE=2560x1440,auto

# Uncomment to allow the kernel use the same resolution used by grub
GRUB_GFXPAYLOAD_LINUX="keep"

#GRUB_DISABLE_LINUX_UUID="true"

# Uncomment to disable generation of recovery mode menu entries
GRUB_DISABLE_RECOVERY="true"

# Colores del menú
export GRUB_COLOR_NORMAL="light-blue/black"
export GRUB_COLOR_HIGHLIGHT="light-cyan/blue"

# Tema Particle-window
GRUB_BACKGROUND="/usr/share/grub/themes/Particle-window/background.jpg"
GRUB_THEME="/usr/share/grub/themes/Particle-window/theme.txt"

#GRUB_INIT_TUNE="480 440 1"
#GRUB_SAVEDEFAULT="true"
#GRUB_DISABLE_SUBMENU="y"

# Sin dual-boot, no necesitamos os-prober, pero lo dejamos igual que
# tenías por si en el futuro añades otro sistema:
GRUB_DISABLE_OS_PROBER="false"
GRUBEOF

# Sustituir el placeholder del UUID LUKS por el valor real detectado arriba
sed -i "s/__LUKS_UUID__/${LUKS_UUID}/" /etc/default/grub

# ---- Tema Particle-window (yeyushengfan258/Particle-grub-theme) ----
# Instalado SIN el flag -b, para que quede en /usr/share/grub/themes/
# (coincide con las rutas de GRUB_BACKGROUND/GRUB_THEME de arriba).
# -s 2k porque tu GRUB_GFXMODE es 2560x1440.
git clone https://github.com/yeyushengfan258/Particle-grub-theme.git /tmp/particle-theme
(cd /tmp/particle-theme && ./install.sh -t window -s 2k)
rm -rf /tmp/particle-theme

grub-mkconfig -o /boot/grub/grub.cfg

# ---- Carpetas de usuario en inglés (Downloads, Documents, etc.) ----
# Se escriben a mano en vez de depender de xdg-user-dirs-update, para
# que queden en inglés SIEMPRE — sin importar qué LANG se haya elegido
# arriba (es_ES, fr_FR, lo que sea). xdg-user-dirs-update traduciría
# estos nombres según el locale; aquí los fijamos a propósito.
# Esto es independiente de chezmoi: son carpetas estándar de cualquier
# escritorio, no "dotfiles" gestionados por el repo de chezmoi.
USER_HOME="/home/${USERNAME}"
mkdir -p "$USER_HOME"/{Desktop,Downloads,Templates,Public,Documents,Music,Pictures,Videos}
mkdir -p "$USER_HOME/Pictures/wallpapers"
mkdir -p "$USER_HOME/.config"
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
echo "  Configuración de sistema completa: usuario, cifrado, bootloader,"
echo "  snapshots y servicios base ya están listos."
echo
echo "  Sal del chroot, desmonta y reinicia:"
echo "    exit"
echo "    umount -R /mnt"
echo "    reboot"
echo
echo "  Tras reiniciar, inicia sesión gráfica en SDDM con tu usuario"
echo "  ($USERNAME) y elige la sesión Hyprland. Verás el Hyprland de"
echo "  FÁBRICA (sin tu configuración todavía) — sirve para abrir una"
echo "  terminal (SUPER+Return por defecto) y seguir desde ahí."
echo
echo "  Una vez dentro, corre:"
echo "    cd ~/arch-install-scripts"
echo "    ./04-post-install.sh git@github.com:USUARIO/dotfiles.git"
echo "  Eso instala yay/wlogout, oh-my-zsh, y aplica TODOS tus dotfiles"
echo "  reales (Hyprland, waybar, rofi, zsh...) vía chezmoi."
echo "=================================================================="
