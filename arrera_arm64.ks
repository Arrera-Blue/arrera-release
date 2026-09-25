# ==============================================================================
# Arrera Linux - Kickstart ARM64 (aarch64)
# ==============================================================================
# IMPORTANT : Ce fichier est le Kickstart officiel ARM64 pour Arrera Linux.
# ==============================================================================

# --------------------------------------------------------------------------
# Configuration générale
# --------------------------------------------------------------------------

# Arrêt automatique après installation
poweroff

lang fr_FR.UTF-8
keyboard --vckeymap=fr --xlayouts='fr'
timezone Europe/Paris --utc

network --bootproto=dhcp --device=link --activate
network --hostname=arrera

# Compte utilisateur
rootpw --lock
user --name=arrera --groups=wheel --plaintext --password=arrera
selinux --permissive


# --------------------------------------------------------------------------
# Dépôts (Système 100% à jour à l'installation + Dépôt Copr Arrera)
# --------------------------------------------------------------------------

url --metalink="https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch"
repo --name="updates" --metalink="https://mirrors.fedoraproject.org/metalink?repo=updates-released-f$releasever&arch=$basearch" --install --cost=50
repo --name="copr-arrera-blue" --baseurl="https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/fedora-$releasever-$basearch/" --cost=100

# Partitionnement (taille fixe requise par livemedia-creator --no-virt)
# ARM64 est 100% UEFI : la partition ESP est OBLIGATOIRE (pas de BIOS Legacy)
zerombr
clearpart --all --initlabel
part /boot/efi --size=1024 --fstype=efi
part / --size=10240 --fstype=ext4

# --------------------------------------------------------------------------
# Services
# --------------------------------------------------------------------------

services --enabled=NetworkManager,firewalld,arrera-kiosk --disabled=gdm

# --------------------------------------------------------------------------
# Paquets
# --------------------------------------------------------------------------

%packages --ignoremissing

# === Base système ===
@core
@hardware-support

# Noyau et démarrage ARM64 (aarch64 systemd-boot UEFI)
kernel
dracut-live
systemd-boot-unsigned
efibootmgr
efivar
dosfstools

# === Claviers et langues complètes ===
xkeyboard-config
libxkbcommon
libxkbcommon-x11
glibc-all-langpacks
langpacks-fr
langpacks-en
langpacks-es
langpacks-de
langpacks-it
langpacks-pt_BR
langpacks-ar
langpacks-zh_CN
langpacks-ja
ibus
ibus-gtk3
ibus-gtk4
ibus-typing-booster

# === Bureau GNOME minimal ===
gnome-shell
gnome-session
gnome-settings-daemon
arrera-gnome-control-center
mutter
gdm
gnome-keyring
xdg-user-dirs
xdg-desktop-portal-gnome
dbus

# === Applications demandées ===
nautilus
firefox
gnome-tweaks
gnome-extensions-app
gnome-text-editor
gnome-disk-utility
loupe
evince
gnome-calendar
gnome-clocks
gnome-weather
ptyxis

# === Partage de fichiers Windows (SMB/CIFS) ===
gvfs-smb
samba-client
cifs-utils

# === Extensions GNOME ===
gnome-shell-extension-appindicator
gnome-shell-extension-forge
gnome-shell-extension-gpaste

# === Outils système ===
sudo
vim-enhanced
nano
git
curl
wget
rsync
tar
unzip
gzip
bzip2
btop
fastfetch
bash-completion
flatpak

# Python et Qt
python3
python3-pip
qt5-qtbase

# === Écosystème Arrera (depuis Copr) ===
chafa
ImageMagick
plymouth
plymouth-plugin-script
arrera-branding
arrera-wallpapers
arrera-gnome-config
arrera-gnome-control-center
gnome-shell-extension-arrera-dock

# Audio, vidéo et réseau
pipewire
pipewire-pulseaudio
wireplumber
NetworkManager-wifi
firewalld

# Polices
google-noto-sans-fonts
google-noto-sans-mono-fonts
dejavu-sans-fonts

# === Installateur Calamares et configuration Arrera (Kiosque) ===
calamares
arrera-installer
cage
squashfs-tools
qt6-qtdeclarative
qt6-qtquickcontrols2

