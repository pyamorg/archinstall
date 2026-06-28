# Arch + Hyprland — instalador genérico

Instala Arch Linux desde cero con Hyprland, cifrado de disco (LUKS2 +
desbloqueo TPM2 con passphrase de respaldo), Btrfs con snapshots
automáticos (snapper), GRUB, y un Hyprland mínimo y funcional.

**No asume nada sobre tus preferencias personales.** Si tienes un repo
de dotfiles gestionado con [chezmoi](https://www.chezmoi.io/), el
instalador te pide la URL en el paso 3 y lo aplica automáticamente —
si tu repo de dotfiles trae un `install-packages.sh` en su raíz, también
se ejecuta solo, en el paso 4.

## Orden de ejecución

| # | Script | Dónde |
|---|--------|-------|
| 1 | `01-partition.sh` | ISO live — particiona, cifra (LUKS2), Btrfs+subvolúmenes |
| 2 | `02-bootstrap.sh` | ISO live — pacstrap del sistema base + Hyprland mínimo |
| 3 | `03-chroot-config.sh` | Dentro de `arch-chroot` — usuario, GRUB, snapper, TPM2, **tus dotfiles (opcional)** |
| 4 | `04-post-install.sh` | Usuario normal, post-reboot — yay + **tu `install-packages.sh` (opcional)** |

```bash
chmod +x *.sh
./01-partition.sh
./02-bootstrap.sh

arch-chroot /mnt
cd /root/arch-hyprland-installer
chmod +x *.sh
./03-chroot-config.sh
# Aquí te pregunta la URL de tu repo de dotfiles (opcional)

exit
umount -R /mnt
reboot
```

Tras el primer arranque (SDDM → Hyprland):
```bash
cd ~/arch-hyprland-installer
./04-post-install.sh
```

## Cómo enganchar TU repo de dotfiles

1. Tu repo de dotfiles debe ser un source de chezmoi normal (carpeta con
   `dot_config/`, `.chezmoi.toml.tmpl` si usas variables, etc.).
2. Opcionalmente, pon un `install-packages.sh` ejecutable en la raíz de
   ESE repo (no en este) con tus paquetes personales — oficiales y AUR.
   Lo detecta y ejecuta solo `04-post-install.sh`.
3. Al correr `03-chroot-config.sh`, dale la URL (HTTPS de GitHub/GitLab,
   o un path local si lo tienes en un USB).

Ejemplo de `install-packages.sh` (plantilla incluida en este repo como
`install-packages.sh.PARA-TU-OTRO-REPO` — cópialo a la raíz de tu repo
de dotfiles, sin la extensión, y ajústalo a tus paquetes reales).

## Cifrado de disco

LUKS2 en la partición raíz (la EFI queda sin cifrar). Desbloqueo por
TPM2 si tu hardware lo soporta, con passphrase de respaldo siempre
activa. **Guarda la passphrase en un sitio seguro** — sin ella no hay
recuperación posible.

## Snapshots (Snapper)

Subvolúmenes `@`, `@home`, `@snapshots`, `@var_log`, `@pkg`. Snapshots
automáticos en cada operación de pacman (`snap-pac`) y cada hora.
```bash
sudo snapper -c root list
sudo snapper -c root undochange <N>..0
```
`./snap-now.sh "descripción"` para un snapshot manual rápido.

## GRUB

Se te pregunta si quieres el tema visual **Particle-window**
([yeyushengfan258/Particle-grub-theme](https://github.com/yeyushengfan258/Particle-grub-theme))
y a qué resolución. Si dices que no, GRUB queda con su aspecto por
defecto.

## ⚠️ Sobre `01-partition.sh`

Borra por completo el disco que le indiques. Pide el nombre dos veces
y una palabra de confirmación exacta — aun así, revisa con `lsblk`
antes de correrlo.
