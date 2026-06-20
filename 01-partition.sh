#!/usr/bin/env bash
#
# 01-partition.sh
# Se ejecuta DESDE EL ISO LIVE DE ARCH (antes de instalar nada).
#
# Particiona el disco con tabla GPT:
#   - Partición EFI (512 MiB, FAT32)
#   - Partición raíz Btrfs (resto del disco) con subvolúmenes:
#       @         -> /
#       @home     -> /home
#       @snapshots-> /.snapshots   (usado por snapper)
#       @var_log  -> /var/log
#       @pkg      -> /var/cache/pacman/pkg
#
# Subvolúmenes Btrfs + snapper para snapshots automáticos del sistema.
# Permite hacer rollback completo en caso de updates rotos o cambios
# accidentales en el sistema de archivos.
#
# ESTE SCRIPT BORRA TODO EL CONTENIDO DEL DISCO QUE INDIQUES.
# No hay deshacer. Léelo dos veces antes de ejecutarlo.

set -euo pipefail

echo "=================================================================="
echo "  ADVERTENCIA: este script BORRA POR COMPLETO el disco indicado."
echo "=================================================================="
echo

lsblk -d -o NAME,SIZE,MODEL,TYPE
echo
read -rp "Escribe el nombre EXACTO del disco a usar (ej: sda, nvme0n1, NO /dev/sda): " DISKNAME
DISK="/dev/${DISKNAME}"

if [ ! -b "$DISK" ]; then
    echo "ERROR: $DISK no existe o no es un dispositivo de bloques. Abortando."
    exit 1
fi

echo
echo "Vas a borrar POR COMPLETO: $DISK"
lsblk "$DISK"
echo
read -rp "Escribe exactamente la palabra BORRAR (mayúsculas) para confirmar: " CONFIRM1
if [ "$CONFIRM1" != "BORRAR" ]; then
    echo "Cancelado. No se ha tocado el disco."
    exit 1
fi
read -rp "Última confirmación. Escribe de nuevo el nombre del disco ($DISKNAME) para continuar: " CONFIRM2
if [ "$CONFIRM2" != "$DISKNAME" ]; then
    echo "Cancelado. No se ha tocado el disco."
    exit 1
fi

echo
echo "--> Particionando $DISK (GPT: EFI 512MiB + resto en Btrfs)..."

# Determinar nombres de partición correctos (nvme usa "p1", sata/virtio usa "1")
if [[ "$DISKNAME" == nvme* ]] || [[ "$DISKNAME" == mmcblk* ]]; then
    PART_EFI="${DISK}p1"
    PART_ROOT="${DISK}p2"
else
    PART_EFI="${DISK}1"
    PART_ROOT="${DISK}2"
fi

parted -s "$DISK" \
    mklabel gpt \
    mkpart "EFI" fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart "ROOT" btrfs 513MiB 100%

echo "--> Formateando partición EFI ($PART_EFI)..."
mkfs.fat -F32 -n EFI "$PART_EFI"

echo
echo "--> Cifrando partición raíz ($PART_ROOT) con LUKS2..."
echo "    Vas a establecer la passphrase de cifrado del disco. GUÁRDALA"
echo "    en un sitio seguro — sin ella, no hay recuperación posible."
cryptsetup luksFormat --type luks2 "$PART_ROOT"

echo "--> Abriendo el contenedor cifrado..."
cryptsetup open "$PART_ROOT" cryptroot
CRYPT_DEV="/dev/mapper/cryptroot"

echo "--> Formateando partición raíz Btrfs sobre el volumen cifrado..."
mkfs.btrfs -f -L ROOT "$CRYPT_DEV"

echo "--> Creando subvolúmenes Btrfs..."
mount "$CRYPT_DEV" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@pkg
umount /mnt

echo "--> Montando subvolúmenes con compresión zstd + noatime..."
MOUNT_OPTS="noatime,compress=zstd,space_cache=v2"

mount -o "$MOUNT_OPTS,subvol=@" "$CRYPT_DEV" /mnt
mkdir -p /mnt/{boot,home,.snapshots,var/log,var/cache/pacman/pkg}
mount -o "$MOUNT_OPTS,subvol=@home" "$CRYPT_DEV" /mnt/home
mount -o "$MOUNT_OPTS,subvol=@snapshots" "$CRYPT_DEV" /mnt/.snapshots
mount -o "$MOUNT_OPTS,subvol=@var_log" "$CRYPT_DEV" /mnt/var/log
mount -o "$MOUNT_OPTS,subvol=@pkg" "$CRYPT_DEV" /mnt/var/cache/pacman/pkg
mount "$PART_EFI" /mnt/boot

echo
echo "=================================================================="
echo "  Particionado, cifrado y montaje completos."
echo "  Partición EFI : $PART_EFI  -> /mnt/boot (SIN cifrar)"
echo "  Partición ROOT: $PART_ROOT -> cifrada LUKS2 -> $CRYPT_DEV -> /mnt"
echo "                  (subvolúmenes @ @home @snapshots @var_log @pkg)"
echo
echo "  Siguiente paso: ./02-bootstrap.sh"
echo "=================================================================="