%end

# --------------------------------------------------------------------------
# Configuration après installation
# --------------------------------------------------------------------------

%post --log=/root/arrera-post-install.log
set -eux

echo "=========================================="
echo " DÉBUT DE LA CONFIGURATION ARRERA LINUX  "
echo "=========================================="

# Configuration sudo
echo "arrera ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/arrera
chmod 0440 /etc/sudoers.d/arrera

# Activation des services pour le média Live (Kiosque Calamares direct sans GNOME)
systemctl enable NetworkManager
systemctl enable firewalld
systemctl enable arrera-kiosk.service
systemctl disable gdm || true

# Cible par défaut pour le Kiosque
systemctl set-default multi-user.target

# Configuration Plymouth par défaut (thème Arrera)
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/plymouth.conf << 'DRACUT_LIVE_EOF'
add_dracutmodules+=" plymouth "
DRACUT_LIVE_EOF

mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf << 'PLYMOUTH_LIVE_EOF'
[Daemon]
Theme=arrera
ShowDelay=0
DeviceTimeout=8
PLYMOUTH_LIVE_EOF

ln -sf /usr/share/plymouth/themes/arrera/arrera.plymouth /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true

# Sauvegarde des fichiers EFI dans le système pour Calamares
mkdir -p /usr/share/arrera-efi
cp -a /boot/efi/EFI /usr/share/arrera-efi/ 2>/dev/null || true

# ================================================================
# Configuration du dépôt Copr Arrera avec clé GPG officielle
# ================================================================
mkdir -p /etc/yum.repos.d
cat > /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:arrera-software:arrera-blue.repo <<'COPR_REPO_EOF'
[copr:copr.fedorainfracloud.org:arrera-software:arrera-blue]
name=Copr repo for arrera-blue owned by arrera-software
baseurl=https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/fedora-$releasever-$basearch/
type=rpm-md
skip_if_unavailable=True
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/pubkey.gpg
repo_gpgcheck=0
enabled=1
enabled_metadata=1
cost=100
COPR_REPO_EOF

# Importer la clé publique GPG officielle du Copr Arrera
rpm --import https://download.copr.fedorainfracloud.org/results/arrera-software/arrera-blue/pubkey.gpg 2>/dev/null || true

# ================================================================
# Configuration de la session Live (auto-login + installateur)
# ================================================================

# Règles Polkit pour la session Live
mkdir -p /etc/polkit-1/rules.d/

cat > /etc/polkit-1/rules.d/49-liveuser.rules <<'POLKIT_LIVE_EOF'
polkit.addAdminRule(function(action, subject) {
    return ["unix-group:wheel"];
});
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
POLKIT_LIVE_EOF

cat > /etc/polkit-1/rules.d/50-calamares.rules <<'POLKIT_CALAMARES_EOF'
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("com.github.calamares") === 0 ||
        action.id.indexOf("io.calamares") === 0 ||
        action.id.indexOf("org.freedesktop.policykit.exec") === 0 ||
        action.id.indexOf("org.freedesktop.udisks2") === 0) {
        return polkit.Result.YES;
    }
});
POLKIT_CALAMARES_EOF

# ================================================================
# Applications Flatpak (Saveurs bureau : Home / School)
# ================================================================
if command -v flatpak &>/dev/null; then
    echo "Configuration de Flathub et installation des Flatpaks..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    flatpak install -y --noninteractive flathub \
        it.mijorus.gearlever \
        io.missioncenter.MissionCenter \
        io.github.flattool.Warehouse \
        com.github.tchx84.Flatseal 2>/dev/null || true
fi

# S'assurer qu'aucun autologin GDM résiduel n'est configuré
rm -f /etc/gdm/custom.conf

# ================================================================
# Configuration Calamares pour finaliser le système installé
# (Rend l'installation Calamares 100% identique à Anaconda)
# ================================================================

# 1. Écriture du script de finalisation du système installé
cat > /usr/bin/arrera-postinstall.sh << 'POSTINSTALL_EOF'
#!/bin/bash
# ==============================================================================
# Arrera Linux - Finalisation post-installation Calamares (chroot cible)
# Aligne le système installé sur la configuration officielle Arrera (identique Anaconda)
# ==============================================================================
# set -e désactivé : les erreurs mineures ne doivent pas faire échouer Calamares
set +e

