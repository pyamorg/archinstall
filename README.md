# archinstall — instalador Arch Linux + Hyprland

## Arquitectura: dos repos, dos responsabilidades

Este repo (`arch-install-scripts`) **solo monta el sistema**: disco,
cifrado, paquetes base, usuario, bootloader, snapshots. **No contiene
dotfiles.**

Toda la configuración de escritorio (Hyprland, waybar, rofi, dunst,
kitty, qt5ct/qt6ct, gtk, btop, zsh...) vive en un repo separado
gestionado con [chezmoi](https://www.chezmoi.io/):

```
git@github.com:pyamorg/dotfiles.git
```

¿Por qué separarlos? Porque son ciclos de vida distintos: el sistema
se monta una vez por máquina; los dotfiles cambian todo el rato y
quieres poder iterar sobre ellos (y aplicarlos en otras máquinas) sin
tocar el instalador. Mantenerlos juntos en un solo repo acababa
duplicando los mismos archivos en dos sitios y desincronizándose.

## Orden de ejecución

```
01-partition.sh        (ISO live)     particiona, cifra, formatea, monta
02-bootstrap.sh        (ISO live)     pacstrap del sistema base + paquetes
   |
   v  arch-chroot /mnt
03-chroot-config.sh    (chroot)       locale, usuario, cifrado, GRUB, snapper
   |
   v  exit; umount -R /mnt; reboot
   |
   (primer login en SDDM -> sesión Hyprland DE FÁBRICA, sin tu config)
   |
   v  abre una terminal (SUPER+Return por defecto) y entra a tu home
04-post-install.sh     (usuario normal, tras 1er arranque)
                        yay + AUR (wlogout, librewolf)
                        oh-my-zsh + zsh como shell por defecto
                        chezmoi init --apply <tu repo>  <- AQUÍ llega
                        tu Hyprland/waybar/rofi/zsh REALES
                        dconf (modo oscuro)
```

Después de `04-post-install.sh`, corre `hyprctl reload` (o cierra
sesión y vuelve a entrar) para que el escritorio tome toda tu config.

`snap-now.sh` es independiente del flujo anterior: es un atajo para
tomar un snapshot manual de snapper en cualquier momento
(`./snap-now.sh "antes de tocar el kernel"`).

## Primera vez: el repo de dotfiles está vacío

Si todavía no has subido nada a `pyamorg/dotfiles`, hazlo una vez
desde una máquina que ya tenga tu configuración actual (típicamente,
tu instalación de referencia):

```bash
# 0. Clave SSH para GitHub, si no la tienes ya en esta máquina
ls ~/.ssh/id_ed25519.pub 2>/dev/null || ssh-keygen -t ed25519 -C "tu_email@ejemplo.com"
cat ~/.ssh/id_ed25519.pub        # pégala en https://github.com/settings/keys
ssh -T git@github.com            # debe saludarte por tu usuario

# 1. Inicializar chezmoi (repo vacío, sin --apply)
chezmoi init git@github.com:pyamorg/dotfiles.git

# 2. Añadir tu config actual al source state de chezmoi
chezmoi add ~/.config/hypr
chezmoi add ~/.config/waybar
chezmoi add ~/.config/rofi
chezmoi add ~/.config/wlogout
chezmoi add ~/.config/dunst
chezmoi add ~/.config/kitty
chezmoi add ~/.config/qt5ct
chezmoi add ~/.config/qt6ct
chezmoi add ~/.config/xdg-desktop-portal
chezmoi add ~/.config/gtk-3.0
chezmoi add ~/.config/gtk-4.0
chezmoi add ~/.config/btop/btop.conf
chezmoi add ~/.config/btop/btop-overrides.conf
chezmoi add ~/.gtkrc-2.0
chezmoi add ~/.zshrc

# 3. Marcar como ejecutable el script de la terminal quake (chezmoi
#    necesita esto explícito para preservar el permiso al aplicar)
chezmoi chattr +executable ~/.config/hypr/scripts/quake-terminal.sh

# 4. Commit y push
chezmoi cd
git add -A
git commit -m "Primer commit: dotfiles iniciales"
git push -u origin main      # o "master", según la rama por defecto
exit
```

A partir de aquí, cualquier instalación nueva que corra
`04-post-install.sh` ya recibe todo esto automáticamente.

## Editar los dotfiles después

```bash
chezmoi edit ~/.config/hypr/hyprland.conf   # edita el archivo gestionado
chezmoi diff                                 # qué cambiaría al aplicar
chezmoi apply                                # aplica al sistema real
chezmoi cd && git add -A && git commit -m "..." && git push && exit
```

## Variables de `04-post-install.sh`

```bash
./04-post-install.sh                                   # usa el repo por defecto
./04-post-install.sh git@github.com:otro/repo.git       # repo distinto, por argumento
DOTFILES_REPO="git@github.com:otro/repo.git" ./04-post-install.sh  # por variable
```

El valor por defecto está en `DOTFILES_REPO_DEFAULT` dentro del propio
script.
