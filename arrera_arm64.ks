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
zerombr
clearpart --all --initlabel
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

# Noyau et démarrage ARM64 (aarch64 UEFI)
kernel
dracut-live
grub2-efi-aa64
grub2-efi-aa64-cdboot
grub2-efi-aa64-modules
shim-aa64
grub2-tools
grub2-tools-extra
grubby
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
set -e

echo "=========================================================="
echo "   Arrera Linux - Finalisation post-installation"
echo "=========================================================="

# 1. Vérification réseau et mise à jour DNF (Option A - compatible VirtualBox NAT & QEMU)
echo "[1/8] Test de la connectivité Internet..."
cp -f /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
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

if [ -f /etc/resolv.conf.bak ]; then
    mv -f /etc/resolv.conf.bak /etc/resolv.conf 2>/dev/null || true
fi

# 2. Nettoyage des noyaux Live et configuration complète de GRUB
echo "[2/8] Nettoyage des anciens noyaux et configuration de GRUB..."

CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || true)

if [ -n "$CURRENT_MACHINE_ID" ] && [ -d /boot/loader/entries ]; then
    for conf in /boot/loader/entries/*.conf; do
        [ -f "$conf" ] || continue
        if ! grep -q "$CURRENT_MACHINE_ID" <<< "$(basename "$conf")"; then
            echo "-> Suppression entrée BLS obsolète du Live : $(basename "$conf")"
            rm -f "$conf"
        fi
    done
fi

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

if [ -f /usr/share/arrera-branding/os-release ]; then
    cp -f /usr/share/arrera-branding/os-release /usr/lib/os-release 2>/dev/null || true
    cp -f /usr/share/arrera-branding/os-release /etc/os-release 2>/dev/null || true
fi

LATEST_KERNEL=$(ls -v /boot/vmlinuz-* 2>/dev/null | grep -v 'rescue' | tail -n 1)
if [ -n "$LATEST_KERNEL" ]; then
    echo "-> Noyau officiel sélectionné par défaut : $LATEST_KERNEL"
    if command -v grubby >/dev/null 2>&1; then
        grubby --set-default="$LATEST_KERNEL" 2>/dev/null || true
    fi
fi

# Configuration des paramètres silencieux et Plymouth pour toutes les entrées BLS
SILENT_CMDLINE="rhgb quiet splash loglevel=3 rd.udev.log_priority=3 systemd.show_status=false vt.global_cursor_default=0"

if [ -d /boot/loader/entries ]; then
    for entry in /boot/loader/entries/*.conf; do
        [ -f "$entry" ] || continue
        # Nettoyer les anciens arguments et rd.live.image
        sed -i -E 's/\s+rd\.live\.image//g' "$entry"
        sed -i -E 's/\s+(rhgb|quiet|splash|loglevel=[0-9]+|rd\.udev\.log_priority=[0-9]+|systemd\.show_status=\w+|vt\.global_cursor_default=[0-9]+)//g' "$entry"
        sed -i "/^options / s/$/ ${SILENT_CMDLINE}/" "$entry"
        sed -i 's/^title Fedora.*/title Arrera Blue-dev 2026/g' "$entry" 2>/dev/null || true
        sed -i 's/^title Arrera.*/title Arrera Blue-dev 2026/g' "$entry" 2>/dev/null || true
    done
fi

if command -v grubby >/dev/null 2>&1; then
    grubby --update-kernel=ALL --remove-args="rd.live.image" 2>/dev/null || true
    grubby --update-kernel=ALL --args="${SILENT_CMDLINE}" 2>/dev/null || true
fi

# Sauvegarder la ligne de commande par défaut pour les futures mises à jour de noyau (/etc/kernel/cmdline)
ROOT_ARG=$(grep -o 'root=[^ ]*' /boot/loader/entries/*.conf 2>/dev/null | head -n 1 || true)
if [ -n "$ROOT_ARG" ]; then
    mkdir -p /etc/kernel
    echo "${ROOT_ARG} ro ${SILENT_CMDLINE}" > /etc/kernel/cmdline
fi

# Configuration stricte de /etc/default/grub pour masquer totalement le menu
mkdir -p /etc/default
cat > /etc/default/grub << 'GRUB_EOF'
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_RECORDFAIL_TIMEOUT=0
GRUB_DISTRIBUTOR="Arrera Blue-dev 2026"
GRUB_DEFAULT=0
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="rhgb quiet splash loglevel=3 rd.udev.log_priority=3 systemd.show_status=false vt.global_cursor_default=0"
GRUB_DISABLE_RECOVERY=true
GRUB_EOF

# Marquer l'environnement GRUB comme démarré avec succès pour éviter que menu_auto_hide ne force l'affichage
if command -v grub2-editenv >/dev/null 2>&1; then
    for envfile in /boot/grub2/grubenv /boot/efi/EFI/fedora/grubenv; do
        if [ -f "$envfile" ] || [ -d "$(dirname "$envfile")" ]; then
            grub2-editenv "$envfile" set menu_auto_hide=1 2>/dev/null || true
            grub2-editenv "$envfile" set boot_success=1 2>/dev/null || true
            grub2-editenv "$envfile" set boot_indeterminate=0 2>/dev/null || true
            grub2-editenv "$envfile" set saved_entry=0 2>/dev/null || true
        fi
    done
fi

# Régénération de la configuration GRUB
if command -v grub2-mkconfig >/dev/null 2>&1; then
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
    if [ -d /boot/efi/EFI/fedora ]; then
        grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null || true
    fi
fi

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

# Écriture de bootloader.conf Calamares (timeout 0 pour masquer GRUB, splash pour Plymouth)
cat > /etc/calamares/modules/bootloader.conf << 'CALAMARES_BOOTLOADER_CONF'
# Configuration du module bootloader pour Arrera Linux
---
efiBootLoader: "sb-shim"
kernelSearchPath: "/usr/lib/modules"
kernelPattern: "^vmlinuz.*"
loaderEntries:
  - "timeout 0"
  - "console-mode keep"
kernelParams: [ "rhgb", "quiet", "splash", "loglevel=3", "rd.udev.log_priority=3", "systemd.show_status=false", "vt.global_cursor_default=0" ]
grubInstall: "grub2-install"
grubMkconfig: "grub2-mkconfig"
grubCfg: "/boot/grub2/grub.cfg"
grubProbe: "grub2-probe"
efiBootMgr: "efibootmgr"
efiBootloaderId: "fedora"
installEFIFallback: true
CALAMARES_BOOTLOADER_CONF

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