echo "=========================================================="
echo "   Arrera Linux - Finalisation post-installation"
echo "=========================================================="

# 1. Vérification réseau et mise à jour DNF (Option A - compatible VirtualBox NAT & QEMU)
echo "[1/8] Test de la connectivité Internet..."

# Sauvegarder la cible du lien symbolique resolv.conf (souvent systemd-resolved)
RESOLV_IS_LINK=0
RESOLV_TARGET=""
if [ -L /etc/resolv.conf ]; then
    RESOLV_IS_LINK=1
    RESOLV_TARGET=$(readlink /etc/resolv.conf 2>/dev/null || true)
fi

# Supprimer le lien symbolique (souvent brisé dans le chroot) avant d'écrire un fichier régulier
rm -f /etc/resolv.conf 2>/dev/null || true
cat > /etc/resolv.conf << 'DNS_EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
DNS_EOF

IS_ONLINE=0
if curl -s --connect-timeout 4 -m 6 https://fedoraproject.org >/dev/null 2>&1 || \
   curl -s --connect-timeout 4 -m 6 https://google.com >/dev/null 2>&1 || \
   curl -s --connect-timeout 3 -m 5 http://1.1.1.1 >/dev/null 2>&1 || \
   ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    IS_ONLINE=1
fi

if [ "$IS_ONLINE" -eq 1 ]; then
    echo "-> Connexion Internet confirmée !"
    echo "-> Rafraîchissement des dépôts et mise à jour des paquets Arrera..."
    dnf makecache -y || true
    dnf upgrade -y --refresh || true
    echo "-> Système mis à jour avec succès."
else
    echo "-> Aucune connexion Internet détectée (ou mode hors-ligne)."
    echo "-> Étape réseau ignorée : installation locale directe."
fi

# Restauration propre du lien symbolique resolv.conf pour systemd-resolved
rm -f /etc/resolv.conf 2>/dev/null || true
if [ "$RESOLV_IS_LINK" -eq 1 ] && [ -n "$RESOLV_TARGET" ]; then
    ln -sf "$RESOLV_TARGET" /etc/resolv.conf 2>/dev/null || true
else
    ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || true
fi

# 2. Nettoyage et configuration de systemd-boot
echo "[2/8] Configuration de systemd-boot et enregistrement des noyaux..."

CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || true)

# Nettoyer les fichiers rescue obsolètes issus de l'ISO Live
if [ -n "$CURRENT_MACHINE_ID" ]; then
    for f in /boot/*rescue*; do
        [ -f "$f" ] || continue
        if ! grep -q "$CURRENT_MACHINE_ID" <<< "$f"; then
            echo "-> Suppression rescue obsolète du Live : $(basename "$f")"
            rm -f "$f"
        fi
    done
fi
rm -f /boot/loader/entries/*rescue*.conf 2>/dev/null || true

# Restaurer os-release Arrera si la mise à jour fedora-release l'a écrasé
if [ -f /usr/share/arrera-branding/os-release ]; then
    cp -f /usr/share/arrera-branding/os-release /usr/lib/os-release 2>/dev/null || true
    cp -f /usr/share/arrera-branding/os-release /etc/os-release 2>/dev/null || true
fi

# Identifier le dernier noyau installé
LATEST_KERNEL=$(ls -v /usr/lib/modules/*/vmlinuz /boot/vmlinuz-* 2>/dev/null | grep -v 'rescue' | tail -n 1 || true)
[ -n "$LATEST_KERNEL" ] && echo "-> Dernier noyau détecté : $LATEST_KERNEL"

# Ligne de commande silencieuse officielle Arrera
SILENT_CMDLINE="rhgb quiet splash loglevel=3 rd.udev.log_priority=3 systemd.show_status=false vt.global_cursor_default=0"

# Détermination de l'UUID de la racine
TARGET_ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || df / 2>/dev/null | tail -1 | awk '{print $1}')
TARGET_ROOT_UUID=$(blkid -s UUID -o value "$TARGET_ROOT_DEV" 2>/dev/null || true)

if [ -z "$TARGET_ROOT_UUID" ] && [ -f /etc/fstab ]; then
    TARGET_ROOT_UUID=$(awk '$2 == "/" && $1 ~ /^UUID=/ {sub(/^UUID=/, "", $1); print $1}' /etc/fstab | head -n 1)
fi

ROOT_PARAM="root=UUID=${TARGET_ROOT_UUID}"
echo "-> Racine cible : $TARGET_ROOT_DEV (UUID: $TARGET_ROOT_UUID)"

# 1. Sauvegarde de la ligne de commande officielle du noyau (/etc/kernel/cmdline)
mkdir -p /etc/kernel
echo "${ROOT_PARAM} ro ${SILENT_CMDLINE}" > /etc/kernel/cmdline
echo "-> Fichier /etc/kernel/cmdline configuré : $(cat /etc/kernel/cmdline)"

# 2. Configuration de kernel-install pour utiliser la disposition BLS
mkdir -p /etc/kernel
cat > /etc/kernel/install.conf << 'EOF'
layout=bls
initrd_generator=dracut
EOF

# 3. Identifier la partition ESP (généralement montée sur /boot ou /boot/efi)
ESP_PATH="/boot"
if [ ! -d "$ESP_PATH/loader" ] && [ -d "/boot/efi/EFI" ]; then
    ESP_PATH="/boot/efi"
fi

if ! mountpoint -q "$ESP_PATH" 2>/dev/null; then
    if grep -q "$ESP_PATH" /etc/fstab 2>/dev/null; then
        mount "$ESP_PATH" 2>/dev/null || true
    fi
fi

# 4. Installation des binaires systemd-boot dans l'ESP
echo "-> Installation de systemd-boot via bootctl (chemin: $ESP_PATH)..."
bootctl --path="$ESP_PATH" --no-variables install 2>/dev/null || bootctl --path="$ESP_PATH" install 2>/dev/null || true

# 5. Configuration générale du chargeur (/loader/loader.conf)
mkdir -p "$ESP_PATH/loader"
cat > "$ESP_PATH/loader/loader.conf" << 'EOF'
default @saved
timeout 0
console-mode keep
editor no
auto-entries 1
auto-firmware 1
EOF

# Nettoyer les entrées BLS fantômes du média Live si présentes
if [ -n "$CURRENT_MACHINE_ID" ] && [ -d "$ESP_PATH/loader/entries" ]; then
    for conf in "$ESP_PATH"/loader/entries/*.conf; do
        [ -f "$conf" ] || continue
        if ! grep -q "$CURRENT_MACHINE_ID" <<< "$(basename "$conf")"; then
            echo "-> Suppression entrée BLS obsolète du Live : $(basename "$conf")"
            rm -f "$conf"
        fi
    done
fi

# 6. Installation des entrées de noyau via kernel-install pour tous les noyaux installés
for kimg in /usr/lib/modules/*/vmlinuz /boot/vmlinuz-*; do
    [ -f "$kimg" ] || continue
    case "$kimg" in
        *rescue*) continue ;;
    esac
    KVER=""
    if [[ "$kimg" =~ /usr/lib/modules/([^/]+)/vmlinuz ]]; then
        KVER="${BASH_REMATCH[1]}"
    elif [[ "$kimg" =~ /boot/vmlinuz-(.+) ]]; then
        KVER="${BASH_REMATCH[1]}"
    fi
    [ -n "$KVER" ] || continue
    echo "-> Génération de l'entrée systemd-boot pour le noyau $KVER..."
    kernel-install add "$KVER" "$kimg" 2>/dev/null || true
done

# Personnaliser le titre dans les entrées BLS générées pour afficher "Arrera Blue 2026"
if [ -d "$ESP_PATH/loader/entries" ]; then
    for entry in "$ESP_PATH"/loader/entries/*.conf; do
        [ -f "$entry" ] || continue
        sed -i 's/^title Fedora.*/title Arrera Blue 2026/g' "$entry" 2>/dev/null || true
        sed -i 's/^title Arrera.*/title Arrera Blue 2026/g' "$entry" 2>/dev/null || true
    done
fi

# 7. Copie du fallback universel EFI (/EFI/BOOT/BOOT*.EFI) pour compatibilité firmware VM (UTM, QEMU)
TARGET_ARCH=$(uname -m)
case "$TARGET_ARCH" in
    aarch64|arm64)
        BOOT_FALLBACK="BOOTAA64.EFI"
        SDBOOT_NAME="systemd-bootaa64.efi"
        ;;
    x86_64|amd64|*)
        BOOT_FALLBACK="BOOTX64.EFI"
        SDBOOT_NAME="systemd-bootx64.efi"
        ;;
esac

mkdir -p "$ESP_PATH/EFI/BOOT"
SDBOOT_SRC="/usr/lib/systemd/boot/efi/$SDBOOT_NAME"
if [ -f "$SDBOOT_SRC" ]; then
    cp -f "$SDBOOT_SRC" "$ESP_PATH/EFI/BOOT/$BOOT_FALLBACK" 2>/dev/null || true
elif [ -f "$ESP_PATH/EFI/systemd/$SDBOOT_NAME" ]; then
    cp -f "$ESP_PATH/EFI/systemd/$SDBOOT_NAME" "$ESP_PATH/EFI/BOOT/$BOOT_FALLBACK" 2>/dev/null || true
elif [ -f "$ESP_PATH/EFI/systemd/"systemd-boot*.efi ]; then
    cp -f "$ESP_PATH/EFI/systemd/"systemd-boot*.efi "$ESP_PATH/EFI/BOOT/$BOOT_FALLBACK" 2>/dev/null || true
fi

# 8. Enregistrement propre dans la NVRAM UEFI
if [ -d /sys/firmware/efi ] && ! mountpoint -q /sys/firmware/efi/efivars; then
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || true
fi

if [ -d /sys/firmware/efi/efivars ] && command -v efibootmgr >/dev/null 2>&1; then
    ESP_DEV=$(findmnt -n -o SOURCE "$ESP_PATH" 2>/dev/null || true)
    if [ -n "$ESP_DEV" ]; then
        ESP_DISK=""
        ESP_PART=""
        if command -v lsblk >/dev/null 2>&1; then
            PK=$(lsblk -no PKNAME "$ESP_DEV" 2>/dev/null || true)
            [ -n "$PK" ] && ESP_DISK="/dev/$PK"
            ESP_PART=$(lsblk -no PARTN "$ESP_DEV" 2>/dev/null || true)
        fi
        if [ -z "$ESP_DISK" ] || [ -z "$ESP_PART" ]; then
            if [[ "$ESP_DEV" =~ ^(/dev/[a-zA-Z]+)([0-9]+)$ ]]; then
                ESP_DISK="${BASH_REMATCH[1]}"
                ESP_PART="${BASH_REMATCH[2]}"
            elif [[ "$ESP_DEV" =~ ^(/dev/[a-zA-Z0-9]+)p([0-9]+)$ ]]; then
                ESP_DISK="${BASH_REMATCH[1]}"
                ESP_PART="${BASH_REMATCH[2]}"
            fi
        fi

        if [ -n "$ESP_DISK" ] && [ -n "$ESP_PART" ]; then
            echo "-> Enregistrement UEFI NVRAM Arrera ($ESP_DISK partition $ESP_PART)..."
            for bnum in $(efibootmgr 2>/dev/null | grep -iE "Arrera|systemd-boot|fedora" | awk '{print $1}' | tr -d 'Boot*' | tr -d ':'); do
                efibootmgr -b "$bnum" -B 2>/dev/null || true
            done
            efibootmgr -c -d "$ESP_DISK" -p "$ESP_PART" -w -L "Arrera Blue 2026" -l "\\EFI\\systemd\\$SDBOOT_NAME" 2>/dev/null || true
        fi
    fi
fi
sync

# 3. Configuration et régénération du thème Plymouth Arrera
echo "[3/8] Application du thème de démarrage Plymouth Arrera..."
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/plymouth.conf << 'DRACUT_EOF'
add_dracutmodules+=" plymouth "
DRACUT_EOF

mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf << 'PLYMOUTH_EOF'
[Daemon]
Theme=arrera
ShowDelay=0
DeviceTimeout=8
PLYMOUTH_EOF

if [ -d /usr/share/plymouth/themes/arrera ]; then
    ln -sf /usr/share/plymouth/themes/arrera/arrera.plymouth /usr/share/plymouth/themes/default.plymouth 2>/dev/null || true
fi

if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    plymouth-set-default-theme arrera 2>/dev/null || true
fi

# Reconstruire explicitement l'initramfs pour TOUS les noyaux avec Plymouth et le thème Arrera
if command -v dracut >/dev/null 2>&1; then
    echo "-> Régénération complète de l'initramfs avec Dracut et le thème Arrera..."
    dracut --regenerate-all --force --add plymouth 2>/dev/null || {
        if [ -n "$LATEST_KERNEL" ]; then
            KVER=$(basename "$LATEST_KERNEL" | sed 's/vmlinuz-//')
            dracut -f --add plymouth "/boot/initramfs-${KVER}.img" "$KVER" 2>/dev/null || true
        fi
    }
fi

# 4. Forcer la cible graphique (GDM / GNOME)
echo "[4/8] Configuration du démarrage graphique (GDM)..."
systemctl set-default graphical.target 2>/dev/null || ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target
systemctl enable gdm 2>/dev/null || ln -sf /usr/lib/systemd/system/gdm.service /etc/systemd/system/display-manager.service

# 5. Désactiver et supprimer définitivement le mode kiosque
echo "[5/8] Nettoyage des composants Kiosque Live..."
systemctl disable arrera-kiosk.service 2>/dev/null || true
rm -f /etc/systemd/system/arrera-kiosk.service
rm -f /etc/systemd/system/multi-user.target.wants/arrera-kiosk.service
rm -f /usr/bin/arrera-installer-kiosk.sh

# 6. Supprimer tout autologin GDM résiduel
echo "[6/8] Réinitialisation de la configuration de connexion GDM..."
rm -f /etc/gdm/custom.conf

# 7. Nettoyer le compte Live temporaire 'arrera' si un utilisateur a été créé
echo "[7/8] Vérification des comptes utilisateurs..."
OTHER_USER=$(awk -F: '$3 >= 1000 && $1 != "arrera" && $1 != "nobody" {print $1}' /etc/passwd | head -n 1)
if [ -n "$OTHER_USER" ]; then
    echo "-> Utilisateur principal installé détecté : $OTHER_USER"
    echo "-> Suppression du compte temporaire live 'arrera'..."
    pkill -9 -u arrera 2>/dev/null || true
    userdel -r -f arrera 2>/dev/null || true
    rm -rf /home/arrera
    rm -f /etc/sudoers.d/arrera
fi

# 8. Nettoyage des raccourcis et mise à jour des caches d'environnement
echo "[8/8] Application des réglages d'environnement Arrera..."
rm -f /home/*/Bureau/install-*.desktop /home/*/Desktop/install-*.desktop 2>/dev/null || true
rm -f /home/*/.config/autostart/install-*.desktop 2>/dev/null || true
rm -f /etc/xdg/autostart/install-*.desktop 2>/dev/null || true
rm -f /usr/share/applications/calamares*.desktop 2>/dev/null || true

if command -v dconf >/dev/null 2>&1; then
    dconf update 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
fi

# Auto-nettoyage du script
rm -f /usr/bin/arrera-postinstall.sh 2>/dev/null || true

echo "=========================================================="
echo "   Système Arrera installé avec succès et prêt !"
echo "=========================================================="
sync
exit 0
POSTINSTALL_EOF

chmod +x /usr/bin/arrera-postinstall.sh

# 2. Écriture de la configuration du module shellprocess Calamares (sans variable bash inline)
mkdir -p /etc/calamares/modules
cat > /etc/calamares/modules/shellprocess-postinstall.conf << 'CALAMARES_POSTINSTALL_CONF'
# Configuration du module shellprocess-postinstall pour Arrera Linux
# Finalise le système installé en chroot (graphical.target, GDM, nettoyage)
---
dontChroot: false
timeout: 600

script:
    - command: "/usr/bin/arrera-postinstall.sh"
      timeout: 600
CALAMARES_POSTINSTALL_CONF

# Écriture de bootloader.conf Calamares (systemd-boot natif)
cat > /etc/calamares/modules/bootloader.conf << 'CALAMARES_BOOTLOADER_CONF'
# Configuration du module bootloader pour Arrera Linux
# Backend : systemd-boot (UEFI natif pour x86_64 et aarch64)
---
efiBootLoader: "systemd-boot"
kernelSearchPath: "/usr/lib/modules"
kernelPattern: "^vmlinuz.*"
loaderEntries:
  - "timeout 0"
  - "console-mode keep"
  - "editor no"
kernelParams: [ "rhgb", "quiet", "splash", "loglevel=3", "rd.udev.log_priority=3", "systemd.show_status=false", "vt.global_cursor_default=0" ]
bootloaderEntryName: "Arrera Blue 2026"
CALAMARES_BOOTLOADER_CONF

# Écriture de partition.conf Calamares (ESP 1 Go sur /boot pour systemd-boot)
cat > /etc/calamares/modules/partition.conf << 'CALAMARES_PARTITION_CONF'
# Configuration du module partition pour Arrera Linux
---
defaultFileSystemType: "ext4"
availableFileSystemTypes: ["ext4", "btrfs", "xfs"]
createHybridBootloaderLayout: false
defaultPartitionTableType: "gpt"
efiSystemPartition: "/boot"
efiSystemPartitionSize: 1024M
essentialMounts: [ "live-*", "control", "ventoy" ]
lvm:
    enable: false
CALAMARES_PARTITION_CONF

# 3. Écriture de settings.conf pour Calamares (inclut shellprocess@postinstall dans exec:)
cat > /etc/calamares/settings.conf << 'CALAMARES_SETTINGS_CONF'
# Configuration file for Calamares - Arrera Linux
# Pipeline optimisé pour Fedora (x86_64 et aarch64)
---
modules-search:
  - local
  - /usr/lib64/calamares/modules
  - /usr/lib/calamares/modules
  - /usr/share/calamares/modules

instances:
  - id:       installmode
    module:   packagechooser
    config:   packagechooser-installmode.conf
  - id:       postinstall
    module:   shellprocess
    config:   shellprocess-postinstall.conf

sequence:
  - show:
      - welcome
      - locale
      - keyboard
      - partition
      - users
      - packagechooser@installmode
      - summary
  - exec:
      - partition
      - mount
      - unpackfs
      - machineid
      - fstab
      - locale
      - keyboard
      - localecfg
      - users
      - networkcfg
      - hwclock
      - services-systemd
      - bootloader
      - shellprocess@postinstall
      - umount
  - show:
      - finished

branding: arrera

prompt-install: true

dont-chroot: false

oem-setup: false

disable-cancel: false

disable-cancel-during-exec: true

hide-back-and-next-during-exec: true

quit-at-end: false
CALAMARES_SETTINGS_CONF

# 4. Service de secours au premier démarrage sur disque dur (Condition: pas en mode Live)
cat > /etc/systemd/system/arrera-postinstall-fallback.service << 'FALLBACK_SERVICE_EOF'
[Unit]
Description=Arrera Linux First Boot Finalizer
DefaultDependencies=no
After=local-fs.target
Before=gdm.service display-manager.service
ConditionKernelCommandLine=!rd.live.image
ConditionPathExists=!/run/initramfs/live

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "systemctl set-default graphical.target 2>/dev/null || ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target; systemctl enable gdm 2>/dev/null || true; systemctl disable arrera-kiosk.service 2>/dev/null || true; rm -f /etc/gdm/custom.conf; systemctl disable arrera-postinstall-fallback.service 2>/dev/null || true; rm -f /etc/systemd/system/arrera-postinstall-fallback.service"

[Install]
WantedBy=multi-user.target graphical.target
FALLBACK_SERVICE_EOF

systemctl enable arrera-postinstall-fallback.service 2>/dev/null || true

echo "=========================================="
echo " FIN DE LA CONFIGURATION ARRERA LINUX    "
echo "=========================================="

%end